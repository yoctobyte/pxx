---
slug: bug-p-an-unspecialized-generic-name-used-as-a-type-is-accepted-and-sized-as-nothing
track: P
prio: 35
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankS
blocked-by: []
title: "A bare generic name used as a type (`^TTest` for `generic TTest<T>`) is accepted, sized as 4, and its fields are writable"
summary: "`PBig = ^TBig` where TBig is `generic TBig<T>` compiles clean OUTSIDE the generic's own scope. It is not merely accepted: SizeOf through it answers 4 for a record whose real specialization is 32, `New(p)` allocates those 4 bytes, `p^.a := 1.0` is ACCEPTED and writes 8 bytes into a 4-byte block, and reading the field straight back gives 0. So one construct produces a heap overflow AND a wrong value AND no diagnostic. The 4 is `TypeStorageSize(tyUnknown)` — nothing was recorded — which is exactly the collision CLAUDE.md warns about: an Integer-shaped probe cannot tell a right answer from a blank one, and only a 32-byte pointee separates them. SEVERITY IS CAPPED BY REACHABILITY, deliberately: fpc REJECTS this source, so no FPC-valid program reaches it and this can only be arrived at from code that is already wrong — the claim is that the mistake gets no diagnostic, not that working code breaks. THE FIX IS NOT A BLANKET REFUSAL: inside a generic's own body the bare name legally means the current instantiation, so every generic method depends on it being accepted there; the refusal has to be scoped to uses outside the declaring generic."
---

# Measured 2026-09-06, compiler `e4abd7e3c3e7` (commit a952d4591)

```pascal
generic TBig<T> = record a, b, c: Double; t: T; end;
PBig     = ^TBig;                       { fpc: rejected. pxx: accepted }
TRealBig = specialize TBig<Double>;
PRealBig = ^TRealBig;

SizeOf(p^)  { PBig }      = 4      <- TypeStorageSize(tyUnknown): nothing recorded
SizeOf(q^)  { PRealBig }  = 32     <- the real answer

New(p);          { survives — allocates 4 }
p^.a := 1.0;     { ACCEPTED — writes 8 bytes into a 4-byte block }
writeln(p^.a);   { 0 — the write and the read do not even agree }
```

The first probe used `T = Integer`, where the true pointee size is **8** and the
blank answer is **4** — close enough to read as "a size, just wrong". Re-cut at
32 bytes on purpose, per the CLAUDE.md rule that a probe whose right answer can
collide with a type default is a guard that cannot fail.

## Scope of any fix — read this before refusing anything

Inside a generic's own body the bare name is LEGAL and means the current
instantiation; `procedure TList.Add` and an internal `PItem = ^TItem` both rely
on it. A refusal keyed on "the name denotes a generic" therefore breaks every
generic method in the tree. The condition wanted is narrower: the name is used
as a type *outside* the scope of the generic that declares it, with no argument
list. That is why this is ranked rather than fixed on sight.

## Corpus

Three fpc-testsuite `{%FAIL}` rows are this one defect and are consolidated onto
it: `tgeneric83.pp` (`{$mode delphi}`, `Test: ^TTest = Nil`), `tgeneric84.pp`
(`PTest = ^TTest`), `tgeneric85.pp` (objfpc `const Test: ^TTest = Nil`). Their
previous reason read *"invalid generic record body accepted (pre-specialization
checking)"*, which names the wrong thing — the record bodies are fine and
nothing about pre-specialization checking is involved; it is the bare name in
type position.

NOT the same as `tgeneric21.pp` (a generic nested in a generic — fpc rejects,
pxx accepts, and that one is a genuine dialect pass) or `tclass13c.pp`
(`TRootClass.Integer` — a qualified member lookup falling through to global
scope, a different missed diagnostic).
