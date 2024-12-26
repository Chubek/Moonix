module moonix.stackvm;

import std.stdio, std.range, std.typecons, std.algorithm, std.container,
    std.string, std.concurrency, std.process, std.variant, core.memory,
    core.attribute, core.sync.barrier, core.sync.condition;

enum MAX_CONST = 256;
enum MAX_DATA = 65536;
enum MAX_CALL = 8096;
enum MAX_CODE = 16384;

alias DataStack = TValue[MAX_DATA];
alias CallStack = CallFrame[MAX_CALL];
alias CodeStack = Code[MAX_CODE];
alias ConstantPool = TValue[MAX_CONST];
alias Address = long;
alias Index = ubyte;
alias TableEntries = SList!Entry;

class Table
{
    TableEntries entries;
    size_t capacity;
    size_t count;

    this(size_t capacity)
    {
        this.capacity = capacity;
        this.count = 0;
    }

    void insertEntry(TValue key, TValue value)
    {
        if (this.count >= this.capacity)
            throw new StackVMError("Table size superceeds capacity", this.count);
        this.entries.insertFront(Entry(key, value));
        this.count++;
    }

    Nullable!Entry getEntry(TValue key)
    {
        Nullable!Entry found;
        foreach (entry; this.entries.opSlice())
        {
            if (entry.key == key)
            {
                found = entry;
                break;
            }
        }
        return found;
    }

    void iter(F)(F fn)
    {
        foreach (entry; this.entries.opSlice())
            fn(entry);
    }

    Entry[] map(F)(F fn)
    {
        Entry[] acc = null;
        foreach (entry; this.entries.opSlice())
            acc ~= fn(entry);
        return acc;
    }

    Entry[] fold(F)(F fn, Entry[] init)
    {
        foreach (entry; this.entries.opSlice())
            init ~= fn(entry);
        return init;
    }

    Entry[] filter(F)(F cond)
    {
        Entry[] filtered = null;
        foreach (entry; this.entries.opSlice())
            if (cond(entry))
                filtered ~= entry;
        return filtered;
    }

    void concat(Entry[] elts)
    {
        foreach (elt; elts)
            this.entries.insertFront(elt);
    }

    Entry head()
    {
        return this.entries.front();
    }

    Entry[] tail()
    {
        Entry[] tail = null;
        foreach (entry; this.entries.opSlice())
            tail ~= entry;
        return tail[1 .. $];
    }
}

struct Entry
{
    TValue key;
    TValue value;

    this(TValue key, TValue value)
    {
        this.key = key;
        this.value = value;
    }

    bool opEquals(const Entry rhs) const
    {
        return this.key == rhs.key && this.value == rhs.value;
    }
}

struct Closure
{
    Address program_counter;
    CallFrame frame;
    private ConstantPool constants;

    this(Address program_counter, CallFrame frame)
    {
        this.program_counter = program_counter;
        this.frame = frame;
        this.constants = null;
    }

    TValue getConstant(Index index)
    {
        if (index >= CONST_MAX)
            throw new StackVMError("Constant index too high", index);
        return this.constants[index];
    }

    void setConstant(Index index, TValue value)
    {
        if (index >= CONST_MAX)
            throw new StackVMError("Constant index too high", index);
        this.constants[index] = value;
    }

    bool opEquals(const Closure rhs) const
    {
        return this.code == rhs.code && this.frame == rhs.frame;
    }
}

enum Instruction
{
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Pow,
    Shr,
    Shl,
    Neg,
    Eq,
    Ne,
    Gt,
    Ge,
    Lt,
    Le,
    Conj,
    Disj,
    Not,
    BitAnd,
    BitNot,
    BitXor,
    BitOr,
    CatString,
    LoadNil,
    LoadBoolean,
    LoadString,
    LoadNumber,
    LoadAddress,
    LoadTable,
    LoadIndex,
    StoreNil,
    StoreBoolean,
    StoreString,
    StoreNumber,
    StoreAddress,
    StoreTable,
    StoreIndex,
    GetTableEntry,
    SetTableEntry,
    SetConstAtTopFrame,
    GetConstAtTopFrame,
    SetConstAtGlobals,
    GetConstAtGlobals,
    DuplicateTop,
    SwapTop,
    RotateTop3,
    RotateTop4,
    Jump,
    JumpIfTrue,
    JumpIfFalse,
    ReturnFromFunction,
    Varargs,
    MarkClosure,
    CallClosure,
    CallFunction,
    CallFunctionConcurrently,
}

struct Code
{
    enum CodeKind
    {
        Instruction,
        Value,
    }

    CodeKind kind;

