module moonix.absyn;

import std.typecons;

interface ASTNode
{
    T accept(T)(NodeVisitor!T visitor);
}

interface Expr : Node
{
}

interface Stat : Node
{
}

interface Factor : Expr
{
}

template NodeVisitor(R)
{
    interface NodeVisitor
    {
        R visitBlock(Block stat);
        R visitAssign(Assign stat);
        R visitFunctionCallStat(FunctionCallStat stat);
        R visitDo(Do stat);
        R visitWhile(While stat);
        R visitRepeat(Repeat stat);
        R visitIf(If stat);
        R visitFor(For stat);
        R visitForIn(ForIn stat);
        R visitFunctionDef(FunctionDef stat);
        R visitLocalFunction(LocalFunction stat);
        R visitLocalVars(LocalVars stat);
        R visitReturn(Return stat);
        R visitBreak(Break stat);
        R visitGoto(Goto stat);
        R visitLabel(Label stat);

        R visitNil(Nil factor);
        R visitBoolean(Boolean factor);
        R visitNumber(Number factor);
        R visitString(String factor);
        R visitVarargs(Varargs factor);
        R visitName(Name factor);
        R visitNestedExpr(NestedExpr factor);

        R visitFunctionThunk(FunctionThunk expr);
        R visitBinary(Binary expr);
        R visitUnary(Unary expr);
        R visitIndex(Index expr);
        R visitField(Field expr);
        R visitMethodCall(MethodCall expr);
        R visitFunctionCallExpr(FunctionCallExpr expr);
        R visitTable(Table expr);
    }
}

class Block : Stat
{
    Stat[] statements;
    Stat laststat;

    this(Stat[] statements, Stat laststat = null)
    {
        this.statements = statements;
        this.laststat = laststat;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitBlock(this);
    }
}

class Assign : Stat
{
    Name[] vars;
    Expr[] values;

    this(Expr[] vars, Expr[] values)
    {
        this.vars = vars;
        this.values = values;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitAssign(this);
    }
}

class FunctionCallStat : Stat
{
    FunctionCallExpr call;

    this(FunctionCallExpr call)
    {
        this.call = call;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitFunctionCallStat(this);
    }
}

class Do : Stat
{
    Block block;

    this(Block block)
    {
        this.block = block;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitDo(this);
    }
}

class While : Stat
{
    Expr condition;
    Block block;

    this(Expr condition, Block block)
    {
        this.condition = condition;
        this.block = block;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitWhile(this);
    }
}

class Repeat : Stat
{
    Block block;
    Expr condition;

    this(Block block, Expr condition)
    {
        this.block = block;
        this.condition = condition;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitRepeat(this);
    }
}

class If : Stat
{
    struct CondBlock
    {
        Expr condition;
        Block block;
    }

    CondBlock[] cond_blocks;
    Block else_block;

    this(CondBlock[] cond_blocks, Block else_block)
    {
        this.cond_blocks = cond_blocks;
        this.else_block = else_block;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitIf(this);
    }
}

class For : Stat
{
    string var;
    Expr start;
    Expr end;
    Expr step;
    Block block;

    this(string var, Expr start, Expr end, Expr step, Block block)
    {
        this.var = var;
        this.start = start;
        this.end = end;
        this.step = step;
        this.block = block;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitFor(this);
    }
}

class ForIn : Stat
{
    string[] names;
    Expr[] iterators;
    Block block;

    this(string[] names, Expr[] iterators, Block block)
    {
        this.names = names;
        this.iterators = iterators;
        this.block = block;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitForIn(this);
    }
}

class FunctionDef : Stat
{
    string[] names;
    string method_name;
    FunctionThunk thunk;

    this(string[] names, string method_name, FunctionThunk thunk)
    {
        this.names = names;
        this.method_name = method_name;
        this.thunk = thunk;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitFunctionDef(this);
    }
}

class LocalFunction : Stat
{
    string name;
    FunctionThunk thunk;

