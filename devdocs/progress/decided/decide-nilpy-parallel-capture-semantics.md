---
track: U
summary: "DECIDE: NilPy parallel for-in capture model — what's private, what's shared, how reductions read"
type: decide
prio: 5
---

# DECIDE — NilPy parallel for-in: private/shared/reduction semantics

- **Type:** decide (Track U — a semantics fork only the user settles).
- **Status:** backlog
- **Opened:** 2026-07-17.
- **Unblocks:** [[feature-nilpy-parallel-for-in]].

## The fork

The shared parallel-for runtime captures loop-body variables **by reference (shared)** —
concurrent writes race (documented, not a heap bug:
[[project_parallel_for_byref_capture_shared_write_race]]; private = function locals /
disjoint slots). Pascal's `parallel for` inherits Pascal's variable model. **NilPy's
variable model differs** — Python variables are function-scoped with late binding, and a
Python programmer's mental model of a `for` loop body is *not* "these vars are shared
across iterations." So NilPy must **choose** a mapping, and the choice is user-visible.

## Options

1. **Iteration-private by default, explicit shared/reduction opt-in** (Python-idiomatic).
   Each iteration gets private copies of body-local names; writing a shared result
   requires either a disjoint index (`out[i] = ...`) or a declared `reduction(op, var)`.
   Matches what a Python user expects; safest. Cost: the lowering must classify names
   (private vs the loop's disjoint-index target vs reduction) and allocate per-worker
   slots.
2. **Shared by reference (mirror Pascal), race is the user's problem.** Thinnest
   lowering — reuse Pascal's model verbatim. But it hands a Python audience a footgun the
   language never had, and "works in the sequential loop, races in the parallel one" is
   exactly the silent-bug class this project hunts.
3. **Restrict v1 to provably-safe bodies** — only allow disjoint-index writes
   (`out[i]`) and declared reductions; reject a body that writes a shared scalar. Compiler
   enforces safety; widen later. Most conservative; smallest correct surface.

## Recommendation

**(3) for v1, evolving toward (1).** Ship the safe subset (disjoint-index +
reduction, reject the rest with a clear diagnostic) — it can't produce a silent race,
matches the runtime's proven-safe patterns, and defers the harder name-classification of
(1) until there's demand. (2) is rejected: a Python-shaped race is a parity trap.

## Also decide (small)

- **Surface syntax:** decorator (`@parallel`), a `parallel for x in …` keyword, or a
  builtin (`parallel(range(n))`). Recommendation: a decorator or `parallel` builtin reads
  most Python-ish and avoids a new statement form.

Resolving this unblocks [[feature-nilpy-parallel-for-in]].

## PARKED — deliberately last (user, 2026-07-20)

Not blocked on any one ticket, and intentionally not given a `blocked-by` edge:
this waits on the whole substrate settling (int/bigint and the object model are
in flux as of this date), and there is no single commit that will say "now".
Revisit when the dust has settled and the picture is clearer — a vague later,
on purpose.

**Do not read the low prio as "small and easy to grab".** The user's framing:
the feature is *trivial to implement* and expensive to live with — it "would
spark bugs under our ass at every clock cycle". The cost is not building it,
it is every latent race it legitimises afterwards, across a language whose
users have never had to think about them (CPython's GIL made `list.append` and
`d[k] = v` effectively atomic; true parallelism removes that, so correct
CPython code silently races). Cheap to add, permanent to own.

Whoever picks this up later: re-read the fork above before writing any code,
and confirm with the user that the substrate is actually settled.

---

## POSTPONED — 2026-08-01 (user), and reclassified

> "3 is totally for later (python does not support anything parallel — nothing
> missed there, just our language feature)."

The important half is the second clause, not the postponement. CPython has no
real parallel `for`, so **this is not a compat gap** — there is no reference
behaviour to match and nothing a Python program expects that NilPy lacks. It is
a pxx language **extension**.

