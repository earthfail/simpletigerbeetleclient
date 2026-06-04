const std = @import("std");
const ArrayList = std.ArrayList;
const Io = std.Io;
const assert = std.debug.assert;
const log = std.log.scoped(.repl);

pub fn main(init: std.process.Init) !void {
    // return mainIO(init);
    return mainEpoll(init);
}

pub fn mainEpoll(init: std.process.Init) !void {
    // Prints to stderr, unbuffered, ignoring potential errors.
    log.debug("Salam", .{});

    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    for (args) |arg| {
        log.info("arg: {s}", .{arg});
    }
    arena.free(args);
    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    var stdout_buffer: [0]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var child = try std.process.spawn(io, .{
        .argv = &.{
            "tigerbeetle",       "start",
            "--addresses=3000",  "--development",
            "./0_0.tigerbeetle",
        },
        .stdin = .close,
    });
    defer child.kill(io);
    try stdout.print("Tigerbeetle Started\n", .{});

    const go_client_filepath = "src/main.go";
    var watch_go_client: bool = true; // just toss inotify events
    var go_process: ?std.process.Child = null;
    defer if (go_process) |*g_proc| g_proc.kill(io);

    // Q: Why epoll and not poll?
    // A: because that is what I know and want to be better at. (posix == linux right?)

    const linux = std.os.linux;
    const epoll_fd = linux.epoll_create1(0);
    var events: [2]linux.epoll_event = undefined;
    var events_program: [events.len]Event = undefined; // should be a stack
    // epoll stdin
    {
        var ev: linux.epoll_event = .{ .events = linux.EPOLL.IN, .data = .{ .fd = linux.STDIN_FILENO } };
        const res = linux.epoll_ctl(@intCast(epoll_fd), linux.EPOLL.CTL_ADD, linux.STDIN_FILENO, &ev);
        if (res != 0) {
            log.err("epoll_ctl stdin failed", .{});
            return;
        }
    }
    // const inotify_init1_flag: u32 = linux.IN.NOBLOCK; // makes the read from inotify_fd non blocking
    const inotify_init1_flag: u32 = 0;
    const inotify_fd = linux.inotify_init1(inotify_init1_flag);
    // const notify_flags = linux.IN.ALL_EVENTS; // for all events
    const inotify_flags = linux.IN.CLOSE_WRITE;
    var go_client_wd = linux.inotify_add_watch(@intCast(inotify_fd), go_client_filepath, inotify_flags);
    // epoll inotify for main.go client
    {
        var ev: linux.epoll_event = .{ .events = linux.EPOLL.IN, .data = .{ .fd = @intCast(inotify_fd) } };
        const res = linux.epoll_ctl(@intCast(epoll_fd), linux.EPOLL.CTL_ADD, @intCast(inotify_fd), &ev);
        if (res != 0) {
            log.err("epoll_ctl inotify failed", .{});
            return;
        }
    }

    const epoll_timeout: i32 = std.time.ms_per_s * 10;
    var __commands_max: u32 = 4000; // this should be enough right?
    eblk: while (__commands_max > 0) : (__commands_max -= 1) {
        const len = linux.epoll_wait(@intCast(epoll_fd), @ptrCast(&events), events.len, epoll_timeout);
        if (len == 0) {
            // log.info("Timeout reached without any events", .{});
            continue;
        }
        var events_program_len = len;
        var read_stdin: bool = false; // to get just first byte from stdin
        for (events[0..len], events_program[0..len]) |e1, *e2| {
            if (!read_stdin and e1.data.fd == linux.STDIN_FILENO) {
                read_stdin = true;
                var buf: [5]u8 = undefined;
                const res = linux.read(linux.STDIN_FILENO, &buf, 5);
                if (res == 0) {
                    log.err("read 0 bytes from stdin", .{});
                    return;
                }
                if (false) log.debug("buf[0]=|{c}|, res={}", .{ buf[0], res });

                const c = byteCommand(buf[0]);
                e2.* = .{ .command = c };
            } else if (e1.data.fd == inotify_fd) {
                var buf: [1]linux.inotify_event = undefined;
                const res = linux.read(@intCast(inotify_fd), @ptrCast(&buf), @sizeOf(linux.inotify_event));
                if (res == 0) {
                    log.err("read 0 bytes from inotify_fd", .{});
                    return;
                }
                // var ptr: [*]u8 = &buf;
                const event = buf[0];
                if (event.wd != go_client_wd) {
                    log.warn("inotify return wd different from go_client_wd: {}, {}", .{ event.wd, go_client_wd });
                }

                if (event.mask & inotify_flags != 0) {
                    e2.* = .{ .file_edit = {} };
                } else events_program_len -= 1;
            } else {
                log.warn("epoll event has fd different from stdin and inotify: {}, {}", .{ e1.data.fd, inotify_fd });
            }
        }

        for (events_program[0..events_program_len]) |e| {
            switch (e) {
                .command => |c| {
                    switch (c) {
                        .help => {
                            try stdout.print(
                                \\ h: for this message
                                \\ q: quit
                                \\ c: toggle compile go client and run on main.go save ({})
                                \\ f: force compile go client
                                \\
                            , .{watch_go_client});
                            // try stdout.flush();
                        },
                        .quit => break :eblk,
                        .compile_go => {
                            // try compileGo(&go_process, io);
                            watch_go_client = !watch_go_client;
                            if (watch_go_client) {
                                go_client_wd = linux.inotify_add_watch(@intCast(inotify_fd), go_client_filepath, inotify_flags);
                            } else {
                                _ = linux.inotify_rm_watch(@intCast(inotify_fd), @intCast(go_client_wd));
                            }
                        },
                        .force_compile => try compileGo(&go_process, io),
                        .nop => {
                            log.debug("nop", .{});
                        },
                    }
                },
                .file_edit => {
                    if (true) {
                        try compileGo(&go_process, io);
                    } else {
                        try stdout.print("COMPILING GO CLIENT\n", .{});
                        try stdout.flush();
                    }
                },
            }
        }
    }
    try stdout.print("Killing tigerbeetle server and go client\n", .{});
    try stdout.flush();
}

