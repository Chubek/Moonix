module moonix.parser;

import std.conv, std.typecons, std.stdio, std.file, std.string, moonix.absyn, moonix.scanner;

class ParserError : Exception
{
    string msg;
    Token token;

    this(string msg, Token token)
    {
        super(msg);
        this.token = token;
    }
}

class Parser
{
    Token[] tokens;
    size_t cursor;

    this(Token[] tokens)
    {
        this.tokens = tokens;
    }

    bool tokensLeft() const
    {
        return this.cursor < this.tokens.length;
    }

    Nullable!Token currentToken() const
    {
        Nullable!Token token;

        if (!tokensLeft())
            return token;
        else
            token = this.tokens[this.cursor];

        return token;
    }

    bool matchToken(TokenKind token_kind) const
    {
        auto current_token = currentToken();

        if (current_token.isNull || current_token.get.kind != token_kind)
            return false;

        return true;
    }

    Nullable!Token consumeTokenSafe(TokenKind token_kind)
    {
        Nullable!Token token;
        if (matchToken(token_kind))
        {
            token = currentToken();
            this.cursor++;
        }

        return token;
    }

    Token consumeToken(TokenKind token_kind)
    {
        auto consumed_token = consumeTokenSafe(token_kind);

        if (consumed_token.isNull)
            throw new ParserError("Expected token: " ~ tokenKindToString(token_kind), null);

        return consumed_token.get;
    }

    bool consumeTokenOpt(TokenKind token_kind)
    {
        if (peekToken().kind == token_kind)
        {
            consumeToken(token_kind);
            return true;
        }
        return false;
    }

    void ungetToken()
    {
        this.cursor--;
    }

    Nullable!Factor parseFactor()
    {
        Nullable!Factor factor;

        if (matchToken(TokenKind.KwNil))
        {
            Token token = consumeToken(TokenKind.KwNil);
            factor = new Nil();
        }
        else if (matchToken(TokenKind.KwTrue))
        {
            Token token = consumeToken(TokenKind.KwTrue);
            factor = new Boolean(true);
        }
        else if (matchToken(TokenKind.KwFalse))
        {
            Token token = consumeToken(TokenKind.KwFalse);
            factor = new Boolean(false);
        }
        else if (matchToken(TokenKind.ConstNumber))
        {
            Token token = consumeToken(TokenKind.ConstNumber);
            factor = new Number(token.lexeme.to!real);
        }
        else if (matchToken(TokenKind.ConstString))
        {
            Token token = consumeToken(TokenKind.ConstString);
            factor = new String(token.lexeme);
        }
        else if (matchToken(TokenKind.ConstName))
        {
            Token token = consumeToken(TokenKind.ConstName);
            factor = new Name(token.lexeme);
        }
        else if (matchToken(TokenKind.DelimLParen))
        {
            consumeToken(TokenKind.DelimLParen);
            auto expression = parseExpression();

            if (expression.isNull)
                throw new ParserError("Expected nested expression after LPAREN", null);

            consumeToken(TokenKind.DelimRParen);
            factor = new NestedExpr(expression.get);
        }
        else if (matchToken(TokenKind.DelimLCurly))
        {
            consumeToken(TokenKind.DelimLCurly);
            auto table = parseTable();

            if (table.isNull)
                throw new ParserError("Expected table constructor after LCURLY", null);

            consumeToken(TokenKind.DelimRCurly);
            factor = table.get;
        }

        return factor;
    }

    Nullable!Table parseTable()
    {
        Nullable!Table table;
        Table.Field[] fields = null;

        while (true)
        {
            if (!tokensLeft())
                return table;

            if (consumeTokenOpt(TokenKind.DelimLBrack))
            {
                auto key = parseExpression();
                consumeToken(TokenKind.DelimRBrack);
                consumeToken(TokenKind.OpAssign);
                auto value = parseExpression();
                fields ~= Table.Field(key, value);

            }
            else if (matchToken(TokenKind.ConstName))
            {
                auto name_token = consumeToken(TokenKind.ConstName);
                auto name_ast = new Name(name_token.lexeme);

                if (!consumeTokenOpt(TokenKind.OpAssign))
                {
                    fields ~= Table.Field(name_ast);
                }
                else
                {
                    auto value = parseExpression();
                    fields ~= Table.Field(name_ast, value);
                }
            }
            else
            {
                auto value = parseExpression();
                fields ~= Table.Field(value);
            }

            if (!(consumeTokenOpt(TokenKind.PunctSemicolon)
                    || consumeTokenOpt(TokenKind.PunctComma)))
            {
                table = new Table(fields);
                return table;
            }

        }

        return table;
    }

