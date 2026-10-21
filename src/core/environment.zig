const std = @import("std");

const ast = @import("ast.zig");

const Symbol = ast.Symbol;
const AstNode = ast.AstNode;

pub const EnvironmentError = error{
    SymbolUndefined,
};

pub const Environment = struct {
    map: std.AutoHashMap(Symbol, AstNode),
    global: *Environment,
    parent: ?*Environment,

    pub fn init(allocator: std.mem.Allocator, parent: ?*Environment) Environment {
        var env = Environment{ .map = std.AutoHashMap(Symbol, AstNode).init(allocator), .global = undefined, .parent = parent };

        if (parent) |parent_env| {
            env.global = parent_env.global;
        }

        return env;
    }

    pub fn deinit(self: *Environment) void {
        self.map.deinit();
    }

    pub inline fn def(self: *Environment, symbol: Symbol, value: AstNode) !void {
        try self.map.put(symbol, value);
    }

    pub inline fn set(self: *Environment, symbol: Symbol, value: AstNode) !void {
        var current_env = self;
        var symbol_updated = false;

        while (true) {
            if (current_env.map.get(symbol)) |_| {
                try current_env.map.put(symbol, value);
                symbol_updated = true;
                break;
            }

            if (current_env.parent) |parent_env| {
                current_env = parent_env;
            } else {
                break;
            }
        }

        if (!symbol_updated) return EnvironmentError.SymbolUndefined;
    }

    pub inline fn get(self: *Environment, symbol: Symbol) AstNode {
        if (self.map.get(symbol)) |value| return value;
        if (self.global.map.get(symbol)) |value| return value;

        var current_env = self.parent;

        while (current_env) |env| {
            if (env.map.get(symbol)) |value| return value;
            current_env = env.parent;
        }

        return ast.makeSymbol(symbol);
    }
};
