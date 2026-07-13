---
prio: 50
---

# bug: an overloaded method's IMPLEMENTATION does not always match back to its DECLARATION

- **Track:** P (Pascal frontend)
- **Found:** 2026-07-13 while fixing b315 (fpjson corpus). b315 stops this from CORRUPTING
  the method table; the mismatch itself is still here.

## What

When a method body is parsed, the binder tries `FindUMethByProc(ci, procIdx)` — i.e. "which
method-table entry was this exact proc registered under at declaration time?". For some
overloads that lookup MISSES, meaning the implementation header created a proc that is not
the one the declaration registered for that signature.

Before b315 the code then fell back to a NAME match (the first entry of that name) and
OVERWROTE its proc — clobbering a different overload. That is what broke
`TJSONArray.Insert(0)`: ten two-arg `Insert` bodies each landed on the one-arg entry.

b315 makes the fallback refuse to bind across a different arity, so nothing is destroyed.
But the underlying mismatch remains, and it still costs:

- **same-arity overloads can still be confused.** Instrumentation on fpjson showed method
  entries 365 and 366 BOTH bound to proc 724, and 361/362 both to proc 728 — duplicate
  bindings among the two-arg Inserts. b315's arity guard cannot separate those.
- a body that fails to match its declaration gets a FRESH table entry, so the class ends up
  with more method entries than it declared.

## Where to look

`compiler/parser.inc`, the method-body header path (~line 19700, `mmi := FindUMethByProc(...)`)
and whatever resolves an implementation header `procedure TFoo.Bar(...)` to its declared
proc. The question to answer first: for fpjson's `Insert` overloads, WHICH ones miss, and
why — a parameter type that compares unequal between decl and impl is the obvious suspect
(fpjson's set includes `UnicodeString` next to `String`, `QWord`, `Int64`, `NativeInt` and
`TJSONFloat`, so an alias that resolves to the same TTypeKind in one place and not the other
would do it). Dump the decl-time and impl-time param TypeKinds for each overload and diff
them; do not theorise.

## Guard

`test/test_method_overload_arity_rebind_b315.pas` covers the arity case. A same-arity case
(two overloads differing only in parameter TYPE, implemented out of order) would pin this
one — worth writing as the first step.
