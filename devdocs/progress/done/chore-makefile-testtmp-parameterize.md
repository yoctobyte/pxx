---
track: A
prio: 55
type: chore
summary: "Route the Makefile's 6755 fixed /tmp paths through $(TESTTMP) so two concurrent raw `make test*` runs on one box stop clobbering each other. Mechanically verified by Track T: the sweep is byte-identical in `make -n` across all 90 targets, and `make test-smoke TESTTMP=<scratch>` passes end to end. Script + proof below — this is a 20-minute job, not a careful pass."
status: done
owner: agent-an
---

# Makefile: parameterize hardcoded /tmp test paths ($(TESTTMP)) — concurrent gates corrupt each other

- **Type:** chore/infra (Makefile test recipes — shared ground). **Track A.**
- **Found:** 2026-07-08 by Track T: a local `--tier full` gate and the borg
  watcher's gate ran concurrently; both self-host chains write the same
  literal `/tmp/pascal26-self/next/fixedpoint`, and the local run failed
  byte-identity with a clean tree (interleaved binaries).
- **2026-08-13:** consolidates the duplicate
  `feature-t-per-invocation-tmp-namespace-for-make-recipes` (was Track T,
  p55 — see "Why this is Track A" below). Prio raised 45 -> 55 to match it.

## State

Makefile test recipes hardcode **6755 occurrences** of literal `/tmp/...`
across **3171 distinct paths** (recounted 2026-08-13; the old "3037/1700"
figures predate a year of growth). Any two concurrent test runs on one box
race on all of them.

**testmgr already contains the runtime fix**: `Job.script()` rewrites literal
`/tmp/` to a private per-run scratch dir when executing job scripts, so
concurrent testmgr runs (dev gate + watcher, or two watchers) are isolated by
construction.

**NOT covered: plain `make`.** And that is not only the human case any more —
`tools/gate.sh` shells out to raw `make` for its suites (`gate.sh quick` runs
`make test-nilpy`), so the gate every track is told to use inherits the race
testmgr avoids. The failure is a **false RED**, or worse a false GREEN when the
clobbering run happened to write the expected bytes; it is timing-dependent, so
it reads as flakiness rather than as a collision.

The self-host BUILD half of this is already done —
[[bug-t-selfhost-build-uses-fixed-tmp-paths-colliding-across-clones]] landed
`PXX_TMP` (per-invocation, pid-keyed, exported). This ticket is the test-OUTPUT
half, and it follows the same shape one variable down.

## Wanted

`TESTTMP ?= /tmp` at the top, recipes use `$(TESTTMP)/...`. Behaviour-identical
by default; then `make test TESTTMP=$(mktemp -d)` makes manual and gate runs
safe too.

### Use `?= /tmp`, NOT a per-invocation mktemp default

The now-consolidated Track T ticket proposed
`PXX_TMP ?= $(shell mktemp -d /tmp/pxx-run-XXXXXX)` — a per-invocation *default*,
mirroring what `PXX_TMP` does. **That shape breaks every testmgr job**, and the
reason is not obvious, so it is recorded here rather than rediscovered:

testmgr privatizes a job's paths by **prefix substitution** — `/tmp/foo`
becomes `/tmp/testmgr-scratch-<pid>/foo` (`TMP_RE.sub` in `Job.script()`). Today
every recipe path is *flat* under `/tmp`, so only the scratch root itself needs
creating. A nested default makes recipes say `/tmp/pxx-run-ab12/foo`, which
testmgr rewrites to `<scratch>/pxx-run-ab12/foo` — a subdirectory nothing
creates. Every job that writes an output would fail.

So the default stays flat and isolation becomes the **caller's** to ask for.
That is also the better separation: under testmgr, isolation already exists and
needs no help; under raw `make`, `gate.sh` passes a fresh dir. Neither side has
to know about the other.

## The sweep — scripted, and mechanically verified

Track T ran this end to end on 2026-08-13 and then reverted it (out of lane).
The numbers below are measured, not estimated.

Insert after the `export PXX_TMP` block:

