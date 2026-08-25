---
slug: feature-p-assertions-switch-and-strict-default
title: "Implement {$ASSERTIONS} / {$C±} / -Sa; assertions stay ON by default, off under --mimic-fpc"
track: P
prio: 30
type: feature
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "Re-filed from decide-assertion-default-vs-fpc, decided 2026-08-25 (option 3, default ON). pxx evaluates Assert() always; FPC ignores it unless -Sa. The dialect contract requires every divergence to be switchable and disabled under the strict family, so the switch is mandated rather than merely preferred. Once it exists the default stops being a one-way door."
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
