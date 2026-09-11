---
slug: bug-n-a-method-call-is-refused-on-arity-from-the-candidates-compiled-so-far-so-import-order-decides
title: A method call is arity-checked against the candidates compiled SO FAR, so import order decides whether a correct program compiles
track: N
type: bug
prio: 75
status: done
---

## Summary

**RESOLVED 2026-09-11** — the call is now deferred to the run-time dispatcher
instead of refused, decided PRE-PARSE beside the existing open-world keyword
fall-through. The repro prints 100 in all six import orders; lekkerzeilen goes
to 28 of 35 with `ctypes` the only wall left. The ticket's own "NOT a quick fix"
premise was measured false: the segfault it feared is caught by a DIFFERENT
refusal site, and the runtime arity check it said had to come first already
exists in `PyHostCall`. See the resolution below.

`obj.m(args)` on a dynamically-typed receiver is arity-checked at compile time
against the same-named methods **compiled so far**, and refused when none of
*those* fits — even though a fitting `m` is declared in a module imported
later. Reordering imports, which cannot affect method resolution in Python,
turns a compile error into a successful build. It is a FALSE NEGATIVE only:
where a candidate fits, run-time dispatch is correct, so no program gets a
wrong answer from this.

## Repro (outside the corpus, three files)

```python
# wide.py
class Wide:
    def probe(self, a, b, hint=None): return 100
# narrow.py
class Narrow:
    def probe(self, a, b): return 200
# caller.py
def call_wide(w): return w.probe(1, 2, 3)
```

Main is `import <three modules>` then `print(call_wide(Wide()))`. **CPython
prints 100 for all six orders.** pascal26 at `d28aae4157c8`:

| import order | result |
| --- | --- |
| wide, narrow, caller | 100 |
| narrow, wide, caller | 100 |
| caller, wide, narrow | 100 |
| caller, narrow, wide | 100 |
| wide, caller, narrow | 100 |
| **narrow, caller, wide** | **error: `probe() takes exactly 2 argument(s), got 3`** |

## Mechanism — the model that fits all twelve measured cells

The candidate scan is over the COMPILATION, and specifically over what has been
compiled **so far**. The call is accepted iff **some already-compiled `probe`
fits the arity**:

- **zero** candidates seen at the call site → deferred to run time → always correct
  (rows 3 and 4 above);
- **≥1 seen and one fits** → accepted, and the run-time arm still picks the right
  class (rows 1, 2, 5);
- **≥1 seen and none fits** → refused (row 6).

Count is NOT the discriminator and neither is "caller in the same file":
two wrong-arity candidates (arity 2 and arity 1) refuse a 3-argument call
whether the caller sits in their file or in its own module — both measured.
An earlier reading of this defect as "one candidate hard-binds, several emit
runtime arms" is **wrong** and is corrected here.

## No silent half — ATTESTED, with the control named

Where exactly one candidate precedes the caller, FITS the arity, and belongs to
the **wrong class**, the binding is still correct at run time:
`Alpha.probe`/`Beta.probe` both `(self, v)`, one imported before the caller and
one after, gave 205 and 105 — CPython's answers — in both directions.

**Sixteen shapes across two seats, non-overlapping, and the instrument is proven
able to find the defect.** frankuser ran eight more at binary `b00c6751b693`,
choosing the axes that have discriminated elsewhere — receiver EXPRESSION
(direct, list element, dict value, comprehension variable) and `__slots__`,
which was the hidden ingredient in a nearby segfault — on the theory that a hard
bind would show up there. None does; all eight match CPython. Crucially they ran
**the known-positive first**: the `narrow, caller, wide` refusal reproduces on
their binary, so the sweep is not a guard that cannot fail. (Their first attempt
*was* one — `$b` without `./` sent bash down PATH and reddened all eight rows
for a harness reason.)

State it as attested, not as unrefuted: *"we could not find one"* and *"we looked
with an instrument proven able to find one"* are different claims, and only the
second should stop a later reader re-ranking this as a correctness bug. It is a
false negative — a refusal — and never a wrong value.

