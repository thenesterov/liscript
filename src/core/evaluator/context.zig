const std = @import("std");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const operators = @import("../operators.zig");
const predicates = @import("../predicates.zig");
const special_forms = @import("../special_forms.zig");

const Symbol = @import("../ast.zig").Symbol;
const SymbolTable = @import("../symbol_table.zig").SymbolTable;
const Environment = @import("../environment.zig").Environment;
const Lexer = @import("../lexer.zig").Lexer;
const Parser = @import("../parser.zig").Parser;

const IoContext = struct {
    _stdout_buf: [1024]u8,
    _stdin_buf: [1024]u8,

    _file_writer: std.Io.File.Writer,
    _file_reader: std.Io.File.Reader,

    pub fn init(self: *IoContext, io: std.Io) void {
        self._file_writer = .init(.stdout(), io, &self._stdout_buf);
        self._file_reader = .init(.stdin(), io, &self._stdin_buf);
    }

    pub fn writer(self: *IoContext) *std.Io.Writer {
        return &self._file_writer.interface;
    }

    pub fn reader(self: *IoContext) *std.Io.Reader {
        return &self._file_reader.interface;
    }
};

const SymbolsContext = struct {
    rest_args: Symbol,
    last_result: Symbol,
};

pub const EvaluatorContext = struct {
    iter_allocator: *ArenaAllocator,
    runtime_allocator: Allocator,

    io: IoContext,
    symbols: SymbolsContext,
    symbol_table: SymbolTable,
    environment: Environment,

    pub fn init(self: *EvaluatorContext, io: std.Io, iter_allocator: *ArenaAllocator, runtime_allocator: Allocator) !void {
        self.* = .{
            .iter_allocator = iter_allocator,
            .runtime_allocator = runtime_allocator,
            .io = undefined,
            .symbols = undefined,
            .symbol_table = .init(runtime_allocator),
            .environment = .init(runtime_allocator, null),
        };

        self.io.init(io);
        self.environment.global = &self.environment;

        self.symbols = .{
            .last_result = try self.symbol_table.insert("_"),
            .rest_args = try self.symbol_table.insert("..."),
        };

        try self.registerBuiltin(operators.Add);
        try self.registerBuiltin(operators.Sub);
        try self.registerBuiltin(operators.Mul);
        try self.registerBuiltin(operators.Div);
        try self.registerBuiltin(operators.Mod);
        try self.registerBuiltin(operators.Concat);

        try self.registerBuiltin(predicates.Equal);
        try self.registerBuiltin(predicates.GreaterThan);
        try self.registerBuiltin(predicates.GreaterThanEqual);
        try self.registerBuiltin(predicates.LessThan);
        try self.registerBuiltin(predicates.LessThanEqual);

        try self.registerBuiltin(special_forms.Quote);
        try self.registerBuiltin(special_forms.TypeOf);
        try self.registerBuiltin(special_forms.Cons);
        try self.registerBuiltin(special_forms.Car);
        try self.registerBuiltin(special_forms.Cdr);
        try self.registerBuiltin(special_forms.Write);
        try self.registerBuiltin(special_forms.Print);
        try self.registerBuiltin(special_forms.Input);
        try self.registerBuiltin(special_forms.Read);
        try self.registerBuiltin(special_forms.Symbol);
        try self.registerBuiltin(special_forms.Do);
        try self.registerBuiltin(special_forms.Cond);
        try self.registerBuiltin(special_forms.Eval);
        try self.registerBuiltin(special_forms.Def);
        try self.registerBuiltin(special_forms.Set);
        try self.registerBuiltin(special_forms.Lambda);
        try self.registerBuiltin(special_forms.Dambda);
        try self.registerBuiltin(special_forms.Macro);
    }

    pub fn deinit(self: *EvaluatorContext) void {
        self.symbol_table.deinit();
        self.environment.deinit();
    }

    pub fn parser(self: *EvaluatorContext, iter_allocator: Allocator, source: []const u8) !Parser {
        const lexer_ptr = try iter_allocator.create(Lexer);
        lexer_ptr.* = .init(source);

        return .init(iter_allocator, self.runtime_allocator, lexer_ptr, &self.symbol_table);
    }

    fn registerBuiltin(self: *EvaluatorContext, comptime T: type) !void {
        const ptr = try self.runtime_allocator.create(T);
        ptr.* = try T.init(self.runtime_allocator, &self.symbol_table);
        try ptr.register(&self.environment);
    }
};
