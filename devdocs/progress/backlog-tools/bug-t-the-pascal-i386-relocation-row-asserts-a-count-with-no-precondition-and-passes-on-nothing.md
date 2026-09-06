---
slug: bug-t-the-pascal-i386-relocation-row-asserts-a-count-with-no-precondition-and-passes-on-nothing
track: T
prio: 55
type: bug
status: backlog-tools
found: 2026-09-06
found-by: frankB
owner: ""
blocked-by: []
summary: "The Pascal i386 absolute-relocation row in `test-emit-obj` asserts `R_386_32 count == 0` over `readelf -rW` output with NO precondition that anything was read, so it passes on an empty relocation section, on a missing file, and — measured — on the string `not an elf file`. `awk ... END{exit (n+0)==0 ? 0 : 1}` leaves `n` unset when nothing matches, and unset is zero, which is the expected value. The C-side row TWENTY LINES ABOVE IT already carries the missing guard — it asserts the RELATION `pcr > abs` before asserting `abs == 0`, and its comment says exactly why: *'A bare nonzero PC32 count stays green after a whole family stops converting; this does not.'* The reasoning was written down and not carried down. Second, independent weakness reported by frankD from the row they cleared: the count can reach 0 by ACCIDENT — one extra unrelated local in `PXXIoCheck` moves `code` off `-0x10` and the count goes 1 -> 0 with the conversion untouched — so even a correctly-read zero does not prove the mechanism. Fix is the pattern already in the file: assert the population is non-empty and assert a relation, not a bare count."
---

# The Pascal i386 relocation row is a guard that cannot fail

## Measured

The row (`Makefile`, the Pascal-object arm of `test-emit-obj`, just below the
C-object arm):

```make
readelf -rW $(TESTTMP)/test_emit_obj_386.o | awk '/Relocation section/{s=($$0 ~ /rel\.text/)} s && /R_386_32/{n++} END{exit (n+0)==0 ? 0 : 1}' || { echo "..."; exit 1; }
```

`n` is unset when nothing matches, `n+0` is 0, and 0 is the expected value. So:

| input | exit | reads as |
| --- | --- | --- |
| an object with no `R_386_32` in `.rel.text` | 0 | PASS (correct) |
| an object with no `.rel.text` at all | 0 | PASS (**vacuous**) |
| the literal text `not an elf file` | 0 | **PASS** |

The third row is the one that settles it: **the assertion cannot tell a correct
answer from having read nothing.** It is CLAUDE.md's own rule twice over — *if
the machinery did nothing at all, would this row still pass?* (yes), and *assert
the PRECONDITION, not just the comparison* (a comparison whose inputs were never
proven to exist cannot fail).

## The fix is already in the file, one block up

The **C**-object arm asserts two things and explains itself:

```make
if [ "$$pcr" -le "$$abs" ]; then echo "... $$abs absolute vs $$pcr PC-relative -- the data-reference conversion regressed"; exit 1; fi
if [ "$$abs" -ne 0 ]; then echo "... still has $$abs absolute relocation(s)"; exit 1; fi
```

> `.text` must be MOSTLY position-independent for this subject, not merely
> partly. **A bare nonzero PC32 count stays green after a whole family stops
> converting; this does not.** It is a guard that can fail and has: before
> families B and C landed, the same subject was 332 absolute against 120
> PC-relative and this line was RED.

`pcr > abs` is exactly the missing precondition — it cannot hold unless
relocations were actually read. **The author wrote the reasoning down and the
next arm did not inherit it**, which is the ordinary way this happens: the two
arms are different claims (the comment says so, correctly — the Pascal object
also carries `@proc` addresses via `ProcAddrFix` and external calls through a
`.data` slot via `DynCall`, arrays the C emitters never touch), and being
different claims is what stopped anyone reading them as one pattern.

## A second, independent weakness — frankD, not re-measured by me

From the row they cleared at HEAD `2699f5769`: the count can reach 0 **by
accident**. One extra unrelated local in `PXXIoCheck` moves `code` off `-0x10`,
the shape that needed an absolute relocation stops occurring, and the count goes
1 -> 0 **with the conversion mechanism untouched**. They confirmed that
particular green is real by checking the load-bearing condition in the artefact
directly (`8b 45 f0` still at 28f22, the store converted anyway, 0 absolute
against 587 PC-relative) — which is the right check and is not what the row
performs.

So there are two separate ways to be green here and neither is "the conversion
works": read nothing, or have the input construct quietly stop occurring.
**They compose** — the second produces a genuine zero, the first produces a
zero from no data, and the row prints the same thing for both and for the real
success.

## What to do

Not "add a positive control" in the abstract. Copy the pattern already twenty
lines above:

1. **Assert the population is non-empty** — some minimum count of `.rel.text`
   relocations of any kind, so an unreadable file or a missing section is RED
   rather than green.
2. **Assert a RELATION rather than a bare count** — `pcr > abs`, which carries
   no expected constant, cannot be satisfied by silence, and stays meaningful
   as the object grows.
3. Keep `abs == 0` as the second assertion. It is the stricter claim and it is
   worth having; it is only unsafe **alone**.

Then corrupt each arm on purpose and check it goes RED before landing — the
step that found this class three times tonight and was skipped the times it did
not.

## Scope

The `-rW | awk` shape is worth grepping for elsewhere in the Makefile before
closing: any `END{exit (n+0)==0 ...}` over a filtered stream has this property,
and the expected value being zero is what makes the vacuous case invisible.
This ticket is about the one row that was measured.

## Not this ticket

`bug-t-a-tier-job-identifier-is-a-selector-doing-double-duty-as-a-label` — that
one is about the identifier and the reason describing something other than the
defect. This one is about the assertion. They met because the same row surfaced
both.
