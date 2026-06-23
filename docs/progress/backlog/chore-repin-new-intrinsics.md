# chore: re-pin stable to expose the new System intrinsics to Track B

- **Type:** chore (Track A — pinning) / cross-track signal
- **Status:** backlog
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