    union
    {
        Instruction v_instruction;
        TValue v_value;
    }

    this(Instruction v_instruction)
    {
        this.kind = CodeKind.Instruction;
        this.v_instruction = v_instruction;
    }

    this(TValue v_value)
    {
        this.kind = CodeKind.Value;
        this.v_value = v_value;
    }

    static Code newInstruction(Instruction v_instruction)
    {
        return Code(v_instruction);
    }

    static Code newValue(TValue v_value)
    {
        return Code(v_value);
    }
}

class StackVMError : Exception
{
    string msg;
    Address address;

    this(string msg, Address address)
    {
        super(msg);
        this.address = address;
    }
}

struct TValue
{
    enum TValueKind
    {
        Nil,
        Boolean,
        String,
        Number,
        Address,
        Table,
        Index,
        Closure,
    }

    TValueKind kind;

    union
    {
        bool v_boolean;
        string v_string;
        real v_number;
        Address v_address;
        Table v_table;
        Index v_index;
        Closure v_closure;
    }

    this(TValueKind kind)
    {
        this.kind = kind;
    }

    this(bool v_boolean)
    {
        this.kind = TValueKind.Boolean;
        this.v_boolean = v_boolean;
    }

    this(string v_string)
    {
        this.kind = TValueKind.String;
        this.v_string = v_string;
    }

    this(real v_number)
    {
        this.kind = TValueKind.Number;
        this.v_number = v_number;
    }

    this(Address v_address)
    {
        this.kind = TValueKind.Address;
        this.v_address = v_address;
    }

    this(Table v_table)
    {
        this.kind = TValueKind.Table;
        this.v_table = v_table;
    }

    this(Index v_index)
    {
        this.kind = TValueKind.Index;
        this.v_index = v_index;
    }

    this(Closure v_closure)
    {
        this.kind = TValueKind.Closure;
        this.v_closure = v_closure;
    }

    static TValue newNil()
    {
        return TValue(TValueKind.Nil);
    }

    static TValue newBoolean(bool v_boolean)
    {
        return TValue(v_boolean);
    }

    static TValue newString(string v_string)
    {
        return TValue(v_string);
    }

    static TValue newNumber(real v_number)
    {
        return TValue(v_number);
    }

    static TValue newAddress(Address v_address)
    {
        return TValue(v_address);
    }

    static TValue newTable(Table v_table)
    {
        return TValue(v_table);
    }

    static TValue newIndex(Index v_index)
    {
        return TValue(v_index);
    }

    static TValue newClosure(Closure v_closure)
    {
        return TValue(v_closure);
    }

    bool opEquals(const TValue rhs) const
    {
        if (this.kind == rhs.kind)
        {
            switch (this.kind)
            {
            case TValueKind.Nil:
                return true;
            case TValueKind.Boolean:
                return this.v_boolean == rhs.v_boolean;
            case TValueKind.String:
                return this.v_string == rhs.v_string;
            case TValueKind.Number:
                return this.v_number == rhs.v_number;
            case TValueKind.Address:
                return this.v_address == rhs.v_address;
            case TValueKind.Table:
                return this.v_table == rhs.v_table;
            case TValueKind.Index:
                return this.v_index == rhs.v_index;
            case TValueKind.Closure:
                return this.v_closure == rhs.v_closure;
            default:
                return false;
            }
        }
        return false;
    }
}

struct CallFrame
{
    Address return_address;
    Address static_link;
    Index nargs, nlocals;
    private ConstantPool constants;

    this(Address return_address, Address static_link, Index nargs, Index nlocals)
    {
        this.return_address = return_address;
        this.static_link = static_link;
        this.nargs = nargs;
        this.nlocals = nlocals;
        this.constants = null;
    }

    void setConstant(Index index, TValue constant)
    {
        if (index >= MAX_CONST)
            throw new StackVMError("Constant index too high", this.return_address);
        this.constants[index] = constant;
    }

    TValue getConstant(Index index)
    {
        if (index >= MAX_CONST)
            throw new StackVMError("Constant index too high", this.return_address);
        return this.constants[index];
    }
}

class Interpreter
{
    DataStack data_stack;
    CallStack call_stack;
    CodeStack code_stack;
    private Address stack_pointer;
    private Address frame_pointer;
    private Address program_counter;
    private size_t code_size;
    private size_t call_size;
    private ConstantPool globals;

    this()
    {
        this.data_stack = null;
        this.call_stack = null;
        this.code_stack = null;
        this.stack_pointer = -1;
        this.frame_pointer = -1;
        this.program_counter = 0;
        this.code_size = -1;
        this.call_size = -1;
        this.globals = null;
    }

