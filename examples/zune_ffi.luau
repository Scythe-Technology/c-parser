--!strict
--[=[
    C to FFI api for Zune
      by Sythivo
--]=]

local ffi = zune.ffi;
assert(ffi, "Zune FFI is required");

local parser = require("../src");

local ffi_transpiler = {};

export type FFILibrary = {}

type StructRegistry = {[string]: Structure};

type ReaderState = {
    state: parser.State,
    structs: StructRegistry,
    aliases: {[string]: number | Structure},
};

local TYPE_NAME = {
    [ffi.types.i8] = "i8",
    [ffi.types.i16] = "i16",
    [ffi.types.i32] = "i32",
    [ffi.types.i64] = "i64",
    [ffi.types.u8] = "u8",
    [ffi.types.u16] = "u16",
    [ffi.types.u32] = "u32",
    [ffi.types.u64] = "u64",
    [ffi.types.float] = "float",
    [ffi.types.double] = "double",
    [ffi.types.void] = "void",
    [ffi.types.pointer] = "pointer",
}

local function readType(state: ReaderState, types: parser.TypePack): number | Structure
    local last = types[#types];
    if (last.type == parser.lexer.OPERATOR and last.value == "*") then
        return ffi.types.pointer;
    elseif (last.type == parser.lexer.KEYWORD) then
        local sub_type = if (#types > 1) then types[#types - 1] else nil;
        if (last.value == "int") then
            if (sub_type and sub_type.value == "unsigned") then
                return ffi.types.u32;
            end
            return ffi.types.i32;
        elseif (last.value == "short") then
            if (sub_type and sub_type.value == "unsigned") then
                return ffi.types.u16;
            end
            return ffi.types.i16;
        elseif (last.value == "long") then
            if (sub_type and sub_type.value == "unsigned") then
                return ffi.types.u64;
            end
            return ffi.types.i64;
        elseif (last.value == "float") then
            return ffi.types.float;
        elseif (last.value == "double") then
            return ffi.types.double;
        elseif (last.value == "void") then
            return ffi.types.void;
        elseif (last.value == "char") then
            if (sub_type and sub_type.value == "unsigned") then
                return ffi.types.u8;
            end
            return ffi.types.i8;
        elseif (last.value == "bool") then
            return ffi.types.u8;
        end
        error(`Unhandled Type: {last.value}`);
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
    local aliases = {};
    local reader_state = {
        state = state,
        structs = struct_registry,
        aliases = aliases,
    };

    for struct_name, struct_info in state.struct_types do
        local fields : {{[string]: Structure | number}} = {};
        for i, field in struct_info.fields do
            table.insert(fields, {
                [field.name] = readType(reader_state, field.type)
            });
        end
        struct_registry[struct_name] = ffi.struct(fields);
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
        aliases[alias_name] = readType(reader_state, alias_type);
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

    local library = ffi.dlopen(file, exported_fns);

    local exported = {}

    for name, _ in exported_fns do
        exported[name] = library[name];
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

if (zune and zune.testing.running) then
    -- based on https://github.com/Scythe-Technology/Zune/blob/8252033c7097597806e59f07db41dbd8d71a8021/test/standard/ffi/sample.zig
    local sample = ffi_transpiler.openLib("./libsample.so", [[
        struct Foo {
            int x, y;
        };

        int add(int a, int b);
        int add_ptr(int* a, int b);
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
    print(Foo:offset("x"));
    print(Foo:offset("y"));

    print(sample.exported.add(1, 2));

    local out = ffi.alloc(ffi.sizeOf(ffi.types.i32)):release();
    sample.exported.add_ptr(out, 52);
    print(out:readi32());

    print(sample.exported.check_struct(Foo:new({
        x = 1,
        y = 2,
    })));

    print(sample.exported.check_struct(Foo:new({
        x = 2,
        y = 2,
    })));
end

return ffi_transpiler;
