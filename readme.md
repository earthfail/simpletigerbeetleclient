# tigerbeetle client in go
tigerbeetle is an oltp database based on double entry accounting built for speed.

This is a client for tigerbeetle using go sdk and planned to be a good starting point for building a backend

# build
- for build go client `go build src/main.go`
- to run tigerbeetle database first create a databasefile (see build.zig "tb-format") and run a repl (see src/main.zig)

# tools
- zig (0.16.0) is mainly used to run tigerbeetle repl and restart go client (src/main.go) on file save
  using inotify and epoll APIs (linux only)
- tigerbeetle repl. build from source or download the binary. It can work for windows but it takes heavy advantage on linux IoUring.


# LICENSE
AGPL
