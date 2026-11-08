const std = @import("std");

const ast = @import("ast.zig");

const Symbol = ast.Symbol;
const AstNode = ast.AstNode;

pub const EnvironmentError = error{
    SymbolUndefined,
};

pub const Environment = struct {
    const LocalBinding = struct {
        id: u32,
        value: AstNode,
    };

    map: std.AutoHashMap(u32, AstNode),
    list: std.ArrayList(LocalBinding),

    global: *Environment,
    parent: ?*Environment,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, parent: ?*Environment) Environment {
        var env = Environment{
            .map = if (parent == null)
                std.AutoHashMap(u32, AstNode).init(allocator)
            else
                undefined,
            .list = .empty,
            .global = undefined,
            .parent = parent,
            .allocator = allocator,
        };

        if (parent) |parent_env| {
            env.global = parent_env.global;
        }

        return env;
    }

    pub fn deinit(self: *Environment) void {
        if (self.parent == null) {
            self.map.deinit();
        }
        self.list.deinit(self.allocator);
    }

    pub inline fn def(self: *Environment, symbol: Symbol, value: AstNode) !void {
        const id = symbol.getId();
        if (self.parent != null) {
            try self.list.append(self.allocator, .{ .id = id, .value = value });
        } else {
            try self.map.put(id, value);
        }
    }

    pub inline fn set(self: *Environment, symbol: Symbol, value: AstNode) !void {
        const id = symbol.getId();
        var current_env = self;

        lookup: while (true) {
            if (current_env.parent) |parent_env| {
                var i: usize = current_env.list.items.len;
                while (i > 0) {
                    i -= 1;
                    if (current_env.list.items[i].id == id) {
                        current_env.list.items[i].value = value;
                        return;
                    }
                }
                current_env = parent_env;
            } else {
                if (current_env.map.get(id)) |_| {
                    try current_env.map.put(id, value);
                    return;
                }
                break :lookup;
            }
        }

        return EnvironmentError.SymbolUndefined;
    }

    pub inline fn get(self: *Environment, symbol: Symbol) AstNode {
        const id = symbol.getId();
        var current_env: ?*Environment = self;

        while (current_env) |env| {
            if (env.parent) |_| {
                var i: usize = env.list.items.len;
                while (i > 0) {
                    i -= 1;
                    if (env.list.items[i].id == id) {
                        return env.list.items[i].value;
                    }
                }
                current_env = env.parent;
            } else {
                if (env.map.get(id)) |value| return value;
                break;
            }
        }

        return ast.make(.symbol, symbol);
    }
};
