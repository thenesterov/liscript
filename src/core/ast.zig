const std = @import("std");

const str = @import("str");

const SymbolTable = @import("symbol_table.zig").SymbolTable;
const Operator = @import("operators.zig").Operator;
const Predicate = @import("predicates.zig").Predicate;
const SpecialForm = @import("special_forms.zig").SpecialForm;
const Environment = @import("environment.zig").Environment;

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
};

pub const Lambda = struct {
    args: AstNode,
    body: AstNode,
    env: *Environment,
};

pub const Dambda = struct {
    args: AstNode,
    body: AstNode,
};

pub const Object = struct {
    body: union(enum) {
        cons: Cons,
        string: []const u8,
        lambda: Lambda,
        dambda: Dambda,
    },

    pub fn repr(self: Object, symbol_table: SymbolTable, writer: *std.Io.Writer) !void {
        switch (self.body) {
            .string => |string| {
                try writer.print("\"", .{});
                try str.escape(string, writer);
                try writer.print("\"", .{});
            },

            .cons => |pair| {
                try writer.print("(", .{});
                try pair.car.repr(symbol_table, writer);

                var current_cdr = pair.cdr;
                while (current_cdr != .nil) {
                    const obj = current_cdr.object.getPtr(*const Object);
                    const next_pair = obj.body.cons;

                    try writer.print(" ", .{});
                    try next_pair.car.repr(symbol_table, writer);

                    current_cdr = next_pair.cdr;
                }

                try writer.print(")", .{});
            },
            .lambda => |lambda| {
                try writer.print("(lambda ", .{});

                if (isNil(lambda.args)) |_| {
                    try writer.print("()", .{});
                } else {
                    try lambda.args.repr(symbol_table, writer);
                }
                try writer.print(" ", .{});
                try lambda.body.repr(symbol_table, writer);
                try writer.print(")", .{});
            },
            .dambda => |dambda| {
                try writer.print("(dambda ", .{});

                if (isNil(dambda.args)) |_| {
                    try writer.print("()", .{});
                } else {
                    try dambda.args.repr(symbol_table, writer);
                }
                try writer.print(" ", .{});
                try dambda.body.repr(symbol_table, writer);
                try writer.print(")", .{});
            },
        }
    }
};

pub const Builtin = union(enum) {
    operator: Operator,
    predicate: Predicate,
    special_form: SpecialForm,

    pub fn repr(self: Builtin, writer: *std.Io.Writer) !void {
        return switch (self) {
            .operator => |operator| try writer.print("{s}", .{operator.repr}),
            .predicate => |predicate| try writer.print("{s}", .{predicate.repr}),
            .special_form => |special_form| try writer.print("{s}", .{special_form.repr}),
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
                    .lambda => |lambda| {
                        lambda.args.deinit(allocator);
                        lambda.body.deinit(allocator);
                    },
                    .dambda => |dambda| {
                        dambda.args.deinit(allocator);
                        dambda.body.deinit(allocator);
                    },
                }
                allocator.destroy(object_ptr);
            },
            else => {},
        }
    }

    pub fn repr(self: AstNode, symbol_table: SymbolTable, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .int => |i| try i.repr(writer),
            .float => |f| try f.repr(writer),
            .nil => |n| try n.repr(writer),
            .bool => |b| try b.repr(writer),
            .symbol => |sym| try sym.repr(symbol_table, writer),
            .object => |obj_ptr| try obj_ptr.repr(symbol_table, writer),
            .builtin => |builtin| try builtin.repr(writer),
        }
    }
};

pub fn makeFloat(f: f64) AstNode {
    return AstNode{ .float = Float.from(f) };
}

pub fn makeInt(i: i32) AstNode {
    return AstNode{ .int = Int.from(i) };
}

pub fn makeNil() AstNode {
    return AstNode{ .nil = Nil.from() };
}

pub fn makeCons(allocator: std.mem.Allocator, car: AstNode, cdr: AstNode) !AstNode {
    const obj = try allocator.create(Object);
    obj.* = .{ .body = .{ .cons = .{
        .car = car,
        .cdr = cdr,
    } } };
    return AstNode{ .object = ObjectPtr.fromPtr(obj) };
}

