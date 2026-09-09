---
prio: 70
track: B
---

> **Track guessed as B from the FAILING STEP** — line 84 of 346, `stable_linux_amd64/default/pinned --mimic-fpc -dPXX_DYNLIB_LIBC -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix`, which names `test/lib_synapse_tls_loopback.pas`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 52 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: lib-test#src:tools/crtl_reachability.py at fca28056d8ec in step 84/346, `stable_linux_amd64/default/pinned --mimic-fpc -dPXX_DYNLIB_LIBC -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posi…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T16:32:30Z
- **Test source:** tools/crtl_reachability.py tools/gen_crtl_map.py +50
- **Failing step:** line 84 of 346 of the job's recipe; it names `test/lib_synapse_tls_loopback.pas`.
  ```
  stable_linux_amd64/default/pinned --mimic-fpc -dPXX_DYNLIB_LIBC -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix test/lib_synapse_tls_loopback.pas /tmp/lib_synapse_tls_loopback
  ```

## Repro
`tools/testmgr.py --tier full --job 'lib-test#src:tools/crtl_reachability.py'` at fca28056d8ec2483d3a9a1b0f064842164f92b46

## Range
> **The named sha `fca28056d8ec` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `fca28056d8ec`, last good `0e3ba86d5208`, **4 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
pascal26:2039: error: undefined variable (SetString)
pascal26:2077: error: undefined variable (SetString)
pascal26:2178: error: undefined variable (SetString)
(tail)
k pinned to: stable_linux_amd64/default/pinned -> stable_pinned   (newest checkpoint: latest -> stable_latest)
frozen builtin RTL: stable_linux_amd64/default/builtin/ (13 src) -- isolates track A's compiler/builtin/ edits
=== lib-test: library smoke against stable_linux_amd64/default/pinned ===
crtl-reachability: OK -- 148 headers, 66 modules, every declared function reachable from its own header
crtl-map: OK -- 613 crtl functions mapped to 63 headers
  lib-units: 144 units compile (0 known-broken skipped)
ok: /tmp/testmgr-scratch-3871455/lib_ipv6  [code=163608B  data=6128B  bss=52028B  procs=555]
ok: /tmp/testmgr-scratch-3871455/lib_net6  [code=171800B  data=7168B  bss=52968B  procs=576]
ok: /tmp/testmgr-scratch-3871455/lib_asyncnet6  [code=171800B  data=6232B  bss=235724B  procs=585]
ok: /tmp/testmgr-scratch-3871455/crtl_exp2  [code=413464B  data=12928B  bss=74188B  procs=963]
  tk-nilpy: ok
ok: /tmp/testmgr-scratch-3871455/lib_urllib_server  [code=1363736B  data=98872B  bss=293084B  procs=2258]
note: urllib_request -> mimic_urllib_request (shim, subset)
note: urllib_error -> mimic_urllib_error (shim, subset)
ok: /tmp/testmgr-scratch-3871455/lib_urllib_client  [code=1761048B  data=125586B  bss=297620B  procs=2594]
note: urllib_request -> mimic_urllib_request (shim, subset)
note: urllib_error -> mimic_urllib_error (shim, subset)
ok: /tmp/testmgr-scratch-3871455/lib_urllib_refusals  [code=1748760B  data=123676B  bss=292404B  procs=2602]
  lib-test: mimic_urllib_request matches CPython
  lib-test: tkhtmlview renders identically under CPython
pascal26:2039: error: undefined variable (SetString)
  in: external/synapse/synautil.pas
  near: ( var APtr : PANSIChar ; >>> AEtx : PANSIChar 
pascal26:2077: error: undefined variable (SetString)
  in: external/synapse/synautil.pas
  near: do begin SearchForLineBreak ( APtr , >>> AEtx , bol 
pascal26:2178: error: undefined variable (SetString)
  in: external/synapse/synautil.pas
  near: <= AEtx ) and ( SynaFpc >>> . strlcomp ( 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
