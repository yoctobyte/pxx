{ pyeval generalized-trampoline tests (feature-lib-pyexec): host methods with
  arbitrary Variant-arg signatures (define_word, add3), string-return
  (next_token_strict), and void multi-arg — the shapes a NilPy-compiled vm needs. }
program test_pyeval_trampoline_shapes;
uses pylib, typinfo, pyeval;
type PVRec=^TVRec; TVRec=record VType,Payload:Int64;end;
  { host with NilPy-style all-Variant signatures + string return }
  TVM=class
    Data:array[0..63] of Int64; Top:Integer;
    words: TPyList;
    toknum: Integer;
    procedure push(const v:Variant); function pop:Variant;
    function define_word(const nm: Variant; const body: Variant): Variant;   { 2 Variant args, Variant ret }
    function next_token_strict: AnsiString;                                   { string ret, 0 args }
    function add3(const a: Variant; const b: Variant; const c: Variant): Variant; { 3 args }
    procedure noop2(const a: Variant; const b: Variant);                      { void, 2 args }
  end;
procedure TVM.push(const v:Variant); begin Data[Top]:=PVRec(@v)^.Payload; Top:=Top+1; end;
function TVM.pop:Variant; begin Top:=Top-1; PVRec(@Result)^.VType:=2; PVRec(@Result)^.Payload:=Data[Top]; end;
function TVM.define_word(const nm: Variant; const body: Variant): Variant;
begin words.append(nm); PVRec(@Result)^.VType:=2; PVRec(@Result)^.Payload:=words.count; end;
function TVM.next_token_strict: AnsiString;
begin toknum:=toknum+1; next_token_strict := 'WORD'; end;
function TVM.add3(const a: Variant; const b: Variant; const c: Variant): Variant;
begin PVRec(@Result)^.VType:=2; PVRec(@Result)^.Payload:=pyvar_to_int(a)+pyvar_to_int(b)+pyvar_to_int(c); end;
procedure TVM.noop2(const a: Variant; const b: Variant); begin end;
var vm:TVM; g:TPyDict; vmv:Variant; fails:Integer;
procedure Run(const s:AnsiString); var l:TPyDict; begin l:=TPyDict.Create; EvalPyStmts(s,g,l); end;
procedure ChkStk(const lbl:AnsiString; want:Int64);
begin vm.Top:=vm.Top-1; if vm.Data[vm.Top]=want then writeln('ok   ',lbl,' = ',want) else begin writeln('FAIL ',lbl,' got ',vm.Data[vm.Top],' want ',want); fails:=fails+1; end; end;
begin
  fails:=0; vm:=TVM.Create; vm.words:=TPyList.Create; vm.toknum:=0;
  g:=TPyDict.Create; PVRec(@vmv)^.VType:=7; PVRec(@vmv)^.Payload:=Int64(Pointer(vm)); g.store('vm',vmv);
  { 2-arg Variant method returning Variant }
  vm.Top:=0; Run('r = vm.define_word("DUP", 42)'+#10+'push(r)'); ChkStk('define_word ret',1);
  vm.Top:=0; Run('vm.define_word("SWAP", 0)'+#10+'push(len(vm.words))'); ChkStk('words grew',2);
  { string-return method: len of returned token }
  vm.Top:=0; Run('t = vm.next_token_strict()'+#10+'push(len(t))'); ChkStk('next_token len',4);
  { 3-arg }
  vm.Top:=0; Run('push(vm.add3(10, 20, 12))'); ChkStk('add3',42);
  { void 2-arg }
  vm.Top:=0; Run('vm.noop2(1, 2)'+#10+'push(99)'); ChkStk('noop2 then push',99);
  writeln;
  if fails=0 then writeln('ALL PASS') else begin writeln(fails,' FAIL'); halt(1); end;
end.
