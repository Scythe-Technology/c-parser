--!strict
--[=[
    C to FFI api for Lune
      by Sythivo
--]=]

local ffi = require("@lune/ffi");

local parser = require("../src");

local ffi_transpiler = {};

export type FFILibrary = {}

type StructRegistry = { [string]: ffi.CStructInfo };

type ReaderState = {
    state: parser.State,
    structs: StructRegistry,
    aliases: { [string]: ffi.CTypes },
};

local TYPE_NAME = {
    [ffi.c.char] = "i8",
    [ffi.c.short] = "i16",
    [ffi.c.int] = "i32",
    [ffi.c.long] = "i64",
    [ffi.c.uchar] = "u8",
    [ffi.c.ushort] = "u16",
    [ffi.c.uint] = "u32",
    [ffi.c.ulong] = "u64",
    [ffi.f32] = "float",
    [ffi.f64] = "double",
    [ffi.c.void] = "void",
}

local function readType(state: ReaderState, types: parser.TypePack): ffi.CTypes
    local last = types[#types];
    if (last.type == parser.lexer.OPERATOR and last.value == "*") then
        local trimmed = table.clone(types);
        table.remove(trimmed, #trimmed);
        local type = readType(state, trimmed);
        return (type::any):ptr();
    elseif (last.type == parser.lexer.KEYWORD) then
        local sub_type = if (#types > 1) then types[#types - 1] else nil;
        local type_map = {
            int = sub_type and sub_type.value == "unsigned" and ffi.c.uint or ffi.c.int,
            short = sub_type and sub_type.value == "unsigned" and ffi.c.ushort or ffi.c.short,
            long = sub_type and sub_type.value == "unsigned" and ffi.c.ulong or ffi.c.long,
            float = ffi.f32,
            double = ffi.f64,
            void = ffi.c.void,
            char = sub_type and sub_type.value == "unsigned" and ffi.c.uchar or ffi.c.char,
            bool = ffi.c.uchar,
        }
        if (type_map[last.value]) then
            return type_map[last.value];
        end
        error(`Unhandled Type: {last.value}`)
    elseif (last.type == parser.STRUCT_TYPE) then
        local struct = state.structs[last.value];
        assert(struct, `Unknown struct: {last.value}`)
        return struct;
    else
        error("Unknown Type");
    end
end

function ffi_transpiler.openLib(file: string, def: string)
    local state = parser.parseHeader(def);
    local exported_fns = {};
    local fn_types = {};
    local struct_registry = {};
    local aliases :{ [string]: ffi.CTypes } = {};
    local reader_state = {
        state = state,
        structs = struct_registry,
        aliases = aliases,
    };

    for struct_name, struct_info in state.struct_types do
        local fields : {ffi.CTypes} = {};
        for i, field in struct_info.fields do
            table.insert(fields, readType(reader_state, field.type));
        end
        struct_registry[struct_name] = ffi.c.struct(fields);
        TYPE_NAME[struct_registry[struct_name]::any] = struct_name;
    end

    for fn_name, fn_type in state.fn_types do
        local args = {};
        for i, arg in fn_type.args do
            table.insert(args, readType(reader_state, arg.type));
        end
        local ret = readType(reader_state, fn_type.ret);
        fn_types[fn_name] = {
            returns = ret,
            args = args,
        };
    end

    for alias_name, alias_type in state.type_aliases do
        aliases[alias_name] = readType(reader_state, alias_type)::any;
    end

    for fn_name, fn_type in state.fns do
        local args = {};
        for _, arg in fn_type.args do
            table.insert(args, readType(reader_state, arg.type));
        end
        local ret = readType(reader_state, fn_type.ret);
        exported_fns[fn_name] = {
            returns = ret,
            args = args,
        };
    end

    local library = ffi.open(file);

    local exported = {}

    for name, fn in exported_fns do
        local ref = library:find(name);
        local d = ffi.c.fn(fn.args, fn.returns);
        exported[name] = d:callable(ref);
    end

    return {
        lib = library,
        exported = exported,
        exported_fns = exported_fns,
        fns = fn_types,
        aliases = aliases,
        structs = struct_registry,
    };
end

local TESTING = true;

if (TESTING) then
    local sample = ffi_transpiler.openLib("./libsample.so", [[
        struct Foo {
            int x, y;
        };

        int add(int a, int b);
        void add_ptr(int* a, int b);
        bool check_struct(Foo foo);
    ]]);

    print(sample);

    for name, fn_type in sample.exported_fns do
        local type_name = {};
        for _, arg in fn_type.args do
            table.insert(type_name, TYPE_NAME[arg::any] or "?");
        end
        print(`exported: {TYPE_NAME[fn_type.returns::any] or "?"} {name}({table.concat(type_name, ", ")})`);
    end

    local Foo = sample.structs.Foo;
    print(Foo);
    print(Foo:offset(0));
    print(Foo:offset(1));

    local result = ffi.c.int:box(0);
    local a = ffi.c.int:box(1);
    local b = ffi.c.int:box(2);
    sample.exported.add(result, a:ref(), b:ref());
    print(ffi.c.int:readData(result, 0));

    local out = ffi.c.int:box(0);
    ffi.c.int:writeData(a, 52, 0);
    sample.exported.add_ptr(nil, out:ref():ref(), a:ref());
    print(ffi.c.int:readData(out, 0));

    local result2 = ffi.c.uchar:box(0);
    sample.exported.check_struct(result2, Foo:box({1, 2}):ref());
    print(ffi.c.uchar:readData(result2, 0));

    local result3 = ffi.c.uchar:box(0);
    sample.exported.check_struct(result3, Foo:box({2, 2}):ref());
    print(ffi.c.uchar:readData(result3, 0));
end

return ffi_transpiler;
