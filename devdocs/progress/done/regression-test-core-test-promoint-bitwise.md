---
prio: 70
track: P
owner: frankD
status: done
---

> **Track T by default: the FAILING STEP named no owner.** Line 2 of 2 is `tools/expect_same.sh sweep_promoint26 "$(/tmp/sweep_promoint26)" "$(printf '18446744073709551615\n0\ncrossed\n1844674407`. The job's own `src` (`test/test_promoint_bitwise.pas`, 2 file(s)) is NOT used here on purpose: it is what the job compiles, not what broke, and guessing a lane from it is what sent three reds in one job to the wrong lane. This is a FALLBACK, not a finding — nothing says the defect is Track T's. Re-lane it before working it.

> **origin/master has advanced 2 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_promoint_bitwise.pas at 0aff068c6d08 in step 2/2, `tools/expect_same.sh sweep_promoint26 "$(/tmp/sweep_promoint26)" "$(printf '18446744073709551615\n0\ncrossed\n184467440…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `7327e547732c`).
  Untriaged.
- **Found:** 2026-09-06T13:36:18Z
- **Test source:** test/test_promoint_bitwise.pas tools/expect_same.sh
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/expect_same.sh`.
  ```
  tools/expect_same.sh sweep_promoint26 "$(/tmp/sweep_promoint26)" "$(printf '18446744073709551615\n0\ncrossed\n18446744073709551616\n255\n255\n15')"
  ```

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_promoint_bitwise.pas'` at 0aff068c6d08caf3d9b2f8d4d5fd5886d27ac0c2

## Range
> **The named sha `0aff068c6d08` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `0aff068c6d08`, last good `bb18f83c859e`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
ok: /tmp/testmgr-scratch-1824622/sweep_promoint26  [code=245528B  data=6276B  bss=52100B  procs=650]
expect_same: MISMATCH [sweep_promoint26]
--- expected
+++ actual
@@ -1,6 +1,6 @@
-18446744073709551615
+-1
 0
-crossed
+not
 18446744073709551616
 255
 255

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Diagnosed and re-laned P — the cause is measured, and a REVERT IS A TRAP

Re-measured at compiler `d697a8a680fd`: still RED, both rows.

**Cause: `10e670503`** (*"a decimal literal above High(Int64) is a QWord at its
creation site, not only at an operand site"*), which is inside the watcher's
own `bb18f83c859e..0aff068c6d08` range. Unusually, the bisect is right about
*what* as well as *when* — the named commit touches the failing MECHANISM
directly: it retags the exact literal this test masks with.

It moved `NormalizeWideUnsignedLiteral` to the literal's CREATION site
(`compiler/pasparser_expr.inc:903`), so every decimal in `[2^63, 2^64)` is now
tagged `tyUInt64`. That is correct for signedness — and `IsWideIntLit`
(`compiler/ast_arena.inc:759`) accepts only `tyInt64`/`tyPromoInt64`, so those
literals silently left the predicate that every PromoInt path asks
(`IRPromoInitFromLiteral`, `IRPromoAddrOf`, ir.inc:1697/1808/1906/12213/…).
PromoInt then falls back to the wrapped machine reading.

`10e670503`'s own comment predicted the hazard one band too high: *"Above
High(QWord) nothing 64-bit-wide holds the value … that case belongs to
feature-a-promoint-wide-literals and the normaliser leaves it alone."* Above
2^64 the tag stays `tyInt64` and PromoInt still works — which is why the whole
defect hides in the single band `[2^63, 2^64)` and reads as a PromoInt bug.

Both failing rows are ONE cause: `mask := 18446744073709551615` is stored as
Int64 `-1`, so `a and mask` = `-1` and `a > b` is `-1 > 0` = `not`.

### Measured, both directions (revert-control on `pasparser_expr.inc:903`)

| | `test_promoint_bitwise` | `q div 18446744073709551615`, `Writeln(9223372036854775907)` |
| --- | --- | --- |
| HEAD, retag live | **RED** (`-1`, `not`) | correct (`3689348814741910323`) |
| control, retag disabled | **GREEN**, all 7 rows | **DOES NOT COMPILE** |

So **reverting `10e670503` re-breaks `bug-p-qword-div-by-a-literal-above-2-63-is-signed`
and makes ordinary QWord programs fail to build.** Do not revert it. Neither
behaviour is optional; the two arms disagree about what the tag MEANS.

### The fix, when the pin sweep is over

`IsWideIntLit` is one name answering two questions: *"is this literal still
untyped-signed"* (the signedness/emission arms, which rely on it going False
after the retag — `pasparser_expr.inc:896` says so explicitly) and *"does this
literal carry exact digits"* (the promo arms, which only ever wanted the span).
The retag made them diverge, with no diagnostic, in a neighbouring subsystem.

