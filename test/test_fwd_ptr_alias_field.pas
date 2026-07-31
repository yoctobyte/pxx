{ bug-pascal-transitive-unit-crashes-at-startup-unless-named-first:
  a forward pointer type (`PX = ^TX;`) whose target is only later declared as
  a plain type ALIAS (`TX = TReal2;`, not a fresh `record ... end`) used to
  leave the pointer's pointee-record binding unpatched: every field access
  through such a pointer silently fell back to offset 0 / tyInteger instead
  of the field's real offset and type. This is the general, non-library form
  of the bug (no units/Synapse needed) — the real-world trigger was Synapse's
  `PInAddr6 = ^TInAddr6; TInAddr6 = sockets.Tin6_addr;` in ssfpc.inc, which
  corrupted an unrelated global at startup and crashed before main() ran. }
program test_fwd_ptr_alias_field;

type
  TReal2 = record
    a: Integer;
    b: Integer;
  end;
  PX = ^TX;        { forward: TX doesn't exist yet }
  TX = TReal2;      { TX is a plain ALIAS, not a fresh record }

procedure Setter(const p: PX);
begin
  p^.a := 11;
  p^.b := 22;
end;

var
  x: TX;
begin
  x.a := 0;
  x.b := 0;
  Setter(@x);
  WriteLn(x.a, ' ', x.b);
end.
