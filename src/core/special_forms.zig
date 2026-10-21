const std = @import("std");

const ast = @import("ast.zig");

const SymbolTable = @import("symbol_table.zig").SymbolTable;
const Environment = @import("environment.zig").Environment;
const Evaluator = @import("evaluator.zig").Evaluator;
const Lexer = @import("lexer.zig").Lexer;
const Parser = @import("parser.zig").Parser;
const ListIter = @import("list_iter.zig").ListIterator;

const SymbolNode = ast.Symbol;
const AstNode = ast.AstNode;
const Object = ast.Object;

pub const SpecialFormError = error{
    CdrIsNotList,
    ArgIsNotList,
    ArgIsNotString,
    ArgsIsRequired,
    LambdaArgsMustBeList,
    LambdaBodyCantBeEmpty,
    DambdaArgsMustBeList,
    DambdaBodyCantBeEmpty,
    MacroArgsMustBeList,
    MacroBodyCantBeEmpty,
};

pub const SpecialForm = struct {
    ptr: *const anyopaque,
    repr: []const u8,
    exec_fn: *const fn (ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) anyerror!AstNode,
};

pub fn MakeSpecialForm(comptime name: []const u8, comptime body_fn: anytype) type {
    return struct {
        pub const repr = name;
        symbol: SymbolNode,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !@This() {
            return .{
                .symbol = try symbol_table.insert(@This().repr),
                .allocator = allocator,
            };
        }

        pub fn specialForm(self: *const @This()) SpecialForm {
            return .{ .ptr = self, .repr = @This().repr, .exec_fn = @This().exec };
        }

        pub inline fn register(self: @This(), environment: *Environment) !void {
            try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
        }

        fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) anyerror!AstNode {
            const self: *const @This() = @ptrCast(@alignCast(ptr));
            return try body_fn(self, environment, evaluator, body);
        }
    };
}

pub const Quote = MakeSpecialForm("quote", struct {
    fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;
        _ = environment;
        _ = evaluator;

        var iter = ListIter.init(body);

        if (iter.next(.cons)) |arg| return arg;

        return SpecialFormError.ArgsIsRequired;
    }
}.exec);

pub const TypeOf = struct {
    pub const repr = "typeof";

    symbol: SymbolNode,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !TypeOf {
        const symbol = try symbol_table.insert(TypeOf.repr);
        return .{ .symbol = symbol, .allocator = allocator };
    }

    pub fn specialForm(self: *const TypeOf) SpecialForm {
        return .{ .ptr = self, .repr = TypeOf.repr, .exec_fn = TypeOf.exec };
    }

    pub inline fn register(self: TypeOf, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
    }

    pub fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const self: *const TypeOf = @ptrCast(@alignCast(ptr));

        const args = try ast.unwrapCons(body);
        const arg = try evaluator.evaluate(args.car, environment);

        const type_str = switch (arg) {
            .object => if (ast.isCons(arg) != null) "list" else "string",
            else => |node| @tagName(node),
        };

        return ast.makeString(self.allocator, type_str);
    }
};

pub const Cons = struct {
    pub const repr = "cons";

    symbol: SymbolNode,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Cons {
        const symbol = try symbol_table.insert(Cons.repr);
        return .{ .symbol = symbol, .allocator = allocator };
    }

    pub fn specialForm(self: *const Cons) SpecialForm {
        return .{ .ptr = self, .repr = Cons.repr, .exec_fn = Cons.exec };
    }

    pub inline fn register(self: Cons, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
    }

    pub fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const self: *const Cons = @ptrCast(@alignCast(ptr));

        const args = try ast.unwrapCons(body);

        const car = args.car;

        const rest_cons = try ast.unwrapCons(args.cdr);
        const cdr = ast.isConsNode(rest_cons.car) orelse return SpecialFormError.CdrIsNotList;

        return ast.makeCons(self.allocator, try evaluator.evaluate(car, environment), try evaluator.evaluate(cdr, environment));
    }
};

pub const Car = struct {
    pub const repr = "car";

    symbol: SymbolNode,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Car {
        const symbol = try symbol_table.insert(Car.repr);
        return .{ .symbol = symbol, .allocator = allocator };
    }

    pub fn specialForm(self: *const Car) SpecialForm {
        return .{ .ptr = self, .repr = Car.repr, .exec_fn = Car.exec };
    }

    pub inline fn register(self: Car, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
    }

    pub fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        _ = ptr;

        const args = try ast.unwrapCons(body);
        const arg = ast.isConsNode(args.car) orelse return SpecialFormError.ArgIsNotList;

        const evaluated_arg = try evaluator.evaluate(arg, environment);
        const list = try ast.unwrapCons(evaluated_arg);

        return list.car;
    }
};

