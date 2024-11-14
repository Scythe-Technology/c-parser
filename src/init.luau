--!strict
local Lexer = require("./lexer");
local State = require("./state");

local parser = {};

parser.lexer = Lexer;

export type State = State.State;
export type ArgumentPack = State.ArgumentPack;

export type Token = Lexer.Token;
export type TypeInfo = Lexer.TypeInfo;

export type TypePack = {Token};

export type FunctionTypeDefintion = {
    args: {
        type: TypePack,
        name: string,
    },
    ret: TypePack,
};

export type StructDefintion = State.StructDefintion;

local STRUCT_TYPE = {
    id = 101,
    name = "struct",
    patterns = {},
};
local ALIAS_TYPE = {
    id = 102,
    name = "alias",
    patterns = {},
}

parser.STRUCT_TYPE = STRUCT_TYPE;
parser.ALIAS_TYPE = ALIAS_TYPE;

function parser.nextDelimiter(state: State, type: TypeInfo, value: string?): number
    local index = state.index + 1;
    while (index <= #state.tokens) do
        local token = state.tokens[index];
        if (token.type == type and (value == nil or token.value == value)) then
            return index;
        end
        index += 1;
    end
    return index;
end

function parser.checkTokensEql(tokens: {Token}, typesToCheck: {TypeInfo}, valuesToMatch: {string}): (boolean, Token?)
    for _, token in tokens do
        if (not table.find(typesToCheck, token.type)) then
            continue;
        end
        if (not table.find(valuesToMatch, token.value)) then
            return false, token;
        end
    end
    return true, nil;
end

function parser.assertTokensEql(tokens: {Token}, typesToCheck: {TypeInfo}, valuesToMatch: {string}, message: string): (boolean, Token?)
    for _, token in tokens do
        if (not table.find(typesToCheck, token.type)) then
            continue;
        end
        State.assertTokenLine(token, token.type, valuesToMatch, message);
    end
    return true, nil;
end

function parser.assertUnexpected(tokens: {Token}, typesToCheck: {TypeInfo}): ()
    for _, token in tokens do
        if (not table.find(typesToCheck, token.type)) then
            error(`{token.line}:{token.column}: Unexpected '{token.value}'`);
        end
    end
end

local c_types = {"const", "unsigned", "signed", "void", "bool", "char", "short", "int", "long", "float", "double"};
function parser.assertTypepack(tokens: {Token}): ()
    parser.assertTokensEql(tokens, {Lexer.OPERATOR}, {"*"}, `invalid operator`);
    parser.assertTokensEql(tokens, {Lexer.KEYWORD}, c_types, `invalid type`);
    parser.assertUnexpected(tokens, {Lexer.OPERATOR, Lexer.KEYWORD, STRUCT_TYPE, ALIAS_TYPE});
end

function parser.gatherTypepack(state: State, ignoreWhitespace: boolean): (number, {Token})
    local tokens = {};
    local index = state.index;
    while (index <= #state.tokens) do
        local token = state.tokens[index];
        if (token.type == Lexer.OPERATOR or token.type == Lexer.KEYWORD) then
            table.insert(tokens, token);
        elseif (token.type == Lexer.IDENIFIER) then
            if (state.struct_types[token.value]) then
                table.insert(tokens, {
                    type = STRUCT_TYPE,
                    value = token.value,
                    line = token.line,
                    column = token.column,
                    pattern = 1,
                });
            elseif (state.type_aliases[token.value]) then
                table.insert(tokens, {
                    type = ALIAS_TYPE,
                    value = token.value,
                    line = token.line,
                    column = token.column,
                    pattern = 1,
                });
            else
                break;
            end
        elseif (token.type ~= Lexer.WHITESPACE or not ignoreWhitespace) then
            break;
        end
        index += 1;
    end
    return index, tokens;
end

function parser.parseFields(state: State): {{
    type: TypePack,
    name: string,
}}
    -- { ... }
    state:assertTokenLine(Lexer.DELIMITER, {"{"});

    -- parse struct body { ... }
    local fields = {};
    local order = 1;
    while true do
        if (state:nextExclude(Lexer.WHITESPACE).value == '}') then
            break;
        end
        -- <type tokens...> <field name> [, ...] ;
        local index, type_tokens = parser.gatherTypepack(state, true);
        parser.assertTypepack(type_tokens);
        state.index = index;
        local field_name = state:token(Lexer.IDENIFIER, "missing field name").value;
        if (fields[field_name]) then
            error(`duplicate field name, {field_name}`);
        end
        fields[field_name] = {
            type = type_tokens,
            order = order,
        };
        order += 1;
        while true do
            local token = state:nextExclude(Lexer.WHITESPACE);
            if (token.type == Lexer.DELIMITER and token.value ~= ',') then
                break;
            end
            local name_token = state:nextExclude(Lexer.WHITESPACE);
            local type_tokens_copy = table.clone(type_tokens);
            local last_type_token = type_tokens_copy[#type_tokens_copy];
            if (last_type_token.type == Lexer.OPERATOR and last_type_token.value == "*") then
                table.remove(type_tokens_copy, #type_tokens_copy);
            end
            if (name_token.type == Lexer.OPERATOR and name_token.value == '*') then
                table.insert(type_tokens_copy, token);
                name_token = state:nextExclude(Lexer.WHITESPACE);
            end
            State.assertTokenLine(name_token, Lexer.IDENIFIER, nil, "missing field name");
            if (fields[name_token.value]) then
                error(`duplicate field name, {name_token.value}`);
            end
            fields[name_token.value] = {
                type = type_tokens_copy,
                order = order,
            };
            order += 1;
        end
        state:assertTokenLine(Lexer.DELIMITER, {';'}, "missing delimiter, ';' after field name");
    end

    local struct_fields = {};

    for name, field in fields do
        struct_fields[field.order] = {
            type = field.type,
            name = name,
        };
    end
    
    return struct_fields;
end

function parser.parseArguments(state: State, with_names: boolean)
    state:assertTokenLine(Lexer.DELIMITER, {'('}, "missing '('");
    state:nextExclude(Lexer.WHITESPACE);
    local arguments : {ArgumentPack} = {};
     -- (<type tokens...> <name token>, ...)
    while true do
        local seperator = state:token();
        if (seperator.type == Lexer.DELIMITER) then
            state:assertTokenLine(Lexer.DELIMITER, {',', ')'}, "missing delimiter, ',' or ')'");
            if (seperator.value == ')') then
                break;
            end
            state:nextExclude(Lexer.WHITESPACE);
        end
        local index, type_tokens = parser.gatherTypepack(state, true);
        parser.assertTypepack(type_tokens);
        state:assert(#type_tokens > 0, "missing argument type");
        state.index = index;
        local name_token = state:token();
        if (name_token.type == Lexer.IDENIFIER) then
            state:nextExclude(Lexer.WHITESPACE);
            state:assertTokenLine(Lexer.DELIMITER, {',', ')'}, "missing delimiter, ',' or ')'");
            table.insert(arguments, {
                type = type_tokens,
                name = name_token.value,
            });
        else
            state:assertTokenLine(Lexer.DELIMITER, {',', ')'}, "missing delimiter, ',' or ')'");
            table.insert(arguments, {
                type = type_tokens,
            });
        end
    end

    return arguments;
end

function parser.parseTypedef(state: State)
    -- typedef ...
    local next_token = state:nextExclude(Lexer.WHITESPACE);
    if (next_token.type == Lexer.KEYWORD) then
        if (next_token.value == "struct") then
            -- typedef struct { ... } <name token>;
            -- typedef struct <name token> { ... } <name token>;
            local token = state:nextExclude(Lexer.WHITESPACE);
            if (token.type == Lexer.IDENIFIER) then
                local alias_token = state:nextExclude(Lexer.WHITESPACE);
                if (alias_token.type == Lexer.IDENIFIER) then
                    state:nextExclude(Lexer.WHITESPACE);
                    state:assertTokenLine(Lexer.DELIMITER, {';'}, "missing delimiter, ';' after struct");
                    state.struct_types[alias_token.value] = state.struct_types[token.value];
                else
                    state:assertTokenLine(Lexer.DELIMITER, {'{', ';'}, "missing delimiter, ';' or '{' after struct");
                end
            elseif (token.type == Lexer.DELIMITER and token.value == '{') then
                local fields = parser.parseFields(state);
                local alias_token = state:nextExclude(Lexer.WHITESPACE);
                state:assertTokenLine(Lexer.IDENIFIER, nil, "missing alias name");
                state.struct_types[alias_token.value] = {
                    fields = fields,
                };
            else
                state:error(`missing struct name or delimiter, '\{' after struct`);
            end
            return;
        else
            local index, type_tokens = parser.gatherTypepack(state, true);
            parser.assertTypepack(type_tokens);
            state.index = index;
            local token = state:token();
            if (token.type == Lexer.DELIMITER and token.value == '(') then
                -- typedef <type tokens...> ([<operator token?>] <name token>)(<arguments...>);
                local name_tokens = {};
                table.insert(name_tokens, state:nextExclude(Lexer.WHITESPACE));
                if (name_tokens[1].type == Lexer.OPERATOR) then
                    if (name_tokens[1].value == '*') then
                        table.insert(name_tokens, state:nextExclude(Lexer.WHITESPACE));
                    else
                        state:error("Unexpected token");
                    end
                end
                state:nextExclude(Lexer.WHITESPACE);
                state:assertTokenLine(Lexer.DELIMITER, {')'}, "missing delimiter, ')' after function name");
                state:nextExclude(Lexer.WHITESPACE);
                local arguments = parser.parseArguments(state, true);
                state.fn_types[name_tokens[#name_tokens].value] = {
                    args = arguments,
                    ret = type_tokens,
                };
                return;
            elseif (token.type == Lexer.IDENIFIER) then
                -- typedef <type tokens...> <name token>;
                state:nextExclude(Lexer.WHITESPACE);
                state:assertTokenLine(Lexer.DELIMITER, {';'}, "missing delimiter, ';' after typedef");
                state.type_aliases[token.value] = type_tokens;
                return;
            else
                state:error("Unexpected token");
            end
        end
    elseif (next_token.type == Lexer.IDENIFIER) then
        -- typedef <type tokens...> <name token>;
        local index, type_tokens = parser.gatherTypepack(state, true);
        parser.assertTypepack(type_tokens);
        state.index = index;
        local alias_token = state:token(Lexer.IDENIFIER, "expected alias name");
        state:nextExclude(Lexer.WHITESPACE);
        state:assertTokenLine(Lexer.DELIMITER, {';'}, "missing delimiter, ';' after typedef");
        state.type_aliases[alias_token.value] = type_tokens;
        return;
    else
        state:error("Unexpected token");
    end
    state:error("TODO: Unhandled typedef");
end

function parser.parseType(state: State)
    local index, type_tokens = parser.gatherTypepack(state, true);
    parser.assertTypepack(type_tokens);
    state.index = index;
    local name_token = state:token(Lexer.IDENIFIER);
    state:assertTokenLine(Lexer.IDENIFIER, nil, "missing name");
    local next_token = state:nextExclude(Lexer.WHITESPACE);
    if (next_token.type == Lexer.DELIMITER and next_token.value == '(') then
        local arguments = parser.parseArguments(state, true);
        -- body ...) { ... } OR
        -- semicolon ...) ;
        local delimiter_token = state:nextExclude(Lexer.WHITESPACE);
        state:assertTokenLine(Lexer.DELIMITER, {';', '{'}, "missing delimiter, ';' or '{' after function definition");
        if (delimiter_token.value == ';') then
            state.fns[name_token.value] = {
                args = arguments,
                ret = type_tokens,
            };
            return;
        end
        -- body { ... }
        local depth = 1;
        while true do
            local token = state:nextExclude(Lexer.WHITESPACE);
            if (token.type == Lexer.DELIMITER) then
                if (token.value == '{') then
                    depth += 1;
                elseif (token.value == '}') then
                    depth -= 1;
                    if (depth == 0) then
                        break;
                    end
                end
            end
        end
        state.fns[name_token.value] = {
            args = arguments,
            ret = type_tokens,
        };

        return;
    end
    state:error("TODO: empty");
end

function parser.parseHeader(input: string)
    local tokens = Lexer.tokenize({
        input = input,
    });

    local state = State.new(tokens);

    for token in state:iter() do
        if (token.type == Lexer.KEYWORD) then
            if (token.value == "struct") then
                local name_token = state:nextExclude(Lexer.WHITESPACE);
                state:assertTokenLine(Lexer.IDENIFIER, nil, "missing struct name");
                state:nextExclude(Lexer.WHITESPACE);
                local fields = parser.parseFields(state);
                state.struct_types[name_token.value] = {
                    fields = fields,
                };
                state:nextExclude(Lexer.WHITESPACE);
                state:assertTokenLine(Lexer.DELIMITER, {';'}, "missing delimiter, ';' after struct");
            elseif (token.value == "typedef") then
                parser.parseTypedef(state);
            elseif (table.find(c_types, token.value)) then
                parser.parseType(state);
            end
        end
    end

    return state;
end

if (zune and zune.testing.running) then
    local fs = zune.fs;
    local testing = zune.testing;
    
    local test = testing.test;
    local expect = testing.expect;
    local describe = testing.describe;

    describe("Parser", function()
        test("parseStruct", function()
            local input = "struct Test { int a; int b; const char* c; };";
            local state = parser.parseHeader(input);
            expect(state.struct_types.Test).toBe(expect.similar({
                fields = {
                    {
                        name = "a",
                        type = {expect.type("table")},
                    },
                    {
                        name = "b",
                        type = {expect.type("table")},
                    },
                    {
                        name = "c",
                        type = {expect.type("table"), expect.type("table"), expect.type("table")},
                    },
                },
            }));
        end)

        test("parseFull Header", function()
            local input = fs.readFile("test/sample.h");
            local state = parser.parseHeader(input);

            expect(state.struct_types.Test).toBe(expect.similar({
                fields = {
                    {
                        name = "a",
                        type = {expect.type("table")},
                    },
                    {
                        name = "b",
                        type = {expect.type("table")},
                    },
                },
            }));

            expect(state.struct_types.Test2).toBe(expect.similar({
                fields = {
                    {
                        name = "a",
                        type = {expect.type("table")},
                    },
                    {
                        name = "b",
                        type = {expect.type("table")},
                    },
                    {
                        name = "c",
                        type = {expect.type("table")},
                    },
                },
            }));

            expect(state.struct_types.TEST).toBe(expect.similar({
                fields = {
                    {
                        name = "a",
                        type = {expect.type("table")},
                    },
                    {
                        name = "b",
                        type = {expect.type("table")},
                    },
                },
            }));

            expect(state.fns.count).toBe(expect.similar({
                ret = {expect.type("table")},
                args = {},
            }));

            expect(state.fns.set_count).toBe(expect.similar({
                ret = {expect.type("table")},
                args = {
                    {
                        name = "c",
                        type = expect.type("table"),
                    }
                },
            }));

            expect(state.fn_types.callback).toBe(expect.similar({
                ret = {expect.type("table")},
                args = {
                    {
                        type = expect.type("table"),
                    }
                },
            }));

            expect(state.fn_types.callback2).toBe(expect.similar({
                ret = {expect.type("table")},
                args = {},
            }));
        end)
    end)
end

return parser;
