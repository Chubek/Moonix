module moonix.stackvm;

import std.math, std.range, std.typecons, std.container;

enum MAX_CONST = 256;
enum STACK_GROWTH_RATE = 1024;
enum DJB2_INIT = 5381;

alias Address = long;
alias Index = size_t;

alias OperandStack = Stack!Value;
alias CallStack = Stack!CallFrame;
alias CodeStack = Stack!Code;
alias UpvalueStack = Stack!Upvalue;

enum Instruction
{
    Add,
    Sub,
    Mul,
    Div,
    FPow,
    IPow,
    Mod,
    Disjunction,
    Conjunction,
    Not,
    Negate,
    BitwiseNot,
    BitwiseOr,
    BitwiseXor,
    BitwiseAnd,
    BitwiseShiftRight,
    BitwiseShiftLeft,
    TruncateReal,
    FloorReal,
    ConcatString,
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
    LoadLocal,
    LoadGlobal,
    StoreLocal,
    StoreGlobal,
    LoadGlobalPointer,
    LoadConstantAtCallTOS,
    StoreConstantAtCallTOS,
    LoadNthArgument,
    LoadFromCodeTOS,
    LoadFromCodeAtOffset,
    InsertIntoTable,
    GetFromTable,
    CheckIfTableHas,
    MakeClosure,
    CallClosure,
    ReturnFromClosure,
    Branch,
    BranchIfTrue,
    BranchIfFalse,
    LoadUpvalue,
    StoreUpvalue,
}

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
    StackTrace trace;

    this(string msg, StackTrace trace)
    {
        super(msg);
        this.trace = trace;
    }
}

class StackTrace
{
    string msg;
}

struct Value
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
        Closure,
        ValuePointer,
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
        Closure v_closure;
        Value* v_value_pointer;
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

    this(Closure v_closure)
    {
        this.kind = Kind.Closure;
        this.v_closure = v_closure;
    }

    this(Value* v_value_pointer)
    {
        this.kind = Kind.ValuePointer;
        this.v_value_pointer = v_value_pointer;
    }

    static Value newNil()
    {
        return Value(Kind.Nil);
    }

    static Value newBoolean(bool v_boolean)
    {
        return Value(v_boolean);
    }

    static Value newString(string v_string)
    {
        return Value(v_string);
    }

    static Value newNumber(real v_number)
    {
        return Value(v_number);
    }

    static Value newNumber(ulong v_number)
    {
        return Value(v_number);
    }

    static Value newAddress(Address v_address)
    {
        return Value(v_address);
    }

    static Value newTable(Table v_table)
    {
        return Value(v_table);
    }

    static Value newIndex(Index v_index)
    {
        return Value(v_index);
    }

    static Value newClosure(Closure v_closure)
    {
        return Value(v_closure);
    }

    static Value newValuePointer(Value* v_value_pointer)
    {
        return Value(v_value_pointer);
    }

    bool opEquals(const Value rhs) const
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
            case Kind.Closure:
                return this.v_closure == rhs.v_closure;
            case Kind.ValuePointer:
                return this.v_value_pointer == rhs.v_value_pointer;
            default:
                return false;
            }
        }
        return false;
    }

    bool isNil() const
    {
        return this.kind == Kind.Nil;
    }

    bool isBoolean() const
    {
        return this.kind == Kind.Boolean;
    }

    bool isNumber() const
    {
        return this.kind == Kind.Number;
    }

    bool isString() const
    {
        return this.kind == Kind.String;
    }

    bool isAddress() const
    {
        return this.kind == Kind.Address;
    }

    bool isIndex() const
    {
        return this.kind == Kind.Index;
    }

    bool isTable() const
    {
        return this.kind == Kind.Table;
    }

    bool isClosure() const
    {
        return this.kind == Kind.Closure;
    }

    bool isValuePointer() const
    {
        return this.kind == Kind.ValuePointer;
    }
}

struct Stack(T)
{
    private T[] container;
    private size_t cursor;
    private size_t length;
    private string name;

    this(string name)
    {
        this.container = new T[STACK_GROWTH_RATE];
        this.cursor = 0;
        this.length = STACK_GROWTH_RATE;
        this.name = name;
    }

    bool isEmpty() const
    {
        return this.cursor == 0;
    }

    void reallocateContainer()
    {
        this.length += STACK_GROWTH_RATE;
        this.container.reserve(this.length);
        this.container.length = this.length;
    }

