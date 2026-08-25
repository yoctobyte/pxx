---
slug: bug-a-delete-on-a-dynamic-array-of-interfaces-dangles-every-survivor
title: "`Delete(arr, i, n)` on an `array of IFoo` releases EVERY element, not just the removed ones"
track: A
prio: 55
type: bug
blocked-by: []
status: backlog_new
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
