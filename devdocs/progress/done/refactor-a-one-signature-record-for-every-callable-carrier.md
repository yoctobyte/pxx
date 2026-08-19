---
track: A
prio: 66
type: refactor
blocked-by: []
summary: "Four dispatchers and TWO independent defaults mechanisms serve one concept. Put the PySig record on the boundfn carrier and DELETE pyboundfn_setdefaults, so every callable shape answers signature questions from one place. Filed as work because it was banked as a note at the bottom of a resolved ticket, where ready/next cannot see it."
status: done
owner: frank2-A
---

# One signature record for every callable carrier

> **RESHAPED 2026-08-19, after frank2 landed steps 1 and 2 (`9e711a681`). This ticket is
> now step 3 alone, it got materially CHEAPER, and it gained a second motivation.**
>
> **Cheaper:** the PYSIG record already carries code, `ReqN`, `TotN`, `Star`, `Dflts` and now
> `Names` (`PYSIG_SIZE` 40 -> 48). Putting `Sig` on the boundfn carrier and deleting
> `pyboundfn_setdefaults` is therefore a **port onto an existing structure, not a design**.
> The ordering argument in this ticket held: step 3 was correctly refused first, because the
> record was still missing the field the carriers would need.
>
> **The new motivation, which is the more important half.** frank2 gave a carrier with no
> names a **named refusal** rather than a wrong answer — today only the tag-8 pair has a
> signature. That was the right call (a silently dropped keyword would bind the default and
> return something plausible), but it means there is now a *reachable diagnostic* standing in
> for a feature. **Completing this ticket turns that refusal into a correct answer for every
> callable shape.** So it is no longer only a tidy-up that deletes a mechanism; it closes a
> user-visible gap. Re-rank accordingly when the queue reaches it.
>
> Two design decisions from `9e711a681` that constrain how the port must behave, both worth
> preserving rather than rediscovering: keywords bind to positions **first**, then remaining
> holes fill from defaults (that order is the only reason writing a keyword beats a default);
> and the missing-required-argument count is recomputed **after** keyword binding rather than
> trusting the positional count, because a keyword can supply a required parameter
> (`r(a=1, b=2)`).

**Filed 2026-08-19 by the coordinator at frank2's request, who banked the finding while
resolving p88 and then confirmed on measurement that it wants its own sitting.**

## Why this is a ticket and not a note

It was already written down — at the bottom of
[[feature-n-a-callable-value-carries-its-signature-type]], resolved, in `done/`. A
conclusion parked in a closed ticket is invisible to `ready`/`next`, so it gets
rediscovered rather than done. That is the same failure this repo has recorded repeatedly;
the fix is a queue entry with a `track:` and a `prio:`, which is the only thing the ranker
reads.

## The finding, in frank2's words

> **Count the mechanisms before extending this.** There are now four dispatchers for one
> concept — `pybound_callv*`, `pycallback_call*`, `PyCallKey1`, `pyvar_callv*` — and two
> independent defaults mechanisms. The signature record this ticket built is the general
> one; the honest next step is to put `Sig` on the boundfn carrier too and DELETE
> `pyboundfn_setdefaults`, rather than teach a fifth path the same trick.

Four mechanisms for one concept is past the threshold this repo already names: two is a
smell, three is a design flaw. The second defaults mechanism (`pyboundfn_setdefaults`)
fires for the **nested** def form and not the module-level one, which is exactly the kind
of split that produces a bug on one arm and a working sibling on the other.

## Why it is Track A, despite being NilPy-facing

It touches `compiler/ir.inc` and `compiler/builtin/pyeval.pas` — shared internals and a
builtin RTL source. Two consequences:

- Gate is Track A's: `make compiler/pascal26` (the fixedpoint) + `tools/gate.sh quick`.
- **A `compiler/builtin/**` change needs `make stabilize-fast && make pin` before the
  fixedpoint gate reflects it.** Landing it without the pin leaves the frozen builtin
  sources and the compiler disagreeing.

## Why it is blocked, and the ordering is not negotiable

Do **not** start before
[[bug-n-a-keyword-argument-through-a-callable-value-is-undefined]] lands. frank2's measured
recommendation:

1. extend PySig with parameter **names**,
2. lower a keyword argument at a callable-value call site into a name/value pair the
   dispatcher can match,
3. **then** put `Sig` on the boundfn carrier and delete `pyboundfn_setdefaults`.

Steps 1 and 2 are the blocking ticket. Step 3 is this one, and it gets **cheaper** after
them, because by that point the record is the obvious single source for every signature
question and the deletion is subtraction rather than a migration. Attempting the
consolidation first means migrating carriers to a record that is still missing the field
they will need.

## Gate

Track A's: fixedpoint + `gate.sh quick`, then `stabilize-fast` + `pin` for the builtin
change. Success is measured in **mechanisms deleted**, not lines: `pyboundfn_setdefaults`
gone, and the nested and module-level def forms answering defaults from the same place.

## Log
- 2026-08-19 — filed. Blocked on the keyword-names work by design.

---

## Resolution (frank2-A, 2026-08-19, on top of 9477001a8)

**Done: the tag-10 carrier reads the same signature record as the tag-8 pair, through
the same lookup, and the reachable refusal is closed.**
**Not done, and deliberately: `pyboundfn_setdefaults` stays.** The ticket's own
success measure ("mechanisms deleted") is not achievable as written, for a reason that
is a property of the language rather than of this code — see "Why the deletion is
wrong" below. That is the one place this resolution departs from the ticket.

### The carriers, ENUMERATED from `defs.inc` rather than counted from memory

