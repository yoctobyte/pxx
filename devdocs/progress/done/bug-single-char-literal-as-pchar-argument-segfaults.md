---
track: P
prio: 80
type: bug
blocked-by: []
summary: "A ONE-character literal passed where a PChar parameter is expected segfaults: `StrCat(buf, '-')` faults, `StrCat(buf, '--')` works. The single-quoted literal types as Char rather than as a string, so its ORDINAL is passed as the pointer and the callee dereferences address 45. FPC converts it to a pointer to a NUL-terminated one-character string. Pre-existing — it hits StrCopy/StrCat/StrPos as much as anything new."
status: done
owner: frank1-P-pchar
---

# `StrCat(buf, '-')` segfaults; `StrCat(buf, '--')` is fine

Found 2026-08-25 by Track B while testing the PChar family
(`feature-b-rtl-gap-inventory-22-sysutils-strutils-symbols`). Not caused by that
work — the same fault is reachable through `StrCopy` and `StrCat`, which have
been in `lib/rtl/strings.pas` all along. Nothing had ever passed a
one-character literal to them.

## Repro (nar5.pas)

```pascal
program nar5;
uses sysutils;
var buf: array[0..63] of Char; i: Integer;
begin
  for i := 0 to 63 do buf[i] := '#';
  StrCopy(@buf[0], 'x');
  StrCat(@buf[0], '-');        { <-- faults here }
  Writeln(StrPas(@buf[0]));
end.
```

| compiler | result |
| --- | --- |
| `fpc -O- -Mobjfpc -Sh` | prints `x-` |
| pxx (pinned stable) | **segfault**, exit 139 |

Note `StrCopy(@buf[0], 'x')` on the line above does NOT fault — it writes
through `Source[i]`, and reading address 120 happens to be mapped often enough
to get away with it. The fault surfaces at whichever call first touches an
unmapped low address. That is the worst shape: the same defect is a crash on one
line and silent garbage on another.

## Mechanism

A single-quoted one-character literal types as `Char`. In an argument position
whose parameter is `PChar`, pxx passes the character's ORDINAL where the
pointer goes, so the callee dereferences address 45 for `'-'`. Two characters
or more type as a string and convert correctly, which is why the boundary is
exactly at length 1.

FPC/Delphi: a character literal in a PChar context converts to a pointer to a
NUL-terminated one-character string. Same rule as the empty literal `''`, which
must become a pointer to a lone `#0` — worth checking in the same fix.

## Why it matters

Every classic PChar call site takes single characters: separators, path
delimiters, `'/'`, `'-'`, `','`. It is also invisible in review — the call reads
correctly and the type checker accepts it. And it degrades to a *wrong value*
rather than a crash whenever the ordinal happens to land on a mapped page,
which is the failure mode this repo treats as expensive
(`devdocs/dev/debugging-playbook.md`).

Sibling check while fixing: any other argument position that converts Char to a
pointer type, and the `''` case above.

## Track B workaround in place

`test/lib_strings_pchar.pas` builds the chained-append case with two-character
literals and notes this slug. No `lib/rtl` code was reshaped — the library never
passes a one-character literal to a PChar parameter.

## Gate

Track P: `make compiler/pascal26` (self-host fixedpoint) + the repro above
printing `x-` and exiting 0.

## Raised 65 -> 80 (coordinator, 2026-08-26)

It is a **segfault**, and the owner ranking rule is stated plainly: "compiler
syntax, segfaults, etc, all prio." 65 ranked it as an ordinary defect.

Three things make it worse than the one-line repro suggests:

- **It is silent and shape-dependent in the cruellest way.** `StrCat(buf, '--')`
  works and `StrCat(buf, '-')` faults. Nothing about the source says the second
  is different, so a program works until the day someone shortens a separator.
- **It has been reachable through `StrCopy`/`StrCat` all along**, so it is not a
  consequence of the RTL work that found it -- that work only walked past it.
- **A one-character literal typing as Char and passing its ORDINAL as a pointer
  is a wild-pointer dereference**, not a refusal. The value is under the
  program's control, which is the difference between a crash and a defect worth
  ranking above a crash.

Almost certainly a double case: the same literal reaches a PChar parameter
through more than one path (direct call, overload resolution, an `array of
const`). Whoever takes it should fix the conversion where the type is decided
and then **grep for the sibling** -- and note the boundary of that grep, since
a site that open-codes the conversion will not name whatever symbol you search
for (`devdocs/dev/normalise-dont-special-case.md`).

## Resolved 2026-08-26 (Track P, frank1-P-pchar)

### Where the type was actually decided

`compiler/pasparser_expr.inc`, the `tkString` arm of the primary-expression
parser: `if Length(CurTok.SVal) = 1` builds an `AN_INT_LIT` tagged `tyChar`
holding the ORDINAL, otherwise an `AN_STR_LIT`. That is the ONE decision point,
and it is right — in Pascal the literal genuinely is both, and the context is
what picks. What was wrong is that "the context picks" was open-coded per
context, and each copy knew about a different set of destinations.

### It was a QUADRUPLE case, and none of the four knew about a PChar

The rule "an `AN_INT_LIT`/`tyChar` node in a string context retags to
`AN_STR_LIT`/`tyString`" existed, verbatim, in four places:

| site | condition it knew | PChar? |
| --- | --- | --- |
| `pasparser_expr.inc` direct-call arg loop | `TypeIsFrozenString(param)` | no |
| `pasparser_stmt.inc` overloaded-call arg loop (byte-identical twin) | `TypeIsFrozenString(param)` | no |
| `pasparser_stmt.inc` `Val`'s first argument | unconditional | n/a |
| `ir.inc` assignment path | `lhsTk = tyPointer and IsNodePChar` | yes |

