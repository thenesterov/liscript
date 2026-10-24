const std = @import("std");

const ast = @import("ast.zig");
const environment = @import("environment.zig");

const Object = ast.Object;
const AstNode = ast.AstNode;
const SymbolTable = @import("symbol_table.zig").SymbolTable;
const Environment = environment.Environment;
const EnvironmentError = environment.EnvironmentError;
const Operator = @import("operators.zig").Operator;
const Predicate = @import("predicates.zig").Predicate;
const ListIter = @import("list_iter.zig").ListIterator;
const EvaluatorContext = @import("evaluator/context.zig").EvaluatorContext;

pub const EvaluatorError = error{
    CantCallLiteral,
    CantCurryDambda,
    LambdaArgMustBeSymbol,
    DambdaArgMustBeSymbol,
    MacroArgMustBeSymbol,
    OperatorMustTakeAtLeastOneArgument,
};

pub const Evaluator = struct {
    allocator: std.mem.Allocator,
    symbol_table: *SymbolTable,

    writer: *std.Io.Writer,
    reader: *std.Io.Reader,

    pub fn init(context: *EvaluatorContext) Evaluator {
        return .{
            .allocator = context.runtime_allocator,
            .symbol_table = &context.symbol_table,
            .writer = context.io.writer(),
            .reader = context.io.reader(),
        };
    }

    pub fn evaluate(self: Evaluator, node: AstNode, environment_: *Environment) anyerror!AstNode {
        return switch (node) {
            .symbol => |symbol| environment_.get(symbol),
            .object => |object| {
                const object_ptr = object.getPtr(*const Object);
                return switch (object_ptr.body) {
                    .cons => |cons| try self.evaluateList(cons, environment_),
                    .string => node,
                    else => node,
                };
            },
            else => node,
        };
    }

    fn evaluateList(self: Evaluator, cons: ast.Cons, environment_: *Environment) anyerror!AstNode {
        const head = try self.evaluate(cons.car, environment_);

        return switch (head) {
            .builtin => |builtin| switch (builtin) {
                .operator => |operator| try self.foldOperator(operator, cons.cdr, environment_),
                .predicate => |predicate| try self.foldPredicate(predicate, cons.cdr, environment_),
                .special_form => |special_form| try special_form.exec_fn(special_form.ptr, environment_, self, cons.cdr),
            },
            .object => res: {
                if (ast.isLambda(head)) |lambda| break :res try self.callLambda(lambda, cons, environment_);
                if (ast.isDambda(head)) |dambda| break :res try self.callDambda(dambda, cons, environment_);
                if (ast.isMacro(head)) |macro| break :res try self.callMacro(macro, cons, environment_);
                return EvaluatorError.CantCallLiteral;
            },
            else => return EvaluatorError.CantCallLiteral,
        };
    }

    fn callLambda(self: Evaluator, lambda: ast.Lambda, cons: ast.Cons, environment_: *Environment) !AstNode {
        const rest_vals_symbol = try self.symbol_table.insert("..."); // todo вынести в константу

        const new_env_ptr = try self.allocator.create(Environment);
        new_env_ptr.* = Environment.init(self.allocator, lambda.env);

        var args_iter = ListIter.init(lambda.args);
        var vals_iter = ListIter.init(cons.cdr);

        while (true) {
            if (args_iter.current == .nil) {
                var rest_vals = ast.makeNil();
                var tail_ptr: *AstNode = &rest_vals;

                while (vals_iter.next(.any)) |val| {
                    const evaluated_val = try self.evaluate(val, environment_);
                    const val_cons = try ast.makeCons(self.allocator, evaluated_val, ast.makeNil());

                    tail_ptr.* = val_cons;

                    const val_cons_ptr = val_cons.object.getPtr(*Object);
                    tail_ptr = &val_cons_ptr.body.cons.cdr;
                }

                try new_env_ptr.def(rest_vals_symbol, rest_vals);
                break;
            }

            if (vals_iter.current == .nil) {
                var rest_args = ast.makeNil();
                var tail_ptr: *AstNode = &rest_args;

                while (args_iter.next(.symbol)) |arg| {
                    const arg_cons = try ast.makeCons(self.allocator, arg, ast.makeNil());

                    tail_ptr.* = arg_cons;

                    const arg_cons_ptr = arg_cons.object.getPtr(*Object);
                    tail_ptr = &arg_cons_ptr.body.cons.cdr;
                }

                return try ast.makeLambda(self.allocator, rest_args, lambda.body, new_env_ptr);
            }

            const sym_node = args_iter.next(.symbol) orelse return EvaluatorError.LambdaArgMustBeSymbol;
            const raw_val_node = vals_iter.next(.any) orelse break;

            const evaluated_val = try self.evaluate(raw_val_node, environment_);

            try new_env_ptr.def(sym_node.symbol, evaluated_val);
        }

        return try self.evaluate(lambda.body, new_env_ptr);
    }

    fn callDambda(self: Evaluator, dambda: ast.Dambda, cons: ast.Cons, environment_: *Environment) !AstNode {
        const rest_vals_symbol = try self.symbol_table.insert("..."); // todo вынести в константу

        const new_env_ptr = try self.allocator.create(Environment);
        new_env_ptr.* = Environment.init(self.allocator, environment_);

        var args_iter = ListIter.init(dambda.args);
        var vals_iter = ListIter.init(cons.cdr);

        while (true) {
            if (args_iter.current == .nil) {
                var rest_vals = ast.makeNil();
                var tail_ptr: *AstNode = &rest_vals;

                while (vals_iter.next(.any)) |val| {
                    const evaluated_val = try self.evaluate(val, environment_);
                    const val_cons = try ast.makeCons(self.allocator, evaluated_val, ast.makeNil());

                    tail_ptr.* = val_cons;

                    const val_cons_ptr = val_cons.object.getPtr(*Object);
                    tail_ptr = &val_cons_ptr.body.cons.cdr;
                }

                try new_env_ptr.def(rest_vals_symbol, rest_vals);
                break;
            }

            if (vals_iter.current == .nil) {
                return EvaluatorError.CantCurryDambda;
            }

            const sym_node = args_iter.next(.symbol) orelse return EvaluatorError.DambdaArgMustBeSymbol;
            const raw_val_node = vals_iter.next(.any) orelse break;

            const evaluated_val = try self.evaluate(raw_val_node, environment_);

            try new_env_ptr.def(sym_node.symbol, evaluated_val);
        }

        return try self.evaluate(dambda.body, new_env_ptr);
    }

    fn callMacro(self: Evaluator, macro: ast.Macro, cons: ast.Cons, environment_: *Environment) !AstNode {
        const rest_vals_symbol = try self.symbol_table.insert("..."); // todo вынести в константу

        const new_env_ptr = try self.allocator.create(Environment);
        new_env_ptr.* = Environment.init(self.allocator, null);
        new_env_ptr.global = new_env_ptr;

        var args_iter = ListIter.init(macro.args);
        var vals_iter = ListIter.init(cons.cdr);

        while (true) {
            if (args_iter.current == .nil) {
                var rest_vals = ast.makeNil();
                var tail_ptr: *AstNode = &rest_vals;

                while (vals_iter.next(.any)) |val| {
                    const evaluated_val = try self.evaluate(val, environment_);
                    const val_cons = try ast.makeCons(self.allocator, evaluated_val, ast.makeNil());

                    tail_ptr.* = val_cons;

                    const val_cons_ptr = val_cons.object.getPtr(*Object);
                    tail_ptr = &val_cons_ptr.body.cons.cdr;
                }

                try new_env_ptr.def(rest_vals_symbol, rest_vals);
                break;
            }

            if (vals_iter.current == .nil) {
                var rest_args = ast.makeNil();
                var tail_ptr: *AstNode = &rest_args;

                while (args_iter.next(.symbol)) |arg| {
                    const arg_cons = try ast.makeCons(self.allocator, arg, ast.makeNil());

                    tail_ptr.* = arg_cons;

                    const arg_cons_ptr = arg_cons.object.getPtr(*Object);
                    tail_ptr = &arg_cons_ptr.body.cons.cdr;
                }

                return try ast.makeMacro(self.allocator, rest_args, try self.macroExpand(macro.body, new_env_ptr));
            }

            const arg = args_iter.next(.symbol) orelse return EvaluatorError.MacroArgMustBeSymbol;
            const val = vals_iter.next(.any) orelse break;

            try new_env_ptr.def(arg.symbol, val);
        }

        return try self.evaluate(try self.macroExpand(macro.body, new_env_ptr), environment_);
    }

    fn macroExpand(self: Evaluator, node: AstNode, environment_: *Environment) anyerror!AstNode {
        return switch (node) {
            .symbol => |symbol| environment_.get(symbol),

            .object => |object| res: {
                const object_ptr = object.getPtr(*const Object);
                break :res switch (object_ptr.body) {
                    .cons => |cons| try ast.makeCons(
                        self.allocator,
                        try self.macroExpand(cons.car, environment_),
                        try self.macroExpand(cons.cdr, environment_),
                    ),
                    else => node,
                };
            },
            else => node,
        };
    }

    fn foldOperator(self: Evaluator, operator: Operator, cdr: AstNode, environment_: *Environment) !AstNode {
        if (ast.isNil(cdr) != null) {
            return EvaluatorError.OperatorMustTakeAtLeastOneArgument;
        }

        const args = try ast.unwrapCons(cdr);

        var operand_1 = try self.evaluate(args.car, environment_);
        var rest = args.cdr;

        while (ast.isNil(rest) == null) {
            const rest_cons = try ast.unwrapCons(rest);

            const operand_2 = try self.evaluate(rest_cons.car, environment_);
            operand_1 = try operator.exec_fn(operator.ptr, operand_1, operand_2);
            rest = rest_cons.cdr;
        }

        return operand_1;
    }

    fn foldPredicate(self: Evaluator, predicate: Predicate, cdr: AstNode, environment_: *Environment) !AstNode {
        if (ast.isNil(cdr) != null) {
            return ast.makeBool(true);
        }

        const args = try ast.unwrapCons(cdr);

        var operand_1 = try self.evaluate(args.car, environment_);
        var rest = args.cdr;

        while (ast.isNil(rest) == null) {
            const rest_cons = try ast.unwrapCons(rest);

            const operand_2 = try self.evaluate(rest_cons.car, environment_);
            const compare_result = try predicate.exec_fn(predicate.ptr, operand_1, operand_2);

            if (!(try ast.unwrapBool(compare_result)).get()) {
                return ast.makeBool(false);
            }

            operand_1 = operand_2;
            rest = rest_cons.cdr;
        }

        return ast.makeBool(true);
    }
};