pub fn mainIO(init: std.process.Init) !void {
    // Prints to stderr, unbuffered, ignoring potential errors.
    log.debug("Salam", .{});

    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();

    // Accessing command line arguments:
    const args = try init.minimal.args.toSlice(arena);
    for (args) |arg| {
        log.info("arg: {s}", .{arg});
    }
    arena.free(args);
    // In order to do I/O operations need an `Io` instance.
    const io = init.io;

    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [0]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stdin_buffer: [2]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buffer);
    const stdin = &stdin_reader.interface;

    var child = try std.process.spawn(io, .{
        .argv = &.{
            "tigerbeetle",       "start",
            "--addresses=3000",  "--development",
            "./0_0.tigerbeetle",
        },
        .stdin = .close,
    });
    var go_process: ?std.process.Child = null;
    try stdout.print("Tigerbeetle Started\n", .{});

    const queue_buffer = try init.gpa.alloc(Event, 5);
    defer init.gpa.free(queue_buffer);
    var queue: Io.Queue(Event) = .init(queue_buffer);

    var receive_commands_fut = try io.concurrent(receiveCommands, .{ io, &queue, stdin });
    defer _ = receive_commands_fut.cancel(io);

    var __commands_max: u32 = 1000;
    while (__commands_max > 0) : (__commands_max -= 1) {
        const e = queue.getOne(io) catch |err| {
            log.err("queue getone got error: {}", .{err});
            break;
        };
        switch (e) {
            .command => |c| {
                switch (c) {
                    .help => {
                        try stdout.print(
                            \\ h: for this message
                            \\ q: quit
                            \\ c: compile go client and run
                            \\
                        , .{});
                        // try stdout.flush();
                    },
                    .quit => break,
                    .compile_go => {
                        try compileGo(&go_process, io);
                    },
                    .nop => {
                        log.debug("nop", .{});
                    },
                }
            },
            .file_edit => {
                try compileGo(&go_process, io);
            },
        }
    }
    try stdout.print("Killing tigerbeetle server and go client\n", .{});
    try stdout.flush();

    queue.close(io);
    child.kill(io);
    if (go_process) |*g_proc| g_proc.kill(io);
}

fn compileGo(go_process: *?std.process.Child, io: Io) !void {
    if (go_process.*) |*g_proc| {
        g_proc.kill(io);
    }
    go_process.* = try std.process.spawn(io, .{
        .argv = &.{ "zig", "build", "go-run" },
        .stdin = .close,
    });
}

fn receiveCommands(io: Io, queue: *Io.Queue(Event), reader: *Io.Reader) void {
    var fin: bool = false;
    while (!fin) {
        const c = getCommand(reader);
        queue.putOne(io, .{ .command = c }) catch |err| switch (err) {
            error.Closed => {
                fin = true;
            },
            error.Canceled => {
                fin = true;
                log.warn("Queue canceled and stopped receiving commands", .{});
            },
        };
        fin = (c == .quit); // doesn't matter much but removed the warning from getCommand takeDelimiter
    }
    log.info("Receive finished", .{});
}

fn getCommand(reader: *Io.Reader) Command {
    // return getCommandFromByte(reader);
    return getCommandFromLine(reader);
}
fn byteCommand(b: u8) Command {
    if (b == 'h') {
        return .help;
    } else if (b == 'q') {
        return .quit;
    } else if (b == 'c') {
        return .compile_go;
    } else if (b == 'f') {
        return .force_compile;
    }
    return .nop;
}
fn getCommandFromByte(reader: *Io.Reader) Command {
    const b = reader.takeByte() catch |err| {
        log.debug("error while getting a line: {}", .{err});
        return .nop;
    };
    return byteCommand(b);
}
fn getCommandFromLine(reader: *Io.Reader) Command {
    // const b = reader.takeByte() catch return .nop;
    const line_m = reader.takeDelimiter('\n') catch |err| {
        log.warn("error while getting a line: {}", .{err});
        return .nop;
    };
    if (line_m) |line| {
        if (line.len > 0) {
            const b = line[0];
            return byteCommand(b);
        }
        return .nop;
    } else {
        log.warn("null while getting a line", .{});
        return .nop;
    }
}

const Command = enum {
    help,
    quit,
    compile_go,
    force_compile,
    nop,
};

const EventType = enum { command, file_edit };
const Event = union(EventType) {
    command: Command,
    file_edit: void,
};
