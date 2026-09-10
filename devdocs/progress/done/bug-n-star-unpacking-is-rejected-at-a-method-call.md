---
slug: bug-n-star-unpacking-is-rejected-at-a-method-call
track: N
type: bug
prio: 70
status: done
owner: ""
created: 2026-09-10
found-by: frankuser
tags: [nilpy, lekkerzeilen, unpacking]
blocked-by: []
summary: "FIXED 2026-09-10 by frankZ's `f98fd53d7`. `self.mark(*keep)` gave `*unpacking into Places.mark is not supported -- it has parameters with defaults`. PyStarExpandCallArgs, the one central expander behind all five doors, now initialises each optional slot from DefaultArgValueNode and asserts a RANGE arity, so no runtime argument binding was needed -- contrary to what the sibling ticket predicted. Two seats reached this within the hour; the resolution below is the losing one's and carries only what is not in that commit: what the fix does NOT own (the plain-function rows were already green, on a different mechanism), why the `**` sibling is a LARGER job and not the same change, the import-fan-in census artefact, and a test covering the METHOD door that commit's own test has no row for. Unblocked lekkerzeilen/sim.py."
---

# Measured 2026-09-10, compiler `b7745aaf0a59`

`lekkerzeilen/ui.py:414`:

```python
if keep is not None:
    self.mark(*keep)
```

`error: *unpacking into Places.mark is not supported`

# Why this is filed as a sibling and not as a new discovery

`bug-n-double-star-unpacking-is-rejected-at-a-method-call` records `**` being
refused at a method call. This is `*` at the same position. CLAUDE.md's rule is
explicit about this shape: *"Fixed one arm of a double case? Grep for the sibling
before closing."* Filing it separately is how the grep gets done in advance
rather than hoped for.

The right fix is probably one change covering both stars at a method call, and a
fix that lands only one should say in its resolution why.

# RESOLVED 2026-09-10 — the fix is frankZ's `f98fd53d7`

`*unpacking` into a method or a constructor with defaults compiles and runs.
`PyStarExpandCallArgs` — the ONE central expander, five call sites, so every
door is covered by one change — initialises each optional slot from
`DefaultArgValueNode` and overwrites it from the sequence under a `pystar_has1`
guard, and the arity guard's lower bound became `required` instead of `wanted`.
No new pylib builtin, so nothing here is inert until the next pin.

`self.mark(*keep)` at lekkerzeilen/ui.py:414 works. `sim.py` is clean; `rig`,
`traffic`, `vessel` and `ui` each advanced to a different wall.

**Two seats reached this defect independently and inside one hour, and frankZ
landed first.** This resolution is the losing seat's; what follows is only the
part that is not already in that commit. Its own write-up is the record of the
fix.

## The sibling ticket predicted a design boundary. Both seats measured that it was not.

`bug-n-double-star-unpacking-is-rejected-at-a-method-call` says, correctly for
what it could see: *"`*` at a method call is implemented, with a deliberate and
honestly stated limit: it is a compile-time expansion, so it cannot reconstruct
defaults. That is a design boundary, and widening it means runtime argument
binding."* **No runtime argument binding was needed.** The compiler already
constructs a default's VALUE at a call site, every time anyone writes a short
ordinary call, and it already had a run-time length probe next door. The refusal
message was true about `pystar_arg` and false about the compiler, and it stood
for a month because nobody re-measured the thing the message asserted.

## What the fix does NOT own, measured rather than assumed

The pre-fix compiler refuses the added test file at its first constructor row,
so the whole file going red-to-green says nothing about the rows below that
point. Cut down to only the plain-function rows, **the pre-fix compiler runs
them green**. They were never broken:

| door | mechanism | defaults before the fix |
| --- | --- | --- |
| plain function `f(*xs)` | `PyStarMixedForwardCall` → `PyStarForwardCall`, a RUN-TIME dispatch on `len(args)` | already correct |
| method / constructor | `PyStarExpandCallArgs`, a COMPILE-TIME expansion | refused outright |

Two mechanisms for one concept, and only the second was broken
(`devdocs/dev/normalise-dont-special-case.md`). Neither commit's test may quote
a plain-function row as evidence for the fix, and
`test_nilpy_star_unpack_into_a_target_with_defaults.npy` says so in its header.

## The `**` sibling is NOT fixed, and this is why

The double-case rule says a fix landing one arm must say why. It is not one
change, and the table above is the reason:

- `f(**d)` at a plain function call **works**, and has all along, because the
  run-time forwarder takes a positional LIST *and* a keyword DICT.
- `p.go(**d)` and `P(**d)` are `expected expression` — unparsed, exactly as the
  sibling ticket measured, re-measured at `df4aebdbbf51`. The compile-time
  expander has **no dict half at all**, and `PyStarForwardCall(procIdx,
  listNode, dictNode)` takes **no `firstSlot`**: it fills slots from 0, so with
  a method it would bind the receiver's slot out of the argument list and there
  is nowhere to pass the receiver node.

So the `**` doors need a **receiver-aware forwarder** — a `firstSlot` through
`PyStarMixedForwardCall`/`PyStarForwardCall` plus a receiver hoisted into slot
0 — a different and larger change than teaching an existing expansion about
defaults. The sibling's own recommendation (*"the `**` half is the one to fix
first"*) was written before either mechanism was traced; on the measurement it
is the harder half, not the easier one. The trace is appended to that ticket so
whoever takes it does not repeat it.

## The census artefact frankuser asked to have recorded here

**Five modules answered the `*unpacking` error and there were three sites.**
`rig`, `traffic` and `vessel` all reported `pascal26:239` while their own line
239 is blank or unrelated: they are blocked by `sim.py`'s site *through the
import*, and they wear `sim`'s line number. **An error-string census
over-counts by the import fan-in** — anyone counting strings gets 5, anyone
opening the files gets 3. The same artefact is live right now on the
`pascal26:156: error: Variant :=: this scalar type not yet supported` rows in
the same three modules. frankuser hit this while reading a census of mine and
asked for it to be recorded on this ticket; it is the strongest argument yet
for a per-subject report that prints the FILENAME beside every failure, which
would have shown 3 without anyone opening anything.

## Added on top of `f98fd53d7`

`test/test_nilpy_star_unpack_into_a_target_with_defaults.npy` and its Makefile
rows, covering the doors that commit's own test has no row for:

- **A METHOD with a trailing default** — `def mark(self, region, place=None)`,
  which is ui.py:414 and the shape this ticket is named after. That test has a
  constructor row and a plain-function row and no method row, and a method is
  the only door where `firstSlot` is non-zero, so an off-by-one counting the
  receiver would pass every row in it.
- **Defaults of two different KINDS in one signature** (`def sized(a, b=2,
  c="dflt")`), which refuses a None-filler and a zero-filler alike.
- **A computed default** (`def off(a, b=BASE * 2)`).
- **The operand as a list, as a tuple, and as the result of a call.**
- **The ARITY guard in both directions**, in the Makefile because our wording
  differs from CPython's and a CPython-oracled row would be red by
  construction. Nothing else in the tier asserted it. The under-run row is the
  guard against a low bound widened all the way to zero.

## Log
- 2026-09-10 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
