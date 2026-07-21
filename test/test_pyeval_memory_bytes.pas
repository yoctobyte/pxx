{ pyeval MEMORY store-word tests (feature-lib-pyexec): slice-assignment
  (vm.memory[a:b]=…), int.to_bytes/int.from_bytes with signed=, signed cell
  round-trip — the Forth , ! @ family. }
program test_pyeval_memory_bytes;
uses pylib, typinfo, pyeval;
type PVRec=^TVRec; TVRec=record VType,Payload:Int64;end;
  TVM=class Data:array[0..63] of Int64; Top:Integer; here:Integer; memory:TPyBytes;
    procedure push(const v:Variant); function pop:Variant; end;
procedure TVM.push(const v:Variant); begin Data[Top]:=PVRec(@v)^.Payload; Top:=Top+1; end;
function TVM.pop:Variant; begin Top:=Top-1; PVRec(@Result)^.VType:=2; PVRec(@Result)^.Payload:=Data[Top]; end;
var vm:TVM; g:TPyDict; vmv:Variant; fails:Integer; i:Integer;
procedure Run(const s:AnsiString); var l:TPyDict; begin l:=TPyDict.Create; EvalPyStmts(s,g,l); end;
procedure ChkStk(const lbl:AnsiString; want:Int64);
begin vm.Top:=vm.Top-1; if vm.Data[vm.Top]=want then writeln('ok   ',lbl,' = ',want) else begin writeln('FAIL ',lbl,' got ',vm.Data[vm.Top],' want ',want); fails:=fails+1; end; end;
begin
  fails:=0; vm:=TVM.Create; vm.here:=0;
  vm.memory:=TPyBytes.Create(64);
  g:=TPyDict.Create; PVRec(@vmv)^.VType:=7; PVRec(@vmv)^.Payload:=Int64(Pointer(vm)); g.store('vm',vmv);
  { `,` store an 8-byte cell then read it back }
  vm.Top:=0;
  Run('val = 0x1234'+#10+'addr = vm.here'+#10+'vm.memory[addr:addr+8] = val.to_bytes(8, ''little'', signed=True)'+#10+'vm.here += 8');
  Run('x = int.from_bytes(vm.memory[0:8], ''little'', signed=True)'+#10+'push(x)');
  ChkStk('store+load 0x1234', $1234);
  { negative value round trip }
  vm.Top:=0;
  Run('vm.memory[8:16] = (-5).to_bytes(8, ''little'', signed=True)');
  Run('push(int.from_bytes(vm.memory[8:16], ''little'', signed=True))');
  ChkStk('store+load -5', -5);
  writeln;
  if fails=0 then writeln('ALL PASS') else begin writeln(fails,' FAIL'); halt(1); end;
end.
