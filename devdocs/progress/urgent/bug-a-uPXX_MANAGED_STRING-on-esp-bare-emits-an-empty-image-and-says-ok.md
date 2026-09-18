---
slug: bug-a-uPXX_MANAGED_STRING-on-esp-bare-emits-an-empty-image-and-says-ok
type: bug
track: A+S
prio: 75
status: urgent
found: 2026-09-18
summary: "`-uPXX_MANAGED_STRING --target=esp32c3 --esp-profile=bare` compiles `writeln('hello')` to a 20-byte code segment, prints `ok:` with exact byte counts, and exits 0. The program is gone. THE TELL IS THAT AN EMPTY PROGRAM AND A HELLO-WORLD ARE BYTE-IDENTICAL INCLUDING DATA — on x86-64 the same pair differs by 40 bytes of data (the string literal) and the hello-world RUNS. Silent: no diagnostic, no refusal, a well-formed ELF that does nothing."
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

## Correction 2026-09-18 — `procs=0` IS NOT THE TELL, AND THIS TICKET LEANED ON IT

Filed leaning on `procs=0` as the evidence. That is wrong and would have sent a
reader hunting in the wrong place. **x86-64 reports `procs=0` for the identical
flag and prints `hello` correctly**, measured today:

    pascal26 -uPXX_MANAGED_STRING --no-signals hello.pas out
    ok: [code=3864B data=336B bss=41800B procs=0]   ->  ./out  =>  hello

`procs=0` means the whole program lowered to backend-emitted machine code with
no Pascal procedure bodies left — which is the NORMAL and correct outcome for a
`writeln` of a literal once the managed-string runtime is out. It says nothing
about whether the program exists.

**The discriminator is the byte-identity of empty-vs-hello, and it must include
`data=`.** On x86-64 the two differ by 40 bytes of data, because the literal is
there. On ESP bare they are identical in code AND data, because nothing was
emitted. Anyone re-measuring this should compare the pair, not read `procs`.

Also corrected in the same pass: `code=` is **page-quantised**, so the `20B`
above is a floor-of-a-segment figure and not a code measurement — see the
2026-09-18 logbook entry and `symtab.inc:14858`, which already said so.
