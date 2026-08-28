program defmem_slice;
{ IR_DEFAULT_MEM (statement IR op 52) — zero a block of memory.

  75 of compiler.pas's 166 remaining refusal lines were this, the leader after
  `in` landed. It reaches the backend from 14 construction sites, every one of
  which passes REC_NONE, so the arm x86-64 carries for a record with MANAGED
  fields (release the ARC fields, then zero) is unreachable from today's IR.

  The construct that produces it is a scalar non-lvalue given to a by-ref
  RECORD parameter — `nil` to a `procedure of object` param, which is a
  two-pointer Code/Data record. The compiler materialises a zeroed temp and
  passes its address. Only the Code half is then written, so DATA IS THE
  WITNESS: it can only be zero because the zeroing put it there.

  THE CALL DEPTH IS LOAD-BEARING AND WAS WRONG ONCE. The temps live in the
  caller's frame. A first version dirtied memory from `Dirty` and called
  `Take(nil)` straight from the main body — but Dirty's frame is DEEPER than
  main's and never overlaps it, so the temp landed on memory that was already
  zero. All three falsification breaks passed against that version, including
  removing the zeroing outright. The wrappers below exist so the temp's frame
  sits at the SAME depth as Dirty's and therefore on Dirty's $5A5A5A5A. }
type
  TObj = class procedure Hi; end;
  TNotify  = procedure of object;
  TNotify2 = procedure(x: Integer) of object;
  TM = record Code, Data: Pointer; end;

procedure TObj.Hi; begin WriteLn('hi'); end;

procedure Dirty;
var b: array[0..63] of Integer; i: Integer;
begin
  for i := 0 to 63 do b[i] := $5A5A5A5A;
  WriteLn('dirty ', b[0]);
end;

procedure Take(const c: TNotify);
var m: TM;
begin m := TM(c); WriteLn('code=', PtrUInt(m.Code), ' data=', PtrUInt(m.Data)); end;

procedure Take2(const c: TNotify2);
var m: TM;
begin m := TM(c); WriteLn('two code=', PtrUInt(m.Code), ' data=', PtrUInt(m.Data)); end;

{ Two temps in ONE call expression: one zeroing that ran and one that did not
  would still look right if only a single temp were ever checked. }
procedure Pair(const a: TNotify; const b: TNotify2);
var ma, mb: TM;
begin
  ma := TM(a); mb := TM(b);
  WriteLn('pair ', PtrUInt(ma.Code), ' ', PtrUInt(ma.Data),
          ' / ', PtrUInt(mb.Code), ' ', PtrUInt(mb.Data));
end;

{ Each wrapper is called at the same depth as Dirty, so its frame — and the
  hidden temp inside it — lands on the bytes Dirty just wrote. }
procedure One;  begin Take(nil);  end;
procedure Two;  begin Take2(nil); end;
procedure Both; begin Pair(nil, nil); end;
procedure Twice; begin Take(nil); Take2(nil); end;

begin
  Dirty; One;
  Dirty; Two;
  Dirty; Both;
  Dirty; Twice;
end.
