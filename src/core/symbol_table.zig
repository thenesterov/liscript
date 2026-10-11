const std = @import("std");
const ast = @import("ast.zig");
const Symbol = ast.Symbol;

pub const SymbolTable = struct {
    string_to_id: std.StringHashMapUnmanaged(u32) = .empty,
    id_to_string: std.ArrayListUnmanaged([]const u8) = .empty,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SymbolTable {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *SymbolTable) void {
        for (self.id_to_string.items) |str| {
            self.allocator.free(str);
        }
        self.id_to_string.deinit(self.allocator);
        self.string_to_id.deinit(self.allocator);
    }

    pub fn insert(self: *SymbolTable, name: []const u8) !Symbol {
        if (self.string_to_id.get(name)) |id| {
            return Symbol.fromId(id);
        }

        const new_id: u32 = @intCast(self.id_to_string.items.len);

        const name_copy = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_copy);

        try self.string_to_id.put(self.allocator, name_copy, new_id);
        try self.id_to_string.append(self.allocator, name_copy);

        return Symbol.fromId(new_id);
    }

    pub fn getName(self: SymbolTable, id: u32) []const u8 {
        std.debug.assert(id < self.id_to_string.items.len);
        return self.id_to_string.items[id];
    }
};
