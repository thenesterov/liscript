const std = @import("std");

const ast = @import("../ast.zig");
const predicates = @import("../builtins/predicates.zig");
const args_unpacker = @import("../helpers/args_unpacker.zig");

const SymbolTable = @import("../symbol_table.zig").SymbolTable;
const Environment = @import("../environment.zig").Environment;
const Evaluator = @import("../evaluator.zig").Evaluator;
const EvaluatorError = @import("../evaluator.zig").EvaluatorError;
const Lexer = @import("../lexer.zig").Lexer;
const Parser = @import("../parser.zig").Parser;
const ListIter = @import("../helpers/list_iter.zig").ListIterator;

const SymbolNode = ast.Symbol;
const AstNode = ast.AstNode;
const Object = ast.Object;

pub const SpecialForm = struct {
    ptr: *const anyopaque,
    repr: []const u8,
    exec_fn: *const fn (ptr: *const anyopaque, environment: *Environment, evaluator: *Evaluator, body: AstNode) anyerror!AstNode,
};

pub fn MakeSpecialForm(comptime name: []const u8, comptime body_fn: anytype) type {
    return struct {
        pub const repr = name;
        symbol: SymbolNode,

        pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !@This() {
            _ = allocator;
            return .{ .symbol = try symbol_table.insert(@This().repr) };
        }

        pub fn specialForm(self: *const @This()) SpecialForm {
            return .{ .ptr = self, .repr = @This().repr, .exec_fn = @This().exec };
        }

        pub inline fn register(self: *const @This(), environment: *Environment) !void {
            try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
        }

        fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: *Evaluator, body: AstNode) anyerror!AstNode {
            const self: *const @This() = @ptrCast(@alignCast(ptr));
            return try body_fn(self, environment, evaluator, body);
        }
    };
}

pub const Quote = MakeSpecialForm("quote", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "arg", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;
        _ = environment;

        const shape = try args_unpacker.unpack(spec, "quote", evaluator.context, body);

        return shape.get("arg");
    }
}.exec);

pub const TypeOf = MakeSpecialForm("typeof", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "arg", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const runtime_allocator = evaluator.context.runtime_allocator;

        const shape = try args_unpacker.unpack(spec, "typeof", evaluator.context, body);

        const arg = shape.get("arg");
        const evaluated_arg = try evaluator.evaluate(arg, environment);

        const type_str = switch (evaluated_arg) {
            .object => if (ast.asObject(.cons, evaluated_arg) != null) "list" else "string",
            else => |node| @tagName(node),
        };

        return ast.makeObject(runtime_allocator, .string, type_str);
    }
}.exec);

pub const Cons = MakeSpecialForm("cons", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "car", .mask = args_unpacker.ArgType.any },
        .{ .name = "cdr", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const runtime_allocator = evaluator.context.runtime_allocator;

        const shape = try args_unpacker.unpack(spec, "cons", evaluator.context, body);

        const car = shape.get("car");
        const evaluated_car = try evaluator.evaluate(car, environment);

        const cdr = shape.get("cdr");
        const evaluated_cdr = try evaluator.evaluate(cdr, environment);

        if (ast.asObject(.cons, evaluated_cdr) == null and ast.as(.nil, evaluated_cdr) == null) {
            return evaluator.context.fail(
                EvaluatorError.TypeError,
                "argument 'cdr' expected cons or nil, got '{s}'",
                .{ast.nodeTypeName(evaluated_cdr)},
            );
        }

        return ast.makeObject(runtime_allocator, .cons, .{ .car = evaluated_car, .cdr = evaluated_cdr });
    }
}.exec);

