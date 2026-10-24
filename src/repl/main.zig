const std = @import("std");

const Io = std.Io;

const str = @import("str");
const liscript = @import("liscript");
const isocline = @import("isocline");

const errors = @import("errors.zig");

const EvaluatorContext = liscript.EvaluatorContext;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    const runtime_arena = init.arena.allocator();

    try setupIsocline(allocator);

    var iter_arena: std.heap.ArenaAllocator = .init(allocator);
    defer iter_arena.deinit();

    var context: EvaluatorContext = undefined;
    try context.init(io, &iter_arena, runtime_arena);
    defer context.deinit();

    const evaluator = liscript.Evaluator.init(&context);

    while (try readline(allocator)) |input| {
        defer std.c.free(input.ptr);
        if (isPromptEmpty(input)) continue;

        _ = iter_arena.reset(.retain_capacity);
        const arena = iter_arena.allocator();

        var stdout = Io.Writer.Allocating.init(arena);
        var parser = try context.parser(arena, input);

        const parsed = parser.parse(.{ .check_dungling_tokens = true }) catch |err| {
            try errors.handleError(arena, err, parser.lexer.getSpan());
            continue;
        };

        const result = evaluator.evaluate(parsed, &context.environment) catch |err| {
            try errors.handleError(arena, err, parser.lexer.getSpan());
            continue;
        };

        if (liscript.ast.isNil(result) != null) continue;

        try result.repr(context.symbol_table, &stdout.writer);
        const repr = stdout.written();

        try isocline.printf(allocator, "{s}\n", .{repr});
        try context.environment.def(context.symbols.last_result, result);
    }

    try isocline.printf(allocator, "\n[b]toodles![/b]\n", .{});
}

fn setupIsocline(allocator: std.mem.Allocator) !void {
    try isocline.setHistory(allocator, ".liscript_history", 2048);
    isocline.highlight.enableLispHighlight();
}

fn readline(allocator: std.mem.Allocator) !?[:0]u8 {
    return try isocline.readline(allocator, "");
}

fn isPromptEmpty(prompt: [:0]u8) bool {
    const trimmed_prompt = std.mem.trim(u8, prompt, " \t\n\r");
    return str.eql(trimmed_prompt, "");
}
