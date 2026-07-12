---
prio: 55
---

# _Generic on a comparison matched NO association (hard error on valid C)

- **Type:** bug (compat — hard error, not silent)
- **Track:** C — C frontend (`cparser.inc`); tag: compat
- **Status:** done — fixed 2026-07-13.
- **Found by:** writing the regression for [[bug-c-generic-long-vs-int-ilp32]]; noted
  there as a separate gap and deliberately left out of that fix rather than widened
  into it.

## Symptom
```c
_Generic(i < 2, int: 1, long: 2)   /* error: no matching association and no default */
```
Same for `!x`, `x && y`, `x || y`. All valid C, all rejected.

## Root cause
A comparison, `!`, and the logical operators yield an **int** in C (C11 6.5.8p6,
6.5.3.3p5). The frontend tags them `tyBoolean` internally, and `CGScalarKindOfTk`
had no case for it — so the descriptor came out `cgUnknown` and matched nothing.

`ParseCSizeof` already treats this correctly (`sizeof` of a comparison is 4, with a
comment saying so). The _Generic layer just never got the same mapping.

## Fix
`tyBoolean -> cgInt` in `CGScalarKindOfTk`. C-mode only — the Pascal frontend never
reaches this code, and nothing else consumes the cg descriptors.

## Regression
Folded into `test/cgeneric_long_rank_b250.c` (same _Generic family) rather than a new
file: comparison, `!`, `&&`, `||`, and a comparison on a long all select `int`.

## Gate
make test green, self-host byte-identical, `testmgr --tier full` 1203/1203.