    void pushData(TValue value)
    {
        if (this.stack_pointer + 1 >= MAX_DATA)
            throw new StackVMError("Data stack overflow", this.stack_pointer);
        this.data_stack[++this.stack_pointer] = value;
    }

    void pushNil()
    {
        pushData(TValue.newNil());
    }

    bool popNil()
    {
        auto data = popData();
        if (data.kind != TValue.TValueKind.Nil)
            throw new StackVMError("Expected Nil value at TOS", this.stack_pointer);
        return true;
    }

    void pushBoolean(bool value)
    {
        pushData(TValue.newBoolean(value));
    }

    bool popBoolean()
    {
        auto data = popData();
        if (data.kind != TValue.TValueKind.Boolean)
            throw new StackVMError("Expected Boolean value at TOS", this.stack_pointer);
        return data.v_boolean;
    }

    void pushString(string value)
    {
        pushData(TValue.newString(value));
    }

    string popString()
    {
        auto data = popData();
        if (data.kind != TValue.TValueKind.Boolean)
            throw new StackVMError("Expected String value at TOS", this.stack_pointer);
        return data.v_string;
    }

    void pushNumber(real value)
    {
        pushData(TValue.newNumber(value));
    }

    real popNumber()
    {
        auto data = popData();
        if (data.kind != TValue.TValueKind.Number)
            throw new StackVMError("Expected Number value at TOS", this.stack_pointer);
        return data.v_number;
    }

    void pushAddress(Address value)
    {
        pushData(TValue.newAddress(value));
    }

    Address popAddress()
    {
        auto data = popData();
        if (data.kind != TValue.TValueKind.Address)
            throw new StackVMError("Expected Address value at TOS", this.stack_pointer);
        return data.v_address;
    }

    void pushTable(Table value)
    {
        pushData(TValue.newTable(value));
    }

    Table popTable()
    {
        auto data = popData();
        if (data.kind != TValue.TValueKind.Table)
            throw new StackVMError("Expected Table value at TOS", this.stack_pointer);
        return data.v_table;
    }

    void pushIndex(Index value)
    {
        pushData(TValue.newIndex(value));
    }

    Index popIndex()
    {
        auto data = popData();
        if (data.kind != TValue.TValueKind.Index)
            throw new StackVMError("Expected Index value at TOS", this.stack_pointer);
        return data.v_index;
    }

    void pushClosure(Closure value)
    {
        pushData(TValue.newClosure(value));
    }

    Closure popClosure()
    {
        auto data = popData();
        if (data.kind != TValue.TValueKind.Closure)
            throw new StackVMError("Expected Closure value at TOS", this.stack_pointer);
        return data.v_closure;
    }

    void swapTopOfDataStack()
    {
        if (this.stack_pointer < 2)
            throw new StackVMError("Not enough data for swap", this.stack_pointer);
        auto tmp = topData();
        this.data_stack[this.stack_pointer] = this.data_stack[this.stack_pointer - 1];
        this.data_stack[this.stack_pointer - 1] = tmp;
    }

    void duplicateTopOfDataStack()
    {
        if (this.stack_pointer <= 0)
            throw new StackVMError("Not enough data for duplicate", this.stack_pointer);
        auto top = topDate();
        pushDate(top);
    }

    void rotateTop3OfDataStack()
    {
        if (this.stack_pointer < 3)
            throw new StackVMError("Not enough data for Rot3", this.stack_pointer);
        auto tmp1 = topData();
        auto tmp2 = this.data_stack[this.stack_pointer - 1];
        auto tmp3 = this.data_stack[this.stack_pointer - 2];
        this.data_stack[this.stack_pointer] = tmp3;
        this.data_stack[this.stack_pointer - 1] = tmp2;
        this.data_stack[this.stack_pointer - 2] = tmp1;
    }

    void rotateTop4OfDataStack()
    {
        if (this.stack_pointer < 4)
            throw new StackVMError("Not enough data for Rot4", this.stack_pointer);
        auto tmp1 = topData();
        auto tmp2 = this.data_stack[this.stack_pointer - 1];
        auto tmp3 = this.data_stack[this.stack_pointer - 2];
        auto tmp4 = this.data_stack[this.stack_pointer - 3];
        this.data_stack[this.stack_pointer] = tmp4;
        this.data_stack[this.stack_pointer - 1] = tmp3;
        this.data_stack[this.stack_pointer - 2] = tmp2;
        this.data_stack[this.stack_pointer - 3] = tmp1;
    }

    TValue popData()
    {
        if (this.stack_pointer <= 0)
            throw new StackVMError("Data stack underflow", this.stack_pointer);
        return this.data_stack[this.stack_pointer--];
    }

