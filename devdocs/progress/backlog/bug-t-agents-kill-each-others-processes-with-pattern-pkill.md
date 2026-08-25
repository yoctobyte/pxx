---
track: T
prio: 55
type: bug
blocked-by: []
summary: "Two csmith batches were killed mid-run from outside their own session. Pattern-pkill (pkill -f <name>) cannot distinguish two agents running the same tool, and this repo ALREADY hit and solved this class once in tools/gui_shot.sh — the rule was written into that one script and never generalised, while devdocs/dev/debugging-playbook.md still actively teaches `pkill -9 -f <path>`."
---

# Agents kill each other's processes, because a name pattern cannot tell two agents apart

- **Track T** (tooling + the `.claude/` guardrails), with a Track D-adjacent doc fix.
- **Raised** 2026-08-20 after Track C lost two csmith batches mid-run; owner asked directly
  for a way around it.

## The incident

Two `csmith_fuzz.py` batches died mid-run (seed 4, then seed 33 after a restart). Nothing in
the owning session issued a stop; no surviving csmith or qemu processes either time; ~8 GB
free; the kernel log is unreadable unprivileged so OOM can be neither confirmed nor excluded.
A 150-seed batch had completed normally minutes earlier, so it is not deterministic.

## THIS REPO ALREADY SOLVED THIS CLASS, IN EXACTLY ONE PLACE

`tools/gui_shot.sh:29-31`, in a comment, describing an identical prior incident:

> Display selection. By default we let Xvfb pick a FREE display (`-displayfd`) so two
> parallel agents never fight over a shared `:99` — **the old hardcoded default meant one
> agent's pkill/lock-rm killed the other's live Xvfb mid-capture.**

and at line 52, the rule it derived:

> **Kill only the Xvfb WE started (by PID) — never pattern-pkill a display number**

That is the correct rule, already learned the hard way, and it lives **in one script** rather
than anywhere a second agent would find it. Same failure as
[[feedback_measuring_a_thing_is_not_filing_it]]'s third face: the correction went where the
author was writing, not where a searcher would land.

## And the playbook actively teaches the dangerous pattern

Three live docs tell agents to do the thing:

| file | line | text |
| --- | --- | --- |
| `devdocs/dev/debugging-playbook.md` | 104 | ``no-op (ETXTBSY) while still printing `ok:`. `pkill -9` first, or use a fresh`` |
| `devdocs/dev/handoffs/nilpy-bughunt.md` | 115 | same |
| `devdocs/dev/handoffs/nilpy-songformatter.md` | 76 | ``` `pkill -9 -f <path>` first, or build ``` |

The handoffs are historical records and **must not be rewritten** (per CLAUDE.md's precedence
rule). `debugging-playbook.md` is a live reference doc, so under that same rule **it is the
bug** and should be fixed.

The ETXTBSY problem it addresses is real: writing over a running binary is a silent no-op that
still prints `ok:`. The advice is right about the problem and wrong about the instrument.

## Why a name pattern cannot work

`pkill -f csmith_fuzz.py` asks *"is there a process whose command line contains this text?"*
when the question is *"is there a process **I** started?"*. Those coincide exactly while one
agent runs the tool, and diverge silently the moment two do — **a true fact about the wrong
subject** ([[feedback_a_true_check_about_the_wrong_subject]]). It also matches the killer's own
waiter, which is the already-recorded `pgrep` variant of the same defect.

## Proposed fix, in three layers

**1. The positive pattern (docs).** Replace the playbook's advice with the rule `gui_shot.sh`
already derived:

- **Kill by PID**, captured when you started it (`$!`, or `setsid` + kill the process group).
- If a pattern is unavoidable, **scope it to something unique to this agent** — a per-run token
  on the command line (`--run-tag <agent>-<pid>`) or the agent's own workdir — never the tool
  or binary name.
- For ETXTBSY specifically, **the better answer is a fresh output path**, which the playbook
  already offers as the alternative. Lead with it; make the kill the fallback, not the default.

**2. The guardrail (`.claude/hooks/`).** The repo already has this mechanism —
`no-full-suite.sh`, wired as a `PreToolUse` matcher on `Bash` in `.claude/settings.json`. A
sibling hook can refuse `pkill -f` / `pkill` / `killall` with a bare name pattern, allow
`kill <pid>` and `pkill -f` with a scoping token, and print the positive pattern in the refusal
so the message teaches rather than just blocks — the same shape that made `no-full-suite.sh`
work. **This is a config change affecting every agent on the box: it needs the owner's
go-ahead, not a peer's.**

**3. Tool-side.** Long-running tools that both C and T touch (`csmith_fuzz.py`, the fuzz
drivers) should stamp a unique run tag into their own command line so that even a careless
pattern kill can be scoped. Cheap, and it makes layer 2's allowance usable.

## What is NOT yet established

**Pattern-pkill is the leading hypothesis, not a diagnosis.** Nobody has been observed doing
it, and plexus-T has been asked directly whether anything on its side sweeps process names. A
clean "nothing here sweeps" is the more valuable answer: it would mean something else on this
box kills long jobs, which outranks a fuzzing batch. **Do not close this on the strength of the
fix alone — the fix is worth doing either way, and it is not evidence about the cause.**

## Gate

T's own lane gate for tooling changes. The hook, if adopted, is testable the way
`no-full-suite.sh` is: assert refusal of the bad forms and acceptance of the scoped ones.
