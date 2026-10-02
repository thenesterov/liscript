const isocline_c = @import("isocline_c");

pub extern fn ic_readline(prompt_text: [*c]const c_char) callconv(.c) [*c]c_char;

pub extern fn ic_printf(fmt: [*c]const c_char, ...) callconv(.c) void;

