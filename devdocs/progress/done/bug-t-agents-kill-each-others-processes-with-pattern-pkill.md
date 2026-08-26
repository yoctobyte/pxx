---
track: T
prio: 55
type: bug
blocked-by: []
summary: "Two csmith batches were killed mid-run from outside their own session. Pattern-pkill (pkill -f <name>) cannot distinguish two agents running the same tool, and this repo ALREADY hit and solved this class once in tools/gui_shot.sh — the rule was written into that one script and never generalised, while devdocs/dev/debugging-playbook.md still actively teaches `pkill -9 -f <path>`."
status: done
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

---

## RESOLUTION 2026-08-26 — OOM is EXCLUDED, and Track T sweeps nothing

The ticket said the fix is worth doing either way but is not evidence about the
cause, and asked for the cause separately. Both were done. **The cause answer is
the more valuable half and it inverts the direction the hypothesis was moving.**

### 1. The sentence that cost six days was wrong

> the kernel log is unreadable unprivileged so OOM can be neither confirmed nor
> excluded

`dmesg` is blocked here (`kernel.dmesg_restrict=1`) — but **`journalctl -k` is
not**, for anyone in group `adm` or `systemd-journal`, and this account is in
`adm`. Everyone who hit the wall hit it with `dmesg` and stopped. 13,201 kernel
lines are readable for the current boot, and the journal reaches back to
2026-08-07, so the 2026-08-20 incident is fully covered.

**Kernel OOM killer: 0 hits across all three boots** (`-b0` 13,201 lines, `-b-1`
14,036, `-b-2` 8,249; pattern `oom-kill|Killed process|Out of memory|oom_reaper|
Memory cgroup out of memory`).

### 2. And the check a kernel-only answer would have got wrong

`systemd-oomd` is **active and enabled** on this box. It kills on cgroup PSI
*before* the kernel is out of memory, logs to its own unit and **not** to the
kernel log, and it targets the heaviest cgroup — which here is precisely a
fuzzing batch or a test matrix. A "no kernel OOM" all-clear would have been
confidently wrong.

**systemd-oomd: 0 kills, ever, on either boot.** Its journal contains three
lines, all startup.

So **both** OOM mechanisms are excluded for 2026-08-20, and the roster's move of
the kill hypothesis toward OOM (`5c170b4e3`) should be reversed.

### 3. Track T sweeps no process names — audited, not asserted

There is **no `pkill` or `killall` anywhere** in `tools/`, `.claude/`, the
Makefile, or the watcher's clone. Everything Track T kills is killed on
identity, not on a name:

- `twatch.kill_child()` — group-kills a child it started with
  `start_new_session`, SIGINT then SIGKILL.
- `testmgr.kill_run()` — a pid from *that clone's own* lockfile, with explicit
  refusals for self and parent, and group-kill only when the target leads its
  own group.
- `testmgr --kill-orphans` — discovers box-wide by scanning `/proc` (it must:
  scoped runs are adopted by systemd and invisible to `pstree`), but **decides**
  on a stale heartbeat in the target's own repo lock plus a 30-minute age floor,
  behind an opt-in flag, and prints `keep` with a reason for every live run.
- The only pattern anywhere is `pgrep -fc 'testmgr\.py|twatch\.py'` in
  `gate.sh:35` — a read-only count for an advisory "the box is busy" note.

The ticket wanted a clean "nothing here sweeps" and this is it. Combined with
§1–2 that is a real narrowing, and **the asymmetry is the point: kernel OOM and
oomd both leave a durable record, a peer's SIGKILL leaves none.** Excluding the
hypotheses that would have left evidence leaves the one that never does. That is
as far as this evidence reaches — it is not proof of a pattern kill, and CLEAR
must not be read as "it exited on its own".

### 4. What landed

- **Layer 1 (docs) — done.** `devdocs/dev/debugging-playbook.md` now leads with
  the fresh-output-path fix for ETXTBSY (it needs no signal at all), makes the
  kill a scoped fallback, states why a name pattern answers the wrong question,
  and cross-references `gui_shot.sh:52` so the rule is findable from where a
  searcher lands rather than only where its author was writing. The two handoff
  files keep the old advice — they are historical records, per CLAUDE.md.
- **Layer 3 (run tags) — done.** `csmith_fuzz.py` re-execs once with
  `--run-tag csmithrun-<pid>-<epoch>`, so the token is in `/proc/<pid>/cmdline`
  and a pattern kill *can* be scoped; the banner prints the exact `kill <pid>`
  and scoped-`pkill` commands and names the dangerous one. Verified live:
  `pgrep -f <tag>` matches 1 process, `pgrep -f csmith_fuzz.py` matches 3.
- **The diagnostic — new, and the reason this cannot recur.** `tools/whokilled.sh`
  answers "what killed a job in this window" in one command. Its design rule is
  the repo's recurring defect stated directly: **"no evidence of X" and "could
  not look for X" must never print the same.** Three verdicts — CLEAR / FOUND /
  CANNOT-TELL — and any blind probe forces exit 2, so a caller cannot mistake
  blindness for an all-clear. It checks completeness explicitly, because
  `journalctl -k` shows an unprivileged user an *empty* log rather than an error,
  which is exactly how the original wall was hit.
  `tools/whokilled_devtest.py` drives all three verdicts on all three probes
  (14 cases) with fakes on PATH — on this box every real probe returns CLEAR, so
  the CANNOT-TELL branches had run zero times, and a canary that has never been
  seen to fail is not yet a canary.
- **Layer 2 (the PreToolUse hook) — NOT landed, escalated.** It is a `.claude/`
  config change affecting every agent on the box; the ticket itself says it needs
  the owner's go-ahead and not a peer's. Filed as
  [[decide-t-refuse-unscoped-pattern-kills-in-a-hook]].

### Still open

Only layer 2, on the owner's decision. The cause is narrowed as far as the
surviving evidence allows and `whokilled.sh` makes the next occurrence answerable
in one command instead of six days.

## Log
- 2026-08-26 — resolved, commit 7f2646d43.
