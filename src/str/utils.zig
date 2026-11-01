const std = @import("std");

pub const StrError = error{
    InvalidEscapeSequence,
};

pub fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn inludesChar(string: []const u8, char: u8) bool {
    return std.mem.indexOfScalar(u8, string, char) != null;
}

pub fn escape(allocator: std.mem.Allocator, raw_string: []const u8) ![]const u8 {
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    for (raw_string) |char| {
        switch (char) {
            '\n' => try buffer.appendSlice(allocator, "\\n"),
            '\r' => try buffer.appendSlice(allocator, "\\r"),
            '\t' => try buffer.appendSlice(allocator, "\\t"),
            '"' => try buffer.appendSlice(allocator, "\\\""),
            '\\' => try buffer.appendSlice(allocator, "\\\\\\\\"), // todo: isocline implementation detail leak
            else => try buffer.appendSlice(allocator, &[_]u8{char}),
        }
    }

    return try buffer.toOwnedSlice(allocator);
}

pub fn unescape(allocator: std.mem.Allocator, escaped: []const u8) ![]const u8 {
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(allocator);

    var i: usize = 0;
    while (i < escaped.len) {
        const char = escaped[i];

        if (char != '\\') {
            try buffer.append(allocator, char);
            i += 1;
        } else {
            i += 1;
            if (i >= escaped.len) return StrError.InvalidEscapeSequence;
            const escaped_char = escaped[i];

            const processed: u8 = switch (escaped_char) {
                '\\' => '\\',
                '"' => '"',
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                else => return StrError.InvalidEscapeSequence,
            };
            try buffer.append(allocator, processed);
            i += 1;
        }
    }

    return try buffer.toOwnedSlice(allocator);
}
