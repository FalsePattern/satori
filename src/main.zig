const std = @import("std");
const koishi = @import("koishi_h");

/// C function pointer equivalent of `Entrypoint`
pub const RawEntrypoint = *const fn (?*anyopaque) callconv(.c) ?*anyopaque;

///State of a `Coroutine` instance.
pub const State = enum(c_int) {
    ///The coroutine is suspended and may be resumed with `resume`.
    suspended = koishi.KOISHI_SUSPENDED,
    ///The coroutine is currently executing and may be yielded from with `yield`.
    ///Only up to one coroutine may be running per thread at all times.
    running = koishi.KOISHI_RUNNING,
    ///The coroutine has finished executing and may be recycled with `recycle` or destroyed with `deinit`.
    dead = koishi.KOISHI_DEAD,
    ///The coroutine has resumed another coroutine and is waiting for it to yield.
    idle = koishi.KOISHI_IDLE,
};

/// A coroutine instance.
///
/// This struct must be initialized with `init` before use.
/// You should *not* pass instances of this struct around by value while the underlying coroutine is in the `running` or `idle` states.
pub const Coroutine = struct {
    /// The raw coroutine data. Don't mess with it.
    koishi_coroutine: koishi.koishi_coroutine_t = .{},

    /// Initialize a coroutine.
    ///
    /// This function must be called before using any of the other APIs with a particular
    /// coroutine instance. It allocates a stack at least `min_stack_size` bytes big
    /// and sets up an initial jump context.
    ///
    /// After this function returns, the coroutine is in the `suspended` state.
    /// When resumed (see `resume`), `entry_point` will begin executing in the
    /// coroutine's context.
    ///
    /// Params:
    /// - `co` The coroutine to initialize.
    /// - `min_stack_size` Minimum size of the stack. The actual size will be a multiple of the system page size and at least two pages big. If 0, the default size will be used (currently 65536).
    /// - `entry_point` Function that will be called when the coroutine is first resumed.
    ///     > A coroutine entry point.
    ///     >
    ///     > The entry point is a function that is called inside a coroutine context when
    ///     > it is resumed for the first time.
    ///     >
    ///     > Once the entry point returns, control flow jumps back to the last `resume`
    ///     > call for this coroutine, as if it yielded. Its state is set to `dead`
    ///     > and it may not be resumed again.
    ///     >
    ///     > Params:
    ///     > - `data` User data that was passed to the first call to `resume`.
    ///     >
    ///     > Returns: Value to be returned from the corresponding `resume` call.
    pub inline fn init(co: *Coroutine, min_stack_size: usize, comptime entry_point: anytype) void {
        co.rawInit(min_stack_size, wrapEntryPoint(entry_point, "init"));
    }
    /// Recycle a previously initialized coroutine.
    ///
    /// This is a light-weight version of `init`. It will set up a new context,
    /// but reuse the existing stack, if allowed by the implementation. This is useful
    /// for applications that want to create lots of short-lived coroutines fairly often.
    /// They can avoid expensive stack allocations and deallocations by pooling and
    /// recycling completed tasks.
    ///
    /// Params:
    /// - `co` The coroutine to recycle. It must be initialized.
    /// - `entry_point` Function that will be called when the coroutine is first resumed.
    ///     > A coroutine entry point.
    ///     >
    ///     > The entry point is a function that is called inside a coroutine context when
    ///     > it is resumed for the first time.
    ///     >
    ///     > Once the entry point returns, control flow jumps back to the last `resume`
    ///     > call for this coroutine, as if it yielded. Its state is set to `dead`
    ///     > and it may not be resumed again.
    ///     >
    ///     > Params:
    ///     > - `data` User data that was passed to the first call to `resume`.
    ///     >
    ///     > Returns: Value to be returned from the corresponding `resume` call.
    ///
    pub inline fn recycle(co: *Coroutine, comptime entry_point: anytype) void {
        co.rawRecycle(wrapEntryPoint(entry_point, "recycle"));
    }

    /// Deinitialize a coroutine.
    ///
    /// This will free the stack and any other resources associated with the coroutine.
    ///
    /// Memory allocated for the structure itself will not be freed, this is your
    /// responsibility.
    ///
    /// After calling this function, the coroutine becomes invalid, and must not be
    /// passed to any of the API functions other than `init`. In particular,
    /// it **may not** be recycled.
    ///
    /// Params:
    /// - `co` The coroutine to deinitialize.
    ///
    pub inline fn deinit(co: *Coroutine) void {
        koishi.koishi_deinit(&co.koishi_coroutine);
    }

    /// Resume a suspended coroutine.
    ///
    /// Transfers control flow to the coroutine context, putting it into the
    /// `running` state. The calling context is put into the `idle`
    /// state.
    ///
    /// If the coroutine is resumed for the first time, \p arg will be passed
    /// as a parameter to its entry point (see `Entrypoint`). Otherwise, it
    /// will be returned from the corresponding `yield` call.
    ///
    /// This function returns when the coroutine yields or finishes executing.
    ///
    /// Params:
    /// - `co` The coroutine to jump into. Must be in the `suspended` state.
    /// - `arg` A value to pass into the coroutine.
    /// - `T` The expected type of the return value.
    ///
    /// Returns: Value returned from the coroutine once it yields or returns.
    ///
    pub inline fn @"resume"(co: *Coroutine, arg: anytype, T: type) T {
        return fromPointer(T)(koishi.koishi_resume(&co.koishi_coroutine, pointerFrom(@TypeOf(arg))(arg)));
    }

    /// Suspend the currently running coroutine.
    ///
    /// Transfers control flow out of the coroutine back to where it was last resumed,
    /// putting it into the `suspended` state. The calling context is put into
    /// the `running` state.
    ///
    /// This function must be called from a real coroutine context.
    ///
    /// This function returns when and if the coroutine is resumed again.
    ///
    /// Params:
    /// - `arg` Value to return from the corresponding `resume` call.
    /// - `T` The expected type of the return value.
    ///
    /// Returns: Value passed to a future `resume` call.
    ///
    pub inline fn yield(arg: anytype, T: type) T {
        return fromPointer(T)(koishi.koishi_yield(pointerFrom(@TypeOf(arg))(arg)));
    }

    /// Return from the currently running coroutine.
    ///
    /// Like `yield`, except the coroutine is put into the `dead` state
    /// and may not be resumed again. For that reason, this function does not return.
    /// This is equivalent to returning from the entry point.
    ///
    /// Params:
    /// - `arg` Value to return from the corresponding `resume` call.
    ///
    pub inline fn die(arg: anytype) noreturn {
        koishi.koishi_die(pointerFrom(@TypeOf(arg))(arg));
        unreachable;
    }

    /// Stop a coroutine.
    ///
    /// Puts `co` into the `dead` state, indicating that it must not be resumed
    /// again. If `co` is the currently running coroutine, then this is equivalent
    /// to calling `die` with `arg` as the argument.
    ///
    /// If `co` is in the `idle` state, the coroutine it's waiting on would yield
    /// to the caller of `co`, as if `co` called `yield(arg)`. This applies
    /// to both explicit and implicit yields (e.g. by return from the entry point),
    /// recursively.
    ///
    /// Params:
    /// - `co` The coroutine to stop.
    /// - `arg` Value to return from the corresponding `resume` call.
    ///
    pub inline fn kill(co: *Coroutine, arg: anytype) void {
        koishi.koishi_kill(&co.koishi_coroutine, pointerFrom(@TypeOf(arg))(arg));
    }

    /// Query the state of a coroutine.
    pub inline fn state(co: *Coroutine) State {
        return @enumFromInt(koishi.koishi_state(&co.koishi_coroutine));
    }

    /// Query the coroutine's stack region.
    ///
    /// Warning: This function may not be supported by some backends. Some backends
    /// may also embed their control structures into the stack at context creation
    /// time, which are not safe to overwrite. Do not use this function unless you
    /// fully understand what you're doing.
    ///
    /// Returns: A pointer to the beginning of the stack memory region. This is always
    /// the lower end, regardless of stack growth direction. Returns `null` if not
    /// supported by the backend. Note that some backends may only support querying
    /// user-created coroutines, but not the thread's main context.
    ///
    /// Params:
    /// - `co` The coroutine to query.
    /// - `stack_size` If not `null`, the stack size is written to memory at this
    /// location. `null` is written if not supported by the backend.
    /// - `T` The expected type of the stack pointer.
    ///
    pub inline fn getStack(co: *Coroutine, stack_size: ?*usize, T: type) ?T {
        return @ptrCast(koishi.koishi_get_stack(&co.koishi_coroutine, stack_size));
    }

    /// Ziggified version of `getStack`.
    ///
    /// The warnings from `getStack` apply.
    ///
    /// Returns:
    /// - null if `getStack` returns null.
    /// - A slice of length 0, but the address of the lower end of the stack if `stack_size` was 0
    /// - A slice that encompasses the full coroutine stack if neither were null.
    ///
    /// Params:
    /// - `co` The coroutine to query.
    pub inline fn getStackBytes(co: *Coroutine) ?[]u8 {
        var stack_size: usize = 0;
        const stack = co.getStack([*]u8, &stack_size) orelse return null;
        return stack[0..stack_size];
    }

    /// Query the currently running coroutine context.
    ///
    /// Warning: Do not dereference the returned pointer.
    ///
    /// Returns: The coroutine currently running on this thread. This function may be
    /// called from the thread's main context as well, in which case it returns a
    /// pseudo-coroutine that represents that context. Attempting to yield from such
    /// pseudo-coroutines leads to undefined behavior. Pseudo-coroutines are never
    /// in the `suspended` state.
    ///
    pub inline fn active() *Coroutine {
        const raw = koishi.koishi_active();
        std.debug.assert(raw != null);
        return @fieldParentPtr("koishi_coroutine", @as(*koishi.koishi_coroutine_t, raw.?));
    }

    /// Query the system's page size.
    ///
    /// The page size is queried only once and then cached.
    ///
    /// Returns: The page size in bytes
    pub inline fn pageSize() usize {
        return koishi.koishi_util_page_size();
    }

    /// Query the real stack size for a given minimum.
    ///
    /// This function computes the exact stack size that `Coroutine.init` would allocate
    /// given `min_size`.
    ///
    /// Returns: The real stack size. It is the closest multiple of the system page
    /// size that is equal or greater than double the pace size.
    ///
    pub inline fn realStackSize(min_size: usize) usize {
        return koishi.koishi_util_real_stack_size(min_size);
    }

    /// Raw version of `init`. Do not use unless necessary.
    pub inline fn rawInit(co: *Coroutine, min_stack_size: usize, entry_point: RawEntrypoint) void {
        koishi.koishi_init(&co.koishi_coroutine, min_stack_size, entry_point);
    }

    /// Raw version of `recycle`. Do not use unless necessary.
    pub inline fn rawRecycle(co: *Coroutine, entry_point: RawEntrypoint) void {
        koishi.koishi_recycle(&co.koishi_coroutine, entry_point);
    }
};