pub const Car = MakeSpecialForm("car", struct {
    const unevaluatede_spec = [_]args_unpacker.Arg{
        .{ .name = "unevaluated_arg", .mask = args_unpacker.ArgType.any },
    };
    const spec = [_]args_unpacker.Arg{
        .{ .name = "arg", .mask = args_unpacker.ArgType.list },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const runtime_allocator = evaluator.context.runtime_allocator;

        const unevaluated_shape = try args_unpacker.unpack(unevaluatede_spec, "car", evaluator.context, body);
        const evaluated_arg = try evaluator.evaluate(unevaluated_shape.get("unevaluated_arg"), environment);

        const wrapped_arg = try ast.makeObject(runtime_allocator, .cons, .{ .car = evaluated_arg, .cdr = ast.nil });

        const shape = try args_unpacker.unpack(spec, "car", evaluator.context, wrapped_arg);

        const boxed_list = shape.get("arg");
        return switch (boxed_list) {
            .nil => ast.nil,
            .object => res: {
                const cons = ast.unwrapObject(.cons, boxed_list) catch unreachable;
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

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const runtime_allocator = evaluator.context.runtime_allocator;

        const unevaluated_shape = try args_unpacker.unpack(unevaluatede_spec, "cdr", evaluator.context, body);
        const evaluated_arg = try evaluator.evaluate(unevaluated_shape.get("unevaluated_arg"), environment);

        const wrapped_arg = try ast.makeObject(runtime_allocator, .cons, .{ .car = evaluated_arg, .cdr = ast.nil });

        const shape = try args_unpacker.unpack(spec, "cdr", evaluator.context, wrapped_arg);

        const boxed_list = shape.get("arg");
        return switch (boxed_list) {
            .nil => ast.nil,
            .object => res: {
                const cons = ast.unwrapObject(.cons, boxed_list) catch unreachable;
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

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const writer = evaluator.context.io.writer();
        const symbol_table = evaluator.context.symbol_table;

        const shape = try args_unpacker.unpack(spec, "write", evaluator.context, body);
        var args_iter = ListIter.init(shape.get("args"));

        while (args_iter.next(.any)) |node| {
            const evaluated_node = try evaluator.evaluate(node, environment);

            if (ast.asObject(.string, evaluated_node)) |string| {
                try writer.print("{s}", .{string});
            } else {
                const repr = try evaluated_node.repr(evaluator.context.runtime_allocator, symbol_table);
                try writer.print("{s}", .{repr});
            }
        }

        try writer.flush();

        return ast.nil;
    }
}.exec);

pub const Print = MakeSpecialForm("print", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "args", .mask = args_unpacker.ArgType.any, .is_rest = true },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const writer = evaluator.context.io.writer();
        const symbol_table = evaluator.context.symbol_table;

        const shape = try args_unpacker.unpack(spec, "print", evaluator.context, body);

        var args_iter = ListIter.init(shape.get("args"));

        while (args_iter.next(.any)) |node| {
            const evaluated_node = try evaluator.evaluate(node, environment);

            if (ast.asObject(.string, evaluated_node)) |string| {
                try writer.print("{s} ", .{string});
            } else {
                const repr = try evaluated_node.repr(evaluator.context.runtime_allocator, symbol_table);
                try writer.print("{s} ", .{repr});
            }
        }

        _ = try writer.write("\n");
        try writer.flush();

        return ast.nil;
    }
}.exec);

pub const Input = MakeSpecialForm("input", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "prompt", .mask = args_unpacker.ArgType.string },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;
        _ = environment;

        const writer = evaluator.context.io.writer();
        const reader = evaluator.context.io.reader();
        const runtime_allocator = evaluator.context.runtime_allocator;

        const shape = try args_unpacker.unpack(spec, "input", evaluator.context, body);

        const boxed_prompt = shape.get("prompt");
        const prompt = ast.unwrapObject(.string, boxed_prompt) catch unreachable;

        _ = try writer.write(prompt);
        try writer.flush();

        const input = try reader.peekDelimiterInclusive('\n');
        reader.toss(input.len);

        return ast.makeObject(runtime_allocator, .string, input);
    }
}.exec);

pub const Read = MakeSpecialForm("read", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "prompt", .mask = args_unpacker.ArgType.string },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;
        _ = environment;

        const writer = evaluator.context.io.writer();
        const reader = evaluator.context.io.reader();
        const iter_arena = evaluator.context.iter_allocator.allocator();

        const shape = try args_unpacker.unpack(spec, "read", evaluator.context, body);

        const boxed_prompt = shape.get("prompt");
        const prompt = ast.unwrapObject(.string, boxed_prompt) catch unreachable;

        _ = try writer.write(prompt);
        try writer.flush();

        const input = try reader.peekDelimiterInclusive('\n');
        reader.toss(input.len);

        var parser = try evaluator.context.parser(iter_arena, input);

        return parser.parse(.{ .check_dungling_tokens = true });
    }
}.exec);

pub const Symbol = MakeSpecialForm("symbol", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "arg", .mask = args_unpacker.ArgType.string },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;
        _ = environment;

        const symbol_table = &evaluator.context.symbol_table;

        const shape = try args_unpacker.unpack(spec, "symbol", evaluator.context, body);

        const boxed_arg = shape.get("arg");
        const arg = ast.unwrapObject(.string, boxed_arg) catch unreachable;

        return ast.make(.symbol, try symbol_table.insert(arg));
    }
}.exec);

