const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    // const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    // const optimize = b.standardOptimizeOption(.{});

    const tool = b.addExecutable(.{
        .name = "tigerbeetle_repl",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.graph.host,
            // .link_libc = true,
        }),
    });
    b.installArtifact(tool);

    const tool_step = b.addRunArtifact(tool);
    const run_step = b.step("run", "Run tigerbeetle repl");

    run_step.dependOn(&tool_step.step);

    const compile_go = b.addSystemCommand(&.{ "go", "run", "src/main.go" });
    const compile_go_step = b.step("go-run", "compile and run main.go");
    compile_go_step.dependOn(&compile_go.step);

    const format_tigerbeetle_server = b.addSystemCommand(&.{
        "tigerbeetle",       "format",
        "--cluster=0",       "--replica=0",
        "--replica-count=1", "--development",
        "./0_0.tigerbeetle",
    });
    const format_tigerbeetle_server_step = b.step("tb-format", "format tigerbeetle cluster");
    format_tigerbeetle_server_step.dependOn(&format_tigerbeetle_server.step);
}
