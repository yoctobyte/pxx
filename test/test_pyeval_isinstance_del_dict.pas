{ pyeval tests: isinstance (type sentinels), del (subscript + local), dict/set
  literals, and dict store into host fields. feature-lib-pyexec. }
program test_pyeval_isinstance_del_dict;
uses pylib, typinfo, pyeval;
type PVRec=^TVRec; TVRec=record VType,Payload:Int64;end;
  TVM=class Data:array[0..63] of Int64; Top:Integer;
    stack: TPyList; vars: TPyDict;
    procedure push(const v:Variant); function pop:Variant; end;
procedure TVM.push(const v:Variant); begin Data[Top]:=PVRec(@v)^.Payload; Top:=Top+1; end;
function TVM.pop:Variant; begin Top:=Top-1; PVRec(@Result)^.VType:=2; PVRec(@Result)^.Payload:=Data[Top]; end;
var vm:TVM; g:TPyDict; vmv:Variant; fails:Integer; i:Integer;
procedure Run(const s:AnsiString); var l:TPyDict; begin l:=TPyDict.Create; EvalPyStmts(s,g,l); end;
procedure ChkStk(const lbl:AnsiString; want:Int64);
begin vm.Top:=vm.Top-1; if vm.Data[vm.Top]=want then writeln('ok   ',lbl,' = ',want) else begin writeln('FAIL ',lbl,' got ',vm.Data[vm.Top],' want ',want); fails:=fails+1; end; end;
begin
  fails:=0; vm:=TVM.Create;
  vm.stack:=TPyList.Create; for i:=0 to 4 do vm.stack.append(pyvar_of_int(i+1));
  vm.vars:=TPyDict.Create;
  g:=TPyDict.Create; PVRec(@vmv)^.VType:=7; PVRec(@vmv)^.Payload:=Int64(Pointer(vm)); g.store('vm',vmv);
  { isinstance }
  vm.Top:=0; Run('x = 5'+#10+'push(1 if isinstance(x, int) else 0)'); ChkStk('isinstance int',1);
  vm.Top:=0; Run('x = "s"'+#10+'push(1 if isinstance(x, int) else 0)'); ChkStk('isinstance str not int',0);
  vm.Top:=0; Run('x = "s"'+#10+'push(1 if isinstance(x, str) else 0)'); ChkStk('isinstance str',1);
  vm.Top:=0; Run('x = [1,2]'+#10+'push(1 if isinstance(x, list) else 0)'); ChkStk('isinstance list',1);
  { del subscript on host list }
  vm.Top:=0; Run('del vm.stack[-1]'+#10+'push(len(vm.stack))'); ChkStk('del stack[-1]',4);
  vm.Top:=0; Run('del vm.stack[0]'+#10+'push(len(vm.stack))'); ChkStk('del stack[0]',3);
  { del local }
  vm.Top:=0; Run('a = 5'+#10+'del a'+#10+'push(7)'); ChkStk('del local',7);
  { dict literal + access }
  vm.Top:=0; Run('d = {"a": 10, "b": 20}'+#10+'push(d["b"])'); ChkStk('dict literal',20);
  { empty dict then set item }
  vm.Top:=0; Run('d = {}'+#10+'d["k"] = 99'+#10+'push(d["k"])'); ChkStk('empty dict store',99);
  { set literal (backed by list) }
  vm.Top:=0; Run('s = {1, 2, 3}'+#10+'push(len(s))'); ChkStk('set literal',3);
  { dict into host field }
  vm.Top:=0; Run('vm.vars["x"] = 42'+#10+'push(vm.vars["x"])'); ChkStk('host dict store',42);
  writeln;
  if fails=0 then writeln('ALL PASS') else begin writeln(fails,' FAIL'); halt(1); end;
end.
