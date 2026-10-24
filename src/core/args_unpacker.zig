const std = @import("std");

const ast = @import("ast.zig");

const AstNode = ast.AstNode;
const ListIter = @import("list_iter.zig").ListIterator;

pub const ArgType = struct {
    pub const any: u16 = 0xFFFF;
    pub const symbol: u16 = 0x0001;
    pub const cons: u16 = 0x0002;
    pub const nil: u16 = 0x0004;
    pub const string: u16 = 0x0008;
    pub const integer: u16 = 0x0010;
    pub const float: u16 = 0x0020;
    pub const boolean: u16 = 0x0040;

    pub const number: u16 = integer | float;
    pub const list: u16 = cons | nil;
    pub const text: u16 = string | symbol;
};

pub const Arg = struct {
    name: []const u8,
    mask: u16 = ArgType.any,
    optional: bool = false,
    is_rest: bool = false,
    require_even: bool = false,
};

pub fn unpack(comptime spec: anytype, comptime fn_name: []const u8, args_cdr: AstNode) !UnpackedResult(spec, fn_name) {
    return try UnpackedResult(spec, fn_name).doUnpack(args_cdr);
}

pub fn UnpackedResult(comptime spec: anytype, comptime fn_name: []const u8) type {
    comptime {
        var found_optional = false;
        var found_rest = false;
        var min_required: usize = 0;

        for (spec) |arg| {
            if (found_rest) {
                @compileError("ArgsUnpacker error: '" ++ arg.name ++ "' inside '" ++ fn_name ++ "' is placed after the .is_rest argument");
            }
            if (arg.is_rest) {
                found_rest = true;
            }
            if (arg.optional) {
                found_optional = true;
            } else if (!arg.is_rest) {
                if (found_optional) {
                    @compileError("ArgsUnpacker error: required argument '" ++ arg.name ++ "' inside '" ++ fn_name ++ "' cannot follow an optional argument");
                }
                min_required += 1;
            }
        }

        const max_capacity = spec.len;

        return struct {
            const Self = @This();

            nodes: [max_capacity]AstNode = undefined,
            present_mask: u32 = 0,
            count: usize = 0,

            fn doUnpack(cdr: AstNode) !Self {
                var self = Self{};
                var iter = ListIter.init(cdr);
                var i: usize = 0;

                while (i < max_capacity) {
                    const current_spec = spec[i];

                    if (current_spec.is_rest) {
                        const rest_chain = iter.current;

                        var check_iter = ListIter.init(rest_chain);
                        var check_idx: usize = i + 1;
                        while (check_iter.next(.any)) |tail_node| {
                            const node_type_bit = getRealTypeBit(tail_node);
                            if ((node_type_bit & current_spec.mask) == 0) {
                                var expected_types: []const u8 = "unknown";
                                inline for (spec, 0..) |s, idx| {
                                    if (idx == i) expected_types = comptime getMaskNames(s.mask);
                                }

                                std.debug.print("TypeError in '{s}': rest argument element {} ('{s}') expected {s}, but got {s}\n", .{
                                    fn_name,
                                    check_idx,
                                    current_spec.name,
                                    expected_types,
                                    @tagName(tail_node),
                                });
                                return error.InvalidArgumentType;
                            }
                            check_idx += 1;
                        }

                        self.nodes[i] = rest_chain;
                        self.present_mask |= (@as(u32, 1) << @intCast(i));
                        i += 1;
                        iter.current = ast.makeNil();
                        break;
                    }

                    if (iter.next(.any)) |arg_node| {
                        const node_type_bit = getRealTypeBit(arg_node);
                        if ((node_type_bit & current_spec.mask) == 0) {
                            var expected_types: []const u8 = "unknown";
                            inline for (spec, 0..) |s, idx| {
                                if (idx == i) expected_types = comptime getMaskNames(s.mask);
                            }
                            std.debug.print("TypeError in '{s}': argument '{s}' expected {s}, but got {s}\n", .{
                                fn_name,
                                current_spec.name,
                                expected_types,
                                @tagName(arg_node),
                            });
                            return error.InvalidArgumentType;
                        }

                        self.nodes[i] = arg_node;
                        self.present_mask |= (@as(u32, 1) << @intCast(i));
                        i += 1;
                    } else {
                        break;
                    }
                }

                inline for (spec, 0..) |current_spec, idx| {
                    if (current_spec.is_rest and current_spec.require_even) {
                        if (self.present_mask & (@as(u32, 1) << idx) != 0) {
                            var tail_iter = ListIter.init(self.nodes[idx]);
                            var tail_count: usize = 0;
                            while (tail_iter.next(.any)) |_| {
                                tail_count += 1;
                            }

                            if (tail_count % 2 != 0) {
                                std.debug.print("Runtime Error inside '{s}': rest argument '{s}' expects an even number of elements (pairs), but got {}.\n", .{
                                    fn_name,
                                    current_spec.name,
                                    tail_count,
                                });
                                return error.OddArgumentCount;
                            }
                        }
                    }
                }

                if (iter.current != .nil) {
                    std.debug.print("Runtime error inside '{s}': too many arguments. Expected maximum {}.\n", .{ fn_name, max_capacity });
                    return error.TooManyArguments;
                }
                if (i < min_required) {
                    std.debug.print("Runtime error inside '{s}': too few arguments. Expected at least {}, got {}.\n", .{ fn_name, min_required, i });
                    return error.TooFewArguments;
                }

                self.count = i;
                return self;
            }

            pub inline fn get(self: Self, comptime name: []const u8) AstNode {
                comptime var found = false;
                comptime var target_idx: usize = 0;

                inline for (spec, 0..) |arg, idx| {
                    if (comptime std.mem.eql(u8, arg.name, name)) {
                        found = true;
                        target_idx = idx;
                    }
                }

                if (comptime !found) {
                    @compileError("ArgsUnpacker Error: Function '" ++ fn_name ++ "' has no argument named '" ++ name ++ "'!");
                }

                return self.nodes[target_idx];
            }

            pub inline fn has(self: Self, comptime name: []const u8) bool {
                comptime var found = false;
                comptime var target_idx: usize = 0;

                inline for (spec, 0..) |arg, idx| {
                    if (comptime std.mem.eql(u8, arg.name, name)) {
                        found = true;
                        target_idx = idx;
                    }
                }

                if (comptime !found) return false;
                return (self.present_mask & (@as(u32, 1) << @intCast(target_idx))) != 0;
            }
        };
    }
}

