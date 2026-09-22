---
prio: 85
track: A
type: bug
status: done
found: 2026-09-22
found-by: frankh-c0
owner: frankb-8e
blocked-by: []
summary: "FIXED 23fcd326f (frankb-8e). A record used AS A VALUE failed to compile with `compiler error: PXXMemMove not found` on riscv32, xtensa, arm32 and aarch64 -- both bare ESP SoCs and the hosted spellings -- while x86-64, i386 and wasm32 copy inline and were fine. Regression from 523833fde the same day, whose evidence-based needsAnsiRuntime scan (an 82.1% size win that was correctly NOT reverted) could not see a construct that names no heap. MY REPORT NAMED A TRIGGER ONE QUARTER THE TRUE WIDTH AND A RULE WRITTEN TO IT WOULD HAVE PASSED MY OWN REPRO: I reduced to `function M: TB` and proposed matching function-result-of-record-type; 8e varied the shape before choosing a rule and found FOUR breaking shapes -- whole-record assignment `r := q`, by-value record parameter `F(r)`, record function result, and assignment from a typed const -- with field-only access `r.a := 7` the single building case. The real trigger is any record used as a VALUE, which no token-level rule separates from a record DECLARATION without becoming a parser, so the fix is the missing kind beside tkUses/tkArray/tkClass gated on TargetCodegenCallsHeapRuntime. AND `object` LEXES AS tkIdent, not a kind, so a kind-only test misses `TB = object ... end` entirely while passing every record row -- the routine's own string/tkString_T trap in a second keyword. Guard: five rows in test/pascal_ambient_unit_needs_heap.sh, one shape per build, positive-controlled by rebuilding to the pre-fix sha exactly (48f69d2d285d) and back (81bf5f94fb6f), plus a THIRD assertion because the existing two cannot see the cheapest wrong repair. SECOND FRONTEND, SAME SHAPE, ALREADY CLOSED: bug-a-cfront-riscv32-byval-record-result-pxxmemmove (C, p70, 2026-07-20) rooted an 18-job regression cascade -- two frontends, two unrelated causes, one shape, two months apart, which is the argument for feature-a-pull-builtinheap-on-demand-instead-of-predicting-it that neither instance makes alone. Conservative fix measured to cost a bare-ESP field-only record program bss 652 -> 66,824 B at binary 81bf5f94fb6f -- AND THAT ROW WAS FALSIFIED WITHIN THE HOUR BY THIS TICKET'S OWN SIBLING COMMIT: 04e20af2c drops the EspArena when DCE proves HeapMmap dead, and the IDENTICAL program at 8c22736b1a7d is bss 652 -> 1,288 B with and without --dce, a difference of 65,536 exactly. Over-detection costs ~636 B, not ~66 KB. Both rows stand with their binaries. The message announcing that commit said it 'does not help your case, because your trigger pulls builtinheap and keeps the allocator reachable' -- a reasonable reading of one's own change and measurably wrong, since the allocator entry points ARE dead in this shape, which is the condition the drop tests for. One seat's measured number carried into another seat's summary by the very commit that retired it; nothing here depended on the arena staying reserved and two summaries asserted it anyway."
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


## RESOLVED 23fcd326f (frankb-8e) — and my reduction was one shape of four

**Do not read the sections above as the defect's extent.** They describe what I
reduced to, and `frankb-8e` varied the shape before choosing a rule. Measured
riscv32 `--platform=posix`, one row each:

| shape | verdict |
| --- | --- |
| `r := q` whole-record assignment | **BREAKS** |
| `F(r)` record parameter by value | **BREAKS** |
| `function M: TB` record result | **BREAKS** ← the shape I reported |
| `r := K` from a typed const | **BREAKS** |
| `r.a := 7` field-only | builds |

