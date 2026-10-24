const std = @import("std");

const ast = @import("ast.zig");
const args_unpacker = @import("args_unpacker.zig");

const SymbolTable = @import("symbol_table.zig").SymbolTable;
const Environment = @import("environment.zig").Environment;
const Evaluator = @import("evaluator.zig").Evaluator;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const ListIter = @import("list_iter.zig").ListIterator;

const SymbolNode = ast.Symbol;
const AstNode = ast.AstNode;
const Object = ast.Object;

pub const SpecialFormError = error{
    CdrIsNotList,
    ArgIsNotList,
    ArgIsNotString,
    ArgsIsRequired,
    LambdaArgsMustBeList,
    LambdaBodyCantBeEmpty,
    DambdaArgsMustBeList,
    DambdaBodyCantBeEmpty,
    MacroArgsMustBeList,
    MacroBodyCantBeEmpty,
};

pub const SpecialForm = struct {
    ptr: *const anyopaque,
    repr: []const u8,
    exec_fn: *const fn (ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) anyerror!AstNode,
};

pub fn MakeSpecialForm(comptime name: []const u8, comptime body_fn: anytype) type {
    return struct {
        pub const repr = name;
        symbol: SymbolNode,
        allocator: std.mem.Allocator,
        symbol_table: *SymbolTable,

        pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !@This() {
            return .{
                .symbol = try symbol_table.insert(@This().repr),
                .allocator = allocator,
                .symbol_table = symbol_table,
            };
        }

        pub fn specialForm(self: *const @This()) SpecialForm {
            return .{ .ptr = self, .repr = @This().repr, .exec_fn = @This().exec };
        }

        pub inline fn register(self: @This(), environment: *Environment) !void {
            try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
        }

        fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) anyerror!AstNode {
            const self: *const @This() = @ptrCast(@alignCast(ptr));
            return try body_fn(self, environment, evaluator, body);
        }
    };
}

pub const Quote = MakeSpecialForm("quote", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "arg", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;
        _ = environment;
        _ = evaluator;

        const shape = try args_unpacker.unpack(spec, "quote", body);

        return shape.get("arg");
    }
}.exec);

pub const TypeOf = MakeSpecialForm("typeof", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "arg", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "typeof", body);

        const arg = shape.get("arg");
        const evaluated_arg = try evaluator.evaluate(arg, environment);

        const type_str = switch (evaluated_arg) {
            .object => if (ast.isCons(evaluated_arg) != null) "list" else "string",
            else => |node| @tagName(node),
        };

        return ast.makeString(self.allocator, type_str);
    }
}.exec);

pub const Cons = MakeSpecialForm("cons", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "car", .mask = args_unpacker.ArgType.any },
        .{ .name = "cdr", .mask = args_unpacker.ArgType.list },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "cons", body);

        const car = shape.get("car");
        const evaluated_car = try evaluator.evaluate(car, environment);

        const cdr = shape.get("cdr");
        const evaluated_cdr = try evaluator.evaluate(cdr, environment);

        return ast.makeCons(self.allocator, evaluated_car, evaluated_cdr);
    }
}.exec);

pub const Car = MakeSpecialForm("car", struct {
    const unevaluatede_spec = [_]args_unpacker.Arg{
        .{ .name = "unevaluated_arg", .mask = args_unpacker.ArgType.any },
    };
    const spec = [_]args_unpacker.Arg{
        .{ .name = "arg", .mask = args_unpacker.ArgType.list },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const unevaluated_shape = try args_unpacker.unpack(unevaluatede_spec, "car", body);
        const evaluated_arg = try evaluator.evaluate(unevaluated_shape.get("unevaluated_arg"), environment);

        const wrapped_arg = try ast.makeCons(self.allocator, evaluated_arg, ast.makeNil());

        const shape = try args_unpacker.unpack(spec, "car", wrapped_arg);

        const boxed_list = shape.get("arg");
        return switch (boxed_list) {
            .nil => ast.makeNil(),
            .object => res: {
                const cons = ast.unwrapCons(boxed_list) catch unreachable;
                break :res cons.car;
            },
            else => unreachable,
        };
    }
}.exec);

