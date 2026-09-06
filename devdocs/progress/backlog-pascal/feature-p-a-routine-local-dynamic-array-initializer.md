---
track: P
prio: 30
type: feature
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "`var v: array of Integer = (1, 2, 3);` inside a routine is refused with `a routine-local dynamic-array initializer is not supported yet; assign in statements`. The FIXED-array case landed 2026-09-06 (feature-p-a-local-var-section-array-initializer); this is the deliberate residual and the reason it is separate is STRUCTURAL, not effort: a dynamic-array element list is carried as pending-init kind 10, whose payload is an AST NODE, and `FlushLocalInits` reads kinds 0/1/2/4/5/9 — every one of them a scalar, a string or a symbol index, none of them holding a node. So there is no local table row to write, and `RegisterVarInitElem` calls `Error` for kind 10 rather than writing a row the flusher would silently ignore. The fix is either a local kind that carries a node, or lowering the element list to statements at the flush site (which is what the diagnostic already tells the programmer to do by hand). fpc 3.2.2 -Mobjfpc accepts it. NOT hit by fcl-passrc rung 7 — ranked on the language, not on a corpus wall."
---

# A routine-local dynamic-array initializer

- **Type:** feature (compat — FPC-legal, refused) — **Track P**
  (`compiler/pasparser_decl.inc`).

```pascal
procedure P;
var v: array of Integer = (1, 2, 3);   { fpc: ok.  pxx: refused }
begin
  WriteLn(Length(v), ' ', v[0]);
end;
```

Global `var v: array of Integer = (1,2,3)` at file scope works today; so does the
routine-local FIXED array since `feature-p-a-local-var-section-array-initializer`.
This is the one spelling left.

## Why the refusal is narrow on purpose

The message names the missing half. Before the fixed-array fix, every local array
initializer answered *"local var-section ARRAY initializer not supported"* —
which was true of the message and false of the compiler, since the machinery
existed and only the fork was missing. Leaving the dynamic case behind the same
wide message would repeat exactly that, so it says `dynamic-array` and the
fixed case no longer reaches it.

**Pending-init kind 10 is the whole obstacle.** It carries an AST node —
the element list, unevaluated. `FlushLocalInits` walks kinds 0/1/2/4/5/9 and
every one of those is a value or an index; nothing in the local path can hold a
node. `RegisterVarInitElem` therefore raises rather than writing a row that
would be dropped without a diagnostic — a silently-ignored table row is the
failure mode this whole area already produced once.

## Gate

The global spelling is the control and must not move (it is the same element
loop). Assert `Length(v)` **and** an element value: a dynamic array that ends up
empty still compiles and still indexes-in-range for zero iterations, so a length
row alone can pass on a do-nothing lowering.
