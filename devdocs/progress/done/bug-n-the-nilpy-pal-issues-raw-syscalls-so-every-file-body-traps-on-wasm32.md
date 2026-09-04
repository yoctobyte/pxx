---
slug: bug-n-the-nilpy-pal-issues-raw-syscalls-so-every-file-body-traps-on-wasm32
track: N
prio: 30
type: bug
status: done
blocked-by: []
owner: frankb-78
created: 2026-09-04
found-by: frankA (wasm32 gap census)
summary: "FIXED 2026-09-04. Two changes. (1) pypal.pas funnels all 17 __pxxrawsyscall sites through ONE PyPalSys whose body is conditional on the very {$ifndef} chain that already set PYPAL_HAVE := False -- so a target with no syscall table now emits NO syscall instruction, not merely a runtime guard in front of one. A NilPy program for wasm32 went from 41 errors on pin v403 to ZERO `value IR op 54` gaps. (2) PLATFORM_WASI, derived from TARGET_WASM32, so the driver selects lib/rtl/platform/wasi instead of posix; a Pascal file-I/O program for wasm32 did not COMPILE before (undefined variable SYS_getgid) and now builds and runs. THE FORK IS SETTLED TWO DIFFERENT WAYS ON PURPOSE -- real wasi for the Pascal RTL, the ESP defined-failure precedent for pypal -- and the body says which is which."
---

# The NilPy PAL issues raw syscalls, so every file body traps on wasm32

## Measured

300 corpus sources compiled for wasm32 with the per-gap coverage report
(`52d134518`), after the Variant and set arms landed:

```
   18  value IR op 54          <- IR_SYSCALL
   13  indirect call returning an aggregate
    9  slot has no wasm value type
   ...
```

`value IR op 54` is IR_SYSCALL and it is the largest remaining group. Fifteen of
the eighteen are in one program and they are all PyPal bodies:

```
    PyPalPoll — value IR op 54
    PyPalOpen — value IR op 54
    PyPalRead — value IR op 54
    PyPalWrite — value IR op 54
    PyPalClose — value IR op 54
    PyPalLseek — value IR op 54
    ... PyPalFtruncate, PyPalUnlink, PyPalRename, PyPalReadlink, PyPalGetcwd
```

## Why this is not a codegen ticket

**An IR_SYSCALL arm for wasm32 cannot be written.** wasi has no syscall
numbers; it has imported functions. So the refusal is CORRECT about the
instruction and wrong about the program: the body should never have been asked
to issue a raw syscall on this target.

`compiler/builtin/pypal.pas` has no `wasm`, `wasi` or platform conditional in it
at all — grep returns nothing. It selects a syscall NUMBER per target and issues
it. Meanwhile `lib/rtl/platform/wasi` exists and is what the Pascal RTL uses.

## The open question, which is why this is a ticket and not a fix

A body that traps and a body that returns a defined error are both defensible
and they are different products:

- **Trap.** A NilPy program doing file I/O on wasm32 stops at the call, loudly.
- **`PAL_ERR_UNSUPPORTED`.** The ESP precedent: *33 PAL entries refuse
  deliberately, so POSIX-shaped code meets `PAL_ERR_UNSUPPORTED` rather than a
  wrong answer.* wasi is not a Unix in the same way ESP is not a Unix.

The third option is the real one: **route pypal through the wasi backend** and
support open/read/write/close/lseek/getcwd for real, refusing only what wasi
genuinely lacks (`unlink`, `rename` and `readlink` all exist in wasi preview1;
`ppoll` does not map cleanly).

Whoever takes this should decide that first, because it changes what "fixed"
means.

## Not a wasm32-only observation

The same file is the reason a NilPy program cannot do file I/O on any target
whose syscall numbers pypal does not carry. wasm32 is where it is VISIBLE,
because that backend turns an unlowerable body into a recorded refusal instead
of a silent miscompile.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit bce31c210.

## FIXED 2026-09-04 (frankb-78) — and the fork went two ways, deliberately

The ticket says whoever takes this must decide first, because it changes what
"fixed" means. It does, and the honest answer is that the two layers want
different answers.

**The Pascal RTL gets option 3, real wasi**, because the work was already done
and only the routing was missing. `lib/rtl/platform/wasi/platform_backend.pas`
existed and its own header said *"this needs no compiler change — pass
`-Fulib/rtl/platform/wasi`"*. That is true, and it is also why nothing used it:
the default PAL is chosen by `AddDefaultPasUnitDirs` from `TargetPlatform`,
which had exactly two values. wasm32 now derives `PLATFORM_WASI`.

    Pascal, Assign/Rewrite/WriteLn/Close, --target=wasm32
      before:  undefined variable (SYS_getgid) — does not compile
      after:   builds, runs, reaches a real wasi I/O error under wasmtime
               (no preopened directory: the sandbox, not the compiler)

A third `PLATFORM_` value rather than an arm of posix, for the reason that
backend's own header gives: posix reaches the kernel through a table of Linux
syscall NUMBERS, and wasm has no syscall instruction and no number space, so
there is nothing to add an `{$ifdef}` to — the MECHANISM differs, not the
constants. `--platform=wasi` is accepted explicitly too, and `--where` reports
the wasi dir, which is the diagnostic that exists so this cannot drift.

**pypal itself gets option 2, the ESP precedent** — a defined failure, not a
trap and not a wasi implementation. `PyPalSupported` and the `-1` returns were
ALREADY that contract; what was missing is that the promise was made at RUNTIME
while the syscall instruction was still emitted, so a body did not fail softly,
it failed to compile. One funnel fixes exactly that:

    17 __pxxrawsyscall sites -> 1, in PyPalSys
    that one site is {$ifdef PYPAL_NO_SYSCALLS} -> return -1
    and PYPAL_NO_SYSCALLS is declared INSIDE the same {$ifndef} chain that
    already decides PYPAL_HAVE := False, so the two cannot drift

    NilPy for wasm32, gap report:  15x `value IR op 54`  ->  ZERO
    (pin v403 on the same source: 41 error lines)

Routing pypal through wasi imports for real is worth doing and is NOT done
here: [[feature-n-route-pypal-through-wasi-imports-so-nilpy-can-do-file-io-on-wasm32]].

## What this does NOT unblock, measured rather than assumed

A NilPy program now COMPILES for wasm32 and is still not RUNNABLE: `statement
IR op 51` (IR_ZERO_SYM) in four bodies, plus `op 60` and `op 32`, and wasmtime
rejects the module with `invalid var_u32: integer representation too long`.
Those are wasm32 CODEGEN and belong to whoever holds that target. I have not
filed them from this one program — frankA reports that backend's gaps from a
300-source census, and one program is a worse instrument than the one already
pointed at it.

## Not regressed, checked against the pin rather than assumed

`test_nilpy_file_read` is byte-identical to pin v403 on x86-64, i386, aarch64
and arm32, and so are `test_nilpy_file_open`, `file_write_text`,
`file_close_readlines` and `environ` on native. riscv32 fails identically on
BOTH binaries (`a heap arena needs mmap` —
[[bug-a-nilpy-on-cross-targets-four-remaining-walls]]), which is the reading
that separates "my change broke it" from "it was already walled off".