    Nullable!Args parseArguments()
    {
        Nullable!Args arguments;

        if (matchToken(TokenKind.ConstString))
        {
            auto string_token = consumeToken(TokenKind.ConstString);
            arguments = Args(string_token);
            return arguments;
        }
        else if (matchToken(TokenKind.DelimLCurly))
        {
            consumeToken(TokenKind.DelimLCurly);
            auto table = parseTable();
            consumeToken(TokenKind.DelimRCurly);
            arguments = Args(table);
            return arguments;
        }
        else
        {
            Expr[] exprs = null;

            while (true)
            {
                auto expr = parseExpression();

                if (expr.isNull)
                    break;

                exprs ~= expr.get;
                if (!consumeTokenOpt(TokenKind.PunctComma))
                    break;
            }

            arguments = Args(exprs);
            return argument;
        }
    }

    Nullable!FunctionThunk parseFunctionThunk()
    {
        Nullable!FunctionThunk function_thunk;
        Name[] params = null;
        bool has_varargs = false;

        while (true)
        {
            if (!tokensLeft())
                return function_thunk;

            if (matchToken(TokenKind.ConstName))
            {
                auto name_token = consumeToken(TokenKind.ConstName);
                auto name_ast = new Name(name_token.lexeme);
                params ~= name_ast;
            }
            else if (consumeTokenOpt(TokenKind.PunctEllipses))
            {
                if (has_varargs)
                    throw new ParserError("There can only be one varargs notation", null);
                else
                    has_varargs = true;
            }

            if (!consumeTokenOpt(TokenKind.PunctComma))
                break;
        }

        auto function_body = parseBlock();
        function_thunk = new FunctionThunk(params, has_varargs, function_body);
        return function_thunk;
    }

    Nullable!FunctionCallStat parseFunctionCallStat()
    {
        Nullable!FunctionCallStat function_call_stat;

        auto prefix_expr = parsePrefixExpr();

        if (prefix_expr.isNull)
            return function_call_stat;

        if (prefix_expr.get is FunctionCallExpr)
            function_call_stat = new FunctionCallStat(prefix_expr.get);

        return function_call_stat;
    }

    Nullable!Do parseDo()
    {
        Nullable!Do do_block;

        consumeToken(TokenKind.KwDo);
        auto block = parseBlock();
        consumeToken(TokenKind.KwEnd);

        do_block = new Do(block);
        return do_block;
    }

    Nullable!Assign parseAssign()
    {
        Nullable!Assign assign;
        Expr[] vars = null;
        Expr[] values = null;

        while (true)
        {
            if (!tokensLeft())
                return assign;

            auto prefix_expr = parsePrefixExpr();

            if (prefix_expr.isNull && !vars)
                return assign;
            else if (prefix_expr.isNull)
                throw new ParserError("Expected variable name", null);

            vars ~= prefix_expr.get;

            if (!consumeTokenOpt(TokenKind.PunctComma))
                break;
        }

        consumeToken(TokenKind.OpAssign);

        while (true)
        {
            if (!tokensLeft())
                return assign;

            auto expr = parseExpression();

            if (expr.isNull)
                throw new ParserError("Expected expression on RHS of assign", null);

            values ~= expr.get;

            if (!consumeTokenOpt(TokenKind.PunctComma))
                break;
        }

        assign = new Assign(vars, values);
        return assign;
    }

    Nullable!While parseWhile()
    {
        Nullable!While while_block;

        consumeToken(TokenKind.KwWhile);
        auto condition = parseExpression();
        consumeToken(TokenKind.KwDo);
        auto block = parseBlock();
        consumeToken(TokenKind.KwEnd);

        while_block = new While(condition, block);
        return while_block;
    }

    Nullable!Repeat parseRepeat()
    {
        Nullable!Repeat repeat_block;

        consumeToken(TokenKind.KwRepeat);
        auto block = parseBlock();
        consumeToken(TokenKind.KwUntil);
        auto condition = parseExpression();

        repeat_block = new Repeat(block, condition);
        return repeat_block;
    }

