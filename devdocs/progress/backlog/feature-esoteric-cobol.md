# Esoteric probe: COBOL

- **Type:** feature — esoteric-frontend-probe
- **Status:** backlog
- **Umbrella:** [[feature-esoteric-frontend-probes]]
- **Opened:** 2026-07-05

## What it is

Verbose, deliberately English-like business language. Programs are split into
DIVISIONs (`IDENTIFICATION`/`ENVIRONMENT`/`DATA`/`PROCEDURE`), with data
declared via `PICTURE` clauses describing fixed-format decimal/text layouts
(`PIC 9(5)V99` = a 5-digit-plus-2-decimal fixed-point number) rather than
ordinary type names.

## Why it's a good probe

The "closest to human expression" thread from this session's brainstorm, for
real this time — COBOL was explicitly designed to read like English business
prose. Structurally it's the most different candidate on this list: no
functions-as-primary-unit (DIVISION-structured instead), and `PICTURE`-clause
fixed-decimal data has no direct equivalent in PXX's type system (closest is
manual scaled-integer arithmetic) — good diversity for the fuzz-probe goal.

## Scope (skeleton only — see umbrella for the category rule)

Lexer + parser for a minimal 4-division skeleton + `DISPLAY` (COBOL's
`VISIBLE`-equivalent) + a couple of `PIC 9(n)` integer variables — no
fixed-decimal (`V99`-style) arithmetic in v1, no file/record I/O. Stop once a
trivial "hello world"-shaped program compiles and runs, or a shared bug
surfaces trying to get there.

## Acceptance

Either: (a) a shared IR/codegen/ABI bug is found and filed as its own Track A
ticket, or (b) the trivial subset compiles and runs clean — both close this
probe successfully.

## Log
- 2026-07-05 — filed as part of the esoteric-frontend-probes umbrella.
