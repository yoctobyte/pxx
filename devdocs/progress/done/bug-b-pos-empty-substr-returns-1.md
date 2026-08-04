# SysUtils.Pos returned 1 for an empty substring

- **Type:** bug — Track B (library), tag `compat` (FPC parity)
- **Status:** done
- **Opened:** 2026-08-04
- **Found by:** `tools/fpc_diff_probe.sh`, new `su-pos` case.

## Symptom

    Pos('', 'abc')     FPC: 0     pxx: 1

C's `strstr` returns a hit at the start for an empty needle; Delphi and FPC
both return 0 (not found). `Pos` had an explicit `if m = 0 then Result := 1`
early-out, so this was a deliberate choice made against the wrong reference.

## Why it matters more than it looks

The idiomatic guard is

    if Pos(sep, s) > 0 then ...

which under the old behaviour fires for an *empty* separator and then indexes
from a position that matched nothing. It is a silent-wrong-value shape, not a
crash — the caller proceeds with a plausible index.

`PosEx` in `lib/rtl/strutils.pas` already returned 0 here, so the two search
functions in the RTL disagreed with each other, which is how it went unnoticed:
whichever one a caller reached for looked self-consistent.

## Fix

`lib/rtl/sysutils.pas` — return 0, matching `PosEx` and FPC.

## Checked, not affected

The **compiler builtin** `Pos` (the no-`uses` intrinsic lowered to a builtin
helper, covered by `test/test_upcase_pos.pas`) is a separate implementation and
was already correct for all three empty cases — verified before assuming, since
a matching bug there would have been Track A.

## Test

`test/lib_strutil.pas` — `pos-empty`, `pos-empty-var`, `pos-both-empty`, plus
found/absent controls. Both the literal and the variable form are asserted
because a literal `''` could plausibly be constant-folded down a different path.
3 fail without the fix.
