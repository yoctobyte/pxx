---
summary: "FPC cold-start broken again: PyBytesCi is called at pyparser.inc:1508 but not defined until 5236, with no forward. One-line fix, verified — FPC then compiles the whole compiler in 10.7s"
type: regression
track: N
prio: 60
status: done
owner: claude-AN
---

# FPC seed drift: `PyBytesCi` is used 3700 lines before it is defined

- **Type:** regression, cold-start bootstrap path — **Track N** (`pyparser.inc`
  is N's carved-out file; the sibling case lived in the shared `parser.inc` and
  was therefore filed as A).
- **Filed:** 2026-08-02 by `claude@xeon` (Track T) from the `fpc-bootstrap`
  canary. **T owns the tool, never the bug** — this is handed over, not fixed.
- **Advisory**, per `testmgr.fpc_canary_job()`: a red here gates nobody's push.
  Nothing day to day uses the FPC seed, which is exactly why it rots silently.

## The failure

```
$ fpc -Mobjfpc -O2 -Tlinux -Px86_64 -FU<tmp> -FE<tmp> -o<out> compiler/compiler.pas
pyparser.inc(1508,16) Error: Identifier not found "PyBytesCi"
```

`PyBytesCi` is *called* at `pyparser.inc:1508` (and 1509) and not *defined*
until `pyparser.inc:5236`. pxx's own frontend resolves it; FPC is single-pass
and needs a forward, so the seed build stops there.

## Culprit — do NOT bisect, the watcher blamed the wrong commit

The tstate report names **`d21c2da3ad81`**, which is a *tickets-only* commit of
mine and cannot have caused it. The watcher's last native run was at
`2e626bcd9b4f` and its next at HEAD, so the whole range inherits the blame.

Exactly one commit in that range touches `compiler/**`:

```
4724ca4a4 fix(N): `b"ell" in b"hello"` was always False
```

which is where the `PyBytesCi` call at 1508 was introduced. Everything else in
the range is tickets and tstate.

## Verified fix — one line

Add a forward beside the other `pyparser.inc` forwards, e.g. after
`function PyParseFor: Integer; forward;` (~line 190):

```pascal
function PyBytesCi: Integer; forward;
```

Measured, not assumed: with that line the seed build goes green —
`136110 lines compiled, 10.7 sec`, binary produced. The probe edit was reverted;
the tree this ticket was filed from is clean.

## This is the second one in two days

[[bug-a-fpc-seed-drift-pymaketruthy-forward-wrong-file]] was the same class,
filed 2026-08-01 and fixed the same evening by `9d2d98856` — that one had the
forward in the wrong *file*, this one has no forward at all. Both were
introduced by a Track N feature commit that pxx accepted and FPC did not.

The pattern is structural, not careless: the seed build is the only thing that
enforces "compiler sources stay FPC-compilable", it is advisory, it runs only
on the watcher, and it is therefore the one signal a dev loop optimised for
speed will never see. Worth noting for whoever picks this up that the FPC seed
build is only **~11 seconds** — cheap enough that Track T should consider
whether it belongs closer to the inner loop; filed separately as
[[feature-t-fpc-seed-canary-closer-to-the-dev-loop]] so this ticket stays a
one-line fix.

## Gate

`fpc -Mobjfpc -O2 -Tlinux -Px86_64 ... compiler/compiler.pas` compiles clean,
and `tools/testmgr.py --tier native --job 'fpc-bootstrap#src:compiler/compiler.pas'`
goes green on the next watcher run.


## Resolved 2026-08-02 — commit 831e2db63

The one-line forward, placed beside the other `pyparser.inc` forwards, with a
comment saying WHY it exists so the next person does not tidy it away as
redundant (pxx does not need it; only FPC does).

Verified end to end rather than at the seed step alone: `make bootstrap` runs
fpc -> `pascal26-build` -> `pascal26-verify` and the two are byte-identical.
135915 lines compiled in 3.8s — which is the ticket's own argument for
[[feature-t-fpc-seed-canary-closer-to-the-dev-loop]] restated with a number:
the check that would have caught this costs four seconds and nothing in the
dev loop runs it.

`gate.sh quick` GREEN. The `fpc-bootstrap` job goes green on T's next run.

Line numbers had drifted since filing (the call is at 1560 now, the body at
5506) — the diagnosis was otherwise exact, including the note not to trust the
blamed sha.

## Log
- 2026-08-02 — resolved, commit 831e2db63.
