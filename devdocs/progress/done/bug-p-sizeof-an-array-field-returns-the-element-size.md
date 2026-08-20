---
track: P
prio: 45
type: bug
blocked-by: []
summary: "`SizeOf(x.F)` where F is a fixed-array FIELD of a record or class returns the ELEMENT size, not the array's: `4 4 12` where FPC 3.2.2 prints `12 12 12` for the same three `array[0..2] of Integer`. A silent wrong VALUE, no diagnostic — a `Move`/`FillChar` sized this way copies one element and looks like it worked."
status: done
owner: frank1-ACP
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

## Root cause (measured, 2026-08-20, frank1-ACP)

`SizeOf`'s hand-rolled selector walk (`parser.inc`, the
`SizeOf(obj.field[.field..])` branch) sized the final field as

```pascal
prevTok := TypeSize(szElemTk);       { szElemTk := RecFieldType(szRec, ...) }
```

and **`RecFieldType` answers an array field's ELEMENT kind** — `UFldTk` holds
the element type, which the codebase's own comment two branches down calls "a
recurring landmine throughout this codebase". So the walk was never told the
field was an array at all. The branch's comment claimed *"an array field is out
of scope and errors below"*; it did not error, it answered 4.

`Length(r.A)` and `High(r.A)` were already correct — the field's array-ness IS
recorded (`UFldIsArray` / `UFldArrLen` / `UFldArrNDims`), it just never reached
this one formula. That also confirms the filer's lane call: nothing shared is
wrong, and the C probe against the gcc oracle was right to come back clean.

## Fix

`RecFieldByteSize(rec, field)` in `symtab.inc` — **one** field-size answer for
every caller instead of a formula per site
(`devdocs/dev/normalise-dont-special-case.md`): static array → span product ×
element size (N-D via the dim table), dynamic array → pointer width, record →
`RecSize`, anything else → `TypeSize`. A field whose extent is not recorded keeps
today's answer rather than a confidently wrong new one. The selector walk calls
it per field, so a deeper chain sizes its LAST field.

## Second defect, found by widening the shapes

`SizeOf(<dynamic-array VAR>)` returned **-4**. The variable branch computes
`TypeSize(ElemType) * Syms[sci].ArrLen`, and a dynamic array's `ArrLen` is -1 —
a NEGATIVE size, silently, which `GetMem(SizeOf(d))` or a `Move` sized that way
would carry into the allocator. A dynamic array variable is a handle, so it now
answers pointer width: the rule the named dynamic-array ALIAS branch already
applied and that the FIELD side gets from `RecFieldByteSize`. Three spellings of
one concept, two of which were wrong in different directions.

## Also found, NOT fixed here (separate ticket)

`SizeOf(p^.A)` — a pointer deref anywhere in the operand — is a **parse error**
(`Expected: ), but got: ^`). Loud rather than silent, so it is a missing feature
rather than this bug, and fixing it means growing the hand-rolled walk again
rather than shrinking it. Filed as
[[bug-p-sizeof-rejects-a-pointer-deref-in-its-operand]].

## Verification

`test/test_sizeof_array_field.pas` — 22 assertions, **byte-identical output
under pxx and fpc 3.2.2**. Each array case is asserted against the plain-VAR
form of the same type, so the test states the invariant (a field sizes like a
variable) rather than freezing a number; the dynamic-var case is additionally
pinned absolutely, since only agreeing with itself is what let -4 hide. Shapes:
1-D, 2-D, enum-indexed, array-of-record, dynamic, shortstring, scalar, nested
record, on a record AND a class, through a two-level chain, and via `Self.`
inside a method — plus `Length`/`High` of the same field, the siblings the
ticket said to grep for.

Gate: `make compiler/pascal26` converged 1 round; `tools/gate.sh quick`.

## Log
- 2026-08-20 — resolved, commit PENDING-COMMIT.
