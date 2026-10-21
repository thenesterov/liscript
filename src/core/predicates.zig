const std = @import("std");

const str = @import("str");
const ast = @import("ast.zig");

const SymbolTable = @import("symbol_table.zig").SymbolTable;
const Environment = @import("environment.zig").Environment;

const Symbol = ast.Symbol;
const AstNode = ast.AstNode;
const Object = ast.Object;

pub const PredicateError = error{
    CannotCompareNonNumbers,
};

pub const Predicate = struct {
    ptr: *const anyopaque,
    repr: []const u8,
    exec_fn: *const fn (ptr: *const anyopaque, a: AstNode, b: AstNode) anyerror!AstNode,
};

pub const Equal = struct {
    pub const repr = "=";

    symbol: Symbol,

    pub fn init(symbol_table: *SymbolTable) !Equal {
        const symbol = try symbol_table.insert(Equal.repr);
        return .{ .symbol = symbol };
    }

    pub fn predicate(self: *const Equal) Predicate {
        return .{ .ptr = self, .repr = Equal.repr, .exec_fn = Equal.exec };
    }

    pub inline fn register(self: Equal, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .predicate = self.predicate() } });
    }

    pub fn exec(ptr: *const anyopaque, a: AstNode, b: AstNode) !AstNode {
        const result = switch (a) {
            .float => |a_float| switch (b) {
                .float => |b_float| @abs(a_float.get() - b_float.get()) < std.math.floatEps(f64),
                .int => |b_int| @abs(a_float.get() - @as(f64, @floatFromInt(b_int.get()))) < std.math.floatEps(f64),
                else => false,
            },
            .int => |a_int| switch (b) {
                .float => |b_float| @abs(@as(f64, @floatFromInt(a_int.get())) - b_float.get()) < std.math.floatEps(f64),
                .int => |b_int| a_int.get() == b_int.get(),
                else => false,
            },
            .nil => switch (b) {
                .nil => true,
                else => false,
            },
            .bool => |a_bool| switch (b) {
                .bool => |b_bool| a_bool.get() == b_bool.get(),
                else => false,
            },
            .symbol => |a_symbol| switch (b) {
                .symbol => |b_symbol| a_symbol.getId() == b_symbol.getId(),
                else => false,
            },
            .object => |a_object| switch (b) {
                .object => |b_object| res: {
                    const a_object_ptr = a_object.getPtr(*const Object);
                    const b_object_ptr = b_object.getPtr(*const Object);

                    const result = switch (a_object_ptr.body) {
                        .string => |a_string| switch (b_object_ptr.body) {
                            .string => |b_string| str.eql(a_string, b_string),
                            else => false,
                        },
                        .cons => |a_cons| switch (b_object_ptr.body) {
                            .cons => |b_cons| {
                                const car_is_equal = try ast.unwrapBool(try Equal.exec(ptr, a_cons.car, b_cons.car));
                                const cdr_is_equal = try ast.unwrapBool(try Equal.exec(ptr, a_cons.cdr, b_cons.cdr));

                                break :res car_is_equal.get() and cdr_is_equal.get();
                            },
                            else => false,
                        },
                        .lambda => false,
                        .dambda => false,
                        .macro => false,
                    };

                    break :res result;
                },
                else => false,
            },
            else => false,
        };

        return ast.makeBool(result);
    }
};

pub const GreaterThan = struct {
    pub const repr = ">";

    symbol: Symbol,

    pub fn init(symbol_table: *SymbolTable) !GreaterThan {
        const symbol = try symbol_table.insert(GreaterThan.repr);
        return .{ .symbol = symbol };
    }

    pub fn predicate(self: *const GreaterThan) Predicate {
        return .{ .ptr = self, .repr = GreaterThan.repr, .exec_fn = GreaterThan.exec };
    }

    pub inline fn register(self: GreaterThan, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .predicate = self.predicate() } });
    }

    pub fn exec(ptr: *const anyopaque, a: AstNode, b: AstNode) !AstNode {
        _ = ptr;

        const result = switch (a) {
            .int => |a_int| switch (b) {
                .int => |b_int| a_int.get() > b_int.get(),
                .float => |b_float| a_int.get() > b_float.get(),
                else => return PredicateError.CannotCompareNonNumbers,
            },
            .float => |a_float| switch (b) {
                .int => |b_int| a_float.get() > b_int.get(),
                .float => |b_float| a_float.get() > b_float.get(),
                else => return PredicateError.CannotCompareNonNumbers,
            },
            else => return PredicateError.CannotCompareNonNumbers,
        };

        return ast.makeBool(result);
    }
};

