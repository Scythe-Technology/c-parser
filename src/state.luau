--!strict
local Lexer = require("./lexer");

export type ArgumentPack = {
    name: string?,
    type: {Lexer.Token},
};

export type FunctionTypeDefintion = {
    args: {ArgumentPack},
    ret: {Lexer.Token},
};

export type StructDefintion = {
    fields: {{
        type: {Lexer.Token},
        name: string,
    }},
};

export type State = {
    tokens: {Lexer.Token},
    index: number,
    fns: {[string]: FunctionTypeDefintion},
    fn_types: {[string]: FunctionTypeDefintion},
    type_aliases: {[string]: {Lexer.Token}},
    struct_types: {[string]: StructDefintion},
} & {
    error: (self: State, message: string) -> (),
    assert: (self: State, condition: boolean, message: string?) -> (),
    assertToken: (self: State, expected: Lexer.TypeInfo, values: {string}?, message: string?) -> (),
    assertTokenLine: (self: State, expected: Lexer.TypeInfo, values: {string}?, message: string?) -> (),

    token: (self: State, expected: Lexer.TypeInfo?, err: string?) -> Lexer.Token,
    next: (self: State, expected: Lexer.TypeInfo?, err: string?) -> Lexer.Token,
    nextExclude: (self: State, exclude: Lexer.TypeInfo) -> Lexer.Token,
    iter: (self: State) -> () -> Lexer.Token?,
};

local state = {};

local function assertUp(level: number, condition: boolean, message: string?)
    if (not condition) then
        error(message or "Assertion Failed", level + 1);
    end
end

local function assertTokenLine(token: Lexer.Token, expected: Lexer.TypeInfo, values: {string}?, message: string?)
    assertUp(2, Lexer.eqlTokenType(token, expected), `{token.line}:{token.column}: {message}`);
    if (values) then
        assertUp(2, table.find(values, token.value) ~= nil, `{token.line}:{token.column}: {message}`);
    end
end

local function assertToken(token: Lexer.Token, expected: Lexer.TypeInfo, values: {string}?, message: string?)
    assertUp(2, Lexer.eqlTokenType(token, expected), message);
    if (values) then
        assertUp(2, table.find(values, token.value) ~= nil, message);
    end
end

local function token(self: State, expected: Lexer.TypeInfo?, err: string?): Lexer.Token
    local token = self.tokens[self.index];
    assert(token ~= nil, "Unexpected <EOF>");
    if (expected ~= nil) then
        assertUp(2, token.type == expected, if (err) then `{token.line}:{token.column}: {err}` else `{token.line}:{token.column}: Expected {expected.name}`);
    end
    return token;
end

local function next(self: State, expected: Lexer.TypeInfo?, err: string?): Lexer.Token
    self.index += 1;
    return token(self, expected, err);
end

local function nextExclude(self: State, exclude: Lexer.TypeInfo): Lexer.Token
    local token = next(self);
    while (token.type == exclude) do
        token = next(self);
    end
    return token;
end

local function iter(self: State): () -> Lexer.Token?
    self.index -= 1;
    return function()
        if (self.index >= #self.tokens) then
            return nil;
        end
        return self:next();
    end;
end

state.assertToken = assertToken;
state.assertTokenLine = assertTokenLine;

function state.new(tokens: {Lexer.Token}): State
    return {
        tokens = tokens,
        index = 1,
        fns = {},
        fn_types = {},
        type_aliases = {},
        struct_types = {},

        error = function(self: State, message: string)
            local token = self.tokens[self.index];
            error(`{token.line}:{token.column}: {message}`, 2);
        end,
        assert = function(self: State, condition: boolean, message: string?)
            assertUp(2, condition, message);
        end,
        assertToken = function(self: State, ...)
            return assertToken(self:token(), ...);
        end,
        assertTokenLine = function(self: State, ...)
            return assertTokenLine(self:token(), ...);
        end,

        token = token,
        next = next,
        nextExclude = nextExclude,
        iter = iter,
    };
end

return state;