pub const Cdr = struct {
    pub const repr = "cdr";

    symbol: SymbolNode,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Cdr {
        const symbol = try symbol_table.insert(Cdr.repr);
        return .{ .symbol = symbol, .allocator = allocator };
    }

    pub fn specialForm(self: *const Cdr) SpecialForm {
        return .{ .ptr = self, .repr = Cdr.repr, .exec_fn = Cdr.exec };
    }

    pub inline fn register(self: Cdr, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
    }

    pub fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        _ = ptr;

        const args = try ast.unwrapCons(body);
        const arg = ast.isConsNode(args.car) orelse return SpecialFormError.ArgIsNotList;

        const evaluated_arg = try evaluator.evaluate(arg, environment);
        const list = try ast.unwrapCons(evaluated_arg);

        return list.cdr;
    }
};

pub const Write = struct {
    pub const repr = "write";

    symbol: SymbolNode,
    symbol_table: *SymbolTable,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Write {
        const symbol = try symbol_table.insert(Write.repr);
        return .{ .symbol = symbol, .symbol_table = symbol_table, .allocator = allocator };
    }

    pub fn specialForm(self: *const Write) SpecialForm {
        return .{ .ptr = self, .repr = Write.repr, .exec_fn = Write.exec };
    }

    pub inline fn register(self: Write, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
    }

    pub fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const self: *const Write = @ptrCast(@alignCast(ptr));

        if (ast.isNil(body) != null) {
            return SpecialFormError.ArgsIsRequired;
        }

        const args = try ast.unwrapCons(body);

        var arg_1 = try evaluator.evaluate(args.car, environment);
        var rest_args = args.cdr;

        if (ast.isString(arg_1)) |string| {
            _ = try evaluator.writer.write(string);
        } else {
            try arg_1.repr(self.symbol_table.*, evaluator.writer);
        }

        while (ast.isNil(rest_args) == null) {
            const rest_cons = try ast.unwrapCons(rest_args);
            const arg_2 = try evaluator.evaluate(rest_cons.car, environment);

            _ = try evaluator.writer.write(" ");

            if (ast.isString(arg_2)) |string| {
                _ = try evaluator.writer.write(string);
            } else {
                try arg_2.repr(self.symbol_table.*, evaluator.writer);
            }

            rest_args = rest_cons.cdr;
        }

        try evaluator.writer.flush();

        return ast.makeNil();
    }
};

pub const Print = struct {
    pub const repr = "print";

    symbol: SymbolNode,
    symbol_table: *SymbolTable,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Print {
        const symbol = try symbol_table.insert(Print.repr);
        return .{ .symbol = symbol, .symbol_table = symbol_table, .allocator = allocator };
    }

    pub fn specialForm(self: *const Print) SpecialForm {
        return .{ .ptr = self, .repr = Print.repr, .exec_fn = Print.exec };
    }

    pub inline fn register(self: Print, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
    }

    pub fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const self: *const Print = @ptrCast(@alignCast(ptr));

        if (ast.isNil(body) != null) {
            return SpecialFormError.ArgsIsRequired;
        }

        const args = try ast.unwrapCons(body);

        var arg_1 = try evaluator.evaluate(args.car, environment);
        var rest_args = args.cdr;

        if (ast.isString(arg_1)) |string| {
            _ = try evaluator.writer.write(string);
        } else {
            try arg_1.repr(self.symbol_table.*, evaluator.writer);
        }

        while (ast.isNil(rest_args) == null) {
            const rest_cons = try ast.unwrapCons(rest_args);
            const arg_2 = try evaluator.evaluate(rest_cons.car, environment);

            _ = try evaluator.writer.write(" ");

            if (ast.isString(arg_2)) |string| {
                _ = try evaluator.writer.write(string);
            } else {
                try arg_2.repr(self.symbol_table.*, evaluator.writer);
            }

            rest_args = rest_cons.cdr;
        }

        _ = try evaluator.writer.write("\n");
        try evaluator.writer.flush();

        return ast.makeNil();
    }
};

pub const Input = struct {
    pub const repr = "input";

    symbol: SymbolNode,
    symbol_table: *SymbolTable,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Input {
        const symbol = try symbol_table.insert(Input.repr);
        return .{ .symbol = symbol, .symbol_table = symbol_table, .allocator = allocator };
    }

    pub fn specialForm(self: *const Input) SpecialForm {
        return .{ .ptr = self, .repr = Input.repr, .exec_fn = Input.exec };
    }

    pub inline fn register(self: Input, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
    }

    pub fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        _ = environment;

        const self: *const Input = @ptrCast(@alignCast(ptr));

        var prompt: []const u8 = "";

        if (ast.isNil(body) == null) {
            const args = ast.isCons(body) orelse return SpecialFormError.CdrIsNotList;
            prompt = try ast.unwrapString(args.car);
        }

        _ = try evaluator.writer.write(prompt);
        try evaluator.writer.flush();

        const input = try evaluator.reader.peekDelimiterInclusive('\n');
        evaluator.reader.toss(input.len);

        return ast.makeString(self.allocator, input);
    }
};

