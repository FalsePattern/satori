const std = @import("std");
const assert = std.debug.assert;

const Coroutine = @import("satori").Coroutine;

const AnEnum = enum {
    Foo,
    Bar,
    Baz,
};
fn cofunc(initial: bool) u32 {
    assert(initial);
    assert(Coroutine.yield(AnEnum.Bar, u8) == 34);
    Coroutine.yield(@as(i32, -1), void);
    return 30;
}

test "Type wrapping" {
    var co = Coroutine{};
    co.init(0, cofunc);
    defer co.deinit();
    assert(co.state() == .suspended);
    assert(co.@"resume"(true, AnEnum) == .Bar);
    assert(co.@"resume"(@as(u8, 34), i32) == -1);
    assert(co.@"resume"({}, u32) == 30);
    assert(co.state() == .dead);
}
