const std = @import("std");
const cmds = @import("commands.zig");

/// Main entrypoint to the program
pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_state.allocator();
    defer _ = gpa_state.deinit();

    try cmds.httpRequestCommand(gpa);
}