pub const Cdr = MakeSpecialForm("cdr", struct {
    const unevaluatede_spec = [_]args_unpacker.Arg{
        .{ .name = "unevaluated_arg", .mask = args_unpacker.ArgType.any },
    };
    const spec = [_]args_unpacker.Arg{
        .{ .name = "arg", .mask = args_unpacker.ArgType.list },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const unevaluated_shape = try args_unpacker.unpack(unevaluatede_spec, "cdr", body);
        const evaluated_arg = try evaluator.evaluate(unevaluated_shape.get("unevaluated_arg"), environment);

        const wrapped_arg = try ast.makeCons(self.allocator, evaluated_arg, ast.makeNil());

        const shape = try args_unpacker.unpack(spec, "cdr", wrapped_arg);

        const boxed_list = shape.get("arg");
        return switch (boxed_list) {
            .nil => ast.makeNil(),
            .object => res: {
                const cons = ast.unwrapCons(boxed_list) catch unreachable;
                break :res cons.cdr;
            },
            else => unreachable,
        };
    }
}.exec);

pub const Write = MakeSpecialForm("write", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "args", .mask = args_unpacker.ArgType.any, .is_rest = true },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "write", body);

        var args_iter = ListIter.init(shape.get("args"));

        while (args_iter.next(.any)) |node| {
            const evaluated_node = try evaluator.evaluate(node, environment);

            if (ast.isString(evaluated_node)) |string| {
                try evaluator.writer.print("{s}", .{string});
            } else {
                try evaluated_node.repr(self.symbol_table.*, evaluator.writer);
            }
        }

        try evaluator.writer.flush();

        return ast.makeNil();
    }
}.exec);

pub const Print = MakeSpecialForm("print", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "args", .mask = args_unpacker.ArgType.any, .is_rest = true },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "print", body);

        var args_iter = ListIter.init(shape.get("args"));

        while (args_iter.next(.any)) |node| {
            const evaluated_node = try evaluator.evaluate(node, environment);

            if (ast.isString(evaluated_node)) |string| {
                try evaluator.writer.print("{s} ", .{string});
            } else {
                try evaluated_node.repr(self.symbol_table.*, evaluator.writer);
                _ = try evaluator.writer.write(" ");
            }
        }

        _ = try evaluator.writer.write("\n");
        try evaluator.writer.flush();

        return ast.makeNil();
    }
}.exec);

pub const Input = MakeSpecialForm("input", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "prompt", .mask = args_unpacker.ArgType.string },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;
        _ = environment;

        const shape = try args_unpacker.unpack(spec, "input", body);

        const boxed_prompt = shape.get("prompt");
        const prompt = ast.unwrapString(boxed_prompt) catch unreachable;

        _ = try evaluator.writer.write(prompt);
        try evaluator.writer.flush();

        const input = try evaluator.reader.peekDelimiterInclusive('\n');
        evaluator.reader.toss(input.len);

        return ast.makeString(self.allocator, input);
    }
}.exec);

pub const Read = MakeSpecialForm("read", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "prompt", .mask = args_unpacker.ArgType.string },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;
        _ = environment;

        const shape = try args_unpacker.unpack(spec, "read", body);

        const boxed_prompt = shape.get("prompt");
        const prompt = ast.unwrapString(boxed_prompt) catch unreachable;

        _ = try evaluator.writer.write(prompt);
        try evaluator.writer.flush();

        const input = try evaluator.reader.peekDelimiterInclusive('\n');
        evaluator.reader.toss(input.len);

        var lexer = Lexer.init(input);
        var parser = Parser.init(self.allocator, self.allocator, &lexer, self.symbol_table); // todo pass iter allocator

        return parser.parse(.{ .check_dungling_tokens = true });
    }
}.exec);

pub const Symbol = MakeSpecialForm("symbol", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "arg", .mask = args_unpacker.ArgType.string },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;
        _ = environment;
        _ = evaluator;

        const shape = try args_unpacker.unpack(spec, "symbol", body);

        const boxed_arg = shape.get("arg");
        const arg = ast.unwrapString(boxed_arg) catch unreachable;

        return ast.makeSymbol(try self.symbol_table.insert(arg));
    }
}.exec);

