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

## The driver inventory, measured 2026-08-24 — whoever does this starts here

Taken while fixing
[[bug-a-a-basic-program-is-an-illegal-instruction-on-aarch64-and-arm32]], which
turned up the FIFTH and SIXTH missing steps in the BASIC driver. Everything
below is grepped, not remembered.

**Nine drivers open-code the entry stub** (`EmitB($48); EmitB($89); EmitB($24);
EmitB($25); EmitGlobRef(BSS_INITIAL_RSP)` — x86-64 bytes, unconditionally):
`aparser` (Ada), `eparser` (Erlang), `fparser` (Fortran), `bparser` (BASIC),
`gparser` (Algol), `lparser` (LOLCODE), `wparser` (Whitespace), `rparser`
(Rust), `zparser` (Zig). `cparser` has its own per-arch chain. Only the Pascal
and NilPy drivers call `EmitProgramEntryForTarget`, and BASIC now does too.

**Eight of those nine are saved by a guard, not by the code being right.** They
open with `if TargetArch <> TARGET_X86_64 then Error('<lang> frontend: only the
x86-64 target is supported by the skeleton')`. BASIC had no such guard, which is
the entire reason it was the one that shipped a SIGILL binary. So the guard is
load-bearing today and a driver that gains a cross target without adopting the
shared prologue gets BASIC's bug for free.

**Six drivers never called `EmitFinalizerRunnerBody`** — `bparser`, `aparser`,
`fparser`, `gparser`, `lparser`, `wparser`. Fixed in that change; the comment on
the routine still claimed it was *"called before ApplyCallFixups by every
frontend driver"*, which had never been true.

**The same six never call `ApplyCallFixups` either, and nothing else does it for
them.** `DceRun` — whose trailing `ApplyCallFixups` is the only one they could
inherit — is off unless `--dce` **and** x86-64 **and**
`IsPascalFrontend`. So a forward call in those frontends is resolved by nothing
at all; it keeps its placeholder for the whole compile. That is why the
placeholder had to become a NOP on every non-x86-64 target, and it is a good
argument for the prologue's counterpart: a shared **epilogue**
(`EmitProgramEpilogue`), which the ticket above does not currently name.

Adding `ApplyCallFixups` to `bparser` is blocked on
[[bug-a-a-unit-free-basic-program-calls-a-helper-it-never-emits]] — it turns a
unit-free `.bas` program with a string literal into a compile error, because the
managed-string helper it calls only ships with builtinheap.

### Suggested shape, updated

`EmitProgramPrologue(needs)` **and** `EmitProgramEpilogue`, adopted driver by
driver with each frontend's test output diffed before and after — the skeleton
frontends all have exactly one test each (`test_ada_skeleton.adb`,
`test_algol_skeleton.alg`, `test_erlang_skeleton.erl`,
`test_fortran_skeleton.f90`, `test_lolcode_skeleton.lol`, `test_ws_skeleton.ws`)
and they run in about a second, so per-driver verification is cheap. Do NOT
sweep all nine in one commit: the BASIC fix above changed emitted bytes for one
driver and needed four measurement rounds to get right.