fn wrapEntryPoint(comptime entry_point: anytype, comptime fn_name: []const u8) RawEntrypoint {
    //Validations
    const info = @typeInfo(@TypeOf(entry_point));
    switch (info) {
        .@"fn" => |Fn| {
            const Ret = Fn.return_type orelse void;
            switch (Fn.params.len) {
                0 => {
                    return struct {
                        pub fn ep(_: ?*anyopaque) callconv(.c) ?*anyopaque {
                            return pointerFrom(Ret)(entry_point());
                        }
                    }.ep;
                },
                1 => {
                    const Param = Fn.params[0].type orelse void;
                    return struct {
                        pub fn ep(data: ?*anyopaque) callconv(.c) ?*anyopaque {
                            return pointerFrom(Ret)(entry_point(fromPointer(Param)(data)));
                        }
                    }.ep;
                },
                else => @compileError("Callback entrypoint must have at most a single parameter"),
            }
        },
        else => @compileError("Argument to " ++ fn_name ++ " must be a function"),
    }
}

const ptr_bits = @bitSizeOf(usize);
fn pointerFrom(comptime T: type) fn (T) callconv(.@"inline") ?*anyopaque {
    const t = @typeInfo(T);
    comptime switch (t) {
        .bool => {
            return struct {
                pub inline fn map(in: bool) ?*anyopaque {
                    return @ptrFromInt(@intFromBool(in));
                }
            }.map;
        },
        .int, .float, .@"struct", .@"union" => {
            return struct {
                pub inline fn map(in: T) ?*anyopaque {
                    return @ptrFromInt(@as(IntThatFits(T), @bitCast(in)));
                }
            }.map;
        },
        .pointer => {
            return struct {
                pub inline fn map(in: T) ?*anyopaque {
                    return @ptrCast(in);
                }
            }.map;
        },
        .optional => |opt| {
            const C = opt.child;
            return struct {
                pub inline fn map(opt_in: ?C) ?*anyopaque {
                    return if (opt_in) |in| pointerFrom(C)(in) else null;
                }
            }.map;
        },
        .@"enum" => |Enum| {
            _ = IntThatFits(Enum.tag_type);
            return struct {
                pub inline fn map(in: T) ?*anyopaque {
                    return @ptrFromInt(@as(IntThatFits(Enum.tag_type), @bitCast(@intFromEnum(in))));
                }
            }.map;
        },
        .void => {
            return struct {
                pub inline fn map(_: void) ?*anyopaque {
                    return null;
                }
            }.map;
        },
        .@"noreturn" => {
            return struct {
                pub inline fn map(_: noreturn) ?*anyopaque {
                    unreachable;
                }
            }.map;
        },
        else => @compileError(@typeName(T) ++ " cannot be boxed into a pointer"),
    };
}
fn fromPointer(comptime T: type) fn (?*anyopaque) callconv(.@"inline") T {
    const t = @typeInfo(T);
    comptime switch (t) {
        .bool => {
            return struct {
                pub inline fn map(in: ?*anyopaque) bool {
                    const int = @intFromPtr(in);
                    return if (int == 0) false else true;
                }
            }.map;
        },
        .int, .float, .@"struct", .@"union" => {
            return struct {
                pub inline fn map(in: ?*anyopaque) T {
                    return @bitCast(@as(IntThatFits(T), @intCast(@intFromPtr(in))));
                }
            }.map;
        },
        .pointer => {
            return struct {
                pub inline fn map(in: ?*anyopaque) T {
                    return @ptrCast(@alignCast(in.?));
                }
            }.map;
        },
        .optional => |opt| {
            const C = opt.child;
            return struct {
                pub inline fn map(opt_in: ?*anyopaque) ?C {
                    return if (opt_in) |in| fromPointer(C)(in) else null;
                }
            }.map;
        },
        .@"enum" => |Enum| {
            const Tag = IntThatFits(Enum.tag_type);
            return struct {
                pub inline fn map(in: ?*anyopaque) T {
                    return @enumFromInt(@as(Tag, @intCast(@intFromPtr(in))));
                }
            }.map;
        },
        .void => {
            return struct {
                pub inline fn map(_: ?*anyopaque) void {
                    return;
                }
            }.map;
        },
        else => @compileError(@typeName(T) ++ " cannot be unboxed from a pointer"),
    };
}

fn IntThatFits(comptime T: type) type {
    const size = @bitSizeOf(T);
    if (size > ptr_bits) {
        @compileError(std.fmt.comptimePrint("{s} cannot be represented as a pointer (bits: {} > {})", .{@typeName(T), size, ptr_bits}));
    }
    return @Type(.{ .int = .{ .bits = size, .signedness = .unsigned } });
}