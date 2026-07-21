{ pyeval f-string tests (feature-lib-pyexec): plain/expression holes, format
  specs (02X), literals, multiple holes, escaped braces — desugared to __fmt. }
program test_pyeval_fstring;
uses pylib, typinfo, pyeval;
type PVRec=^TVRec; TVRec=record VType,Payload:Int64;end;
  TVM=class Data:array[0..63] of Int64; Top:Integer;
    outp: TPyList;
    procedure push(const v:Variant); function pop:Variant;
    procedure emit(const s: Variant); end;
procedure TVM.push(const v:Variant); begin Data[Top]:=PVRec(@v)^.Payload; Top:=Top+1; end;
function TVM.pop:Variant; begin Top:=Top-1; PVRec(@Result)^.VType:=2; PVRec(@Result)^.Payload:=Data[Top]; end;
procedure TVM.emit(const s: Variant); begin outp.append(s); end;
var vm:TVM; g:TPyDict; vmv:Variant; fails:Integer;
procedure Run(const s:AnsiString); var l:TPyDict; begin l:=TPyDict.Create; EvalPyStmts(s,g,l); end;
procedure ChkStk(const lbl:AnsiString; want:Int64);
begin vm.Top:=vm.Top-1; if vm.Data[vm.Top]=want then writeln('ok   ',lbl,' = ',want) else begin writeln('FAIL ',lbl,' got ',vm.Data[vm.Top],' want ',want); fails:=fails+1; end; end;
procedure ChkLast(const lbl, want: AnsiString);
var v: Variant; got: AnsiString;
begin v := vm.outp.at(vm.outp.count-1); got := pystr_of(v);
  if got=want then writeln('ok   ',lbl,' = [',want,']') else begin writeln('FAIL ',lbl,' got [',got,'] want [',want,']'); fails:=fails+1; end; end;
begin
  fails:=0; vm:=TVM.Create; vm.outp:=TPyList.Create;
  g:=TPyDict.Create; PVRec(@vmv)^.VType:=7; PVRec(@vmv)^.Payload:=Int64(Pointer(vm)); g.store('vm',vmv);
  { plain hole }
  vm.Top:=0; Run('val = 42'+#10+'push(len(f"{val}"))'); ChkStk('f{val} len',2);
  { hex format 02X }
  Run('val = 255'+#10+'vm.emit(f"{val:02X}")'); ChkLast('02X','FF');
  Run('val = 5'+#10+'vm.emit(f"{val:02X}")'); ChkLast('02X pad','05');
  { literal + hole + literal }
  Run('n = 7'+#10+'vm.emit(f"[{n}]")'); ChkLast('bracketed','[7]');
  { multiple holes }
  Run('a = 1'+#10+'b = 2'+#10+'vm.emit(f"{a},{b}")'); ChkLast('two holes','1,2');
  { hole with expression }
  Run('x = 10'+#10+'vm.emit(f"{x + 5}")'); ChkLast('expr hole','15');
  { escaped braces }
  Run('vm.emit(f"{{literal}}")'); ChkLast('escaped','{literal}');
  writeln;
  if fails=0 then writeln('ALL PASS') else begin writeln(fails,' FAIL'); halt(1); end;
end.
