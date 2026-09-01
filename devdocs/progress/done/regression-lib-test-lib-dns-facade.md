---
prio: 70
track: B
status: done
---

> **Track guessed as B from the FAILING STEP** — line 1 of 2, `stable_linux_amd64/default/pinned -Fulib/rtl/platform/posix test/lib_dns_facade.pas /tmp/lib_dns_facade`, which names `test/lib_dns_facade.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 2 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 12 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:test/lib_dns_facade.pas at 021cd94f10a9 in step 1/2, `stable_linux_amd64/default/pinned -Fulib/rtl/platform/posix test/lib_dns_facade.pas /tmp/lib_dns_facade` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `5ea286a98481`).
  Untriaged.
- **Found:** 2026-09-01T20:25:01Z
- **Test source:** test/lib_dns_facade.pas tools/expect_same.sh
- **Failing step:** line 1 of 2 of the job's recipe; it names `test/lib_dns_facade.pas`.
  ```
  stable_linux_amd64/default/pinned -Fulib/rtl/platform/posix test/lib_dns_facade.pas /tmp/lib_dns_facade
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:test/lib_dns_facade.pas'` at 021cd94f10a97c051c6c71d75d308028adc34c43

## Range
> **The named sha `021cd94f10a9` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `021cd94f10a9`, last good `1e37a55f6748`, **14 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
pascal26:47: error: undefined variable (PalVfork)
(tail)
pascal26:47: error: undefined variable (PalVfork)
  near: boundP ) ; pid := PalVfork >>> ; if pid 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## 2026-09-01 (frankH) — resolved: a deliberate PAL rename, in EIGHT files not one

`e2ba5a1e1` renamed the PAL entry `PalVfork` -> `PalFork` on purpose: the old
name was false, and it had already cost a real conclusion — `lib/crtl/src/unistd.c`
reasoned FROM the name that the PAL had no `fork()`, and left `fork()` an ENOSYS
stub, against a PAL whose body had issued `SYS_fork` all along (busybox ash then
failed with `can't fork`). The rename is right; the test callers were missed.

**The ticket named one file. Grepping the shape first found eight**, ten call
sites: `lib_dns_{resolve,facade,spoof,tcp,multins,chase}.pas` plus
`lib_dns_cache_facade.pas` and `lib_dns_aaaa.pas` with two each. Fixing only the
filed file would have moved the red one row down and looked like a second bug.

Pure rename, same signature (`function PalFork: Integer`). `PalVforkAndExec` is
deliberately untouched — it keeps its name per `platform_backend.pas:1408` — and
`\bPalVfork\b` does not match inside it.

**Verified:** `make lib-test` EXIT=0 end to end against stable v399, with
`synapse-ssl` and `reportlab-diff` declared SKIPPED by the summary line itself.

### For whoever tunes the auto-filer: both banners were correct and both pointed away

- *"This commit CANNOT be the cause"* — true, `021cd94f10a9` moved no
  `stable_linux_amd64/**`.
- *"Look at flakiness or box load, not at the named sha"* — **false, and it was
  the only actionable sentence on the ticket.** Nothing was flaky.

The cause was a rename in `lib/rtl` plus its `test/` callers. The heuristic
drops `compiler/` commits from a `$(PXX_STABLE)` job's bisect range, which is
sound, but the fallback advice it then prints assumes the residue is
environmental. It is not: `lib/` and `test/` are still in range and are exactly
where a `$(PXX_STABLE)` job's real regressions live. Suggest the fallback say
"look in `lib/` and `test/` within the range" before it says "flakiness".
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 876675b0f.
