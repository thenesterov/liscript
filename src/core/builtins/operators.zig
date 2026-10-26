const std = @import("std");

const ast = @import("../ast.zig");
const evaluator_ = @import("../evaluator.zig");

const SymbolTable = @import("../symbol_table.zig").SymbolTable;
const Environment = @import("../environment.zig").Environment;
const Evaluator = evaluator_.Evaluator;
const EvaluatorError = evaluator_.EvaluatorError;

const Symbol = ast.Symbol;
const AstNode = ast.AstNode;
const Object = ast.Object;

pub const OperatorError = error{
    CannotAddNonNumber,
    CannotAddIntWithNonNumber,
    CannotAddFloatWithNonNumber,

    CannotSubNonNumber,
    CannotSubIntWithNonNumber,
    CannotSubFloatWithNonNumber,

    CannotMulNonNumber,
    CannotMulIntWithNonNumber,
    CannotMulFloatWithNonNumber,

    ZeroDivision,
    CannotDivNonNumber,
    CannotDivIntWithNonNumber,
    CannotDivFloatWithNonNumber,

    CannotModNonNumber,
    CannotModIntWithNonNumber,
    CannotModFloatWithNonNumber,

    CannotConcatWithNonString,
};

pub const Operator = struct {
    ptr: *const anyopaque,
    repr: []const u8,
    exec_fn: *const fn (ptr: *const anyopaque, evaluator: *Evaluator, a: AstNode, b: AstNode) anyerror!AstNode,
};

pub const Add = struct {
    pub const repr = "+";

    symbol: Symbol,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Add {
        _ = allocator;
        const symbol = try symbol_table.insert(Add.repr);
        return .{ .symbol = symbol };
    }

    pub fn operator(self: *const Add) Operator {
        return .{ .ptr = self, .repr = Add.repr, .exec_fn = Add.exec };
    }

    pub inline fn register(self: *Add, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .operator = self.operator() } });
    }

    pub fn exec(ptr: *const anyopaque, evaluator: *Evaluator, a: AstNode, b: AstNode) !AstNode {
        _ = ptr;
        return switch (a) {
            .int => |a_int| switch (b) {
                .int => |b_int| ast.make(.int, a_int.get() + b_int.get()),
                .float => |b_float| ast.make(.float, @as(f64, @floatFromInt(a_int.get())) + b_float.get()),
                else => evaluator.context.fail(
                    EvaluatorError.TypeError,
                    "cannot add '{s}' and '{s}'",
                    .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
                ),
            },
            .float => |a_float| switch (b) {
                .int => |b_int| ast.make(.float, a_float.get() + @as(f64, @floatFromInt(b_int.get()))),
                .float => |b_float| ast.make(.float, a_float.get() + b_float.get()),
                else => evaluator.context.fail(
                    EvaluatorError.TypeError,
                    "cannot add '{s}' and '{s}'",
                    .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
                ),
            },
            else => return evaluator.context.fail(
                EvaluatorError.TypeError,
                "cannot add '{s}' and '{s}'",
                .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
            ),
        };
    }
};

pub const Sub = struct {
    pub const repr = "-";

    symbol: Symbol,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Sub {
        _ = allocator;
        const symbol = try symbol_table.insert(Sub.repr);
        return .{ .symbol = symbol };
    }

    pub fn operator(self: *const Sub) Operator {
        return .{ .ptr = self, .repr = Sub.repr, .exec_fn = Sub.exec };
    }

    pub inline fn register(self: *Sub, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .operator = self.operator() } });
    }

    pub fn exec(ptr: *const anyopaque, evaluator: *Evaluator, a: AstNode, b: AstNode) !AstNode {
        _ = ptr;
        return switch (a) {
            .int => |a_int| switch (b) {
                .int => |b_int| ast.make(.int, a_int.get() - b_int.get()),
                .float => |b_float| ast.make(.float, @as(f64, @floatFromInt(a_int.get())) - b_float.get()),
                else => evaluator.context.fail(
                    EvaluatorError.TypeError,
                    "cannot subtract '{s}' and '{s}'",
                    .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
                ),
            },
            .float => |a_float| switch (b) {
                .int => |b_int| ast.make(.float, a_float.get() - @as(f64, @floatFromInt(b_int.get()))),
                .float => |b_float| ast.make(.float, a_float.get() - b_float.get()),
                else => evaluator.context.fail(
                    EvaluatorError.TypeError,
                    "cannot subtract '{s}' and '{s}'",
                    .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
                ),
            },
            else => evaluator.context.fail(
                EvaluatorError.TypeError,
                "cannot subtract '{s}' and '{s}'",
                .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
            ),
        };
    }
};

pub const Mul = struct {
    pub const repr = "*";

    symbol: Symbol,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Mul {
        _ = allocator;
        const symbol = try symbol_table.insert(Mul.repr);
        return .{ .symbol = symbol };
    }

    pub fn operator(self: *const Mul) Operator {
        return .{ .ptr = self, .repr = Mul.repr, .exec_fn = Mul.exec };
    }

    pub inline fn register(self: *Mul, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .operator = self.operator() } });
    }

    pub fn exec(ptr: *const anyopaque, evaluator: *Evaluator, a: AstNode, b: AstNode) !AstNode {
        _ = ptr;
        return switch (a) {
            .int => |a_int| switch (b) {
                .int => |b_int| ast.make(.int, a_int.get() * b_int.get()),
                .float => |b_float| ast.make(.float, @as(f64, @floatFromInt(a_int.get())) * b_float.get()),
                else => evaluator.context.fail(
                    EvaluatorError.TypeError,
                    "cannot multiply '{s}' and '{s}'",
                    .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
                ),
            },
            .float => |a_float| switch (b) {
                .int => |b_int| ast.make(.float, a_float.get() * @as(f64, @floatFromInt(b_int.get()))),
                .float => |b_float| ast.make(.float, a_float.get() * b_float.get()),
                else => evaluator.context.fail(
                    EvaluatorError.TypeError,
                    "cannot multiply '{s}' and '{s}'",
                    .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
                ),
            },
            else => return evaluator.context.fail(
                EvaluatorError.TypeError,
                "cannot multiply '{s}' and '{s}'",
                .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
            ),
        };
    }
};

