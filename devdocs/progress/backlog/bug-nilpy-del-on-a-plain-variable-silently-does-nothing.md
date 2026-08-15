---
track: N
prio: 30
type: bug
summary: "NilPy: `del x` on a plain variable is accepted and does nothing — the name stays bound, so reading it afterwards returns the old value where CPython raises NameError. `del lst[i]` and `del d[k]` are correct."
---

# `del x` on a plain variable is a silent no-op

- **Type:** bug (silent semantic divergence) — **Track N**
- **Found:** 2026-08-06, bughunting with `tools/pydiff.py`.
- Low priority: `del` on a bare name is uncommon, and the container forms —
  which are the ones real code uses — are correct.

## Measured (self-hosted at `54fbd2754`)

```python
x = 5
del x
print(x)            # CPython NameError    pxx 5

s = "hi"
del s
print(s)            # CPython NameError    pxx hi

lst = [1, 2]
del lst
print(lst)          # CPython NameError    pxx [1, 2]

def f():
    y = 7
    del y
    return y        # CPython UnboundLocalError    pxx 7
print(f())
```

Module scope and def scope behave the same. No diagnostic in any case — the
statement parses, compiles, and has no effect.

The container forms are correct and must stay so:

```python
lst = [1, 2, 3]; del lst[1]; print(lst)      # [1, 3]      agrees
d = {"a": 1, "b": 2}; del d["a"]; print(d)   # {'b': 2}    agrees
```

## Why it is worth fixing even at low priority

Silence is the problem, not the missing unbind. `del` on a name is written for
one of two reasons: to drop a reference so an object can be collected, or to
make a later accidental use fail loudly. NilPy grants neither, and the second
one inverts: code that used `del` as a guard rail gets the OPPOSITE of what it
asked for, with no sign.

## It survives the upward-compatibility rule — checked

> If code works on CPython, it must work on NilPy. Accepting what CPython
> rejects is a feature, not a defect. (User, 2026-08-06 — see
> `devdocs/dev/nilpy-semantics-divergences.md`.)

Most "we are laxer than CPython" findings are NOT bugs under that rule, so this
one was re-checked against it rather than assumed. It survives, because a
program CPython **accepts and runs to completion** can observe the difference:

```python
x = 5
del x
try:
    print("read:", x)
except NameError:
    print("gone")
```

CPython prints `gone`; pxx prints `read: 5`. Nothing is rejected on either side —
this is a working program giving two answers, which is the definition of the
bug.

## How to land it

**Actually unbind.** It wants a notion of "bound" the frontend does not have
today (a NilPy local is a frame slot, always present), so it likely means a
sentinel plus a check on read — a real cost on every read of any name that is
ever `del`'d, which is why this sits at prio 30 rather than higher.

An earlier draft of this ticket recommended *refusing* `del <name>` outright, on
the general principle that a clear refusal beats a plausible wrong answer. **That
is wrong here** and is struck: `del x` is valid CPython, and refusing it would
break upward compatibility — the one direction that is not negotiable. Refusal
is the right answer for a form CPython also rejects, not for one it accepts.

## Gate

Per-fix loop. A `.npy` test with `del` on a module-scope name, a def-local, and
both container forms (which must stay correct), diffed against CPython — or, if
option 2 is taken, a `{%FAIL}`-style expectation that the bare-name form is
rejected.

## 2026-08-15 — designed, costed, and PARKED with the trap named

Worked the implementation far enough to price it, then stopped rather than
half-apply it. What the ticket says ("a sentinel plus a check on read") is
right; what it does not say is where the cost actually lands, which is the
REBIND, not the read.

**The read hook is cheap and was the thing I expected to be hard.** There is
exactly ONE arm that turns a bare NilPy name into a value — the `AN_IDENT`
construction in `parser.inc` (~4875) — and an assignment TARGET does not reach
it (targets go through `PyAssignTargetSym`). So a guard can be hoisted in front
of the read via the existing `PyHoistStmt` machinery, gated on `PyExprMode`,
for the handful of names a pre-scan finds in a `del <name>` statement. The
`del` arm itself is already isolated and takes an early exit before any
expression parse, so it cannot guard itself by accident.

**The rebind is where it gets decided, and it is a two-way choice with no
obviously right answer** — which is why this is parked rather than guessed:

1. **Hidden "deleted" flag per name.** `del x` sets it, the read guard tests
   it. Then a later `x = 5` must CLEAR it, and a name is bound at all sixteen
   `PyAssignTargetSym` call sites (plain assign, augmented, for-target,
   with-target, unpack, chained, nested…). Miss one and a rebound name raises
   NameError — a **wrong refusal of a valid program**, the one direction
   upward compatibility does not allow. Hooking the resolver itself would emit
   a side effect from a lookup, which is the trial-parse-hoist landmine
   (`project_trial_parse_rewind_leaves_its_hoists_queued`).
