---
track: P
prio: 60
type: feature
summary: "A routine directive that is accepted but cannot be honored is silently ignored — `iram` on x86-64, `inline` anywhere (the flag is written and never read), `register`, `cdecl` on a routine. Warn: 'directive ignored here', so the source stops claiming something the build does not do."
status: done
---

# Warn when a routine directive is accepted but cannot be honored

- **Type:** feature (Pascal frontend — diagnostics) — **Track P**
- **Opened:** 2026-08-03, from the user while documenting decorators:
  *"at worst, worth a warning 'you declared this decorator but it cannot be
  fulfilled' or 'its invalid/ignored/conflicting/overruled by calling
  convention'."*

## The situation

Routine directives fall into three groups today (measured, and now tabulated in
`docs/language/dialect.md#routine-directives`):

- **load-bearing** — `assembler`, `generator`, `async`, `stackless`,
  `interrupt`, `flexcolumn`, `external`, `virtual`/`override`/`abstract`,
  `static` on a class method;
- **accepted and ignored** — `cdecl`, `register`, `inline`, `stackful`,
  `reintroduce`, `static` on a plain routine, `iram` off the ESP targets, and
  the hint directives;
- **rejected** — `stdcall`, `safecall`, `pascal`, `mwpascal` outside a method
  declaration, and `varargs` anywhere
  ([[compat-pascal-calling-convention-directives-uneven]]).

Only `interrupt` says anything when it cannot be honored:

```
error: interrupt directive: raw hardware-vector codegen implemented for riscv32
(esp32c3) and xtensa Call0 (esp32s3) only. Use `iram;` for an IDF-registered ISR.
```

Everything else is silent. `iram` on x86-64 compiles clean. So does `cdecl` on a
routine — and there the silence is defensible (the convention is the target's,
so the marker is documentation) but a reader cannot tell the two cases apart.

## `inline` is the interesting one

`ProcInline` is **written and never read.** `if declInline then
ProcInline[procIdx] := True` in `parser.inc` is its only mention outside the
`False` initialiser in `symtab.inc`; no backend, IR pass or inliner consults it.
The `-O2` inliner decides purely on shape — a function, scalar result, at most
six scalar by-value params, not external/cdecl/variadic/generator/stackless.

Measured with `PXXDBG=a.inline` at `-O2` on a marked and an unmarked routine of
the same shape:

```
PXXDBG a.inline RETAIN twice  shape=1 params=1     { NO inline directive }
PXXDBG a.inline RETAIN thrice shape=1 params=1     { inline; }
```

Identical. So `inline` neither helps nor hurts, and a routine that does not
qualify is not inlined however loudly it is marked. That matches every modern
compiler — the directive is a hint and the optimizer already knows — but it
means a user writing `inline` on a six-parameter procedure returning a record is
being told nothing while getting nothing.

## Proposal

A single `warning: directive 'X' is ignored here` diagnostic, off by default or
under an existing strictness flag (`--strict-fpc`'s umbrella is the natural
home — see [[project_strict_fpc_umbrella_and_lax_default]]), covering:

- a target-conditional directive on a target that has no use for it (`iram`);
- a directive that is inert everywhere (`register`, `cdecl` on a routine) —
  message should say *why* ("the calling convention is the target's"), not just
  that it was dropped;
- `inline` on a routine the inliner cannot take, with the reason it failed the
  shape test. This is the one with real user value: it turns a silent no-op into
  "your routine is too big to inline, and here is which rule it broke".

Deliberately NOT proposed: warning on the hint directives
(`deprecated`/`platform`/…). Those are meant to be inert until usage warnings
exist, and warning about them would fire on ordinary FPC source.

## Priority

Raised 30 -> 60 by the user, 2026-08-03: *"raise the prio on that ticket though..
feedback is informative"*. The point is general, not about this ticket alone —
a diagnostic that tells the user what the compiler actually did is worth more
than its size suggests, and should not be ranked as cosmetic just because it
changes no generated code.

## Gate

Each inert directive warns under the flag and stays silent without it; the
corpora and `lib/rtl` build with no new warnings in the default mode; self-host
fixedpoint byte-identical.


## Implemented 2026-08-05 — `--warn-ignored-directives`

Opt-in, diagnostic only, silent by default (these are all legal FPC source and
warning unconditionally would fire on every ordinary unit). Follows the
`--warn-uses-leak` pattern rather than going under `--strict-fpc`: this reports
what the compiler *did*, it does not change what it accepts, so it does not
belong in the FPC-parity umbrella.

    $ pascal26 -O2 --warn-ignored-directives dir1.pas d1
    dir1.pas:2: warning: directive 'cdecl' ignored here: the calling convention is
      the target's and is not selectable per routine, so P already uses it; the
      marker is documentation only
    dir1.pas:3: warning: directive 'register' ignored here: ...
    dir1.pas:4: warning: directive 'iram' ignored here: IRAM placement exists on
      the ESP targets (xtensa, riscv32) only; this target has no separate
      instruction RAM to place R in
    dir1.pas:5: warning: directive 'stackful' ignored here: it is the default
      strategy, so it selects nothing
    dir1.pas:6: warning: directive 'inline' ignored here: the inliner takes at most
      six by-value scalar parameters and Big has 7
    dir1.pas:7: warning: directive 'inline' ignored here: only a function with a
      scalar result is inlined, and NotFn is a procedure

Covers `cdecl`, `register`, `iram` off the ESP targets, `stackful`,
`reintroduce`, and `inline`. Each message says **why**, as the ticket asked —
"the calling convention is the target's", not "dropped".

Hint directives are excluded as specified.

### `inline`: only causes that are actually established

The ticket wanted "which rule it broke". The flag reports the four causes
knowable **at the declaration** — optimisation level below -O2, a procedure
rather than a function, assembler/generator/async/stackless, and more than six
parameters. It deliberately does **not** claim "your body is too complex": the
body has not been parsed at that point, and the eligibility gate is ~30 bare
`Exit`s in three retention functions with no reason recorded. Threading a
reason out of those is a real change to the inliner and is not worth risking
for a diagnostic; asserting an unestablished cause would be exactly the failure
this ticket exists to fix.

So a routine that fails only on body shape gets no warning today. The control
case in the test (`Ok`, one param, inlinable) correctly stays silent at -O2 and
correctly warns at -O0 with the optimisation-level reason.

### Verified

- default build: zero warnings;
- `-O0`: every `inline` warns with the level reason instead;
- pulling sysutils under the flag: zero warnings, so the RTL is clean;
- each warning fires once — suppressed during `PreScanPass`, which parses every
  header a second time and made them all double initially.

Test: `test/test_warn_ignored_directives.pas` — asserts silence without the
flag, exactly 6 warnings with it, and that the program still runs.
Docs are Track D's: [[task-d-document-warn-ignored-directives]].

Gate: `testmgr --tier limited` 1587/1587 GREEN + self-host fixedpoint.

**Resolved:** PENDING-COMMIT

## Log
- 2026-08-06 — resolved, commit PENDING-COMMIT.