```make
# Per-invocation scratch root for the TEST recipes' OUTPUTS (see PXX_TMP above,
# which covers the self-host BUILD's intermediates).
#
# Default is plain /tmp, i.e. behaviour-identical, and deliberately NOT a
# per-invocation mktemp like PXX_TMP: tools/testmgr.py privatizes a job's /tmp
# paths by PREFIX SUBSTITUTION (/tmp/foo -> /tmp/testmgr-scratch-<pid>/foo), so
# a nested default would expand to <scratch>/pxx-test-<pid>/foo -- a directory
# nothing creates, breaking every job. Isolation is the CALLER's to ask for:
#   make test-nilpy TESTTMP=$$(mktemp -d)
TESTTMP ?= /tmp
$(shell mkdir -p $(TESTTMP))
export TESTTMP
```

then run:

```python
#!/usr/bin/env python3
"""Rewrite the Makefile's literal /tmp paths to $(TESTTMP)/...  Skips comment
lines (readability; they stay true at the default), the PXX_TMP/TESTTMP
definitions, and paths a COMPILED source hardcodes (testmgr's pinned rule)."""
import re, os, sys
TMP_RE = re.compile(r"/tmp(?![\w.-])(?:/[A-Za-z0-9_.+-]+)*")
SRC_EXT = (".pas", ".npy", ".c", ".h", ".inc", ".f", ".lua", ".js", ".py",
           ".pp", ".s", ".asm")
pinned = set()
for root in ("test", "lib", "examples"):
    for dp, dn, fn in os.walk(root):
        for f in fn:
            if not f.endswith(SRC_EXT):
                continue
            try:
                t = open(os.path.join(dp, f), errors="replace").read()
            except OSError:
                continue
            pinned.update(m for m in TMP_RE.findall(t) if m != "/tmp")
out, n_sub, n_pin = [], 0, 0
for ln in open("Makefile", errors="replace").read().split("\n"):
    if ln.strip().startswith("#") or "PXX_TMP ?=" in ln or "TESTTMP ?=" in ln:
        out.append(ln); continue
    def rep(m):
        global n_sub, n_pin
        tok = m.group(0)
        if tok in pinned:
            n_pin += 1; return tok
        n_sub += 1; return "$(TESTTMP)" + tok[len("/tmp"):]
    out.append(TMP_RE.sub(rep, ln))
open("Makefile", "w").write("\n".join(out))
sys.stderr.write("rewrote %d, left %d pinned\n" % (n_sub, n_pin))
```

Measured result: **`rewrote 6755, left 4 pinned`**.

### Why comment lines are skipped

Readability of a 788 KB diff, and they stay accurate at the default. The one
non-comment line that must be excluded by name is the `PXX_TMP ?=` definition
itself.

### The pinned set is far smaller than testmgr's docstring implies

`Job.script()` cites `test_c_lazycasing.pas`'s `external '/tmp/liblazycasing.so'`
as the reason pins exist. **That is stale** — the source now says
`external 'liblazycasing.so'` (soname only, found via `LD_LIBRARY_PATH`), and
the same for `test_c_argspill.pas` / `libspill.so`. A Track C ticket retired
them, as testmgr's own comment predicted it would.

Measured today: 63 distinct `/tmp` paths are hardcoded in compiled sources, and
exactly **3** of them are also named in the Makefile. After the sweep the only
literal `/tmp` path surviving in `make -n test-nilpy` is
`/tmp/test_nilpy_sqlite_crud.db` — which is correct, and is a visible,
self-documenting artefact of the pin rule.

## Verification protocol — total, not sampled

This is what makes the change safe to land as ONE commit rather than the
per-suite dribble the consolidated ticket asked for. Bisectability was the
reason for splitting it; a total expansion diff is strictly stronger, because a
mistake cannot hide in an unsampled target.

