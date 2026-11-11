const std = @import("std");

const Allocator = std.mem.Allocator;

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

    pub fn repr(self: Float, allocator: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{d}", .{self.get()});
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

    pub fn repr(self: Int, allocator: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{d}", .{self.get()});
    }
};

pub const Nil = packed struct {
    bits: u64,

    const TAG: u64 = 0x7FF9 << 48;

    pub fn from() Nil {
        return .{ .bits = TAG };
    }

    pub fn repr(self: Nil, allocator: Allocator) ![]const u8 {
        _ = self;
        _ = allocator;

        return "nil";
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

    pub fn repr(self: Bool, allocator: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "{}", .{self.get()});
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

    pub fn repr(self: Symbol, allocator: Allocator, symbol_table: SymbolTable) ![]const u8 {
        const name = symbol_table.getName(self.getId());

        if (std.mem.indexOfAny(u8, name, " \r\t\\\"") != null) {
            return try std.fmt.allocPrint(allocator, "@\"{s}\"", .{try str.escape(allocator, name)});
        }

        return try std.fmt.allocPrint(allocator, "{s}", .{name});
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

    pub fn repr(self: ObjectPtr, allocator: Allocator, symbol_table: SymbolTable) ![]const u8 {
        const obj = self.getPtr(*const Object);
        return try obj.repr(allocator, symbol_table);
    }
};

pub const Cons = struct {
    car: AstNode,
    cdr: AstNode,

    pub fn repr(self: Cons, allocator: Allocator, symbol_table: SymbolTable) ![]const u8 {
        var repr_list: std.ArrayList(u8) = .empty;
        defer repr_list.deinit(allocator);

        try repr_list.appendSlice(allocator, "(");
        try repr_list.appendSlice(allocator, try self.car.repr(allocator, symbol_table));

        var current_cdr = self.cdr;
        while (current_cdr != .nil) {
            const obj = current_cdr.object.getPtr(*const Object);
            const next_pair = obj.body.cons;

            try repr_list.appendSlice(allocator, " ");
            try repr_list.appendSlice(allocator, try next_pair.car.repr(allocator, symbol_table));

            current_cdr = next_pair.cdr;
        }

        try repr_list.appendSlice(allocator, ")");

        return try repr_list.toOwnedSlice(allocator);
    }
};

pub const Lambda = struct {
    args: AstNode,
    body: AstNode,
    env: *Environment,

    pub fn repr(self: Lambda, allocator: Allocator, symbol_table: SymbolTable) ![]const u8 {
        var repr_list: std.ArrayList(u8) = .empty;
        defer repr_list.deinit(allocator);

        try repr_list.appendSlice(allocator, "(lambda ");

        if (helpers.as(.nil, self.args)) |_| {
            try repr_list.appendSlice(allocator, "()");
        } else {
            try repr_list.appendSlice(allocator, try self.args.repr(allocator, symbol_table));
        }

        try repr_list.appendSlice(allocator, " ");
        try repr_list.appendSlice(allocator, try self.body.repr(allocator, symbol_table));
        try repr_list.appendSlice(allocator, ")");

        return try repr_list.toOwnedSlice(allocator);
    }
};

pub const Dambda = struct {
    args: AstNode,
    body: AstNode,

    pub fn repr(self: Dambda, allocator: Allocator, symbol_table: SymbolTable) ![]const u8 {
        var repr_list: std.ArrayList(u8) = .empty;
        defer repr_list.deinit(allocator);

        try repr_list.appendSlice(allocator, "(dambda ");

        if (helpers.as(.nil, self.args)) |_| {
            try repr_list.appendSlice(allocator, "()");
        } else {
            try repr_list.appendSlice(allocator, try self.args.repr(allocator, symbol_table));
        }

        try repr_list.appendSlice(allocator, " ");
        try repr_list.appendSlice(allocator, try self.body.repr(allocator, symbol_table));
        try repr_list.appendSlice(allocator, ")");

        return try repr_list.toOwnedSlice(allocator);
    }
};

pub const Racro = struct {
    args: AstNode,
    body: AstNode,

    pub fn repr(self: Racro, allocator: Allocator, symbol_table: SymbolTable) ![]const u8 {
        var repr_list: std.ArrayList(u8) = .empty;
        defer repr_list.deinit(allocator);

        try repr_list.appendSlice(allocator, "(racro ");

        if (helpers.as(.nil, self.args)) |_| {
            try repr_list.appendSlice(allocator, "()");
        } else {
            try repr_list.appendSlice(allocator, try self.args.repr(allocator, symbol_table));
        }

        try repr_list.appendSlice(allocator, " ");
        try repr_list.appendSlice(allocator, try self.body.repr(allocator, symbol_table));
        try repr_list.appendSlice(allocator, ")");

        return try repr_list.toOwnedSlice(allocator);
    }
};

pub const TailCall = struct {
    expr: AstNode,
    env: *Environment,

    pub fn repr(self: TailCall, allocator: Allocator, symbol_table: SymbolTable) ![]const u8 {
        _ = self;
        _ = allocator;
        _ = symbol_table;

        return "<tail-call>";
    }
};

pub const Object = struct {
    body: union(enum) {
        cons: Cons,
        string: []const u8,
        lambda: Lambda,
        dambda: Dambda,
        racro: Racro,
        tail_call: TailCall,
    },

    pub fn repr(self: Object, allocator: Allocator, symbol_table: SymbolTable) ![]const u8 {
        return switch (self.body) {
            .string => |string| res: {
                break :res std.fmt.allocPrint(allocator, "\"{s}\"", .{try str.escape(allocator, string)});
            },
            inline else => |obj| try obj.repr(allocator, symbol_table),
        };
    }
};

pub const Builtin = union(enum) {
    operator: Operator,
    predicate: Predicate,
    special_form: SpecialForm,

    pub fn repr(self: Builtin, allocator: Allocator) ![]const u8 {
        return switch (self) {
            inline else => |builtin| std.fmt.allocPrint(allocator, "{s}", .{builtin.repr}),
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
                    .tail_call => {},
                }
                allocator.destroy(object_ptr);
            },
            else => {},
        }
    }

    pub fn repr(self: AstNode, allocator: Allocator, symbol_table: SymbolTable) Allocator.Error![]const u8 {
        return switch (self) {
            .symbol => |sym| try sym.repr(allocator, symbol_table),
            .object => |obj_ptr| try obj_ptr.repr(allocator, symbol_table),
            inline else => |*x| try x.repr(allocator),
        };
    }
};
