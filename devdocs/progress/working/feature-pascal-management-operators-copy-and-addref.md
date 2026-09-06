---
slug: feature-pascal-management-operators-copy-and-addref
title: "`class operator Copy` / `AddRef` are recognised but never dispatched"
track: P
prio: 30
type: feature
status: working
owner: frankA
blocked-by: []
summary: "`class operator Copy` and `AddRef` PARSE and register, and the compiler then refuses at the use site rather than compiling them silently: `operator Copy/AddRef is recognised but not dispatched yet`. Initialize/Finalize landed in slice 3 and WORK, including a nested managed FIELD at any depth and every element of a FIXED array (2026-09-06). THIS TICKET'S OWN `What FPC does` SECTION WAS WRONG AND IS CORRECTED IN PLACE: it said Copy `replaces` AddRef and that both fire wherever a record value is duplicated. Measured against fpc 3.2.2 with three programs differing only in which operators are declared, they are DISJOINT SITES and neither ever displaces the other -- Copy is the ASSIGNMENT event (`b := a`, `b := Mk`, `arr[0] := a`), AddRef is the BY-VALUE PARAMETER event and only that, and a `const` or `var` parameter runs neither. With Copy declared and AddRef absent the by-value copy runs NO operator at all while its slot is still Finalized, so the two halves do not share a site and CAN LAND INDEPENDENTLY. Swept -O1..-O3, identical. CORPUS EVIDENCE, measured 2026-09-06 at 88a0b3d93835: fpc testsuite tmoperator8 stops on exactly this refusal at line 63, and it is the ONLY one of the six live tmoperator rows that does -- it declares all four operators. The refusal is deliberate and must stay until the dispatch lands: a record whose declared invariant simply never runs is a plausible wrong value far from the cause, which is the expensive shape here."
---

# `class operator Copy` / `AddRef` are recognised but never dispatched

- **Type:** feature (Pascal frontend, operator overloading)
- **Track:** P (shared `parser.inc` — A-gated)
- **Status:** working
- **Follows:** [[feature-pascal-class-management-operators]] — slice 3 landed
  Initialize/Finalize and refuses these two by name.

## Symptom

    error: operator Copy/AddRef is recognised but not dispatched yet — the copy
           lifetime event is a separate slice

The spelling parses, the arity is checked, the overload registers — and then
nothing invokes it, because pxx has no **copy** lifetime event. Accepting one
silently would give a record whose invariant never runs.

## What FPC does — MEASURED 2026-09-06, and it is not what this section said

The two paragraphs that used to sit here said `Copy` *"replaces the copy
entirely; when present, `AddRef` is not called for that assignment"* and that
both *"fire wherever a record value is duplicated"*. **Both claims are false
against fpc 3.2.2.** They describe a precedence between two operators that
compete for one event; what fpc actually has is two operators on **disjoint
sites**, and no site where the choice between them arises.

Measured with three programs differing only in which operators are declared —
AddRef alone, both, Copy alone — each operator printing its own name so a value
check cannot confuse them:

| duplication site | AddRef alone | both declared | Copy alone |
| --- | --- | --- | --- |
| `b := a` (local := local) | *nothing* | **Copy** | **Copy** |
| by-value parameter | **AddRef** | **AddRef** | *nothing* |
| `b := Mk` (return into a var) | *nothing* | **Copy** | **Copy** |
| `arr[0] := a` (into a container) | *nothing* | **Copy** | **Copy** |
| `const` parameter | *nothing* | *nothing* | *nothing* |
| `var` parameter | *nothing* | *nothing* | *nothing* |

Read the middle column against the two outer ones: with BOTH declared, the
assignment sites still run Copy and the by-value site still runs AddRef. Neither
operator ever displaces the other, because neither is ever offered the other's
site. So:

- **`Copy(constref src; var dst)` is the ASSIGNMENT event** — every store of a
  record value into an existing destination.
- **`AddRef(var a)` is the BY-VALUE PARAMETER event, and only that** — the copy
  the caller makes into the callee's parameter slot.

The Copy-only column is the one that settles it: the by-value parameter runs
**no operator at all**, while its slot is still Finalized at exit. So a declared
`Copy` is silently not honoured for a parameter copy — arguably fpc's own gap,
and recorded here as measurement rather than as a target.

**Axis swept:** `-O1`, `-O2`, `-O3`, identical at all three (`-O0` is not an fpc
spelling). Not swept: a record with a genuinely managed FIELD (ansistring,
interface) alongside the operators, which could route the copy through a
different helper — check that before relying on the table for such a record.

**What this changes for the slice.** The scope is much narrower than "wherever a
record value is duplicated": `Copy` hooks the RECORD-ASSIGNMENT lowering, which
already has a branch to hang it on — `ir.inc` tests `RecordHasManagedFields` and
picks `IR_COPY_REC_MANAGED` over `IR_COPY_REC` at the general `AN_ASSIGN` arm
and again at the inline-var-decl arm. A Copy operator is a third arm in the same
choice, emitting a call instead of a bulk copy. `AddRef` is a separate and much
smaller hook at the by-value record argument copy. **The two halves do not share
a site and could land independently**, which the old framing hid by treating
them as one event with a precedence rule.

Not yet established: whether those two `IR_COPY_REC_MANAGED` arms are the whole
assignment population. There are 78 `IR_COPY_REC` mentions across `compiler/`;
a census keyed on which of them can receive a USER record assignment is the
first task of the implementing slice, and a call-site census is open-world — see
the field-vs-call-site distinction before trusting a count of them.

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
