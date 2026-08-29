---
prio: 70
track: B
status: done
owner: frankB
---

> **Track guessed as B** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 37 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/lib_synapse.pas red at ee62e6dc0582 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-29T18:57:15Z
- **Test source:** test/lib_synapse.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_synapse.pas'` at ee62e6dc0582f6a018102c4e1d1d9a083d7e4f32

## Range
bad `ee62e6dc0582`, and this is the job's **first-ever run** — there is no earlier passing sha, so no interval contains the cause and every commit a range could name is equally innocent. **No idle bisect will happen**; a red here is a finding about the job, not a regression from the commits around it.

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

---

## Resolved — already fixed when it was filed. Pin lag, not a regression.

**This ticket never described a live defect.** It is `lib_synapse` failing under
the *pinned* compiler for a bug that had been fixed in `master` ten minutes
earlier.

- The cause is [[bug-a-a-deep-unit-dependency-parses-with-a-spliced-token-stream]]
  — a uses-edge target written out of range over `PreScanPass`, so a deep
  transitive unit chain parses with a spliced token stream and the parser hits
  EOF still expecting `implementation`. That ticket names `test/lib_synapse.pas`
  as exactly what it makes red, and I filed it on 2026-08-28 off this job's
  predecessor, `regression-lib-test-lib-synapse`.
- frankA fixed it in **`614ec6017`** ("range-check the uses-edge target"), landed
  **18:47Z**.
- twatch auto-filed this ticket at **18:57Z** — *after* the fix was in master.
- The job builds with `$(PXX_STABLE)`, which was still **v390**, blessed before
  the fix. So the job stayed red against a compiler that no longer existed at
  HEAD.

### Measured, as a controlled comparison

One command, one corpus, one box; only the pinned binary differs:

| pin | `make lib-test` → `lib_synapse` |
| --- | --- |
| v390 | **RED** — `pascal26:270: error: expected implementation section` in `dns_cache.pas` |
| v391 | **GREEN** — and `lib_synapse_transitive_unit` and `lib_synapse_ssl` (`SYNAPSE-SSL OK`) with it |

The whole `lib-test` run at v391 is green, exit 0, with **no `SKIPPED:` clause**,
so all three synapse jobs actually ran rather than being skipped for a missing
corpus. Reduced form of the failure, for the record: `uses synacode, synautil,
blcksock, sysutils` under `--mimic-fpc` — **any pair passes, the four together
fail**, which is the "deep transitive chain" of the cause ticket.

### The boilerplate reasoned correctly and concluded wrongly

The auto-filed note at the top says:

> *This commit CANNOT be the cause. The job builds only with `$(PXX_STABLE)`,
> and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled
> it are unchanged. Look at flakiness or box load, not at the named sha.*

Every clause before the last is right, and the last one sends the reader to the
wrong place — which is the expensive kind of wrong, because *a named cause stops
the next reader looking*. "The bytes that compiled it are unchanged" rules out
**the named commit**; it does not rule out **the pinned binary**, and here the
pinned binary was the entire cause. The deduction has only two branches where it
needs three:

| the stable bytes are unchanged, therefore… | |
| --- | --- |
| …not this commit | correct |
| …flakiness or box load | the only alternative offered |
| **…the pin is stale relative to a fix that IS in master** | **missing, and it is this** |

That third branch is not exotic: it is the *expected* state of every
`$(PXX_STABLE)`-gated job between a compiler fix landing and the next pin. In
that window the watcher re-files the same finding every sweep, each against a
fresh innocent sha — this ticket is the `-2` of exactly that sequence, and a
`-3` was due on the next sweep had the pin not moved. Suggested boilerplate fix
filed for Track T as
[[chore-t-a-stable-gated-red-should-name-pin-lag-before-flakiness]].

Nothing to do in Track B: `lib/rtl` and the synapse corpus were correct
throughout, which is what the predecessor ticket concluded too.
- 2026-08-29 — resolved, commit PENDING-COMMIT.
