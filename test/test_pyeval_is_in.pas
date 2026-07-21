{ pyeval tests: is/is not (identity, the x is None idiom) and in/not in
  (membership). feature-lib-pyexec. }
program test_pyeval_is_in;
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
  { is None }
  vm.Top:=0; Run('x = None'+#10+'push(1 if x is None else 0)'); ChkStk('is None true',1);
  vm.Top:=0; Run('x = 5'+#10+'push(1 if x is None else 0)'); ChkStk('is None false',0);
  { is not None }
  vm.Top:=0; Run('x = 5'+#10+'push(1 if x is not None else 0)'); ChkStk('is not None',1);
  { if x is None: raise ... (skipped) }
  vm.Top:=0; Run('name = 7'+#10+'if name is None:'+#10+'    raise RuntimeError("no")'+#10+'push(name)'); ChkStk('is None guard skipped',7);
  { in / not in }
  vm.Top:=0; Run('xs = [1,2,3]'+#10+'push(1 if 2 in xs else 0)'); ChkStk('in true',1);
  vm.Top:=0; Run('xs = [1,2,3]'+#10+'push(1 if 9 in xs else 0)'); ChkStk('in false',0);
  vm.Top:=0; Run('xs = [1,2,3]'+#10+'push(1 if 9 not in xs else 0)'); ChkStk('not in',1);
  writeln;
  if fails=0 then writeln('ALL PASS') else begin writeln(fails,' FAIL'); halt(1); end;
end.
