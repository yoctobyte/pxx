# bug: assigning a local dynamic-array-of-managed-record to a field drops/frees the elements

- **Type:** bug (Track A — codegen, managed dynamic-array assignment / refcount)
- **Status:** backlog
- **Found:** 2026-06-23, garin TDocModel.DeleteNode (Track B)
- **Severity:** medium — silent data loss; in a repeated-call path it escalates to
  a segfault. Easy to hit when rebuilding a managed array via a local temp.

## Gap

Assigning a **local** dynamic array of a record that has a managed field
(`AnsiString`) to a **field** of the same type does not properly retain the
elements: after the assigning procedure returns, the record's managed-string
fields are freed/empty. A second such reassignment on the same object then reads
freed memory.

```pascal
type
  TRec = record Cap: AnsiString; P: Integer; end;
  TBag = class
    Items: array of TRec;
    Cnt: Integer;
    procedure Add(const c: AnsiString);
    procedure Shrink;   { rebuild Items from itself via a local, then reassign }
  end;
procedure TBag.Add(const c: AnsiString);
begin SetLength(Items, Cnt+1); Items[Cnt].Cap := c; Inc(Cnt); end;
procedure TBag.Shrink;
var tmp: array of TRec; i, n: Integer;
begin
  SetLength(tmp, Cnt); n := 0;
  for i := 0 to Cnt-1 do begin tmp[n] := Items[i]; Inc(n); end;
  Items := tmp;          { <-- whole-array assign from a local }
  Cnt := n;
end;
...
b.Add('a'); b.Add('b'); b.Add('c');
b.Shrink; writeln(b.Items[0].Cap);   { 'a'  — ok }
b.Shrink; writeln(b.Items[0].Cap);   { fpc: 'a'   pxx: ''  (string lost) }
```

Observed (pinned, 2026-06-23): first line prints `a`, second prints empty. With a
*shrinking* rebuild (fewer survivors) the same shape segfaults instead (the
original DeleteNode hit `Segmentation fault`).

## Likely cause

The `field := localDynArray` path for an array whose element is a managed record
doesn't bump the array/element refcount (or the per-element string refs), so the
local's cleanup at procedure exit frees data the field still points at.

## Control (works)

- A single assignment, with no read of the field inside the proc, is fine
  (`pdyn.pas`): the corruption shows on the *second* rebuild.
- **In-place compaction** (never reassign the array reference; mutate the
  existing `FNodes` and `SetLength` to shrink) works correctly — this is what
  `TDocModel.DeleteNode` now does. No app-logic distortion; arguably the better
  idiom anyway.

## Repro

`/tmp/pdyn2.pas` (above). `array of integer` is unaffected (no managed field);
the defect is specific to managed-element records.

## Track B impact

None outstanding — `DeleteNode` uses in-place compaction. Filed so the codegen
path gets fixed (any "rebuild a managed array via a temp and assign back" hits it).