    void push(T value)
    {
        if (this.cursor >= this.length)
            reallocateContainer();
        this.container[this.cursor++] = value;
    }

    T pop()
    {
        if (!this.cursor)
            throw new StackFlowError("The " ~ this.name ~ " stack underflew", this.cursor);
        return this.container[--this.cursor];
    }

    Nullable!T topSafe() const
    {
        Nullable!T front;
        if (!this.cursor)
            throw new StackFlowError("The " ~ this.name ~ " stack undeflew", this.cursor);
        front = cast(T) this.container[this.cursor - 1];
        return front;
    }

    T top() const
    {
        auto front_nullable = topSafe();
        if (front_nullable.isNull)
            throw new StackFlowError("The " ~ this.name ~ " stack underflew", this.cursor);
        return cast(T) front_nullable.get;
    }

    T* topAsPointer() const
    {
        return cast(T*)&this.container[this.cursor - 1];
    }

    T* offsetAsPointer(Index offset)
    {
        return cast(T*)&this.container[offset];
    }

    T opIndex(const size_t key) const
    {
        if (key >= this.cursor)
            throw new StackFlowError("The " ~ this.name ~ " stack overflew", key);
        return cast(T) this.container[key];
    }

    void opIndexAssign(T value, const size_t key)
    {
        if (key >= this.cursor)
            throw new StackFlowError("The " ~ this.name ~ " stack overflew", key);
        this.container[key] = value;
    }

    T[] opSlice(size_t dim : 0)(size_t i, size_t j) const
    {
        if (i <= 0)
            throw new StackFlowError("The " ~ this.name ~ " stack underflew at slice", i);
        else if (j >= this.cursor)
            throw new StackFlowError("The " ~ this.name ~ " stack overflew at slice", j);
        return this.container[i .. j];
    }

    T[] opIndex()(T[] slice)
    {
        return slice;
    }

    Address getCursor()
    {
        return this.cursor;
    }

    void setCursor(size_t new_cursor)
    {
        this.cursor = new_cursor;
    }

    size_t getLength() const
    {
        return this.length;
    }
}

struct Code
{
    enum Kind
    {
        Instruction,
        Value,
        EndClosureMarker,
    }

    Kind kind;

    union
    {
        Instruction v_instruction;
        Value v_value;
    }

    this(Instruction v_instruction)
    {
        this.kind = Kind.Instruction;
        this.v_instruction = v_instruction;
    }

    this(Value v_value)
    {
        this.kind = Kind.Value;
        this.v_value = v_value;
    }

    static Code newInstruction(Instruction v_instruction)
    {
        return Code(v_instruction);
    }

    static Code newValue(Value v_value)
    {
        return Code(v_value);
    }

    static Code newEndClosureMarker()
    {
        Code code;
        code.kind = Kind.EndClosureMarker;
        return code;
    }

    bool isInstruction() const
    {
        return this.kind == Kind.Instruction;
    }

    bool isValue() const
    {
        return this.kind == Kind.Value;
    }

    bool isEndClosureMarker()
    {
        return this.kind == Kind.EndClosureMarker;
    }
}

struct CallFrame
{
    alias ConstantPool = Value[MAX_CONST];

    Index num_args, num_locals;
    private Address static_link;
    private Address frame_link;
    private Address dynamic_link;
    private ConstantPool constant_pool;

    this(Index num_args, Index num_locals, Address static_link, Address frame_link)
    {
        this.num_args = num_args;
        this.num_locals = num_locals;
        this.static_link = static_link;
        this.dynamic_link = -1;
        this.frame_link = frame_link;
    }

    Address getStaticLink() const
    {
        return this.static_link;
    }

    Address getDynamicLink() const
    {
        return this.dynamic_link;
    }

    Address getFrameLink() const
    {
        return this.frame_link;
    }

    void setDynamicLink(const Address new_dynamic_link)
    {
        this.dynamic_link = new_dynamic_link;
    }

    bool isNestedCall() const
    {
        return this.dynamic_link == -1;
    }

    void storeConstant(Index index, Value value)
    {
        this.constant_pool[index] = value;
    }

    Value opIndex(size_t index) const
    {
        return this.constant_pool[index];
    }

    void opIndexAssign(const Value value, size_t index)
    {
        this.constant_pool[index] = value;
    }
}

class Table
{
    struct Entry
    {
        Value key;
        Value value;

        this(Value key, Value value)
        {
            this.key = key;
            this.value = value;
        }

        bool opEquals(const Entry rhs) const
        {
            return this.key == rhs.key && this.value == rhs.value;
        }
    }

