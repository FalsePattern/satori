# satori

Ziggified bindings for the [koishi](https://github.com/taisei-project/koishi) C coroutine library.

## How to use it

First, update your `build.zig.zon`:

```shell
zig fetch --save "git+https://github.com/FalsePattern/satori/#master"
```

Next, add this snippet to your `build.zig` script:

```zig
const satori_dep = b.dependency("satori", .{
    .target = target,
    .optimize = optimize,
});
your_module.addImport("satori", satori_dep.module("satori"));
```

This will provide satori as an importable module to `your_module`, and links it against koishi.

## Additional options

```
.verbose = [bool]             Verbose logging for configure phase. [default: false]
.impl = [enum]                Which implementation to use. Leave empty to autodetect.
                                Supported Values:
                                  emscripten
                                  fcontext
                                  ucontext
                                  ucontext_e2k
                                  ucontext_sjlj
                                  win32fiber
.threadsafe = [bool]          Whether multiple coroutines can be ran on different threads at once (needs compiler support) [default: true]
.valgrind = [bool]            Enable support for running under Valgrind (for debugging) [default: false]
.linkage = [enum]             Whether the koishi library should be statically or dynamically linked. [default: static]
                                Supported Values:
                                  static
                                  dynamic
```

Using the emscripten implementation requires `-s ASYNCIFY` in your emscripten linker args!