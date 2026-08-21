---
slug: bug-a-nil-is-not-accepted-as-a-method-pointer-argument
track: A
prio: 40
type: bug
blocked-by: []
summary: "`Take(nil)` where `Take(e: TEv)` and `TEv = procedure(x: Integer) of object` is refused with 'no overload of Take matches these arguments: (Pointer)'. FPC accepts it. Assignment of nil to a method pointer works (that was the segfault fixed in bug-a-assigning-nil-to-a-method-pointer-segfaults); only the ARGUMENT position does not."
status: done
owner: claude-A
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

---

## Resolved 2026-08-21 — and it was three bugs, not one

The ticket said "only the ARGUMENT position does not [work]". Probing the seven
nil-able parameter shapes first, before touching anything, said otherwise:

| parameter | before |
| --- | --- |
| `Pointer` / `PChar` / plain procvar / dynamic array | accepted |
| **class** (`P(o: TObject)`) | **refused** |
| **interface** | **refused** |
| **method pointer** | **refused** |

So the everyday case — `P(o: TSomething)` refusing `P(nil)` — was broken too and
nobody had filed it. The three that fail are exactly the three whose type kind is
not `tyPointer`, which is what `nil` parses as.

### One predicate, asked from three directions

`ProcParamIsNilable(procIdx, j)` — "is this parameter reference-shaped?".
It cannot be a kind test: an interface and a method pointer are BOTH `tyRecord`,
and a plain record is not nil-able, so the parameter's `ProcParamRecId` has to be
consulted. Its three callers were three separate bugs:

1. **Argument position** — `MatchArgNilOk`, reached through a new
   `MatchParamCompatible(i, j, aTk)` seam. The eight compatible-phase sites all
   asked `TypesCompatible(Procs[i].Params[j].TypeKind, argTypes[j])` verbatim;
   they now ask the seam, so the nil rule lives in ONE place instead of being
   copy-pasted eight times. Two of those eight were already spelled slightly
   differently from the others, which is the drift this avoids.

   `nil`-ness itself is a side channel (`MatchArgNil[]`), filled beside
   `MatchArgRec[]` at the single entry into `MatchProcCall*`, because the type
   channel genuinely cannot carry it: by kind alone `nil` is indistinguishable
   from any other pointer value, and a nil-able parameter accepts nil but NOT an
   arbitrary pointer.

2. **Default value** — `procedure TakeDef(e: TEv = nil)` called as `TakeDef;`
   **segfaulted**, while `TakeDef(nil)` written out was fine. `DefaultArgValueNode`
   built the literal 0 wearing the PARAMETER's kind, so lowering read an aggregate
   off address 0. It is the identical trap to the `tyVariant` note already sitting
   ten lines below it in that function — one type family over, uncaught.

3. **Record constant** — `const R: TRec = (n: 4; ev: nil)` segfaulted **in startup
   code, before `main`**, so the record's other fields never initialised either and
   the failure did not look like it was about `ev`. Same cause a third time: a
   literal 0 tagged `tyRecord` is an ADDRESS to copy 16 bytes from. Tagged
   `tyPointer` it is the node a written `ev := nil` builds, and `AN_ASSIGN`'s
   tyRecord arm zeroes the field's full width.

Three occurrences of one concept is what `root-cause-over-microfix.md` calls a
design flaw rather than a smell, and the shared predicate is the answer to it.

### The trap that cost the most time

`Procs[i].Params[j].IsRef` is **TRUE for an ordinary by-VALUE record parameter** —
anything over 8 bytes is passed by reference for the ABI. The first cut excluded
`IsRef` parameters (nil is not an lvalue, so `var`/`out` must not accept it) and
that silently excluded exactly the two cases the ticket was about. The right
question is `ByRefArgNeedsLvalue`, which asks `ProcParamExplicitByRef and not
ProcParamIsConst` — and whose own docstring records the same trap being fixed for
interfaces in `bug-a-a-non-lvalue-is-refused-as-an-interface-argument`.

Found by measuring, not reasoning: `PXXDBG=a.nilarg` (added, documented in
`devdocs/dev/debug-switches.md`) prints each candidate's kind, rec id and lvalue
verdict. The probe is what showed `isref=TRUE` on a by-value parameter.

### `IsNilLiteralNode` — the other shared predicate

"Is this AST node `nil`?" is three non-obvious facts (INT_LIT, value 0, tagged
tyPointer) and was open-coded in `ir.inc`'s assignment arm. Now one function in
`ast_arena.inc`, asked by the matcher too.

### Siblings swept, per the ticket's own list

- comparison `if ev = nil` — already worked, verified.
- `var`/`out` method-pointer parameter — correctly still refuses nil (not an lvalue).
- local record const, array-of-record const — work.
- **`var R: TRec = (n: 7; ev: nil)` is refused** — and it is NOT this bug: the
  same declaration without any reference field is refused identically. Filed as
  [[bug-p-a-record-typed-var-initialiser-is-refused]] (Track P).

### Gate

`test/test_nil_argument_positions.pas` — all three positions and all seven
nil-able shapes in one program, output verified **identical to FPC 3.2.2**.
`make compiler/pascal26` fixedpoint (1 round) + `tools/gate.sh quick` GREEN.
The FPC seed needed the function order fixed (`MatchArgNilOk` calls
`ByRefArgNeedsLvalue`); the seed canary caught it.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
