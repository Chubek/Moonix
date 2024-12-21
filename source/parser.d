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
            auto nested_expr = parseExpr();
            consumeToken(TokenKind.DelimRParen);
            factor = new NestedExpr(nested_expr);
        }

        return factor;
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

        auto factor = parseFactor();

        if (factor.isNull)
            throw new ParserError("Expected expression factor", null);

        unary = new Unary(op, factor.get);
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

    Nullable!Binary parseExpression()
    {
        Nullable!Binary expression;

        auto lhs = parseConjunction();

        if (lhs.isNull)
            return expression;

        if (!consumeTokenOpt(TokenKind.OpOr))
            throw new ParserError("Expected OR", null);

        auto rhs = parseConjunction();

        if (rhs.isNull)
            throw new ParserError("Expected RHS of disjunction", null);

        expression = new Binary(Binary.BinaryOp.Or, lhs.get, rhs.get);
        return expression;
    }
}