    this(string name, FunctionThunk thunk)
    {
        this.name = name;
        this.thunk = thunk;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitLocalFunction(this);
    }
}

class LocalVars : Stat
{
    Name[] names;
    Expr[] values;

    this(string[] names, Expr[] values)
    {
        this.names = names;
        this.values = values;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitLocalVars(this);
    }
}

class Return : Stat
{
    Expr[] values;

    this(Expr[] values = null)
    {
        this.values = values;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitReturn(this);
    }
}

class Goto : Stat
{
    Name label;

    this(string label)
    {
        this.label = label;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitGoto(this);
    }
}

class Label : Stat
{
    Name name;

    this(string name)
    {
        this.name = name;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitLabel(this);
    }
}

class Break : Stat
{
    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitBreak(this);
    }
}

class Nil : Factor
{
    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitNil(this);
    }
}

class Boolean : Factor
{
    bool value;

    this(bool value)
    {
        this.value = value;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitBoolean(this);
    }
}

class Number : Factor
{
    real value;

    this(real value)
    {
        this.value = value;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitNumber(this);
    }
}

class String : Factor
{
    string value;

    this(string value)
    {
        this.value = value;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitString(this);
    }
}

class Name : Factor
{
    string name;

    this(string name)
    {
        this.name = name;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitName(this);
    }
}

class Varargs : Factor
{
    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitVarargs(this);
    }
}

class NestedExpr : Factor
{
    Expr expr;

    this(Expr expr)
    {
        this.expr = expr;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitNestedExpr(this);
    }
}

class FunctionThunk : Expr
{
    Name[] params;
    bool has_varargs;
    Block def_body;

    this(string[] params, bool has_varargs = false, Block def_body)
    {
        this.params = params;
        this.has_varargs = has_varargs;
        this.def_body = def_body;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitFunctionThunk(this);
    }
}

class Binary : Expr
{
    enum BinaryOp
    {
        Add,
        Sub,
        Mul,
        Div,
        Pow,
        Mod,
        Cat,
        Lt,
        Le,
        Gt,
        Ge,
        Eq,
        Ne,
        And,
        Or,
    }

    BinaryOp op;
    Expr left;
    Expr right;

    this(BinaryOp op, Expr left, Expr right)
    {
        this.op = op;
        this.left = left;
        this.right = right;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitBinary(this);
    }
}

class Unary : Expr
{
    enum UnaryOp
    {
        Neg,
        Not,
        Len,
    }

    UnaryOp op;
    Expr expr;

    this(UnaryOp op, Expr expr)
    {
        this.op = op;
        this.expr = expr;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitUnary(this);
    }
}

class Index : Expr
{
    Expr table;
    Expr key;

    this(Expr table, Expr key)
    {
        this.table = table;
        this.key = key;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitIndex(this);
    }
}

class Field : Expr
{
    Expr table;
    Name key;

    this(Expr table, string key)
    {
        this.table = table;
        this.key = key;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitField(this);
    }
}

class FunctionCallExpr : Expr
{
    Expr func;
    Args args;

    this(Expr func, Args args)
    {
        this.func = func;
        this.args = args;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitFunctionCallExpr(this);
    }
}

class MethodCall : Expr
{
    Expr target;
    Name method;
    Args args;

    this(Expr target, string method, Args args)
    {
        this.target = target;
        this.method = method;
        this.args = args;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitMethodCall(this);
    }
}

struct Args
{
    Expr[] exprs;
    Table table;
    String str;

    this(Expr[] exprs)
    {
        this.exprs = exprs;
    }

    this(Table table)
    {
        this.table = table;
    }

    this(String str)
    {
        this.str = str;
    }
}

class Table : Expr
{
    struct Field
    {
        Expr key;
        Name name;
        Expr value;
    }

    Field[] fields;

    this(Field[] fields)
    {
        this.fields = fields;
    }

    override T accept(T)(NodeVisitor!T visitor)
    {
        return visitor.visitTable(this);
    }
}
