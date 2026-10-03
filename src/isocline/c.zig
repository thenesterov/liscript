const isocline_c = @import("isocline_c");

pub extern fn ic_readline(prompt_text: [*c]const c_char) callconv(.c) [*c]c_char;

pub extern fn ic_printf(fmt: [*c]const c_char, ...) callconv(.c) void;

pub extern fn ic_set_history(fname: [*c]const c_char, max_entries: c_long) callconv(.c) void;

