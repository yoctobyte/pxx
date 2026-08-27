---
prio: 70
track: B
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
