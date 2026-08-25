---
slug: bug-a-delete-on-a-dynamic-array-of-interfaces-dangles-every-survivor
title: "`Delete(arr, i, n)` on an `array of IFoo` releases EVERY element, not just the removed ones"
track: A
prio: 55
type: bug
blocked-by: []
status: done
owner: ""
created: 2026-08-25
summary: "Deleting 2 of 5 interface elements destroys all five objects immediately: the fresh buffer does not retain the survivors, the old buffer's element-aware release drops all of them, and the three kept slots are left pointing at freed memory. Use-after-free reachable from ordinary code. AnsiString and managed-record element types are handled; the COM-interface element type is not."
---

# Repro (fpc-testsuite tarray11 reduced)

```pascal
program di;
{$mode objfpc}
type
  ITest = interface end;
  TTest = class(TInterfacedObject, ITest)
    fValue: LongInt;
    constructor Create(v: LongInt);
    destructor Destroy; override;
  end;
  TIA = array of ITest;
var freed: array of LongInt;
constructor TTest.Create(v: LongInt); begin fValue := v; end;
destructor TTest.Destroy;
begin
  SetLength(freed, Length(freed) + 1);
  freed[High(freed)] := fValue;
  inherited;
end;
var c: TIA; i: LongInt;
begin
  SetLength(c, 5);
  for i := 0 to 4 do c[i] := TTest.Create(i);
  Delete(c, 2, 2);
  { fpc: freed = 2 3      pxx: freed = 0 1 2 3 4 }
end.
```

| after `Delete(c, 2, 2)` | fpc 3.2.2 | pxx (HEAD 2026-08-25) |
| --- | --- | --- |
| destroyed | `2 3` | `0 1 2 3 4` |
| `c[0]`, `c[1]`, `c[2]` | live | **dangling** |

Everything after that point in the program reads freed memory. `tarray11.pp`
halts at code 30, which is its `CheckFreedArray([2, 3])` check; before
`bug-a-assigning-nil-to-a-whole-dynamic-array-of-records-or-interfaces` was
fixed the same test SIGSEGV'd earlier and hid this.

# Where it is

`ParseStatementAST`'s `AN_DYN_DELETE` arm (pasparser_stmt.inc ~5196) states the
contract in its own comment: *"the lowering retains the kept elements in the
fresh buffer (records: field-walk via the layout descriptor) to balance the old
buffer's element-aware release"*. `PXXDynArrayRetainImmediate` in
`compiler/builtin/builtinheap.pas` DOES implement `baseKind = 4` (COM interface,
`PXXIntfAddRef` per slot) — and its comment says that half is what makes
`SetLength` shrink correct — so the primitive is present and right.

So the defect is upstream of the helper: the AN_DYN_DELETE lowering is not
asking for kind 4, or not calling the retain at all for this element type. Start
by printing the baseKind the lowering passes (`PXXDBG=a.ir:<proc>`) rather than
reading the chain — `devdocs/dev/debugging-playbook.md`, and note that this
ticket's own "where it is" is a hypothesis, not a measurement.

# Check the siblings before closing

`Insert` shares the template (`AN_DYN_COPY`) and the same retain/release
balance, and `Copy(arr, i, n)` is the third. If Delete has the hole, measure all
three against the same destructor-logging oracle. Static `array[0..N] of IFoo`
whole-array assignment uses the header-free mirror
(`PXXStaticArrayRelease`/RetainImmediate pair) and is a fourth.

## Log
- 2026-08-25 — resolved, commit PENDING-COMMIT.

# Resolution, 2026-08-25

`compiler/ir.inc`: the three dyn-array walk dispatch tails (Delete ~6540,
Insert ~6688, Copy ~6879) were three hand-rolled copies of the same
(depth, baseKind, baseRecDesc) argument triple, and all three knew only about
AnsiString and record-with-managed-fields. A COM interface element fell through
to "nothing to release", so every survivor of a `Delete` kept the refcount the
old buffer had handed it, and the freed buffer's slots were never released.

Replaced by one helper:

```pascal
function AppendDynWalkTail(last, depth, elemTk, elemRec: Integer): Integer;
```

keyed on `ManagedElemKind(elemTk, elemRec)` — 1 AnsiString, 3 record, 4 COM
interface — which is the single answer the codebase already had for
"what does one element of this container need". All three gates widened from the
hand-written two-kind test to `(dcDepth > 1) or (ManagedElemKind(...) <> 0)`.

This is the exact failure `ManagedElemKind`'s own comment predicts: its header
records that the policy had been spelled out nine times and that **every** copy
had missed kind 4. It is now spelled out once.

Measured: the reduced repro printed `freed: 0 1 2 3 4` before (every element
destroyed by the Delete, survivors included — dangling) and prints `freed: 2 3`
after, matching fpc 3.2.2. `test/test_dynarray_delete_insert_copy_of_interfaces.pas`
covers Delete / Delete-at-head / Copy / SetLength-shrink and diffs MATCH against
fpc; it is wired into `test-core`.

One divergence remains and is filed separately, not asserted here:
`bug-a-a-dynarray-delete-temp-holds-the-new-buffer-until-scope-exit` — the
survivors are destroyed at scope exit rather than at the following `a := nil`,
because the hidden fresh-buffer temp holds a reference. Refcounts are correct;
the destruction TIME is one scope late. fpc-testsuite `tarray11` moved
SIGSEGV -> Halt(30) -> Halt(32) across the two fixes, and that last check is
this remaining ticket.

Gate: `make compiler/pascal26` fixedpoint converged in one round;
`tools/gate.sh quick` GREEN (self-host 111s, testmgr quick, FPC seed canary).