**The rule I proposed — collect `<ident> = record`, then match
`function`/`)` `:` `<that ident>` — would have fixed one of four, PASSED MY OWN
REPRO, and closed this ticket.** That is the exact failure CLAUDE.md names: a
minimal case fixes every axis you did not think about, and those are the axes
you cannot list, because if you could you would have varied them. I had the
rule in front of me all session and my reduction still pinned one axis. The
corpus caught it, as it did the last time.

The true trigger is **any record used as a VALUE**, which no token-level rule
separates from a record DECLARATION without becoming a parser — so the fix is
the missing kind beside `tkUses`/`tkArray`/`tkClass`, gated on
`TargetCodegenCallsHeapRuntime` because x86-64 and i386 copy inline.

**And the half no reduction could have shown me:** `record` lexes as `tkRecord`,
but **`object` lexes as an ordinary `tkIdent`** (`pasparser_generic.inc` asks
`DGenIdentIs(j, 'object')`). A kind-only test misses `TB = object a, b, c:
Integer; end` completely while passing every record row above. That is the same
routine's `string`/`tkString_T` trap in a second keyword, and only running the
shape finds it.

## The arena cost, measured by 8e rather than taken on trust

I argued the conservative rule was not free on `--esp-profile=bare`. 8e measured
it instead of accepting it: a program declaring a record and touching only its
FIELDS goes **bss 652 -> 66,824 B**, code 320 -> 552, procs 17 -> 85. That is the
65,536 B `EspArena`, exactly, for a routine never called. The conservative arm
was taken anyway — correctly, since the alternative is a build break on four
targets — with the cost written into the guard's comment and an explicit line
saying the assertion does **not** bless that arena.

### THAT ROW WAS FALSIFIED BY THIS TICKET'S OWN SIBLING COMMIT, WITHIN THE HOUR

**Both rows stand, each with its binary.** 66,824 B was correct at
`81bf5f94fb6f`. `04e20af2c` — the arena drop, landed the same hour — makes the
IDENTICAL program **bss 652 -> 1,288 B** at `8c22736b1a7d`, with and without
`--dce`. The difference is 65,536 exactly, so the attribution needs no
argument. Over-detection by the record arm costs **~636 B**, not ~66 KB, and
the x86-64 size is what its target gate is actually protecting.

**The message announcing `04e20af2c` said it "does not help your case, because
your trigger pulls builtinheap and keeps the allocator reachable."** That is a
reasonable reading of one's own change and it is measurably wrong — the
allocator entry points are dead in this shape, which is precisely the condition
the drop tests for. Neither of us would have caught it by reading, and the
number had already been written into two summaries by then.

So this is the ordinary stale-summary rule arriving through an unguarded door:
not an author failing to re-read their own sentence, but **one seat's measured
number carried into another seat's summary by the very commit that retired
it.** Nothing in either ticket depended on the arena staying reserved, and both
asserted it anyway. The repair is the one CLAUDE.md prescribes — carry both
rows with their trees rather than overwriting — because a number whose
population and binary were recorded is correctable, and one quoted bare is not.

It is also the evidence
`feature-a-pull-builtinheap-on-demand-instead-of-predicting-it` was missing:
that ticket now carries a measured number instead of an argument, and it is the
layer where this gets fixed properly.

## Second frontend, same shape, already closed two months ago

`bug-a-cfront-riscv32-byval-record-result-pxxmemmove` — C to riscv32, by-value
record result emitting `PXXMemMove` with no builtinheap injected, p70,
2026-07-20 — **rooted an 18-job regression cascade**. Two frontends, two
unrelated causes, one shape, two months apart. Neither instance argues for the
on-demand fix on its own; the pair does.

## Log
- 2026-09-22 - filed by frankh-c0 with a repro and a measured target set - commit e7b8532c9.
- 2026-09-22 - FIXED by frankb-8e, and the fix is wider than the report: four breaking shapes, not the one I reduced to - commit 23fcd326f.
- 2026-09-22 - resolved, with the summary rewritten to lead with 8e's four-row table instead of my reduction. The close is not the fix - commit 04e20af2c.
