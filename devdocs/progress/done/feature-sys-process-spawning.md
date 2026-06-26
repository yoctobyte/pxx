# Process spawning and execution support — libc-free execve pipeline

- **Type:** feature
- **Status:** done (host) — PalKill + O_CLOEXEC + real-fork hardening; cross-arch qemu pending
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

## DONE on host (2026-06-22, Track B)

All three items landed and verified on x86-64:
1. raw-syscall pipeline (vfork/execve/pipe2/dup2/wait4) — was already in place.
2. **O_CLOEXEC pipes** — concurrent children no longer leak each other's fds
   (regression: test/lib_process_multi.pas).
3. **PalKill** (sys_kill) — SIGSTOP/SIGCONT/SIGTERM children (used by the player's
   audio).
4. **Child-stack safety SOLVED by switching to real `fork`** (own COW address
   space) instead of vfork/clone(CLONE_VM|VFORK). The "child must exec without
   returning" hazard is gone — the child can run its dup2/close/execve path
   safely. x86-64 SYS_fork; aarch64 clone(SIGCHLD).

Verified x86-64: lib_process, lib_process_multi, video player + audio, full
lib-test. **Remaining:** i386/arm32/aarch64 are the same mechanical change but
need a qemu cross smoke (Track A `make test-i386/aarch64/arm32`). Closing the
host work; reopen a focused cross-validation ticket if a target diverges.
