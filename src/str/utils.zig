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

pub fn escape(raw_string: []const u8, writer: *std.Io.Writer) !void {
    for (raw_string) |char| {
        switch (char) {
            '\n' => try writer.print("\\n", .{}),
            '\r' => try writer.print("\\r", .{}),
            '\t' => try writer.print("\\t", .{}),
            '"' => try writer.print("\\\"", .{}),
            '\\' => try writer.print("\\\\\\\\", .{}), // todo: isocline implementation detail leak
            else => try writer.print("{c}", .{char}),
        }
    }
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