    Nullable!If parseIf()
    {
        Nullable!If if_block;
        CondBlock main_block = null;
        CondBlock[] alt_blocks = null;
        Block else_block = null;

        consumeToken(TokenKind.KwIf);

        auto main_condition = parseExpression();
        consumeToken(TokenKind.KwThen);
        auto main_block = parseBlock();
        main_block = If.CondBlock(main_condition, main_block);

        while (true)
        {
            if (!tokensLeft())
                return if_block;

            if (!consumeTokensOpt(TokenKind.KwElseif))
                break;

            auto alt_condition = parseExpression();
            consumeToken(TokenKind.KwThen);
            auto alt_block = parseBlock();

            alt_blocks ~= If.CondBlock(alt_condition, alt_block);
        }

        if (consumeTokenOpt(TokenKind.KwElse))
        {
            else_block = parseBlock();
        }

        consumeToken(TokenKind.KwEnd);
        if_block = new If(main_block, alt_blocks, else_block);
        return if_block;
    }

    Nullable!For parseFor()
    {
        Nullable!For for_block;
        Nullable!Expr opt_expr;
        Name name = null;
        Expr start = null;
        Expr end = null;
        Expr step = null;
        Block block = null;

        consumeToken(TokenKind.KwFor);

        if (matchToken(TokenKind.ConstName))
        {
            auto name_token = consumeToken(TokenKind.ConstName);
            name = new Name(name_token.lexeme);
        }
        else
            throw new ParserError("Expected NAME", null);

        if (matchToken(TokenKind.PunctComma) || matchToken(TokenKind.KwIn))
        {
            ungetToken();
            ungetToken();
            return for_block;
        }

        consumeToken(TokenKind.OpAssign);
        opt_expr = parseExpression();

        if (opt_expr.isNull)
            throw new ParserError("Expected start expression", null);

        start = opt_expr.get;

        consumeToken(TokenKind.PunctComma);
        opt_expr = parseExpression();

        if (opt_expr.isNull)
            throw new ParserError("Expected end expression", null);

        end = opt_expr.get;

        if (consumeTokenOpt(TokenKind.PunctComma))
        {
            opt_expr = parseExpression();

            if (opt_expr.isNull)
                throw new ParserError("Expected step expression after COMMA", null);

            step = opt_expr.get;
        }

        consumeToken(TokenKind.KwDo);
        block = parseBlock();
        consumeToken(TokenKind.KwEnd);

        for_block = new For(name, start, end, step, block);
        return for_block;
    }

    Nullable!ForIn parseForIn()
    {
        Nullable!ForIn for_in_block;
        Name[] names = null;
        Expr[] exprs = null;
        Block block = null;

        consumeToken(TokenKind.KwFor);

        while (true)
        {
            if (!tokensLeft())
                return for_in_block;

            if (matchToken(TokenKind.ConstName))
            {
                auto name_token = consumeToken(TokenKind.ConstName);
                auto name_ast = new Name(name_token.lexeme);
                names ~= name_ast;
            }

            if (!consumeTokenOpt(TokenKind.PunctComma))
                break;
        }

        consumeToken(TokenKind.KwIn);

        while (true)
        {
            if (!tokensLeft())
                return for_in_block;

            auto expr_opt = parseExpression();

            if (expr_opt.isNull)
                throw new ParserError("Expected expression in for...in block", null);

            exprs ~= expr_opt.get;

            if (!consumeTokenOpt(TokenKind.PunctComma))
                break;
        }

        consumeToken(TokenKind.KwDo);
        block = parseBlock();
        consumeToken(Tokenkind.KwEnd);

        for_in_block = new ForIn(names, exprs, block);
        return for_in_block;
    }

    Nullable!FunctionDef parseFunctionDef()
    {
        Nullable!FunctionDef function_def;
        FunctionName function_name;
        FunctionThunk function_thunk;

        consumeToken(TokenKind.KwFunction);
        auto prefix_expr = parsePrefixExpr();

        if (prefix_expr.isNull || prefix_expr.get !is FunctionName)
            throw new ParserError("Expected function name", null);

        function_name = prefix_expr.get;

        auto function_thunk_opt = parseFunctionThunk();

        if (function_thunk_opt.isNull)
            throw new ParserError("Expected function body", null);

        function_thunk = function_thunk_opt.get;
        function_def = new FunctionDef(function_name, function_thunk);
        return function_def;
    }

