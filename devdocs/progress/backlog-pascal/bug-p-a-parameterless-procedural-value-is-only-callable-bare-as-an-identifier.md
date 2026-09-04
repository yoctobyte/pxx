---
slug: bug-p-a-parameterless-procedural-value-is-only-callable-bare-as-an-identifier
track: P
prio: 40
type: bug
status: open
blocked-by: []
owner: unassigned
created: 2026-09-04
found-by: frankA (writing test_cross_method_pointer_call)
summary: "A parameterless procedural value is callable with no argument list ONLY when it is spelled as a bare identifier. `m;` compiles; `h.p;`, `h.nul;` and `a[0];` all give `expected ':=' before ';'` and the statement is read as the start of an assignment. The boundary is NOT `of object` and NOT the record field -- a plain `procedure` in a record field and a method pointer in an ARRAY element fail identically, so it is any procedural-valued lvalue that is not a single identifier. `h.nul()` with empty parens works, so the value and its call machinery are fine and only the no-parens statement path is missing the shape."
---

# A parameterless procedural value is only callable bare as an identifier

## Measured

x86-64, HEAD, 2026-09-04. Four spellings, one compiler run each.

| statement | shape | result |
| --- | --- | --- |
| `m;` | plain variable, `procedure of object` | **accepted**, prints |
| `m();` | plain variable, empty parens | **accepted**, prints |
| `h.nul();` | record FIELD, empty parens | **accepted**, prints |
| `h.nul;` | record FIELD, bare | `error: expected ':=' before ';'` |
| `h.p;` | record FIELD, plain `procedure` (no `of object`) | `error: expected ':=' before ';'` |
| `a[0];` | ARRAY element, `procedure of object` | `error: expected ':=' before ';'` |

The last three all report at the `;`, with the context `near: ... h . p >>> ; end .`
— the statement parser has taken the designator as an assignment target and is
waiting for `:=`.

## The boundary is not what the first example suggested

The shape turned up as `h.nul;` in a method-pointer test, so the obvious title
was "a method-pointer field cannot be called bare". **Both halves of that are
wrong, and removing each named feature is what showed it:**

- drop `of object` — `h.p;` for `p: procedure` in a record fails identically,
  so it is not about method pointers;
- drop the field — `a[0];` for an array of `procedure of object` fails
  identically, so it is not about record fields.

What survives both removals is: **the designator is not a bare identifier.**
`m;` is the only accepted no-parens form.

## Why it is filed rather than patched

Same reason as [[bug-p-member-access-on-a-procedural-variable-call-result-is-rejected]],
and probably the same code: the statement-level path recognises the
simple-identifier spelling of a procedural value and the other spellings are
built at the several `AllocNode(AN_CALL_IND)` sites, each of which decides for
itself. Adding the no-parens case at whichever site produced this symptom is
the arm that stays broken — `normalise-dont-special-case` before the microfix
rather than after.

FPC accepts all six rows, and real Pascal writes `OnClick;` far more often than
`OnClick()`, so this is a compat item with actual source behind it rather than
an edge case only a probe reaches.

## Not a blocker for the test that found it

`test/test_cross_method_pointer_call.pas` uses `h.nul()` and says in its header
why, with this slug. When this is fixed, that test is the natural place to add
the bare rows.

## Log

- 2026-09-04 | frankA | filed while writing the wasm32 method-pointer cross test
  (`99fa70c34`). Not on the wasm32 path at all — every row above was measured on
  the x86-64 build.
