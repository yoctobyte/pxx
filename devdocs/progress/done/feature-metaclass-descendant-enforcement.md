# Metaclass alias descendant-constraint enforcement

- **Type:** feature
- **Status:** done
- **Owner:** Track A
- **Opened:** 2026-06-06 (from todo.md §4 / rainy-afternoon)

## Motivation

Named `class of` metaclass aliases are pointer-backed and work for the covered
subset, but do not yet enforce every descendant constraint against arbitrary
pointer-compatible assignments — a too-broad assignment is currently accepted.

## Scope

- Enforce that a value assigned to a `class of TBase` metaclass is `TBase` or a
  descendant; reject unrelated pointer-compatible assignments.

## Acceptance

A test assigning a non-descendant class reference to a metaclass variable is
rejected; valid descendant assignments still compile; self-host fixedpoint holds.

## Investigation (2026-07-02, Track A) — scoped, not attempted

Traced the representation before writing any code:

- A named metaclass alias (`TFooClass = class of TFoo`) is registered via
  `RegisterClassRefAlias` (symtab.inc:230): a `tyPointer` type alias tagged
  `AliasElemTk = tyClass`, `AliasElemRec = REC_UCLASS_BASE + <TFoo's class
  id>`. So a `var mc: TFooClass;` variable's *declared base class* is
  discoverable from its alias's `AliasElemRec`.
- A bare class name used as a value (`mc := TDerived;`) parses to an
  `AN_CLASSREF` node (parser.inc:1312) with `ASTIVal[node] = <TDerived's
  class id>` — so the *specific class being assigned* is also directly
  available at the assignment site, no extra work needed there.
- `IsSubclassOf(otherCi, ci)` (symtab.inc:368) already walks `UClsParent` and
  answers exactly the "is otherCi a descendant of ci" question this needs
  (note: strict descendant — `otherCi = ci` needs an explicit `or` alongside
  it, since `IsSubclassOf` starts from `UClsParent[otherCi]`, not `otherCi`
  itself).

So the two pieces the ticket needs both already exist and just need wiring
together at the assignment site — **for the one case the ticket's own repro
covers** (a bare class-name literal assigned to a declared metaclass
variable). That part alone would be small.

**What makes it bigger:** grepped for any existing "reject an assignment
because of an object/class-pointer type mismatch" check anywhere in the
compiler (the same way `obj: TBase := TDerived.Create` is allowed but the
reverse should not compile) and found **none** — plain class-typed variable
assignment is not type-checked for compatibility at all today; classes are
just pointers at runtime and nothing currently gates that. This ticket's own
title says "against arbitrary pointer-compatible assignments," i.e. it wants
metaclass assignment to be *stricter* than ordinary class-pointer assignment
already is — which means deciding a scope question rather than just wiring
existing pieces:

1. Cover **only** the bare-class-literal-RHS case (`mc := TDerived;`), which
   is cheap and matches the ticket's literal repro, but leaves the
   "arbitrary pointer-compatible assignment" in the title unaddressed for
   the other RHS shapes it names (assigning another metaclass *variable* of
   an unrelated alias, or a plain class-typed pointer expression) — those
   need comparing two `AliasElemRec` bases against each other, a
   fundamentally different (variable-to-variable, not literal-to-variable)
   check with its own edge cases (what if the RHS metaclass alias's base is
   an ANCESTOR of the LHS's, e.g. narrowing at compile time when the runtime
   value happens to be a real descendant?).
2. Or introduce a real "class-pointer assignment compatibility" check as a
   general mechanism (which would also apply to plain, non-metaclass class
   variables) — bigger, and changes behavior for existing programs that may
   rely on today's unchecked pointer-compatible assignment.

Parking rather than landing option 1 as a narrow, asymmetric fix (rejects a
literal, silently accepts everything else the ticket's own title says should
also be rejected) — that would technically pass the ticket's one acceptance
test while leaving the title's actual claim false. Whoever picks this up next
should decide between (1) and (2) first; the representation-level legwork
above (aliases already carry the base class id, `AN_CLASSREF` already carries
the specific class id, `IsSubclassOf` already answers the descendant
question) means either path is mostly wiring once the scope is settled.

## Log
- 2026-06-06 — ticket opened from todo.md §4.
- 2026-07-02 — investigated representation (alias base class id,
  `AN_CLASSREF`, `IsSubclassOf`); found the "arbitrary pointer-compatible
  assignment" half of the title has no existing check to extend and needs a
  scope decision before implementing. Parked with the above notes.
- 2026-07-03 — Implemented (Track A), resolving the parked scope question as
  a middle path: enforce descendant compatibility for the two RHS shapes that
  carry a statically known class — a bare class-name literal (`AN_CLASSREF`)
  and another metaclass variable (compared via its declared alias base, so
  compile-time narrowing `TChildClass := TBaseClass-var` is rejected too).
  Arbitrary pointer expressions / casts / nil stay unchecked — no general
  class-pointer assignment check was introduced (option 2 explicitly not
  taken; it would change behavior of existing unchecked programs).
  `CheckMetaclassAssign` (parser.inc), hooked at the plain-identifier
  assignment statement. Regressions: test_metaclass_descendant.pas (valid
  base/descendant/var/nil forms), test_metaclass_descendant_error.pas
  (unrelated class rejected), test_metaclass_narrowing_error.pas (ancestor
  metaclass var rejected); all in `make test`. Self-host byte-identical.
