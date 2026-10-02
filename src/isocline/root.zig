const std = @import("std");

const c = @import("./c.zig"); 

pub fn readline(allocator: std.mem.Allocator, prompt: []const u8) !?[:0]u8 {
    const prompt_c = try allocator.dupeZ(u8, prompt);
    defer allocator.free(prompt_c);

    const prompt_ptr: [*c]const c_char = @ptrCast(prompt_c.ptr);

    const res_ptr = c.ic_readline(prompt_ptr);
    if (res_ptr == null) return null;

    const slice_ptr: [*:0]u8 = @ptrCast(res_ptr);

    return std.mem.span(slice_ptr);
}

pub fn printf(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const formatted = try std.fmt.allocPrintSentinel(allocator, fmt, args, 0);
    defer allocator.free(formatted);

    const c_fmt_ptr: [*c]const c_char = @ptrCast(formatted.ptr);

    @call(.auto, c.ic_printf, .{c_fmt_ptr});
}