    alias TableEntries = SList!Entry;

    TableEntries entries;
    size_t count;

    this()
    {
        this.count = 0;
    }

    void insertEntry(Value key, Value value)
    {
        this.entries.insertFront(Entry(key, value));
        this.count++;
    }

    bool setEntry(Value key, Value value)
    {
        foreach (ref entry; this.entries[])
        {
            if (entry.key == key)
            {
                entry.value = value;
                return true;
            }
        }
        return false;
    }

    bool hasEntry(Value key)
    {
        foreach (entry; this.entries[])
            if (entry.key == key)
                return true;
        return false;
    }

    Nullable!Entry getEntry(Value key)
    {
        Nullable!Entry found;
        foreach (entry; this.entries[])
        {
            if (entry.key == key)
            {
                found = entry;
                break;
            }
        }
        return found;
    }
}

class Closure
{
    size_t num_params;
    bool is_varargs;
    private Address local_program_counter;
    private UpvalueStack upvalue_stack;

    this(size_t num_params, bool is_varargs, Address local_program_counter)
    {
        this.num_params = num_params;
        this.is_varargs = is_varargs;
        this.local_program_counter = local_program_counter;
    }

    void setLocalPC(Address new_local_program_counter)
    {
        this.local_program_counter = new_local_program_counter;
    }

    Address getLocalPC() const
    {
        return this.local_program_counter;
    }

    void insertUpvalue(Upvalue upvalue)
    {
        this.upvalue_stack.push(upvalue);
    }

    Upvalue getUpvalue(Index index)
    {
        return this.upvalue_stack[index];
    }
}

struct Upvalue
{
    Value* value;
    bool is_closed;

    this(Value* value)
    {
        this.value = value;
        this.is_closed = false;
    }

    void closeDown()
    {
        this.is_closed = true;
    }

    Value* getValuePointer()
    {
        return this.value;
    }

}

class Executor
{
    Address stack_pointer = 0, frame_pointer = 0, global_program_counter = 0;
    Index locals_count = 0, args_count = 0;
    private OperandStack operand_stack = null;
    private CallStack call_stack = null;
    private CodeStack code_stack = null;
    private CodeStack local_code_stack = null;

    void pushOperand(const Value new_operand)
    {
        this.operand_stack.push(new_operand);
        this.stack_pointer++;
    }

    Value popOperand()
    {
        return this.operand_stack[this.stack_pointer--];
    }

    void pushCallFrame(const CallFrame new_call_frame)
    {
        this.call_stack.push(new_call_frame);
    }

    CallFrame popCallFrame()
    {
        return this.call_stack.pop();
    }

    CallFrame topCallFrame() const
    {
        return this.call_stack.top();
    }

    CallFrame* topCallFrameAsPointer() const
    {
        return this.call_stack.topAsPointer();
    }

    void pushCode(const Code new_code)
    {
        this.code_stack.push(new_code);
    }

    Code popCode()
    {
        return this.code_stack.pop();
    }

    Code topCode() const
    {
        return this.code_stack.top();
    }

    void setCodeStackCursorToPC()
    {
        this.call_stack.setCursor(this.global_program_counter);
    }

    void setUpCallFrame(Address call_address)
    {
        auto new_call_frame = CallFrame(this.locals_count, this.args_count,
                this.stack_pointer, this.frame_pointer);
        if (!this.call_stack.isEmpty())
        {
            auto previous_call_frame = topCallFrameAsPointer();
            new_call_frame.setDynamicLink(previous_call_frame.getDynamicLink());
        }
        else
            new_call_frame.setDynamicLink(call_address);
        this.global_program_counter = call_address;
        this.frame_pointer = this.stack_pointer - this.locals_count - this.args_count;
        pushCallFrame(new_call_frame);
        setCodeStackCursorToPC();
    }

    void clearUpCallFrame()
    {
        auto top_call_frame = popCallFrame();
        this.stack_pointer = top_call_frame.getStaticLink();
        this.global_program_counter = top_call_frame.getDynamicLink();
        this.frame_pointer = top_call_frame.getFrameLink();
        setCodeStackCursorToPC();
    }

    Value loadLocalAtOffset(Index offset) const
    {
        auto top_call_frame = topCallFrameAsPointer();
        return this.operand_stack[this.frame_pointer + top_call_frame.num_locals + offset];
    }

