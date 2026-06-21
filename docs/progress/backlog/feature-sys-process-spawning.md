# Process spawning and execution support — libc-free execve pipeline

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-21
- **Relation:** Stresses system calls, file descriptor redirection, and child stack safety in the compiler. Blocker for feature-demo-video-player.

## Goal

Provide a statically-linked, libc-free process spawning API using raw system calls (`sys_vfork`, `sys_execve`, `sys_pipe2`, `sys_dup2`, `sys_wait4`).

## Surface (sketch)

In `lib/rtl/platform.pas`:
- Expose system calls for target architectures.
- Signature wrappers for:
  - `function sys_vfork: PID;`
  - `function sys_execve(const pathname: PChar; argv: PPChar; envp: PPChar): Integer;`
  - `function sys_pipe2(var pipefd: array of Integer; flags: Integer): Integer;`
  - `function sys_dup2(oldfd, newfd: Integer): Integer;`
  - `function sys_wait4(pid: PID; var wstatus: Integer; options: Integer; rusage: Pointer): PID;`

In a new process control unit or `sysutils`:
- `function ExecutePipeline(const cmd: AnsiString; const args: array of AnsiString; var childStdinFd, childStdoutFd: Integer): PID;`

## Implementation Steps

1. Expose the raw system calls per architecture.
2. Implement safety wrapper for child execution under `sys_vfork`/`sys_clone`: the child must call `sys_execve` or `sys_exit` directly without returning to the caller function to prevent clobbering the parent stack.
3. Manage pipe descriptors and redirect stdin/stdout of the child process.

## Log
- 2026-06-21 — Opened.
