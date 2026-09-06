---
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: frankD
created: 2026-09-06
summary: "`L.Objects[i].Free` and `b.Pick(i).Free` are refused with `\"Free\": no such member on this record/class`, while `b.FA[i].Free` on the same objects compiles. The boundary is exactly BuiltinFreeHere's `PureDesignator(node)` guard, and the guard is CORRECT for the desugaring it protects: GenMakeFreeObjectExpr CloneASTs the operand up to three times (nil test, Destroy, FreeMem), so a getter or a function call would run three times. The fix is to stop cloning — materialise a non-designator receiver into a temp, or route the whole thing through an RTL helper that takes the instance once. THE STATED BLOCKER IS FALSE AND WAS MEASURED AS SUCH 2026-09-06: `AllocTemp` (symtab.inc:6200) does have zero callers, and it is merely an unused ALIAS for `AllocVar('', tyInteger)` -- the hidden-local pattern itself has **193 sites** in `compiler/**` (58 tyPointer, 27 tyAnsiString, 23 tyInteger, ...), at least four of them in the Pascal frontend (`pasparser_stmt.inc:2463`, `:3685`, `:7565`, `pasparser_expr.inc:10838`), and the canonical spelling is `sym := AllocVar('', tk)` then `GenMakeAssign(GenMakeIdent(sym, tk), value)` then `GenMakeIdent(sym, tk)` -- exactly `GenMakeStrArgTemp` (pasparser_stmt.inc:357). So there IS an established pattern; a zero-caller count on a NAME was read as a missing CAPABILITY. The real work is the desugaring, not the temp. Two of fcl-passrc pscanner.pp's seven remaining walls are `FStreams.Objects[i].Free` / `FMacros.Objects[i].Free`."
---

# `Free` on a computed receiver is refused, because the desugaring clones it

- **Type:** bug (compat — everyday Pascal is refused) — **Track P**
  (`compiler/pasparser_call.inc`, `compiler/pasparser_stmt.inc`).
- Found in fcl-passrc rung 7, [[feature-pascal-corpus-passrc]].

## The measurement, and it is a clean three-row boundary

```pascal
b.FA[0].Free;        { array field element   — COMPILES }
b.Pick(1).Free;      { plain function call   — refused  }
b.Objects[2].Free;   { indexed property      — refused  }
```

fpc 3.2.2 `-Mobjfpc` compiles and runs all three. pxx refuses rows 2 and 3 with

```
error: "Free": no such member on this record/class
```

which is the message `RequireRecMember` emits when nothing claimed the name —
**not** a diagnostic about the receiver, so the error text points away from the
cause. `.ClassName` and an inherited ordinary method on the SAME receiver both
work, so this is `Free` specifically and not member lookup.

## Where it is decided

`BuiltinFreeHere` (`pasparser_call.inc:3473`) is the shared predicate for
`<designator>.Free` and it is called from both Pascal member-dispatch copies.
Its last condition is `PureDesignator(node)`, which accepts `AN_IDENT`,
`AN_FIELD`, `AN_INDEX`, `AN_DEREF` and casts over those, and rejects everything
else. An indexed property read is `MakeAccessorCall` — an `AN_CALL`.

**The guard is not the bug and must not simply be deleted.**
`GenMakeFreeObjectExpr` (`pasparser_stmt.inc:1930`) builds

```
if <obj> <> nil then begin <obj>.Destroy; FreeMem(<obj>) end
```

with a separate `CloneAST(objNode)` in each position — the AST is a tree, not a
DAG. Dropping `PureDesignator` would call the getter three times, which for
`Objects[i]` is merely wasteful and for `Pick(i)` is an observable behaviour
change. That is a silently wrong program in place of a refusal.

## Two routes, and the work is the same either way

1. **Materialise a temp.** `tmp := <obj>; if tmp <> nil then ...`, with `tmp` a
   hidden local.

   **CORRECTED 2026-09-06, and this is the line that was blocking the work.**
   `AllocTemp` (`symtab.inc:6200`) is `AllocVar('', tyInteger)` and has zero
   callers -- true, and it says nothing about the capability, because it is an
   unused ALIAS. Measured at HEAD: **`AllocVar('', <tk>)` appears 193 times in
   `compiler/**`** -- 58 `tyPointer`, 27 `tyAnsiString`, 23 `tyInteger`, 12
   `tyVariant`, and so on -- with at least four in the Pascal frontend
   (`pasparser_stmt.inc:2463`, `:3685`, `:7565`, `pasparser_expr.inc:10838`).
   The three-line idiom is right there in `GenMakeStrArgTemp`
   (`pasparser_stmt.inc:357`):

       st := AllocVar('', tyAnsiString);
       preSeq := GenMakeSeq(preSeq, GenMakeSeq(
                   GenMakeAssign(GenMakeIdent(st, tyAnsiString), argNode), -1));
       Result := GenMakeIdent(st, tyAnsiString);

   **A zero-caller count is a true fact about a NAME and was converted into a
   false claim about a MECHANISM.** The frontend has made hidden locals for a
   long time; it has just never called them `AllocTemp`. What remains is the
   desugaring itself -- materialise the receiver once and stop cloning -- which
   is real work and is not blocked on a missing pattern.
   this way, so this is a new pattern, not a reuse. It also needs the result to
   be a statement SEQUENCE where today it is a single node, and every
   `GenMakeFreeObjectExpr` caller assigns it straight into `Result`.
