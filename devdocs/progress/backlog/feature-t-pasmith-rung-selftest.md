---
track: T
prio: 35
type: feature
blocked-by: []
summary: "A fuzz rung that has only ever been SILENT is indistinguishable from one that does not work. Proposes a --selftest that proves each rung's fold actually observes its construct, by MUTATING the generated program rather than by rebuilding an old compiler — cheaper, needs no checkout, and applies to rungs that were never written against a specific fix."
---

# pasmith: prove each rung can still see the bug it was written for

- **Type:** feature (fuzz tooling — Track T owns the tool)
- **Opened:** 2026-08-16
- **Origin:** a dev session working the Pascal oracle sweep, after two rungs
  in a row were validated
  *by accident* — both times by running the differential against a compiler
  binary built before the fix the rung targeted, and finding it fired.

## The problem, stated plainly

> A rung that has only ever been silent is indistinguishable from one that
> doesn't work.

Every green sweep is consistent with two very different worlds: the compiler is
correct, or the rung stopped observing its construct. Nothing in the harness
distinguishes them. And rungs rot quietly — a probability tweak, a refactor that
drops a fold, a generator knob defaulting to 0 — all produce a rung that emits
nothing and reports clean forever.

Two real data points, both from 2026-08-16, both accidental:

| rung | pre-fix binary | post-fix |
| --- | --- | --- |
| `forvarlimit` / `formaxlimit` | 23 divergences | 0 |
| `consts` | probe DIFFERED | AGREE |

Neither was planned. Two accidents is two more validations than most fuzzers
ever get, and it should not take an accident.

## The proposal, and the cheaper alternative I recommend

**As proposed:** record the parent sha of the fix a rung targets, and give
`--selftest` a mode that builds that sha's compiler once and asserts the rung
produces non-zero divergences against it. If it ever goes quiet against its own
parent, it has rotted.

That is exactly right about the *goal*. The cost is the mechanism: building an
arbitrary old sha means a checkout plus a full FPC-seeded bootstrap, minutes per
rung, in a clone other agents are working in — and it only covers rungs written
against a specific landed fix, which is a minority of them.

**Recommended instead: mutate the PROGRAM, not the compiler.** The question a
selftest needs to answer is *"if this construct held a wrong value, would the
checksum notice?"* — and that can be asked by corrupting the generated source
and compiling both with the CURRENT compiler.

Prototyped, on the `consts` rung, simulating the exact defect
(`const C: double = 3` storing `0.00`):

```
  kc0: double = 30;   ->  15330008813825973117
  kc0: double = 0;    ->   4448751675484099592     DIFFER, so the fold sees it
```

Two seconds, one compiler, no checkout, no old binary. And it applies to every
rung, including the many that were never written against a particular fix.

## Where value-mutation is NOT enough, and what to do there

Worth writing down, because it is the interesting half and a naive
implementation would paper over it.

Value mutation works when the fold observes a **value** (`consts`, `checked`).
It does not work for a rung whose observable only differs under *buggy
semantics* — `forvarlimit` is the case. Mutating the seeded limit changes the
trip count under a correct compiler too, so the test would pass without proving
anything about re-evaluation; and mutating the decrement away is invisible by
construction, because a correct compiler evaluates the limit once and ignores
it. That is the whole point of the rung.

For those, the right mutation is a **semantic twin**: emit, alongside the `for`
loop, a hand-written `while` loop that re-reads the limit each iteration — i.e.
the buggy semantics, spelled out in source that any correct compiler will honour
— and assert the two produce DIFFERENT checksums. If they agree, the fold could
not have distinguished the bug from the fix, and the rung is not doing its job.

So the mode has two kinds of check, and each rung declares which it uses:

- `value`: corrupt a literal the fold reads; expect a different checksum.
- `twin`: emit the buggy-semantics equivalent; expect a different checksum.

Both answer the same question and neither needs an old compiler.

### The rule for choosing between them

Generalised from the two cases above, and it is the whole design in one line:

> **A rung whose bug is about WHAT VALUE something holds takes a `value`
> mutation. A rung whose bug is about WHEN something is evaluated takes a
> `twin`.**

`consts` is a what-value bug — the evaluator stored `0.00` — so corrupting the
literal reproduces it exactly. `forvarlimit` is a when-evaluated bug — the value
is right every time it is read, the defect is that it is read at all — and no
corruption of a value can express that, because a correct compiler and a buggy
one agree about every value in the program. Only a second program that spells
out the other evaluation order can separate them.

Applying the rule to the rungs that exist today:

| rung | bug is about | kind |
| --- | --- | --- |
| `consts` | what value the evaluator stored | `value` |
| `checked` | whether the check fired at all | `value` (corrupt the operand so it cannot overflow) |
| `forvarlimit` | when the limit is evaluated | `twin` |
| `formaxlimit` | when the loop stops | `twin` |

## Also worth having: the cheap structural check

The commonest rot is simply that a rung stops emitting. That needs no compiling
at all — generate N seeds, assert the rung's marker appears at least once, fail
loudly with the seed count if not. It is nearly free and catches the failure
mode that a probability tweak or a `--wide` list edit introduces. Run it in
`--check`, which is already the generator's own gate.

## Acceptance

- `pasmith_run.py --selftest` reports per-rung PASS/FAIL and exits non-zero on
  any failure.
- Every rung with a fold declares a `value` or `twin` mutation; a rung with
  neither is reported as UNPROVEN rather than silently passing — an unproven
  rung is the thing this ticket exists to make visible.
- The structural check runs in `--check` and names the rung and the seed count
  when a rung emits nothing.
- Deliberately NOT required: building an old compiler. If someone later wants
  the parent-sha check for a specific rung, it composes — but it must not be the
  price of having a selftest at all.

Related: [[feature-pasmith-real-const-rung]], [[feature-pasmith-for-limit-rungs]],
[[feature-pasmith-divergence-signature-granularity]] (the same theme one level
up: a signature that names the wrong thing is a finding you cannot act on; a
rung that observes nothing is coverage you do not have).

## Considered and DECLINED as a rung: `2 ** 0.5` vs `math.sqrt(2)`

Raised alongside this ticket, so recording the decision rather than leaving it
to be re-proposed. NilPy's fractional-exponent arm is still `exp(y*ln(x))` while
`lib/rtl/math.pas`'s `Power` was fixed for that exact case with a double-double
kernel, so the two disagree by about one ulp. It is filed as a Track B bug.

**It is a poor fuzz target and should not become a rung.** Detecting a one-ulp
difference requires an exact-equality fold, and this generator's standing rule is
that a fold must not be able to manufacture a divergence nobody owns. Exact
float equality is the most hair-trigger fold available: it fires on any
legitimate libm variation, any formatting choice, any reassociation a backend is
entitled to make. That is the same trap [[feature-pasmith-real-const-rung]]
sidesteps by folding real constants through a COMPARISON BRACKET rather than by
value — and a bracket, by construction, cannot see one ulp.

So the property that makes the bug interesting is exactly the property that
makes it unfuzzable here. A targeted unit test with a recorded expected value is
the right instrument; a differential generator is not.
