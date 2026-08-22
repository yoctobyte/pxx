---
track: A
prio: 45
type: bug
blocked-by: []
summary: "FIXED 2026-08-21. A failed Variant conversion (i := v with v='abc') printed 'Runtime error: EVariantError, ...' from inside the builtin helper and Halt(219)'d, so `try ... except on E: Exception` could not catch it and the program died — FPC catches it and continues. Fixed with the existing hook design: PXXVariantErrorHook in builtinheap, installed by sysutils, one funnel replacing eight inline writeln+Halt sites."
---

# A failed Variant conversion killed the process instead of raising

- **Type:** bug (uncatchable failure on ordinary code) — Track A (`compiler/builtin`),
  with the raiser half in `lib/rtl` (Track B files; see the ownership note)
- **Status:** done
- **Opened / closed:** 2026-08-21, found by running `test/fpcv.pas` — a file
  sitting UNWIRED in the tree with a note calling it an FPC oracle probe —
  against FPC.

## Measured

```pascal
uses SysUtils;
var v: Variant; i: Integer;
begin
  v := 'abc';
  try i := v; except on e: Exception do WriteLn('caught: ', e.ClassName); end;
  WriteLn('still alive');
end.
```

| | FPC 3.2.2 | pxx (before) |
| --- | --- | --- |
| output | `caught: EVariantError` / `still alive` | `Runtime error: EVariantError, cannot convert string to integer` |
| exit code | 0 | 219 |

The handler is unreachable, and `try i := v; except` is *the* shape this code is
written in — the entire reason for the try is that the text may not be numeric.
So the first bad input killed the program, with a message that names an
exception class nobody could catch.

## Why it happened

`VariantToInt` and its seven siblings in `compiler/builtin/builtin.pas` each did
`writeln(...); Halt(219)` inline. Those units are BELOW the exception
machinery — they have no `Exception` class to raise, and the unit that has one
(`sysutils`) cannot be assumed present.

That exact problem was already solved here, five times: `PXXDivZeroHook`,
`PXXOverflowHook`, `PXXRangeErrorHook`, `PXXIoErrorHook`, `PXXNilRefHook` — a
nil-by-default proc slot in `builtinheap`, installed by sysutils'
`initialization`, with the print-and-halt kept as the no-sysutils fallback. The
variant sites simply never got one.

## The fix

- `builtinheap.pas`: `PXXVariantErrorHook` + **one funnel**,
  `PXXVariantError(const msg)`, replacing eight copies of writeln+Halt. Fallback
  text unchanged for a program without sysutils.
- `sysutils.pas`: `EVariantError` **declared here now** (it was in `variants`),
  `SysRaiseVariantError`, and the hook installed beside the other five.
- `variants.pas`: re-exports the class (`EVariantError = sysutils.EVariantError`)
  so `on E: EVariantError` written against either unit catches the same object.

The class had to move because `uses variants` is OPTIONAL in pxx — variant
support is in the compiler — while sysutils is what any program that catches
anything already has. Re-exporting rather than leaving a second declaration is
the point: two classes with one name is a trap where the handler that looks
right does not fire.

## Tests

- `test/test_variant_conversion_failure_is_catchable.pas` — 9 lines, catching by
  the specific class AND by plain `Exception`, for int/float/bool, plus the
  message surviving the hand-off. Byte-identical to fpc 3.2.2 except the last
  line's WORDING (FPC: "Invalid variant type cast"; pxx names the conversion).
- **`test/fpcv.pas` is now wired** — the oracle probe that found this. It was
  exempted in the wiring sweep hours earlier as "an FPC oracle probe, not a
  test", which was true *at the time*: two of its five lines could not pass.
  It agrees line for line now, so the probe became the test.

## Left alone, deliberately

`compiler/builtin/promocore.pas:1524` has a sibling `RunError(219)` on the
variant→PromoInt path. Left as-is because no repro reaches it: every shape tried
(`p := v` for a non-numeric string) takes the string-parse path instead and
yields 0. That `p := v` with `v := 'abc'` silently produces **0** rather than
failing is its own question — PromoInt is a pxx extension so FPC is no oracle
for it, and it is recorded here rather than guessed at.

## Ownership note

The raiser half touches `lib/rtl/sysutils.pas` and `lib/rtl/variants.pas`, which
are Track B files. Done in one change rather than filed and handed off because
the fix is inert when split — the hook with nothing installing it changes
nothing — and no agent held Track B (`working/` was empty). Six lines in
sysutils, three in variants, both in the units that own the class.

## Gate

`make compiler/pascal26` (byte-identical fixedpoint) + `tools/gate.sh quick`
GREEN, plus the six variant/promoint tests re-run by hand and
`test_rtl_fpc_compat_helpers` still 23 / 23 (it catches `EVariantError` from
`variants`, which is what proves the re-export works).

## Log
- 2026-08-21 — resolved, commit 7d725f0d8.