pub const Do = MakeSpecialForm("do", struct {
    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        var iter = ListIter.init(body);
        var result: AstNode = ast.nil;

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

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "cond", evaluator.context, body);

        var iter = ListIter.init(shape.get("clauses"));

        while (iter.current != .nil) {
            const cond_expr = iter.next(.any).?;

            if (iter.current == .nil) {
                return try evaluator.evaluate(cond_expr, environment);
            }

            const then_expr = iter.next(.any).?;

            const evaluated_cond = try evaluator.evaluate(cond_expr, environment);

            if (ast.as(.bool, evaluated_cond)) |boolean| {
                if (boolean.get()) {
                    return try evaluator.evaluate(then_expr, environment);
                }
            } else {
                return evaluator.context.fail(EvaluatorError.TypeError, "condition must be a boolean, got '{s}'", .{ast.nodeTypeName(evaluated_cond)});
            }
        }

        return ast.nil;
    }
}.exec);

pub const Eval = MakeSpecialForm("eval", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "arg", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "eval", evaluator.context, body);

        const arg = shape.get("arg");

        const evaluated_arg = try evaluator.evaluate(arg, environment);
        return try evaluator.evaluate(evaluated_arg, environment);
    }
}.exec);

pub const Def = MakeSpecialForm("def", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "args", .mask = args_unpacker.ArgType.any, .is_rest = true, .require_even = true },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "def", evaluator.context, body);
        const args = shape.get("args");

        if (ast.as(.nil, body) != null) return evaluator.context.fail(EvaluatorError.TypeError, "'def' expects at least one symbol and one value", .{});

        var iter = ListIter.init(args);

        while (iter.current != .nil) {
            const boxed_symbol = iter.next(.symbol) orelse {
                if (ast.asObject(.cons, iter.current)) |cons| {
                    return evaluator.context.fail(
                        EvaluatorError.TypeError,
                        "'def' expected a symbol for the name, got '{s}'",
                        .{ast.nodeTypeName(cons.car)},
                    );
                } else {
                    return evaluator.context.fail(
                        EvaluatorError.TypeError,
                        "'def' expected a symbol for the name, got '{s}'",
                        .{ast.nodeTypeName(iter.current)},
                    );
                }
            };

            const boxed_value = iter.next(.any).?;

            const symbol = try ast.unwrap(.symbol, boxed_symbol);
            const value = try evaluator.evaluate(boxed_value, environment);

            try environment.def(symbol, value);
        }

        return ast.nil;
    }
}.exec);

pub const Set = MakeSpecialForm("set!", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "args", .mask = args_unpacker.ArgType.any, .is_rest = true, .require_even = true },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "set!", evaluator.context, body);
        const args = shape.get("args");

        if (ast.as(.nil, body) != null) return evaluator.context.fail(EvaluatorError.TypeError, "'set!' expects at least one symbol and one value", .{});

        var iter = ListIter.init(args);

        while (iter.current != .nil) {
            const boxed_symbol = iter.next(.symbol) orelse {
                if (ast.asObject(.cons, iter.current)) |cons| {
                    return evaluator.context.fail(
                        EvaluatorError.TypeError,
                        "'set!' expected a symbol for the name, got '{s}'",
                        .{ast.nodeTypeName(cons.car)},
                    );
                } else {
                    return evaluator.context.fail(
                        EvaluatorError.TypeError,
                        "'set!' expected a symbol for the name, got '{s}'",
                        .{ast.nodeTypeName(iter.current)},
                    );
                }
            };
            const boxed_value = iter.next(.any).?;

            const symbol = try ast.unwrap(.symbol, boxed_symbol);
            const value = try evaluator.evaluate(boxed_value, environment);

            environment.set(symbol, value) catch {
                return evaluator.context.fail(
                    EvaluatorError.NameError,
                    "name '{s}' is not defined",
                    .{evaluator.context.symbol_table.getName(symbol.getId())},
                );
            };
        }

        return ast.nil;
    }
}.exec);

pub const Lambda = MakeSpecialForm("lambda", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "args", .mask = args_unpacker.ArgType.list },
        .{ .name = "body", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const runtime_allocator = evaluator.context.runtime_allocator;

        const shape = try args_unpacker.unpack(spec, "lambda", evaluator.context, body);

        const args = shape.get("args");
        const body_ = shape.get("body");

        return try ast.makeObject(runtime_allocator, .lambda, .{ .args = args, .body = body_, .env = environment });
    }
}.exec);

pub const Dambda = MakeSpecialForm("dambda", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "args", .mask = args_unpacker.ArgType.list },
        .{ .name = "body", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;
        _ = environment;

        const runtime_allocator = evaluator.context.runtime_allocator;

        const shape = try args_unpacker.unpack(spec, "dambda", evaluator.context, body);

        const args = shape.get("args");
        const body_ = shape.get("body");

        return try ast.makeObject(runtime_allocator, .dambda, .{ .args = args, .body = body_ });
    }
}.exec);

