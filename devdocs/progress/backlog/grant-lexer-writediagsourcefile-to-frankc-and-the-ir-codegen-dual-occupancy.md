---
slug: grant-lexer-writediagsourcefile-to-frankc-and-the-ir-codegen-dual-occupancy
track: A
prio: 40
type: grant
status: open
found: 2026-08-30
blocked-by: []
summary: "Two shared-file dispositions the coordinator made on 2026-08-30 and is filing rather than leaving in chat: (1) frankC gets `lexer.inc` bounded to WriteDiagSourceFile, for feature-c-diagnostics-name-the-module-they-are-in; (2) ir_codegen.inc is held by frankA and frankS at once, deliberately, because their edits are in disjoint functions."
---

# GRANT: `lexer.inc` → frankC, bounded to `WriteDiagSourceFile` — plus the `ir_codegen.inc` dual occupancy

Filed because **an authorisation is a finding about what is permitted**, and an unfiled grant
does not read as missing — it reads as *covered*, because a neighbouring ticket covers the
same file. The tooling makes an unfiled TICKET unrepresentable and cannot see an unfiled
GRANT. This is the coordinator applying to itself the rule it spends its day enforcing.

## 1. `lexer.inc` → frankC, bounded to `WriteDiagSourceFile`

For `feature-c-diagnostics-name-the-module-they-are-in` [C p40].

`lexer.inc` is **shared A/P ground** — the one file Track P did not get carved out when
`parser.inc` was sliced into `pasparser_*` — so by CLAUDE.md a Track C ticket may not touch
it and must file a Track A ticket instead. The exception is granted because the change is
genuinely a *single-function* one and the ticket says so: `WriteDiagSourceFile` is "the single
place that decides what to print", and the shape is "when the Pascal table has no answer, ask
the C one".

**Scope, and it is the whole grant:**

- `WriteDiagSourceFile` **only**. Not the lexer's tables, not token numbering, not
  `defs.inc`, not `symtab.inc`.
- **The Pascal arm must be untouched.** It is not enough that Pascal diagnostics still
  work — the C answer is consulted only where the Pascal table returns nothing, so the
  Pascal path must be reachable in exactly the states it was before. A fallback that fires
  one state too early is invisible to every Pascal test that has an answer.
- Anything else `lexer.inc` needs → **Track A ticket, hand off**, as normal.

**Slot check at grant time:** no lane holds `lexer.inc`. frankA is in `symtab.inc`,
`emit.inc`, `exception_emit.inc` and `ir_codegen.inc` on the libc-RTL work; the Pascal
pointer-alias fix landed and is pinned. Verified against the running fleet, not recalled.

**Expires** when the ticket resolves. It is not a standing widening of Track C.

## 2. `ir_codegen.inc` is held by TWO lanes at once, deliberately

frankA (`feature-port-rtl-over-libc`, increment 2) and frankS (xtensa wide-record, spot 3)
are both in this file right now. That is normally the exact hazard the track letters exist to
prevent, and it is being permitted on a **bounded, checked** argument rather than an
optimistic one:

| lane | region | ticket |
| --- | --- | --- |
| frankA | the body of `EmitSyscall` — a single choke point | `feature-port-rtl-over-libc` |
| frankS | the xtensa arm of `EmitParamSpillsForTarget`, all three spots in ONE landing | xtensa wide-record |

The disjointness is a **property of the edits, not of the file**, and it rests on frankA's own
statement that the register rotation goes inside `EmitSyscall` with **no caller changes** — so
the 19 `EmitSyscall` call sites in this file are read, not written. **If that stops being
true, the grant lapses and frankA must say so before touching a call site.** A refactor that
"just also touches" a caller is how this becomes a real collision.

Conditions on both:

- **Land promptly and `pull --rebase` before pushing.** Two disjoint functions in one file
  merge; two disjoint functions in one file over six hours accumulate a third editor.
- **frankS's three spots land together or not at all** — a subset turns data loss into active
  corruption, which arm32's ticket states and frankS measured. That constraint is
  independent of this grant and survives it.

## Why record the dual occupancy as a grant at all

Because the *reason* is what decays, not the decision. A future reader finding two lanes in
one file will see either an oversight or a precedent, and both readings are wrong: it was
permitted for a stated reason, with a stated expiry, and with a named condition whose failure
revokes it. That is the difference between a decision and a habit — and a guard whose stated
reason nobody re-reads is the more dangerous kind (see face 181 in
`feature-a-a-refusal-is-a-claim-with-a-date-on-it`).
