---
track: P
prio: 45
type: bug
blocked-by: []
summary: "`SizeOf(x.F)` where F is a fixed-array FIELD of a record or class returns the ELEMENT size, not the array's: `4 4 12` where FPC 3.2.2 prints `12 12 12` for the same three `array[0..2] of Integer`. A silent wrong VALUE, no diagnostic — a `Move`/`FillChar` sized this way copies one element and looks like it worked."
---

# `SizeOf(<array field>)` returns the element size

- **Type:** bug (Pascal frontend) — **Track P**.
- **Filed:** 2026-08-20 by frank3, while clearing wall 18 of
  [[feature-pascal-corpus-generics]]. Pre-existing and unrelated to that fix:
  reproduced on pinned v368 *and* on a self-hosted build at `57b9b7148`.
- **Shared-file catch:** the fix lands in the SHARED `compiler/parser.inc` /
  the `SizeOf` builtin, which Track P and Track A both touch. Whoever takes it
  obeys A's gate and the no-concurrent-edit rule.

## The bug

```pascal
program sz;
{$mode objfpc}{$H+}
type
  TR = record A: array[0..2] of Integer; end;
  TC = class public B: array[0..2] of Integer; end;
var r: TR; c: TC; v: array[0..2] of Integer;
begin
  c := TC.Create;
  WriteLn(SizeOf(r.A), ' ', SizeOf(c.B), ' ', SizeOf(v));
end.
```

| | record field | class field | plain var |
| --- | ---: | ---: | ---: |
| pxx (`57b9b7148`, self-hosted) | **4** | **4** | 12 |
| FPC 3.2.2 (oracle) | 12 | 12 | 12 |

The *variable* answers correctly, so this is not `SizeOf` and not the array
type — it is the selector path losing the array-ness of a FIELD and reporting
its element's size instead.

**Lane measured, not guessed.** The obvious alternative root was the shared
type-descriptor ground — pxx models an array by its ELEMENT type, which broke
the C frontend five separate silent ways once already. So the C side was probed
before filing: a `struct R { int a[3]; }`, `sizeof(r.a)` against the gcc oracle,
same binary, answers **12 and gcc answers 12**. C is clean, so this is the
Pascal FIELD path and not shared descriptor ground — hence Track P. If a fix
turns out to reach `symtab.inc` after all, re-file it A. Same shape as the field-vs-var split that wall 18
turned out to be, and worth checking whether the two share a cause: the field
paths know less about arrays than the var path does at several points.

## Why it matters more than the number suggests

There is no diagnostic. `Move(src.A, dst.A, SizeOf(src.A))` and
`FillChar(r.A, SizeOf(r.A), 0)` are the idiomatic uses, and both silently touch
one element of three while every surrounding line reads as correct — the class
of bug `devdocs/dev/debugging-playbook.md` opens on: a plausible wrong value
far from the cause, not a crash.

## Suggested first probes

- `PXXDBG=a.ast:<proc>` on the `SizeOf(r.A)` expression — is the argument node
  already typed as the element, or does `SizeOf` mis-fold a correctly-typed
  array selector? Do not reason about it; print it.
- Check dynamic-array fields and `array[TKind]` fields (now parseable, see
  wall 18) for the same answer.
- Grep the sibling before closing: `Length()` and `High()` of the same field.