Split the predicate rather than widen it: add a digits-only test
(`AN_INT_LIT and ASTSLen > 0 and tag in {tyInt64, tyPromoInt64, tyUInt64}`,
plus its `AN_NEG` companion) and route the PROMO call sites to it, leaving
`IsWideIntLit` untouched for the signedness arms. Widening `IsWideIntLit`
itself would hand the promo path every QWord operand — the condition
`10e670503` exists to prevent.

Fixture gap to close with it: `test_promoint_bitwise` is the only row in the
band, and it is a NilPy-motivated Pascal test. A `PromoInt := <2^63..2^64
literal>` row and a QWord `div`/compare row belong in one file, because they
are the two arms of one tag and each is the other's positive control.

Not opened during the 2026-09-06 pin sweep (a multi-site change in shared A
files); claimed by frankD, Track P, since the retag site is P's.

**Parked, not in progress.** The diagnosis above is complete and the fix is
specified; `owner:` here is attribution, not a lock. Anyone may take it — read
the revert-trap table first.

## RESOLVED 2026-09-06 (frankD) — the predicate was split, not widened or reverted

Fixed as specified above. `WideLitHasDigits` / `IsWideNegLitDigits` added in
`compiler/ast_arena.inc`; three PROMO-SLOT call sites routed to them
(`IRPromoInitFromLiteral`, `IRPromoAddrOf`, `IRPromoEmitBinop`'s mixed-helper
guard). `IsWideIntLit` is untouched and the signedness arms still rely on it
going False after the retag.

**One correction to the plan above.** It said to route "the PROMO call sites".
That is too wide: the discriminator is the DESTINATION, not the literal. Inside
`[2^63, 2^64)` a correct 64-bit reading EXISTS, so the machine-int lowering and
the Write arm are right to take it and are cheaper. Only a promo slot needs the
digits.

**The variant arms look like they belong and do not, measured.** A variant
carries no unsignedness, so the band genuinely is wrong there — fpc 3.2.2
prints 18446744073709551615 for `v := 18446744073709551615` and we print -1.
But those arms reach the promo RUNTIME, and a program that never mentions
PromoInt does not load promocore, so switching them makes an ordinary program
fail with `runtime helper PXXPromoFromStr not found`. I wrote that fix, built
it, measured the failure and reverted it. Filed separately as
[[bug-a-a-wide-unsigned-literal-boxed-into-a-variant-stores-the-wrapped-value]].

**The trap, because it caught me inside my own verification:** a probe for the
variant arm must declare NO PromoInt. My band probe declared one for unrelated
rows, which loaded promocore, which made the broken fix read as correct. The
population was wrong while every row was honest.

### Verified at compiler `b31b9b1821c1`

- the row itself 7/7, and all 8 `test_promoint_*` rows GREEN under `testmgr --tier native`
- QWord control unchanged: `q div 18446744073709551615`, `Writeln(9223372036854775907)`, `9223372036854775808 > 1`
- boundary probe at 2^63-1 / 2^63 / 2^64-2 / 2^64-1 / 2^64 / 10^20 / negative — byte-identical to fpc 3.2.2
- NilPy byte-identical to CPython across the same band (`tyPromoInt64` shares the predicate)
- `gate.sh quick` GREEN

### Fixture pairing closed

`test_promoint_bitwise` (narrowing) and
`test_a_decimal_literal_above_high_int64_is_a_qword` (widening) now name each
other. Moving this predicate breaks exactly one of them, and the second works
ONLY because it declares no PromoInt — an absence that was load-bearing and
invisible from either file. Both headers now say so.

Nothing here is inert until the next pin: the fix is in `compiler/**` and no
`lib/**` file depends on it.
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
