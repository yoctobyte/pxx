---
slug: bug-n-the-nilpy-pal-issues-raw-syscalls-so-every-file-body-traps-on-wasm32
track: N
prio: 30
type: bug
status: open
blocked-by: []
owner: unassigned
created: 2026-09-04
found-by: frankA (wasm32 gap census)
summary: "compiler/builtin/pypal.pas issues RAW SYSCALLS unconditionally, so on wasm32 -- which has none -- all fifteen PyPal file bodies are emitted as `unreachable` and trap if called. Measured: 15 of the 57 wasm32 gap instances left over 300 corpus sources, the single largest remaining group and larger than every codegen gap combined. NOT a codegen bug: an IR_SYSCALL arm for wasm32 cannot exist, because wasi has imports rather than syscall numbers. lib/rtl/platform/wasi ALREADY EXISTS for the Pascal RTL and pypal does not use it. Open design question inside: a trapping body and a defined PAL_ERR_UNSUPPORTED are both defensible and the ESP precedent chose the second."
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
