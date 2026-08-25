---
slug: refactor-a-two-dyn-array-depth-functions-that-drift
title: "`NodeDynDepth` and `DynArrayNodeDepth` are twins, and they drift apart"
track: A
prio: 30
type: refactor
blocked-by: []
status: unfinished
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


## PARKED 2026-08-25 — the merge is one line; the merge is also a SEMANTIC WIDENING

Banked rather than done, because the one-line version cannot be verified with a
dev-track gate and the widening it causes is not obviously safe.

### The duplication is smaller than it looks

`DynArrayNodeDepth` has exactly **one** external caller — `IsNodeArray`, six
lines below it in `symtab.inc`. Everything else is its own recursion. So the
merge really is:

```pascal
function IsNodeArray(node: Integer): Boolean;
begin
  Result := False;
  if NodeDynDepth(node) > 0 then Result := True
  else if ASTKind[node] = AN_IDENT then Result := Syms[ASTIVal[node]].IsArray
  else if ASTKind[node] = AN_FIELD then Result := RecFieldIsArray(...);
end;
```

plus a `function NodeDynDepth(node: Integer): Integer; forward;` in
`compiler.pas` (symtab.inc is included at line 101, `ast_arena.inc` at 129 — the
same hoist pattern line 61 already uses for `IsNilLiteralNode`), and deleting
`DynArrayNodeDepth`.

### Why that is not a no-op

`NodeDynDepth` is a strict SUPERSET: it also answers for `AN_FIELD`,
`AN_CALL`/`AN_VIRTUAL_CALL`/`AN_INTF_CALL`/`AN_CALL_IND`, and `AN_DYN_COPY`. So
`IsNodeArray` starts answering **True** for a dyn-array-returning CALL and for
`Copy(a, i, n)`, where it answers False today. Each caller was read:

| site | effect of the widening |
| --- | --- |
| `pasparser_expr.inc:5130` (Length's diagnostic) | **none** — guarded by `ASTKind[valNode] = AN_IDENT`, where the two functions already agree exactly |
| `pasparser_lval.inc:1307/1321/1348` (index suffix loop) | a call base now takes the `ResolveNodeRec` arm. Call results are intercepted earlier by `ApplyCallResultPtrSuffix`, but `AN_DYN_COPY` and `AN_COMMA` bases are not — `Copy(MakeArr,1,2)[0]` is a parse error today and would change shape |
| `ir.inc:1802` (`isArr` in index lowering) | a call / comma / Copy base changes the STRIDE decision. Plausibly more correct; unverified |
| `pyparser.inc:37300/37314/37341` (NilPy's copy of the lval loop) | same as the lval sites, in a frontend that is currently DEFERRED and whose suite this gate does not run |

That last row is the decisive one. Two of the four sites are in NilPy, the
change is a wrong-VALUE class of change rather than a compile-error class, and
the gate a dev track may run (`gate.sh quick`) covers neither the nilpy suite
nor the cross targets.

### What this needs to land

An A/B differential across the array/dyn-array/open-array corpus AND the nilpy
suite — i.e. a full-tier run, which is Track T's job, not a dev lane's. Concrete
recipe for whoever picks it up:

1. Record every affected test's OUTPUT with the current compiler (not just
   pass/fail — the failure mode here is a wrong value, and several of these
   tests would still exit 0).
2. Apply the three-line merge above.
3. Re-record and diff. Any difference is the answer to "should `IsNodeArray`
   widen?", which is the real open question — and it is plausibly **yes**, since
   a dyn-array call result genuinely IS an array.
4. If it widens cleanly, delete `DynArrayNodeDepth`. If not, the narrow set has
   to be justified in a comment on `IsNodeArray` rather than left implicit in a
   second function — which is the actual bug this ticket is about.

The `AN_COMMA` arm both functions were missing was added to BOTH on 2026-08-25
(`1facc0a40`), and each now carries a note pointing at the other, so the drift is
at least visible while this waits.