pub fn makeBool(b: bool) AstNode {
    return AstNode{ .bool = Bool.from(b) };
}

pub fn makeSymbol(symbol: Symbol) AstNode {
    return AstNode{ .symbol = symbol };
}

pub fn makeString(allocator: std.mem.Allocator, string: []const u8) !AstNode {
    const obj = try allocator.create(Object);
    obj.* = .{ .body = .{ .string = string } };
    return AstNode{ .object = ObjectPtr.fromPtr(obj) };
}

pub fn makeLambda(allocator: std.mem.Allocator, args: AstNode, body: AstNode, environment: *Environment) !AstNode {
    const obj = try allocator.create(Object);
    obj.* = .{ .body = .{ .lambda = .{ .args = args, .body = body, .env = environment } } };
    return AstNode{ .object = ObjectPtr.fromPtr(obj) };
}

pub fn makeDambda(allocator: std.mem.Allocator, args: AstNode, body: AstNode) !AstNode {
    const obj = try allocator.create(Object);
    obj.* = .{ .body = .{ .dambda = .{ .args = args, .body = body } } };
    return AstNode{ .object = ObjectPtr.fromPtr(obj) };
}

pub fn isNil(node: AstNode) ?Nil {
    return switch (node) {
        .nil => |nil| nil,
        else => null,
    };
}

pub fn isCons(node: AstNode) ?Cons {
    return switch (node) {
        .object => |object| res: {
            const object_ptr = object.getPtr(*const Object);
            break :res switch (object_ptr.body) {
                .cons => |cons| cons,
                else => null,
            };
        },
        else => null,
    };
}

pub fn isConsNode(node: AstNode) ?AstNode {
    return switch (node) {
        .object => |object| res: {
            const object_ptr = object.getPtr(*const Object);
            break :res switch (object_ptr.body) {
                .cons => node,
                else => null,
            };
        },
        else => null,
    };
}

pub fn isString(node: AstNode) ?[]const u8 {
    return switch (node) {
        .object => |object| res: {
            const object_ptr = object.getPtr(*const Object);
            break :res switch (object_ptr.body) {
                .string => |string| string,
                else => null,
            };
        },
        else => null,
    };
}

pub fn isLambda(node: AstNode) ?Lambda {
    return switch (node) {
        .object => |object| res: {
            const object_ptr = object.getPtr(*const Object);
            break :res switch (object_ptr.body) {
                .lambda => |lambda| lambda,
                else => null,
            };
        },
        else => null,
    };
}

pub fn isDambda(node: AstNode) ?Dambda {
    return switch (node) {
        .object => |object| res: {
            const object_ptr = object.getPtr(*const Object);
            break :res switch (object_ptr.body) {
                .dambda => |dambda| dambda,
                else => null,
            };
        },
        else => null,
    };
}

pub fn unwrapFloat(node: AstNode) !Float {
    return switch (node) {
        .float => |float| float,
        else => error.IsNotFloat,
    };
}

pub fn unwrapInt(node: AstNode) !Int {
    return switch (node) {
        .int => |int| int,
        else => error.IsNotInt,
    };
}

pub fn unwrapBool(node: AstNode) !Bool {
    return switch (node) {
        .bool => |boolean| boolean,
        else => error.IsNotBool,
    };
}

pub fn unwrapString(node: AstNode) ![]const u8 {
    return switch (node) {
        .object => |object| res: {
            const object_ptr = object.getPtr(*const Object);
            break :res switch (object_ptr.body) {
                .string => |string| string,
                else => error.IsNotString,
            };
        },
        else => error.IsNotString,
    };
}

pub fn unwrapCons(node: AstNode) !Cons {
    if (isCons(node)) |cons| return cons;
    return error.IsNotCons;
}

pub fn unwrapSymbol(node: AstNode) !Symbol {
    return switch (node) {
        .symbol => |symbol| symbol,
        else => error.IsNotSymbol,
    };
}
