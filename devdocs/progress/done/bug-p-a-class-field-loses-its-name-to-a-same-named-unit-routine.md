---
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: frankD
created: 2026-09-06
summary: "A class's own FIELD, PROPERTY or CLASS VAR whose name matches a routine in a used unit lost the name to the routine and stopped being a variable: `ExceptObject := TBox.Create` inside a method answered `cannot assign to the result of a function call`, and reading the same field as a `var` argument answered `by-reference argument must be a variable` — two diagnostics, neither naming resolution, for one cause. The member-shadow rule asked `FindUMeth` only, so it covered METHODS and no other member kind. It exists in TWO COPIES — pasparser_expr.inc:5167 (read) and pasparser_stmt.inc:7858 (assign) — and the statement copy's own comment already said the two must move together; fixing one alone leaves a shadowed field readable and unwritable, which is worse than fixing neither. CLASS CONST is deliberately excluded (bug-p-a-class-const-is-unreachable-through-an-instance-receiver). Live case: fcl-passrc pastree.pp:2397, a field named `ExceptObject` against lib/rtl sysutils' `function ExceptObject: TObject`. FIXED 2026-09-06."
---

# A class member loses its name to a same-named unit routine

- **Type:** bug (compat — everyday Pascal is refused) — **Track P**
  (`compiler/pasparser_expr.inc`, `compiler/pasparser_stmt.inc`).
- Found in fcl-passrc rung 7, [[feature-pascal-corpus-passrc]].

## The rule, and the half that was implemented

A class's own member hides an outer-scope routine. pxx implemented that for
**methods** — `FindUMeth(SelfMemberCi(name), name) >= 0` — and for nothing
else, so a field, property or class var sharing a name with a used unit's
routine resolved to the ROUTINE.

## Two copies, two unrelated-looking diagnostics

| use | site | message |
| --- | --- | --- |
| read (`Clear(TBox(ExceptObject))`) | `pasparser_expr.inc:5167` | `by-reference argument must be a variable` |
| write (`ExceptObject := TBox.Create`) | `pasparser_stmt.inc:7858` | `cannot assign to the result of a function call` |

**Neither message names resolution**, which is why the expression site was
found first and the statement site only surfaced when a test asserted a WRITE.
The statement site's own comment said *"the two MUST move together"* — the
comment was right and the code had drifted from it. This is
`devdocs/dev/normalise-dont-special-case.md`'s "fixed one arm of a double case?
grep for the sibling before closing", with the sibling already documented in
place.

## Resolution 2026-09-06

Both sites now ask four member kinds: `FindUMeth`, `FindUField`, `FindUProp`,
`FindClassVar`. **Class const stays out on purpose** — `<instance>.K` is
refused generally, so routing the name to member dispatch trades one wrong
answer for a different one.

`test/test_a_class_member_hides_a_same_named_unit_routine.pas`, wired in the
Makefile, byte-identical to fpc 3.2.2 `-Mobjfpc`:

```
field n   = 41
field nil = TRUE
property  = from-the-property
classvar  = 8
unit call = [padded]
```

**The rows are the member kinds and each asserts a value only the member can
produce**, because not every arm fails by refusing: a read-only use of a
shadowed property whose getter returns the routine's type compiles either way
and prints the wrong source's answer. The last row is the control — a name this
class does NOT declare must still reach sysutils from inside a method, or the
fix is not "the member wins" but "no unit routine is callable in a method".

With this and [[bug-p-a-class-typecast-is-refused-as-a-by-reference-argument]],
fcl-passrc `pastree.pp` (5947 lines) clears its first two walls. Two remain:
`:2979` a receiver-less `Free;` inside a method, and `:4940` a missing
`TFPList.Assign` (an RTL gap, Track B).

## Log
- 2026-09-06 — fixed and resolved; see the commit carrying this file.