pub const GreaterThanEqual = struct {
    pub const repr = ">=";

    symbol: Symbol,

    pub fn init(symbol_table: *SymbolTable) !GreaterThanEqual {
        const symbol = try symbol_table.insert(GreaterThanEqual.repr);
        return .{ .symbol = symbol };
    }

    pub fn predicate(self: *const GreaterThanEqual) Predicate {
        return .{ .ptr = self, .repr = GreaterThanEqual.repr, .exec_fn = GreaterThanEqual.exec };
    }

    pub inline fn register(self: GreaterThanEqual, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .predicate = self.predicate() } });
    }

    pub fn exec(ptr: *const anyopaque, a: AstNode, b: AstNode) !AstNode {
        _ = ptr;

        const result = switch (a) {
            .int => |a_int| switch (b) {
                .int => |b_int| a_int.get() >= b_int.get(),
                .float => |b_float| a_int.get() >= b_float.get(),
                else => return PredicateError.CannotCompareNonNumbers,
            },
            .float => |a_float| switch (b) {
                .int => |b_int| a_float.get() >= b_int.get(),
                .float => |b_float| a_float.get() >= b_float.get(),
                else => return PredicateError.CannotCompareNonNumbers,
            },
            else => return PredicateError.CannotCompareNonNumbers,
        };

        return ast.makeBool(result);
    }
};

pub const LessThan = struct {
    pub const repr = "<";

    symbol: Symbol,

    pub fn init(symbol_table: *SymbolTable) !LessThan {
        const symbol = try symbol_table.insert(LessThan.repr);
        return .{ .symbol = symbol };
    }

    pub fn predicate(self: *const LessThan) Predicate {
        return .{ .ptr = self, .repr = LessThan.repr, .exec_fn = LessThan.exec };
    }

    pub inline fn register(self: LessThan, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .predicate = self.predicate() } });
    }

    pub fn exec(ptr: *const anyopaque, a: AstNode, b: AstNode) !AstNode {
        _ = ptr;

        const result = switch (a) {
            .int => |a_int| switch (b) {
                .int => |b_int| a_int.get() < b_int.get(),
                .float => |b_float| a_int.get() < b_float.get(),
                else => return PredicateError.CannotCompareNonNumbers,
            },
            .float => |a_float| switch (b) {
                .int => |b_int| a_float.get() < b_int.get(),
                .float => |b_float| a_float.get() < b_float.get(),
                else => return PredicateError.CannotCompareNonNumbers,
            },
            else => return PredicateError.CannotCompareNonNumbers,
        };

        return ast.makeBool(result);
    }
};

pub const LessThanEqual = struct {
    pub const repr = "<=";

    symbol: Symbol,

    pub fn init(symbol_table: *SymbolTable) !LessThanEqual {
        const symbol = try symbol_table.insert(LessThanEqual.repr);
        return .{ .symbol = symbol };
    }

    pub fn predicate(self: *const LessThanEqual) Predicate {
        return .{ .ptr = self, .repr = LessThanEqual.repr, .exec_fn = LessThanEqual.exec };
    }

    pub inline fn register(self: LessThanEqual, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .predicate = self.predicate() } });
    }

    pub fn exec(ptr: *const anyopaque, a: AstNode, b: AstNode) !AstNode {
        _ = ptr;

        const result = switch (a) {
            .int => |a_int| switch (b) {
                .int => |b_int| a_int.get() <= b_int.get(),
                .float => |b_float| a_int.get() <= b_float.get(),
                else => return PredicateError.CannotCompareNonNumbers,
            },
            .float => |a_float| switch (b) {
                .int => |b_int| a_float.get() <= b_int.get(),
                .float => |b_float| a_float.get() <= b_float.get(),
                else => return PredicateError.CannotCompareNonNumbers,
            },
            else => return PredicateError.CannotCompareNonNumbers,
        };

        return ast.makeBool(result);
    }
};
