{ %FAIL-style negative: `.member` on a memberless SCALAR variable.

  This COMPILED and read the value's own bytes back as an integer. For
  s = 'Hello', `s.Length` printed 1819043144 — the four bytes of 'Hell' as an
  Int32 — and `s.NoSuchMember` printed exactly the same, with no diagnostic
  either way. Ints and booleans answered with themselves, floats with 0.

  `s.Length` / `s.ToUpper` / `s.Trim` is Delphi's TStringHelper surface, which
  FPC compiles under {$modeswitch typehelpers} and pxx does not implement — so
  this is the shape real code arrives in, not a synthetic one. Refusing is the
  honest answer until the helpers exist (feature-p-delphi-string-helpers), and
  the message has to say WHICH it is: a reader who gets a plausible number back
  has no reason to suspect the compiler.

  Sibling of test_array_member_fail.pas, which is where the same refusal for
  arrays already lives — its own note assumed strings were covered by the
  Length() intrinsic, and nothing checked.
  bug-p-a-member-on-a-scalar-silently-reads-the-values-own-bytes }
program test_scalar_member_fail;
var s: string;
begin
  s := 'Hello';
  writeln(s.Length);
end.
