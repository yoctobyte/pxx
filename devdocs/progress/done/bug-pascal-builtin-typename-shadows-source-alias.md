---
prio: 50
---

# ParseTypeKind's builtin-name chain runs BEFORE the alias table — every builtin name shadows a source declaration

- **Type:** bug (name resolution — silent wrong TYPE, not a parse error)
- **Track:** P — Pascal frontend (shared parser.inc, so Track A file-lane)
- **Status:** done
  [[bug-pascal-builtin-pointer-type-cast]] (resolved) once the real ordering was measured.

## The defect
`ParseTypeKind`'s chain of built-in type names (`widechar`, `tdatetime`, `currency`, `sizeint`,
`valreal`, `utf8string`, ...) is tested **before** `FindTypeAlias` is ever consulted. A comment
inside that chain asserts the opposite —

> "A user or RTL declaration still wins — FindTypeAlias is consulted before this."

— and it is simply **not true**. The alias lookup happens further down. So a program (or an RTL
unit) that declares its own type with one of those names gets the BUILT-IN meaning instead, with
no diagnostic.

## Why it has not bitten yet, and why that is luck
Nobody redeclares `widechar` or `tdatetime`. But the moment the P-names (`PInteger`, `PWord`, ...)
were added to the same chain, it became fatal immediately: **this compiler declares
`PWord = ^NativeInt`** (the machine word — see the PWord/ILP32 landmine), and the builtin
`PWord = ^UInt16` silently re-typed it. `pw^` read TWO bytes instead of eight.

That was caught by a test that DECLARES ITS OWN PWord (`test_builtin_pointer_types_b303.pas`).
**The self-host byte-identical gate did NOT catch it** — the compiler's own PWord kept working by
luck of where it happens to be declared. Do not rely on the self-host gate for this class of bug;
it only proves the compiler still builds itself, not that name resolution is right.

The P-names were shipped with an EXPLICIT `FindTypeAlias(lo) < 0` guard on their own branch, so
they are correct today. The rest of the chain is still wrong.

## The fix
Consult `FindTypeAlias` ONCE, at the top of the identifier case, and only fall through to the
builtin-name chain when it misses. Then delete the per-name guard the P-names carry, and correct
the comment that started this.

Care: some builtins may be *deliberately* winning today (the chain maps `tdatetime`/`currency` to
what lib/rtl/sysutils declares them as, so the two agree and nothing shows). Changing the order
makes the RTL's declaration authoritative instead — which is what it should be, but check each
name that the RTL also declares, and gate on `make test` + the RTL/lib tests, not just self-host.

## Gate
`make test` + self-host byte-identical + `make lib-test` (this touches how RTL type names resolve).

## Log
- 2026-07-13 — resolved, commit 5c21dd25.
