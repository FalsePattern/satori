const std = @import("std");
const c = @import("c");

fn coroutine(_: ?*anyopaque) callconv(.c) ?*anyopaque {
    std.debug.print("Foo\n", .{});
    _ = c.koishi_yield(@ptrFromInt(1));
    std.debug.print("Bar\n", .{});
    _ = c.koishi_yield(@ptrFromInt(1));
    std.debug.print("Baz\n", .{});
    return @ptrFromInt(0);
}

pub fn main() !void {
    var co: c.koishi_coroutine_t = undefined;

    c.koishi_init(&co, 0, &coroutine);
    defer c.koishi_deinit(&co);
    while (@intFromPtr(c.koishi_resume(&co, null)) != 0) {
        std.debug.print("yielded\n", .{});
    }
    std.debug.print("done!\n", .{});
}