2. **Sentinel VALUE in the name's own slot.** `del x` stores an "unbound" tag
   and the guard compares against it. A later `x = 5` clears it for free — no
   store hook at all, all sixteen sites correct by construction. The cost is
   that the name must be a VARIANT to hold the tag, so the pre-scan has to
   force the type of every `del`-able name, and the allocation sites are as
   numerous as the binding ones.

Option 2 is the better shape (it deletes the store-hook problem instead of
managing it) and is what I would build, but forcing a type from a pre-scan
touches how NilPy allocates locals, which is not a change to start at the tail
of a long session.

**Nothing was applied**; the ticket returns to the backlog with the design and
the trap recorded, per `root-cause-over-microfix`'s "bank the diagnosis and
park it, never microfix as a consolation".

One measurement worth keeping: today's behaviour is a silent no-op, so any
partial implementation that raises where it should not is strictly WORSE than
the current bug. That asymmetry is what makes option 2 the safe one and option
1 the one that needs completeness before it is safe at all.

## 2026-08-15 — correction to the parked design: option 2 needs a NEW variant tag

Re-opened it long enough to check the one thing the design above assumed
without measuring: that a sentinel could be spelled with an existing tag.
It cannot.

**`VT_EMPTY` (tag 0) is Python's `None`**, not "unbound" — `defs.inc` calls it
"unassigned slot", which is what misled the earlier note, but every NilPy path
reads it as None: `pynone()` yields it, `x is None` is a VT_EMPTY tag test, a
nil class pointer boxes to it in two codegen sites, a variant global is born
VT_EMPTY *because* that already means None, and `pystr_of` renders it `'None'`.
So storing VT_EMPTY on `del x` would make `del x; print(x)` print `None` — a
different wrong answer, not a fix.

Option 2 therefore costs a **new tag** (`VT_UNBOUND`), which is a bigger change
than "a sentinel value in the slot" sounded: the tag has to be inert in every
consumer that switches on `pyvartag` — see
`project_variant_object_tag_list_lives_in_four_places` for how that list has
already been missed once. It stays the better shape (the rebind clears it for
free) but it is no longer the cheap half of the fork.

Still parked, still prio 30, and the asymmetry from the note above is unchanged
and decisive: today's bug is a silent no-op, so any partial version that raises
where it should not is strictly worse.

## 2026-08-15 (session 3) — two measured facts that change the parked design

Picked it up, measured the two things the parked design assumed, and returned it
without applying anything. Both assumptions were wrong in ways that matter.

**1. The "forcing a type from a pre-scan" worry is unfounded — the pre-scan
already exists.** Session 2 parked partly because "forcing a type from a
pre-scan touches how NilPy allocates locals". It does not need a new pre-scan:
`PyParseDefBody` already runs a **trial typing pass** over the body
(`PyTypingPass := True`, `pyparser.inc` ~23593), rolled back and repeated until
`PyTypingChanged` is false, precisely to infer local types before the frame is
laid out. The `del` arm runs inside it. So `del x` can call
`PyNoteLocalType(name, tyVariant)` during the trial round and the real parse
allocates `x` as a variant for free — no new machinery, no new allocation site.
Measured: `x = 5` is `tk=13` (tyInt64) today at BOTH module and def scope
(`PXXDBG=n.locals`), so the forcing is genuinely required, and this is where it
belongs.

**2. Hoisting the guard in front of the statement is WRONG, and that was the
plan.** Session 2's design put the read guard in front of the containing
statement via `PyHoistStmt`. That raises in places CPython does not:

```python
del x
if flag and x:      # CPython: never evaluates x when flag is False
    ...
```

A hoisted check runs unconditionally, so this raises NameError on a program
CPython runs to completion — the exact "strictly worse than the current silent
no-op" failure the ticket's own closing note warns about. Same for `x if c else
0`, `a or x`, and a read inside a comprehension's filter.

The guard therefore has to be **in-expression**: wrap the ident node so it is
evaluated exactly where the read is. That is architecturally natural — the ONE
read arm (`parser.inc` ~4916) already rewrites its own node in place for NilPy
frame cells (`SymCellPtr` -> `AN_DEREF`), so a wrapper is the same shape. Note
it is **two** sites, not one: `PyMakeIdent` builds the node for the paths that
bypass the ordinary expression grammar, and the comment at the read arm says so.

**Revised cost.** Still `VT_UNBOUND` (session 2's correction stands — `VT_EMPTY`
is None, not unbound). Plus: a pylib guard callable that takes the variant and
the name and either returns it or raises NameError, minding
[[project_variant_fn_return_forward_nrvo_corruption]] (a Variant function return
corrupts under FORWARD — a var-out proc is the safe shape); the wrapper applied
at both ident-building sites; the trial-pass type forcing above.

**Recommendation: leave it at prio 30 and take it as a deliberate half-day, not
as a queue item picked up between other work.** Three sessions have now each
found the previous session's design wrong on one point. The reason it keeps
happening is not that the fix is hard but that the failure mode is asymmetric —
today's bug is silent and harmless, and every wrong version of the fix is a
loud, wrong refusal of a valid program. Nothing applied; back to backlog.
