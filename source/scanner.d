module moonix.scanner;

import std.stdio, std.typecons, std.container, std.ascii, std.string, std.file,
    std.algorithm, std.conv;

enum TokenKind
{
    KwIf,
    KwThen,
    KwElseif,
    KwElse,
    KwIn,
    KwDo,
    KwEnd,
    KwFor,
    KwWhile,
    KwRepeat,
    KwUntil,
    KwFunction,
    KwLocal,
    KwReturn,
    KwGoto,
    KwBreak,
    KwTrue,
    KwFalse,
    KwNil,
    OpAdd,
    OpMinus,
    OpTimes,
    OpDivide,
    OpExponent,
    OpModulo,
    OpGreat,
    OpLess,
    OpLessEqual,
    OpGreatEqual,
    OpEqual,
    OpUnequal,
    OpAnd,
    OpOr,
    OpConcat,
    OpLength,
    OpNot,
    OpAssign,
    DelimLBrack,
    DelimRBrack,
    DelimLCurly,
    DelimRCurly,
    DelimLParen,
    DelimRParen,
    PunctDot,
    PunctComma,
    PunctColon,
    PunctColonColon,
    PunctSemicolon,
    PunctEllipses,
    ConstString,
    ConstNumber,
    ConstName,
    Newline,
}

struct Position
{
    size_t line_no;
    size_t column_no;
}

struct Token
{
    string lexeme;
    TokenKind kind;
    Position position;
}

class ScannerError : Exception
{
    string msg;
    Position position;

    this(string msg, Position position)
    {
        super(msg);
        this.position = position;
    }
}

class Scanner
{
    string source;
    size_t line_no;
    size_t column_no;
    bool whitespace_allowed = true;

    this(string source)
    {
        this.source = source;
        this.line_no = 1;
        this.column_no = 0;
    }

    static Scanner fromFile(string path)
    {
        string source = readText(path);
        return new Scanner(source);
    }

    Position getCurrentPosition() const
    {
        return Position(this.line_no, this.column_no);
    }

    bool columnsLeft() const
    {
        return (this.line_no * this.column_no) < this.source.length;
    }

    void skipNewline()
    {
        while (this.whitespace_allowed && columnsLeft() && (peekChar() == '\n' || peekChar() == '\r'))
            this.line_no++;
    }

    void skipWhitespace()
    {
        while (this.whitespace_allowed && columnsLeft() && isWhite(peekChar()))
            skipChar();
    }

    char peekChar() const
    {
        return this.source[this.line_no * this.column_no];
    }

    Nullable!char npeekChar(size_t n) const
    {
        Nullable!char chr;
        if ((this.line_no * this.column_no) + n < this.source.length)
            chr = this.source[(this.line_no * this.column_no) + n];
        return chr;
    }

    char nextChar()
    {
        return this.source[this.line_no * this.column_no++];
    }

    void skipChar()
    {
        this.column_no++;
    }

    void ungetChar()
    {
        this.column_no--;
    }

    bool isIdentifierHead(char chr)
    {
        return isAlpha(chr) || chr == '_';
    }

    bool isIdentifierTail(char chr)
    {
        return isIdentifierHead(chr) || isDigit(chr);
    }

    bool isNonDecimalIntegerHead(char chr)
    {
        return "0xobXOB".indexOf(chr) != -1;
    }

    bool isRealMiddle(char chr)
    {
        return ".eE".indexOf(chr) != -1;
    }

    bool isExponentSign(char chr)
    {
        return "+-".indexOf(chr) != -1;
    }

    bool isOperator(char chr)
    {
        return "+-*^%=~<>/#".indexOf(chr) != -1;
    }

    bool isStringDelim(char chr)
    {
        return chr == '\'' || chr == '"';
    }

    bool isDelimiter(char chr)
    {
        return "{}[]()".indexOf(chr) != -1;
    }

    bool isPunct(char chr)
    {
        return ",;:.".indexOf(chr) != -1;
    }