## Corpus impact (lekkerzeilen, the p90 demo umbrella)

Three classes declare `nearest`: `traffic.py:161` `(self, x, z)`,
`traffic.py:1035` `(self, focus)`, `world.py:125`
`(self, x, z, hint=None, window=240.0)`. `hud.py:277` calls
`traffic.nearest(state.position)` — one argument.

The model predicts which orders work, and they do:

| modules compiled | result |
| --- | --- |
| `hud` alone | OK (zero candidates) |
| `world` + `hud` | `nearest() takes 2 to 4 arguments, got 1` |
| `traffic` + `world` | `takes exactly 2 argument(s), got 3` |
| `world` + `traffic` | OK |
| 24 modules, alphabetical | FAIL |
| 24 modules, **`world` then `traffic` first** | **all compiled** |

Reordering the imports is not a fix and must not be applied to the corpus —
it is the evidence. Per "no compiler-appeasement workarounds", the platonic
import order stays.

## Where it is in the compiler, and a FALSE PREMISE in the guard's own comment

`compiler/pyparser.inc`. There are TWO arity refusals and they print
**textually identical** messages, so which one fires cannot be read off the
error. **Measured, not inferred** (2026-09-11, binary `b00c6751b693`): both
sites were temporarily tagged and rebuilt, and every row in this ticket —
the three-file repro, `traffic` alone, and `world`+`hud` — comes out of the
**dynamic-receiver site**, in both its `takes exactly N` and `takes N to M`
branches. The `PyParseClassMethodCall` pair never fired. Say it that way
because an identical message across two sites is exactly the shape that sends
a fix to the wrong one.

That site guards itself on `hitCi >= 0` and explains why:

> *Guarded on hitCi >= 0: only there is the class known at compile time. When
> dispatch is genuinely dynamic (hitCi < 0, ...) a compile error would reject
> valid programs, so those keep today's behaviour and want a RUNTIME arity
> check instead — filed separately.*

**The reasoning is right and the premise is wrong.** `hitCi >= 0` does not mean
the receiver's class is known — it means *some class compiled so far declares
this name*. In the repro the receiver is `w`, an unannotated parameter with no
static type at all, and `hitCi` is simply the winner of a name scan. So the
case the comment sets out to protect — genuinely dynamic dispatch — falls on
the REFUSING side of the guard whenever any same-named method has been
compiled, which is the defect. The intended behaviour is already written down
in that comment; only the test for it is mis-aimed.

Two further notes for whoever takes it:

- The adjacent machinery is most of the fix already. `nDual` holds the demoted
  candidates and there is an existing promotion loop that prefers a dual whose
  arity fits (added for `var.get()` on tkinter). It fires when SOME candidate
  fits; the missing arm is when none does.
- **The "filed separately" ticket does not exist** — no ticket in
  `devdocs/progress/**` covers a runtime arity check for dynamic dispatch
  (searched 2026-09-11). This ticket is that one, and the import-order face
  above is a second, louder way into the same room.

## Fix direction (not attempted)

Defer the arity decision to the same run-time dispatcher the zero-candidate
case already uses, rather than refusing from a partial candidate set. The
zero-candidate path is measured correct on every row above, so the machinery
exists; what is missing is treating an incomplete scan as incomplete instead
of as exhaustive.

**This is NOT a quick fix and that is why it is filed rather than fixed.**
The refusal was ADDED deliberately, to close
`bug-nilpy-too-few-args-to-container-method-compiles-and-segfaults`: before it,
a missing required argument left the callee reading an uninitialised slot —
`[1,2,3].index()` and `d.get()` core-dumped and `[1,2,3].count()` returned a
wrong value silently. Simply relaxing the guard reinstates that. The safe order
is runtime arity checking FIRST, then narrowing the compile-time refusal to
receivers whose class is actually static.

## A side finding, because this ticket's own absence was the instance

The comment said the successor was *"filed separately"* and it was not. That is
a comment asserting **paperwork exists** — checkable, false, and nastier than a
stale fact, because a reader who trusts it stops looking for the ticket and
concludes the design is already tracked. Same family as a hazard block, which
succeeds by stopping you and therefore generates no signal when wrong.

