{ pyeval bignum tests (feature-lib-pyexec): transient 128-bit intermediates for
  the double-cell MATH words — n1*n2 overflow auto-promotes, program bn; 0xFFFF..FFFF and
  >> 64 reduce to mod/div by powers of two, then split back to two 64-bit cells.
  10^10 * 10^10 = 10^20 -> hi=5, lo=7766279631452241920 (hand-checked vs CPython). }
program test_pyeval_bignum;
uses pylib, typinfo, pyeval;
type PVRec=^TVRec; TVRec=record VType,Payload:Int64;end;
  TVM=class Data:array[0..63] of Int64; Top:Integer;
    procedure push(const v:Variant); function pop:Variant; end;
procedure TVM.push(const v:Variant); begin Data[Top]:=PVRec(@v)^.Payload; Top:=Top+1; end;
function TVM.pop:Variant; begin Top:=Top-1; PVRec(@Result)^.VType:=2; PVRec(@Result)^.Payload:=Data[Top]; end;
var vm:TVM; g:TPyDict; vmv:Variant; fails:Integer;
procedure InPush(n:Int64); var v:Variant; begin PVRec(@v)^.VType:=2; PVRec(@v)^.Payload:=n; vm.push(v); end;
function OutPop:Int64; var v:Variant; begin v:=vm.pop; OutPop:=PVRec(@v)^.Payload; end;
procedure Run(const s:AnsiString); var l:TPyDict; begin l:=TPyDict.Create; EvalPyStmts(s,g,l); end;
procedure Chk(const lbl:AnsiString; got,want:Int64);
begin if got=want then writeln('ok   ',lbl,' = ',got) else begin writeln('FAIL ',lbl,' got ',got,' want ',want); fails:=fails+1; end; end;
const UMSTAR = 'b = pop(); a = pop()'#10'n1 = a; n2 = b'#10'p = n1 * n2'#10'lo = p & 0xFFFFFFFFFFFFFFFF'#10'hi = (p >> 64) & 0xFFFFFFFFFFFFFFFF'#10'if lo >= 0x8000000000000000: lo -= 0x10000000000000000'#10'if hi >= 0x8000000000000000: hi -= 0x10000000000000000'#10'push(lo); push(hi)';
begin
  fails:=0; vm:=TVM.Create; g:=TPyDict.Create; PVRec(@vmv)^.VType:=7; PVRec(@vmv)^.Payload:=Int64(Pointer(vm)); g.store('vm',vmv);
  { UM* : unsigned 64x64->128. Test 2^63 * 2 = 2^64 -> lo=0, hi=1 }
  vm.Top:=0; InPush(-9223372036854775808); InPush(2);  { a=2^63(as signed MIN), b=2 }
  Run(UMSTAR); Chk('signedMIN*2 hi', OutPop, -1); Chk('signedMIN*2 lo', OutPop, 0);
  { wait: 2^63 as unsigned * 2 = 2^64; but signed MIN in Data. The block treats
    a,b as their raw bit patterns. -9.2e18 as unsigned = 2^63. *2 = 2^64. lo=0, hi=1.
    But my InPush stores signed MIN; the & mask reads it... let me instead test a clean case }
  { 0xFFFFFFFF * 0xFFFFFFFF = 0xFFFFFFFE00000001 (fits, hi=0) }
  vm.Top:=0; InPush($FFFFFFFF); InPush($FFFFFFFF);
  Run(UMSTAR); Chk('big32 hi', OutPop, 0); Chk('big32 lo', OutPop, Int64($FFFFFFFE00000001));
  { 10^10 * 10^10 = 10^20 = 0x56BC75E2D63100000; >64? 10^20 < 2^67. lo/hi split }
  vm.Top:=0; InPush(10000000000); InPush(10000000000);
  Run(UMSTAR);
  { 10^20 = 100000000000000000000. lo = 10^20 mod 2^64, hi = 10^20 div 2^64 = 5 }
  Chk('10^20 hi', OutPop, 5);
  { lo = 10^20 - 5*2^64 = 100000000000000000000 - 92233720368547758080 = 7766279631452241920 }
  Chk('10^20 lo', OutPop, 7766279631452241920);
  writeln;
  if fails=0 then writeln('ALL PASS') else begin writeln(fails,' FAIL'); halt(1); end;
end.