    void storeLocalAtOffset(Index offset, Value value)
    {
        auto top_call_frame = topCallFrameAsPointer();
        this.operand_stack[this.frame_pointer + top_call_frame.num_locals + offset] = value;
    }

    Value loadGlobalAtOffset(Index offset)
    {
        return this.operand_stack[offset];
    }

    Value* loadGlobalAtOffsetAsPointer(Index offset)
    {
        return this.operand_stack.offsetAsPointer(offset);
    }

    void storeGlobalAtOffset(Index offset, Value value)
    {
        this.operand_stack[offset] = value;
    }

    Value loadNthArgument(Index offset) const
    {
        auto top_call_frame = topCallFrameAsPointer();
        return this.operand_stack[this.frame_pointer
            + top_call_frame.num_locals + top_call_frame.num_args + offset];
    }

    Value loadFromCodeTOS()
    {
        auto top_code = popCode();
        assert(top_code.isValue());
        return top_code.v_value;
    }

    Value loadFromCodeAtOffset(Index offset) const
    {
        assert(this.code_stack[offset].isValue());
        return this.code_stack[offset].v_value;
    }

    Value loadConstantAtCallTOS(Index offset)
    {
        auto top_call_frame = *topCallFrameAsPointer();
        return top_call_frame[offset];
    }

    void storeConstantAtCallTOS(Index offset, Value value)
    {
        auto top_call_frame = topCallFrameAsPointer();
        top_call_frame.storeConstant(offset, value);
    }

    Closure makeClosure(Index num_params, bool has_varargs)
    {
        return new Closure(num_params, has_varargs, this.global_program_counter);
    }

