---
prio: 30
---

# `class operator Copy` / `AddRef` are recognised but never dispatched

- **Type:** feature (Pascal frontend, operator overloading)
- **Track:** P (shared `parser.inc` — A-gated)
- **Status:** backlog
- **Follows:** [[feature-pascal-class-management-operators]] — slice 3 landed
  Initialize/Finalize and refuses these two by name.

## Symptom

    error: operator Copy/AddRef is recognised but not dispatched yet — the copy
           lifetime event is a separate slice

The spelling parses, the arity is checked, the overload registers — and then
nothing invokes it, because pxx has no **copy** lifetime event. Accepting one
silently would give a record whose invariant never runs.

## What FPC does

- `class operator AddRef(var a: TFoo)` — after a value copy, on the DESTINATION.
- `class operator Copy(constref src: TFoo; var dst: TFoo)` — replaces the copy
  entirely; when present, `AddRef` is not called for that assignment.

Both fire wherever a record value is duplicated: assignment, passing by value,
returning by value, and copying into a container.

## Why it is a separate slice

Initialize/Finalize are *scope* events and desugar into `Initialize(v); try
BODY finally Finalize(v); end` around the routine body — one AST rewrite, no
backend work (see the parent ticket). A copy event has no such single site: it
has to be hooked wherever a record assignment is lowered, which is the
`AN_ASSIGN` record path plus the by-value argument and return paths — i.e. the
IR side, not the parser side. That likely makes the dispatch half a **Track A**
ticket once the shape is settled.

## Repro

The Copy refusal fixture under `test/` (currently pinned as an ERROR — it
becomes an output test when this lands).

## Gate

`make compiler/pascal26` (self-host fixedpoint) + a trace program diffed
against FPC 3.2.2 + `tools/gate.sh quick`.
