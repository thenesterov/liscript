const std = @import("std");
const Io = std.Io;

pub const ast = @import("ast.zig");
pub const SymbolTable = @import("symbol_table.zig").SymbolTable;

pub fn evaluate(command: []const u8) []const u8 {
    return command;
}
