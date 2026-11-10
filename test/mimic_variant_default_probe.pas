{ Probe unit for test_nilpy_a_nonzero_variant_default_reaches_the_callee.npy:
  one default of each kind, every one chosen so an UNapplied default cannot
  produce it by accident. }
unit mimic_variant_default_probe;
interface
function vd(v: Variant = 7): Integer;
function vneg(v: Variant = -3): Integer;
function vzero(v: Variant = 0): Integer;
function bd(b: Boolean = True): Boolean;
implementation
function vd(v: Variant): Integer;
begin
  Result := v;
end;
function vneg(v: Variant): Integer;
begin
  Result := v;
end;
{ a ZERO default is the library sentinel for "not supplied": it arrives as
  None (tag 0), which lib/pcl facades test with pyvartag }
function vzero(v: Variant): Integer;
begin
  Result := pyvartag(v);
end;
function bd(b: Boolean): Boolean;
begin
  Result := b;
end;
end.
