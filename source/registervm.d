module moonix.registervm;

import std.stdio, std.math, std.range, std.typecons, std.algorithm,
    std.container, std.string, std.concurrency, std.process, std.variant,
    core.memory, core.attribute, core.sync.barrier, core.sync.condition;

alias Offset = long;

struct Register
{
    enum Slot
    {
        A,
        B,
        C,
    }

    Slot slot;
    Offset offset;

    this(Slot slot, Offset offset)
    {
        this.slot = slot;
        this.offset = offset;
    }

    static Register newARegister(Offset offset)
    {
        return Register(Slot.A, offset);
    }

    static Register newBRegister(Offset offset)
    {
        return Register(Slot.B, offset);
    }

    static Register newCRegister(Offset offset)
    {
        return Register(Slot.C, offset);
    }

    static Register newARegister()
    {
        return Register(Slot.A, 0);
    }

    static Register newBRegister()
    {
        return Register(Slot.B, 0);
    }

    static Register newCRegister()
    {
        return Register(Slot.C, 0);
    }

}

struct RegisterSlots
{
    Register a_slot;
    Register b_slot;
    Register c_slot;

    this(Offset a_offset, Offset b_offset, Offset c_offset)
    {
        this.a_slot = Register.newARegister(a_offset);
        this.b_slot = Register.newBRegister(b_offset);
        this.c_slot = Register.newCRegister(c_offset);
    }

    this()
    {
        this.a_slot = Register.newARegister();
        this.b_slot = Register.newBRegister();
        this.c_slot = Register.newCRegister();
    }
}

struct Instruction
{
    enum Opcode
    {
        Add,
    }

    Opcode opcode;
    RegisterSlots register_slots;

    this(Opcode opcode)
    {
        this.opcode = opcode;
        this.register_slots = RegisterSlots();
    }

    this(Opcode opcode, Offset a_offset, Offset b_offset, Offset c_offset)
    {
        this.opcode = opcode;
        this.register_slots = RegisterSlots(a_offset, b_offset, c_offset);
    }
}
