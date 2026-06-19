# Parallel tracks: compiler (A) and libraries/demos (B)

Two work streams proceed in parallel, decoupled by a **pinned stable compiler**.
The point: A can rebuild and temporarily regress the compiler while B keeps
building libraries and demo apps against a known-good baseline.

## The boundary

```
                stabilize (publish)              compile with
   track A  ───────────────────────▶  stable_linux_amd64/default/latest  ◀───────  track B
  compiler/**                          (frozen, git-tracked pascal26)              lib/**, examples/**
```

- **`$(PXX_STABLE)`** = `stable_linux_amd64/default/latest` (override per build:
  `make lib-test PXX_STABLE=stable_linux_amd64/default/v9`).
- B auto-follows `latest`. A pin is only for chasing a regression.
- Current platform (x86-64) only. Cross-compile is a later concern; the cross
  suites (`make test-i386 / test-aarch64 / test-arm32 / cross-bootstrap`)
  discover any per-target gaps after the fact.

## Track A — compiler

Owns (ideal): `compiler/**`, and the compiler / cross / esp / bootstrap /
stabilize parts of the `Makefile` and `test/`.

Publishing a new baseline, when a feature B needs lands:

```sh
make stabilize        # runs `make test` + 4-iteration fixedpoint, then records:
                      #   stable_linux_amd64/default/v{N+1}, latest -> vN+1,
                      #   last.sha256, history.log (ts, vN, sha, commit, subject)
git add stable_linux_amd64 && git commit -m "chore(stable): record vN"
```

`history.log` is the changelog and the sync signal — its last line tells B which
commit the current `latest` was built from. Roll back with `make revert
VERSION=N` (restores `compiler/pascal26` from a recorded binary).

The **authoritative gate is unchanged**: `make test` + self-host fixedpoint.
A feature is not "done" until it passes that. `make stabilize` will not record a
baseline that fails the gate.

## Track B — libraries and demos

Owns (ideal): `lib/**`, `examples/**`, new `test/lib_*`, and the `lib-test` /
`demos` `Makefile` block. Always compiles with `$(PXX_STABLE)`, never rebuilds
the compiler.

```sh
make pxx-stable-check   # shows the pinned version; warns if it lags HEAD
make lib-test           # curated GREEN smoke (may hard-fail; keep it green)
make demos              # compile-smoke dashboard for every example (exit 0)
```

`lib-test` and `demos` are **discovery harnesses, not gates**. When they surface
missing or bugged library / language support (e.g. a demo needs `Copy` or
`IntToStr`, or a parse error), **file a ticket** in `docs/progress/backlog`
rather than treating the red as a hard failure. Keep `lib-test` itself green —
move anything broken out to a ticket.

## Lanes are soft, not walls

The split above is the *ideal*, not a fence. This is a dialect:

- A may touch `lib/**` when a builtin or a compiler test needs it (ideally only
  the builtin libs, but not exclusively).
- B may be asked to bug-hunt or advise on the compiler.

Expect a grey zone. The rule that matters: **the authoritative gate is `make
test` + self-host fixedpoint**, and a fresh `make stabilize` is what hands B a
compiler with new features. Coordinate through commits on `master` and the
`history.log` baseline; keep cross-edits to the shared `Makefile` inside each
track's fenced section to avoid collisions.