That changes how it should be ranked, not just when. By CLAUDE.md's own
taxonomy, "more than the spec" is the **X tag** (experimental: optional, never a
prio, picked up on user request or for fun) — the mirror image of `compat`,
which is "exactly the spec". Its `prio: 5` was already the right number by
instinct; this records the *reason*, so a later sweep does not read the low
priority as neglect and promote it.

The recommendation in the ticket stands unchanged if it is ever built: option 3
(reject what cannot be proven safe) evolving toward 1. Mirroring Pascal's
by-reference capture stays rejected — a Python-shaped race is a parity trap, and
here there is not even a parity argument to trade against it.

---

# DECIDED 2026-08-11 (user) — take Pascal's solution

> "i suggest to take pascal's solution. same as pascal took python's async."
> — user

Settled in a Track U session that also produced `devdocs/dev/threading-model.md`
(the CPython comparison, the container-integrity contract, monothreaded-as-a-
feature). Read that first; it carries the *why*.

## Surface — Pascal's `parallel for`, transliterated

Pascal's, measured at HEAD:

```pascal
parallel for i := 0 to N-1 do ...
parallel(ParBalanced) for i := ...          { policy preset / lvalue }
parallel(dist pdX, cap N, ...) for i := ... { named-arg policy }
reduction(add: total)                        { clause }
```

NilPy's:

```python
parallel for i in range(n):
    out[i] = i * 3

parallel(workers=4, cap=50) for i in range(n):   # policy, as real kwargs
```

**`parallel` is a SOFT keyword**, exactly as on the Pascal side — where
`test_parallel_policy_lang.pas` deliberately declares `function parallel(x:
Integer)` and asserts it still parses as an ordinary call. NilPy must carry the
same test.

This is the detail that makes the transplant honest rather than a Pascal import:
**Python solved the same problem the same way.** `match`, `case` and `type` are
soft keywords (PEP 634) precisely so `match = 1` keeps working. Both languages
independently needed "add a statement without stealing an identifier" and both
landed on soft keywords, so the mechanism is shared ground, not a borrowing.

Policy gets *more* Pythonic than Pascal's bare-word named args, because Python
has real kwargs. Same clause list carries the reductions, as OpenMP does
(`schedule(static) reduction(+:sum)` in one pragma).

## Capture — BY REFERENCE (shared), and the ticket's own recommendation is INVERTED

The fork recommended option 3 evolving toward option 1 (iteration-private by
default) on the grounds that it is "Python-idiomatic" — that a Python programmer
does not think of loop-body variables as shared across iterations.

**That is backwards. Python has no per-iteration scope.** A `for` body's names
*are* the enclosing function's names — which is exactly why the closure-in-a-loop
gotcha exists and why `i` survives the loop. Iteration-private capture would
**invent a scoping rule Python does not have.**

So Pascal's by-ref capture (`capSi`/`capOfs`, "by-ref via the enclosing frame
pointer") is not the thin-and-dirty option here; it is the **semantically
faithful** one. Option 2 wins — but for the opposite reason it was rejected: not
*"the race is the user's problem"*, but *"shared is what Python's scope rules
already say."*

What carries the safety, instead of a private-by-default model:

1. **Explicit per-loop opt-in.** The soft keyword IS the declaration of intent.
   Nothing is auto-parallelised — the programmer knows when parallelism pays and
   the compiler cannot.
2. **Explicit reduction clause** for the accumulate case (below).
3. **Container integrity** — [[feature-nilpy-threadsafe-containers]], separate
   and independent. Not a blocker for this, not blocked by it.
4. **Documentation** — `devdocs/dev/threading-model.md`.

### One divergence to WRITE DOWN, not discover

**`i` after the loop is meaningless.** CPython leaves a loop variable at its last
value; a fanned loop has no last value. Define it as unspecified and say so in
the docs. Do not quietly leave whatever the last worker wrote.

## Reduction — the op set is fine, the ACCUMULATOR TYPE is the catch

Spelling uses Python's own vocabulary, as kwargs beside the policy:

```python
parallel(sum=total, max=best) for i in range(n):
    total += arr[i]
    if arr[i] > best: best = arr[i]
```