    Token scanIdentifier()
    {
        auto current_position = getCurrentPosition();
        string lexeme = "";

        while (columnsLeft() && isIdentifierTail(peekChar()))
            lexeme ~= nextChar();

        switch (lexeme)
        {
        case "if":
            return Token(lexeme, TokenKind.KwIf, current_position);
        case "then":
            return Token(lexeme, TokenKind.KwThen, current_position);
        case "elseif":
            return Token(lexeme, TokenKind.KwElseif, current_position);
        case "else":
            return Token(lexeme, TokenKind.KwElse, current_position);
        case "do":
            return Token(lexeme, TokenKind.KwDo, current_position);
        case "end":
            return Token(lexeme, TokenKind.KwEnd, current_position);
        case "while":
            return Token(lexeme, TokenKind.KwWhile, current_position);
        case "until":
            return Token(lexeme, TokenKind.KwUntil, current_position);
        case "repeat":
            return Token(lexeme, TokenKind.KwRepeat, current_position);
        case "for":
            return Token(lexeme, TokenKind.KwFor, current_position);
        case "function":
            return Token(lexeme, TokenKind.KwFunction, current_position);
        case "local":
            return Token(lexeme, TokenKind.KwLocal, current_position);
        case "goto":
            return Token(lexeme, TokenKind.KwGoto, current_position);
        case "break":
            return Token(lexeme, TokenKind.KwBreak, current_position);
        case "return":
            return Token(lexeme, TokenKind.KwReturn, current_position);
        case "nil":
            return Token(lexeme, TokenKind.KwNil, current_position);
        case "true":
            return Token(lexeme, TokenKind.KwTrue, current_position);
        case "false":
            return Token(lexeme, TokenKind.KwFalse, current_position);
        case "not":
            return Token(lexeme, TokenKind.OpNot, current_position);
        case "and":
            return Token(lexeme, TokenKind.OpAnd, current_position);
        case "or":
            return Token(lexeme, TokenKind.OpOr, current_position);
        default:
            return Token(lexeme, TokenKind.ConstName, current_position);
        }
    }

    Token scanNumber()
    {
        auto current_position = getCurrentPosition();
        string lexeme = "";

        while (columnsLeft() && isDigit(peekChar()))
            lexeme ~= nextChar();

        if (isRealMiddle(peekChar()))
            lexeme ~= nextChar();

        if (std.ascii.toLower(lexeme[$ - 1]) == 'e' && isExponentSign(peekChar()))
            lexeme ~= nextChar();

        if (lexeme.indexOf('.') != -1 || lexeme.indexOf('e') != -1 || lexeme.indexOf('E') != -1)
            return Token(lexeme, TokenKind.ConstNumber, current_position);
        else
            return Token(lexeme, TokenKind.ConstNumber, current_position);
    }

    Token scanNonDecimalInteger()
    {
        auto current_position = getCurrentPosition();
        string lexeme = "";

        while (columnsLeft() && isNonDecimalIntegerHead(peekChar()))
            lexeme ~= nextChar();

        switch (lexeme)
        {
        case "0x":
        case "0X":
            while (columnsLeft() && isHexDigit(peekChar()))
                lexeme ~= nextChar();
            return Token(lexeme, TokenKind.ConstNumber, current_position);
        case "0o":
        case "0O":
            while (columnsLeft() && isOctalDigit(peekChar()))
                lexeme ~= nextChar();
            return Token(lexeme, TokenKind.ConstNumber, current_position);
        case "0b":
        case "0B":
            while (columnsLeft() && "01".indexOf(peekChar()) != -1)
                lexeme ~= nextChar();
            return Token(lexeme, TokenKind.ConstNumber, current_position);
        default:
            throw new ScannerError("Unterminated non-decimal integer symbol", getCurrentPosition());
        }
    }

    Token scanString()
    {
        auto current_position = getCurrentPosition();
        string lexeme = "";
        char delim;

        if (columnsLeft() && isStringDelim(peekChar()))
            delim = nextChar();

        while (columnsLeft() && peekChar() != delim)
            lexeme ~= nextChar();

        skipChar();

        return Token(lexeme, TokenKind.ConstString, current_position);
    }

