const std = @import("std");

const ast = @import("ast.zig");

const SymbolTable = @import("symbol_table.zig").SymbolTable;
const Environment = @import("environment.zig").Environment;

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
    exec_fn: *const fn (ptr: *const anyopaque, a: AstNode, b: AstNode) anyerror!AstNode,
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

    pub inline fn register(self: Add, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .operator = self.operator() } });
    }

    pub fn exec(ptr: *const anyopaque, a: AstNode, b: AstNode) !AstNode {
        _ = ptr;
        return switch (a) {
            .int => |a_int| switch (b) {
                .int => |b_int| ast.makeInt(a_int.get() + b_int.get()),
                .float => |b_float| ast.makeFloat(@as(f64, @floatFromInt(a_int.get())) + b_float.get()),
                else => OperatorError.CannotAddIntWithNonNumber,
            },
            .float => |a_float| switch (b) {
                .int => |b_int| ast.makeFloat(a_float.get() + @as(f64, @floatFromInt(b_int.get()))),
                .float => |b_float| ast.makeFloat(a_float.get() + b_float.get()),
                else => OperatorError.CannotAddFloatWithNonNumber,
            },
            else => return OperatorError.CannotAddNonNumber,
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

    pub inline fn register(self: Sub, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .operator = self.operator() } });
    }

    pub fn exec(ptr: *const anyopaque, a: AstNode, b: AstNode) !AstNode {
        _ = ptr;
        return switch (a) {
            .int => |a_int| switch (b) {
                .int => |b_int| ast.makeInt(a_int.get() - b_int.get()),
                .float => |b_float| ast.makeFloat(@as(f64, @floatFromInt(a_int.get())) - b_float.get()),
                else => OperatorError.CannotSubIntWithNonNumber,
            },
            .float => |a_float| switch (b) {
                .int => |b_int| ast.makeFloat(a_float.get() - @as(f64, @floatFromInt(b_int.get()))),
                .float => |b_float| ast.makeFloat(a_float.get() - b_float.get()),
                else => OperatorError.CannotSubFloatWithNonNumber,
            },
            else => return OperatorError.CannotSubNonNumber,
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

    pub inline fn register(self: Mul, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .operator = self.operator() } });
    }

    pub fn exec(ptr: *const anyopaque, a: AstNode, b: AstNode) !AstNode {
        _ = ptr;
        return switch (a) {
            .int => |a_int| switch (b) {
                .int => |b_int| ast.makeInt(a_int.get() * b_int.get()),
                .float => |b_float| ast.makeFloat(@as(f64, @floatFromInt(a_int.get())) * b_float.get()),
                else => OperatorError.CannotMulIntWithNonNumber,
            },
            .float => |a_float| switch (b) {
                .int => |b_int| ast.makeFloat(a_float.get() * @as(f64, @floatFromInt(b_int.get()))),
                .float => |b_float| ast.makeFloat(a_float.get() * b_float.get()),
                else => OperatorError.CannotMulFloatWithNonNumber,
            },
            else => return OperatorError.CannotMulNonNumber,
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

    pub inline fn register(self: Div, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .operator = self.operator() } });
    }

    pub fn exec(ptr: *const anyopaque, a: AstNode, b: AstNode) !AstNode {
        _ = ptr;
        return switch (a) {
            .int => |a_int| switch (b) {
                .int => |b_int| res: {
                    if (b_int.get() == 0) return OperatorError.ZeroDivision;
                    break :res ast.makeInt(@divFloor(a_int.get(), b_int.get()));
                },
                .float => |b_float| res: {
                    if (b_float.get() == 0) return OperatorError.ZeroDivision;
                    break :res ast.makeFloat(@as(f64, @floatFromInt(a_int.get())) / b_float.get());
                },
                else => OperatorError.CannotDivIntWithNonNumber,
            },
            .float => |a_float| switch (b) {
                .int => |b_int| res: {
                    if (b_int.get() == 0) return OperatorError.ZeroDivision;
                    break :res ast.makeFloat(a_float.get() / @as(f64, @floatFromInt(b_int.get())));
                },
                .float => |b_float| res: {
                    if (b_float.get() == 0) return OperatorError.ZeroDivision;
                    break :res ast.makeFloat(a_float.get() / b_float.get());
                },
                else => OperatorError.CannotDivFloatWithNonNumber,
            },
            else => return OperatorError.CannotDivNonNumber,
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

    pub inline fn register(self: Mod, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .operator = self.operator() } });
    }

    pub fn exec(ptr: *const anyopaque, a: AstNode, b: AstNode) !AstNode {
        _ = ptr;
        return switch (a) {
            .int => |a_int| switch (b) {
                .int => |b_int| ast.makeInt(@mod(a_int.get(), b_int.get())),
                .float => |b_float| ast.makeFloat(@as(f64, try std.math.mod(f64, a_int.get(), b_float.get()))),
                else => OperatorError.CannotModIntWithNonNumber,
            },
            .float => |a_float| switch (b) {
                .int => |b_int| ast.makeFloat(try std.math.mod(f64, a_float.get(), @as(f64, @floatFromInt(b_int.get())))),
                .float => |b_float| ast.makeFloat(try std.math.mod(f64, a_float.get(), b_float.get())),
                else => OperatorError.CannotModFloatWithNonNumber,
            },
            else => return OperatorError.CannotModNonNumber,
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

    pub inline fn register(self: Concat, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .operator = self.operator() } });
    }

    pub fn exec(ptr: *const anyopaque, a: AstNode, b: AstNode) !AstNode {
        const self: *const Concat = @ptrCast(@alignCast(ptr));

        const a_string = ast.unwrapString(a) catch return OperatorError.CannotConcatWithNonString;
        const b_string = ast.unwrapString(b) catch return OperatorError.CannotConcatWithNonString;

        return ast.makeString(self.allocator, try std.mem.concat(self.allocator, u8, &[_][]const u8{ a_string, b_string }));
    }
};
