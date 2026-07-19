---
track: A
prio: 60
type: feature
---

# Variant-returning functions (hidden-dest ABI) + variant bool printing

Filed by the N-lane agent, self-resolved (sole-A confirmed this session).
Functions returning Variant had NO return convention (pylib TPyList.get/pop
are the first): tyVariant added to RetViaHiddenDest, so 16-byte variant
results ride the same caller-owned hidden-destination path as records —
every existing call/prologue/epilogue site keys on that predicate.
IRLowerAddress accepts variant-returning AN_CALL/AN_VIRTUAL_CALL (the call's
IR value IS the dest address), covering writeln args and assignment sources.
EmitWriteVariant gains a real VT_BOOL branch: True/False (Python spelling,
matches FPC's writeln(Variant-bool) rendering; old behavior printed 1/0).
Stale '1' expectations updated: test_variant.pas, test_nilpy_variant,
test_nilpy_local_variant. x86-64 only — cross-backend variant writers still
print bools as ints (Track T will surface; noted here).
Resolved with [[feature-nilpy-list]].