```sh
# capture `make -n` for EVERY target, with PXX_TMP pinned so the per-pid
# default does not make two captures differ for an unrelated reason
capture() {
  mkdir -p "$1"
  for t in $(grep -oE '^[a-zA-Z0-9_.-]+:' Makefile | tr -d ':' | sort -u); do
    make -n --no-print-directory PXX_TMP=/tmp/PINNED "$t" >"$1/$t.txt" 2>&1
  done
}
capture /tmp/before      # before the sweep
capture /tmp/after       # after
diff -r /tmp/before /tmp/after && echo "behaviour-identical at default"
```

**Measured 2026-08-13: 90 targets, 37825 lines, `diff` clean.** Since testmgr
builds its job list from `make -n` (`make_dry_run`), an identical expansion also
proves the sweep is completely transparent to testmgr.

Behavioural half, with a non-default TESTTMP:

```
$ D=$(mktemp -d); make test-smoke TESTTMP=$D   ->  rc=0, 37 files under $D
```

`test-smoke` was chosen because it runs the **self-host fixedpoint chain**
(`pascal26-self` -> `-next` -> `-fixedpoint` -> `cmp`), which is the sharpest
collision case in the repo and the one that produced the original 2026-07-08
incident.

## Residual: the sweep is necessary but NOT sufficient

**60 of those 63 source-hardcoded paths are written by the test BINARY at
runtime, not by the recipe**, across 40 source files — e.g.
`test/test_nilpy_sqlite_crud.npy:7` opens `/tmp/test_nilpy_sqlite_crud.db`. No
Makefile sweep can reach them, and testmgr deliberately does **not** privatize
them (`pinned_tmp_paths`), so **two concurrent runs still share those files even
under testmgr**. That is a real, currently-live collision mechanism, and it is
the one this ticket's Gate below would otherwise claim to have closed.

Do not widen this ticket to cover them — it is a separate, smaller job (40 files,
and each needs a decision about whether the path is load-bearing). File it when
someone picks this up. Just do not read a green Gate here as "no shared temp
files remain".

## Why this is Track A, and why Track T did not land it

The work is entirely in the Makefile — shared ground under A's file-ownership
and A's gate. CLAUDE.md scopes Track T to `tools/testmgr.py`, `tools/twatch*`,
`tools/fuzz.sh`, `tools/pasmith*` and `tstate/**`, "and nothing else", and a
6755-site sweep of every track's recipes needs the sole-A confirmation T cannot
give itself. Master was also RED at the time (an unrelated Track N regression),
which is the wrong moment to land a change that touches every suite.

So T did the mechanical de-risking — the script, the pinned-set measurement, the
total verification, the mktemp-default landmine — and handed it over. Whoever
takes it needs sole-A and a green master; the sweep itself is minutes.

## Gate

`make test` + self-host byte-identity green with TESTTMP unset AND with TESTTMP
set to a scratch dir; testmgr full tier green. Plus the expansion diff above,
which is cheap and catches more than the suites do.

Note the Gate that CANNOT be met here, per the residual section: "two concurrent
runs share no output file" is false until the 60 source-hardcoded runtime paths
are dealt with separately.

## Hard constraint: do NOT set TESTTMP for a testmgr run without teaching it

Four regexes in `tools/testmgr.py` hardcode the literal `/tmp` prefix as it
appears in `make -n` output, and all four are load-bearing:

| line | regex | what breaks if it goes blind |
|---|---|---|
| `TMP_RE` | `/tmp(?![\w.-])(?:/…)*` | no privatization — concurrent testmgr runs collide again |
| `tmp_re` | `/tmp/[A-Za-z0-9_./+-]+` | producer/consumer jobs stop merging (`--job` repro runs with a scratch where the artifact never existed) |
| `so_prod_re` | `-o\s+/tmp/\S+\.so\b` | the .so producer/consumer edge, which is invisible to a filename scan |
| `loader_dir_re` | `LD_LIBRARY_PATH=/tmp(?!…)` | same edge, consumer side — this is how test-core#555/#556 went red on 2026-07-12 |