pub const Div = struct {
    pub const repr = "/";

    symbol: Symbol,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Div {
        _ = allocator;
        const symbol = try symbol_table.insert(Div.repr);
        return .{ .symbol = symbol };
    }

    pub fn operator(self: *const Div) Operator {
        return .{ .ptr = self, .repr = Div.repr, .exec_fn = Div.exec };
    }

    pub inline fn register(self: *Div, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .operator = self.operator() } });
    }

    pub fn exec(ptr: *const anyopaque, evaluator: *Evaluator, a: AstNode, b: AstNode) !AstNode {
        _ = ptr;
        return switch (a) {
            .int => |a_int| switch (b) {
                .int => |b_int| res: {
                    if (b_int.get() == 0) return evaluator.context.fail(EvaluatorError.ZeroDivisionError, "division by zero", .{});
                    break :res ast.make(.int, @divFloor(a_int.get(), b_int.get()));
                },
                .float => |b_float| res: {
                    if (b_float.get() == 0) return evaluator.context.fail(EvaluatorError.ZeroDivisionError, "division by zero", .{});
                    break :res ast.make(.float, @as(f64, @floatFromInt(a_int.get())) / b_float.get());
                },
                else => evaluator.context.fail(
                    EvaluatorError.TypeError,
                    "cannot divide '{s}' and '{s}'",
                    .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
                ),
            },
            .float => |a_float| switch (b) {
                .int => |b_int| res: {
                    if (b_int.get() == 0) return evaluator.context.fail(EvaluatorError.ZeroDivisionError, "division by zero", .{});
                    break :res ast.make(.float, a_float.get() / @as(f64, @floatFromInt(b_int.get())));
                },
                .float => |b_float| res: {
                    if (b_float.get() == 0) return evaluator.context.fail(EvaluatorError.ZeroDivisionError, "division by zero", .{});
                    break :res ast.make(.float, a_float.get() / b_float.get());
                },
                else => evaluator.context.fail(
                    EvaluatorError.TypeError,
                    "cannot divide '{s}' and '{s}'",
                    .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
                ),
            },
            else => return evaluator.context.fail(
                EvaluatorError.TypeError,
                "cannot divide '{s}' and '{s}'",
                .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
            ),
        };
    }
};

pub const Mod = struct {
    pub const repr = "%";

    symbol: Symbol,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Mod {
        _ = allocator;
        const symbol = try symbol_table.insert(Mod.repr);
        return .{ .symbol = symbol };
    }

    pub fn operator(self: *const Mod) Operator {
        return .{ .ptr = self, .repr = Mod.repr, .exec_fn = Mod.exec };
    }

    pub inline fn register(self: *Mod, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .operator = self.operator() } });
    }

    pub fn exec(ptr: *const anyopaque, evaluator: *Evaluator, a: AstNode, b: AstNode) !AstNode {
        _ = ptr;
        return switch (a) {
            .int => |a_int| switch (b) {
                .int => |b_int| ast.make(.int, @mod(a_int.get(), b_int.get())),
                .float => |b_float| ast.make(.float, @as(f64, try std.math.mod(f64, a_int.get(), b_float.get()))),
                else => evaluator.context.fail(
                    EvaluatorError.TypeError,
                    "cannot modulo '{s}' and '{s}'",
                    .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
                ),
            },
            .float => |a_float| switch (b) {
                .int => |b_int| ast.make(.float, try std.math.mod(f64, a_float.get(), @as(f64, @floatFromInt(b_int.get())))),
                .float => |b_float| ast.make(.float, try std.math.mod(f64, a_float.get(), b_float.get())),
                else => evaluator.context.fail(
                    EvaluatorError.TypeError,
                    "cannot modulo '{s}' and '{s}'",
                    .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
                ),
            },
            else => return evaluator.context.fail(
                EvaluatorError.TypeError,
                "cannot modulo '{s}' and '{s}'",
                .{ ast.nodeTypeName(a), ast.nodeTypeName(b) },
            ),
        };
    }
};

pub const Concat = struct {
    pub const repr = "++";

    symbol: Symbol,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Concat {
        const symbol = try symbol_table.insert(Concat.repr);
        return .{ .symbol = symbol, .allocator = allocator };
    }

    pub fn operator(self: *const Concat) Operator {
        return .{ .ptr = self, .repr = Concat.repr, .exec_fn = Concat.exec };
    }

    pub inline fn register(self: *Concat, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .operator = self.operator() } });
    }

    pub fn exec(ptr: *const anyopaque, evaluator: *Evaluator, a: AstNode, b: AstNode) !AstNode {
        _ = evaluator;

        const self: *const Concat = @ptrCast(@alignCast(ptr));

        const a_string = ast.unwrapObject(.string, a) catch return OperatorError.CannotConcatWithNonString;
        const b_string = ast.unwrapObject(.string, b) catch return OperatorError.CannotConcatWithNonString;

        return ast.makeObject(self.allocator, .string, try std.mem.concat(self.allocator, u8, &[_][]const u8{ a_string, b_string }));
    }
};
