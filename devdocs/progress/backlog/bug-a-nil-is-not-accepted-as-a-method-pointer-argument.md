---
slug: bug-a-nil-is-not-accepted-as-a-method-pointer-argument
track: A
prio: 40
type: bug
blocked-by: []
summary: "`Take(nil)` where `Take(e: TEv)` and `TEv = procedure(x: Integer) of object` is refused with 'no overload of Take matches these arguments: (Pointer)'. FPC accepts it. Assignment of nil to a method pointer works (that was the segfault fixed in bug-a-assigning-nil-to-a-method-pointer-segfaults); only the ARGUMENT position does not."
status: backlog
---

# `nil` is not accepted as a method-pointer argument

```pascal
type TEv = procedure(x: Integer) of object;
procedure Take(e: TEv); begin ... end;
...
  Take(nil);
```

```
pascal26:20: error: no overload of Take matches these arguments
  argument types: (Pointer)
  candidates:
```

FPC accepts this — `nil` is assignment-compatible with a method pointer, in
every position.

## Where it sits

Found while fixing `bug-a-assigning-nil-to-a-method-pointer-segfaults`, and
deliberately NOT folded into it: that one was a segfault in the STORE lowering
and this is argument type-matching, a different mechanism with a different fix
site. `ev := nil` now works in all four assignment shapes (variable, field,
array element, `var` parameter); the argument position is the one that is left.

## Where to look

A method pointer's declared type kind is `tyRecord` (`MethodPtrRecId`, the
16-byte {Code,Data} layout), and `nil` parses as `AN_INT_LIT 0` typed
`tyPointer` (`pasparser_expr.inc:370`). So overload matching is being asked
"does `Pointer` match `record`" and correctly answering no. The assignment path
learned to special-case this shape; the parameter-match path did not — which
makes it the same double-case story one level over, and worth checking whether
the two can consult ONE predicate ("is this node a nil literal being handed to a
nil-able destination") rather than growing a third copy.

**Grep for the siblings while there:** the same question is asked by a `var`/
`out` argument, a default parameter value (`e: TEv = nil`), a `case`/comparison
(`if ev = nil then`, which should be checked — it may already work by another
route), and a record/array CONSTANT initialiser containing a method-pointer
field set to nil.

## Gate

A test covering the argument, default-value and comparison positions, each
against FPC 3.2.2. Self-host byte-identical + `tools/gate.sh quick`.