    TValue topData()
    {
        return this.data_stack[this.stack_pointer];
    }

    TValue getArgument(Index index)
    {
        auto call_frame = topCallFrame();
        auto nargs = call_frame.nargs;
        return this.data_stack[this.frame_pointer + (nargs - index)];
    }

    TValue getLocal(Index index)
    {
        auto call_frame = topCallFrame();
        auto nlocals = call_frame.nlocals;
        auto nargs = call_frame.nargs;
        return this.data_stack[this.frame_pointer + ((nargs + nlocals) - index)];
    }

    TValue getConstantAtGlobals(Index index)
    {
        if (index >= MAX_CONST)
            throw new StackVMError("Global index too high", index);
        return this.globals[index];
    }

    void setConstantAtGlobals(Index index, TValue value)
    {
        if (index >= MAX_CONST)
            throw new StackVMError("Global index too high", index);
        this.globals[index] = value;
    }

    TValue getConstantAtTopFrame(Index index)
    {
        auto call_frame = getTopFrame();
        return call_frame.getConstant(index);
    }

    CallFrame getTopFrame() const
    {
        return this.call_stack[this.call_size];
    }

    CallFrame popCallFrame()
    {
        if (this.call_size <= 0)
            throw new StackVMError("Call stack underflow", this.call_size);
        return this.call_stack[this.call_size--];
    }

    void setConstantAtTopFrame(Index index, TValue value)
    {
        auto call_frame = getTopFrame();
        call_frame.setConstant(index, value);
    }

    void insertInstructionIntoCodeStack(Instruction value)
    {
        this.code_stack[++this.code_size] = Code.newInstruction(value);
    }

    void insertValueIntoCodeStack(TValue value)
    {
        this.code_stack[++this.code_size] = Code.newValue(value);
    }

    Instruction nextCodeInstruction()
    {
        if (this.code_size <= this.program_counter)
            throw new StackVMError("Code stack overflow", this.program_counter);
        auto code = this.code_stack[this.program_counter++];
        if (code.kind != Code.CodeKind.Instruction)
            throw new StackVMError("Expected instruction at PC", this.program_counter);
        return code.v_instruction;
    }

    TValue nextCodeValue()
    {
        if (this.code_size <= this.program_counter)
            throw new StackVMError("Code stack overflow", this.program_counter);
        auto code = this.code_stack[this.program_counter++];
        if (code.kind != Code.CodeKind.Value)
            throw new StackVMError("Expected value at PC", this.program_counter);
        return code.v_value;
    }

    bool codeRemains()
    {
        return this.program_counter < this.code_size;
    }

    void setupNewCallFrame(Index nargs, Index nlocals)
    {
        if (this.call_size >= MAX_CALL)
            throw new StackVMError("Call stack overflow", this.call_size);
        this.call_stack[++this.call_size] = CallFrame(this.stack_pointer + nargs + nlocals,
                this.frame_pointer, nargs, nlocals);
        this.frame_pointer = this.stack_pointer;
    }

    void popCallStackAndClear()
    {
        if (this.call_size <= 0)
            throw new StackVMError("Call stack underflow", this.call_size);
        auto call_frame = popCallFrame();
        auto return_address = call_frame.return_address;
        auto static_link = call_frame.static_link;
        auto nargs = call_frame.nargs;
        auto nlocals = call_frame.nlocals;
        this.stack_pointer = return_address - nargs - nlocals;
        this.frame_pointer = static_link;
    }

    void setProgramCounter(Address new_address)
    {
        this.program_counter = new_address;
    }

    Address getProgramCounter()
    {
        return this.program_counter;
    }