Measured across `compiler/**` and `lib/**` (2026-09-11): **33** comments claim
paperwork (`filed separately`, `tracked separately`, `see the ticket`). 21 name
a slug within six lines; **12 name nothing checkable**; and **one names a slug
that has no ticket file** — `compiler/pyparser.inc:23973` cites
`bug-a-nilpy-enumerate-over-str-inline-param-leak`, and no ticket in
`devdocs/progress/**` covers it (checked by name and by grepping for
`AN_INLINE_PARAM`). So the class has at least two confirmed instances and a
12-row population nobody has checked. Not claimed here; recorded so it is not
re-derived. The cheap rule for whoever writes the next one: **name the slug or assert no
filing at all** — an unsourced "see the ticket" cannot be falsified by a
reader, which is exactly what makes it survive.

(That sentence originally spelled out the dispatch-suppression marker that
`tools/progress.py` greps for — and the regex matched it, so this p75 ticket
was hidden from `ready` and `next` entirely, on a sentence about CITATIONS.
Nobody could have taken it. Censused when found: 7 open ranked tickets trip
that marker and **6 genuinely mean it**, so the detector is right and this was
the only false row. The repair is the same rule as the one above — describe
the marker, never respell it — which is also why this note does not quote it.)

## RESOLVED 2026-09-11 — deferred to the run-time dispatcher, pre-parse

`compiler/pyparser.inc`, one new arm in `PyParseVariantMethod`, beside the
existing open-world keyword fall-through and modelled on it. When no candidate
compiled so far can accept the number of arguments the call writes, warn and
emit `pydyn_meth<n>(recv, 'name', args...)` instead of refusing.

The three-file repro prints **100** in all six import orders, which is
CPython's answer. `hud.py` and `traffic.py` both compile.

### The ticket's own "NOT a quick fix" was wrong, and here is what it got wrong

It said relaxing the refusal reinstates
`bug-nilpy-too-few-args-to-container-method-compiles-and-segfaults`, and that
the safe order is runtime arity checking FIRST. **Both halves were measured
false, and the same measurement settles them.**

**There are THREE arity-refusal pairs in this file, not two, and they print
different text.** Tagged and rebuilt (2026-09-11) rather than read:

| shape | site |
| --- | --- |
| `xs = [1,2,3]` then `xs.index()` — DIRECT receiver | the field/`requires N argument(s), none given` pair |
| `def f(xs): xs.index()` — dynamic receiver | the `takes exactly N` pair, i.e. this ticket's |
| the three-file repro | the same `takes exactly N` pair |

The segfault ticket's own headline cases are caught by the **other** site,
which this change does not touch. That was checkable in one build and the
ticket asserted the opposite from reading.

**And the runtime arity check the comment asks for already exists.** `pyeval`'s
`PyHostCall` refuses `nargs < n` by name. So the deferred calls fail LOUDLY, at
run time, with CPython's own diagnosis:

| program | pxx after this change | CPython |
| --- | --- | --- |
| `def f(d): d.get()` | `pyeval: too few args to get (need 1, got 0)`, rc=1 | `TypeError: get expected at least 1 argument, got 0` |
| `def f(xs): xs.index()` | `too few args to index (need 1, got 0)`, rc=1 | `TypeError: index expected at least 1 argument, got 0` |
| `det.analyze(1)` vs `analyze(self,chords,fn,sections=None)` | `too few args to analyze (need 3, got 1)`, rc=1 | `TypeError: Det.analyze() missing 1 required positional argument: 'fn'` |

No segfault, no uninitialised slot, no wrong value. The typo protection moves
from a refusal to a warning plus a run-time error, which is the direction this
frontend already took for an undeclared method NAME on 2026-09-10.

### Why the arm is pre-parse, which is the part that is not obvious

By the refusal site, the receiver guard has ALREADY been hoisted against the
candidates compiled so far. A deferral decided there would emit a runtime
dispatch sitting behind a guard that rejects the very class the dispatch exists
to find — green in the compiler and wrong at run time. `PyCallArgCountAt` reads
the count off the token stream, which is what makes deciding before the hoist
possible, and the keyword arm next door was already doing exactly that.