    Nullable!LocalFunction parseLocalFunction()
    {
        Nullable!LocalFunction local_function;
        Name name = null;
        FunctionThunk function_thunk = null;

        consumeToken(TokenKind.KwLocal);

        if (!consumeTokenOpt(TokenKind.KwFunction))
        {
            ungetToken();
            return local_function;
        }

        if (!matchToken(TokenKind.ConstName))
            throw new ParserError("Expected local function name", null);

        auto name_token = consumeToken(TokenKind.ConstName);
        name = new Name(name_token.lexeme);

        auto function_thunk_opt = parseFunctionThunk();

        if (function_thunk_opt.isNull)
            throw new ParserError("Expected local function body", null);

        function_thunk = function_thunk_opt.get;
        local_function = new LocalFunction(name, function_thunk);
        return local_function;
    }

    Nullable!LocalVars parseLocalVars()
    {
        Nullable!LocalVars local_vars;
        Name[] names = null;
        Expr[] values = null;

        consumeToken(TokenKind.KwLocal);

        while (true)
        {
            if (!tokensLeft())
                return local_vars;

            if (matchToken(TokenKind.ConstName))
            {
                auto name_token = consumeToken(TokenKind.ConstName);
                names ~= new Name(name_token.lexeme);
            }

            if (!consumeTokenOpt(TokenKind.PunctComma))
                break;
        }

        if (!consumeTokenOpt(TokenKind.OpAssign))
        {
            local_vars = new LocalVars(names, values);
            return local_vars;
        }

        while (true)
        {
            if (!tokensLeft())
                return local_vars;

            auto expr = parseExpression();

            if (expr.isNull)
                throw new ParserError("Expected expression after ASSIGN in local variables", null);

            values ~= expr.get;

            if (!consumeTokenOpt(TokenKind.PunctComma))
                break;
        }

        local_vars = new LocalVars(names, values);
        return local_vars;
    }

    Nullable!Return parseReturn()
    {
        Nullable!Return return_stat;
        Expr[] values;

        consumeToken(TokenKind.KwReturn);

        while (true)
        {
            if (!tokensLeft())
            {
                return_stat = new Return(values);
                return return_stat;
            }

            auto expr = parseExpression();

            if (expr.isNull)
            {
                return_stat = new Return(values);
                return return_stat;
            }

            values ~= expr.get;

            if (!consumeTokenOpt(TokenKind.PunctComma))
                break;
        }

        return_stat = new Return(values);
        return return_stat;
    }

    Nullable!Label parseLabel()
    {
        Nullable!Label label;

        consumeToken(TokenKind.PunctColonColon);

        auto name_token = consumeToken(TokenKind.ConstName);
        auto name_ast = new Name(name_token.lexeme);

        label = new Label(name_ast);
        return label;
    }

    Nullable!Goto parseGoto()
    {
        Nullable!Goto goto_stat;

        consumeToken(TokenKind.KwGoto);

        auto name_token = consumeToken(TokenKind.ConstName);
        auto name_ast = new Name(name_token.lexeme);

        goto_stat = new Goto(name_ast);
        return goto_stat;
    }

    Nullable!Break parseBreak()
    {
        Nullable!Break break_stat;

        consumeToken(TokenKind.KwBreak);

        break_stat = new Break();
        return break_stat;
    }

