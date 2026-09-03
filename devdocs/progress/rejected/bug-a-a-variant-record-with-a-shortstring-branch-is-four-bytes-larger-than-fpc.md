---
prio: 45
track: A
type: bug
status: rejected
resolved: PENDING-COMMIT
summary: "REJECTED, FALSE PREMISE, filed and retracted the same day by its author. The oracle was `fpc -O2` with no -M flag, where **Integer is TWO BYTES** (Turbo Pascal compatibility), so the FPC record I compared against did not contain the type mine did. Re-measured with LongInt on both sides: pxx and FPC 3.2.2 BOTH say 12, in FPC's default mode and under -Mobjfpc. The variant layout matches. tools/fpc_diff_probe.sh passes -Mobjfpc and never had this hazard; I ran fpc by hand and lost the flag the tool carries."
---

# A variant record with a shortstring branch is four bytes larger than FPC — WRONG

## The retraction, and it is the only part worth reading

```pascal
type TC = record case k: Byte of 0: (s: string[4]); 1: (n: LongInt); end;
```

| | `SizeOf(Integer)` | SizeOf(TC) |
| --- | --- | --- |
| pxx, `-dPXX_SHORTSTRING` | 4 | **12** |
| FPC 3.2.2, default mode | 2 | **12** |
| FPC 3.2.2, `-Mobjfpc` | 4 | **12** |

Written with `n: Integer` instead of `n: LongInt`, the same comparison reads 12
against 8 — because FPC's bare `Integer` is a SmallInt in its default mode and
pxx's is 32 bits. **The two compilers were laying out different records.** The
number was real, reproducible, and about a type I had not declared.

`record case k: Byte of 0: (s: string[4]) end` is 6 in both. `record case
k: LongInt of 0: (i: LongInt) end` is 8 in both, which also confirms
[[bug-p-a-tagged-variant-record-is-padded-to-eight]] (done, `1a2db4cfc`) has NOT
regressed — that was the question this measurement was ordered to answer, and
the answer is clean.

## Why this is filed rather than deleted

**`fpc` WITH NO `-M` FLAG IS NOT THE ORACLE.** `tools/fpc_diff_probe.sh` passes
`-Mobjfpc` on every compile; I invoked `fpc -O2` directly for a one-off record
comparison and silently got a compiler whose `Integer`, `Boolean` sizes and
string defaults differ from the mode every other measurement in this repo uses.
It does not error. It compiles, runs, and prints a number about a different
program.

Every FPC comparison in this family made by hand is exposed to this, and the
discriminator is one line: print `SizeOf(Integer)` beside any layout number
taken from FPC. Where it says 2, the record under test is not the record you
declared.

The frozen-string layout claims landed in `18b92fac9` are NOT affected: those
records hold only `Byte` and `string[N]` fields, and `test_frozen_string_layout.pas`
prints no sizes at all — its FPC agreement is over booleans and strings, which
carry no width. Re-checked, not assumed.

[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]
