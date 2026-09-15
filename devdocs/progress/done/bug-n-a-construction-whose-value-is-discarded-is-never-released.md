---
type: bug
track: N
prio: 70
status: done
slug: bug-n-a-construction-whose-value-is-discarded-is-never-released
---

# `P(1, 2)` as a bare statement never released the instance

A construction whose value goes nowhere leaked it, one instance per execution,
forever. CPython drops it at the end of the statement.

Measured 2026-09-15, 12000 iterations, CPython as oracle:

| shape | pxx before | pxx after | CPython |
|---|---|---|---|
| `P(1, 2)` discarded | **56 bytes/call** | 0 | 0 |
| `p = P(1, 2)` bound | 0 | 0 | 0 |

The bound row is the control and it says the class itself is fine: it is the
DISCARD that leaks, not the construction.

## MECHANISM

A NilPy construction is lowered through a conduit local that holds its rc=1
*"for whoever consumes the expression and never releases it"*
(`SymIsCtorResultTemp`, `compiler/defs.inc:4401`). Every consumer that works --
an assignment, an argument bind, a container store, a return -- takes that rc=1
off it. A discarded statement has no consumer at all, so nothing ever does.

## FIX

`PyParseStatement`'s expression-statement tail: when the statement IS a
user-class construction, bind it to a hidden `tyClass` local. That is the same
ownership the assignment spelling already has, and `PyClassSymArcEligible` has
no name filter, so the temp gets rebind-release and scope-exit release like any
other NilPy class local.

**In a loop the slot is reused**, so iteration N+1's store releases iteration
N's object and only the last one waits for scope exit -- bounded, not merely
deferred. That is why a 12000-iteration fixture reads 0 rather than 56/12000.

**NOT released at end of STATEMENT**, which is what CPython does and what a
reader will ask for. That needs a release the lowering has no place to emit, and
it would be the arg-spill mistake again in a new position: what makes this safe
is precisely that the object outlives every borrow taken during the statement.

## THIS IS ONE ROW OF A FAMILY AND THE REST IS OPEN

See `bug-n-a-freshly-allocated-value-whose-result-is-discarded-is-never-released`
for the method and container spellings, which this fix does NOT cover and which
must NOT be fixed the same way -- a parser-level rule cannot tell a fresh result
from a borrowed one, and three of lekkerzeilen-c8's measured rows return
borrowed references and are already clean.

## FIXTURE

`test/test_nilpy_a_user_object_does_not_leak_because_of_how_its_value_is_consumed.npy`,
row `ctor_discard`, beside `ctor_bound` as its control. Verified to FAIL on a
pre-fix compiler (72 bytes/call) and pass after, with CPython agreeing.