pub const Read = struct {
    pub const repr = "read";

    symbol: SymbolNode,
    symbol_table: *SymbolTable,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Read {
        const symbol = try symbol_table.insert(Read.repr);
        return .{ .symbol = symbol, .symbol_table = symbol_table, .allocator = allocator };
    }

    pub fn specialForm(self: *const Read) SpecialForm {
        return .{ .ptr = self, .repr = Read.repr, .exec_fn = Read.exec };
    }

    pub inline fn register(self: Read, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
    }

    pub fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        _ = environment;

        const self: *const Read = @ptrCast(@alignCast(ptr));

        var prompt: []const u8 = "";

        if (ast.isNil(body) == null) {
            const args = ast.isCons(body) orelse return SpecialFormError.CdrIsNotList;
            prompt = try ast.unwrapString(args.car);
        }

        _ = try evaluator.writer.write(prompt);
        try evaluator.writer.flush();

        const input = try evaluator.reader.peekDelimiterInclusive('\n');
        evaluator.reader.toss(input.len);

        var lexer = Lexer.init(input);
        var parser = Parser.init(self.allocator, self.allocator, &lexer, self.symbol_table); // todo pass iter allocator

        return parser.parse(.{ .check_dungling_tokens = true });
    }
};

pub const Symbol = struct {
    pub const repr = "symbol";

    symbol: SymbolNode,
    symbol_table: *SymbolTable,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Symbol {
        const symbol = try symbol_table.insert(Symbol.repr);
        return .{ .symbol = symbol, .symbol_table = symbol_table, .allocator = allocator };
    }

    pub fn specialForm(self: *const Symbol) SpecialForm {
        return .{ .ptr = self, .repr = Symbol.repr, .exec_fn = Symbol.exec };
    }

    pub inline fn register(self: Symbol, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
    }

    pub fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        _ = environment;
        _ = evaluator;

        const self: *const Symbol = @ptrCast(@alignCast(ptr));

        if (ast.isNil(body) != null) {
            return SpecialFormError.ArgsIsRequired;
        }

        const args = try ast.unwrapCons(body);
        const arg = try ast.unwrapString(args.car);

        return ast.makeSymbol(try self.symbol_table.insert(arg));
    }
};

pub const Do = MakeSpecialForm("do", struct {
    fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const this = @as(@TypeOf(self), self);
        _ = this;

        var iter = ListIter.init(body);
        var result: AstNode = ast.makeNil();

        while (iter.next(.any)) |elem| {
            result = try evaluator.evaluate(elem, environment);
        }

        return result;
    }
}.exec);

pub const Cond = struct {
    pub const repr = "cond";

    symbol: SymbolNode,
    symbol_table: *SymbolTable,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Cond {
        const symbol = try symbol_table.insert(Cond.repr);
        return .{ .symbol = symbol, .symbol_table = symbol_table, .allocator = allocator };
    }

    pub fn specialForm(self: *const Cond) SpecialForm {
        return .{ .ptr = self, .repr = Cond.repr, .exec_fn = Cond.exec };
    }

    pub inline fn register(self: Cond, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
    }

    pub fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        _ = ptr;

        if (ast.isNil(body) != null) {
            return ast.makeNil();
        }

        const args = try ast.unwrapCons(body);

        var condition_or_value = try evaluator.evaluate(args.car, environment);
        var rest_args = args.cdr;

        while (ast.isNil(rest_args) == null) {
            const rest_cons = try ast.unwrapCons(rest_args);

            const condition = try ast.unwrapBool(condition_or_value);
            if (condition.get()) {
                return try evaluator.evaluate(rest_cons.car, environment);
            }

            const else_ = try ast.unwrapCons(rest_cons.cdr);
            condition_or_value = try evaluator.evaluate(else_.car, environment);
            rest_args = else_.cdr;
        }

        return condition_or_value;
    }
};

pub const Eval = struct {
    pub const repr = "eval";

    symbol: SymbolNode,
    symbol_table: *SymbolTable,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Eval {
        const symbol = try symbol_table.insert(Eval.repr);
        return .{ .symbol = symbol, .symbol_table = symbol_table, .allocator = allocator };
    }

    pub fn specialForm(self: *const Eval) SpecialForm {
        return .{ .ptr = self, .repr = Eval.repr, .exec_fn = Eval.exec };
    }

    pub inline fn register(self: Eval, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
    }

    pub fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        const self: *const Eval = @ptrCast(@alignCast(ptr));
        _ = self;

        if (ast.isNil(body) != null) return ast.makeNil();

        const args = try ast.unwrapCons(body);
        const evaluated_arg = try evaluator.evaluate(args.car, environment);

        return try evaluator.evaluate(evaluated_arg, environment);
    }
};

