---
track: P
prio: 55
type: bug
blocked-by: []
status: done
summary: "`p := 'alpha'` with p: PChar stored the literal's HANDLE -- which points at the 8-byte length prefix -- so WriteLn(p) printed nothing and Length(AnsiString(p)) answered 1. A ONE-CHAR literal stored the ordinal instead and SEGFAULTED on the next read. And `p = 'alpha'` compared pointers, not contents. The call-argument path already did this right, so it is one marshalling rule applied at one of its two boundaries."
owner: claude-A
---

# A string literal assigned to a PChar is empty

Found 2026-08-24 by the PChar differential run under
[[refactor-centralize-managed-string-pchar-conversion]]'s acceptance line. All
three halves reproduce with the pinned binary.

```pascal
var p: PChar;
begin
  p := 'alpha';
  writeln('[', p, ']');                  { pxx []   fpc [alpha]  WRONG }
  writeln(Length(AnsiString(p)));        { pxx 1    fpc 5        WRONG }
  p := 'e';
  writeln('[', p, ']');                  { SEGFAULT              WORSE }
  p := 'alpha';
  if p = 'alpha' then ... ;              { pointer identity, not content }
end.
```

`p := 'literal'` is not an exotic shape — it is how every C binding spells a
constant argument, and how half the FPC examples on the internet start.

## Three defects, one statement

**1. The handle, not char 0.** A Pascal string literal's handle points at an
8-byte length prefix; character 0 is at +8. The call-ARGUMENT path already
applies that skip (the `tyString -> tyPointer` marshalling in `AN_CALL`), which
is exactly why `Show('lit')` printed the text and `p := 'lit'; Show(p)` did
not. The assignment arm in `ir.inc` had the same skip and it was guarded
`CProgramMode` — *"C-mode only -> Pascal self-build unaffected"*, which was
true of the risk and false of the requirement. One marshalling rule, applied at
one of its two boundaries.

**2. A one-character literal is not a string node.** `'e'` parses as an
`AN_INT_LIT` tagged `tyChar` (the parser splits on `Length(SVal) = 1`), so the
assignment stored the ordinal 101 into the pointer and the next read
dereferenced address 101. FPC reads a one-char literal in a PChar context as
the one-char string it also is.

**3. The comparison compared pointers.** `p = 'alpha'` was True only when `p`
held that very literal's handle, and False for the same text built at run time
— `PChar(s) = 'alpha'` with `s := 'alp' + 'ha'` answered False on the pinned
binary too. Fixing (1) removed the coincidence that made the common case look
right, which is the honest order to find it in.

## Fixed 2026-08-24 (claude-A)

- `ir.inc`, the assignment arm: the `+8` skip now applies in Pascal too, asking
  `IsNodePChar` about the **destination**. C keeps its blanket rule for any
  pointer destination, which is right there — a C string literal *is* a
  `char*`. Pascal does not permit a string literal in a plain `Pointer`, so pxx
  does not invent a meaning for it.
- Same place: a `tyChar` `AN_INT_LIT` assigned to a PChar is retagged to the
  `AN_STR_LIT` it should have been — the same two-line move the frozen-string
  argument path already makes, and the source span is already on the node.
  Kept beside the `+8` so the whole "a literal assigned to a PChar" rule lives
  in one place.
- `pasparser_expr.inc`, the relational level: a PChar operand whose other side
  is a string or a char is wrapped with `WrapPCharToString`, exactly as the
  additive level already wraps it for `+`. Downstream comparison arms then see
  two string operands and need to know nothing about PChar. Excluded in C mode,
  where `p == "x"` genuinely IS a pointer comparison.

**Verified:** `test/test_pchar_from_a_string_literal.pas`, wired into
`test-core` — assignment to a var / a record field / a static array element / a
dynamic array element, the argument boundary that was always right, the
one-char and empty literals, and five comparison rows including the
runtime-built pointer that never matched. `ALL OK` under fpc 3.2.2 and under
pxx on **x86-64, i386, aarch64, arm32 and riscv32**.

A 49-row PChar cross-product (7 sources × 7 contexts) is now byte-identical to
FPC with zero divergences; before this it had four. C mode re-checked against
gcc on the `const char *p = "alpha"` rows: unchanged.

Self-host fixedpoint converged in one round; `tools/gate.sh quick` GREEN.

## Filed in passing

[[bug-p-a-typed-constant-of-pchar-type-is-a-parse-error]] —
`const KC: PChar = 'konst';` does not parse at all.

## Gate

`make compiler/pascal26` converged + the test on five targets + FPC + the
49-row cross-product + the gcc C-mode re-check + `tools/gate.sh quick` GREEN.

## Log
- 2026-08-24 — resolved, commit d86c82868.
