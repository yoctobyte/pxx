---
track: N
prio: 40
type: bug
status: backlog
---

# A Nil Python generator instance leaks its locals and its argument cells

A deliberate trade made in [[feature-nilpy-yield-outside-a-for-loop]], recorded
here rather than left to be rediscovered as a mystery.

## What leaks, and why it was traded

**The locals.** A stackless generator's step function returns at every `yield`
and is re-entered at the next one, so its locals are NOT going out of scope —
they are the generator's live state, checkpointed into the heap instance. The
epilogue used to release them anyway, which freed the objects the instance still
pointed at; the symptom was silent and bad (a generator walking `for t in xs`
got a dangling list on its second step and the loop simply ENDED, one element
in). `EmitManagedLocalCleanup` now exits early for a stackless routine. The
references are therefore dropped when the instance is freed — which is to say,
not at all.

**The argument cells.** A Nil Python variant parameter is by-ref, so the
instance slot holds an address that must outlive the loop. The for-in desugar
allocates a 16-byte `pycell_new` per variant argument and never frees it
(`GenMakeVariantArgCell`, parser.inc).

Both are **one-off per generator instance** — not per yield, not per step — so a
loop that runs a million times leaks nothing extra. A pipeline that creates a
million generators leaks a million small blocks.

## The shape of the fix

`SlFree` already runs at the end of the for-in desugar and knows the instance.
What it does not know is which slots hold managed values. Give it that — a
per-proc map of which persistent slots are variant / class / string — and the
release becomes a loop at instance teardown, which is also where a proper
generator OBJECT (see [[feature-nilpy-a-generator-as-a-first-class-value]])
would want it. Doing both at once is probably cheaper than doing either.

Note the ordering constraint that made this a trade in the first place: the
frame copy and the instance copy of a value are bitwise duplicates, and exactly
one of them is live at a time. Any release has to be at teardown, not at step
exit, or it re-creates the dangling-pointer bug this replaced.
