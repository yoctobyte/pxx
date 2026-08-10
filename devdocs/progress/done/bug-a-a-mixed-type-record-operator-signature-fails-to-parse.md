---
track: A
prio: 50
type: bug
blocked-by: []
owner: claude-A
status: done
---

# A mixed-type record operator (`TVec * Integer`) fails to parse — and hid a silent wrong value

- **Type:** bug (wrong refusal, hiding a silent wrong value) — **Track A**
- **Found:** 2026-08-10 by an FPC differential over the operator-overloading
  surface.
- **Pre-existing.**

```pascal
type TVec = record
  x, y: Integer;
  class operator * (const a: TVec; k: Integer): TVec;   { scale a vector }
end;
```

pxx: `error: unexpected token`. FPC compiles it. Every operator was affected —
`*`, `+`, `-` — and every mixed pair, including `(Integer, TVec)` and
`(TVec, string)`. Only the homogeneous `(const a, b: TVec)` form worked.

## Fault 1 — a depth-blind skip

The in-record `class operator` declaration is the SIGNATURE only; pxx keys an
operator on its operand types, so the in-record form carries nothing the
top-level definition does not and is parsed and discarded by **scanning to the
terminating `;`**. That scan did not track parentheses — and a parameter list
separates groups with `;` too. So it stopped INSIDE the parens and left
`k: Integer): TVec;` to be parsed as a field.

`(const a, b: TVec)` has no inner `;`, which is exactly why the homogeneous form
was fine and nobody noticed. Fixed by tracking paren depth and stopping at the
`;` at depth 0.

## Fault 2 — the one this uncovered, and the reason the parse fix could not ship alone

With the signature parsing, this compiles and is **silently wrong**:

```pascal
class operator + (const a, b: TVec): TVec;      { a.x + b.x }
class operator + (const a: TVec; k: Integer): TVec;  { a.x + k*1000 }
...
r := a + 5;   { FPC: 5001.  pxx: 6 }
```

`FindOpOverload` keys the table on the **LEFT operand only** —
`(opKind, typeKind, recId)` — so two overloads of one operator sharing a left
type collide and the first registered always wins. The use sites
(`parser.inc` x2, `ir.inc` x1) all looked up by `ASTTk[left]` and never
consulted the right operand at all.

This was unreachable before, because the mixed-type signature did not parse.
**Landing the parse fix alone would have converted a compile error into a
silent wrong value** — the exact trap in
[[feedback_widening_a_lowering_needs_a_family_sweep_not_a_wider_gate]].

Fixed without widening the table: the entry already names a proc whose `Params`
carry the real operand types, so `FindOpOverload2` prefers an entry whose SECOND
parameter matches the right operand and **falls back to the old first-match**,
leaving every single-overload program byte-identical. (`TParam` has no
`RecName`; the record id is on the param's SYMBOL — the builtin-mirrored-record
member check caught that immediately, see
[[project_compiler_own_structs_are_builtin_mirrored_records]].)

## Verified

`test/test_op_overload_mixed_operands.pas`, asserted in the Makefile: `+`, `-`,
`=`, `*`-by-Integer, chaining, a method on an operator result, a static class
function, accumulation in a loop, array elements, nesting, and the collision row
where both `TVec+TVec` and `TVec*Integer` exist and each site must pick by the
RIGHT operand. All diffed against `fpc -O1`; the file does not compile on
`pinned` at all.

82-test operator/record family sweep vs `pinned`: no behavioural difference.
`tools/gate.sh quick` GREEN, self-host fixedpoint converged in 1 round.

## Still open, deliberately

`class operator *(k: Integer; const a: TVec)` — a **scalar LEFT operand** — is
still refused at the definition (`impossible operator overload: this operation
is predefined for built-in operand types`). The pre-scan takes the type at the
first `:` and so sees only the left operand, and more importantly the use-site
lookup is keyed on the left operand's type: registering a scalar-left operator
would make `3 * 5` match it. That needs the table keyed on BOTH operands, which
is a design change rather than a fix —
[[decide-operator-table-keyed-on-one-operand-or-two]].

## Log
- 2026-08-10 — resolved, commit PENDING-COMMIT.
