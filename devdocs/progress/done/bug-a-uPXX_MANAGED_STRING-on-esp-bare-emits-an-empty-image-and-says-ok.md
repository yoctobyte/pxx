---
slug: bug-a-uPXX_MANAGED_STRING-on-esp-bare-emits-an-empty-image-and-says-ok
type: bug
track: A+S
prio: 75
status: done
found: 2026-09-18
summary: "RESOLVED 2026-09-18, AND THE TITLE IS WRONG: the flag is not involved. empty.pas and hello.pas are BYTE-IDENTICAL on --esp-profile=bare WITH AND WITHOUT -uPXX_MANAGED_STRING, on esp32c3 and esp32s3 — the flag stripped 57 KB of unrelated runtime and made an identity that was already there visible. Nor is the program gone: an assignment survives the same build (code 52 vs 20). `writeln` specifically lowers to nothing, via an empty `if EspBareBoot then begin end` arm at ir_codegen_riscv32.inc:3569 — and that is DOCUMENTED and intended, docs/targets/esp32.md:70, 'writeln/readln are intentionally no-ops — there is no console'. So the image was correct and THE SILENCE was the defect. FIXED: a once-per-compilation warning at the parse choke point ParsewriteArgsAST, naming the doc line and offering --platform=posix. Four controls, and the negative one made it usable — the first cut lived in the backend arms and fired on a program with no console output at all, because the linked RTL's own writelns reach that arm. THE LARGER DEFECT THIS WAS SITTING ON is filed separately: the two ESP backends ask different questions and disagree on the IDF profile, where nothing is documented as a no-op — bug-a-writeln-diverges-between-the-two-esp-backends-on-the-idf-profile."
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

## Correction 2026-09-18 (frankS) — THE FLAG IS NOT INVOLVED, AND THE NO-OP IS DOCUMENTED

Took this with the discriminator the correction above prescribes — compare the
empty/hello PAIR including `data=`, do not read `procs`. Applying it one step
further than the ticket did retires the headline.

**`-uPXX_MANAGED_STRING` is not implicated.** `empty.pas` and `hello.pas` are
byte-identical on `--esp-profile=bare` **with and without the flag**, on both
architectures:

| build | flag | empty | hello | identical? |
| --- | --- | --- | --- | --- |
| esp32c3 bare | `-uPXX_MANAGED_STRING` | `code=20 data=296` | `code=20 data=296` | **yes** |
| esp32c3 bare | *(none)* | `code=57900 data=616` | `code=57900 data=616` | **yes** |
| esp32s3 bare | *(none)* | `code=46436 data=616` | `code=46436 data=616` | **yes** |
| x86-64 | `-uPXX_MANAGED_STRING` | `data=296` | `data=336` | no (the 40-byte literal) |

The flag removed 57 KB of unrelated runtime and made an identity that was
already there **visible**. It is the messenger.

**And the program is not gone.** An assignment survives the same build:

    empty.pas   code=20B  bss=37560B
    assign.pas  code=52B  bss=37564B     { i := 12345 }
    hello.pas   code=20B  bss=37560B     { writeln('hello') }

Codegen works. **`writeln` specifically lowers to nothing** — for a string and
for an integer alike.

**The mechanism is an empty branch, and it is deliberate.**
`ir_codegen_riscv32.inc:3569`:

```pascal
IR_WRITE, IR_WRITELN:
  begin
    if EspBareBoot then
    begin
      { Bare-metal: write/writeln does nothing (UART output is explicit
        MMIO in user code, see test_esp_bare.pas). }
    end
```

`docs/targets/esp32.md:70` states it as a feature, scoped to this profile:
*"`writeln`/`readln` are intentionally no-ops — there is no console. Output
goes through your own UART writes."* So the emitted image is CORRECT. **What
was wrong was that nobody was told**, which is the half this ticket got right.

## FIXED — the silence, not the no-op

A once-per-compilation warning at the parse choke point
(`ParsewriteArgsAST`, `pasparser_stmt.inc`):

    pascal26:3: warning: write/writeln emits nothing on this ESP profile:
    there is no console. Write to the UART from your own code
    (docs/targets/esp32.md:70), or build a hosted image with --platform=posix.

Four controls, all measured: hello on bare c3 **warns** (with a real line);
hello on bare s3 **warns**; an EMPTY program **does not**; hosted x86-64 does
not and still prints `hello`. Three `writeln`s produce one warning.

**Why the parse site and not the backend.** The first cut put it in the two
codegen arms and it fired on a program with no console output at all — the
linked RTL's own `writeln` calls reach that arm. `CurrentUnitIdx = -1`
restricts it to the main program, and only the parse site knows that. **A
warning that fires on every ESP compile is not a warning**, and the empty-program
negative control is what caught it; without that row this would have shipped.

## What this ticket should NOT be closed on: a bigger defect it was sitting on

The two backends spell the guard differently and **disagree on the IDF
profile**, which is not documented as a no-op anywhere:

| backend | guard | bare | IDF profile |
| --- | --- | --- | --- |
| xtensa | `TargetPlatform = PLATFORM_ESP` | drops | **drops — objects byte-identical** |
| riscv32 | `EspBareBoot` | drops | **emits, into the syscall write path** |

Measured with `--emit-obj`: xtensa `--platform=esp` gives `code=208948` for both
empty and hello; riscv32 `--platform=esp` gives `258788` vs `258828`, a 40-byte
delta in code AND data. The riscv32 object has **32 `ecall`s** against the bare
object's 2, and `write` is **not** an external — only `calloc` and `free` are —
so that path traps to IDF's machine-mode handler rather than printing.

xtensa is the primary ESP target and the one that silently drops. Filed as
[[bug-a-writeln-diverges-between-the-two-esp-backends-on-the-idf-profile]].

## Log
- 2026-09-18 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 16ebf18ce.