| tag | carrier | signature before | after |
| --- | --- | --- | --- |
| 8 `VT_BOUNDMETHOD` | `{code, recv}` pair (`pybound_new`) | `Sig` | `Sig` (unchanged) |
| 9 `VT_PYCLOSURE` | interpreted pyeval source closure | none | none — no compiled proc to take a record from |
| 10 `VT_BOUNDFN` | lifted lambda / nested def | none | **`Sig`, this change** |
| 11/12/13 `VT_CLASSREF` / `VT_CALLABLE` / `VT_BTYPE` | a static address | none | none |

Four, not three. `VT_BOUNDMETHOD = 8` (`defs.inc:683`) is the one a count from memory
drops, and it is the carrier that already had the record — so a wrong count would have
had the port migrating the wrong side.

### What landed

- `compiler/builtin/pyeval.pas` — `TBoundFnObj` gains `Sig`; `pyboundfn_setsig` sets it;
  `pyboundfn_callvn` becomes a wrapper over a new `pyboundfn_callvn_mask`, which takes the
  caller's **supplied mask** so a HOLE below `nargs` keeps its own default
  (`g(1, c=9)` must leave `b` alone); `PyBoundFnCallKw` is the tag-10 keyword dispatcher;
  `pyvar_callv_kw` routes to it.
- `compiler/builtin/pylib.pas` — `PySigFindParam` exported, and
  `pybound_pair_call_kw`'s open-coded name walk **deleted** in favour of it. That is the
  mechanism this refactor actually removes: one record, one way to ask it a name, rather
  than a second copy of the walk becoming a third.
- `compiler/pyparser.inc` — both creation sites chain `pyboundfn_setsig` with an
  `AN_PYSIGREF` node (the lambda lifter passes `lamProc`, the nested-def path `procIdx`);
  `compiler/ir.inc` + the two `pyparser.inc` allow-lists learn the new setter so the chain
  still boxes as a callable.

Both design decisions from `9e711a681` are preserved verbatim in the new dispatcher, and
the code says so at the point where each matters: keywords bind to positions **first** and
holes fill from defaults after; the missing-required count is computed **after** keyword
binding, not from the positional count.

### Why the deletion is wrong — the line between the two mechanisms

The record holds **one static array per proc**. A lambda's default is captured **per
instance**:

```python
def mk(k):
    g = lambda x, y=k: x * 100 + y
    return g
mk(1)(5)   # 501
mk(7)(5)   # 507
```

Two live closures over one proc, whose `y` defaults differ. `Dflts` cannot express that,
so deleting `pyboundfn_setdefaults` would regress it — the bound slots are the only place
a per-instance default can live. What IS static per proc is the parameter **names**, and
that is exactly what this change takes from the record.

So the split the ticket read as "two mechanisms for one concept" is really two concepts
that were not named apart: **names are compile-time, these defaults are run-time.** The
consolidation that was available is the one that landed (one record, one lookup); the one
the ticket asked for is not available at all. Recorded here rather than half-done.

Note the record also names the CAPTURES (they are real parameters of the lifted proc), so
the dispatcher clamps the visible window to `NDefBase + NDef` — naming a capture is an
unexpected keyword, which is what CPython answers.

### Measured against CPython

```python
def use(g):    return g(y=5, x=6)
def use_hole(g): return g(1, c=9)
f = lambda x, y=2: x * 10 + y ;         print(use(f))       # 65
t = lambda a, b=20, c=300: a*10000 + b*100 + c ; print(use_hole(t))  # 12009
```

On the pinned compiler both raise
*"a keyword argument through this kind of callable value is not supported yet"*. At this
sha both match CPython, and so do every error shape:

| call | CPython | pxx |
| --- | --- | --- |
| `g(zz=1)` | unexpected keyword argument 'zz' | same classification |
| `g(1, a=2)` | multiple values for argument 'a' | same |
| `g(b=5)` (a required) | missing 1 required positional argument | same |
| `g(cap=1)` (a capture) | unexpected keyword argument | same |

Regression test: `test/test_nilpy_kwarg_through_lifted_value.npy`, enumerated in
`test-nilpy` and `test-core` (a `.npy` the Makefile does not name is uncovered forever).

### Gate

`make compiler/pascal26` converged in 1 round; `tools/gate.sh quick` GREEN
(self-host fixedpoint + testmgr quick + FPC seed canary).

**No pin.** The ticket's gate section calls for `stabilize-fast && make pin` because
`compiler/builtin/**` changed, and that is right — until the pinned compiler moves, a
NilPy program built with `PXX_STABLE` still meets the old refusal. The pin is being held
deliberately (owner's call, morning, awake), so **this ticket lands its code and the pin
follows separately**; that is the one outstanding step and it is not a defect in the work.

### Found while probing, filed, NOT fixed here

Two NilPy-frontend bugs, both reproducing on the pinned compiler and both unrelated to
this refactor:

- [[bug-nilpy-a-lambda-returned-directly-is-not-callable]] — `return lambda x: ...`
  yields a value that is not callable at all, while `g = lambda ...; return g` works.
- [[bug-nilpy-a-keyword-call-through-a-statically-unknown-callee-does-not-compile]] —
  `a = mk(1); a(x=5)` is a COMPILE error ("undefined variable (x)"), because the keyword
  lowering is gated on the frontend resolving a candidate callee. The runtime side this
  ticket built handles that call correctly; some sites just never reach it.

Track N owns both; filed rather than fixed, per the lane rules.

## Log
- 2026-08-19 — filed. Blocked on the keyword-names work by design.
- 2026-08-19 — **resolved** (frank2-A). Tag 10 carries `Sig`; `pybound_pair_call_kw` and
  the new tag-10 dispatcher share `PySigFindParam`. `pyboundfn_setdefaults` KEPT — the
  reason is a language property, written up above. Pin deferred by owner's instruction.
- 2026-08-19 — resolved, commit 186ac6f7d.
