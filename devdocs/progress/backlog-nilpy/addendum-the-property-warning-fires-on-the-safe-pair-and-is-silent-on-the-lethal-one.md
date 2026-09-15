# Addendum: the property warning fires on the SAFE pair and is silent on the lethal one

Untracked, filed by the lekkerzeilen seat. Addendum to
`bug-n-the-property-conflict-warning-misses-five-of-eight-conflicts-including-the-one-that-crashed.md`,
which is now tracked, so this is a separate file rather than an edit to it.

## What prompted it

Building the demo emits:

    pascal26:351: warning: Nil Python: several unrelated classes declare a
    .spawn property -- reading it through the receiver at run time

`.spawn` is in the DETECTED set. `.flow` -- the one that actually crashed the
demo -- was in the MISSED set. That pairing is worth recording, because it is
not just a recall problem.

## The two conflicts side by side

Both pairs are the same two classes, `Region` and `World` in
`/home/neo/lekkerzeilen/lekkerzeilen/world.py`, and both are read through the
same genuinely polymorphic receiver:

    app.py:641   self.scene = self.world if self.world is not None else region

`.spawn` -- WARNED, and provably harmless:

    world.py:278  (Region)  return (self.number("spawn_x"), self.number("spawn_z"),
                                    self.number("spawn_heading"))
    world.py:1064 (World)   return (self.number("spawn_x"), self.number("spawn_z"),
                                    self.number("spawn_heading"))

Identical bodies, and `number()` is declared on both (world.py:249, world.py:1044).
Whichever class the receiver turns out to be, the caller gets the same 3-tuple.
There is nothing here to get wrong.

`.flow` -- NOT warned, and it crashed:

    world.py:343 (Region)   fx, fz = self.grids.get("flow_x"), self.grids.get("flow_z")
                            return (fx, fz) if fx and fz else None
    world.py:1272 (World)   return (self.grid("flow_x"), self.grid("flow_z"))

Different RETURN CONTRACTS. Region may return `None`; World always returns a
2-tuple, because `World.grid()` (world.py:1259) constructs a `TiledGrid` wrapper
unconditionally and never returns None. So a caller guarded with
`if flow is None` has that guard fire on Region and never fire on World.

**Corrected after checking the demo: this does NOT currently misbehave, and my
first draft of this file said it did.** The package has exactly one consumer,
`Environment.current()` (environment.py:72), and the World path is absorbed
downstream: `TiledGrid.at()` (world.py:948) returns the caller's `outside`
value when the named grid is absent, and `current()` passes `outside=0.0`. So
Region-without-flow yields `_ZERO` and World-without-flow-grids yields
`Vec3(0.0, 0.0, 0.0)`. Same answer by a different road. The comment on that arm
-- "The caller wants a number, not an exception" -- says the defence is
deliberate.

What survives is narrower and still worth the compiler's attention: the two
properties have genuinely different contracts, and the demo is safe only because
a THIRD piece of code happens to be defensive. Nothing in the property pair
enforces that, and the next consumer of `.flow` inherits the mismatch without
the warning that would have flagged it.

## The point

The discriminator between a benign property conflict and a dangerous one is not
whether two classes declare the same name. It is whether their bodies agree in
what they can RETURN. The current check appears to be keyed on the former, which
is why it can be simultaneously noisy and incomplete:

  - it fired on the pair whose implementations are textually identical
  - it stayed silent on the pair whose return contracts disagree

That combination is worse than either failure alone. A warning that cries on the
harmless case trains the reader to skip it, and the one it skipped was the one
that took the demo down.

## Suggested shape, offered not prescribed

Rank the conflict rather than reporting its existence: compare the declared
return shapes of the conflicting bodies and stay quiet when they agree. Even a
crude approximation -- "one arm can yield None and the other cannot" -- would
have inverted both of these results, which is the whole of the complaint.

Not verified against the compiler; I have not read the check. Compiler seat's
call entirely.
