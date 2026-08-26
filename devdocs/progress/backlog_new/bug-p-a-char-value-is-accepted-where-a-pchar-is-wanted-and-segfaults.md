---
track: P
prio: 60
type: bug
blocked-by: []
summary: "A Char VALUE (a `c: Char` variable, or `Chr(45)`) is accepted where a PChar parameter is expected and its ordinal is passed as the pointer, so the callee dereferences address 45. FPC refuses the variable outright and const-folds `Chr(45)` into a character constant that converts. Two answers are defensible — refuse, or const-fold — and they are not the same answer for the two shapes."
status: backlog
owner: unassigned
---

# `Show(c)` / `Show(Chr(45))` with a `PChar` parameter passes the ordinal

Found 2026-08-26 by Track P alongside
`bug-single-char-literal-as-pchar-argument-segfaults`, which fixed every
CONSTANT shape (`'-'`, `#45`, a named `const Dash = '-'`) by retagging the
literal as the one-character string it also is. These two shapes are not
constants as far as pxx is concerned, so nothing retags them and the ordinal
still goes where the pointer goes.

## Repro

```pascal
program d;
procedure Show(p: PChar);
begin Writeln(p[0]); end;
var c: Char;
begin
  c := '-';
  Show(c);        { pxx: SEGFAULT.  fpc: compile error }
  Show(Chr(45));  { pxx: SEGFAULT.  fpc: prints `-`    }
end.
```

| shape | FPC 3.2.2 | pxx (HEAD, 2026-08-26) |
| --- | --- | --- |
| `Show(c)`, `c: Char` variable | `Error: Incompatible type for arg no. 1: got "Char" expected "PChar"` | compiles, **segfaults** |
| `Show(Chr(45))` | prints `-` | compiles, **segfaults** |

FPC's rule, measured rather than recalled: a character **constant** converts to
a pointer to a NUL-terminated one-character string; a character **variable**
does not convert at all. `Chr(45)` is a constant expression there, so it is on
the converting side of that line — the boundary is CONSTNESS, not literalness.

## Two forks, and they want different answers

* **`Chr(45)`** — pxx does not constant-fold `Chr` of a literal, so the node is
  a runtime `AN_UNOP` tagged `tyChar` rather than the `AN_INT_LIT` the shared
  resolver (`IsCharLitNode`, `compiler/pasparser_name.inc`) recognises. Folding
  it would put it on the already-correct path with no new rule at all, and
  would fix the constant-expression family generally (`Chr(x)` where x is a
  const, `Succ('a')`, …). That looks like the right fix.
* **`c: Char` variable** — there is no constant to materialise, so the only
  correct answers are "refuse" (FPC's) or "keep segfaulting". Refusing is a
  strictness change: pxx's overload matching accepts `tyChar` → `tyPointer`
  today, and that same laxity is what lets `Show('-')` match the PChar overload
  at all before the retag runs. So tightening it needs the match to distinguish
  a char CONSTANT from a char VALUE, not just to drop the conversion.

Because the second half is a dialect-strictness call rather than a
mechanical fix, whoever takes this should settle it first — possibly as a
Track U `decide-*` — rather than guessing.

## Why prio 60

A wild-pointer dereference, which the owner's rule ranks high; but unlike the
literal case, both spellings are *unusual* code (passing a bare Char where the
signature says PChar), and neither is the invisible shape-dependence that made
`StrCat(buf, '-')` worth 80.

## Gate

Track P: `make compiler/pascal26` (self-host fixedpoint) + the two rows above
matching FPC. Add them to `test/test_char_literal_to_pchar_param.pas`, whose
header already notes that a char VARIABLE is deliberately absent pending this
ticket.
