---
prio: 70
track: B
status: done
---

> **Track guessed as B from the FAILING STEP** — line 2 of 2, `if [ ! -f "library_candidates/fcl-json/packages/fcl-json/src/fpjson.pp" ]; then \ echo "test-fpjson: SKIP — no fcl-json `, which names `tools/install_lib_candidates.sh`. Not from the job's name or its `src`: those describe what the job is ABOUT, and this job's recipe spans 3 source file(s). The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **This commit CANNOT be the cause.** The job builds only with `$(PXX_STABLE)`, and this commit moved no `stable_linux_amd64/**` — so the bytes that compiled it are unchanged. Look at flakiness or box load, not at the named sha; the bisect is unsound here and has been skipped.

> **origin/master has advanced 7 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-fpjson#src:tools/install_lib_candidates.sh at fca28056d8ec in step 2/2, `if [ ! -f "library_candidates/fcl-json/packages/fcl-json/src/fpjson.pp" ]; then \ echo "test-fpjson: SKIP — no fcl-json…` (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven, twatch `0c5ad13167ab`).
  Untriaged.
- **Found:** 2026-09-09T16:32:30Z
- **Test source:** tools/install_lib_candidates.sh test/fpjson/testutils.pas +1
- **Failing step:** line 2 of 2 of the job's recipe; it names `tools/install_lib_candidates.sh test/fpjson/testutils.pas test/fpjson/tjrun.pp`.
  ```
  if [ ! -f "library_candidates/fcl-json/packages/fcl-json/src/fpjson.pp" ]; then \ echo "test-fpjson: SKIP — no fcl-json tree at library_candidates/fcl-json/packages (tools/install_lib_candidates.sh fcl-json)"; \ exit 0; \ fi; \ wd="$(mktemp -d)"; trap 'rm -rf "$wd"' EXIT; \ root="$(pwd)"; \ for d in
  ```

## Repro
`tools/testmgr.py --tier full --job 'test-fpjson#src:tools/install_lib_candidates.sh'` at fca28056d8ec2483d3a9a1b0f064842164f92b46

## Range
> **The named sha `fca28056d8ec` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `fca28056d8ec`, last good `0e3ba86d5208`, **4 observable commit(s)** in range (it builds with `$(PXX_STABLE)`, so `compiler/` commits cannot have caused it and are dropped; pin moves, `lib/` and `test/` are kept) — the watcher narrows this by idle bisect.

## Log tail
```
pascal26:3534: error: undefined variable (UTF8Decode)
pascal26:3621: error: undefined variable (SLineBreak)
pascal26:3042: error: undefined variable (sLinebreak)
pascal26:3419: error: undefined variable (sLineBreak)
pascal26:3944: error: undefined variable (UTF8Encode)
pascal26:3963: error: undefined variable (UTF8Encode)
(tail)
compiling fpjson suite runner ...
test-fpjson: FAIL — the suite runner did not COMPILE (this is a
  compile failure, not a test failure; 0 of 203 tests ran):
pascal26:3534: error: undefined variable (UTF8Decode)
  in: fpjson.pp
  near: FHash . Count ; end ; >>> function TJSONObject . 
pascal26:3621: error: undefined variable (SLineBreak)
  in: fpjson.pp
  near: I ] , Self . Items >>> [ I ] 
pascal26:3761: warning: duplicate definition of 'TJSONObject.Add' with the same parameter types; the later body wins, but calls written between the two bind to the earlier one
pascal26:3981: warning: duplicate definition of 'TJSONObject.Get' with the same parameter types; the later body wins, but calls written between the two bind to the earlier one
pascal26:3042: error: undefined variable (sLinebreak)
  in: testjsondata.pp
  near: ( 'FormatJSON, default' , '[' + sLinebreak >>> + '  0,' + 
pascal26:3419: error: undefined variable (sLineBreak)
  in: testjsondata.pp
  near: ( 'Format []' , '{' + sLineBreak >>> + '  "x" : 1,' + 
pascal26:3944: error: undefined variable (UTF8Encode)
  in: testjsondata.pp
  near: ( O , '{ "A" : "' + UTF8Encode >>> ( S ) 
pascal26:3963: error: undefined variable (UTF8Encode)
  in: testjsondata.pp
  near: ( O , '{ "A" : "' + UTF8Encode >>> ( W ) 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*
- 2026-09-11 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit cead35240.

## 2026-09-11 (frankS) — real, mine, fixed at 8887170da

**CAUSE.** `0ffe185bb` moved six System names out of `lib/rtl/sysutils.pas` into
`compiler/builtin/builtin.pas`. This job builds with `$(PXX_STABLE)` — the PINNED
compiler plus a FROZEN copy of `compiler/builtin/` that predates the move — so
the name is gone from the only two places such a build can look. For test-fpjson the names
are `UTF8Encode` and `sLineBreak`, in `testjsondata.pp`.

**FIX.** All six restored in `lib/rtl/sysutils.pas` as a deliberate duplicate of
builtin's copies, with a retirement test written on the `sLineBreak` note (grep
the name in `stable_linux_amd64/default/builtin/builtin.pas`; delete the sysutils
copy when it is there). Verified positive-control first, in place: revert
`sysutils.pas` to origin/master and this job's own recipe reproduces the error in
the log tail above; apply the fix and it reports `PASS — 203/203`.

**THE BANNER AT THE TOP OF THIS TICKET SAID THE OPPOSITE, AND IT IS WORTH A
SENTENCE.** "This commit CANNOT be the cause ... Look at flakiness or box load"
is TRUE about the named sha `fca28056d8ec` (a tstate publish, docs only) and
WRONG as advice, because this job reads live `lib/**` and the untested range
below the named sha held four observable commits — one of which is the cause. The
ticket's own Range section said so correctly thirty lines further down ("the
cause is somewhere below it", "**4 observable commit(s)**"), so the ticket
contradicted itself and the contradiction was in the half a reader sees first.
Reworded in `tools/twatch.py` at HEAD to stop at the exculpation and hand the
residual question to the Range section, which already carries the
`range_non_causal` case for when the answer genuinely is the box.