    Nullable!Block parseBlock()
    {
        Nullable!Block block;
        Stat[] statements = null;
        Stat retstat = null;

        while (true)
        {
            if (matchToken(TokenKind.KwFor))
            {
                auto for_block = parseFor();

                if (for_block.isNull)
                {
                    auto for_in_block = parseForIn();

                    if (for_in_block.isNull)
                        throw new ParserError("Expected for or for...in block", null);

                    statements ~= for_in_block.get;

                }
                else
                    statements ~= for_block.get;
            }
            else if (matchToken(TokenKind.KwWhile))
            {
                auto while_block = parseWhile();

                if (while_block.isNull)
                    throw new ParserError("Expected while block", null);

                statements ~= while_block.get;
            }
            else if (matchToken(TokenKind.KwIf))
            {
                auto if_block = parseIf();

                if (if_block.isNull)
                    throw new ParserError("Expected if block", null);

                statements ~= if_block.get;
            }
            else if (matchToken(TokenKind.KwRepeat))
            {
                auto repeat_block = parseRepeat();

                if (repeat_block.isNull)
                    throw new ParserError("Expected repeat block", null);

                statements ~= repeat_block.get;
            }
            else if (matchToken(TokenKind.KwFunction))
            {
                auto function_def = parseFunctionDef();

                if (function_def.isNull)
                    throw new ParserError("Expected function definition", null);

                statements ~= function_def.get;
            }
            else if (matchToken(TokenKind.KwLocal))
            {
                auto local_function = parseLocalFunction();

                if (local_function.isNull)
                {
                    auto local_vars = parseLocalVars();

                    if (local_vars.isNull)
                        throw new ParserError("Expected local function or variables", null);

                    statements ~= local_vars.get;
                }
                else
                    statements ~= local_function.get;

            }
            else if (matchToken(TokenKind.PunctColonColon))
            {
                auto label_stat = parseLabel();

                if (label_stat.isNull)
                    throw new ParserError("Improper label", null);

                statements ~= label_stat.get;
            }
            else if (matchToken(TokenKind.KwDo))
            {
                auto do_block = parseDo();

                if (do_block.isNull)
                    throw new ParserError("Expected do block", null);

                statements ~= do_block.get;
            }

            if (!consumeTokenOpt(TokenKind.Newline) || !consumeTokenOpt(TokenKind.PunctSemicolon))
                throw new ParserError("Expected NEWLINE or SEMICOLON at the end of statement", null);

            if (matchToken(TokenKind.KwBreak) || matchToken(TokenKind.KwGoto)
                    || matchToken(TokenKind.KwReturn)
                    || matchToken(TokenKind.KwEnd) || !tokensLeft())
                break;
        }

        if (matchToken(TokenKind.KwBreak))
            laststat = parseBreak().get;
        else if (matchToken(TokenKind.KwReturn))
            laststat = parseReturn().get;
        else if (matchToken(TokenKind.KwGoto))
            laststat = parseGoto().get;

        block = new Block(statements, laststat);
        return block;

    }

    Nullable!PrefixExpr parsePrefixExpr()
    {
        Nullable!PrefixExpr prefix_expr;
        Expr[] exprs = null;

        while (true)
        {
            if (!tokensLeft())
                return prefix_expr;

            auto factor = parseFactor();
            exprs ~= factor;

            if ((consumeTokenOpt(TokenKind.DelimLParen) || consumeTokenOpt(TokenKind.DelimLCurly)
                    || consumeTokenOpt(TokenKind.ConstString)) && exprs)
            {
                auto arguments = parseArguments();

                if (arguments.exprs && !consumeTokenOpt(TokenKind.DelimRParen))
                    throw new ParserError("Unterminated argument list", null);

                prefix_expr = new FunctionCallExpr(exprs, arguments);
                return prefix_expr;
            }
            else if (consumeTokenOpt(TokenKind.PunctColon) && exprs)
            {
                auto name_token = consumeToken(TokenKind.ConstName);
                auto name_ast = new Name(name_token.lexeme);

                if (consumeTokenOpt(TokenKind.DelimLParen))
                {
                    auto arguments = parseArguments();
                    consumeToken(TokenKind.DelimRParen);
                    prefix_expr = new MethodCall(exprs, name_ast, arguments);
                }
                else
                {
                    prefix_expr = new FunctionName(exprs, name_ast);
                    return prefix_expr;
                }
            }
            else if (consumeTokenOpt(TokenKind.DelimLBrack) && exprs)
            {
                auto bracket_expr = parseExpression();

                if (bracket_expr.isNull)
                    throw new ParserError("Empty bracket expression", null);

                consumeToken(TokenKind.DelimRBrack);
                prefix_expr = new Index(exprs, bracket_expr);
                return prefix_expr;
            }
            else if (consumeTokenOpt(TokenKind.PunctDot))
                continue;
            else
            {
                if (exprs[$ - 1] is Name)
                {
                    Name name_ast = exprs[$ - 1];
                    exprs = exprs[0 .. $ - 1];
                    prefix_expr = new Field(exprs, name_ast);
                    return prefix_expr;
                }
                else
                    throw new ParserError("Expected NAME", null);
            }
        }
    }

