const std = @import("std");

const nodes = @import("nodes.zig");

const AstNode = nodes.AstNode;

pub fn nodeTypeName(node: AstNode) []const u8 {
    return switch (node) {
        .object => |obj| @tagName(std.meta.activeTag(obj.getPtr(*const nodes.Object).body)),
        else => @tagName(std.meta.activeTag(node)),
    };
}

fn RawType(comptime tag: std.meta.Tag(AstNode)) type {
    return switch (tag) {
        .float => f64,
        .int => i32,
        .nil => void,
        .bool => bool,
        .symbol => nodes.Symbol,
        .object => @compileError("use makeObject for .object"),
        else => @compileError("can't make .builtin"),
    };
}

pub fn make(
    comptime tag: std.meta.Tag(AstNode),
    value: RawType(tag),
) AstNode {
    return switch (tag) {
        .int => .{ .int = nodes.Int.from(value) },
        .float => .{ .float = nodes.Float.from(value) },
        .bool => .{ .bool = nodes.Bool.from(value) },
        .symbol => .{ .symbol = value },
        .nil => .{ .nil = nodes.Nil.from() },
        .object => unreachable,
        .builtin => unreachable,
    };
}

pub const nil = make(.nil, {});

pub fn makeObject(
    allocator: std.mem.Allocator,
    comptime tag: std.meta.Tag(Body),
    value: @FieldType(Body, @tagName(tag)),
) !AstNode {
    const obj = try allocator.create(nodes.Object);
    obj.* = .{ .body = @unionInit(Body, @tagName(tag), value) };
    return AstNode{ .object = nodes.ObjectPtr.fromPtr(obj) };
}

pub fn as(
    comptime tag: std.meta.Tag(AstNode),
    node: AstNode,
) ?@FieldType(AstNode, @tagName(tag)) {
    return switch (node) {
        tag => |v| v,
        else => null,
    };
}

pub fn asObject(
    comptime tag: std.meta.Tag(Body),
    node: AstNode,
) ?@FieldType(Body, @tagName(tag)) {
    const obj = switch (node) {
        .object => |o| o.getPtr(*const nodes.Object),
        else => return null,
    };
    return switch (obj.body) {
        tag => |v| v,
        else => null,
    };
}

const Body = @FieldType(nodes.Object, "body");

pub fn unwrap(
    comptime tag: std.meta.Tag(AstNode),
    node: AstNode,
) error{TypeMismatch}!@FieldType(AstNode, @tagName(tag)) {
    return switch (node) {
        tag => |v| v,
        else => error.TypeMismatch,
    };
}

pub fn unwrapObject(
    comptime tag: std.meta.Tag(Body),
    node: AstNode,
) error{TypeMismatch}!@FieldType(Body, @tagName(tag)) {
    const obj = switch (node) {
        .object => |o| o.getPtr(*const nodes.Object),
        else => return error.TypeMismatch,
    };

    return switch (obj.body) {
        tag => |v| v,
        else => error.TypeMismatch,
    };
}
