program test_parallel_for_capture_callee;
{ A captured dynamic array passed from a `parallel for` body to a callee — as
  `var`, as `const`, and by value
  (bug-parallel-for-captured-dynarray-var-arg-segfault). The worker's capture
  accessor is a ^TArr holding the handle; a var named-dyn-array param expects
  the handle-SLOT address, so the raw deref handed it the handle and the
  callee's slot-deref read element 0 as the handle and crashed. The arg
  lowering now materialises a hidden slot (temp := handle, pass &temp).
  Element writes alias the shared buffer and propagate; resize through the
  param is not published back (documented copy-in shape). }
uses palparallel;

type TArr = array of Integer;

var vErr, cErr: Integer;

procedure SinkVar(i: Integer; var a: TArr);
begin a[i] := i * 3; end;

procedure SinkConst(i: Integer; const a: TArr);
begin if a[i] <> i * 3 then vErr := vErr + 1; end;

procedure SinkVal(i: Integer; a: TArr);
begin if a[i] <> i * 3 then cErr := cErr + 1; end;

procedure Run;
var i: Integer; la: TArr;
begin
  SetLength(la, 100);
  parallel for i := 0 to 99 do SinkVar(i, la);
  parallel for i := 0 to 99 do SinkConst(i, la);
  parallel for i := 0 to 99 do SinkVal(i, la);
  writeln('la42=', la[42]);
  writeln('vErr=', vErr, ' cErr=', cErr);
  if (la[42] = 126) and (vErr = 0) and (cErr = 0) then
    writeln('PARFORCALLEE OK')
  else
    writeln('PARFORCALLEE FAIL');
end;

begin
  Run;
end.
