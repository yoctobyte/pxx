# chore: re-pin stable to expose the new System intrinsics to Track B

- **Type:** chore (Track A — pinning) / cross-track signal
- **Status:** done
- **Found:** 2026-06-23, differential probe vs FPC (Track B)
- **Severity:** medium (Track B cannot use shipped intrinsics until re-pinned)

## Situation

Several System intrinsics have landed in the compiler but are NOT in the pinned
stable (`stable_linux_amd64/default/pinned`, v38) that Track B builds against, so
Track B code using them fails at compile with `undefined variable`:

- `Succ` / `Pred` / `Odd`  (5f3dfe5)
- `Abs` / `Sqr`            (3604594)
- `UpCase` / `Pos`         (f078bc9)
- `Concat`                 (91f5750)
- `Delete` / `Insert`      (5d38bef)

Verified: with the pinned v38, `writeln(succ('a'))`, `abs(-9)`, `upcase('x')`,
`pos('cd', s)` all report `undefined variable`; the engine/demo code therefore
still hand-rolls these (e.g. solitaire/2048 avoid `Pos`, use manual run/merge).

## Ask (Track A)

`make stabilize` + `make pin` once the intrinsics are settled, and commit
`stable_linux_amd64/**`, so Track B can drop the hand-rolled equivalents and use
`Pos`/`UpCase`/`Abs`/`Succ`/`Delete`/`Insert` directly. No code change required
here — purely a re-pin.

## Note

Not urgent-blocking (Track B has working idioms), but it removes a pile of
interim hand-rolls across the library/demo lane.

## Update 2026-06-23 — large fix batch now waiting on a pin

Since this was filed, Track A landed many fixes in compiler/ that the pinned v38
(`aa055c5`) does NOT yet include — `tools/fpc_diff_probe.sh` still shows all 16
known divergences against the pin. A re-pin would expose, in one go:
- `a034eaa` Length accepts any string/array r-value (+ `4281ed0` literal fold) —
  unblocks GUI code like `Length(memo.Text)` (the eliah smoke worked around it)
- `57d8f49` nested `{ }` / `(* *)` comments
- `da4c8f9` variant-record union layout
- `d828533` inline `ParamStr(i)` + out-of-range returns ''
- `3a2e952` binary literals / explicit enum values / subrange types
Plus the earlier Succ/Pred/Odd/Abs/Sqr/UpCase/Pos/Concat/Delete/Insert intrinsics.
Net: a pin bump retires ~10 Track-B interim idioms at once.

## Resolution (2026-06-23)

Re-pinned: `make stabilize` (full test + 4-iteration fixedpoint, green) + `make
pin` → stable v39 (sha 59d5aa64…), builtin RTL re-frozen. Exposes to Track B, in
one bump: the Succ/Pred/Odd/Abs/Sqr/UpCase/Pos/Concat/Delete/Insert intrinsics
plus this session's fixes — Length r-value getter, nested comments, variant-record
union layout, inline ParamStr, binary literals / explicit enum / subrange types,
default parameters, @obj.Method→Pointer, and array-constructor open-array args.
Closes chore-repin-new-intrinsics.