pub const Do = MakeSpecialForm("do", struct {
    fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        var iter = ListIter.init(body);
        var result: AstNode = ast.makeNil();

        while (iter.next(.any)) |elem| {
            result = try evaluator.evaluate(elem, environment);
        }

        return result;
    }
}.exec);

pub const Cond = MakeSpecialForm("cond", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "clauses", .mask = args_unpacker.ArgType.any, .is_rest = true },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "cond", body);

        var iter = ListIter.init(shape.get("clauses"));

        while (iter.current != .nil) {
            const cond_expr = iter.next(.any).?;

            if (iter.current == .nil) {
                return try evaluator.evaluate(cond_expr, environment);
            }

            const then_expr = iter.next(.any).?;

            const evaluated_cond = try evaluator.evaluate(cond_expr, environment);

            if (ast.isBoolean(evaluated_cond)) |boolean| {
                if (boolean.get()) {
                    return try evaluator.evaluate(then_expr, environment);
                }
            }
        }

        return ast.makeNil();
    }
}.exec);

pub const Eval = MakeSpecialForm("eval", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "arg", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "eval", body);

        const arg = shape.get("arg");

        const evaluated_arg = try evaluator.evaluate(arg, environment);
        return try evaluator.evaluate(evaluated_arg, environment);
    }
}.exec);

pub const Def = MakeSpecialForm("def", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "args", .mask = args_unpacker.ArgType.any, .is_rest = true, .require_even = true },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "def", body);
        const args = shape.get("args");

        if (ast.isNil(body) != null) return error.TooFewArguments;

        var iter = ListIter.init(args);

        while (iter.current != .nil) {
            const boxed_symbol = iter.next(.symbol) orelse return error.ArgShouldBeSymbol; // TODO
            const boxed_value = iter.next(.any).?;

            const symbol = try ast.unwrapSymbol(boxed_symbol);
            const value = try evaluator.evaluate(boxed_value, environment);

            try environment.def(symbol, value);
        }

        return ast.makeNil();
    }
}.exec);

pub const Set = MakeSpecialForm("set!", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "args", .mask = args_unpacker.ArgType.any, .is_rest = true, .require_even = true },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "set!", body);
        const args = shape.get("args");

        if (ast.isNil(body) != null) return error.TooFewArguments;

        var iter = ListIter.init(args);

        while (iter.current != .nil) {
            const boxed_symbol = iter.next(.symbol) orelse return error.ArgShouldBeSymbol; // TODO
            const boxed_value = iter.next(.any).?;

            const symbol = try ast.unwrapSymbol(boxed_symbol);
            const value = try evaluator.evaluate(boxed_value, environment);

            try environment.set(symbol, value);
        }

        return ast.makeNil();
    }
}.exec);

pub const Lambda = MakeSpecialForm("lambda", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "args", .mask = args_unpacker.ArgType.list },
        .{ .name = "body", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;
        _ = evaluator;

        const shape = try args_unpacker.unpack(spec, "lambda", body);

        const args = shape.get("args");
        const body_ = shape.get("body");

        return try ast.makeLambda(self.allocator, args, body_, environment);
    }
}.exec);

pub const Dambda = MakeSpecialForm("dambda", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "args", .mask = args_unpacker.ArgType.list },
        .{ .name = "body", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;
        _ = environment;
        _ = evaluator;

        const shape = try args_unpacker.unpack(spec, "dambda", body);

        const args = shape.get("args");
        const body_ = shape.get("body");

        return try ast.makeDambda(self.allocator, args, body_);
    }
}.exec);

pub const Macro = MakeSpecialForm("macro", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "args", .mask = args_unpacker.ArgType.list },
        .{ .name = "body", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;
        _ = environment;
        _ = evaluator;

        const shape = try args_unpacker.unpack(spec, "dambda", body);

        const args = shape.get("args");
        const body_ = shape.get("body");

        return try ast.makeMacro(self.allocator, args, body_);
    }
}.exec);
