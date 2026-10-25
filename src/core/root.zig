const std = @import("std");
const Io = std.Io;

pub const ast = @import("ast.zig");
pub const SymbolTable = @import("symbol_table.zig").SymbolTable;

const lexer = @import("lexer.zig");
const environment = @import("environment.zig");
pub const operators = @import("builtins/operators.zig");
pub const predicates = @import("builtins/predicates.zig");
pub const special_forms = @import("builtins/special_forms.zig");

pub const Span = lexer.Span;
pub const Lexer = lexer.Lexer;
pub const Parser = @import("parser.zig").Parser;
pub const Environment = environment.Environment;
pub const Evaluator = @import("evaluator.zig").Evaluator;
pub const EvaluatorContext = @import("evaluator/context.zig").EvaluatorContext;

pub fn evaluate(command: []const u8) []const u8 {
    return command;
}