**Op set verified** against `ParseParallelFor`, which accepts `min`, `max`,
`mul`, `+`, `or`, `xor`, `and`. Every proposed name has a home: `sum`→`+`,
`prod`→`mul`, `any`→`or`, `all`→`and`, plus `min`/`max` directly. No runtime gap.

**Keep it explicit — do NOT infer the reduction from `total += x` in the body.**
The augmented assignment is a perfectly good syntactic marker, but float addition
is not associative, so an inferred reduction makes results vary run to run with
worker count. That must be asked for, not received.

### The measurement that scopes v1 (`PXXDBG=n.locals`, pinned)

| variable | inferred kind |
| --- | --- |
| `i` (loop var) | `tyInt64` (13) |
| `best` — assigned, not accumulated | `tyInt64` (13) |
| `fsum` — float accumulator | `tyDouble` (19) |
| **`total` — `total += i`** | **28 — the PROMOTABLE INT family** |

No annotation escape: `a: int = 0` is still 28, and so is `b = b + i` — it is
**any integer accumulator**, not a `+=` artefact. Correct for Python semantics
(arbitrary precision), and it means the commonest reduction lands on the one type
that is not a machine scalar.

A promo-int spills to a heap bignum, and `promocore.pas`'s own header says the
heap tier *"costs a pack/unpack per operation"*, with line 1546 calling the
repack *"profiled as the dominant"* cost. So **every** bignum addition packs,
allocates and unpacks. Under `--threadsafe` each of those takes the global heap
spinlock, so a parallel integer sum does not merely run slow — it **anti-scales**,
workers contending on one lock in a loop whose purpose was to scale. And it is
silent: a small test sum stays inline and looks fine; a production sum spills and
crawls.

**"Promote in advance" was considered and measured out.** It buys nothing —
the heap representation is serialised and repacked per operation, so
pre-promoting only enters the expensive tier sooner. Strictly worse than lazy
promotion.

Pleasant inversion: **float sums are the easy case** (plain `tyDouble`), and so
are `max`/`min`/`any`/`all` on ints, because assignment-style accumulators do not
promote. Only `sum`/`prod` over integers are hard.

### v1 policy — native by default, loud on overflow

The promo-int **inline tier is a native int already carrying the check that
triggers the spill**. So a parallel reduction needs no new arithmetic — it needs
a **policy at the existing spill point**:

- **Default:** the per-worker partial stays in the inline tier; reaching the
  spill point **raises**. A check we already pay for, native speed, loud failure
  instead of a silent cliff.
- **Opt-in:** true arbitrary precision on request, documented as *correct but
  does not scale — the heap lock serialises your workers*. Filed as
  [[feature-nilpy-parallel-reduction-bigint]].
- **Documented as:** "native int, unless you ask for bigint in advance."

**This restriction is free**, and that is a principle rather than a convenience:
CLAUDE.md's upward-compatibility rule runs one direction — if code works on
CPython it must work on NilPy — and **no CPython program contains a `parallel
for`**. Nothing we restrict here can break a working program. This is the one
corner of NilPy where limits cost nothing.

*Load-bearing claim to confirm before relying on it:* "the check is already
there" is read from `promocore.pas`'s header and the
`PROMO_TAG_INLINE`/`PROMO_TAG_HEAP` split, **not** from the emitted code. Verify
the exact hook first.

Aligned with where promo-int is already going: the same header names *"stage 4's
check elision and range analysis"* as what restores native speed for values that
never leave the inline tier. A reduction accumulator is exactly such a value, so
the two efforts pull together.

## Also settled

- **`--threadsafe` required**, mirroring the Pascal error.
- **v1 is `range()` only.** Arbitrary iterables fan by index later.
- **x86-64 only**, because `--threadsafe` is (`builtinheap.pas:1555`). Whether
  that is a hard limit or unfinished work is open — see the threading doc.

## Status

No longer a Track U question. Re-filed as ordinary Track N work on
[[feature-nilpy-parallel-for-in]], which keeps its low prio: the decision is
made, the *parking* stands. The user's framing is unchanged — trivial to
implement, expensive to own — and the X-tag reclassification (an extension, not
a compat gap) still holds.
