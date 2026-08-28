---
prio: 70
track: B
blocked-by: [bug-a-a-deep-unit-dependency-parses-with-a-spliced-token-stream]
status: blocked
owner: frankB
---

> **Track guessed as B** from the test source. The ranker reads frontmatter, so an unset track parks a stub in Track T's queue regardless of what the body says -- correct the `track:` line if this is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 13 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/lib_synapse.pas red at c52fc389fd97 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-27T23:45:49Z
- **Test source:** test/lib_synapse.pas

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_synapse.pas'` at c52fc389fd976e2333282adc22a2ca49c7ee000f

## Range
> **The named sha `c52fc389fd97` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `c52fc389fd97`, last good `aca7f699288e`, **9 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
pascal26:270: error: expected implementation section
(tail)
pascal26:270: error: expected implementation section
  in: stable_linux_amd64/default/../../lib/rtl/dns_cache.pas
  near: n  end  end  >>>  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-28 (frankB, Track B) — TRIAGED. Not a regression, not Track B, and the range is a false window.

Reproduced at HEAD, then falsified the range end to end. Three findings, in the
order they were measured.

**1. The pin is exonerated — the coordinator's hypothesis 1, killed in one
command.** v388 (`e8b72f8afeb6`) and v389 (`325b4479070a`) fail **identically**
on this job. No bisect needed and none run.

**2. Every commit in the range is innocent, including the "last good".** The
five observable commits are four of mine plus the pin. I rebuilt each state's
own `lib/` + `test/` into a scratch dir (`git archive`, no tree mutation) and
compiled the job against it — all five fail. So does `aca7f699288e` itself, the
declared **last good**, compiled with v388, the pin actually in force then.

**3. Not a Track B defect.** The library sources are correct: `dns_cache.pas`
and `sockets.pas` each compile standalone under `--mimic-fpc`, and so does every
unit in the chain individually. The failure needs a specific `uses` shape, and
the diagnostic's `near:` context shows the parser reading a **generated** token
(`procedure FlushGroup$126591`) that exists in no source file — two units' token
streams spliced. Reported line 270 of `dns_cache.pas` is **past EOF**; the file
is 269 lines.

Minimal repro, four lines, deterministic and `-O`-independent:

```pascal
program z;
uses synacode, synaip, blcksock;
begin
end.
```

All three *pairs* pass; only the triple fails, and only with `blcksock` last.
Moving it first or middle cures it, as does prepending `sysutils`.

Filed, not worked around, per the platonic-code rule:

- **`bug-a-a-deep-unit-dependency-parses-with-a-spliced-token-stream`** [A, p70]
  — the actual defect, with the full ordering table.
- **`bug-t-a-skipped-job-is-passlike-so-it-becomes-a-false-last-good`** [T, p60]
  — why this looked like a regression. `PASSLIKE = ("pass", "skip")`, and
  `external/synapse` is corpus-gated, so the job SKIPped at `aca7f69` and that
  sha became "last good". The tree landed on plexus before `c52fc38`, the job
  ran for the **first time**, and a first-ever run was reported as a regression
  over nine commits that could not have caused it.

This ticket is now **blocked on the Track A fix** and is a red-until-then, not a
Track B work item. `external/synapse` was fetched here (`tools/install_externals.sh`,
pinned `b3224c3d133a`) to reproduce; it is gitignored and nothing was committed
from it.