…and a fifth group, the FIVE method/interface-call argument loops in
`pasparser_lval.inc`, had no copy of the rule at all, which is why
`o.M('-')` segfaulted as well.

Only the ASSIGN copy had ever learned about a PChar (added by
`bug-p-a-string-literal-assigned-to-a-pchar-is-empty`), and its own comment
says it was put in `ir.inc` so *"the whole 'a literal assigned to a PChar' rule
lives in one place"* — which is exactly the trap
`devdocs/dev/normalise-dont-special-case.md` describes: one place per CONTEXT
is not one place.

### The fix

ONE resolver, in Track P's `compiler/pasparser_name.inc`:

* `IsCharLitNode` — the node shape;
* `EnsureCharLitSpan` — materialise the char-pool span from the ordinal when a
  node has none (the `LabelSpanOfTok` move, one file up);
* `RetagCharLitAsStr` — the retag;
* `ParamTakesCharLitAsStr` — the PARAMETER-side rule: frozen string (the old
  condition, kept bit-for-bit) **or** a pointer parameter that is not by-ref,
  not open-array, not untyped and not procedural;
* `CoerceCharLitArg` / `CoerceCharLitArgs` — the per-slot and whole-chain walks.

The three parser copies now call it; the five method-call loops call it; the
comparison path calls the retag directly.

### Two siblings the shape-variation turned up

1. **`p = '-'` compared the POINTER against 45** and answered False, while
   `p = '--'` was right. The relational path's PChar-vs-string wrap already
   listed `tyChar` as convertible, so it *read* as covered — but
   `NormalizeUnsignedLiteralOperand` runs first, sees an ordinal literal
   against a POINTER (an unsigned operand) and retags it `tyUInt64`, after
   which the wrap cannot recognise a char. Found with `PXXDBG=a.ast`: the
   literal's `tk` was 14 (`tyUInt64`), not 3 (`tyChar`). Reading the source
   would have concluded the arm was fine — this is the measure-don't-reason
   case in miniature.
2. **A named `const Dash = '-'`** folds to a bare ordinal with no source span,
   so it was not the same node shape a written `'-'` is, and even the
   already-fixed ASSIGN path correctly declined it (`ASTSLen > 0`). `pv := Dash`
   segfaulted while `pv := '-'` and `pv := #45` were both fine. Fixed at the
   point the node is BUILT (the `skConst` arm) rather than at each consumer, so
   all three spellings are now one shape.

### What FPC does — measured, not recalled

`fpc 3.2.2 -O- -Mobjfpc -Sh`, one program per shape:

| shape | FPC | pxx before | pxx after |
| --- | --- | --- | --- |
| `Show('-')` | `-` | SEGV | `-` |
| `Show('')` | empty | empty | empty |
| `Show(#45)` | `-` | SEGV | `-` |
| `Show(Dash)` (named const) | `-` | SEGV | `-` |
| overloaded `Ov('-')` | picks PChar | SEGV | picks PChar |
| `o.M('-')` (method) | `-` | SEGV | `-` |
| `Show(Mid('-'))` (nested) | `-` | SEGV | `-` |
| `pv := Dash` | `-` | SEGV | `-` |
| `pv = '-'` | True | **False** | True |
| `Show(c)`, `c: Char` | **compile error** | SEGV | SEGV → filed |
| `Show(Chr(45))` | `-` | SEGV | SEGV → filed |

The boundary in FPC is **constness, not literalness**: a character CONSTANT
(literal, `#n`, named const, constant expression) converts to a pointer to
NUL-terminated one-character data; a character VARIABLE does not convert at
all. The empty literal `''` the ticket asked about was already correct in pxx
and stays correct.

### Regression test

`test/test_char_literal_to_pchar_param.pas`, wired into `test-core` beside
`test_pchar_from_a_string_literal`. It asserts every arm above **plus the
two-character control beside each**, so a future change cannot repair one
boundary and break the other. It prints `ALL OK` under pxx at HEAD and under
`fpc 3.2.2 -Mobjfpc -Sh`; the SAME source compiled by the **pinned stable**
(pre-fix) segfaults with exit 139 and prints nothing, so the witness is real.

### Not fixed here — filed, because all three are length-INDEPENDENT

Varying the shape found three neighbours that this bug was merely standing next
to; each is broken at every literal length, so none of them is this defect:

* `bug-p-a-typed-pchar-const-cannot-be-initialised-from-a-literal` (prio 70) —
  `const GP: PChar = '-'` compiles and segfaults, `= '--'` is a parse error,
  and the array form is "too many array constant elements". A different
  machinery (`PendingInit*`) needing a data relocation.
* `bug-p-a-char-value-is-accepted-where-a-pchar-is-wanted-and-segfaults`
  (prio 60) — `Show(c)` and `Show(Chr(45))`. Half of it is a const-folding gap,
  half a dialect-strictness call.
* `bug-p-a-string-literal-is-refused-as-a-pchar-parameter-default` (prio 55) —
  `p: PChar = '-'` refused at both lengths; loud, not silent.

### Gate

`make compiler/pascal26` converged after 1 round (byte-identical self-host
fixedpoint) on each of the three builds; `tools/gate.sh quick` GREEN.

## Log
- 2026-08-26 — resolved, commits e2f10dd78 (the argument boundary: one shared resolver, the three parser copies and the five method-call loops) and fae5b3931 (the comparison path + the named char const, and the regression test).