pub const Def = struct {
    pub const repr = "def";

    symbol: SymbolNode,
    symbol_table: *SymbolTable,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Def {
        const symbol = try symbol_table.insert(Def.repr);
        return .{ .symbol = symbol, .symbol_table = symbol_table, .allocator = allocator };
    }

    pub fn specialForm(self: *const Def) SpecialForm {
        return .{ .ptr = self, .repr = Def.repr, .exec_fn = Def.exec };
    }

    pub inline fn register(self: Def, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
    }

    pub fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        if (ast.isNil(body) != null) {
            return SpecialFormError.ArgsIsRequired;
        }

        const symbol_defintion_cons = try ast.unwrapCons(body);
        const var_name = try ast.unwrapSymbol(symbol_defintion_cons.car);
        const var_value_node = symbol_defintion_cons.cdr;

        if (ast.isNil(var_value_node) != null) {
            return SpecialFormError.ArgsIsRequired; // todo
        }

        const var_value_cons = try ast.unwrapCons(var_value_node);
        const var_value_evaluated = try evaluator.evaluate(var_value_cons.car, environment);

        try environment.def(var_name, var_value_evaluated);

        if (ast.isNil(var_value_cons.cdr) == null) {
            return Def.exec(ptr, environment, evaluator, var_value_cons.cdr);
        }

        return ast.makeNil();
    }
};

pub const Set = struct {
    pub const repr = "set!";

    symbol: SymbolNode,
    symbol_table: *SymbolTable,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, symbol_table: *SymbolTable) !Set {
        const symbol = try symbol_table.insert(Set.repr);
        return .{ .symbol = symbol, .symbol_table = symbol_table, .allocator = allocator };
    }

    pub fn specialForm(self: *const Set) SpecialForm {
        return .{ .ptr = self, .repr = Set.repr, .exec_fn = Set.exec };
    }

    pub inline fn register(self: Set, environment: *Environment) !void {
        try environment.def(self.symbol, .{ .builtin = .{ .special_form = self.specialForm() } });
    }

    pub fn exec(ptr: *const anyopaque, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        if (ast.isNil(body) != null) {
            return SpecialFormError.ArgsIsRequired;
        }

        const symbol_defintion_cons = try ast.unwrapCons(body);
        const var_name = try ast.unwrapSymbol(symbol_defintion_cons.car);
        const var_value_node = symbol_defintion_cons.cdr;

        if (ast.isNil(var_value_node) != null) {
            return SpecialFormError.ArgsIsRequired; // todo
        }

        const var_value_cons = try ast.unwrapCons(var_value_node);
        const var_value_evaluated = try evaluator.evaluate(var_value_cons.car, environment);

        try environment.set(var_name, var_value_evaluated);

        if (ast.isNil(var_value_cons.cdr) == null) {
            return Set.exec(ptr, environment, evaluator, var_value_cons.cdr);
        }

        return ast.makeNil();
    }
};

pub const Lambda = MakeSpecialForm("lambda", struct {
    fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        _ = evaluator;

        const this = @as(@TypeOf(self), self);

        var iter = ListIter.init(body);

        if (iter.next(.cons) orelse iter.next(.nil)) |args| {
            if (iter.next(.any)) |body_| {
                return try ast.makeLambda(this.allocator, args, body_, environment);
            }

            return SpecialFormError.LambdaBodyCantBeEmpty;
        }

        return SpecialFormError.LambdaArgsMustBeList;
    }
}.exec);

pub const Dambda = MakeSpecialForm("dambda", struct {
    fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        _ = environment;
        _ = evaluator;

        const this = @as(@TypeOf(self), self);

        var iter = ListIter.init(body);

        if (iter.next(.cons) orelse iter.next(.nil)) |args| {
            if (iter.next(.any)) |body_| {
                return try ast.makeDambda(this.allocator, args, body_);
            }

            return SpecialFormError.DambdaBodyCantBeEmpty;
        }

        return SpecialFormError.DambdaArgsMustBeList;
    }
}.exec);

pub const Macro = MakeSpecialForm("macro", struct {
    fn exec(self: anytype, environment: *Environment, evaluator: Evaluator, body: AstNode) !AstNode {
        _ = environment;
        _ = evaluator;

        const this = @as(@TypeOf(self), self);

        var iter = ListIter.init(body);

        if (iter.next(.cons) orelse iter.next(.nil)) |args| {
            if (iter.next(.any)) |body_| {
                return try ast.makeMacro(this.allocator, args, body_);
            }

            return SpecialFormError.MacroBodyCantBeEmpty;
        }

        return SpecialFormError.MacroArgsMustBeList;
    }
}.exec);
