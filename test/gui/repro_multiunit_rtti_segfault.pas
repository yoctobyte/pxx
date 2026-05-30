program repro_multiunit_rtti_segfault;
{ Regression test for the multi-unit RTTI segfault (fixed 2026-05-30).
  Was: 4+ units pulling in typinfo's RTTI + a published class with an inherited
  property => GetPropInfo walked a WILD NamePtr => SIGSEGV. Root cause was NOT
  unit count: EmitPropInfo interned each prop name (which appends to Data[])
  *between* the per-prop record reservations, so the runtime's fixed-64-byte
  props[i] stride landed on interleaved string data. Adding a 4th unit just
  changed which names were already interned, hence the heisenbug. Fixed by
  reserving the prop/meth array contiguously before filling (rtti_emit.inc).
  Expected output: "propcount=2" then "Name found". }
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
