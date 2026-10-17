const std = @import("std");

const str = @import("str");
const liscript = @import("liscript");
const isocline = @import("isocline");

const errors = @import("errors.zig");

const Io = std.Io;
const Lexer = liscript.Lexer;
const Parser = liscript.Parser;
const SymbolTable = liscript.SymbolTable;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    try isocline.set_history(allocator, ".liscript_history", 2048);

    var iter_arena = std.heap.ArenaAllocator.init(allocator);
    defer iter_arena.deinit();

    var symbol_table = SymbolTable.init(allocator);
    defer symbol_table.deinit();

    while (try isocline.readline(allocator, "")) |input| {
        defer std.c.free(input.ptr);

        _ = iter_arena.reset(.retain_capacity);
        const arena = iter_arena.allocator();

        const prompt = std.mem.trim(u8, input, " \t\n\r");
        if (str.eql(prompt, "")) continue;

        var stdout = Io.Writer.Allocating.init(arena);

        var lexer = Lexer.init(prompt);
        var parser = Parser.init(arena, &lexer, &symbol_table);

        const parsed = parser.parse(.{ .check_dungling_tokens = true }) catch |err| {
            try errors.handleError(arena, err, lexer.getSpan());
            continue;
        };

        try parsed.repr(symbol_table, &stdout.writer);
        const repr = stdout.written();

        try isocline.printf(allocator, "{s}\n", .{repr});
    }

    try isocline.printf(allocator, "\n[b]toodles![/b]\n", .{});
}
