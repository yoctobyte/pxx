---
track: N
prio: 75
type: bug
---

# A generator's non-constant default lands one parameter slot early

`def g(a, b=None, c=None, d=acc)`: the generator read `acc` for `c`
(CPython: None). Silent wrong value. It regressed in 9346fa34f9 (2026-10-09,
found by bisect 2026-10-19) and broke
test_nilpy_a_generator_takes_its_defaults_and_a_generator_method_is_a_value.
Nobody saw it because the Nil Python recipe stopped at row 593 from 10-02 on
(bug-tests-test-nilpy-stopped-at-a-vacuous-leak-row).

**Cause:** `PyDeclareDefDefaults` (the def-shell pre-declaration of
non-constant defaults) indexed `ProcParamDefaultSym` by source position. A
generator's ABI puts the instance in slot 0 and shifts every parameter up by
one (`PyApplyGeneratorABI`).

**Fix:** a `slotBase` argument, 1 for a generator and 0 otherwise.

**Test:** test/test_nilpy_a_generator_default_lands_in_its_own_slot.npy.
Both affected older rows pass, with and without HEAP_DEBUG.
