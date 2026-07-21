{ pyeval M3 tests (feature-lib-pyexec): method calls — str methods (upper/join),
  list methods (append/insert), list literals, and HOST vm methods dispatched
  through the reflection trampoline (vm.push/vm.pop), plus the pictured-output
  build idiom. }
program test_pyeval_m3;
uses pylib, typinfo, pyeval;
type PVRec=^TVRec; TVRec=record VType,Payload:Int64;end;
  TVM=class
    Data:array[0..63] of Int64; Top:Integer;
    pic: TPyList;
    procedure push(const v:Variant); function pop:Variant; end;
procedure TVM.push(const v:Variant); begin Data[Top]:=PVRec(@v)^.Payload; Top:=Top+1; end;
function TVM.pop:Variant; begin Top:=Top-1; PVRec(@Result)^.VType:=2; PVRec(@Result)^.Payload:=Data[Top]; end;
var vm:TVM; g:TPyDict; vmv:Variant; fails:Integer;
procedure Run(const src: AnsiString);
var l: TPyDict;
begin l:=TPyDict.Create; EvalPyStmts(src, g, l); end;
procedure ChkStk(const lbl: AnsiString; want: Int64);
begin vm.Top:=vm.Top-1;
  if vm.Data[vm.Top]=want then writeln('ok   ',lbl,' = ',want)
  else begin writeln('FAIL ',lbl,' got ',vm.Data[vm.Top],' want ',want); fails:=fails+1; end;
end;
procedure ChkS(const lbl, got, want: AnsiString);
begin if got=want then writeln('ok   ',lbl,' = ',want)
  else begin writeln('FAIL ',lbl,' got [',got,'] want [',want,']'); fails:=fails+1; end;
end;
begin
  fails:=0; vm:=TVM.Create; g:=TPyDict.Create;
  vm.pic := TPyList.Create;
  PVRec(@vmv)^.VType:=7; PVRec(@vmv)^.Payload:=Int64(Pointer(vm)); g.store('vm',vmv);
  { str methods }
  vm.Top:=0; Run('s = "hello"'+#10+'push(len(s.upper()))'); ChkStk('upper len',5);
  { str.join over a list built in-place }
  vm.Top:=0; Run('xs = ["a","b","c"]'+#10+'r = "-".join(xs)'+#10+'push(len(r))'); ChkStk('join len',5);
  { list append/insert on a host field }
  vm.Top:=0; Run('vm.pic.append("x")'+#10+'vm.pic.insert(0, "y")'+#10+'push(len(vm.pic))'); ChkStk('pic len',2);
  { explicit vm.push through method dispatch -> trampoline }
  vm.Top:=0; Run('vm.push(123)'); ChkStk('vm.push',123);
  { vm.pop through trampoline }
  vm.Top:=0; vm.Data[0]:=55; vm.Top:=1;
  Run('x = vm.pop()'+#10+'vm.push(x + 1)'); ChkStk('vm.pop+1',56);
  { build pictured output: join chars }
  vm.Top:=0; Run('buf = []'+#10+'for c in ["1","2","3"]:'+#10+'    buf.insert(0, c)'+#10+'r = "".join(buf)'+#10+'push(len(r))'); ChkStk('picbuf',3);
  writeln;
  if fails=0 then writeln('ALL PASS') else begin writeln(fails,' FAIL'); halt(1); end;
end.
