const std = @import("std");

const str = @import("str");

const helpers = @import("helpers.zig");
const Operator = @import("../builtins/operators.zig").Operator;
const Predicate = @import("../builtins/predicates.zig").Predicate;
const SpecialForm = @import("../builtins/special_forms.zig").SpecialForm;
const Environment = @import("../environment.zig").Environment;
const SymbolTable = @import("../symbol_table.zig").SymbolTable;

pub const Float = packed struct {
    bits: u64,

    pub fn from(f: f64) Float {
        return .{ .bits = @bitCast(f) };
    }

    pub fn get(self: Float) f64 {
        return @bitCast(self.bits);
    }

    pub fn repr(self: Float, writer: *std.Io.Writer) !void {
        try writer.print("{d}", .{self.get()});
    }
};

pub const Int = packed struct {
    bits: u64,

    const TAG: u64 = 0x7FF8 << 48;

    pub fn from(i: i32) Int {
        const int_i64 = @as(i64, i);
        const int_u64 = @as(u64, @bitCast(int_i64));

        return .{ .bits = TAG | int_u64 };
    }

    pub fn get(self: Int) i32 {
        return @bitCast(@as(u32, @truncate(self.bits)));
    }

    pub fn repr(self: Int, writer: *std.Io.Writer) !void {
        try writer.print("{d}", .{self.get()});
    }
};

pub const Nil = packed struct {
    bits: u64,

    const TAG: u64 = 0x7FF9 << 48;

    pub fn from() Nil {
        return .{ .bits = TAG };
    }

    pub fn repr(self: Nil, writer: *std.Io.Writer) !void {
        _ = self;
        try writer.print("nil", .{});
    }
};

pub const Bool = packed struct {
    bits: u64,

    const TAG: u64 = 0x7FFA << 48;

    pub fn from(b: bool) Bool {
        const bool_u64: u64 = if (b) 1 else 0;
        return .{ .bits = TAG | bool_u64 };
    }

    pub fn get(self: Bool) bool {
        return (self.bits & 1) == 1;
    }

    pub fn repr(self: Bool, writer: *std.Io.Writer) !void {
        try writer.print("{}", .{self.get()});
    }
};

pub const Symbol = packed struct {
    bits: u64,

    const TAG: u64 = 0x7FFB << 48;

    pub fn fromId(id: u32) Symbol {
        return .{ .bits = TAG | id };
    }

    pub fn getId(self: Symbol) u32 {
        return @truncate(self.bits);
    }

    pub fn repr(self: Symbol, symbol_table: SymbolTable, writer: *std.Io.Writer) !void {
        const name = symbol_table.getName(self.getId());
        if (std.mem.indexOfAny(u8, name, " \r\t\\\"") != null) {
            try writer.print("@\"", .{});
            try str.escape(name, writer);
            try writer.print("\"", .{});
        } else {
            try writer.print("{s}", .{name});
        }
    }
};

pub const ObjectPtr = packed struct {
    bits: u64,

    const TAG: u64 = 0x7FFC << 48;
    const MASK: u64 = 0x0000FFFFFFFFFFFF;

    pub fn fromPtr(ptr: anytype) ObjectPtr {
        const addr = @intFromPtr(ptr);
        return .{ .bits = TAG | (addr & MASK) };
    }

    pub fn getPtr(self: ObjectPtr, comptime T: type) T {
        return @ptrFromInt(self.bits & MASK);
    }

    pub fn repr(self: ObjectPtr, symbol_table: SymbolTable, writer: *std.Io.Writer) !void {
        const obj = self.getPtr(*const Object);
        try obj.repr(symbol_table, writer);
    }
};

