const std = @import("std");

const str = @import("str");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const symbol_table = @import("symbol_table.zig");

const Allocator = std.mem.Allocator;
const AstNode = ast.AstNode;
const Lexer = lexer.Lexer;
const LexerError = lexer.LexerError;
const StrError = str.StrError;
const SymbolTable = symbol_table.SymbolTable;

pub const ParserError = error{
    ExpectedEof,
    UnexpectedToken,
    IncorrectNumberFormat,
    MissingOpeningParenthesis,
    MissingClosingParenthesis,
};

const ParseOptions = struct {
    check_dungling_tokens: bool = false,
};

pub const Parser = struct {
    allocator: Allocator,
    runtime_allocator: Allocator,

    lexer: *Lexer,
    symbol_table: *SymbolTable,

    pub fn init(allocator: Allocator, runtime_allocator: Allocator, lexer_: *Lexer, symbol_table_: *SymbolTable) Parser {
        return .{ .allocator = allocator, .runtime_allocator = runtime_allocator, .lexer = lexer_, .symbol_table = symbol_table_ };
    }

    pub fn parse(self: *Parser, opts: ParseOptions) (LexerError || ParserError || StrError || Allocator.Error)!AstNode {
        const token = try self.lexer.nextToken();

        const parsed = switch (token) {
            .l_paren => try self.parseList(),
            .string => |string| res: {
                const unescaped_string = try str.unescape(self.allocator, string);
                break :res try ast.makeObject(self.runtime_allocator, .string, unescaped_string);
            },
            .integer => |integer| res: {
                const parsed_int = std.fmt.parseInt(i32, integer, 10) catch return ParserError.IncorrectNumberFormat;
                break :res ast.make(.int, parsed_int);
            },
            .float => |float| res: {
                const parsed_float = std.fmt.parseFloat(f64, float) catch return ParserError.IncorrectNumberFormat;
                break :res ast.make(.float, parsed_float);
            },
            .quoted_symbol => |quoted_symbol| res: {
                const symbol = try self.symbol_table.insert(quoted_symbol);
                break :res ast.make(.symbol, symbol);
            },
            .identifier => |identifier| res: {
                if (str.eql(identifier, "true")) return ast.make(.bool, true);
                if (str.eql(identifier, "false")) return ast.make(.bool, false);
                if (str.eql(identifier, "nil")) return ast.nil;

                const symbol = try self.symbol_table.insert(identifier);
                break :res ast.make(.symbol, symbol);
            },
            .quote => res: {
                const symbol = try self.symbol_table.insert("quote");
                const quote_symbol = ast.make(.symbol, symbol);

                const quoted_expr = try self.parse(.{});

                const args = try ast.makeObject(self.runtime_allocator, .cons, .{ .car = quoted_expr, .cdr = ast.nil });
                break :res try ast.makeObject(self.runtime_allocator, .cons, .{ .car = quote_symbol, .cdr = args });
            },

            .r_paren => ParserError.MissingOpeningParenthesis,
            .eof => ParserError.ExpectedEof,
        };

        if (opts.check_dungling_tokens) {
            const dungling_token = try self.lexer.peekToken();
            switch (dungling_token) {
                .eof => {},
                .r_paren => return ParserError.MissingOpeningParenthesis,
                else => return ParserError.UnexpectedToken,
            }
        }

        return parsed;
    }

    fn parseList(self: *Parser) !AstNode {
        var nodes: std.ArrayList(AstNode) = .empty;
        errdefer {
            for (nodes.items) |item| item.deinit(self.runtime_allocator);
            nodes.deinit(self.runtime_allocator);
        }

        while (true) {
            const next_token = try self.lexer.peekToken();

            switch (next_token) {
                .r_paren => {
                    _ = try self.lexer.nextToken();
                    break;
                },
                .eof => return ParserError.MissingClosingParenthesis,
                else => {
                    const item = try self.parse(.{});
                    try nodes.append(self.runtime_allocator, item);
                },
            }
        }

        defer nodes.deinit(self.runtime_allocator);

        var current_tail = ast.nil;

        if (nodes.items.len > 0) {
            var i = nodes.items.len;
            while (i > 0) {
                i -= 1;
                const head_element = nodes.items[i];
                current_tail = try ast.makeObject(self.runtime_allocator, .cons, .{ .car = head_element, .cdr = current_tail });
            }
        }
        return current_tail;
    }
};
