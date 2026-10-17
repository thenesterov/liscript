const isocline = @import("isocline");

const Allocator = @import("std").mem.Allocator;
const Span = @import("liscript").Span;

const ErrorDetails = struct {
    message: []const u8,
    note: ?[]const u8 = null,
};

fn drawErrorPath(allocator: Allocator, col: usize) !void {
    for (0..col + 1) |_| {
        try isocline.printf(allocator, "[sienna]~[/]", .{});
    }
    try isocline.printf(allocator, "[sienna]^\n[/]", .{});
}

fn printError(allocator: Allocator, details: ErrorDetails, span: Span) !void {
    try drawErrorPath(allocator, span.col);
    try isocline.printf(allocator, "[firebrick]{s} at line {d}, col {d}.[/]\n", .{ details.message, span.row, span.col });

    if (details.note) |note| {
        try isocline.printf(allocator, "[steelblue]note: {s}[/]\n\n", .{note});
    } else {
        try isocline.printf(allocator, "\n", .{});
    }
}

pub fn handleError(allocator: Allocator, err: anyerror, span: Span) !void {
    switch (err) {
        error.ExpectedEof => {},
        error.InvalidEscapeSequence => try printError(allocator, .{
            .message = "Syntax error: invalid escape sequence",
            .note = "only 'n', 't', 'r', '\\' and '\"' symbols can be escaped",
        }, span),
        error.UnexpectedToken => try printError(allocator, .{
            .message = "Syntax error: unexpected token",
        }, span),
        error.UnterminatedString => try printError(allocator, .{
            .message = "Syntax error: string was never closed",
            .note = "add a matching '\"' to close the string literal",
        }, span),
        error.UnexpectedStringTerminator => try printError(allocator, .{
            .message = "Syntax error: unexpected characters after string literal",
            .note = "separate tokens with a whitespace, a newline, or a closing parenthesis",
        }, span),
        error.IncorrectNumberFormat => try printError(allocator, .{
            .message = "Syntax error: incorrect number format",
        }, span),
        error.MissingOpeningParenthesis => try printError(allocator, .{ .message = "Syntax error: ')' has no matching opening parenthesis" }, span),
        error.MissingClosingParenthesis => try printError(allocator, .{
            .message = "Syntax error: '(' has no matching closing parenthesis",
        }, span),
        else => {
            try drawErrorPath(allocator, span.col);
            try isocline.printf(allocator, "[firebrick]Unexpected error: {s}[/]\n\n", .{@errorName(err)});
        },
    }
}