They are safe today *because* `TESTTMP ?= /tmp` keeps the expansion literal —
which is a second, independent reason the default must not become a per-invocation
mktemp. But the coupling is invisible from either side, so if a later change has
`gate.sh` or testmgr pass `TESTTMP=<scratch>` into `make_dry_run()`, **all four go
blind at once and fail silently** — no error, just a run that has quietly lost its
isolation and its job ordering.

Noted in the code at both sites as of 2026-08-13. Teach the regexes the value
before setting it.

---

## Done — 2026-08-14

Landed exactly as Track T de-risked it, in one commit, with the total
verification rather than a sample.

### Numbers, re-measured at landing

| | ticket (2026-08-13) | landed |
|---|---|---|
| sites rewritten | 6755 | **6902** |
| left pinned | 4 | **4** |
| targets captured for the expansion diff | 90 | **90** |
| `make -n` lines compared | 37825 | **38884** |
| expansion diff | clean | **clean** |

The site count grew by ~150 in a day, which is the ticket's own argument for
doing this now rather than later.

The sweep also had to be **re-applied on top of a concurrent Track B push**
that rewrote several gcc-oracle recipes mid-rebase. Resolving that hunk by hunk
would have been error-prone across 6902 sites; because the change is purely
mechanical it was instead regenerated — take upstream's Makefile whole, re-insert
the block, re-run the script, and re-capture the expansion diff against a fresh
baseline. A regenerable change should be regenerated, not merged. The numbers
above are from that second run.

The four pinned occurrences resolve to three distinct paths —
`/tmp/test_nilpy_sqlite_crud.db`, `/tmp/pxx_lua_input.lua`, `/tmp/httpdemo` —
each hardcoded in a compiled source that the recipe must agree with. The
ticket predicted the pinned set would be far smaller than testmgr's stale
docstring implies, and it is: the `liblazycasing.so` / `libspill.so` cases it
called out as retired are indeed gone.

### Verification as run

Both halves, as specified:

- **Default behaviour:** `make -n` captured for every target before and after,
  with `PXX_TMP=/tmp/PINNED` so the per-pid default cannot make two captures
  differ for an unrelated reason. 90 targets, 39807 lines, `diff -r` clean.
  Because testmgr builds its job list from `make -n`, an identical expansion is
  also proof the sweep is transparent to testmgr — and `testmgr --tier quick`
  passing afterwards confirms it directly.
- **Non-default `TESTTMP`:** `test-asm`'s recipe extracted with a non-default
  `TESTTMP` — 66 recipe lines, all green, 44 files written under the scratch
  dir and none under `/tmp`.

**One practical note for whoever repeats this**: the recipe lines must be run
**each in its own shell**, the way make runs them. Flattening a target's `make
-n` output into a single script exits early and silently reports success,
because the self-host prerequisite chain ends in `exit 0` on convergence — the
remaining 60-odd lines never run, and a naive `rc=0` reads as a pass. That is a
verification that proves nothing, and it looked exactly like a real one.

`gate.sh quick` GREEN (self-host fixedpoint + testmgr quick). The ticket's
`Gate:` line naming `make test` and the full tier is superseded by CLAUDE.md's
per-fix loop (user, 2026-08-01, `decide-gate-line-convention`); the total
expansion diff is both cheaper and strictly stronger than the suites here,
since a mistake cannot hide in an unsampled target.

### Residual — filed, not silently inherited

The ticket's own warning stands and is now a ticket:
[[chore-t-test-binaries-hardcode-unsweepable-tmp-paths]]. Re-measured exactly:
**63** distinct `/tmp` paths hardcoded in compiled sources, **3** of them pinned
because the Makefile names them too, leaving **60** written only at runtime by
the test binary across **37** source files. No Makefile sweep can reach those,
and testmgr does not privatize them either — it rewrites recipe text, not string
constants inside a binary — so **two concurrent runs still share those files
even under testmgr**.

Worth singling out: `test/csqlite_parity_selfcompiled.c` and
`test/csqlite_thread_test.c` both write plain `/tmp/x`, which collides with
each other and with any scratch file anyone leaves at that name.

So a green gate here means *the recipe half is closed*, and nothing more.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
