---
prio: 70
track: B
status: done
---

> **Track guessed as B from the FAILING STEP** — line 1 of 2, `stable_linux_amd64/default/pinned -Fulib/rtl/platform/posix test/lib_dns_spoof.pas /tmp/lib_dns_spoof`, which names `test/lib_dns_spoof.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/lib_dns_spoof.pas at 021cd94f10a9 in step 1/2, `stable_linux_amd64/default/pinned -Fulib/rtl/platform/posix test/lib_dns_spoof.pas /tmp/lib_dns_spoof` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T20:25:01Z
- **Test source:** test/lib_dns_spoof.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/lib_dns_spoof.pas`.
  ```
  stable_linux_amd64/default/pinned -Fulib/rtl/platform/posix test/lib_dns_spoof.pas /tmp/lib_dns_spoof
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_dns_spoof.pas'` at 021cd94f10a97c051c6c71d75d308028adc34c43

## Range
> **The named sha `021cd94f10a9` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `021cd94f10a9`, last good `1e37a55f6748`, **14 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
pascal26:40: error: undefined variable (PalVfork)
(tail)
pascal26:40: error: undefined variable (PalVfork)
  near: boundP ) ; pid := PalVfork >>> ; if pid 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## 2026-09-01 (frankH) — resolved: one deliberate PAL rename, filed once per file

`e2ba5a1e1` renamed the PAL entry `PalVfork` -> `PalFork` on purpose (the old
name was false and had already cost a real conclusion in `lib/crtl/src/unistd.c`,
which left `fork()` an ENOSYS stub by reasoning FROM the name, against a PAL
whose body issued `SYS_fork` all along). The rename is right; ten call sites in
`test/` were missed.

**Track T filed eight tickets, one per failing file. They are one bug.** Fixed
together in the commit subject `fix(B): eight DNS tests still called PalVfork,
a name e2ba5a1e1 deliberately retired` — `lib_dns_{resolve,facade,spoof,tcp,
multins,chase}.pas` plus `cache_facade` and `aaaa` with two sites each.

Pure rename, same signature; `PalVforkAndExec` deliberately untouched.

**Verified:** `make lib-test` EXIT=0 end to end against stable v399.

Worth recording that the two instruments agreed while failing differently: a
grep for the shape in the working tree found exactly the same eight files the
watcher found by running them on seven. That is corroboration; two greps would
not have been.

### For whoever tunes the auto-filer

Each of these tickets carries *"look at flakiness or box load, not at the named
sha"*. It is the only actionable line on them and it is **wrong** — nothing was
flaky. Dropping `compiler/` commits from a `$(PXX_STABLE)` job's bisect range is
sound, but the fallback then assumes the residue is environmental. `lib/` and
`test/` remain in range and are exactly where such a job's real regressions
live; the advice should name them before it says "flakiness".
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 876675b0f.
