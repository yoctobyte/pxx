---
slug: bug-a-uPXX_MANAGED_STRING-on-esp-bare-emits-an-empty-image-and-says-ok
type: bug
track: A+S
prio: 75
status: open
found: 2026-09-18
summary: "`-uPXX_MANAGED_STRING --target=esp32c3 --esp-profile=bare` compiles `writeln('hello')` to procs=0 and a 20-byte code segment, prints `ok:` with exact byte counts, and exits 0. The same source with the managed runtime emits 72 procs / 57,900 B. An empty program and a hello-world are BYTE-IDENTICAL under the flag, which is the tell. Silent: no diagnostic, no refusal, a well-formed ELF that does nothing."
---

# What

    pascal26 -uPXX_MANAGED_STRING --target=esp32c3 --esp-profile=bare hello.pas out
    ok: out  [code=20B  data=296B  bss=37560B  procs=0]

`procs=0`. The program is gone. With the flag omitted the same source gives
`code=57900B ... procs=72` and is a real image.

| build | code | procs |
| --- | --- | --- |
| esp32c3 bare, default | 57,900 | 72 |
| esp32c3 bare, `-uPXX_MANAGED_STRING` | 20 | **0** |
| esp32s3 bare, `-uPXX_MANAGED_STRING` | 52 | 0 |
| x86-64, `-uPXX_MANAGED_STRING` | 3,864 | (runs correctly, prints `hello`) |

**x86-64 is FINE** — it prints `hello`, rc=0. So this is not the flag being
broken in general; it is the flag on the ESP bare path.

## The tell, and why nothing caught it

`empty.pas` and `hello.pas` produce **byte-identical** output under the flag.
A program whose body cannot change the image is a program that was not
compiled. Nothing asserts that today.

This is the shape CLAUDE.md already names for a different cause — *"a full disk
makes the compiler lie green: no write in elfwriter.inc is checked, so ENOSPC
yields `ok:` with exact byte counts for a truncated binary"*. Same signature,
different door: **`ok:` plus exact byte counts is not evidence that anything was
emitted.** The byte counts are honest about a buffer that is empty.

## Why it is prio 75 and in urgent/

Not because the flag is common — it is not the default. Because the failure is
SILENT and the artifact is well-formed: a flashed image would boot into nothing
and the compiler said `ok`. A refusal would be fine; a wrong answer that passes
for a right one is not. It also sits directly under the ESP size work, where
`-uPXX_MANAGED_STRING` is the obvious lever someone will reach for next —
[[bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce]] names exactly
that define as the reason a Pascal hello-world pulls `builtinheap`
unconditionally.

## First checks for whoever takes it

1. Does `DetectPascalRuntimeNeeds` leave `needsHeap` false and then something
   downstream refuse to emit any proc at all on the bare path? (`needsAnsiRuntime
   := PasDefineExists('PXX_MANAGED_STRING')`, `pasparser_prog.inc:104`; under the
   flag it is False and `needsHeap` is not forced at :199.)
2. Is the writeln lowered to a builtin that only exists in the heap unit, so it
   silently resolves to nothing rather than erroring?
3. **Positive control, and it is free:** assert that `empty.pas` and
   `hello.pas` do NOT produce identical images on any target. That single row
   would have caught this and catches the whole class.

## Do not

Do not "fix" it by re-defining PXX_MANAGED_STRING on the bare path. That
restores the 57,900-byte floor this flag exists to escape, and the escape is
what the ESP size work needs. The correct outcome is either a working small
image or an explicit refusal.
