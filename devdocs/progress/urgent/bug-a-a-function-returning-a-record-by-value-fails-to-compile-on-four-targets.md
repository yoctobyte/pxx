---
prio: 85
track: A
type: bug
status: new
found: 2026-09-22
found-by: frankh-c0
owner: ""
blocked-by: []
summary: "A function whose RESULT TYPE is a record fails to compile with `compiler error: PXXMemMove not found` on riscv32, xtensa, arm32 and aarch64 -- both bare ESP SoCs and the hosted spellings -- while x86-64, i386 and wasm32 are fine. Ordinary Pascal, no strings and no allocation in the source. REGRESSION, measured 2026-09-22: the PINNED compiler (v418) compiles the repro and HEAD does not. Cause is 523833fde (same day), which replaced an unconditionally-true needsAnsiRuntime with an evidence-based token scan -- a real 82.1% size win that must NOT be reverted for this. The by-value record return lowers onto PXXMemMove on exactly the four targets frontend_prologue.inc:168 names for the aggregate-result epilogue, and nothing in the source says `heap`, so the scan cannot see it. The trigger is a CONSTRUCT and not a name, which is what makes it awkward: every other entry in that scan matches an identifier or token kind, and this one is `function ... : <T>` where T was declared `= record`. A record type alone is NOT enough -- `var r: TBig; r.a := 7` compiles clean on esp32c3 at 296 B. Topic is held by frankb-8e, who owns that scan and has been told; owner deliberately left empty. NOTE FOR WHOEVER FIXES IT: the crude rule (any tkRecord plus one of the four targets) closes it but over-detects, and on --esp-profile=bare over-detection is NOT `only size` -- pulling builtinheap there reserves a 65,536 B EspArena, ~16% of the chip's SRAM."
---

# A function returning a record by value fails to compile on four targets

## Repro — 11 lines, no strings, no allocation

    program recret;
    type TBig = record a, b, c: Integer; end;
    function MkBig(x: Integer): TBig;
    begin
      MkBig.a := x; MkBig.b := x; MkBig.c := x;
    end;
    var r: TBig;
    begin
      r := MkBig(7);
      if r.a = 0 then Halt(1);
    end.

    pascal26:45: error: compiler error: PXXMemMove not found

## Target set — one row each, measured, not inferred

| target | verdict |
| --- | --- |
| `--esp-profile=bare --target=esp32c3` | **PXXMemMove not found** |
| `--esp-profile=bare --target=esp32s3` | **PXXMemMove not found** |
| `--target=riscv32` | **PXXMemMove not found** |
| `--target=xtensa` | **PXXMemMove not found** |
| `--target=arm32` | **PXXMemMove not found** |
| `--target=aarch64` | **PXXMemMove not found** |
| `--target=i386` | ok (`code=713B`) |
| `--target=wasm32` | ok (`code=104B`) |
| x86-64 (default) | ok (`code=821B`) |

Those four are the set `frontend_prologue.inc:168` already names for the
aggregate-result epilogue, plus xtensa's own `PXXMemMove` sites — not a new set.

**A RECORD ALONE IS NOT THE TRIGGER.** `type TBig = record a, b, c: Integer;
end; var r: TBig; begin r.a := 7; end.` compiles clean on esp32c3,
`code=296B data=360B bss=656B procs=17`. The trigger is specifically a function
whose RESULT TYPE is a record.

## It is a regression, and the control is the pin

    stable_linux_amd64/default/pinned  --esp-profile=bare --target=esp32c3
      ok: code=6216B data=656B bss=66888B procs=90

    compiler/pascal26 (464ddd6c2b02)   --esp-profile=bare --target=esp32c3
      error: compiler error: PXXMemMove not found

## Cause, and why it must not be reverted

`523833fde` (2026-09-22) replaced

    needsAnsiRuntime := PasDefineExists('PXX_MANAGED_STRING');

— which answered True for every program ever compiled, because the define was
set unconditionally — with an evidence-based token scan. That is a large and
correct win: x86-64 hello-world 25,016 -> 4,472 B (-82.1%), xtensa bare 860 -> 58
B of code with procs 88 -> 0.

**Its own commit comment predicts this failure and the prediction held exactly:**

> *"a name missing from this scan is a BUILD BREAK, never a miscompile — loud,
> attributable, and fixed by adding the name."*

Loud, attributable, nothing miscompiled. This ticket is the "adding the name"
step, not an argument against the change.

## Why it is harder than adding a name

Every other entry in that scan matches an **identifier** or a **token kind**.
This trigger is a **construct**: `function ... : <T>` where `T` was declared
`= record`. A single forward pass suffices — Pascal declares a record type
before using it as a result type, so collecting `<ident> = record` names and
then matching `function`/`)` `:` `<that ident>` works in one loop over the same
token stream the scan already walks.

**Do not reach for the crude rule without pricing it.** "Any `tkRecord` present
AND one of the four targets" closes the hole and over-detects. The commit's own
reasoning says over-detection costs only size — **that is true on the hosted
three and false on `--esp-profile=bare`**, where pulling `builtinheap` reserves a
65,536 B `EspArena`, about 16% of the chip's SRAM. See
`feature-s-the-64-kib-esp-heap-arena-is-reserved-even-when-dce-proves-the-allocator-unreachable`.

## Two findings alongside, both independent of the cause

**The ESP harness reports a BUILD FAILURE as a VALUE MISMATCH.** `Makefile:36123`
runs `tools/esp_run_bare.sh ... 2>/dev/null`, so the compiler's diagnostic is
discarded and the test prints

    --- test_esp_record_result.oracle
    +++ test_esp_record_result.c3
    @@ -1,5 +0,0 @@
    esp32c3 record result MISMATCH

An empty file against a 5-line oracle. That sends the reader to codegen when the
compiler had already said what was wrong, in a sentence, on stderr. Worth a
`|| echo` on the build step.

**DCE was nearly blamed.** `372dd5113` is a recent DCE commit, the symptom was
empty output, and the coincidence is persuasive. `--no-dce` fails identically,
which exonerates DCE in one command — and it only counted because the
expectation was recorded before the run.

## Ownership

`frankb-8e` holds this topic (it owns that scan and has a further patch on it).
Messaged 2026-09-22 with the repro and the target set. `owner:` deliberately
left empty so the ranker does not read it as claimed.
