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
alias CodeList = Instruction[MAX_CODE];
alias ConstantPool = TValue[MAX_CONST];
alias Address = size_t;
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

enum Instruction
{
    Add,
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
        True,
        False,
        String,
        Number,
        Address,
        Table,
    }

    TValueKind kind;

    union
    {
        string v_string;
        real v_number;
        Address v_address;
        Table v_table;
    }

    this(TValueKind kind)
    {
        this.kind = kind;
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

    static TValue newNil()
    {
        return TValue(TValueKind.Nil);
    }

    static TValue newTrue()
    {
        return TValue(TValueKind.True);
    }

    static TValue newFalse()
    {
        return TValue(TValueKind.False);
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

    bool opEquals(const TValue rhs) const
    {
        if (this.kind == rhs.kind)
        {
            switch (this.kind)
            {
            case TValueKind.Nil:
            case TValueKind.True:
            case TValueKind.False:
                return true;
            case TValueKind.String:
                return this.v_string == rhs.v_string;
            case TValueKind.Number:
                return this.v_number == rhs.v_number;
            case TValueKind.Address:
                return this.v_address == rhs.v_address;
            case TValueKind.Table:
                return this.v_table == rhs.v_table;
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
    size_t nargs, nlocals;
    private ConstantPool constants;

    this(Address return_address, Address static_link, size_t nargs, size_t nlocals)
    {
        this.return_address = return_address;
        this.static_link = static_link;
        this.nargs = nargs;
        this.nlocals = nlocals;
        this.constants = null;
    }

    void setConstant(size_t index, TValue constant)
    {
        if (index >= MAX_CONST)
            throw new StackVMError("Constant index too high", this.return_address);
        this.constants[index] = constant;
    }

    TValue getConstant(size_t index)
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
    CodeList code_list;
    private Address stack_pointer;
    private Address frame_pointer;
    private Address program_counter;
    private size_t code_size;
    private size_t call_size;

    this()
    {
        this.data_stack = null;
        this.call_stack = null;
        this.code_list = null;
        this.stack_pointer = 0;
        this.frame_pointer = 0;
        this.program_counter = 0;
        this.code_size = 0;
        this.call_size = 0;
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

    void pushTrue()
    {
        pushData(TValue.newTrue());
    }

    void pushFalse()
    {
        pushData(TValue.newFalse());
    }

    void pushString(string value)
    {
        pushData(TValue.newString(value));
    }

    void pushNumber(real value)
    {
        pushData(TValue.newNumber(value));
    }

    void pushAddress(Address value)
    {
        pushData(TValue.newAddress(value));
    }

    TValue popData()
    {
        if (this.stack_pointer == 0)
            throw new StackVMError("Data stack underflow", this.stack_pointer);
        return this.data_stack[this.stack_pointer--];
    }

    TValue getArgument(size_t number)
    {
        auto call_frame = this.call_stack[this.call_size - 1];
        auto nargs = call_frame.nargs;
        return this.data_stack[this.frame_pointer + (nargs - number)];
    }

    TValue getLocal(size_t number)
    {
        auto call_frame = this.call_stack[this.call_size - 1];
        auto nlocals = call_frame.nlocals;
        auto nargs = call_frame.nargs;
        return this.data_stack[this.frame_pointer + ((nargs + nlocals) - number)];
    }

    TValue getConstantAtTopFrame(size_t index)
    {
        auto call_frame = this.call_stack[this.call_size - 1];
        return call_frame.getConstant(index);
    }

    void setConstantAtTopFrame(size_t index, TValue value)
    {
        auto call_frame = this.call_stack[this.call_size - 1];
        call_frame.setConstant(index, value);
    }

    void insertCode(Instruction code)
    {
        this.code_list[this.code_size++] = code;
    }

    Instruction nextCode()
    {
        if (this.code_size + 1 < this.program_counter)
            throw new StackVMError("Code list overflow", this.program_counter);
        return this.code_list[this.program_counter++];
    }

    void setupNewCallFrame(size_t nargs, size_t nlocals)
    {
        if (this.call_size + 1 >= MAX_CALL)
            throw new StackVMError("Call stack overflow", this.call_size);
        this.call_stack[++this.call_size] = CallFrame(this.stack_pointer + nargs + nlocals,
                this.frame_pointer, nargs, nlocals);
        this.frame_pointer = this.stack_pointer;
    }

    void popCallStackAndClear()
    {
        if (this.call_size == 0)
            throw new StackVMError("Call stack underflow", this.call_size);
        auto call_frame = this.call_stack[this.call_size--];
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
}
