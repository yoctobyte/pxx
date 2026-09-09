---
track: P
prio: 60
type: bug
status: done
owner: frankS
resolved-by: frankS
created: 2026-09-09
found-by: frankS
tags: [overload, arity, methods]
blocked-by: []
summary: "A bare method call inside its own class body -- implicit Self, the most common method call there is -- was bound at ANY arity, silently. FindUMethOverloadAhead is a SELECTOR: with no candidate whose arity fits it falls through to FindUMethArity and then to FindUMeth, the first name match at any arity, and the hand-rolled argument loop at pasparser_stmt.inc then appends whatever it parses without consulting the signature. Measured against fpc 3.2.2, which refuses all four: `Plain(1.5,2,3)` and `Plain(1.5,2)` onto one parameter gave x=0.0 with every argument lost; `Two(7,8,9)` onto two gave a=8 b=9 with Self eating the 7; `Two(7)` gave a=369098760 -- UNINITIALISED memory, no crash and no diagnostic. The other three spellings of the same call -- Self.Plain(...), c.Plain(...) and a free routine -- were all refused already, so this was the arm that stayed broken. Fixed by asking FindUMethArityStrict at that site, with a carve-out for a trailing `array of const`: variadic bracket-elision passes MORE arguments than the signature has on purpose, it is a pxx extension fpc refuses, and it reaches the site through the very fallback being closed -- a gate written from fpc's answer alone would have deleted it in silence. Fixtures both directions; the still-valid one is byte-identical against the PINNED pre-fix compiler. Gate GREEN."
---

# A bare method call inside its own class ignores its arity

- **Type:** bug — **Track P** (`compiler/pasparser_stmt.inc`, the implicit-Self
  call site; helper in `compiler/pasparser_lval.inc`).
- Found inside the candidate-selection group, while measuring whether
  [[bug-p-a-shadowed-soft-intrinsic-is-closed-without-consulting-the-arguments]]
  still had a live instance. It does not — but a class with a method named
  `Delete` shadowing the intrinsic turned out to accept `Delete(a, 1, 1)` and
  run `Delete(Double)` with 0.0. That has nothing to do with intrinsics.

## The measurement

fpc 3.2.2 refuses every row; pre-fix pxx compiled all four clean.

| call | signature | pxx ran |
| --- | --- | --- |
| `Plain(1.5, 2, 3)` | `Plain(x: Double)` | `x=0.0` — every argument lost |
| `Plain(1.5, 2)` | `Plain(x: Double)` | `x=0.0` |
| `Two(7, 8, 9)` | `Two(a, b: Integer)` | `a=8 b=9` — Self ate the 7 |
| `Two(7)` | `Two(a, b: Integer)` | `a=369098760` — **uninitialised** |

The last row is why this is not a diagnostics ticket. There is no crash and no
message; the callee reads whatever the argument slot held.

## Exactly one door of four

| spelling | pre-fix |
| --- | --- |
| `Self.Plain(1.5, 2, 3)` | refused |
| `c.Plain(1.5, 2, 3)` | refused |
| `Free1(1.5, 2, 3)` (free routine) | refused |
| **`Plain(1.5, 2, 3)` bare, inside the class** | **accepted** |

`FindUMethOverloadAhead` is a **selector** — asked *which* overload, having
already been told this is a method call — so with no arity-viable candidate it
answers with the first name match rather than declining.
`FindUMethArityStrict` exists precisely so a caller can decline, and its own
header says so; it had one caller, the `Write`-inside-a-`write`-member path.
This is the sibling site that was never given the strict question. Same shape
as [[bug-p-a-method-call-with-missing-arguments-is-accepted-and-reads-garbage]],
which fixed the QUALIFIED parenless spelling.

## The carve-out is a measured dependency, not caution

Variadic bracket-elision (`Desc('a', 1)` against
`Desc(const a: array of const)`, `feature-writeln-as-library`) passes **more**
explicit arguments than the signature has parameters, on purpose — and it
reaches this site through the very loose fallback being closed. **fpc refuses
that source too** ("Wrong number of parameters"), so an arity gate derived from
fpc's answer alone would have deleted a pxx extension with no test to notice.
Hence `UMethNameCanAbsorbVarRecTail`, asked of the NAME over the visible set
rather than of one candidate — the same shape and the same reason as
`ParamIsVarRecArray` beside it.

## Not fixed here, and deliberately

The elided spelling of that extension **segfaults** at this door while the
bracketed one works. Separate defect, separate ticket:
[[bug-p-a-bare-variadic-method-call-segfaults-where-the-bracketed-spelling-works]].
Converting a segfault into a diagnostic as a side effect of an arity fix would
have hidden it.

## Verification

- `test_p_a_bare_method_call_ignores_arity_fail.pas` — four diagnostics,
  rc=1, no binary.
- `test_p_a_bare_method_call_arity_still_valid.pas` — exact arity, trailing
  defaults, a parameterless method, two overloads, an inherited method and the
  bracketed `array of const`. **Byte-identical against the PINNED pre-fix
  compiler**, so the check refuses nothing that was legal.
- `gate.sh quick` GREEN, self-host fixedpoint converged.
