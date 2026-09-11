---
slug: bug-p-an-array-constructor-in-argument-position-is-typed-as-a-set
title: "`['x']` in argument position is typed as a set, so an `array of` overload is never reachable"
track: P
prio: 55
type: bug
status: open
owner: ""
found-by: frankH
created: 2026-09-11
tags: [overload-resolution, open-arrays, sets, array-constructor]
blocked-by: []
summary: "A `[...]` constructor in an argument position is typed as a SET unconditionally, so an `array of T` parameter can never be selected for one. Two outcomes, and the SECOND is the reason this is not a diagnostic ticket: with no set-typed candidate in scope pxx REFUSES (`no overload of P matches these arguments / argument types: (set)`) where fpc compiles; with a set-typed parameter in scope -- including one that is only a DEFAULT, `f: TF = []` -- pxx compiles and SILENTLY SELECTS THE WRONG OVERLOAD, answering 1 where fpc answers 2 on the same six-line source. Found while writing test/lib_sysutils_executeprocess.pas, whose real declarations have exactly the default-set shape; the fixture passes variables rather than literals to stay a test of ExecuteProcess."
---

# `['x']` is a set, even where only an array can go

## Repro

Six lines, no RTL, no `uses`:

```pascal
program n;
function P(const c: AnsiString): Integer; overload;
begin P := 1; end;
function P(const c: array of AnsiString): Integer; overload;
begin P := 2; end;
begin WriteLn(P(['x'])); end.
```

- fpc 3.2.2 (`-Mobjfpc`): compiles, prints **2**.
- pxx (pinned): **refuses**

```
pascal26:6: error: no overload of P matches these arguments
  argument types: (set)
```

Add a set-typed default parameter to both candidates -- `f: TF = []`, with
`TF = set of (fA, fB)` -- and the refusal becomes something worse:

- fpc: prints **2**
- pxx: compiles and prints **1**

The literal is typed as a set, the set-shaped candidate now accepts *something*,
and the `array of AnsiString` overload is never in the running. Nothing is
reported.

## Why the silent arm matters more than the refusal

A refusal is a wall: it stops, it names a line, somebody fixes it. The
default-parameter arm compiles clean and calls a different function, and the
only way to notice is to have an oracle beside you. Against the real
`sysutils.ExecuteProcess` declarations -- which carry `Flags: TExecuteFlags = []`
on both overloads, so they ARE this shape --
`ExecuteProcess('/bin/sh', ['x'])` answers **0** under pxx and **2** under fpc,
because pxx never passes the argument to a child at all.

A multi-element literal of multi-character strings takes a third door and
refuses with a message about the wrong construct entirely:
`ExecuteProcess('/bin/sh', ['-c', 'exit 4'])` gives
`pascal26:5: error: set item must be one character`, where fpc runs it and
answers 4.

## What it is NOT

Not a corpus blocker. FPC's own `cfileutl.pas` call sites pass variables, so
this does not gate `umbrella-pxx-compiles-fpc-itself`. It is filed on the
strength of the silent arm, not on population.

## Shape of the fix

The decision needs the CANDIDATE's parameter type to reach the constructor's
typing, rather than typing the constructor first and matching afterwards --
`[...]` is ambiguous by construction in this dialect and only the target type
disambiguates it. Whether that is a re-type-on-retry in the overload loop or a
deferred literal kind is an implementation question, not a fork.

## Provenance

Found 2026-09-11 while writing `test/lib_sysutils_executeprocess.pas` for
[[feature-b-sysutils-has-no-executeprocess-and-no-texecuteflags]]. The note that
survived into that fixture's header recorded the diagnostic as
`(ShortString, set, set)`; re-derived against the declarations as they actually
stand, the single-element case does not refuse at all -- it is the silent arm.
The remembered spelling was a refusal variant with the extra arguments still on
it. Recording that because the header comment still quotes the old spelling as
the reason it uses variables, and the reason is sound either way.
