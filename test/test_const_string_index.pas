program test_const_string_index;
{ Regression: indexing a string CONSTANT (RAMP[i]) must read one char from the
  literal's frozen storage, not the whole string / garbage
  (bug-const-string-index-miscompiles). Covers char + string context, literal +
  variable index, call-arg context, and a const ARRAY (must stay correct). }
const RAMP = ' .:-=+*#%@';
const HEX = '0123456789abcdef';
const TBL: array[0..4] of Integer = (10, 20, 30, 40, 50);
var c: Char; i, b: Integer; s: AnsiString;
begin
  i := 3;
  c := RAMP[i];  writeln(Ord(c));        { 58  (':') var index }
  c := RAMP[3];  writeln(Ord(c));        { 58       lit index  }
  s := 'X' + RAMP[i]; writeln(s);        { X:  string context  }
  s := RAMP[i];       writeln(s);        { :                   }
  writeln('[', RAMP[3], ']');            { [:]  call-arg context }
  b := 171;                              { $AB }
  writeln(HEX[(b div 16) + 1], HEX[(b mod 16) + 1]);   { ab }
  i := 2;
  writeln(TBL[i], ' ', TBL[2]);          { 30 30  (const array unaffected) }
end.
