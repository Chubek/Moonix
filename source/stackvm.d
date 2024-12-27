module moonix.stackvm;

import std.stdio, std.math, std.range, std.typecons, std.algorithm,
    std.container, std.string, std.concurrency, std.process, std.variant,
    core.memory, core.attribute, core.sync.barrier, core.sync.condition;

enum MAX_CONST = 256;
enum DJB2_INIT = 5381;

alias OperandStack = Stack!TValue;
alias CallStack = Stack!CallFrame;
alias CodeStack = Stack!Code;
alias EnvironmentStack = Stack!Environment;
alias Environment = TValue[Identifier];
alias ConstantPool = TValue[MAX_CONST];
alias TableEntries = SList!Entry;
alias Address = long;
alias Index = ubyte;

class StackFlowError : Exception
{
    string msg;
    Address address;

    this(string msg, Address address)
    {
        super(msg);
        this.address = address;
    }
}

class StackVMError : Exception
{
    string msg;
    Address address;

    this(string msg, StackTrace trace)
    {
        super(msg);
        this.trace = trace;
    }
}

struct StackTrace
{
    string stack_name;
    Address operand_stack_pointer;
    Address call_stack_pointer;
    Address code_stack_pointer;
    Address frame_pointer;

    this(string stack_name, Address operand_stack_pointer,
            Address call_stack_pointer, Address code_stack_pointer, Address frame_pointer)
    {
        this.stack_name = stack_name;
        this.operand_stack_pointer = operand_stack_pointer;
        this.call_stack_pointer = call_stack_pointer;
        this.code_stack_pointer = code_stack_pointer;
        this.frame_pointer = frame_pointer;
    }
}

struct Stack(T)
{
    private SList!T container = null;
    private Address pointer = 0;
    private size_t length = 0;
    private string name = null;

    this(string name)
    {
        this.name = name;
    }

    void push(T value)
    {
        this.container.insertFront(value);
        this.pointer++;
        this.length++;
    }

    Nullable!T topSafe()
    {
        Nullable!T front;
        if (this.pointer > 0)
            front = this.container.front();
        return front;
    }

    T top()
    {
        auto front_nullable = topSafe();
        if (front_nullable.isNull)
            throw new StackFlowError("The " ~ this.name ~ " stack underflew", this.pointer);
        return front_nullable.get;
    }

    T pop()
    {
        auto front_nullable = topSafe();
        if (front_nullable.isNull)
            throw new StackFlowError("The " ~ this.name ~ " stack underflew", this.pointer);
        this.container.removeFront();
        this.pointer--;
        this.length--;
        return front_nullable.get;
    }

    Address getPointer()
    {
        return this.pointer;
    }

    void setPointer(Address pointer)
    {
        this.pointer = pointer;
    }

    Address getLength()
    {
        return this.length;
    }
}

struct Identifier
{
    private string value;

    this(string value)
    {
        this.value = value;
    }

    string getIDValue()
    {
        return this.value;
    }

    size_t toHash() const @safe nothrow
    {
        size_t hash = DJB2_INIT;
        foreach (chr; this.value)
            hash = ((hash << 5) + hash) + chr;
        return hash;
    }

    bool opEquals(const Identifier rhs) const
    {
        return getIDValue() == rhs.getIDValue();
    }
}

class Table
{
    TableEntries entries = null;
    size_t count = 0;

    void insertEntry(TValue key, TValue value)
    {
        this.entries.insertFront(Entry(key, value));
        this.count++;
    }

    bool setEntry(TValue key, TValue value)
    {
        foreach (ref entry; this.entries.opSlice())
        {
            if (entry.key == key)
            {
                entry.value = value;
                return true;
            }
        }
        return false;
    }

