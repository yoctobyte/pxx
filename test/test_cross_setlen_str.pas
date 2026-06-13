program test_cross_setlen_str;

{ Cross-target SetLength-on-managed-AnsiString oracle (compile with
  -dPXX_MANAGED_STRING). The cross backends route SetLength(ansistring, n)
  through the portable PXXStrSetLen runtime helper: shrink truncates, grow
  preserves the existing prefix and zero-fills the new tail, n<=0 publishes nil.
  Verified through writeln + concat so the check does not depend on managed
  Length or char-indexing (separate pre-existing cross gaps). Output is
  identical on every target as on x86-64. }

var
  s: AnsiString;
begin
  s := 'hello';
  SetLength(s, 3);
  writeln('[' + s + ']');        { [hel] }

  s := 'ab';
  SetLength(s, 4);               { grow: 'ab' + two NUL bytes }
  writeln('[' + s + ']');

  s := 'keepme';
  SetLength(s, 6);               { same length: unchanged }
  writeln('[' + s + ']');        { [keepme] }

  s := 'discard';
  SetLength(s, 0);               { publish nil }
  writeln('[' + s + ']');        { [] }
end.
