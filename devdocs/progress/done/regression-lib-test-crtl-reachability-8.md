---
prio: 70
track: C
status: done
---

> **Track guessed as C from the FAILING STEP** — line 23 of 88, `python3 tools/gen_crtl_map.py --check`, which names `tools/gen_crtl_map.py`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 50 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 4 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:tools/crtl_reachability.py at cdae8cf6580b in step 23/88, `python3 tools/gen_crtl_map.py --check` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `065bb7eaf0d5`).
  Untriaged.
- **Found:** 2026-09-02T11:19:41Z
- **Test source:** tools/crtl_reachability.py tools/gen_crtl_map.py +48
- **Failing step:** line 23 of 88 of the job's recipe; it names `tools/gen_crtl_map.py`.
  ```
  python3 tools/gen_crtl_map.py --check
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:tools/crtl_reachability.py'` at cdae8cf6580bc5dd40f603391a4e98c5d8317c09

## Range
> **The named sha `cdae8cf6580b` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `cdae8cf6580b`, last good `2d6e7d5c26db`, **2 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
lib track pinned to: stable_linux_amd64/default/pinned -> stable_pinned   (newest checkpoint: latest -> stable_latest)
frozen builtin RTL: stable_linux_amd64/default/builtin/ (11 src) -- isolates track A's compiler/builtin/ edits
=== lib-test: library smoke against stable_linux_amd64/default/pinned ===
crtl-reachability: OK -- 78 headers, 46 modules, every declared function reachable from its own header
crtl-map: compiler/crtl_names.inc is STALE — run: python3 tools/gen_crtl_map.py

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## Log
- 2026-09-02 — the seven watcher saw `lib-test#src:tools/crtl_reachability.py` GREEN at 0da8a0ae4200 (tier full) and did NOT close this: this is a repeat stub (`regression-lib-test-crtl-reachability-8`, not `regression-lib-test-crtl-reachability`) — the job already went red, was closed, and came back, so one green is the outcome a live intermittent bug produces most of the time. The green is recorded because it is evidence and because a ticket that stops moving with no reason reads as forgotten; closing this one is a human's call.

## 2026-09-04, plexus — both steps GREEN at HEAD, and the failure mode is NOT intermittent

frankC. HEAD `162a22dd3`, the two structural steps of `lib-test` run verbatim:

```
crtl-reachability: OK -- 147 headers, 66 modules, every declared function reachable from its own header
crtl-map: OK -- 608 crtl functions mapped to 63 headers
```

The log tail on this stub names the second step —
`crtl-map: compiler/crtl_names.inc is STALE` — and that is a **deterministic
property of a tree, not a flake.** It says one thing only: somebody added a
crtl function and did not re-run `python3 tools/gen_crtl_map.py`. It goes green
again the moment anyone else does, which is why this job flaps and why the flap
reads like an intermittent when it is a queue of independent human omissions.

`compiler/crtl_names.inc` has been regenerated **six times** between the red sha
`cdae8cf6580b` and HEAD (`2f920dfd4`, `41a2d59a8`, `9f25e5fd3`, `87136719f`,
`be7294fc7`, `bd53b29d9` — every one of them a crtl-surface commit). So the
red was real, was caused by a commit below the named sha exactly as the
auto-file predicted, and was cleared as collateral by the next person to touch
crtl rather than by anyone reading this ticket.

**Not closed here.** The measurement retires *this instance*; it does not retire
the class, and closing on a green is what produced `-2` through `-8`. The class
is that `--check` is the ONLY guard and it lives in a tier that runs hours later
on another host, so the interval between "a crtl function is added" and "anyone
learns the map is stale" is a full-tier cycle. The cheap repair is a habit —
regenerate in the same commit that adds a crtl function — and the durable one is
a guard closer to the edit. Deliberately not widening any gate to get it; see
CLAUDE.md, and note that auto-regenerating from the Makefile is ruled out on
purpose (`gen_crtl_map.py`'s own docstring: the check exists so a forgotten
regeneration **fails** rather than silently succeeding).

## 2026-09-04 (frankC, Track C) — green at HEAD, and the loop is closed

Reproduced at HEAD `0afaf9e0a`, not under the pin:

```
$ python3 tools/gen_crtl_map.py --check
crtl-map: OK -- 608 crtl functions mapped to 63 headers        rc=0
$ python3 tools/crtl_reachability.py
crtl-reachability: OK -- 148 headers, 66 modules, every declared
function reachable from its own header                          rc=0
```

Both halves of the job's step 23 pass. `compiler/crtl_names.inc` was last
regenerated in `bd53b29d9`, a crtl feature commit — so the staleness was
cleared as a side effect of someone adding crtl surface, not by anyone holding
this ticket.

**THE NUMBER IN THE SLUG IS THE FINDING.** This is
`regression-lib-test-crtl-reachability-8`; `-2` through `-7` and the unsuffixed
original are all in `done/`. **The same generated file went stale and was
auto-filed eight times.** Seven were closed and the eighth is this one. Closing
it as "green now" without asking why there were eight would guarantee a ninth.

**Why there were eight: the check lived only where the per-fix loop does not
run.** `python3 tools/gen_crtl_map.py --check` appeared exactly once in the
tree, at `Makefile:26287`, inside the `lib-test` tier. `tools/gate.sh` never
mentioned it. Track T samples the tip every ~8 commits, which is the right
cadence for a breadth sweep and the wrong one for a generated file whose
regenerator is a single command — so every crtl addition that forgot the
regenerate step got caught a sweep later, by a watcher, as a fresh ticket with a
fresh range, in a lane guessed from the failing step.

**Fixed by wiring the cheap half into `gate.sh quick`.** Measured: 0.44s, and
it builds nothing. Its sibling `crtl_reachability.py` is deliberately NOT wired
— 9.5s is a fifth of the whole gate, and it answers a different question. The
arm follows the two that were already there for exactly this shape (`IROpName
names every IR op`, `AST slot-write census matches its snapshot`), including
their FAIL-if-the-checker-is-missing branch, because an arm that skips on a
tracked file passes green for a tree with no checker in it.

**Positive control, and the first attempt at it was wrong in the instructive
way.** The map is built from names that crtl both DECLARES in a header and
DEFINES in `lib/crtl/src` — declared-but-undefined names are excluded on
purpose. So a control that only appended a declaration to `ctype.h` left the
map correctly unchanged and the check correctly green: a guard aimed at a
population the defect does not live in. With both halves added:

```
crtl-map: compiler/crtl_names.inc is STALE — run: python3 tools/gen_crtl_map.py
rc=1
```

which is the exact message in this ticket's own Log tail. Header, source and
`crtl_names.inc` all restored afterwards and each revert verified by `cmp`
against a pre-control copy.

**What this does not fix.** The auto-file cadence itself: a ninth instance can
still be filed by the watcher if the map goes stale on a host that is not
running this gate. The gate arm makes it far less likely to reach a sweep, not
impossible.
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit b992d2073.
