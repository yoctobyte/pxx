program RecordAbiMixedLink;
{ The PASCAL half of the i386 aggregate-layout oracle. A `record` and the
  `struct` a C compiler builds from the same fields must have the same size and
  the same field offsets, because a record crosses a `cdecl` boundary and now a
  `cvar` global too.

  THIS EXISTS BECAUSE NO PXX-ONLY TEST COULD SEE THE BUG. Every frontend's i386
  layout was self-consistent, so a whole-program run agreed with itself while
  disagreeing with the platform. What made it visible was ONE COMPILER
  DISAGREEING WITH ITSELF: pxx's C frontend answered sizeof 12 / offset 4 for
  `struct MIX {int a; double y;}` and pxx's Pascal frontend answered 16 / 8 for
  the same fields, in the same invocation family, for the same target.

  The gcc `main` this links against carries its OWN copy of every struct and
  compares three answers, not two -- so a row cannot pass by pxx being
  self-consistently wrong, which is exactly the state this replaced.
  bug-a-pascal-nilpy-rust-and-zig-over-align-an-8-byte-member-on-i386 }

type
  TMix   = record a: Integer; y: Double; end;         { 8-byte member after a 4 }
  TCharQ = record c: Byte; q: Int64; end;             { the same, via Int64 }
  TWideC = record y: Double; c: Byte; end;            { trailing pad, not leading }
  TNest  = record h: Integer; inner: TMix; end;       { the inner record's own alignment }

var
  GMix: TMix; cvar;    { the value round trip: C writes these, Pascal reads them }

function p_size(k: Integer): Integer; cdecl;
begin
  case k of
    0: p_size := SizeOf(TMix);
    1: p_size := SizeOf(TCharQ);
    2: p_size := SizeOf(TWideC);
    3: p_size := SizeOf(TNest);
  else p_size := -1;
  end;
end;

function p_off(k: Integer): Integer; cdecl;
{ The offset of the SECOND field, taken from addresses rather than from a
  compiler-computed constant: the question is where the field really is. }
var m: TMix; cq: TCharQ; wc: TWideC; ns: TNest;
begin
  case k of
    0: p_off := Integer(PtrUInt(@m.y)  - PtrUInt(@m));
    1: p_off := Integer(PtrUInt(@cq.q) - PtrUInt(@cq));
    2: p_off := Integer(PtrUInt(@wc.c) - PtrUInt(@wc));
    3: p_off := Integer(PtrUInt(@ns.inner) - PtrUInt(@ns));
  else p_off := -1;
  end;
end;

function p_mix_a: Integer; cdecl;
begin
  p_mix_a := GMix.a;
end;

function p_mix_y_is(v: Double): Integer; cdecl;
{ Compared here rather than returned, so the row does not also depend on the
  i386 double RETURN convention -- one question per assertion. }
begin
  if GMix.y = v then p_mix_y_is := 1 else p_mix_y_is := 0;
end;

begin
end.
