module moonix.absyn;

import std.typecons;

alias BracketPair = Tuple!(Expression, "lhs", Expression, "rhs");
alias NamedPair = Tuple!(Name, "name", Expression, "expression");
alias Bracketed = Tuple!(PrefixExpression, "prefixes", Expression, "bracket");
alias Prefixed = Tuple!(PrefixExpression, "prefixes", Name, "name");
alias IfPair = Tuple!(Expression, "condition", Block, "block");

abstract class ASTNode
{
    size_t line_no;
    size_t column_no;
}

class Name : ASTNode
{
    string value;
}

class String : ASTNode
{
    string value;
}

enum NumberKind
{
    Integer,
    Real,
}

class Number : ASTNode
{
    NumberKind kind;

    union
    {
        long v_integer;
        double v_real;
    }
}

enum ExpressionKind
{
    Nil,
    False,
    True,
    Number,
    String,
    Ellipses,
    Function,
    UnaryExpression,
    BinaryExpression,
    PrefixExpression,
    TableConstructor,
}

class Expression : ASTNode
{
    ExpressionKind kind;

    union
    {
        Number v_number;
        String v_string;
        Function v_function;
        UnaryExpression v_unary_expression;
        BinaryExpression v_binary_expression;
        PrefixExpression v_prefix_expression;
        TableConstructor v_table_constrcutor;
    }
}

enum PrefixExpressionKind
{
    Variable,
    NestedExpression,
    FunctionCall,
}

class PrefixExpression : ASTNode
{
    PrefixExpressionKind kind;

    union
    {
        FunctionCall v_function_call;
        Expression v_nested_expression;
        Variable v_variable;
    }
}

enum ArgumentKind
{
    TableConstructor,
    ExpressionList,
    String,
}

class Argument : ASTNode
{
    ArgumentKind kind;

    union
    {
        TableConstrcutor v_table_constructor;
        String v_string;
        Expression[] v_expression_list;
    }
}

enum BinaryOperatorKind
{
    Plus,
    Minus,
    Times,
    Division,
    Exponent,
    Modulo,
    Concatenation,
    Lesser,
    Greater,
    LesserEqual,
    GreaterEqual,
    Equal,
    Unequal,
    And,
    Or,
}

class BinaryExpression : ASTNode
{
    BinaryOperatorKind kind;
    Expression left;
    Expression right;
}

enum UnaryOperatorKind
{
    Negate,
    Not,
    Length,
}

class UnaryOperator : ASTNode
{
    UnaryOperatorKind kind;
    Expression subject;
}

enum FieldKind
{
    BracketPair,
    NamedPair,
    Expression,
}

class Field : ASTNode
{
    FieldKind kind;

    union
    {
        BracketPair v_bracket_pair;
        NamedPair v_name_pair;
        Expression v_expression;
    }
}

class TableConstructor : ASTNode
{
    Field[] fields;
}

enum ParameterKind
{
    Name,
    Ellipses,
}

class Parameter : ASTNode
{
    ParameterKind kind;
    Name v_name;
}

class FunctionThunk : ASTNode
{
    Parameter[] parameters;
    Block block;
}

class FunctionName : ASTNode
{
    Name[] name_list;
    Name colon_notation;
}

enum VariableKind
{
    Name,
    Bracketed,
    Prefixed,
}

class Variable : ASTNode
{
    VariableKind kind;

    union
    {
        Name v_name;
        Bracketed v_bracketed;
        Prefixed v_prefixed;
    }
}

enum StatementKind
{
    Label,
    FunctionCall,
    Assignment,
    DoBlock,
    WhileBlock,
    RepeatBlock,
    IfBlock,
    ForBlock,
    ForInBlock,
    FunctionBlock,
}

class FunctionCall : ASTNode
{
    PrefixExpression prefix_expression;
    Name colon_name;
    Argument[] arguments;
}

class FunctionBlock : ASTNode
{
    FunctionName name;
    FunctionThunk thunk;
    bool is_local;
}

class Assignment : ASTNode
{
    Name[] name_list;
    Expression[] expression_list;
    bool is_local;
}

class DoBlock : ASTNode
{
    Block block;
}

class WhileBlock : ASTNode
{
    Expression condition;
    Block block;
}

class RepeatBlock : ASTNode
{
    Block block;
    Expression condition;
}

class IfBlock : ASTNode
{
    IfPair main_pair;
    IfPair[] elif_pairs;
    Block else_block;
}

class ForBlock : ASTNode
{
    NamedPair discriminant;
    Expression ceiling;
    Expression step;
    Block block;
}

class ForInBlock : ASTNode
{
    Name[] name_list;
    Expression[] expression_list;
    Block block;
}

class Label : ASTNode
{
    Name label;
}

class Goto : ASTNode
{
    Name label;
}

enum LastStatementKind
{
    Break,
    Return,
    Goto,
}

class LastStatement : ASTNode
{
    LastStatementKind kind;

    union
    {
        Expression[] v_return;
        Goto v_goto;
    }
}

class Statement : ASTNode
{
    StatementKind kind;

    union
    {
        Label v_label;
        FunctionCall v_function_call;
        Assignment v_assignment;
        DoBlock v_do_block;
        WhileBlock v_while_block;
        RepeatBlock v_repeat_block;
        IfBlock v_if_block;
        ForBlock v_for_block;
        ForInBlock v_for_in_block;
    }
}

class Block : ASTNode
{
    Statement[] statements;
    LastStatement last_statement;
}
