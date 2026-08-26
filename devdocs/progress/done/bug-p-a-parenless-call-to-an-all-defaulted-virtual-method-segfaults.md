---
summary: "A parenless call to an all-defaulted VIRTUAL method (`d.Foo;`) sent the call out carrying only Self, so the callee read an uninitialised frame slot and SEGFAULTED; every neighbouring spelling worked"
type: bug
track: P
prio: 70
---

# `d.Foo;` on an all-defaulted virtual method segfaults

- **Type:** bug (Pascal frontend — method-call argument filling) — **Track P**
- **Found and fixed 2026-08-26**, while fixing
  [[bug-p-inherited-ignores-the-parents-default-parameter-values]]. Not filed
  before being fixed: it was found by varying that ticket's repro and is the
  same missing step on a different call path, so it landed in the same commit.

## Measured

```pascal
type TBase = class
  n: Integer;
  procedure D(a: Integer = 3); virtual;
end;
var d: TBase;
begin d := TBase.Create; d.D; WriteLn(d.n); end.
```

| spelling | fpc 3.2.2 | pxx (before) |
| --- | --- | --- |
| `d.D;` — **virtual**, all-defaulted, NO parens | `3` | **SEGFAULT** |
| `d.D();` — empty parens | `3` | `3` |
| `d.D(5);` — explicit | `5` | `5` |
| `d.Z;` — virtual, ZERO parameters | `42` | `42` |
| `d.D;` where `D` is **non-virtual** | `3` | `3` |

## Why it survived: every neighbour works

The crashing cell is the only one. A zero-parameter method is fine because
there is nothing to fill; empty parens are fine because that arm was added
deliberately (for `J.FormatJSON()`); explicit arguments are fine; and the
NON-virtual spelling of the identical source is fine. So any test written
"nearby" passes, and the shape that crashes is the one whose siblings all work.

## Cause

In `ParseLValueAST`'s instance-method branch, argument parsing is
`if CurTok.Kind = tkLParen then begin ... end;` — with **no else**. With no
parentheses the call node went out carrying only Self, the arity was short by
the defaulted parameters, and the callee read an uninitialised frame slot. On a
virtual call that is a fault; non-virtual happened to survive it.

## The trap inside the fix, worth more than the fix

The obvious repair is `else if CanFillDefaultsFrom(mpi, 1) then
FillDefaultArgs(...)`. **That does nothing**, and it compiles and self-hosts
while doing nothing. `CanFillDefaultsFrom` is

```pascal
Result := (CurTok.Kind = tkRParen) and ... and ProcParamHasDefault[...];
```

so it really answers *"the argument list ENDS HERE and the rest can default"* —
two questions under one name. With no parentheses `CurTok` is `;`, so it
answers False for a method whose parameters plainly do have defaults. The first
attempt at this fix did exactly that and the segfault was unchanged.

The arm therefore tests `ProcParamHasDefault` directly. `CanFillDefaultsFrom`
is left alone: eight call sites depend on its `tkRParen` half, and splitting it
is a separate change. Noted here because the next person to add a defaults arm
will reach for it too.

## Verified

`test/test_inherited_and_parenless_defaults.pas`, byte-identical against
fpc 3.2.2, with all five rows above plus the partial-argument case
(`b.Foo(7)` → the second parameter defaults). `gate.sh quick` GREEN.