fn getRealTypeBit(node: AstNode) u16 {
    if (ast.isNil(node) != null) return ArgType.nil;
    if (ast.isCons(node) != null) return ArgType.cons;

    if (ast.isInteger(node) != null) return ArgType.integer;
    if (ast.isFloat(node) != null) return ArgType.float;
    if (ast.isString(node) != null) return ArgType.string;
    if (ast.isSymbol(node) != null) return ArgType.symbol;
    if (ast.isBoolean(node) != null) return ArgType.boolean;

    const tag = std.meta.activeTag(node);
    return @as(u16, 1) << @intCast(@intFromEnum(tag));
}

fn getMaskNames(comptime mask: u16) []const u8 {
    return comptime blk: {
        if (mask == ArgType.any) break :blk "any type";

        var result: []const u8 = "";
        var first = true;

        const types = .{
            .{ .bit = ArgType.symbol, .name = "symbol" },
            .{ .bit = ArgType.cons, .name = "cons" },
            .{ .bit = ArgType.nil, .name = "nil" },
            .{ .bit = ArgType.string, .name = "string" },
            .{ .bit = ArgType.integer, .name = "integer" },
            .{ .bit = ArgType.float, .name = "float" },
            .{ .bit = ArgType.boolean, .name = "boolean" },
        };

        for (types) |t| {
            if ((mask & t.bit) != 0) {
                if (!first) {
                    result = result ++ " or ";
                }
                result = result ++ t.name;
                first = false;
            }
        }

        if (result.len == 0) break :blk "unknown type";
        break :blk result;
    };
}
