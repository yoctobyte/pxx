---
slug: feature-p-assertions-switch-and-strict-default
title: "Implement {$ASSERTIONS} / {$C±} / -Sa; assertions stay ON by default, off under --mimic-fpc"
track: P
prio: 30
type: feature
blocked-by: []
status: done
owner: frankH
created: 2026-08-25
summary: "DONE. {$ASSERTIONS}/{$C±}/-Sa and the default-ON policy were already built by feature-p-assertions-directive-and-position; the one gap was that --mimic-fpc never implied assertions-off, so a program whose only divergence from an FPC build was a failing Assert exited 1 where fpc exits 0. Added to both mimic arms (not to EnableStrictFpc — a runtime-polarity default is not compile-time parity). Writing the acceptance test found a second, larger defect and fixed it: a root-level `uses` re-snapshotted the per-file DIRECTIVE baseline, and since the main file is lexed in full first, a directive written after the final `end.` decided every used unit's polarity — assertions here, record layout with {$PACKRECORDS}. Item 4 (a pxx.skip dialect-pass row) is MOOT: the only two corpus files using Assert set {$ASSERTIONS ON} in their own source."
---

# What to build

- `{$ASSERTIONS ON/OFF}` and its short spelling `{$C+}` / `{$C-}`, with
  **per-unit** granularity — that granularity is what makes the switch worth
  more than a default flip.
- A `-Sa` command-line flag matching FPC's.
- **Default: ON.** An assertion that silently evaporates is a check the author
  believed they had, and code written *for* pxx is the population a silent
  default-off would harm.
- `--mimic-fpc` implies assertions-off, so a corpus build gets FPC's polarity
  without naming this flag.
- A `pxx.skip` `dialect-pass` entry so the conformance sweep runs with FPC's
  polarity.

# Why this shape is mandated, not chosen

`meta-dialect-extensions-and-fpc-strict`, the contract every extension follows:
*"1. Be available by default (lenient) or behind an explicit opt-in switch —
never silently mandatory. 2. Be disabled / rejected under the strict family ...
so a strict compile is FPC-faithful."*

Assertions-on is a divergence in pxx's favour, so clause 1 permits it as the
default and clause 2 requires the off switch. Options "just keep ours" and "just
match FPC" each drop one clause.

# Acceptance (contract clause 4 — a test on both sides)

- `Assert(1 = 2, 'm')` raises `EAssertionFailed` in the default dialect, and the
  class, catchability and message stay as they are today (all three already
  match FPC and none of them changes).
- The same source is a no-op under `-Sa`-off / `{$C-}` / `--mimic-fpc`, and the
  output is then bit-identical to `fpc -Mobjfpc` with no flags.
- `{$C-}` in one unit does not disarm assertions in another.

---

## Measured against the compiler as it stood, 2026-09-09 (frankH)

Three of the four items were **already built**, by
`feature-p-assertions-directive-and-position`:

| item | where | state |
| --- | --- | --- |
| `{$ASSERTIONS ON/OFF}` + `{$C±}` | `paslexer.inc:2456`, `:2602` | built |
| `-Sa` | `compiler.pas:1465` — a deliberate no-op, ON is already our default | built |
| default ON | `AssertionsVal`, `defs.inc:5963` | built |
| per-unit granularity | `PasResetDirectivesToBaseline` | built, and **wrong about its baseline** — see below |
| `--mimic-fpc` implies assertions-off | nowhere | **the gap** |

`{$C±}` polarity is byte-identical to `fpc -Sa` at every position, measured on a
five-row probe with the directives at the `Assert`'s own lexical position:

```
--- pxx default ---   1 default on / 2 C-minus off / 3 C-plus on / 4 long-off off / 5 long-on on
--- fpc -Sa ---       1 default on / 2 C-minus off / 3 C-plus on / 4 long-off off / 5 long-on on
```

### The gap, and why it goes in the mimic arms

