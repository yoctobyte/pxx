---
track: P
prio: 55
type: bug
blocked-by: []
status: done
owner: claude-A
commit: PENDING-COMMIT
summary: "`Integer(v) := x` over an ordinary lvalue was refused — only `Integer(p^) := x` parsed. That made writing through an UNTYPED `var x` parameter impossible, though reading one already worked, so a Move/FillChar-shaped routine could look at its argument and not store to it."
---

# Cast-as-lvalue only accepts a pointer deref

Found 2026-08-22 by an FPC differential sweep over procedures and parameters
(`fpc -Mobjfpc -O1` 3.2.2 vs pxx `3d521d909`). Surfaced by a probe that could
not compile:

```pascal
procedure SetI(var x); begin Integer(x) := 99; end;
```

```
pascal26:2: error: cast-as-lvalue statement requires a pointer deref inside the cast
```

## The measurement

| statement | fpc | pxx before |
| --- | --- | --- |
| `Integer(p^) := 5` | ok | ok |
| `Integer(i) := 5` (`i: Integer`) | ok | **refused** |
| `Byte(b) := 5` (`b: Byte`) | ok | **refused** |
| `Char(b) := 'x'` (`b: Byte`) | ok | **refused** |
| `Integer(x) := 99` (`var x` untyped) | ok | **refused** |
| `Integer(b) := 5` (`b: Byte`) | **rejected** ("different size") | refused |
| `Integer(x)` as an r-value | ok | ok |

The last two rows frame the fix. FPC's rule is same-**size** reinterpretation,
so it refuses a widening cast too — and pxx already supported the READ side of
an untyped parameter, so the asymmetry was: a `Move`/`FillChar`-shaped routine
could look at its argument and not store to it.

## Root cause

`ParseStatementAST`'s cast-as-lvalue arm parsed the operand and then required
it to be an `AN_DEREF`:

```pascal
if ASTKind[valNode] <> AN_DEREF then
  Error('cast-as-lvalue statement requires a pointer deref inside the cast');
ASTTk[valNode] := Ord(castTk);
```

The arm exists because retagging an `AN_DEREF` makes the store truncate to the
cast's width. Nothing was ever written for a plain lvalue.

Retagging an `AN_IDENT` would NOT have worked as a two-line fix, and this is the
part worth recording: the assignment lowering takes a plain identifier's width
from the SYMBOL, not from the node, so a retag would be silently ignored — and
for an untyped parameter, which is declared `tyPointer`, the store would have
written **8 bytes into a 4-byte Integer** and quietly corrupted the neighbour.

## The fix

Normalise into the shape that already works instead of adding a second store
path (`devdocs/dev/normalise-dont-special-case.md`):

```
Integer(v) := x      -->      PInteger(@v)^ := x
```

i.e. wrap the lvalue in `AN_ADDR` and then `AN_DEREF`, and let the existing
deref arm retag and store at the cast's width. One path, one set of semantics,
and the width question answers itself.

Two guards on the way in:

- The operand must be an lvalue (`IsASTLValue`), so `Integer(f(x)) := 1` still
  gets a diagnostic rather than a mysterious address-of.
- The cast type must be the same **size** as the variable's, matching FPC —
  silently writing 4 bytes into a `Byte` would corrupt whatever follows it.
  The error says so in words: *"the cast type must be the same size as the
  variable"*.

**An untyped `var` parameter is exempt from the size rule**, because it has no
declared width to disagree with — which is exactly what makes `Integer(x) := 99`
and `Byte(x) := 7` both legal against the same parameter. Untypedness has no
per-symbol flag (it lives in the parallel `ProcParamUntyped`, keyed by proc and
slot, because `Params[].SymIdx` is -1 after `RegisterProc` and a param symbol
does not outlive the callee's scope), so `IsUntypedVarParamSym` matches the
current routine's params by name — unambiguous inside the body being parsed.

## Verified against fpc

Pointer deref (unchanged), plain variable, record field, array element,
`Char` over a `Byte`, `Char` over a char array element and a char field, and an
untyped parameter written as both Integer and Byte, against a variable, a field
and an element. The untyped-parameter rows carry **guard variables on either
side of the target**, so a store that used the parameter's declared 8-byte
width instead of the cast's would fail the test rather than pass quietly. All
byte-identical to `fpc -O1`.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick` GREEN.
Test `test/test_cast_as_lvalue_over_a_variable.pas`, 15 assertions, wired into
`test-core`.
