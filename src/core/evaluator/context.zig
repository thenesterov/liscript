const std = @import("std");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const ast = @import("../ast.zig");

const operators = @import("../builtins/operators.zig");
const predicates = @import("../builtins/predicates.zig");
const special_forms = @import("../builtins/special_forms.zig");

const Symbol = @import("../ast.zig").Symbol;
const SymbolTable = @import("../symbol_table.zig").SymbolTable;
const Environment = @import("../environment.zig").Environment;
const Lexer = @import("../lexer.zig").Lexer;
const Parser = @import("../parser.zig").Parser;
const EvaluatorError = @import("errors.zig").EvaluatorError;

const IoContext = struct {
    io: std.Io,

    _stdout_buf: [1024]u8,
    _stdin_buf: [1024]u8,

    _file_writer: std.Io.File.Writer,
    _file_reader: std.Io.File.Reader,

    pub fn init(self: *IoContext, io: std.Io) void {
        self.io = io;
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

    last_error_node: ?ast.AstNode = null,
    last_error_message: ?[]const u8 = null,

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
        try self.registerBuiltin(special_forms.Racro);
        try self.registerBuiltin(special_forms.Load);
        try self.registerBuiltin(special_forms.Error);
        try self.registerBuiltin(special_forms.Assert);
        try self.registerBuiltin(special_forms.AssertEq);
        try self.registerBuiltin(special_forms.AssertError);
        try self.registerBuiltin(special_forms.GenSym);
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

    pub fn setErrorMessage(self: *EvaluatorContext, comptime fmt: []const u8, args: anytype) void {
        const allocator = self.iter_allocator.allocator();
        self.last_error_message = std.fmt.allocPrint(allocator, fmt, args) catch "Out of memory while formatting error";
    }

    pub fn setErrorNode(self: *EvaluatorContext, node: ast.AstNode) void {
        self.last_error_node = node;
    }

    pub fn fail(self: *EvaluatorContext, err: EvaluatorError, comptime fmt: []const u8, args: anytype) EvaluatorError {
        switch (err) {
            EvaluatorError.TypeError => self.setErrorMessage("TypeError: " ++ fmt, args),
            EvaluatorError.NameError => self.setErrorMessage("NameError: " ++ fmt, args),
            EvaluatorError.RuntimeError => self.setErrorMessage("RuntimeError: " ++ fmt, args),
            EvaluatorError.AssertionError => self.setErrorMessage("AssertionError: " ++ fmt, args),
            EvaluatorError.ZeroDivisionError => self.setErrorMessage("ZeroDivisionError: " ++ fmt, args),
        }
        return err;
    }

    fn registerBuiltin(self: *EvaluatorContext, comptime T: type) !void {
        const ptr = try self.runtime_allocator.create(T);
        ptr.* = try T.init(self.runtime_allocator, &self.symbol_table);
        try ptr.register(&self.environment);
    }
};
