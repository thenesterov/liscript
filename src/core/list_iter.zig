const std = @import("std");

const ast = @import("ast.zig");

const AstNode = ast.AstNode;
const Object = ast.Object;

const ExpectType = enum {
    any,
    float,
    int,
    nil,
    bool,
    symbol,
    cons,
    string,
};

pub const ListIterator = struct {
    current: AstNode,

    pub fn init(node: AstNode) ListIterator {
        return .{ .current = node };
    }

    pub fn next(self: *ListIterator, expect_type: ExpectType) ?AstNode {
        if (self.current == .nil) return null;

        const cons = ast.isCons(self.current) orelse return null;
        const element = cons.car;

        const matches = switch (expect_type) {
            .any => true,
            .float => element == .float,
            .int => element == .int,
            .nil => element == .nil,
            .bool => element == .bool,
            .symbol => element == .symbol,

            .cons => if (element == .object) res: {
                const obj = element.object.getPtr(*const Object);
                break :res obj.body == .cons;
            } else false,

            .string => if (element == .object) res: {
                const obj = element.object.getPtr(*const Object);
                break :res obj.body == .string;
            } else false,
        };

        if (matches) {
            self.current = cons.cdr;
            return element;
        }

        return null;
    }
};
