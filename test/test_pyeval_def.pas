{ pyeval nested-function tests (feature-lib-pyexec): def/return, the to_cell
  helper idiom, early return from loops, local-scope isolation, nested calls. }
program test_pyeval_def;
uses pylib, typinfo, pyeval;
type PVRec=^TVRec; TVRec=record VType,Payload:Int64;end;
  TVM=class Data:array[0..63] of Int64; Top:Integer;
    procedure push(const v:Variant); function pop:Variant; end;
procedure TVM.push(const v:Variant); begin Data[Top]:=PVRec(@v)^.Payload; Top:=Top+1; end;
function TVM.pop:Variant; begin Top:=Top-1; PVRec(@Result)^.VType:=2; PVRec(@Result)^.Payload:=Data[Top]; end;
var vm:TVM; g:TPyDict; vmv:Variant; fails:Integer;
procedure Run(const s:AnsiString); var l:TPyDict; begin l:=TPyDict.Create; EvalPyStmts(s,g,l); end;
procedure ChkStk(const lbl:AnsiString; want:Int64);
begin vm.Top:=vm.Top-1; if vm.Data[vm.Top]=want then writeln('ok   ',lbl,' = ',want) else begin writeln('FAIL ',lbl,' got ',vm.Data[vm.Top],' want ',want); fails:=fails+1; end; end;
begin
  fails:=0; vm:=TVM.Create; g:=TPyDict.Create; PVRec(@vmv)^.VType:=7; PVRec(@vmv)^.Payload:=Int64(Pointer(vm)); g.store('vm',vmv);
  { simple def + return }
  vm.Top:=0; Run('def sq(x):'+#10+'    return x * x'+#10+'push(sq(6))'); ChkStk('sq',36);
  { def used twice (the to_cell idiom) }
  vm.Top:=0; Run('def to_cell(x):'+#10+'    x = x & 0xFF'+#10+'    if x >= 128:'+#10+'        x -= 256'+#10+'    return x'+#10+'push(to_cell(200))'); ChkStk('to_cell 200 -> -56',-56);
  vm.Top:=0; Run('def to_cell(x):'+#10+'    x = x & 0xFF'+#10+'    if x >= 128:'+#10+'        x -= 256'+#10+'    return x'+#10+'push(to_cell(50))'); ChkStk('to_cell 50 -> 50',50);
  { def with loop + early return }
  vm.Top:=0; Run('def firstbig(n):'+#10+'    for k in range(n):'+#10+'        if k > 3:'+#10+'            return k'+#10+'    return -1'+#10+'push(firstbig(10))'); ChkStk('firstbig',4);
  { local scope isolation: outer x unaffected }
  vm.Top:=0; Run('def f(x):'+#10+'    x = 999'+#10+'    return x'+#10+'x = 5'+#10+'y = f(1)'+#10+'push(x)'); ChkStk('scope isolation',5);
  { nested calls }
  vm.Top:=0; Run('def dbl(x):'+#10+'    return x + x'+#10+'def quad(x):'+#10+'    return dbl(dbl(x))'+#10+'push(quad(3))'); ChkStk('nested calls',12);
  { return None (bare) then push after }
  vm.Top:=0; Run('def noop():'+#10+'    return'+#10+'noop()'+#10+'push(7)'); ChkStk('return none',7);
  writeln;
  if fails=0 then writeln('ALL PASS') else begin writeln(fails,' FAIL'); halt(1); end;
end.