    Token scanOperator()
    {
        auto current_position = getCurrentPosition();
        string lexeme = "";

        while (columnsLeft() && isOperator(peekChar()))
            lexeme ~= nextChar();

        switch (lexeme)
        {
        case "+":
            return Token(lexeme, TokenKind.OpAdd, current_position);
        case "-":
            return Token(lexeme, TokenKind.OpMinus, current_position);
        case "*":
            return Token(lexeme, TokenKind.OpTimes, current_position);
        case "^":
            return Token(lexeme, TokenKind.OpExponent, current_position);
        case "/":
            return Token(lexeme, TokenKind.OpDivide, current_position);
        case "%":
            return Token(lexeme, TokenKind.OpModulo, current_position);
        case "~=":
            return Token(lexeme, TokenKind.OpUnequal, current_position);
        case "=":
            return Token(lexeme, TokenKind.OpAssign, current_position);
        case "==":
            return Token(lexeme, TokenKind.OpEqual, current_position);
        case ">":
            return Token(lexeme, TokenKind.OpGreat, current_position);
        case "<":
            return Token(lexeme, TokenKind.OpLess, current_position);
        case ">=":
            return Token(lexeme, TokenKind.OpGreatEqual, current_position);
        case "<=":
            return Token(lexeme, TokenKind.OpLessEqual, current_position);
        case "#":
            return Token(lexeme, TokenKind.OpLength, current_position);
        default:
            throw new ScannerError("Unexpected operator characters", getCurrentPosition());
        }
    }

    Token scanDelimiter()
    {
        auto current_position = getCurrentPosition();
        char chr = nextChar();

        switch (chr)
        {
        case '{':
            return Token("{", TokenKind.DelimLCurly, current_position);
        case '}':
            return Token("}", TokenKind.DelimRCurly, current_position);
        case '[':
            return Token("[", TokenKind.DelimLBrack, current_position);
        case ']':
            return Token("]", TokenKind.DelimRBrack, current_position);
        case '(':
            return Token("(", TokenKind.DelimRParen, current_position);
        case ')':
            return Token(")", TokenKind.DelimLParen, current_position);
        default:
            throw new ScannerError("Wrong delimiter character", getCurrentPosition());
        }
    }

    Token scanPunctuation()
    {
        auto current_position = getCurrentPosition();
        string lexeme = "";

        while (columnsLeft() && isPunct(peekChar()))
            lexeme ~= nextChar();

        switch (lexeme)
        {
        case ",":
            return Token(lexeme, TokenKind.PunctComma, current_position);
        case ";":
            return Token(lexeme, TokenKind.PunctSemicolon, current_position);
        case ":":
            return Token(lexeme, TokenKind.PunctColon, current_position);
        case "::":
            return Token(lexeme, TokenKind.PunctColonColon, current_position);
        case ".":
            return Token(lexeme, TokenKind.PunctDot, current_position);
        case "..":
            return Token(lexeme, TokenKind.OpConcat, current_position);
        case "...":
            return Token(lexeme, TokenKind.PunctEllipses, current_position);
        default:
            throw new ScannerError("Unexpected punctuation", getCurrentPosition());
        }
    }

    Token[] scanSource()
    {
        Token[] tokens;

        while (true)
        {
            skipWhitespace();

            if (peekChar == '\r' || peekChar == '\n')
            {
                skipNewline();
                tokens ~= Token("\n", TokenKind.Newline, getCurrentPosition());
                continue;
            }

            if (!this.whitespace_allowed)
                this.whitespace_allowed = true;

            if (!columnsLeft())
                break;

            if (isIdentifierHead(peekChar()))
                tokens ~= scanIdentifier();
            else if (isDigit(peekChar()))
            {
                Nullable!char npeek = npeekChar(2);
                if (!npeek.isNull && isNonDecimalIntegerHead(npeek.get))
                    tokens ~= scanNonDecimalInteger();
                else
                    tokens ~= scanNumber();
            }
            else if (isOperator(peekChar()))
                tokens ~= scanOperator();
            else if (isPunct(peekChar()))
            {
                this.whitespace_allowed = false;
                tokens ~= scanPunctuation();
            }
            else if (isDelimiter(peekChar()))
                tokens ~= scanDelimiter();
            else if (isStringDelim(peekChar()))
                tokens ~= scanString();

        }

        return tokens;
    }
}

unittest
{
    Scanner scanner = new Scanner("1 + 1;");
    Token[] tokens = scanner.scanSource();
    assert(tokens[0].kind == TokenKind.ConstNumber);
}
