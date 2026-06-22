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

## Update (2026-06-22, Track B)

- **O_CLOEXEC pipe fix landed** (commit ab71066): `ExecutePipeline` pipes are now
  close-on-exec, so spawning multiple concurrent children no longer leaks earlier
  children's pipe fds (was an EOF/wait deadlock). Regression:
  `test/lib_process_multi.pas`.
- **Still open (hardening, step 2 of this ticket):** the child branch of
  `PalBackendVforkAndExec` runs a normal Pascal path (dup2/close calls, local
  `res`) on the **shared vfork address space** before `execve`. Per this ticket's
  own design note the child must reach `execve`/`exit` *directly* without writing
  the shared stack. It works in practice today (single + now multi child pass),
  but is fragile. Robust options: a real `fork` (separate address space) so the
  child can set up fds safely, or a leaf-only asm/syscall child trampoline. Not
  blocking the video player anymore.
- **PalKill added** (sys_kill, all posix arches; esp stub): lets callers
  SIGSTOP/SIGCONT/SIGTERM spawned children (used by the video player's audio
  pause/stop). The vfork-child-stack hardening above is still the remaining item.
