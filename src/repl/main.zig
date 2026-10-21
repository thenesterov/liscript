const std = @import("std");

const str = @import("str");
const liscript = @import("liscript");
const isocline = @import("isocline");

const errors = @import("errors.zig");

const Io = std.Io;
const Lexer = liscript.Lexer;
const Parser = liscript.Parser;
const SymbolTable = liscript.SymbolTable;
const Environment = liscript.Environment;
const EnvironmentPool = liscript.EnvironmentPool;
const operators = liscript.operators;
const predicates = liscript.predicates;
const special_forms = liscript.special_forms;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    const runtime_arena = init.arena.allocator();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var stdin_buffer: [1024]u8 = undefined;
    var stdin_file_reader: Io.File.Reader = .init(.stdout(), io, &stdin_buffer);
    const stdin_reader = &stdin_file_reader.interface;

    try isocline.set_history(allocator, ".liscript_history", 2048);

    var iter_arena = std.heap.ArenaAllocator.init(allocator);
    defer iter_arena.deinit();

    var symbol_table = SymbolTable.init(allocator);
    defer symbol_table.deinit();

    var environment = Environment.init(runtime_arena, null);
    environment.global = &environment;
    defer environment.deinit();

    const last_result_symbol = try symbol_table.insert("_");

    const add = try operators.Add.init(&symbol_table);
    const sub = try operators.Sub.init(&symbol_table);
    const mul = try operators.Mul.init(&symbol_table);
    const div = try operators.Div.init(&symbol_table);
    const mod = try operators.Mod.init(&symbol_table);
    const concat = try operators.Concat.init(runtime_arena, &symbol_table);

    try add.register(&environment);
    try sub.register(&environment);
    try mul.register(&environment);
    try div.register(&environment);
    try mod.register(&environment);
    try concat.register(&environment);

    const equal = try predicates.Equal.init(&symbol_table);
    const greater_than = try predicates.GreaterThan.init(&symbol_table);
    const greater_than_equal = try predicates.GreaterThanEqual.init(&symbol_table);
    const less_than = try predicates.LessThan.init(&symbol_table);
    const less_than_equal = try predicates.LessThanEqual.init(&symbol_table);

    try equal.register(&environment);
    try greater_than.register(&environment);
    try greater_than_equal.register(&environment);
    try less_than.register(&environment);
    try less_than_equal.register(&environment);

    const quote = try special_forms.Quote.init(runtime_arena, &symbol_table);
    const typeof = try special_forms.TypeOf.init(runtime_arena, &symbol_table);
    const cons = try special_forms.Cons.init(runtime_arena, &symbol_table);
    const car = try special_forms.Car.init(runtime_arena, &symbol_table);
    const cdr = try special_forms.Cdr.init(runtime_arena, &symbol_table);
    const write = try special_forms.Write.init(runtime_arena, &symbol_table);
    const print = try special_forms.Print.init(runtime_arena, &symbol_table);
    const input_ = try special_forms.Input.init(runtime_arena, &symbol_table);
    const read = try special_forms.Read.init(runtime_arena, &symbol_table);
    const symbol = try special_forms.Symbol.init(runtime_arena, &symbol_table);
    const do = try special_forms.Do.init(runtime_arena, &symbol_table);
    const cond = try special_forms.Cond.init(runtime_arena, &symbol_table);
    const eval = try special_forms.Eval.init(runtime_arena, &symbol_table);
    const def = try special_forms.Def.init(runtime_arena, &symbol_table);
    const set = try special_forms.Set.init(runtime_arena, &symbol_table);
    const lambda = try special_forms.Lambda.init(runtime_arena, &symbol_table);
    const dambda = try special_forms.Dambda.init(runtime_arena, &symbol_table);

    try quote.register(&environment);
    try typeof.register(&environment);
    try cons.register(&environment);
    try car.register(&environment);
    try cdr.register(&environment);
    try write.register(&environment);
    try print.register(&environment);
    try input_.register(&environment);
    try read.register(&environment);
    try symbol.register(&environment);
    try do.register(&environment);
    try cond.register(&environment);
    try eval.register(&environment);
    try def.register(&environment);
    try set.register(&environment);
    try lambda.register(&environment);
    try dambda.register(&environment);

    const evaluator = liscript.Evaluator.init(runtime_arena, &symbol_table, stdout_writer, stdin_reader);

    while (try isocline.readline(allocator, "")) |input| {
        defer std.c.free(input.ptr);

        _ = iter_arena.reset(.retain_capacity);
        const arena = iter_arena.allocator();

        const prompt = std.mem.trim(u8, input, " \t\n\r");
        if (str.eql(prompt, "")) continue;

        var stdout = Io.Writer.Allocating.init(arena);

        var lexer = Lexer.init(input);
        var parser = Parser.init(arena, runtime_arena, &lexer, &symbol_table);

        const parsed = parser.parse(.{ .check_dungling_tokens = true }) catch |err| {
            try errors.handleError(arena, err, lexer.getSpan());
            continue;
        };

        const result = evaluator.evaluate(parsed, &environment) catch |err| {
            try errors.handleError(arena, err, lexer.getSpan());
            continue;
        };

        if (liscript.ast.isNil(result) != null) continue;

        try environment.def(last_result_symbol, result);

        try result.repr(symbol_table, &stdout.writer);
        const repr = stdout.written();

        try isocline.printf(allocator, "{s}\n", .{repr});
    }

    try isocline.printf(allocator, "\n[b]toodles![/b]\n", .{});
}
