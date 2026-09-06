---
slug: feature-pascal-management-operators-copy-and-addref
title: "`class operator Copy` / `AddRef` are recognised but never dispatched"
track: P
prio: 30
type: feature
status: backlog
owner: ""
blocked-by: []
summary: "`class operator Copy` and `AddRef` PARSE and register, and the compiler then refuses at the use site rather than compiling them silently: `operator Copy/AddRef is recognised but not dispatched yet`. Initialize/Finalize landed in slice 3 and WORK -- measured 2026-09-06, both fire for a local and in the right order -- so this is the copy/assign lifetime event only. CORPUS EVIDENCE, measured 2026-09-06 at 88a0b3d93835: fpc testsuite tmoperator8 stops on exactly this refusal at line 63, and it is the ONLY one of the six live tmoperator rows that does. That is the demand for this slice and the reason it is not speculative. The refusal is deliberate and must stay until the dispatch lands: a record whose declared invariant simply never runs is a plausible wrong value far from the cause, which is the expensive shape here."
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

## 2026-09-06 (frankS) — the corpus row that asks for this

`tmoperator8.pp` in the fpc testsuite stops at line 63 on this ticket's own
refusal string, and it is the only one of the six live `tmoperator` rows that
does. Measured at `88a0b3d93835`; the other five split two-and-three onto
[[feature-pascal-management-operators-nested-and-array]] and
[[feature-a-record-rtti-descriptors-for-initializearray-and-finalizearray]].

**Skip row, verbatim, so the evidence and the ticket cannot drift apart:**

    tmoperator8.pp	gap: management operators AddRef/Copy/Initialize/Finalize on records

That reason is only two-thirds true and is corrected in the same commit:
Initialize and Finalize work. The row is blocked on Copy/AddRef alone.
