---
track: P
prio: 45
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "`L.Objects[i].Free` and `b.Pick(i).Free` are refused with `\"Free\": no such member on this record/class`, while `b.FA[i].Free` on the same objects compiles. The boundary is exactly BuiltinFreeHere's `PureDesignator(node)` guard, and the guard is CORRECT for the desugaring it protects: GenMakeFreeObjectExpr CloneASTs the operand up to three times (nil test, Destroy, FreeMem), so a getter or a function call would run three times. The fix is to stop cloning — materialise a non-designator receiver into a temp, or route the whole thing through an RTL helper that takes the instance once. `AllocTemp` (symtab.inc:6193) exists and has ZERO callers, so the parser has no established pattern for a hidden local and that is the real work. Two of fcl-passrc pscanner.pp's seven remaining walls are `FStreams.Objects[i].Free` / `FMacros.Objects[i].Free`."
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
   hidden local. `AllocTemp` (`symtab.inc:6193`) is `AllocVar('', tyInteger)`
   and **has zero callers** — the Pascal frontend has never made a hidden local
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
