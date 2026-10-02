const std = @import("std");
const Io = std.Io;

const liscript = @import("liscript");
const isocline = @import("isocline");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    while (try isocline.readline(allocator, "")) |input| {
        defer std.c.free(input.ptr); 

        const prompt = std.mem.trim(u8, input, " \t\n\r");

        if (std.mem.eql(u8, prompt, "")) continue;

        try isocline.printf(allocator, "{s}\n", .{ input });
    }

    try isocline.printf(allocator, "\n[b]toodles![/b]\n", .{});
}