    bool hasEntry(TValue key)
    {
        foreach (entry; this.entries.opSlice())
            if (entry.key == key)
                return true;
        return false;
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
    StoreNil,
    StoreBoolean,
    StoreString,
    StoreNumber,
    StoreAddress,
    StoreTable,
    StoreIndex,
    InsertTableEntry,
    GetTableEntry,
    SetTableEntry,
    CheckTableEntry,
    SetConstantAtTopFrame,
    GetConstantAtTopFrame,
    SetConstantAtGlobals,
    GetConstantAtGlobals,
    GetArgument,
    GetLocal,
    StoreLocal,
    DuplicateTop,
    SwapTop,
    OverTop,
    RotateTop3,
    RotateTop4,
    Jump,
    JumpIfTrue,
    JumpIfFalse,
    Call,
    CallConcurrently,
    Return,
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

struct TValue
{
    enum Kind
    {
        Nil,
        Boolean,
        String,
        Number,
        Address,
        Table,
        Index,
        Identifier,
    }

    Kind kind;

    union
    {
        bool v_boolean;
        string v_string;
        real v_number;
        Address v_address;
        Table v_table;
        Index v_index;
        Identifier v_identifier;
    }

    this(Kind kind)
    {
        this.kind = kind;
    }

    this(bool v_boolean)
    {
        this.kind = Kind.Boolean;
        this.v_boolean = v_boolean;
    }

    this(string v_string)
    {
        this.kind = Kind.String;
        this.v_string = v_string;
    }

    this(real v_number)
    {
        this.kind = Kind.Number;
        this.v_number = v_number;
    }

    this(Address v_address)
    {
        this.kind = Kind.Address;
        this.v_address = v_address;
    }

    this(Table v_table)
    {
        this.kind = Kind.Table;
        this.v_table = v_table;
    }

    this(Index v_index)
    {
        this.kind = Kind.Index;
        this.v_index = v_index;
    }

    this(Identifier v_identifier)
    {
        this.kind = Kind.Identifier;
        this.v_identifier = v_identifier;
    }

    static TValue newNil()
    {
        return TValue(Kind.Nil);
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

    static TValue newIdentifier(Identifier v_identifier)
    {
        return TValue(v_identifier);
    }

    bool opEquals(const TValue rhs) const
    {
        if (this.kind == rhs.kind)
        {
            switch (this.kind)
            {
            case Kind.Nil:
                return true;
            case Kind.Boolean:
                return this.v_boolean == rhs.v_boolean;
            case Kind.String:
                return this.v_string == rhs.v_string;
            case Kind.Number:
                return this.v_number == rhs.v_number;
            case Kind.Address:
                return this.v_address == rhs.v_address;
            case Kind.Table:
                return this.v_table == rhs.v_table;
            case Kind.Index:
                return this.v_index == rhs.v_index;
            case Kind.Identifier:
                return this.v_identifier == rhs.v_identifier;
            default:
                return false;
            }
        }
        return false;
    }
}

struct CallFrame
{
    private Address return_address;
    private Address static_link;
    private Index nargs, nlocals;
    private ConstantPool constants;
    private Environment environment;

    this(Address return_address, Address static_link, Index nargs, Index nlocals,
            Environment environment)
    {
        this.return_address = return_address;
        this.static_link = static_link;
        this.nargs = nargs;
        this.nlocals = nlocals;
        this.constants = null;
        this.environment = environment;
    }

    void setConstant(Index index, TValue constant)
    {
        if (index >= MAX_CONST)
            throw new StackVMError("Constant index too high", index);
        else if (index < 0)
            throw new StackVMError("Constant index too low", index);
        this.constants[index] = constant;
    }

    TValue getConstant(Index index)
    {
        if (index >= MAX_CONST)
            throw new StackVMError("Constant index too high", index);
        else if (index < 0)
            throw new StackVMError("Constant index too low", index);
        return this.constants[index];
    }

    TValue accessEnvironment(const Identifier identifier) const
    {
        return this.environment[identifier];
    }

    Index getNumArgs() const
    {
	return this.nargs;
    }

    Index getNumLocals() const
    {
	return this.nlocals;
    }

    Address getReturnAddress() const
    {
	return this.return_address;
    }

    Address getStaticLink() const
    {
	return this.static_link;
    }
}

class Interpreter
{
    OperandStack operand_stack;
    CallStack call_stack;
    CodeStack code_stack;
    EnvironmentStack environment_stack;
    private ConstantPool globals;
    private StackTrace trace;

    this()
    {
        this.operand_stack = null;
        this.call_stack = null;
        this.code_stack = null;
        this.environment_stack = null;
        this.globals = null;
        this.trace = null;
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
                pushNumber(pow(lhs, rhs));
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
                if (value.kind != TValue.Kind.Boolean)
                    throw new StackVMError("Expected Boolean value at PC", this.program_counter);
                pushBoolean(value.v_boolean);
                continue;
            case Instruction.StoreString:
                auto value = nextCodeValue();
                if (value.kind != TValue.Kind.String)
                    throw new StackVMError("Expected String value at PC", this.program_counter);
                pushString(value.v_string);
                continue;
            case Instruction.StoreNumber:
                auto value = nextCodeValue();
                if (value.kind != TValue.Kind.Number)
                    throw new StackVMError("Expected Number value at PC", this.program_counter);
                pushString(value.v_string);
                continue;
            case Instruction.StoreAddress:
                auto value = nextCodeValue();
                if (value.kind != TValue.Kind.Address)
                    throw new StackVMError("Expected Address value at PC", this.program_counter);
                pushAddress(value.v_address);
                continue;
            case Instruction.StoreIndex:
                auto value = nextCodeValue();
                if (value.kind != TValue.Kind.Index)
                    throw new StackVMError("Expected Index value at PC", this.program_counter);
                pushIndex(value.v_index);
                continue;
            case Instruction.StoreTable:
                auto value = nextCodeValue();
                if (value.kind != TValue.Kind.Table)
                    throw new StackVMError("Expected Table value at PC", this.program_counter);
                pushTable(value.v_table);
                continue;
            case Instruction.SetConstantAtTopFrame:
                auto index = popIndex();
                auto value = popData();
                setConstantAtTopFrame(index, value);
                continue;
            case Instruction.GetConstantAtTopFrame:
                auto index = popIndex();
                auto value = getConstantAtTopFrame(index);
                pushData(value);
                continue;
            case Instruction.SetConstantAtGlobals:
                auto index = popIndex();
                auto value = popData();
                setConstantAtGlobals(index, value);
                continue;
            case Instruction.GetConstantAtGlobals:
                auto index = popIndex();
                auto value = getConstantAtGlobals(index);
                pushData(value);
                continue;
            case Instruction.GetTableEntry:
                auto key = popData();
                auto table = popTable();
                auto entry = table.getEntry(key);
                if (entry.isNull)
                    throw new StackVMError("No such index at table", this.stack_pointer);
                pushData(entry.get.value);
                continue;
            case Instruction.InsertTableEntry:
                auto key = popData();
                auto value = popData();
                auto table = popTable();
                table.insertEntry(key, value);
                pushTable(table);
                continue;
            case Instruction.SetTableEntry:
                auto key = popData();
                auto value = popData();
                auto table = popTable();
                if (!table.setEntry(key, value))
                    throw new StackVMError("No such index at table", this.stack_pointer);
                pushTable(table);
                continue;
            case Instruction.CheckTableEntry:
                auto key = popData();
                auto table = popTable();
                pushBoolean(table.hasEntry(key));
                continue;
            case Instruction.DuplicateTop:
                duplicateTopOfOperandStack();
                continue;
            case Instruction.SwapTop:
                swapTopOfOperandStack();
                continue;
            case Instruction.OverTop:
                overTopOfOperandStack();
                continue;
            case Instruction.RotateTop3:
                rotateTop3OfOperandStack();
                continue;
            case Instruction.RotateTop4:
                rotateTop4OfOperandStack();
                continue;
            case Instruction.Jump:
                auto addr = popAddress();
                setProgramCounter(addr);
                continue;
            case Instruction.JumpIfTrue:
                auto addr = popAddress();
                auto boolean = popBoolean();
                if (boolean)
                    setProgramCounter(addr);
                continue;
            case Instruction.JumpIfFalse:
                auto addr = popAddress();
                auto boolean = popBoolean();
                if (!boolean)
                    setProgramCounter(addr);
                continue;
            case Instruction.Call:
                auto nargs = popIndex();
                auto nlocals = popIndex();
                setupNewCallFrame(nargs, nlocals);
                continue;
            case Instruction.CallConcurrently:
                // todo
                continue;
            case Instruction.Return:
                popCallStackAndClear();
                continue;
            case Instruction.GetArgument:
                auto index = popIndex();
                pushData(getArgument(index));
                continue;
            case Instruction.GetLocal:
                auto index = popIndex();
                pushData(getLocal(index));
                continue;
            case Instruction.StoreLocal:
                auto index = popIndex();
                auto data = popData();
                setLocal(index, data);
                continue;
            default:
                continue;
            }

        }
    }
}
