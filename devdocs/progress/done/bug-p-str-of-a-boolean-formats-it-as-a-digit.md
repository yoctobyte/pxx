---
track: P
prio: 40
type: bug
blocked-by: []
summary: "`Str(b, s)` on a Boolean produced '1'/'0' while `writeln(b)` on the next line printed TRUE/FALSE — one compiler rendering one value two ways, and FPC gives TRUE for both. `StrBool` already existed and was already correct; Str's dispatch simply had no Boolean arm and fell through to StrInt. The SAME defect as bug-p-str-of-a-qword-formats-it-signed one type over: Str's dispatch is a hand-written copy of write's and has been missing a case each time."
status: done
owner: frankH
---

# `Str` of a Boolean formats it as a digit

- **Track P** — the `Str` intrinsic's formatter dispatch,
  `pasparser_stmt.inc` (the `CaseEqual(name, 'Str')` arm).
- Found 2026-09-04 while measuring what a library `writeln` would have to
  reproduce for phase 3 of [[feature-writeln-as-library]]. Not looked for.

## Repro

```pascal
var s: ShortString; b: Boolean;
begin
  b := True; Str(b, s);
  writeln('Str=', s, ' writeln=', b);   { pxx: Str=1 writeln=TRUE }
end.                                    { fpc: Str=TRUE writeln=TRUE }
```

## What it was

`Str`'s dispatch chose between `StrFloat`, `StrQWord` and `StrInt`. Boolean was
explicitly *excluded* from the `StrQWord` arm — correctly, since a Boolean is an
unsigned ordinal and would otherwise have printed through the unsigned
formatter — and then fell into `StrInt`, which prints digits.

`StrBool` has existed the whole time in `compiler/builtin/builtin.pas` and is
correct (`StrStrW('TRUE', width)`). **Nothing routed to it from `Str`.** The
`write`/`writeln` path already did, which is why the two disagreed.

Fix: one arm, claiming `tyBoolean` before the unsigned test. The `<> tyBoolean`
exclusion in the `StrQWord` arm then became a condition that could never fire,
and was deleted rather than left looking like a live guard.

## Why it was findable

Directly above the fix sits the comment for
`bug-p-str-of-a-qword-formats-it-signed`: *"`Str(q, s)` on a QWord >= 2^63
produced `-1` — a silent wrong VALUE, while `writeln(q)` two lines away was
right."* Identical shape, one type over, and that ticket's own fix is what put
the dispatch table under a reader's eye. **`Str`'s table is a hand-written copy
of `write`'s**, and it has now been short a case twice; the third renderer,
`array of const` boxing, loses the same information for the sized booleans
(filed as
[[bug-a-the-sized-booleans-render-as-a-digit-in-both-str-and-writeln]]).

## Test

`test/test_str_of_boolean.pas`, wired into `test-core`, byte-identical to
`fpc 3.2.2 -Mdelphi -O1`.

The expected values are ones the broken path **cannot** produce (`TRUE`, not
`1`) — a row asserting `1` would have passed against the bug. Two properties of
the file are deliberate:

- It compares its **whole** output, not the tail line. The pre-fix compiler
  still printed the final `STR BOOL OK`, so a tail-only assertion — the shape
  the neighbouring elision tests use — would have been green against the bug.
- The `wt=`/`wf=` rows render the same value through `writeln`. On the pre-fix
  compiler they stay GREEN while the `Str` rows go red, so the failure output
  *shows* the two-renderings split rather than just reporting a mismatch.

**Control, run rather than assumed:** with the arm removed and the old
exclusion restored, 6 of 11 rows go RED (`t=1`, `f=0`, and all four width rows)
and the `writeln` rows stay green. Restoring the fix returned the compiler to
byte-identical sha `c94252bb92cd`, so the control changed nothing else.

## Gate

`make compiler/pascal26` — `converged after 1 round(s)`, the recompute verb.
`tools/gate.sh quick` 12/12 PASS with the **FPC seed canary PASS rather than
SKIP** (gated before committing, which is the only condition under which it
runs at all).

## Not fixed here

`WordBool`/`LongBool`/`ByteBool` still print `1` from *both* renderers. That is
a different defect with a different cause — they have no boolean-ness to
dispatch on — and is filed separately.

## Log

- 2026-09-04 — found, fixed, tested and closed in one pass, commit `14c8dcbb7`.
  The fix and the close are the same commit; there is no separate close to
  cite. Test `test/test_str_of_boolean.pas` and the reverted-arm control are
  both in it.
