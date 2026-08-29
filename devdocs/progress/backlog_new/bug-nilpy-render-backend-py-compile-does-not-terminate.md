---
track: N
prio: 55
type: bug
blocked-by: []
summary: "songformatter's render_backend.py (413 lines) does not finish compiling: killed at 25:00.06 wall clock, 95% CPU, RSS FLAT at 102 MB, state R — spinning, not allocating. The 2026-07-31 record says it compiled. Bounded rather than diagnosed: lines 1..296 compile in 7s, the whole file spins. Filed with no proposed cause because every cause tried so far has been wrong, and each wrong one is recorded so nobody re-walks it."
status: new
owner: ""
---

# `render_backend.py` does not finish compiling

- **Type:** bug (compiler non-termination) — **Track N** by the file's language;
  re-lane to A if the loop turns out to be below the frontend.
- **Filed:** 2026-08-29 by the wasm lane, against pin v392 (`60b060bb54a8`),
  while re-measuring [[feature-demo-songformatter-pxx-target]].
- The 2026-07-28 and 07-31 passes both record this module compiling, so this is
  a regression rather than a gap. The app has not changed (`~/songformatter`
  HEAD is still `12cf40e`, 2026-07-28).

## Measurement

```
$ cd ~/songformatter
$ /usr/bin/time -v timeout 1500 pascal26 render_backend.py /tmp/rb
Command exited with non-zero status 124
        Elapsed (wall clock) time: 25:00.06
        Maximum resident set size (kbytes): 102252
```

Sampled while running: **95% CPU, state R, RSS flat at 102252 KB** across 20
seconds. So it is **spinning, not allocating** — an unbounded or pathological
loop, not a memory blowup. That distinction is the one thing here established
rather than guessed, and it says the fix is a loop bound, not a capacity.

No stack sample: `ptrace_scope` blocks attaching to a running process on this
box, and re-running under gdb costs another 25 minutes per attempt.

## Bound

| input | result |
| --- | --- |
| lines 1..140 (through `_apply_color_key`) | ok, 7s |
| lines 1..184 (through `_map_font`) | ok, 8s |
| lines 1..296 (into `class TkCanvasBackend`) | **ok, 7s** |
| lines 1..378 | fails fast: `undefined variable (_TkTextObject)` at :301 |
| the whole file | **spins** |

So the loop needs something at or after line 297, and the 1..378 row cannot
narrow it because the forward reference at :301 aborts the compile before the
loop is reached.

## Causes tried and REJECTED, so nobody re-walks them

Each of these looked right and is wrong:

* **Not the `_as_tk_photo` helper.** Deleting it made the compile finish in 9
  seconds, which I read as a fix. It is not: the deletion makes compilation
  **fail earlier**, at the call site on line 329, so it never reaches the loop.
  A fast failure masking a slow one reads exactly like a repair. Replacing the
  function with a `return None` stub — which keeps the call site valid — still
  spins.
* **Not a forward class reference.** `TkCanvasBackend.beginText` returns a
  `_TkTextObject` defined 80 lines later. Moving `_TkTextObject` above
  `TkCanvasBackend` still spins.
* **Not the construction itself.** Replacing `return _TkTextObject(self, x, y)`
  with `return None` still spins.
* **Not mutual class reference on its own.** Two classes that construct and
  store each other compile in 3 seconds.

## The probe trap that cost an hour, and the rule that follows

**Any bisect of this file must run in `~/songformatter`.** The identical bytes,
compiled from a scratch directory, fail in 7 seconds with

```
pascal26:1: error: unexpected token
```

which reads as a parse bug at line 1 and is actually an unresolvable sibling
import reported at the wrong line. `cmp` confirms the two inputs are
byte-identical; only the working directory differs. Every truncation test run
outside the app directory measured import resolution rather than the loop, and
they all "failed" identically, which looked like a consistent finding.

Two probe artefacts, one lesson: **a probe that changes the failure has not
necessarily reached the defect.** A faster failure and a different failure are
both indistinguishable from progress unless you check *which* failure you now
have.

## Why no proposed cause

Every cause proposed for this so far has been wrong, and the ones above were
each supported by a passing experiment. Filing the bound and the timing is
worth more than a fifth guess. Whoever picks it up starts from: something at or
after line 297, in a build that reaches line 378 without aborting.

## Gate

Track N's: `make test-nilpy` green + self-host byte-identical, plus
`render_backend.py` compiling from `~/songformatter` in bounded time — and the
timing recorded, since "it finished" is not a result here without a number next
to it.
