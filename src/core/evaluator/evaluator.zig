const std = @import("std");

const ast = @import("../ast.zig");
const environment = @import("../environment.zig");

const Object = ast.Object;
const AstNode = ast.AstNode;
const SymbolTable = @import("../symbol_table.zig").SymbolTable;
const Environment = environment.Environment;
const EnvironmentError = environment.EnvironmentError;
const Operator = @import("../builtins/operators.zig").Operator;
const Predicate = @import("../builtins/predicates.zig").Predicate;
const ListIter = @import("../helpers/list_iter.zig").ListIterator;
const EvaluatorContext = @import("../evaluator/context.zig").EvaluatorContext;
const EvaluatorError = @import("errors.zig").EvaluatorError;
const EvaluatorMode = @import("../evaluator/mode.zig").EvaluatorMode;

pub const Evaluator = struct {
    context: *EvaluatorContext,

    pub fn init(context: *EvaluatorContext) Evaluator {
        return .{ .context = context };
    }

    pub fn evaluate(self: *Evaluator, node: AstNode, environment_: *Environment, mode: EvaluatorMode) anyerror!AstNode {
        if (mode == .lazy) {
            return self.evaluateInner(node, environment_, mode) catch |err| {
                if (self.context.last_error_node == null) {
                    self.context.setErrorNode(node);
                }
                return err;
            };
        }

        var current_node = node;
        var current_env = environment_;

        while (true) {
            const out = self.evaluateInner(current_node, current_env, mode) catch |err| {
                if (self.context.last_error_node == null) {
                    self.context.setErrorNode(current_node);
                }
                return err;
            };

            if (ast.asObject(.tail_call, out)) |tail_call| {
                current_node = tail_call.expr;
                current_env = tail_call.env;
                continue;
            }

            return out;
        }
    }

    fn evaluateInner(self: *Evaluator, node: AstNode, environment_: *Environment, mode: EvaluatorMode) anyerror!AstNode {
        return switch (node) {
            .symbol => |symbol| environment_.get(symbol),
            .object => |object| {
                const object_ptr = object.getPtr(*const Object);
                return switch (object_ptr.body) {
                    .cons => |cons| try self.evaluateList(cons, environment_, mode),
                    .string => node,
                    else => node,
                };
            },
            else => node,
        };
    }

    fn evaluateList(self: *Evaluator, cons: ast.Cons, environment_: *Environment, mode: EvaluatorMode) anyerror!AstNode {
        const head = try self.evaluate(cons.car, environment_, .strict);

        return switch (head) {
            .builtin => |builtin| switch (builtin) {
                .operator => |operator| self.foldOperator(operator, cons.cdr, environment_, mode),
                .predicate => |predicate| self.foldPredicate(predicate, cons.cdr, environment_, mode),
                .special_form => |special_form| special_form.exec_fn(special_form.ptr, environment_, self, mode, cons.cdr),
            },
            .object => res: {
                if (ast.asObject(.lambda, head)) |lambda| break :res self.callLambda(lambda, cons, environment_, mode);
                if (ast.asObject(.dambda, head)) |dambda| break :res self.callDambda(dambda, cons, environment_, mode);
                if (ast.asObject(.racro, head)) |racro| break :res self.callRacro(racro, cons, environment_, mode);
                return self.context.fail(
                    EvaluatorError.TypeError,
                    "cannot call non-function type '{s}'",
                    .{ast.nodeTypeName(head)},
                );
            },
            .symbol => |symbol| {
                return self.context.fail(
                    EvaluatorError.NameError,
                    "name '{s}' is not defined",
                    .{self.context.symbol_table.getName(symbol.getId())},
                );
            },
            else => return self.context.fail(
                EvaluatorError.TypeError,
                "cannot call non-function type '{s}'",
                .{ast.nodeTypeName(head)},
            ),
        };
    }

    fn callLambda(self: *Evaluator, lambda: ast.Lambda, cons: ast.Cons, environment_: *Environment, mode: EvaluatorMode) !AstNode {
        _ = mode;

        const new_env_ptr = try self.context.runtime_allocator.create(Environment);
        new_env_ptr.* = Environment.init(self.context.runtime_allocator, lambda.env);

        var args_iter = ListIter.init(lambda.args);
        var vals_iter = ListIter.init(cons.cdr);

        while (true) {
            if (args_iter.current == .nil) {
                var rest_vals = ast.nil;
                var tail_ptr: *AstNode = &rest_vals;

                while (vals_iter.next(.any)) |val| {
                    const evaluated_val = try self.evaluate(val, environment_, .strict);
                    const val_cons = try ast.makeObject(self.context.runtime_allocator, .cons, .{ .car = evaluated_val, .cdr = ast.nil });

                    tail_ptr.* = val_cons;

                    const val_cons_ptr = val_cons.object.getPtr(*Object);
                    tail_ptr = &val_cons_ptr.body.cons.cdr;
                }

                try new_env_ptr.def(self.context.symbols.rest_args, rest_vals);
                break;
            }

            if (vals_iter.current == .nil) {
                var rest_args = ast.nil;
                var tail_ptr: *AstNode = &rest_args;

                while (args_iter.next(.symbol)) |arg| {
                    const arg_cons = try ast.makeObject(self.context.runtime_allocator, .cons, .{ .car = arg, .cdr = ast.nil });

                    tail_ptr.* = arg_cons;

                    const arg_cons_ptr = arg_cons.object.getPtr(*Object);
                    tail_ptr = &arg_cons_ptr.body.cons.cdr;
                }

                return try ast.makeObject(self.context.runtime_allocator, .lambda, .{ .args = rest_args, .body = lambda.body, .env = new_env_ptr });
            }

            const sym_node = args_iter.next(.symbol) orelse {
                if (ast.asObject(.cons, args_iter.current)) |cons_| {
                    return self.context.fail(
                        EvaluatorError.TypeError,
                        "lambda parameter must be a symbol, not '{s}'",
                        .{ast.nodeTypeName(cons_.car)},
                    );
                } else {
                    return self.context.fail(
                        EvaluatorError.TypeError,
                        "lambda parameter must be a symbol, not '{s}'",
                        .{ast.nodeTypeName(args_iter.current)},
                    );
                }
            };
            const raw_val_node = vals_iter.next(.any) orelse break;

            const evaluated_val = try self.evaluate(raw_val_node, environment_, .strict);

            try new_env_ptr.def(sym_node.symbol, evaluated_val);
        }

        return try ast.makeObject(self.context.runtime_allocator, .tail_call, .{
            .expr = lambda.body,
            .env = new_env_ptr,
        });
    }

    fn callDambda(self: *Evaluator, dambda: ast.Dambda, cons: ast.Cons, environment_: *Environment, mode: EvaluatorMode) !AstNode {
        _ = mode;

        const new_env_ptr = try self.context.runtime_allocator.create(Environment);
        new_env_ptr.* = Environment.init(self.context.runtime_allocator, environment_);

        var args_iter = ListIter.init(dambda.args);
        var vals_iter = ListIter.init(cons.cdr);

        const expected_arity = args_iter.len();
        const provided_arity = vals_iter.len();

        while (true) {
            if (args_iter.current == .nil) {
                var rest_vals = ast.nil;
                var tail_ptr: *AstNode = &rest_vals;

                while (vals_iter.next(.any)) |val| {
                    const evaluated_val = try self.evaluate(val, environment_, .strict);
                    const val_cons = try ast.makeObject(self.context.runtime_allocator, .cons, .{ .car = evaluated_val, .cdr = ast.nil });

                    tail_ptr.* = val_cons;

                    const val_cons_ptr = val_cons.object.getPtr(*Object);
                    tail_ptr = &val_cons_ptr.body.cons.cdr;
                }

                try new_env_ptr.def(self.context.symbols.rest_args, rest_vals);
                break;
            }

            if (vals_iter.current == .nil) return self.context.fail(
                EvaluatorError.TypeError,
                "currying is not allowed for dambda (expected {d}, got {d})",
                .{ expected_arity, provided_arity },
            );

            const sym_node = args_iter.next(.symbol) orelse {
                if (ast.asObject(.cons, args_iter.current)) |cons_| {
                    return self.context.fail(
                        EvaluatorError.TypeError,
                        "dambda parameter must be a symbol, not '{s}'",
                        .{ast.nodeTypeName(cons_.car)},
                    );
                } else {
                    return self.context.fail(
                        EvaluatorError.TypeError,
                        "dambda parameter must be a symbol, not '{s}'",
                        .{ast.nodeTypeName(args_iter.current)},
                    );
                }
            };
            const raw_val_node = vals_iter.next(.any) orelse break;

            const evaluated_val = try self.evaluate(raw_val_node, environment_, .strict);

            try new_env_ptr.def(sym_node.symbol, evaluated_val);
        }

        return try self.evaluate(dambda.body, new_env_ptr, .lazy);
    }

    fn callRacro(self: *Evaluator, racro: ast.Racro, cons: ast.Cons, environment_: *Environment, mode: EvaluatorMode) !AstNode {
        _ = mode;

        const new_env_ptr = try self.context.runtime_allocator.create(Environment);
        new_env_ptr.* = Environment.init(self.context.runtime_allocator, null);
        new_env_ptr.global = new_env_ptr;

        var args_iter = ListIter.init(racro.args);
        var vals_iter = ListIter.init(cons.cdr);

        while (true) {
            if (args_iter.current == .nil) {
                var rest_vals = ast.nil;
                var tail_ptr: *AstNode = &rest_vals;

                while (vals_iter.next(.any)) |val| {
                    const val_cons = try ast.makeObject(self.context.runtime_allocator, .cons, .{ .car = val, .cdr = ast.nil });

                    tail_ptr.* = val_cons;

                    const val_cons_ptr = val_cons.object.getPtr(*Object);
                    tail_ptr = &val_cons_ptr.body.cons.cdr;
                }

                try new_env_ptr.def(self.context.symbols.rest_args, rest_vals);
                break;
            }

            if (vals_iter.current == .nil) {
                var rest_args = ast.nil;
                var tail_ptr: *AstNode = &rest_args;

                while (args_iter.next(.symbol)) |arg| {
                    const arg_cons = try ast.makeObject(self.context.runtime_allocator, .cons, .{ .car = arg, .cdr = ast.nil });

                    tail_ptr.* = arg_cons;

                    const arg_cons_ptr = arg_cons.object.getPtr(*Object);
                    tail_ptr = &arg_cons_ptr.body.cons.cdr;
                }

                return try ast.makeObject(self.context.runtime_allocator, .racro, .{ .args = rest_args, .body = try self.racroExpand(racro.body, new_env_ptr) });
            }

            const arg = args_iter.next(.symbol) orelse {
                if (ast.asObject(.cons, args_iter.current)) |cons_| {
                    return self.context.fail(
                        EvaluatorError.TypeError,
                        "racro parameter must be a symbol, not '{s}'",
                        .{ast.nodeTypeName(cons_.car)},
                    );
                } else {
                    return self.context.fail(
                        EvaluatorError.TypeError,
                        "racro parameter must be a symbol, not '{s}'",
                        .{ast.nodeTypeName(args_iter.current)},
                    );
                }
            };
            const val = vals_iter.next(.any) orelse break;

            try new_env_ptr.def(arg.symbol, val);
        }

        return try self.evaluate(try self.racroExpand(racro.body, new_env_ptr), environment_, .lazy);
    }

    fn racroExpand(self: *Evaluator, node: AstNode, environment_: *Environment) anyerror!AstNode {
        return switch (node) {
            .symbol => |symbol| environment_.get(symbol),
            .object => |object| res: {
                const object_ptr = object.getPtr(*const Object);
                break :res switch (object_ptr.body) {
                    .cons => |cons| try ast.makeObject(
                        self.context.runtime_allocator,
                        .cons,
                        .{
                            .car = try self.racroExpand(cons.car, environment_),
                            .cdr = try self.racroExpand(cons.cdr, environment_),
                        },
                    ),
                    else => node,
                };
            },
            else => node,
        };
    }

    fn foldOperator(self: *Evaluator, operator: Operator, cdr: AstNode, environment_: *Environment, mode: EvaluatorMode) !AstNode {
        _ = mode;
        if (ast.as(.nil, cdr) != null) return self.context.fail(
            EvaluatorError.TypeError,
            "operator '{s}' requires at least 1 argument",
            .{operator.repr},
        );

        const args = try ast.unwrapObject(.cons, cdr);

        var operand_1 = try self.evaluate(args.car, environment_, .strict);
        var rest = args.cdr;

        while (ast.as(.nil, rest) == null) {
            const rest_cons = try ast.unwrapObject(.cons, rest);

            const operand_2 = try self.evaluate(rest_cons.car, environment_, .strict);
            operand_1 = try operator.exec_fn(operator.ptr, self, operand_1, operand_2);
            rest = rest_cons.cdr;
        }

        return operand_1;
    }

    fn foldPredicate(self: *Evaluator, predicate: Predicate, cdr: AstNode, environment_: *Environment, mode: EvaluatorMode) !AstNode {
        _ = mode;

        if (ast.as(.nil, cdr) != null) {
            return ast.make(.bool, true);
        }

        const args = try ast.unwrapObject(.cons, cdr);

        var operand_1 = try self.evaluate(args.car, environment_, .strict);
        var rest = args.cdr;

        while (ast.as(.nil, rest) == null) {
            const rest_cons = try ast.unwrapObject(.cons, rest);

            const operand_2 = try self.evaluate(rest_cons.car, environment_, .strict);
            const compare_result = try predicate.exec_fn(predicate.ptr, self, operand_1, operand_2);

            if (!(try ast.unwrap(.bool, compare_result)).get()) {
                return ast.make(.bool, false);
            }

            operand_1 = operand_2;
            rest = rest_cons.cdr;
        }

        return ast.make(.bool, true);
    }
};
