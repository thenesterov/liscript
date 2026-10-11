const std = @import("std");
const Io = std.Io;

const liscript = @import("liscript");
const isocline = @import("isocline");

const SymbolTable = liscript.SymbolTable;
const ObjectPtr = liscript.ast.ObjectPtr;
const AstNode = liscript.ast.AstNode;
const Object = liscript.ast.Object;
const Float = liscript.ast.Float;
const Bool = liscript.ast.Bool;
const Int = liscript.ast.Int;
const Nil = liscript.ast.Nil;

fn createCons(allocator: std.mem.Allocator, car: AstNode, cdr: AstNode) !AstNode {
    const obj = try allocator.create(Object);
    obj.* = .{ .body = .{ .cons = .{
        .car = car,
        .cdr = cdr,
    } } };
    return AstNode{ .object = ObjectPtr.fromPtr(obj) };
}

fn nodeFloat(f: f64) AstNode {
    return AstNode{ .float = Float.from(f) };
}
fn nodeInt(i: i32) AstNode {
    return AstNode{ .int = Int.from(i) };
}

fn nodeNil() AstNode {
    return AstNode{ .nil = Nil.from() };
}

fn nodeBool(b: bool) AstNode {
    return AstNode{ .bool = Bool.from(b) };
}

fn nodeString(allocator: std.mem.Allocator, s: []const u8) !AstNode {
    const obj = try allocator.create(Object);
    obj.* = .{ .body = .{ .string = s } };
    return AstNode{ .object = ObjectPtr.fromPtr(obj) };
}

// (1 1.1 "hello" true nil)
fn example1(allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    var symbol_table = SymbolTable.init(allocator);
    defer symbol_table.deinit();

    const nil_node = try createCons(
        allocator,
        nodeNil(),
        nodeNil(),
    );
    const bool_node = try createCons(
        allocator,
        nodeBool(true),
        nil_node,
    );
    const string_node = try createCons(
        allocator,
        try nodeString(allocator, "hello\n"),
        bool_node,
    );
    const float_node = try createCons(
        allocator,
        nodeFloat(1.1),
        string_node,
    );
    const int_node = try createCons(
        allocator,
        nodeInt(1),
        float_node,
    );
    try int_node.repr(symbol_table, &buf.writer);

    return allocator.dupe(u8, buf.written());
}

// (* 2 (+ 3 4))
fn example2(allocator: std.mem.Allocator) ![]const u8 {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    var symbol_table = SymbolTable.init(allocator);
    defer symbol_table.deinit();

    const sym_plus = try symbol_table.insert("+");
    const sym_mult = try symbol_table.insert("*");

    const node_plus = AstNode{ .symbol = sym_plus };
    const node_mult = AstNode{ .symbol = sym_mult };

    const sum_operand2_node = try createCons(
        allocator,
        nodeInt(4),
        nodeNil(),
    );
    const sum_operand1_node = try createCons(
        allocator,
        nodeInt(3),
        sum_operand2_node,
    );
    const sum_node = try createCons(
        allocator,
        node_plus,
        sum_operand1_node,
    );

    const mul_operand2_node = try createCons(
        allocator,
        sum_node,
        nodeNil(),
    );
    const mul_operand1_node = try createCons(
        allocator,
        nodeInt(2),
        mul_operand2_node,
    );
    const mul_node = try createCons(
        allocator,
        node_mult,
        mul_operand1_node,
    );

    try mul_node.repr(symbol_table, &buf.writer);

    return allocator.dupe(u8, buf.written());
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const arena_allocator = init.arena.allocator();

    const example_1 = try example1(arena_allocator);
    defer arena_allocator.free(example_1);
    try isocline.printf(allocator, "{s}\n", .{example_1});

    const example_2 = try example2(arena_allocator);
    defer arena_allocator.free(example_2);
    try isocline.printf(allocator, "{s}\n", .{example_2});

    try isocline.set_history(allocator, ".liscript_history", 2048);

    while (try isocline.readline(allocator, "")) |input| {
        defer std.c.free(input.ptr);

        const prompt = std.mem.trim(u8, input, " \t\n\r");

        if (std.mem.eql(u8, prompt, "")) continue;

        try isocline.printf(allocator, "{s}\n", .{input});
    }

    try isocline.printf(allocator, "\n[b]toodles![/b]\n", .{});
}