pub const Racro = MakeSpecialForm("racro", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "args", .mask = args_unpacker.ArgType.list },
        .{ .name = "body", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;
        _ = environment;

        const runtime_allocator = evaluator.context.runtime_allocator;

        const shape = try args_unpacker.unpack(spec, "racro", evaluator.context, body);

        const args = shape.get("args");
        const body_ = shape.get("body");

        return try ast.makeObject(runtime_allocator, .racro, .{ .args = args, .body = body_ });
    }
}.exec);

pub const Load = MakeSpecialForm("load", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "path", .mask = args_unpacker.ArgType.string },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "load", evaluator.context, body);

        const boxed_path = shape.get("path");
        const path = ast.unwrapObject(.string, boxed_path) catch unreachable;

        const io = evaluator.context.io.io;
        const iter_allocator = evaluator.context.iter_allocator.allocator();

        const content = std.Io.Dir.cwd().readFileAlloc(
            io,
            path,
            iter_allocator,
            .limited(10 * 1024 * 1024),
        ) catch |err| {
            return evaluator.context.fail(
                EvaluatorError.RuntimeError,
                "could not load file '{s}': {s}",
                .{ path, @errorName(err) },
            );
        };
        defer iter_allocator.free(content);

        var parser = try evaluator.context.parser(iter_allocator, content);

        var last_result: AstNode = ast.nil;

        while (true) {
            const expr = parser.parse(.{}) catch |err| {
                if (err == error.ExpectedEof) break;

                return evaluator.context.fail(
                    EvaluatorError.RuntimeError,
                    "parse error in '{s}': {s}",
                    .{ path, @errorName(err) },
                );
            };

            last_result = evaluator.evaluate(expr, environment) catch |err| {
                return err;
            };
        }

        return last_result;
    }
}.exec);

pub const Error = MakeSpecialForm("error", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "message", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "error", evaluator.context, body);

        const boxed_message = try evaluator.evaluate(shape.get("message"), environment);
        const message = ast.unwrapObject(.string, boxed_message) catch
            return evaluator.context.fail(
                EvaluatorError.TypeError,
                "argument 'message' expected string, got '{s}'",
                .{ast.nodeTypeName(boxed_message)},
            );

        evaluator.context.last_error_message = try std.mem.concat(
            evaluator.context.runtime_allocator,
            u8,
            &[_][]const u8{ "RuntimeError: ", message },
        );
        return EvaluatorError.RuntimeError;
    }
}.exec);

pub const Assert = MakeSpecialForm("assert", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "value", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "assert", evaluator.context, body);

        const boxed_value = try evaluator.evaluate(shape.get("value"), environment);
        const value = ast.unwrap(.bool, boxed_value) catch return evaluator.context.fail(
            EvaluatorError.AssertionError,
            "expected truthy value, got '{s}'",
            .{try boxed_value.repr(evaluator.context.runtime_allocator, evaluator.context.symbol_table)},
        );

        if (!value.get()) {
            return evaluator.context.fail(EvaluatorError.AssertionError, "expected truthy value, got 'false'", .{});
        }

        return ast.nil;
    }
}.exec);

pub const AssertEq = MakeSpecialForm("assert-eq", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "expected", .mask = args_unpacker.ArgType.any },
        .{ .name = "actual", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "assert-eq", evaluator.context, body);

        const expected = try evaluator.evaluate(shape.get("expected"), environment);
        const actual = try evaluator.evaluate(shape.get("actual"), environment);

        const equal_pr = predicates.Equal.init(evaluator.context.runtime_allocator, &evaluator.context.symbol_table);
        const boxed_compare_result = try predicates.Equal.exec(&equal_pr, evaluator, expected, actual);
        const compare_result = ast.unwrap(.bool, boxed_compare_result) catch unreachable;

        if (!compare_result.get()) {
            return evaluator.context.fail(
                EvaluatorError.AssertionError,
                "values are not equal\n  expected: {s}\n  actual:   {s}",
                .{
                    try expected.repr(evaluator.context.runtime_allocator, evaluator.context.symbol_table),
                    try actual.repr(evaluator.context.runtime_allocator, evaluator.context.symbol_table),
                },
            );
        }

        return ast.nil;
    }
}.exec);

pub const AssertError = MakeSpecialForm("assert-error", struct {
    const spec = [_]args_unpacker.Arg{
        .{ .name = "value", .mask = args_unpacker.ArgType.any },
    };

    pub fn exec(self: anytype, environment: *Environment, evaluator: *Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        const shape = try args_unpacker.unpack(spec, "assert-error", evaluator.context, body);

        const boxed_value = evaluator.evaluate(shape.get("value"), environment) catch return ast.nil;

        return evaluator.context.fail(
            EvaluatorError.AssertionError,
            "expected error, got '{s}'",
            .{try boxed_value.repr(evaluator.context.runtime_allocator, evaluator.context.symbol_table)},
        );
    }
}.exec);
