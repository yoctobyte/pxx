program repro_multiunit_rtti_segfault;
{ PRE-EXISTING COMPILER BUG (predates Phase 5; reproduces at commit fd1c3b4).
  4+ units that pull in typinfo's RTTI + a published class with an inherited
  property => GetPropInfo walks a WILD NamePtr => SIGSEGV.
  Fault is inside typinfo.GetPropInfo at the inline string-compare
  (props[i].NamePtr^ = name); NamePtr is a corrupt pointer.
  Heisenbug: adding locals/writelns near the call shifts code layout and can
  make it pass, so it is layout/relocation sensitive (data-ptr fixup or codegen).
  3 units (typinfo, streams, classes_lite) WORK; adding any 4th (math here)
  breaks it. Blocks Phase 5 LFM, which inherently needs 5 units. }
uses typinfo, streams, classes_lite, math;
type
  TF = class(TComponent)
  private FA: Integer; FB: Integer;
  published
    property A: Integer read FA write FA;
    property B: Integer read FB write FB;
  end;
var cls: PClassRTTI; p: PPropInfo;
begin
  cls := GetClass('TF');
  if cls = nil then begin writeln('cls nil'); Halt(1); end;
  writeln('propcount=', cls^.PropCount);   { prints 2 (correct) }
  p := GetPropInfo(cls, 'Name');            { SIGSEGV here: wild NamePtr }
  if p <> nil then writeln('Name found') else writeln('NOT found');
end.
