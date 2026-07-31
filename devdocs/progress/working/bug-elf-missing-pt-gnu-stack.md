---
summary: "ELF writer emits no PT_GNU_STACK, so our .so files are refused by newer kernels"
type: bug
track: A
prio: 70
---

# Shared objects carry no `PT_GNU_STACK` — dlopen fails on Linux 7.x

- **Type:** bug (ELF writer) — **Track A**
- **Found:** 2026-07-31 by Track T, enrolling a second watcher host.
- **Job:** `test-asm#src:test/test_asm_so.asm` — GREEN on borg, RED on xeon.

## Symptom

```
dlopen: /tmp/.../test_asm_so26.so: cannot enable executable stack as shared
        object requires: Invalid argument
test-asm: .so dlopen round-trip FAILED
```

The `.so` **builds fine** (`ok: ... [code=49B data=64B bss=0B procs=2]`) — only
the `dlopen` round-trip fails. Note this is not a missing-assembler problem;
pxx uses its own asm frontend and nasm is irrelevant here.

## Root cause (measured)

```
$ readelf -lW <pxx-built .so> | grep GNU_STACK
        (nothing — no PT_GNU_STACK segment at all)

$ readelf -lW <gcc-built .so> | grep GNU_STACK
GNU_STACK  0x000000 0x0 0x0 0x000000 0x000000 RW  0x10
```

We emit **no `PT_GNU_STACK` program header**. Absent that header the loader
applies the legacy default — *this object requires an executable stack* — and
tries to remap the stack RWX at load time. Modern kernels refuse, hence
`Invalid argument`.

The fix is to always emit a `PT_GNU_STACK` program header with `RW` (no `X`)
flags, for shared objects and executables alike. This is a one-header addition
in `elfwriter.inc`, not a codegen change.

## Why it only showed up now

| host | kernel | result |
|---|---|---|
| borg | 6.17.0-35-generic | PASS — tolerates the missing header |
| xeon | 7.0.0-28-generic | FAIL — refuses to enable an executable stack |

So this is a **latent bug we have been shipping**, not a regression: any user on
a recent kernel already cannot `dlopen` a pxx-built shared object. The second
host did not cause it, it revealed it — which is precisely the argument for
keeping hosts on differing kernels rather than homogenising them.

## Scope to check while fixing

- executables as well as `.so` (same header, same default)
- all targets, not just x86-64 — the ELF writer is shared
- whether anything in the runtime actually *wants* an executable stack (it
  should not; if something does, that is the real bug)

## Notes

- Filed by Track T; T owns the tool, never the bug — not fixed here.
- Blocks nothing on the xeon enrollment: it is a real red that the new host is
  correctly reporting, and it should stay red until fixed rather than be
  skipped. Track T is NOT adding a skip for this.