### The safety argument, stated so a reviewer can falsify it

**This arm cannot change a program that compiles today.** It fires only where
no candidate fits, which is precisely where the code below calls `Error()`. A
compilation that succeeds today never reaches it. It is NOT a relaxation of
that refusal, which still stands for everything the new arm declines to take:

- a `*args`/`**kwargs` callee is variadic and fits any count;
- a STR method of the same name at a fitting arity keeps the str arm, because
  the runtime dispatcher is object-only and would raise `AttributeError` on a
  string receiver — `s.find("b", 1)` must not become a dynamic dispatch;
- above four arguments the dispatcher refuses anyway, so today's diagnostic is
  the better one and the arm stands aside;
- a class whose own OVERLOADS include a fitting arity is not a miss, which is
  why the test is `FindUMethArityStrict` and not `FindUMethArity` — the latter
  falls back to the first name match and therefore can never reject. The
  comment at the refusal site says so and it is easy to use the wrong one.

### One divergence NOT fixed here, and it is now more reachable

`PyHostCall` reports too-few-args with `writeln` + `Halt(1)`. CPython raises a
catchable `TypeError`. Deferring more calls to that path makes an uncatchable
exit reachable where a program could have caught the error. Filed separately
rather than changed in the same commit, because it is an RTL behaviour change
with its own blast radius.

### Corpus, and the delta attributed before it is quoted

At compiler `f9fb672ee109`, corpus `2a3d60e`: **28 of 35 modules compile, and
every one of the 7 remaining failures is `ctypes`.** `nearest` is gone as a wall
class. My change accounts for `hud.py` and `traffic.py` and nothing else — both
errored on `nearest()` arity at `c53cb51926a2` on this same tree and compile at
`f9fb672ee109`, and the new warning fires at the failing call site in each (3
occurrences in `hud`, 6 in `traffic`). The `_pxx` wall was cleared by frankZ's
getattr fold plus frankuser's corpus seam rewrite, not by this.

Counts on different corpus revisions are not comparable: frankuser measured 27
of 35 at corpus `8fb873d`. Mine is `2a3d60e`.

### The pinned compiler could NOT date this one, and that is worth writing down

The pinned-versus-current discriminator has a precondition nobody had stated:
**the pin has to get far enough to see the construct.** Pin `095ef4811a5b` stops
`hud.py` at `math.atan2` and `traffic.py` at `undefined variable (__mul__)` —
earlier walls — so it reports a failure that says nothing about arity. The
control here is the tree itself, measured in both directions on it.

(And the first attempt at that control was a guard that could not fail: an
unset `$P` ran a bare `--threadsafe ...`, which is not a compiler, printed no
`error:`, and read as "the pin compiles it cleanly". Same empty-command green
frankuser hit with `$b` and no `./`.)

### Gate

`make compiler/pascal26` — `converged after 1 round(s)`, `f9fb672ee109`.
`tools/gate.sh quick` — RED on **one** row, `pinned builds live lib/rtl`
(`mimic_queue :: unknown type: TPyDeque`), which is another seat's builtin
awaiting an owner-only pin and does not involve this diff; the canary's own text
prescribes reporting it and carrying on.
The open-world dispatch family — the rows this arm joins — is green, including
both refusal rows it could have broken (`nilpy_open_world_kwarg_fail`,
`nilpy_open_world_arity_fail`) plus `open_world_method_dispatch`,
`open_world_keyword_dispatch` and `arity_four_dynamic_call`.
`make test-nilpy` was attempted THREE times and killed by the box's memory
reaper every time, never by a test — 541 ok rows and zero failures at the
furthest point (a 9GB `python3` belonging to another seat was resident). Stated
as an unfinished tier, not as a green one.

## Log
- 2026-09-11 — resolved, commit 8de1fff93. The FIX is that commit; the ticket was
  moved to `done/` in it too, so close and fix are the same sha here.
