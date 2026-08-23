---
track: A
prio: 40
type: refactor
summary: "Five frontend drivers each open-code the same program prologue (entry stub, div0 stub, signal runtime, I/O lock stubs, System intrinsics, the emitted AnsiString runtime). The copies drift in one direction — whatever the Pascal driver gained last — and the BASIC one has now been caught missing four of them, one at a time."
---

# One program-driver prologue, instead of five copies that drift

- **Type:** refactor (Track A — the drivers live in `pasparser_prog.inc`,
  `cparser.inc`, `pyparser.inc`, `bparser.inc` and the other skeleton frontends)
- **Status:** backlog — opened 2026-08-24 from the fourth instance
- **Owner:** —

## The pattern, measured rather than felt

Starting a program is a fixed checklist: entry stub → div-by-zero stub → signal
runtime → `--threadsafe` I/O lock stubs → System intrinsics (TGuid/TObject) →
the emitted AnsiString runtime (with its forwards) → parse → lower → exit. Every
frontend driver performs it, and every one of them performs it by hand.

The BASIC driver alone has now been caught missing **four** of those steps, each
found separately, each by a user-visible failure:

| missing step | how it surfaced |
| --- | --- |
| `--threadsafe` I/O lock stubs | call to code offset 0 — the ELF entry — hanging until the stack was gone |
| signal runtime | shipped with none at all ([[bug-a-only-the-pascal-driver-emits-the-signal-runtime]]) |
| `RegisterBuiltinTGuid` / `RegisterBuiltinTObject` | `unknown type: TGuid` reported inside a compiler builtin, against a BASIC program mentioning neither |
| the emitted AnsiString runtime | [[regression-test-core-test-basic-comprehensive-2]] — same code-offset-0 guard, one stub family later |

Three of those four comments sit within twenty lines of each other in
`bparser.inc`, each explaining that this frontend was the one that did not make
a call every other driver makes. The C and NilPy drivers have their own shorter
versions of the same list.

**The drift has a direction**: a driver is missing whatever the Pascal driver
gained most recently, because the Pascal driver is where new runtime support is
written and the others are updated only when something breaks. So the count of
missing steps grows with time, silently, and each one is found by a crash rather
than by a check.

## Shape

Not a shared PARSER — `devdocs/dev/the-substrate-is-ast-and-ir-not-the-parser.md`
still holds, and this is not parsing. It is the emission prologue, which is
already language-neutral: `EmitProgramEntryForTarget`,
`EmitProgramRuntimeStubsForTarget`, `RegisterEmittedStringRuntimeForwards` and
`EmitAnsiStringRuntime` are shared routines today. What is duplicated is the
CALL SEQUENCE and its guards.

One `EmitProgramPrologue(needs)` that every driver calls, with the per-frontend
variation passed in (BASIC has no `uses` pre-scan of its own; NilPy always wants
the string runtime on x86-64; C gates on `DetectPascalRuntimeNeeds`). A driver
then cannot forget a step, because there is no step to forget.

## Acceptance

- Every frontend driver reaches its parse through one prologue call.
- A new runtime stub family is added in ONE place and every frontend has it.
- Self-host byte-identical; `test-core` green including the `.bas`, `.c`, `.npy`
  and skeleton-frontend jobs; cross targets unaffected (the prologue's
  target conditionals move with it).

## Not

- Not a merge of the parsers, the lexers or their helpers.
- Not a change to WHAT any driver emits today — a pure de-duplication, so a
  driver that is currently missing a step GAINS it, and that is the point.
