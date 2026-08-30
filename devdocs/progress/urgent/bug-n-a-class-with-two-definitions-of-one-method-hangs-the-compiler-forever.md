---
track: N
prio: 65
type: bug
blocked-by: []
summary: "9-line repro: a class defining the same method twice, whose body assigns a parameter to a SAME-NAMED attribute (`self.prefix = prefix`), plus any later scope holding a local of that name, makes the compiler spin at 100% CPU forever. RSS is flat, so it never OOMs and never self-terminates — it hangs until killed. CPython accepts the source (last definition wins). Any lane running a lib gate over such a file hangs with no output."
status: urgent
owner: unassigned
---

# A class with two definitions of one method hangs the compiler forever

- **Type:** bug (hang / non-termination) — **Track N** (NilPy frontend).
- **Filed:** 2026-08-30 by frankB (Track B), found while building the minidom shim.
- **Measured against pin** `53800fbeb0b66e11`.

## Why this is filed urgent rather than at the severity of its symptom

**A hang is the one failure that does not report.** A wrong answer is visible, a
crash has an exit status and a location, but this produces no output, no error,
and no exit — a lane running `make lib-test` over a file of this shape waits
forever and its operator reads it as a slow box. It is also *silent by
construction*: RSS is flat, so the OOM killer never intervenes and the process
never dies on its own.

It reached this repo as a 452-line library file that could not be added to
`lib/rtl` at all, because doing so would have hung every lane's library gate.

## Repro — 9 lines, complete

```python
class C:
    def __init__(self, name, prefix):
        self.prefix = prefix

    def __init__(self, tagName, prefix):
        self.prefix = prefix

    def other(self):
        prefix = None
```

Compiling anything that imports this module never terminates:

```
$ timeout 120 pinned -Fu<libdir> t.npy t.bin      # t.npy is `import mimic_bis`
$                                                 # (killed by timeout; no output)
```

CPython accepts the same file — a re-`def` simply rebinds, last definition wins:

```
CPython imports and runs; C("a","b").prefix = b
```

## It is a spin, not a deadlock and not a memory blowup

Sampled against the compiler's own PID:

```
  t=3s:  STAT R  %CPU 100  RSS 67796 KB
  t=8s:  STAT R  %CPU 100  RSS 67796 KB
  t=15s: STAT R  %CPU 100  RSS 67796 KB
```

Runnable, pegged at one core, allocation perfectly flat. So it is a
non-terminating loop that allocates nothing — which is why waiting does not help
and why nothing in the environment ever ends it.

## The three required ingredients, each varied against an identical base

All three must hold at once. Removing any one makes the file compile:

| # | ingredient | control that removes it | result |
| --- | --- | --- | --- |
| 1 | a **class** containing **two definitions of the same method** | single definition | COMPILES |
| 2 | the body assigns a parameter to a **same-named attribute** (`self.prefix = prefix`) | `pass`, or `x = prefix` (plain local) | COMPILES |
| 3 | a **later scope** holds a **local with that same name** (`prefix = None`) | local named anything else | COMPILES |

## What the boundary is NOT — measured, because each of these was a hypothesis

Every row below was a guess that died to a control, and each one narrows the fix:

| guess | verdict |
| --- | --- |
| it needs `__init__` specifically | **no** — a duplicated ordinary method `m` hangs identically |
| the two signatures must differ | **no** — two byte-identical signatures hang |
| it needs defaulted parameters | **no** — `def __init__(self, name, prefix)` with no default hangs |
| it needs *several* defaults (the original had four) | **no** — one parameter is enough, and none is enough |
| the third scope must be a method of the class | **no** — a module-level `def other(): prefix = None` hangs too |
| the third scope's *parameters* matter | **no** — `other(self)` taking nothing hangs; only its LOCAL matters |
| the shared name can be the attribute's | **no** — `self.zzz = prefix` + local `zzz` COMPILES |
| the shared name can be the parameter's when they differ | **no** — `self.zzz = prefix` + local `prefix` COMPILES |
| it needs a base class | **no** — `class C:` with no base hangs |
| it is about slicing, or 5-argument construction | **no** — see below |

The last two rows are the sharpest constraint on a fix: the collision is
specifically between a **parameter and an attribute that share one name**, and
breaking that identity in *either* direction stops the hang. A name-resolution
loop that consults both the parameter scope and the attribute set, with two
method definitions supplying two answers, fits every row in both tables.

## How it was found, since the first two hypotheses were wrong and cost the most

Original symptom: a 452-line `mimic_xml_dom_minidom.py` hung. Bisecting by layer
pointed at `Document.createElementNS`, and varying one factor at a time there
said the hang needed a 2-arg and a 5-arg constructor call, sliced locals, and the
result returned. **All three of those were artefacts of the file, not the bug** —
`Element.setAttributeNS` had the identical slice-and-construct shape in a layer
that compiled, and a 12-line hand-written version of that shape compiled too.

What actually found it was a delta-debugger reducing the real file rather than a
hand-built imitation of it: 452 → 23 lines over 442 probes. Its output was
degenerate — every method collapsed into one class, `createElementNS` left with a
one-line body — and *that* is what exposed the real ingredients, none of which
involve slicing or construction at all. The reduction disproved my own diagnosis;
a hand-reduction guided by that diagnosis would have preserved the wrong factors
and never converged.

Two notes on doing this safely, since a hang is being measured:

- The reducer classified by timeout, so a loaded box could accept a drop that
  made compilation merely *slow*. Box load was ~11.6 throughout. Guarded by
  re-verifying at 60s every twelfth accepted drop and at 90s at the end; the
  final 9-line repro is confirmed at **120s** against a ~4s normal compile for
  the same file, a 30x margin.
- It ran against a private copy of `lib/rtl`, never the real tree, so no lane's
  gate could ever meet the probe file.

## Gate

Track N's: `make test-nilpy` green + self-host byte-identical. Plus the 9-line
repro above compiling — and, because a hang has no error message to assert on,
a bounded `timeout` around that compile so a regression is a red rather than a
hung suite.

Worth adding the repro to the NilPy tests under a timeout for exactly that
reason: this class of defect cannot be caught by asserting on output, only by
asserting that the compiler *finished*.

## Consumer

Blocks [[feature-b-a-real-minidom-is-an-implementation-not-a-shim]]. The DOM
implementation is written and its CPython differential is banked and passing
(`test/lib_mimic_xml_dom_minidom.npy`, 34 checks), but the module cannot enter
`lib/rtl` until this is fixed. Per the platonic-code rule the source is **not**
being reshaped to dodge this — renaming the local would silence it and hide the
bug.