`--mimic-fpc` set `EnableStrictFpc` and `IChecksVal := True` and never touched
the assertion polarity, so a program whose only divergence from an FPC build was
a failing `Assert` exited 1 under `--mimic-fpc` where `fpc -Mobjfpc` exits 0 —
the acceptance line "bit-identical to `fpc -Mobjfpc` with no flags", failing.

Assertions-off went into the two mimic arms and **not** into `EnableStrictFpc`,
on the `{$I+}` precedent one line above it: `EnableStrictFpc` carries only
COMPILE-TIME parity (case, operator, visibility, require-forward), and a
RUNTIME-polarity default belongs to "claim to BE FPC". `--strict-fpc` on its own
must not silently delete a user's assertions.

### What the acceptance test then found, which is bigger than this ticket

Writing the four-polarity test surfaced a second defect in the same feature, and
it is the one worth reading. A used unit is reset to a **directive baseline**;
a root-level `uses` used to RE-SNAPSHOT that baseline instead of resetting to
it (`pasparser_proc.inc`, the `savedCurrentUnitIdx < 0` fork, deliberately
mirrored from the defines fork beside it). But **the main file is lexed in full
before the parser reaches its `uses`**, so what got folded in was not the state
at the `uses` — it was the state at END OF FILE. Measured both directions
against fpc:

| main program's trailing directive | flags | fpc | pxx (before) |
| --- | --- | --- | --- |
| `{$ASSERTIONS ON}` **after the final `end.`** | pxx `--no-assertions` / fpc none | off | **on** |
| `{$C-}` **after the final `end.`** | pxx default / `fpc -Sa` | on | **off** |

Text past `end.` that fpc never compiles at all was deciding a used unit's
runtime behaviour. Assertions are the cheapest of the eleven values in that
table: the same line written `{$PACKRECORDS 1}` is a **record layout** in a unit
that never asked. The fork's own justification — *"the root is one source, its
directives are lexically ordered, and nothing about it is order-dependent"* — is
true of defines and false of directives, for exactly that lexing reason.

Fixed by always resetting the directive baseline. The **defines** fork is
untouched: it is load-bearing (`{$undef PXX_MANAGED_STRING}` on line 1 selects
the frozen-string model for `compiler/builtin/*.pas`) and has its own positive
control, `test_frozen_string_reentrant.pas`, which stays green.

**Why the existing test could not have caught it:**
`test_a_used_unit_keeps_its_own_assertion_default.pas` expects the child to read
`on`, and `on` is BOTH the correct reset value and the never-touched value —
the expected value collides with the failure value, so the row cannot fail on
this. The new rows expect `off` for the same unit under a flag, which only a
live reset can produce.

### Item 4 (`pxx.skip` `dialect-pass` entry) — MOOT, recorded rather than satisfied

`tools/run_pascal_conformance.sh` passes only `--strict-case --strict-operator`,
never `--mimic-fpc`, so the sweep keeps pxx's assertions-ON polarity. Censused
the corpus: of 1988 `tests/test/*.pp`, **two** use `assert(` —
`tinterface4.pp` and `tprec23.pp` — and **both open with `{$ASSERTIONS ON}` in
their own source**, which outranks every command line under both compilers.
(`tinterface4.pp` is skip-listed anyway, on `AfterConstruction`.) So the sweep's
polarity is unobservable to every row in the corpus, and a skip entry would
assert something no row can test. Item dropped as moot, not satisfied.

### Verification

- `tools/gate.sh quick` GREEN with `compiler/**` uncommitted, so the FPC seed
  canary ran (`PASS  FPC seed canary (concurrent)`).
- self-host fixedpoint `converged after 1 round(s)`, `7affb8b14faf`.
- five-row probe: pxx default == `fpc -Mobjfpc -Sa`, pxx `--mimic-fpc` ==
  `fpc -Mobjfpc` with no flags, byte for byte, both re-measured in clean
  directories (fpc reuses a `.ppu` built under a different `-Sa`, and a stale
  one answered for the wrong command line once here).
