--!strict
export type TypeInfo = {
    id: number,
    name: string,
    patterns: {string},
};

export type Token = {
    type: TypeInfo,
    value: string,
    pattern: number,
    line: number,
    column: number,
};

local lexer = {};

local keywords = {
    "continue", "break", "return",
    "if", "else", "switch", "case", "default",
    "for", "while", "do",
    "unsigned", "signed",
    "void", "bool", "char", "short", "int", "long", "float", "double",
    "struct", "enum", "union",
    "typedef", "extern", "static", "register", "auto", "const", "volatile",
    "sizeof", "alignof",
};

local patterns: {TypeInfo} = {};

local function newPattern(name: string, list: {string}, id: number): TypeInfo
    local info = {
        id = id,
        name = name,
        patterns = list,
    };
    if (#list == 0) then
        return info;
    end
    table.insert(patterns, info);
    return info;
end

lexer.KEYWORD = newPattern("keyword", {}, 0);
lexer.IDENIFIER = newPattern("identifier", {`^%a[%w_]*`}, 1);
lexer.NUMBER = newPattern("number", {`^%d+`}, 2);
lexer.COMMENT = newPattern("comment", {`^//[^\n]*`, `^/%*.-%*/`, `^/%*.*`}, 3);
lexer.OPERATOR = newPattern("operator", {`^[%+%-%*/%%&|%^!=<>]=?`}, 4);
lexer.DELIMITER = newPattern("delimiter", {`^[%(%)\{%\}%[%],;%.]`}, 5);
lexer.STRING = newPattern("string", {`^"[^"]*"`}, 6);
lexer.WHITESPACE = newPattern("whitespace", {`^%s+`}, 7);

type Options = {
    input: string,
    whitespace: boolean?,
}

local IDENIFIER = lexer.IDENIFIER;
local KEYWORD = lexer.KEYWORD;
local NUMBER = lexer.NUMBER;
local COMMENT = lexer.COMMENT;
local OPERATOR = lexer.OPERATOR;
local DELIMITER = lexer.DELIMITER;
local STRING = lexer.STRING;
local WHITESPACE = lexer.WHITESPACE;

function lexer.tokenize(opts: Options): {Token}
    local tokens: {Token} = {};
    local index = 1;

    local input = opts.input;
    local line = 1;
    local column = 1;
    while index <= #input do
        for _, info in patterns do
            local startIdx, endIdx;
            local id = 1;
            for patternId, pattern in info.patterns do
                id = patternId;
                startIdx, endIdx = input:find(pattern, index);
                if startIdx and endIdx then
                    break;
                end
                startIdx, endIdx = nil, nil;
            end
            if not startIdx or not endIdx then
                continue;
            end
            local value = input:sub(startIdx, endIdx);
            local lines = value:split("\n");
            local this_line = line;
            local this_column = column;
            line += #lines - 1;
            if (#lines > 1) then
                column = 1;
            end
            column += #lines[#lines];
            index += endIdx - startIdx;
            if (info == IDENIFIER) then
                if table.find(keywords, value) then
                    info = KEYWORD;
                    id = 1;
                end
            elseif (info == WHITESPACE) then
                if (opts.whitespace == false) then
                    continue;
                end
            end
            table.insert(tokens, {
                type = info,
                value = value,
                pattern = id,
                line = this_line,
                column = this_column,
            });
            break
        end

        index += 1;
    end

    return tokens
end

function lexer.eqlTokenType(token: Token, type: TypeInfo)
    return token.type == type;
end

function lexer.eqlToken(token: Token, type: TypeInfo, value: string)
    return lexer.eqlTokenType(token, type) and token.value == value;
end

if (zune and zune.testing.running) then
    local testing = zune.testing;
    
    local test = testing.test;
    local expect = testing.expect;
    local describe = testing.describe;

    describe("Lexer", function()
        local example_code = [[
int main() {
    // This is a comment
    /*
        This is a block comment
    */
    int a = 0;
    a += 1;
    a = a + 1 * 3;
    printf("Hello, World!\n");
    return 0;
}]]
        test("tokenize (default)", function()
            local tokens = lexer.tokenize({
                input = example_code,
            });
            expect(tokens).toBe(expect.type("table"));
            expect(#tokens).toBe(55);

            local function next()
                return table.remove(tokens, 1);
            end

            local function expectToken(type: TypeInfo, value: string, id: number?)
                local token = next();
                assert(token, "Expected token, got nil");
                expect(token.type).toBe(type);
                expect(token.value).toBe(value);
                expect(token.pattern).toBe(id or 1);
            end

            expectToken(KEYWORD, "int");
            expectToken(WHITESPACE, " ");
            expectToken(IDENIFIER, "main");
            expectToken(DELIMITER, "(");
            expectToken(DELIMITER, ")");
            expectToken(WHITESPACE, " ");
            expectToken(DELIMITER, "{");
            expectToken(WHITESPACE, "\n    ");
            expectToken(COMMENT, "// This is a comment");
            expectToken(WHITESPACE, "\n    ");
            expectToken(COMMENT, "/*\n        This is a block comment\n    */", 2);
            expectToken(WHITESPACE, "\n    ");
            expectToken(KEYWORD, "int");
            expectToken(WHITESPACE, " ");
            expectToken(IDENIFIER, "a");
            expectToken(WHITESPACE, " ");
            expectToken(OPERATOR, "=");
            expectToken(WHITESPACE, " ");
            expectToken(NUMBER, "0");
            expectToken(DELIMITER, ";");
            expectToken(WHITESPACE, "\n    ");
            expectToken(IDENIFIER, "a");
            expectToken(WHITESPACE, " ");
            expectToken(OPERATOR, "+=");
            expectToken(WHITESPACE, " ");
            expectToken(NUMBER, "1");
            expectToken(DELIMITER, ";");
            expectToken(WHITESPACE, "\n    ");
            expectToken(IDENIFIER, "a");
            expectToken(WHITESPACE, " ");
            expectToken(OPERATOR, "=");
            expectToken(WHITESPACE, " ");
            expectToken(IDENIFIER, "a");
            expectToken(WHITESPACE, " ");
            expectToken(OPERATOR, "+");
            expectToken(WHITESPACE, " ");
            expectToken(NUMBER, "1");
            expectToken(WHITESPACE, " ");
            expectToken(OPERATOR, "*");
            expectToken(WHITESPACE, " ");
            expectToken(NUMBER, "3");
            expectToken(DELIMITER, ";");
            expectToken(WHITESPACE, "\n    ");
            expectToken(IDENIFIER, "printf");
            expectToken(DELIMITER, "(");
            expectToken(STRING, "\"Hello, World!\\n\"");
            expectToken(DELIMITER, ")");
            expectToken(DELIMITER, ";");
            expectToken(WHITESPACE, "\n    ");
            expectToken(KEYWORD, "return");
            expectToken(WHITESPACE, " ");
            expectToken(NUMBER, "0");
            expectToken(DELIMITER, ";");
            expectToken(WHITESPACE, "\n");
            expectToken(DELIMITER, "}");

            expect(#tokens).toBe(0);
        end)
        test("tokenize (no whitespace)", function()
            local tokens = lexer.tokenize({
                input = example_code,
                whitespace = false,
            });
            expect(tokens).toBe(expect.type("table"));
            expect(#tokens).toBe(33);
    
            local function next()
                return table.remove(tokens, 1);
            end

            local function expectToken(type: TypeInfo, value: string, id: number?)
                local token = next();
                assert(token, "Expected token, got nil");
                expect(token.type).toBe(type);
                expect(token.value).toBe(value);
                expect(token.pattern).toBe(id or 1);
            end
    
            expectToken(KEYWORD, "int");
            expectToken(IDENIFIER, "main");
            expectToken(DELIMITER, "(");
            expectToken(DELIMITER, ")");
            expectToken(DELIMITER, "{");
            expectToken(COMMENT, "// This is a comment");
            expectToken(COMMENT, "/*\n        This is a block comment\n    */", 2);
            expectToken(KEYWORD, "int");
            expectToken(IDENIFIER, "a");
            expectToken(OPERATOR, "=");
            expectToken(NUMBER, "0");
            expectToken(DELIMITER, ";");
            expectToken(IDENIFIER, "a");
            expectToken(OPERATOR, "+=");
            expectToken(NUMBER, "1");
            expectToken(DELIMITER, ";");
            expectToken(IDENIFIER, "a");
            expectToken(OPERATOR, "=");
            expectToken(IDENIFIER, "a");
            expectToken(OPERATOR, "+");
            expectToken(NUMBER, "1");
            expectToken(OPERATOR, "*");
            expectToken(NUMBER, "3");
            expectToken(DELIMITER, ";");
            expectToken(IDENIFIER, "printf");
            expectToken(DELIMITER, "(");
            expectToken(STRING, "\"Hello, World!\\n\"");
            expectToken(DELIMITER, ")");
            expectToken(DELIMITER, ";");
            expectToken(KEYWORD, "return");
            expectToken(NUMBER, "0");
            expectToken(DELIMITER, ";");
            expectToken(DELIMITER, "}");

            expect(#tokens).toBe(0);
        end);

        test("broken comment", function()
            local tokens = lexer.tokenize({
                input = "/* something",
                whitespace = false,
            });
            expect(tokens).toBe(expect.type("table"));
            expect(#tokens).toBe(1);
    
            local function next()
                return table.remove(tokens, 1);
            end

            local function expectToken(type: TypeInfo, value: string, id: number?)
                local token = next();
                assert(token, "Expected token, got nil");
                expect(token.type).toBe(type);
                expect(token.value).toBe(value);
                expect(token.pattern).toBe(id or 1);
            end
    
            expectToken(COMMENT, "/* something", 3);

            expect(#tokens).toBe(0);
        end);
    end)
end

return lexer;
