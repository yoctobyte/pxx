---
track: N
prio: 50
type: grant
blocked-by: []
summary: "Bounded cross-lane grant: frankS (Track S) may edit ONE site in Track N's pyparser.inc -- the `TargetArch = TARGET_XTENSA` refusal and its justifying comment at ~line 45973 -- as part of the arch-vs-platform ruling. Nothing else in the file. Granted because leaving the fifth site unedited recreates, in NilPy, the exact refusal the ruling retires."
status: backlog
---

# Grant: the xtensa refusal site in `pyparser.inc`, to frankS, bounded

**Granted 2026-08-30 by the coordinator, filed at the moment of giving.** An
unfiled grant fails both ways: it reads as covered because a neighbouring ticket
covers the same file, and the tooling cannot see it.

## What is granted

**One site.** `compiler/pyparser.inc` at approximately line 45973: the
`if TargetArch = TARGET_XTENSA then Error(...)` refusal and the comment
justifying it, which is carried **verbatim** from the four sites the
arch-vs-platform ruling already names.

**Nothing else in that file**, and nothing else in Track N. If the edit turns
out to need a second site, a symbol rename, or anything in `pylexer.inc`, that
is a new conversation and not an extension of this one.

## Why it is granted rather than handed off

`pyparser.inc` is **Track N's carved-out file** and the standing rule is that a
frontend owns its own parser: a lane needing a change in someone else's frontend
files the ticket and hands it over. That rule is right and this grant does not
weaken it.

Three things make this the exception rather than an erosion of it:

1. **The omission is the defect.** The ruling retires a premise — the hosted
   profile separated `arch` from `platform`, so every claim written before it
   that used "xtensa" to mean "ESP/FreeRTOS" expired without being edited. A
   session that implements the runtime and touches only the four Pascal sites
   leaves **NilPy on hosted xtensa refused by a premise that same commit just
   retired.** That is the ordinary fix-one-arm-and-forget-the-sibling hazard, and
   it is exactly what `normalise-dont-special-case` says to grep for before
   closing.
2. **Contention does not widen.** Measured before granting: no tree holds
   `pyparser.inc`, and no commit in the recent range touches it. The binding
   constraint the ruling identifies is the `pasparser_*` set, which frankA holds
   and which this does not go near. `symtab.inc` is likewise frankA's and is not
   in scope here.
3. **Two copies here are the intended design, not drift.** Under
   `the-substrate-is-ast-and-ir-not-the-parser`, the Pascal and NilPy frontends
   duplicating a refusal is correct — parsers are duplicated across languages on
   purpose. So there is no refactor to propose and no shared helper to reach for;
   there is one line in each frontend and both must move.

## Standing constraint

**Push immediately after the edit.** The value of the narrow scope is that the
file is held for minutes rather than a session, and an unpushed edit holds it
without anyone being able to see that it does.

`regression-nilpy-a-literal-str-receiver-with-key-reaches-no-keyed-overload`
[N p50] also needs this file — the keyword promoter, far from line 45973 — and
whoever takes it should sequence after this grant is pushed rather than merge
against it. That ticket is unclaimed as of this filing.

## Provenance

frankS found the fifth site by grepping for the refusal's own comment text after
the coordinator flagged an **adjacency** between two expired xtensa premises and
explicitly declined to assert it was one mechanism. It is one mechanism, and the
grep rather than the adjacency is what says so. The ruling's own file list names
four sites; this is the fifth, and the ruling has been amended.
