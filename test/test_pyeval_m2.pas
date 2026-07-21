{ pyeval M2 tests (feature-lib-pyexec): host FIELD reflection — attribute
  read/write (scalar + augassign), subscript read/write over bytes/list (Python
  negative indexing), computed-address stores, and attr/subscript inside loops
  and conditionals. This is the vm.memory[]/vm.here access the Forth STORE/FETCH
  family needs. }
program test_pyeval_m2;
uses pylib, typinfo, pyeval;
type PVRec=^TVRec; TVRec=record VType,Payload:Int64;end;
  TVM=class
    Data:array[0..63] of Int64; Top:Integer;
    here: Integer; base: Integer; trace: Boolean;
    memory: TPyBytes; stack: TPyList;
    procedure push(const v:Variant); function pop:Variant; end;
procedure TVM.push(const v:Variant); begin Data[Top]:=PVRec(@v)^.Payload; Top:=Top+1; end;
function TVM.pop:Variant; begin Top:=Top-1; PVRec(@Result)^.VType:=2; PVRec(@Result)^.Payload:=Data[Top]; end;
var vm:TVM; g:TPyDict; vmv:Variant; fails:Integer; i:Integer; sv:Variant;
procedure Run(const src: AnsiString);
var l: TPyDict;
begin vm.Top:=0; l:=TPyDict.Create; EvalPyStmts(src, g, l); end;
procedure ChkStk(const lbl: AnsiString; want: Int64);
begin
  vm.Top:=vm.Top-1;
  if vm.Data[vm.Top]=want then writeln('ok   ',lbl,' = ',want)
  else begin writeln('FAIL ',lbl,' got ',vm.Data[vm.Top],' want ',want); fails:=fails+1; end;
end;
procedure ChkI(const lbl: AnsiString; got, want: Int64);
begin
  if got=want then writeln('ok   ',lbl,' = ',want)
  else begin writeln('FAIL ',lbl,' got ',got,' want ',want); fails:=fails+1; end;
end;
begin
  fails:=0; vm:=TVM.Create; g:=TPyDict.Create;
  vm.here:=100; vm.base:=10; vm.trace:=False;
  vm.memory := TPyBytes.Create(0); for i:=0 to 15 do vm.memory.append(i*2);
  vm.stack := TPyList.Create; for i:=0 to 4 do vm.stack.append(pyvar_of_int(i+1));
  PVRec(@vmv)^.VType:=7; PVRec(@vmv)^.Payload:=Int64(Pointer(vm)); g.store('vm',vmv);

  { attribute read }
  Run('push(vm.here)'); ChkStk('read here', 100);
  Run('push(vm.base)'); ChkStk('read base', 10);
  { attribute write scalar }
  Run('vm.here = 250'); ChkI('write here', vm.here, 250);
  Run('vm.trace = True'); ChkI('write trace true', Ord(vm.trace), 1);
  Run('vm.trace = False'); ChkI('write trace false', Ord(vm.trace), 0);
  { attribute augassign }
  vm.here := 100;
  Run('vm.here += 5'); ChkI('here += 5', vm.here, 105);
  Run('vm.here -= 20'); ChkI('here -= 20', vm.here, 85);
  { attribute read in expression }
  vm.here := 40;
  Run('push(vm.here + vm.base)'); ChkStk('here+base', 50);
  { subscript read: bytes }
  Run('push(vm.memory[3])'); ChkStk('memory[3]', 6);
  Run('push(vm.memory[0])'); ChkStk('memory[0]', 0);
  { subscript read: list, negative }
  Run('push(vm.stack[-1])'); ChkStk('stack[-1]', 5);
  Run('push(vm.stack[0])'); ChkStk('stack[0]', 1);
  { subscript write: bytes }
  Run('vm.memory[5] = 99'); ChkI('memory[5]=99', vm.memory.at(5), 99);
  { subscript write: list }
  Run('vm.stack[2] = 77'); sv:=vm.stack.at(2); ChkI('stack[2]=77', PVRec(@sv)^.Payload, 77);
  { store-word idiom: vm.memory[addr] = val with computed addr }
  vm.here := 7;
  Run('addr = vm.here'+#10+'vm.memory[addr] = 42'); ChkI('memory[here]=42', vm.memory.at(7), 42);
  { loop over memory writing }
  Run('for k in range(3):'+#10+'    vm.memory[k] = k + 10'); 
  ChkI('loop mem0', vm.memory.at(0), 10); ChkI('loop mem2', vm.memory.at(2), 12);
  { if using attribute + subscript }
  vm.here := 4;
  Run('if vm.here < 10:'+#10+'    push(vm.memory[vm.here])');
  ChkStk('cond mem[here]', vm.memory.at(4));

  writeln;
  if fails=0 then writeln('ALL PASS') else begin writeln(fails,' FAIL'); halt(1); end;
end.
