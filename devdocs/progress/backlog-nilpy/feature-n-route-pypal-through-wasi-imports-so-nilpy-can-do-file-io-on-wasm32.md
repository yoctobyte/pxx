---
track: N
prio: 25
type: feature
blocked-by: []
status: backlog
summary: "pypal on wasm32 returns a defined -1 from every entry point rather than trapping (the ESP precedent), which is what made NilPy compile for that target at all. It is not real file I/O: `open` fails, `os.listdir` is empty, `time.time()` raises. wasi preview1 HAS open/read/write/close/seek/getcwd/unlink/rename/readlink as imports, and lib/rtl/platform/wasi already binds them for the Pascal RTL -- so the work is a pypal backend that calls those imports, not new capability. ppoll is the one that does not map."
---

# Route pypal through wasi imports so NilPy can do file I/O on wasm32

## Where this starts from

[[bug-n-the-nilpy-pal-issues-raw-syscalls-so-every-file-body-traps-on-wasm32]]
settled the fork two ways: the Pascal RTL got REAL wasi (the backend already
existed; only the routing was missing), and pypal got the ESP precedent — a
defined failure. That was the right split for unblocking compilation, and it
leaves NilPy on wasm32 able to run and unable to touch a file.

`PyPalSys` is now the single site. On a target without a syscall table its body
is `-1` and no syscall instruction is emitted. **That single site is also the
seam this feature needs** — a wasi arm goes there, or beside it.

## What wasi preview1 actually has

Real imports, so these are implementable rather than refusable:
`path_open`, `fd_read`, `fd_write`, `fd_close`, `fd_seek`, `fd_filestat_set_size`,
`path_unlink_file`, `path_rename`, `path_readlink`, `fd_readdir`,
`clock_time_get`. `lib/rtl/platform/wasi/platform_backend.pas` already binds
this set for the Pascal side — read it first; the argument marshalling is the
work and it is done once there.

`ppoll` is the one that does not map cleanly (wasi has `poll_oneoff` with a
different subscription model), and `getcwd` is a preopen-table question rather
than a call. Refusing those two and implementing the rest is a complete
product.

## The thing to be careful about

wasi paths are relative to a PREOPENED directory descriptor; there is no
ambient filesystem root. So `PyPalOpen(path, flags, mode)` cannot be a
one-to-one translation — it needs the preopen lookup the Pascal backend already
does. **Do not invent a second one.** If that lookup wants to be shared, share
it deliberately rather than by copying, and note that the per-language PAL
duplication is otherwise ACCEPTED on purpose
(`decide-runtime-primitive-layering`).

## How you will know it works

A NilPy program cannot RUN on wasm32 yet for unrelated codegen reasons
(IR_ZERO_SYM and friends), so this cannot be end-to-end tested today. Until
that clears, the honest gate is a compile plus the wasi import section
containing `path_open` — and say so, rather than reporting a green that only
means the module was built.
