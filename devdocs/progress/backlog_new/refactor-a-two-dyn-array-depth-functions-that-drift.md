---
slug: refactor-a-two-dyn-array-depth-functions-that-drift
title: "`NodeDynDepth` and `DynArrayNodeDepth` are twins, and they drift apart"
track: A
prio: 30
type: refactor
blocked-by: []
status: backlog_new
owner: ""
created: 2026-08-25
summary: "Two functions answer 'how many `array of` levels does this expression have': NodeDynDepth (ast_arena.inc) and DynArrayNodeDepth (symtab.inc). They have diverged at least twice and each divergence produced a silent wrong VALUE, not an error. Merge them."
---

# The two

| | file | callers |
| --- | --- | --- |
| `NodeDynDepth(node)` | `compiler/ast_arena.inc` | IR lowering, and increasingly the parser |
| `DynArrayNodeDepth(node)` | `compiler/symtab.inc` | `IsNodeArray`, parser-side selector typing |

Both answer the same question — remaining dyn-array nesting of an expression —
over the same AST, with the same recursion. Neither calls the other.

# The drift is documented IN THE CODE, twice

`DynArrayNodeDepth`'s `AN_INDEX` arm carries this note, from a fix to a real
bug:

> *"IR's NodeDynDepth already knew this; the parser-side twin did not, so
> `a[i][j]` was TYPED as indexing the element BASE type — for a managed-string
> base that made `m[0][1]` a CHAR read off an 8-byte stride (silent garbage;
> `bug-p-open-array-of-a-named-dynamic-array-reads-garbage`)."*

It happened again on 2026-08-25: the `AN_COMMA` arm — the node the call-result
materialisation builds — was missing from **both**, and had to be added to both
in one edit
(`bug-p-a-nested-dynamic-array-result-crashes-however-it-is-reached`).
`ResolveNodeRec` had carried its own comma arm since the csmith
struct-through-a-comma fix, so the shape was already known to be needed
somewhere; the two dyn-array twins simply never heard about it.

Note the failure mode both times: **not an error — a wrong value.** A depth
that is too small types an index as the base element, and the read comes off
the wrong stride. That is the expensive kind of bug this repo's debugging
playbook is written about.

# Why there are two (guess, not measured)

`DynArrayNodeDepth`'s header says *"Keep this parser-side helper here because
selectors are typed before IR lowering runs"* — i.e. an include-ORDER argument,
not a semantic one. If that is the whole reason, the fix is to move the single
implementation to whichever include is early enough (or add a forward), not to
keep two.

Check that before merging: if the two genuinely differ on some shape ON PURPOSE,
that difference is undocumented and is itself the bug to write down.

# Scope

- One implementation. Delete the other; forward-declare if include order needs it.
- Same for the sibling trio if they have twins: `NodeDynBaseTk`,
  `NodeDynBaseRec`, `NodeDynBaseSym`, `IsNodeArray`.
- `devdocs/dev/normalise-dont-special-case.md` is the doctrine this is an
  instance of — "if you fix a bug on one arm of a double case, grep for the
  sibling before closing the ticket" — and here the double case is two whole
  functions.

# Gate

Track A: `make compiler/pascal26` (fixedpoint) + `tools/gate.sh quick`. The
regression tests that already pin the behaviour are
`test/test_a_nested_dynamic_array_result.pas`,
`test/test_index_a_dynamic_array_call_result.pas`, and the
open-array-of-named-dyn-array tests.