    Nullable!Unary parseUnary()
    {
        Nullable!Unary unary;

        Unary.UnaryOp op;

        if (consumeTokenOpt(TokenKind.OpMinus))
            op = Unary.UnaryOp.Neg;
        else if (consumeTokenOpt(TokenKind.OpNot))
            op = Unary.UnaryOp.Not;
        else if (consumeTokenOpt(TokenKind.OpLength))
            op = Unary.UnaryOp.Len;
        else
            op = Unary.UnaryOp.None;

        auto prefix = parsePrefixExpr();

        if (prefix.isNull)
            throw new ParserError("Expected prefix expression", null);

        unary = new Unary(op, prefix.get);
        return unary;
    }

    Nullable!Binary parseExponentiation()
    {
        Nullable!Binary exponentiation;

        auto lhs = parseUnary();

        if (lhs.isNull)
            return exponentiation;

        consumeToken(TokenKind.OpExponent);

        auto rhs = parseUnary();

        if (rhs.isNull)
            throw new ParserError("Expected RHS of exponentiationiation", null);

        exponentiation = new Binary(Binary.BinaryOp.Pow, lhs.get, rhs.get);
        return exponentiation;
    }

    Nullable!Binary parseMultiplication()
    {
        Nullable!Binary multiplication;

        auto lhs = parseExponentiation();

        if (lhs.isNull)
            return multiplication;

        Binary.BinaryOp op;

        if (consumeTokenOpt(TokenKind.OpTimes))
            op = Binary.BinaryOp.Mul;
        else if (consumeTokenOpt(TokenKind.OpDivide))
            op = Binary.BinaryOp.Div;
        else if (consumeTokenOpt(TokenKind.OpModulo))
            op = Binary.BinaryOp.Mod;
        else
            throw new ParserError("Expected MUL, DIV or MOD", null);

        auto rhs = parseExponentiation();

        if (rhs.isNull)
            throw new ParserError("Expected RHS of multiplication, division or modulo", null);

        multiplication = new Binary(op, lhs.get, rhs.get);
        return multiplication;
    }

    Nullable!Binary parseAddition()
    {
        Nullable!Binary addition;

        auto lhs = parseMultiplication();

        if (lhs.isNull)
            return addition;

        Binary.BinaryOp op;

        if (consumeTokenOpt(TokenKind.OpAdd))
            op = Binary.BinaryOp.Add;
        else if (consumeTokenOpt(TokenKind.OpMinus))
            op = Binary.BinaryOp.Sub;
        else
            throw new ParserError("Expected ADD or SUB", null);

        auto rhs = parseMultiplication();

        if (rhs.isNull)
            throw new ParserError("Expected RHS of addition or subtraction", null);

        addition = new Binary(op, lhs.get, rhs.get);
        return addition;
    }

    Nullable!Binary parseConcatenation()
    {
        Nullable!Binary concatenation;

        auto lhs = parseAddition();

        if (lhs.isNull)
            return concatenation;

        if (!consumeTokenOpt(TokenKind.OpConcat))
            throw new ParserError("Expected CAT", null);

        auto rhs = parseAddition();

        if (rhs.isNull)
            throw new ParserError("Expected RHS of concatentation", null);

        concatenation = new Binary(Binary.BinaryOp.Cat, lhs.get, rhs.get);
        return concatenation;
    }

    Nullable!Binary parseConjunction()
    {
        Nullable!Binary conjunction;

        auto lhs = parseConcatenation();

        if (lhs.isNull)
            return conjunction;

        if (!consumeTokenOpt(TokenKind.OpAnd))
            throw new ParserError("Expectd AND", null);

        auto rhs = parseConcatenation();

        if (rhs.isNull)
            throw new ParserError("Expected RHS of conjunction", null);

        conjunction = new Binary(Binary.BinaryOp.And, lhs.get, rhs.get);
        return conjunction;
    }

    Nullable!Binary parseDisjunction()
    {
        Nullable!Binary disjunction;

        auto lhs = parseConjunction();

        if (lhs.isNull)
            return expression;

        if (!consumeTokenOpt(TokenKind.OpOr))
            throw new ParserError("Expected OR", null);

        auto rhs = parseConjunction();

        if (rhs.isNull)
            throw new ParserError("Expected RHS of disjunction", null);

        disjunction = new Binary(Binary.BinaryOp.Or, lhs.get, rhs.get);
        return disjunction;
    }

    Nullable!Expr parseExpression()
    {
        return parseDisjunction();
    }

    Nullable!Stat parseLua()
    {
        return parseBlock();
    }
}
