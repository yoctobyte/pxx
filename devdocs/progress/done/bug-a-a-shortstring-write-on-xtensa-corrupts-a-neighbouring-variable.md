---
slug: bug-a-a-shortstring-write-on-xtensa-corrupts-a-neighbouring-variable
track: A+S
prio: 70
type: bug
status: done
found: 2026-08-30
owner: frankS
---

# A shortstring write on xtensa corrupts a NEIGHBOURING variable

> ## THE PREMISE IS WRONG. Nothing is corrupted. (frankS, 2026-08-30)
>
> **This is not memory corruption. It is frozen-string EQUALITY comparing
> addresses.** I wrote the "memory corruption" framing myself, into the handback
> table, a commit message and a message to the coordinator, and I got it from the
> test's own failure message without checking it. The slug and title stay so the
> links resolve; everything below the fold is the real defect.
>
> `test_shortstring_trunc` prints `b-CLOBBERED` because it tests
> `if b = 'BBBB'`. Print `b` instead and it is `BBBB`, `Length(b)` is `4`, and
> the neighbour is **intact**. The write truncates correctly. The comparison is
> what is broken, and it is broken for every frozen string, not just after a
> truncating write.
>
> **How the wrong reading survived one level of scepticism:** my first minimal
> repro assigned an oversized literal to `a`, printed `a` and printed `b`, and
> **passed**. I had reproduced the write and dropped the comparison — removing
> the actual defect from my own repro while believing I had bounded it. The test
> row that says `CLOBBERED` names a mechanism it never verifies, and a repro
> built from the message rather than from the code inherits the same error.

## The defect

`b = 'BBBB'` for `b: string[4]` answers **false**.

```
xtensa   print=[BBBB] len=4 | eq-lit WRONG | ne-lit ok | eq-sh WRONG | eq-ansi ok | gt-lit ok
x86-64   print=[BBBB] len=4 | eq-lit ok    | ne-lit ok | eq-sh ok    | eq-ansi ok | gt-lit ok
```

The pattern names the cause exactly: **`=` between two frozen strings is wrong;
everything else is right.** `<>` is "right" only because two distinct addresses
really are unequal. `>` is right because the ordered arm handles frozen. `= ms`
is right because an AnsiString on either side reaches the string arm.

`ir_codegen_xtensa.inc` had **two guards** in front of one compare arm:

```pascal
{ equality } (op in [tkEq,tkNeq])          and (left=tyAnsiString or right=tyAnsiString)
{ ordered  } (op in [tkLt,tkLe,tkGt,tkGe]) and (… or TypeIsFrozenString(left) or TypeIsFrozenString(right))
```

Both sides frozen and the operator `=`: neither guard fires, so it falls through
to the **integer compare** and compares the two buffer addresses.

## The comment that made it invisible, and why it was written

Directly above the guard:

> *The ordered guard also accepts a FROZEN string on either side, which the
> equality guard does not need: **frozen equality already works**.*

That is false, and it is not carelessness — it is **a measurement that passes
for the wrong reason**. Measured here both ways:

```
'BBBB' = 'BBBB'   ->  ok        (two identical literals INTERN TO ONE ADDRESS)
b = 'BBBB'        ->  WRONG
```

Check frozen equality with two literals and address equality and string equality
agree, so a broken compiler answers correctly. Check it with a variable and it
never worked. The claim was written by someone who tested the reachable-looking
case; the case that distinguishes the two mechanisms is the one with a variable
in it.

## Sixth backend skipped, again — and riscv32 already had the fix

`grep`ping the sibling before writing this: **x86-64, i386, arm32, aarch64 and
riscv32 all pass every check. Only xtensa failed.** riscv32 carries the fix with
the identical root cause in its own comment:

> *Was gated on tyAnsiString only, so frozen = frozen (e.g.
> `ParamStr(1) = '--selftest'`) compared ADDRESSES.*

Same shape as `ABIParamSlotHoldsValueAddr` and as `PXXStrCmp3`'s own miscount
three lines above this guard — *"the FOUR cross backends had no ordered-string
arm at all; there were five, and that miscount is why xtensa was never
visited."* The arm that says that was itself written with a two-guard split,
which is the same defect committed a second time inside its own fix.

## Fix

**Merge the two guards into one** covering all six operators with the frozen
terms on both sides — rather than adding the missing terms beside the existing
guard. The operand decompose already handles frozen (`len` at `[buf]`, `src` at
`buf+8`); only the guard excluded it. One guard cannot diverge from itself.

## Measured

129-source differential, compiler `147123b1bb41` (verified self-host fixedpoint):

```
before  MATCH  99   DIFF 8   CFAIL 21
after   MATCH 100   DIFF 7   CFAIL 21
exactly one row moved, DIFF -> MATCH; regressions: NONE
```

`test_shortstring_trunc` wired into `test-xtensa` (now 101). The row uses the
**variable** form deliberately, with a comment saying why a literal-vs-literal
check would pass on the broken compiler — otherwise the next person simplifying
that row reintroduces the blind spot that hid this for the life of the backend.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
