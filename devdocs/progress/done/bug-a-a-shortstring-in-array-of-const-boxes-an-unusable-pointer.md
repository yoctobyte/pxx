---
track: A
prio: 65
type: bug
blocked-by: []
summary: "`Format('%s', [sh])` returned EMPTY for a ShortString and GARBAGE for a `string[5]`, while `writeln(sh)` on the next line was right. `tyString` covers two shapes with different layouts -- a frozen LITERAL is an interned blob behind an 8-byte length prefix, a ShortString VARIABLE is [len:Byte][chars] -- and the boxing arm added 8 unconditionally, so a variable's text was skipped past. An offset fix would NOT have been correct: a ShortString carries no guaranteed NUL. Converts through an owning hidden AnsiString local instead, keeping the literal fast path the compiler's own asm-text emitters depend on."
status: done
owner: frankH
---

# A ShortString in `array of const` boxes an unusable pointer

- **Track A** — `compiler/ir.inc`, the `AN_VARREC_ARRAY` element lowering.
- Found 2026-09-04 while measuring what a library `writeln` must reproduce for
  phase 3 of [[feature-writeln-as-library]]. Not looked for.

## Repro

```pascal
uses sysutils;
var sh: ShortString; s5: string[5];
begin
  sh := 'short';  writeln('[', Format('%s', [sh]), ']');   { pxx []      fpc [short] }
  s5 := 'five5';  writeln('[', Format('%s', [s5]), ']');   { pxx [<junk>] fpc [five5] }
  writeln('[', sh, ']');                                   { pxx [short] fpc [short] }
end.
```

The third line is the tell: **the same value, the same program, two
renderings.** `Format` is not exotic — this is one of the most-used routines in
the RTL and a ShortString argument is ordinary code.

## Cause

`tyString` names TWO shapes with different memory layouts, and the boxing arm
was written for one of them:

| shape | layout | old arm |
| --- | --- | --- |
| frozen string LITERAL (`AN_STR_LIT`, and a named string const) | interned blob, 8-byte length prefix, NUL-terminated by `InternStr` | `+8` → correct |
| ShortString VARIABLE | `[len: Byte][chars...]`, **measured** | `+8` → past the text |

For a 5-char ShortString, offset 8 is the zero fill, so the consumer read an
empty string. For a `string[5]` the whole buffer is shorter than 8 bytes, so it
read *past the variable* and printed adjacent frame memory.

The arm's own comment said "frozen (inline) string **literal**" — it was
accurate about what it handled and nothing checked that only literals arrived.
The recurring shape: one question, two spellings, one taught.

## Why an offset fix would have been wrong

**A ShortString carries no guaranteed NUL.** Assign `'longer'` then `'ab'` and
the buffer still reads `ab` + `ger`. A consumer holding only a char pointer —
which is all a `TVarRec` union slot can carry — would run past the text. The
length has to be *applied*, not stepped over.

So the element is converted: stored through a hidden `AnsiString` local, letting
the **store's DEST type** do the conversion — the same mechanism `an := sh`
already uses, and the same one the `tySingle` widening beside it and
`IRPromoInitFromLiteral` rely on. The local OWNS the handle, so scope exit
releases it; a bare `+1` in the union slot could not be released, since a
`TVarRec` has no managed field and no finaliser.

**The literal path is untouched, deliberately.** The compiler's own asm-text
emitters build `['b %', n]` vectors constantly, so making every literal allocate
would have been a self-host performance regression — the fix branches on
`AN_STR_LIT` and leaves that path exactly as it was.

## Test

`test/test_shortstring_in_array_of_const.pas`, wired into `test-core`,
byte-identical to `fpc 3.2.2 -Mdelphi -O1`.

Rows chosen so each can only pass for the right reason:

- **`stale`** is the row an offset-only fix still fails (`'longer'` then `'ab'`
  must give `ab`, not `abger`).
- **`s5`** is a `string[5]`, whose entire buffer is shorter than the 8 bytes the
  old arm skipped. Its expected value is a *full-capacity* string, so a
  truncation bug cannot hide in it either.
- **`lit` / `konst`** are the control that the literal fast path did not start
  allocating.
- **`empty`** separates "empty because empty" from "empty because the pointer is
  unusable" — the pre-fix failure mode.
- Whole output is compared, not the tail line: the pre-fix compiler still
  printed the final `SHORTSTRING VARREC OK`.

**A second assertion class, because a value check physically cannot see it.**
The fix parks a managed handle per element, which is exactly the shape that
leaks silently. `tools/assert_no_leak.sh` is wired beside the value row:
`allocs=10975 frees=10961 live=14` over 3000 iterations, against a bound of 200
(a per-iteration leak would show ~3000).

**Control, run:** with the fix reverted, 4 rows go RED (`plain`, `stale`, `s5`,
`mixed`) while `lit`, `konst` and `builtin` stay GREEN — the literal-works /
variable-fails split is visible in the failure output itself. Restoring returned
the compiler to byte-identical sha `f646807f39ed`.

## Gate

`make compiler/pascal26` — `converged after 1 round(s)`, the recompute verb.
The self-host is meaningful evidence here rather than a formality: the asm-text
emitters build these vectors on every compile, so a broken literal path could
not have reproduced the compiler.

## Neighbours found in the same measurement, not fixed here

- [[bug-a-a-qword-boxes-as-vtint64-so-array-of-const-loses-unsignedness]] — we
  emit tag 16 where FPC emits 17.
- [[bug-a-the-sized-booleans-render-as-a-digit-in-both-str-and-writeln]] —
  `LongBool` boxes `vtInteger`.

`ShortString` → `vtAnsiString` (tag 11, where FPC uses `vtString` = 4) is
**not** a defect and is not filed: `builtinheap.pas:99` records it as a chosen
consequence of this RTL's string model, and with this fix the payload now
matches what that tag promises.

## Log

- 2026-09-04 — found, fixed, tested and closed in one pass, commit `1cac1742a`.
  Fix and close are the same commit. Test, leak row and the reverted-arm control
  are all in it.