    void runVM()
    {
        while (codeRemains())
        {
            Instruction next_code = nextCodeInstruction();

            switch (next_code)
            {
            case Instruction.Add:
                auto rhs = popNumber();
                auto lhs = popNumber();
                pushNumber(lhs + rhs);
                continue;
            case Instruction.Sub:
                auto rhs = popNumber();
                auto lhs = popNumber();
                pushNumber(lhs - rhs);
                continue;
            case Instruction.Mul:
                auto rhs = popNumber();
                auto lhs = popNumber();
                pushNumber(lhs * rhs);
                continue;
            case Instruction.Div:
                auto rhs = popNumber();
                auto lhs = popNumber();
                pushNumber(lhs / rhs);
                continue;
            case Instruction.Mod:
                ulong rhs = cast(ulong) popNumber();
                ulong lhs = cast(ulong) popNumber();
                pushNumber(lhs % rhs);
                continue;
            case Instruction.Pow:
                auto rhs = popNumber();
                auto lhs = popNumber();
                pushNumber(lhs ^^ rhs);
                continue;
            case Instruction.Shr:
                ulong rhs = cast(ulong) popNumber();
                ulong lhs = cast(ulong) popNumber();
                pushNumber(lhs >> rhs);
                continue;
            case Instruction.Shl:
                ulong rhs = cast(ulong) popNumber();
                ulong lhs = cast(ulong) popNumber();
                pushNumber(lhs << rhs);
                continue;
            case Instruction.Neg:
                auto num = popNumber();
                pushNumber(-num);
                continue;
            case Instruction.Conj:
                auto rhs = popBoolean();
                auto lhs = popBoolean();
                pushBoolean(lhs && rhs);
                continue;
            case Instruction.Disj:
                auto rhs = popBoolean();
                auto lhs = popBoolean();
                pushBoolean(lhs || rhs);
                continue;
            case Instruction.Not:
                auto boolean = popBoolean();
                pushBoolean(!boolean);
                continue;
            case Instruction.BitAnd:
                ulong rhs = cast(ulong) popNumber();
                ulong lhs = cast(ulong) popNumber();
                pushNumber(lhs & rhs);
                continue;
            case Instruction.BitOr:
                ulong rhs = cast(ulong) popNumber();
                ulong lhs = cast(ulong) popNumber();
                pushNumber(lhs | rhs);
                continue;
            case Instruction.BitXor:
                ulong rhs = cast(ulong) popNumber();
                ulong lhs = cast(ulong) popNumber();
                pushNumber(lhs ^ rhs);
                continue;
            case Instruction.BitNot:
                ulong num = cast(ulong) popNumber();
                pushNumber(~num);
                continue;
            case Instruction.Gt:
                auto rhs = popNumber();
                auto lhs = popNumber();
                pushBoolean(lhs > rhs);
                continue;
            case Instruction.Ge:
                auto rhs = popNumber();
                auto lhs = popNumber();
                pushBoolean(lhs >= rhs);
                continue;
            case Instruction.Lt:
                auto rhs = popNumber();
                auto lhs = popNumber();
                pushBoolean(lhs < rhs);
                continue;
            case Instruction.Le:
                auto rhs = popNumber();
                auto lhs = popNumber();
                pushBoolean(lhs <= rhs);
                continue;
            case Instruction.Eq:
                auto rhs = popData();
                auto lhs = popData();
                pushBoolean(lhs == rhs);
                continue;
            case Instruction.Ne:
                auto rhs = popData();
                auto lhs = popData();
                pushBoolean(lhs != rhs);
                continue;
            case Instruction.CatString:
                auto rhs = popString();
                auto lhs = popString();
                pushString(lhs ~ rhs);
                continue;
            case Instruction.StoreNil:
                pushNil();
                continue;
            case Instruction.StoreBoolean:
                auto value = nextCodeValue();
                if (value.kind != TValue.TValueKind.Boolean)
                    throw StackVMError("Expected Boolean value at PC", this.program_counter);
                pushBoolean(value.v_boolean);
                continue;
            case Instruction.StoreString:
                auto value = nextCodeValue();
                if (value.kind != TValue.TValueKind.String)
                    throw StackVMError("Expected String value at PC", this.program_counter);
                pushString(value.v_string);
                continue;
            case Instruction.StoreNumber:
                auto value = nextCodeValue();
                if (value.kind != TValue.TValueKind.Number)
                    throw StackVMError("Expected Number value at PC", this.program_counter);
                pushString(value.v_string);
                continue;
            case Instruction.StoreAddress:
                auto value = nextCodeValue();
                if (value.kind != TValue.TValueKind.Address)
                    throw new StackVMError("Expected Address value at PC", this.program_counter);
                pushAddress(value.v_address);
                continue;
            case Instruction.StoreIndex:
                auto value = nextCodeValue();
                if (value.kind != TValue.TValueKind.Index)
                    throw new StackVMError("Expected Index value at PC", this.program_counter);
                pushIndex(value.v_index);
                continue;
            case Instruction.StoreTable:
                auto value = nextCodeValue();
                if (value.kind != TValue.TValueKind.Table)
                    throw new StackVMError("Expected Table value at PC", this.program_counter);
                pushTable(value.v_table);
                continue;
            case Instruction.StoreClosure:
                auto value = nextCodeValue();
                if (value.kind != TValue.TValueKind.Closure)
                    throw new StackVMError("Expected Closure value at PC", this.program_counter);
                pushClosure(value.v_closure);
                continue;

            }

        }
    }
}