2. **An RTL helper** taking the instance once and doing the nil test plus the
   virtual `Destroy` itself. One evaluation by construction and no parser temp
   — but the destructor call has to dispatch virtually from the helper, which
   the parse-time `GenMakeMethodCall0(..., ci, 'Destroy')` currently arranges
   using the STATIC class id.

Route 2 also removes a clone from the pure-designator path, so the two arms
stop being two arms. `devdocs/dev/normalise-dont-special-case.md`.

## What this is NOT

Not a missing door. `BuiltinFreeHere` is reached on both failing rows and
answers False on purpose; the caller census would have found it and reported
every site as covered. The absent thing is a capability, not a call.

## Gate

`make compiler/pascal26`, the three rows above matching fpc, plus a row proving
the receiver is evaluated **once** — a getter with a side effect (a counter it
increments) freed through this path, asserting the counter is 1 and not 3. A
compile-only row cannot see the defect this ticket's guard exists to prevent.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit a5588f5c6.

## Resolution 2026-09-06 — the temp went in, the guard came out, and there was a third piece

**Route 1 of the two the ticket listed.** `GenMakeFreeObjectExpr`
(`pasparser_stmt.inc`) materialises a non-designator receiver into a hidden
`tyClass` local before building the nil test, and clones the LOCAL. The temp
carries the resolved rec (`Syms[t].RecName := ResolveNodeRec(objNode);
SymSyncTypeRef(t)`) because both downstream readers need it: `GenMakeMethodCall0`
dispatches Destroy, and the tkFreeMem lowering injects `PXXClassFinalize` only
when the argument node is tyClass (`ir.inc:13578`). Three lines, the same shape
as the `with`-temp at `pasparser_stmt.inc:4356`, exactly as the corrected
summary said.

`BuiltinFreeHere`'s `PureDesignator(node)` condition is gone. **Order matters
and the ticket was right to say so**: removing the guard without the temp turns
a refusal into a silently wrong program — three getter calls, and for a
function receiver three objects created with only the last freed.

**THE THIRD PIECE WAS NOT IN THE PLAN AND IT IS THE REUSABLE PART.** With the
temp in, `b.Objects[2].Free;` stopped reporting `"Free": no such member` and
started reporting

```
error: expected ':=' before ';'
```

because `GenMakeFreeObjectExpr` now returns an `AN_SEQ` (assignment, then the
`AN_IF`) and the statement parser has a **recognition door** at
`pasparser_stmt.inc:8482` listing the node kinds a desugaring may hand back in
lvalue position: `ASTNodeIsCall(valNode) or (ASTKind[valNode] = AN_IF)`. A kind
missing from that list gets no diagnostic — it falls through to `Expect(':=')`
and reports assignment for a construct with no assignment in it. One door, one
line, widened with `AN_SEQ` and a comment naming it as an enumerated predicate.
**The ticket's two routes both change the node the desugaring returns, so both
would have hit this**, and neither mentioned it.

## Gate, as the ticket specified it

`test/test_free_on_a_computed_receiver_evaluates_it_once.pas`, wired in the
Makefile, byte-identical to fpc 3.2.2 `-Mobjfpc`:

```
field elem  freed=1 calls=0     { pure designator: no temp, no getter }
call        freed=3 calls=1     { b.Pick(1).Free   — ONE evaluation }
property    freed=6 calls=2     { b.Objects[2].Free — ONE evaluation }
```

**The counter is the assertion and `freed` alone cannot see the defect.** With
the receiver cloned three times the objects still get freed and `freed` still
reaches 6 — the sum is right and the evaluation count is not — so a test
checking only the destructor totals passes on the broken desugaring. That is
the ticket's own "a compile-only row cannot see the defect this guard exists to
prevent", one level sharper: a VALUE row cannot see it either.

Rung 7 of [[feature-pascal-corpus-expansion]] — fcl-passrc `pscanner.pp`, 5333
lines — compiles and links clean with this. It does **not yet run**: filed
separately.
