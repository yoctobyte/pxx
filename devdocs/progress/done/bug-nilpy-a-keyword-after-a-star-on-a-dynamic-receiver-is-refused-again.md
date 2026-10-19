---
track: N
prio: 30
type: bug
---

# A keyword after a *unpack on a run-time dispatched receiver was refused again

Found 2026-10-19 in the full row sweep. `test_nilpy_a_keyword_argument_after_a_star_unpack`
(fixed 09-12 in d220115cf3) stopped compiling: `pick(True).n(*xs, forced=9)`
gave "dispatched at run time, and that path cannot combine *unpacking with
keyword arguments yet". Bisected to d4e33b4a83 (10-10). That commit sent star
calls on an ambiguous receiver to `pydyn_methl` so they bind on the run-time
class, and it refused a keyword beside the star there. Nobody saw it because
the recipe was stopping at row 593.

**Fix:**
- Parser: when the keywords are a trailing run, the kwspec names only that run,
  marked `>`. Any other mix still refuses, with a message that says why.
- `PyDynMethL` right-aligns a `>` kwspec once the star's length is known.
- `PyBindHostKwArgs` fills a slot that a keyword skips (`*xs, x=9` past a
  defaulted `c`) from the callee's signature defaults. It used to refuse this
  with "can only omit TRAILING parameters". A slot with no default is still
  refused.

Test: `test_nilpy_a_dynamic_star_call_takes_trailing_keywords` (CPython output).