    void runClosure(Closure closure)
    {
        setUpCallFrame(closure.getLocalPC());
        auto next_code = popCode();

        while (!next_code.isEndClosureMarker())
        {
            if (next_code.isValue())
                throw new StackVMError("Wrong code value at code stack TOS", null);

            switch (next_code.v_instruction)
            {
            case Instruction.Add:
                auto addendr = popOperand();
                auto addendl = popOperand();
                assert(addendr.isNumber() && addendl.isNumber());
                pushOperand(Value.newNumber(addendl.v_number + addendr.v_number));
                continue;
            case Instruction.Sub:
                auto subtrahend = popOperand();
                auto minued = popOperand();
                assert(minued.isNumber() && subtrahend.isNumber());
                pushOperand(Value.newNumber(minued.v_number - subtrahend.v_number));
                continue;
            case Instruction.Mul:
                auto multiplier = popOperand();
                auto multiplicand = popOperand();
                assert(multiplicand.isNumber() && multiplier.isNumber());
                pushOperand(Value.newNumber(multiplicand.v_number * multiplier.v_number));
                continue;
            case Instruction.Div:
                auto divisor = popOperand();
                auto dividend = popOperand();
                assert(dividend.isNumber() && divisor.isNumber());
                pushOperand(Value.newNumber(dividend.v_number / divisor.v_number));
                continue;
            case Instruction.IPow:
                auto exponent = popOperand();
                auto base = popOperand();
                assert(base.isNumber() && exponent.isNumber());
                pushOperand(Value.newNumber(base.v_number ^^ exponent.v_number));
                continue;
            case Instruction.FPow:
                auto exponent = popOperand();
                auto base = popOperand();
                assert(base.isNumber() && exponent.isNumber());
                pushOperand(Value.newNumber(pow(base.v_number, exponent.v_number)));
                continue;
            case Instruction.Mod:
                auto divisor = popOperand();
                auto dividend = popOperand();
                assert(dividend.isNumber() && divisor.isNumber());
                pushOperand(Value.newNumber(
                        cast(ulong) dividend.v_number % cast(ulong) divisor.v_number));
                continue;
            case Instruction.TruncateReal:
                auto truncatee = popOperand();
                assert(truncatee.isNumber());
                pushOperand(Value.newNumber(trunc(truncatee.v_number)));
                continue;
            case Instruction.FloorReal:
                auto flooree = popOperand();
                assert(flooree.isNumber());
                pushOperand(Value.newNumber(floor(flooree.v_number)));
                continue;
            case Instruction.ConcatString:
                auto concated = popOperand();
                auto concatee = popOperand();
                assert(concatee.isString() && concated.isString());
                pushOperand(Value.newString(concatee.v_string ~ concated.v_string));
                continue;
            case Instruction.Eq:
                auto equated = popOperand();
                auto equatee = popOperand();
                pushOperand(Value.newBoolean(equatee == equated));
                continue;
            case Instruction.Ne:
                auto equated = popOperand();
                auto equatee = popOperand();
                pushOperand(Value.newBoolean(equatee != equated));
                continue;
            case Instruction.Gt:
                auto compared = popOperand();
                auto comparee = popOperand();
                assert(comparee.isNumber() && compared.isNumber());
                pushOperand(Value.newBoolean(compared.v_number > comparee.v_number));
                continue;
            case Instruction.Ge:
                auto compared = popOperand();
                auto comparee = popOperand();
                assert(comparee.isNumber() && compared.isNumber());
                pushOperand(Value.newBoolean(compared.v_number >= comparee.v_number));
                continue;
            case Instruction.Lt:
                auto compared = popOperand();
                auto comparee = popOperand();
                assert(comparee.isNumber() && compared.isNumber());
                pushOperand(Value.newBoolean(compared.v_number < comparee.v_number));
                continue;
            case Instruction.Le:
                auto compared = popOperand();
                auto comparee = popOperand();
                assert(comparee.isNumber() && compared.isNumber());
                pushOperand(Value.newBoolean(compared.v_number <= comparee.v_number));
                continue;
            case Instruction.Conjunction:
                auto conjunctee = popOperand();
                auto conjuncted = popOperand();
                assert(conjuncted.isBoolean() && conjunctee.isBoolean());
                pushOperand(Value.newBoolean(conjuncted.v_boolean && conjuncted.v_boolean));
                continue;
            case Instruction.Disjunction:
                auto disjunctee = popOperand();
                auto disjuncted = popOperand();
                assert(disjuncted.isBoolean() && disjunctee.isBoolean());
                pushOperand(Value.newBoolean(disjuncted.v_boolean || disjunctee.v_boolean));
                continue;
            case Instruction.Not:
                auto negated = popOperand();
                assert(negated.isBoolean());
                pushOperand(Value.newNumber(!negated.v_boolean));
                continue;
            case Instruction.Negate:
                auto complemented = popOperand();
                assert(complemented.isNumber());
                pushOperand(Value.newNumber(-complemented.v_number));
                continue;
            case Instruction.BitwiseAnd:
                auto right_op = popOperand();
                auto left_op = popOperand();
                assert(left_op.isNumber() && right_op.isNumber());
                assert(left_op.v_number >= 0 && right_op.v_number >= 0);
                pushOperand(Value.newNumber(
                        (cast(ulong) left_op.v_number) & (cast(ulong) right_op.v_number)));
                continue;
            case Instruction.BitwiseOr:
                auto right_op = popOperand();
                auto left_op = popOperand();
                assert(left_op.isNumber() && right_op.isNumber());
                assert(left_op.v_number >= 0 && right_op.v_number >= 0);
                pushOperand(Value.newNumber(
                        (cast(ulong) left_op.v_number) | (cast(ulong) right_op.v_number)));
                continue;
            case Instruction.BitwiseXor:
                auto right_op = popOperand();
                auto left_op = popOperand();
                assert(left_op.isNumber() && right_op.isNumber());
                assert(left_op.v_number >= 0 && right_op.v_number >= 0);
                pushOperand(Value.newNumber(
                        (cast(ulong) left_op.v_number) ^ (cast(ulong) right_op.v_number)));
                continue;
            case Instruction.BitwiseNot:
                auto operand = popOperand();
                assert(operand.isNumber());
                assert(operand.v_number >= 0);
                pushOperand(Value.newNumber(~(cast(ulong) operand.v_number)));
                continue;
            case Instruction.BitwiseShiftRight:
                auto bitnum = popOperand();
                auto shiftee = popOperand();
                assert(shiftee.isNumber() && bitnum.isNumber());
                assert(shiftee.v_number >= 0 && (bitnum.v_number >= 1 && bitnum.v_number <= 64));
                pushOperand(Value.newNumber(
                        (cast(ulong) shiftee.v_number) >> (cast(ubyte) bitnum.v_number)));
                continue;
            case Instruction.BitwiseShiftLeft:
                auto bitnum = popOperand();
                auto shiftee = popOperand();
                assert(shiftee.isNumber() && bitnum.isNumber());
                assert(shiftee.v_number >= 0 && (bitnum.v_number >= 1 && bitnum.v_number <= 64));
                pushOperand(Value.newNumber(
                        (cast(ulong) shiftee.v_number) << (cast(ubyte) bitnum.v_number)));
                continue;
            case Instruction.LoadLocal:
                auto index = popOperand();
                assert(index.isIndex());
                pushOperand(loadLocalAtOffset(index.v_index));
                continue;
            case Instruction.StoreLocal:
                auto index = popOperand();
                auto value = popOperand();
                assert(index.isIndex());
                storeLocalAtOffset(index.v_index, value);
                continue;
            case Instruction.LoadGlobal:
                auto index = popOperand();
                assert(index.isIndex());
                pushOperand(loadGlobalAtOffset(index.v_index));
                continue;
            case Instruction.StoreGlobal:
                auto index = popOperand();
                auto value = popOperand();
                assert(index.isIndex());
                storeGlobalAtOffset(index.v_index, value);
                continue;
            case Instruction.LoadGlobalPointer:
                auto index = popOperand();
                assert(index.isIndex());
                pushOperand(Value.newValuePointer(loadGlobalAtOffsetAsPointer(index.v_index)));
                continue;
            case Instruction.LoadConstantAtCallTOS:
                auto index = popOperand();
                assert(index.isIndex());
                pushOperand(loadConstantAtCallTOS(index.v_index));
                continue;
            case Instruction.StoreConstantAtCallTOS:
                auto index = popOperand();
                auto value = popOperand();
                assert(index.isIndex());
                storeConstantAtCallTOS(index.v_index, value);
                continue;
            case Instruction.LoadNthArgument:
                auto index = popOperand();
                assert(index.isIndex());
                pushOperand(loadNthArgument(index.v_index));
                continue;
            case Instruction.LoadFromCodeTOS:
                auto value = loadFromCodeTOS();
                pushOperand(value);
                continue;
            case Instruction.LoadFromCodeAtOffset:
                auto index = popOperand();
                assert(index.isIndex());
                pushOperand(loadFromCodeAtOffset(index.v_index));
                continue;
            case Instruction.InsertIntoTable:
                auto value = popOperand();
                auto key = popOperand();
                auto table = popOperand();
                assert(table.isTable());
                table.v_table.insertEntry(key, value);
                pushOperand(table);
                continue;
            case Instruction.GetFromTable:
                auto key = popOperand();
                auto table = popOperand();
                assert(table.isTable());
                auto entry = table.v_table.getEntry(key);
                if (entry.isNull)
                    throw new StackVMError("Table entry does not exist", null);
                pushOperand(entry.get.value);
                continue;
            case Instruction.CheckIfTableHas:
                auto key_in_question = popOperand();
                auto table = popOperand();
                assert(table.isTable());
                pushOperand(Value.newBoolean(table.v_table.hasEntry(key_in_question)));
                continue;
            case Instruction.MakeClosure:
                auto num_params = popOperand();
                auto is_varargs = popOperand();
                assert(num_params.isIndex() && is_varargs.isBoolean());
                pushOperand(Value.newClosure(makeClosure(num_params.v_index, is_varargs.v_boolean)));
                continue;
            case Instruction.CallClosure:
                auto closure_to_call = popOperand();
                assert(closure_to_call.isClosure());
                runClosure(closure_to_call.v_closure);
                continue;
            case Instruction.ReturnFromClosure:
                break;
            case Instruction.Branch:
                auto address = popOperand();
                assert(address.isAddress());
                closure.setLocalPC(address.v_address);
                continue;
            case Instruction.BranchIfTrue:
                auto condition = popOperand();
                auto address = popOperand();
                assert(address.isAddress() && condition.isBoolean());
                if (condition.v_boolean)
                    closure.setLocalPC(address.v_address);
                continue;
            case Instruction.BranchIfFalse:
                auto condition = popOperand();
                auto address = popOperand();
                assert(address.isAddress() && condition.isBoolean());
                if (!condition.v_boolean)
                    closure.setLocalPC(address.v_address);
                continue;
            case Instruction.LoadUpvalue:
                auto index = popOperand();
                assert(index.isIndex());
                auto value_pointer = loadGlobalAtOffsetAsPointer(index.v_index);
                closure.insertUpvalue(Upvalue(value_pointer));
                continue;
            case Instruction.StoreUpvalue:
                auto index = popOperand();
                assert(index.isIndex());
                auto upvalue = closure.getUpvalue(index.v_index);
                pushOperand(Value.newValuePointer(upvalue.getValuePointer()));
                continue;
            default:
                break;
            }
        }

        clearUpCallFrame();
    }

    void runVM()
    {
        auto entrypoint = popOperand();
        assert(entrypoint.isClosure());
        runClosure(entrypoint.v_closure);
    }
}