pub const Cons = struct {
    car: AstNode,
    cdr: AstNode,

    pub fn repr(self: Cons, symbol_table: SymbolTable, writer: *std.Io.Writer) !void {
        try writer.print("(", .{});
        try self.car.repr(symbol_table, writer);

        var current_cdr = self.cdr;
        while (current_cdr != .nil) {
            const obj = current_cdr.object.getPtr(*const Object);
            const next_pair = obj.body.cons;

            try writer.print(" ", .{});
            try next_pair.car.repr(symbol_table, writer);

            current_cdr = next_pair.cdr;
        }

        try writer.print(")", .{});
    }
};

pub const Lambda = struct {
    args: AstNode,
    body: AstNode,
    env: *Environment,

    pub fn repr(self: Lambda, symbol_table: SymbolTable, writer: *std.Io.Writer) !void {
        try writer.print("(lambda ", .{});

        if (helpers.as(.nil, self.args)) |_| {
            try writer.print("()", .{});
        } else {
            try self.args.repr(symbol_table, writer);
        }
        try writer.print(" ", .{});
        try self.body.repr(symbol_table, writer);
        try writer.print(")", .{});
    }
};

pub const Dambda = struct {
    args: AstNode,
    body: AstNode,

    pub fn repr(self: Dambda, symbol_table: SymbolTable, writer: *std.Io.Writer) !void {
        try writer.print("(dambda ", .{});

        if (helpers.as(.nil, self.args)) |_| {
            try writer.print("()", .{});
        } else {
            try self.args.repr(symbol_table, writer);
        }
        try writer.print(" ", .{});
        try self.body.repr(symbol_table, writer);
        try writer.print(")", .{});
    }
};

pub const Racro = struct {
    args: AstNode,
    body: AstNode,

    pub fn repr(self: Racro, symbol_table: SymbolTable, writer: *std.Io.Writer) !void {
        try writer.print("(racro ", .{});

        if (helpers.as(.nil, self.args)) |_| {
            try writer.print("()", .{});
        } else {
            try self.args.repr(symbol_table, writer);
        }
        try writer.print(" ", .{});
        try self.body.repr(symbol_table, writer);
        try writer.print(")", .{});
    }
};

pub const Object = struct {
    body: union(enum) {
        cons: Cons,
        string: []const u8,
        lambda: Lambda,
        dambda: Dambda,
        racro: Racro,
    },

    pub fn repr(self: Object, symbol_table: SymbolTable, writer: *std.Io.Writer) !void {
        return switch (self.body) {
            .string => |string| {
                try writer.print("\"", .{});
                try str.escape(string, writer);
                try writer.print("\"", .{});
            },
            inline else => |obj| obj.repr(symbol_table, writer),
        };
    }
};

pub const Builtin = union(enum) {
    operator: Operator,
    predicate: Predicate,
    special_form: SpecialForm,

    pub fn repr(self: Builtin, writer: *std.Io.Writer) !void {
        return switch (self) {
            inline else => |builtin| writer.print("{s}", .{builtin.repr}),
        };
    }
};

pub const AstNode = union(enum) {
    float: Float,
    int: Int,
    nil: Nil,
    bool: Bool,
    symbol: Symbol,
    object: ObjectPtr,
    builtin: Builtin,

    pub fn deinit(self: AstNode, allocator: std.mem.Allocator) void {
        switch (self) {
            .object => |object| {
                const object_ptr = object.getPtr(*const Object);
                switch (object_ptr.body) {
                    .cons => |cons| {
                        cons.cdr.deinit(allocator);
                        cons.car.deinit(allocator);
                    },
                    .string => |string| allocator.free(string),
                    inline .lambda, .dambda, .racro => |*sf| {
                        sf.args.deinit(allocator);
                        sf.body.deinit(allocator);
                    },
                }
                allocator.destroy(object_ptr);
            },
            else => {},
        }
    }

    pub fn repr(self: AstNode, symbol_table: SymbolTable, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .symbol => |sym| try sym.repr(symbol_table, writer),
            .object => |obj_ptr| try obj_ptr.repr(symbol_table, writer),
            inline else => |*x| try x.repr(writer),
        }
    }
};
