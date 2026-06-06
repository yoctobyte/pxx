# By-value record args >8 bytes truncate (and operator operand edges)

- **Type:** bug
- **Status:** done
- **Owner:** Antigravity
- **Opened:** 2026-06-06 (surfaced while fixing bug-operator-result-inferred-var)

## Symptom

The record-by-value **argument-passing** path mishandles records larger than a
machine word, and operator operands in a few shapes:

- **By-value record param > 8 bytes truncates.** A `function add3(a, b: TR3): TR3`
  with `TR3 = record A, B, C: Integer end` (12 bytes) loses the 3rd field:
  `add3(p,q).C` is garbage. Same for a record-by-value operator param. (Already a
  documented limitation — `const` record params are passed by reference for
  exactly this reason; `docs/dialect.md` "Parameter Passing Notes".)
- **`const` operator params segfault.** `operator + (const a, b: TR3): TR3` then
  `r := p + q` segfaults — the operator call lowering passes operands by value
  and ignores `const`-by-ref.
- **Operator result reused directly as an operand is garbled.** `a + b + a`
  (8-byte `TVec`) prints garbage: the intermediate record result fed as an
  operand goes through the same by-value arg path.

## Why grouped

All three are the **record-by-value argument** path, distinct from the operator
*result* path fixed in `bug-operator-result-inferred-var` (2cf92fb). The 8-byte
direct result case works; these need records passed by reference (with a callee
copy when by-value semantics are required).

## Scope

- Pass record value-params > 8 bytes by reference (hidden pointer), matching the
  aggregate ABI used for returns; honor `const` operator params by reference.
- Make an operator-result temp addressable so it can feed the next operator.

## Acceptance

`add3(p,q)` (12-byte by-value), `const`-param operators, and `a + b + a` all
produce correct results; self-host fixedpoint holds. Extend
`test/test_op_record_result.pas` with the >8-byte and chained cases (currently
omitted with a note).

## Log
- 2026-06-06 — ticket opened from the operator-result fix investigation.
- 2026-06-06 — claimed by Antigravity; working on implementation.
- 2026-06-06 — implemented parameter reference matching and chained operator temporary loading; fixed-point self-host verified and tests added.
