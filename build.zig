const std = @import("std");

pub fn build(b: *std.Build) void {
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
