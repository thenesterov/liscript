const std = @import("std");
const Io = std.Io;

pub const ast = @import("ast.zig");
pub const SymbolTable = @import("symbol_table.zig").SymbolTable;

const lexer = @import("lexer.zig");

pub const Span = lexer.Span;
pub const Lexer = lexer.Lexer;
pub const Parser = @import("parser.zig").Parser;

pub fn evaluate(command: []const u8) []const u8 {
    return command;
}
