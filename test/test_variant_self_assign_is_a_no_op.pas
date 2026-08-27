program test_variant_self_assign_is_a_no_op;
{ `v := v` must leave the variant ALONE. It emptied it instead, on every target,
  and leaked the payload while doing so.

  bug-a-a-variant-assigned-to-itself-becomes-empty. Every backend's
  variant-to-variant arm is retain(src) / clear(dest) / copy 16 bytes, and the
  retain-before-clear that guards the aliased case guards the payload's
  REFCOUNT — not the slot BYTES. PXXVarClear ends in PXXMemZero(v, 16), so when
  src and dest are the same slot it wiped the bytes the copy was about to read
  and the copy faithfully copied sixteen zeroes. FPC leaves the value.

  The fix removed the zeroing from that path (PXXVarReleasePayload / the
  x86-64 VariantRelPayload blob) rather than branching on `src = dest`: the
  bytes are overwritten by the copy on the next instruction, so the zeroing was
  never wanted here and self-assignment falls out as the degenerate case.

  Expectations are FPC's, verified by running fpc -O1 on this source. }

var
  v, w: Variant;
  s: AnsiString;
  i: LongInt;   { LongInt, not Integer: FPC's default mode makes Integer 16-bit,
                  and this file is meant to compile under fpc as its own oracle }
  ok: Boolean;

procedure Both(var a: Variant; var b: Variant);
{ Aliasing the compiler cannot see: called as Both(v, v), so the store below is
  a self-assignment only at run time. A `src = dest` test would have had to be a
  RUNTIME one to catch this; removing the zeroing catches it with no test. }
begin
  a := b;
end;

begin
  ok := True;

  s := 'ab'; v := s;
  v := v;
  writeln(v);                       if v <> 'ab' then ok := False;

  v := 42;
  v := v;
  writeln(v);                       if v <> 42 then ok := False;

  v := 2.5;
  v := v;
  writeln(v);                       if v <> 2.5 then ok := False;

  { the same through var parameters, where the alias is invisible to codegen }
  s := 'cd'; v := s;
  Both(v, v);
  writeln(v);                       if v <> 'cd' then ok := False;

  { and the ordinary two-slot case must still work — this is the path the fix
    touched, so it needs saying out loud that it did not break }
  s := 'ef'; v := s; w := 'zz';
  w := v;
  writeln(w);                       if w <> 'ef' then ok := False;
  writeln(v);                       if v <> 'ef' then ok := False;

  { The leak half. The old path took the payload to +2 with the retain, back to
    +1 with the clear, and then zeroed the only slot that referenced it — one
    orphaned string per self-assignment. 200000 iterations is far past what a
    per-iteration leak survives inside the default heap. }
  for i := 1 to 200000 do
  begin
    s := 'x';
    v := s + 'y';
    v := v;
  end;
  writeln(v);                       if v <> 'xy' then ok := False;

  if ok then writeln('ALL OK') else writeln('FAILED');
end.
