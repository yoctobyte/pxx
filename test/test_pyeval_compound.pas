{ pyeval compound-block tests (feature-lib-pyexec): if/elif/else (inline + block),
  while (+break), for-in over range(), and nesting — results observed by pushing
  onto a stub VM stack. Complements test/test_pyeval_m1.pas (expression + host
  bridge). }
program test_pyeval_compound;
uses pylib, typinfo, pyeval;
type PVRec=^TVRec; TVRec=record VType,Payload:Int64;end;
  TVM=class Data:array[0..63] of Int64; Top:Integer;
    procedure push(const v:Variant); function pop:Variant; end;
procedure TVM.push(const v:Variant); begin Data[Top]:=PVRec(@v)^.Payload; Top:=Top+1; end;
function TVM.pop:Variant; begin Top:=Top-1; PVRec(@Result)^.VType:=2; PVRec(@Result)^.Payload:=Data[Top]; end;
var vm:TVM; g:TPyDict; vmv:Variant; fails:Integer;
procedure Run(const src: AnsiString);
var l: TPyDict;
begin vm.Top:=0; l:=TPyDict.Create; EvalPyStmts(src, g, l); end;
procedure Chk(const lbl: AnsiString; want: Int64);
var v: Variant;
begin
  vm.Top:=vm.Top-1; v:=vm.Data[vm.Top];
  if PVRec(@v)^.Payload = want then writeln('ok   ',lbl,' = ',want)
  else begin writeln('FAIL ',lbl,' got ',vm.Data[vm.Top],' want ',want); fails:=fails+1; end;
end;
begin
  fails:=0; vm:=TVM.Create; g:=TPyDict.Create;
  PVRec(@vmv)^.VType:=7; PVRec(@vmv)^.Payload:=Int64(Pointer(vm)); g.store('vm',vmv);
  Run('r=0'+#10+'if 3>2: r=5'+#10+'push(r)'); Chk('inline-if-true',5);
  Run('r=0'+#10+'if 1>2: r=5'+#10+'push(r)'); Chk('inline-if-false',0);
  Run('x=2'+#10+'if x==1:'+#10+'    r=10'+#10+'elif x==2:'+#10+'    r=20'+#10+'else:'+#10+'    r=30'+#10+'push(r)'); Chk('elif',20);
  Run('x=9'+#10+'if x==1:'+#10+'    r=10'+#10+'elif x==2:'+#10+'    r=20'+#10+'else:'+#10+'    r=30'+#10+'push(r)'); Chk('else',30);
  Run('r=0'+#10+'i=1'+#10+'while i<=5:'+#10+'    r+=i'+#10+'    i+=1'+#10+'push(r)'); Chk('while-sum',15);
  Run('r=0'+#10+'i=0'+#10+'while i<100:'+#10+'    if i==3:'+#10+'        break'+#10+'    r+=i'+#10+'    i+=1'+#10+'push(r)'); Chk('while-break',3);
  Run('r=0'+#10+'for k in range(4):'+#10+'    r+=k'+#10+'push(r)'); Chk('for-range',6);
  Run('r=0'+#10+'for k in range(2,5):'+#10+'    r+=k'+#10+'push(r)'); Chk('for-range2',9);
  Run('r=0'+#10+'for k in range(10):'+#10+'    if k%2==0:'+#10+'        r+=k'+#10+'push(r)'); Chk('for-nested-if',20);
  { nested for }
  Run('r=0'+#10+'for a in range(3):'+#10+'    for b in range(3):'+#10+'        r+=1'+#10+'push(r)'); Chk('nested-for',9);
  writeln;
  if fails=0 then writeln('ALL PASS') else begin writeln(fails,' FAIL'); halt(1); end;
end.
