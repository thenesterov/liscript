const std = @import("std");

const Io = std.Io;

const str = @import("str");
const liscript = @import("liscript");
const isocline = @import("isocline");

const errors = @import("errors.zig");

const Evaluator = liscript.Evaluator;
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

    var evaluator = liscript.Evaluator.init(&context);

    try loadStd(&evaluator, &iter_arena);

    while (try readline(allocator)) |input| {
        defer std.c.free(input.ptr);
        if (isPromptEmpty(input)) continue;

        context.last_error_message = null;
        context.last_error_node = null;

        _ = iter_arena.reset(.retain_capacity);
        const arena = iter_arena.allocator();

        var stdout = Io.Writer.Allocating.init(arena);
        var parser = try context.parser(arena, input);

        const parsed = parser.parse(.{ .check_dungling_tokens = true }) catch |err| {
            try errors.handleSyntaxError(arena, err, parser.lexer.getSpan());
            continue;
        };

        const result = evaluator.evaluate(parsed, &context.environment) catch |err| {
            try errors.handleEvaluateError(arena, err, context, &stdout);
            continue;
        };

        try context.environment.def(context.symbols.last_result, result);
        if (liscript.ast.as(.nil, result) != null) continue;

        try result.repr(context.symbol_table, &stdout.writer);
        const repr = stdout.written();

        try isocline.printf(allocator, "{s}\n", .{repr});
    }

    try isocline.printf(allocator, "\n[b]toodles![/b]\n", .{});
}

fn setupIsocline(allocator: std.mem.Allocator) !void {
    try isocline.setHistory(allocator, ".liscript_history", 2048);
    isocline.highlight.enableLispHighlight();
}

fn readline(allocator: std.mem.Allocator) !?[:0]u8 {
    return try isocline.readline(allocator, "λ");
}

fn isPromptEmpty(prompt: [:0]u8) bool {
    const trimmed_prompt = std.mem.trim(u8, prompt, " \t\n\r");
    return str.eql(trimmed_prompt, "");
}

fn loadStd(evaluator: *Evaluator, iter_arena: *std.heap.ArenaAllocator) !void {
    const arena = iter_arena.allocator();
    var stdout = Io.Writer.Allocating.init(arena);

    const load_expression = "(load \"std/std.ls\")";

    var parser = try evaluator.context.parser(arena, load_expression);
    const parsed = parser.parse(.{ .check_dungling_tokens = true }) catch |err| {
        try errors.handleSyntaxError(arena, err, parser.lexer.getSpan());
        @panic("failed to parse standard library");
    };

    _ = evaluator.evaluate(parsed, &evaluator.context.environment) catch |err| {
        try errors.handleEvaluateError(arena, err, evaluator.context.*, &stdout);
        @panic("failed to load standard library");
    };
}
