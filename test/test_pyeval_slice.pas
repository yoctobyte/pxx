{ pyeval slice tests (feature-lib-pyexec): str/bytes/list slicing incl. open bounds and the hex(x)[2:] strip-0x idiom. }
program test_pyeval_slice;
uses pylib, typinfo, pyeval;
type PVRec=^TVRec; TVRec=record VType,Payload:Int64;end;
  TVM=class Data:array[0..63] of Int64; Top:Integer;
    memory:TPyBytes;
    procedure push(const v:Variant); function pop:Variant; end;
procedure TVM.push(const v:Variant); begin Data[Top]:=PVRec(@v)^.Payload; Top:=Top+1; end;
function TVM.pop:Variant; begin Top:=Top-1; PVRec(@Result)^.VType:=2; PVRec(@Result)^.Payload:=Data[Top]; end;
var vm:TVM; g:TPyDict; vmv:Variant; fails:Integer; i:Integer;
procedure Run(const s: AnsiString); var l:TPyDict; begin l:=TPyDict.Create; EvalPyStmts(s,g,l); end;
procedure ChkStk(const lbl:AnsiString; want:Int64);
begin vm.Top:=vm.Top-1; if vm.Data[vm.Top]=want then writeln('ok   ',lbl,' = ',want) else begin writeln('FAIL ',lbl,' got ',vm.Data[vm.Top],' want ',want); fails:=fails+1; end; end;
begin
  fails:=0; vm:=TVM.Create; g:=TPyDict.Create;
  vm.memory:=TPyBytes.Create(0); for i:=0 to 15 do vm.memory.append(i);
  PVRec(@vmv)^.VType:=7; PVRec(@vmv)^.Payload:=Int64(Pointer(vm)); g.store('vm',vmv);
  { string slice }
  vm.Top:=0; Run('s = "hello world"'+#10+'push(len(s[0:5]))'); ChkStk('str[0:5] len',5);
  vm.Top:=0; Run('s = "hexval"'+#10+'push(len(s[2:]))'); ChkStk('str[2:] len',4);
  vm.Top:=0; Run('s = "hexval"'+#10+'push(len(s[:3]))'); ChkStk('str[:3] len',3);
  { hex(x)[2:] idiom -> strip 0x }
  vm.Top:=0; Run('h = hex(255)'+#10+'push(len(h[2:]))'); ChkStk('hex[2:] len',2);
  { bytes slice }
  vm.Top:=0; Run('b = vm.memory[2:6]'+#10+'push(len(b))'); ChkStk('bytes[2:6] len',4);
  { list slice via literal }
  vm.Top:=0; Run('xs = [10,20,30,40,50]'+#10+'push(len(xs[1:4]))'); ChkStk('list[1:4] len',3);
  writeln;
  if fails=0 then writeln('ALL PASS') else begin writeln(fails,' FAIL'); halt(1); end;
end.
