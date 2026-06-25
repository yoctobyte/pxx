program test_set_of_char_const;
{ Regression: a `set of char` typed const must not allocate a phantom var that
  shadows a same-named char variable case-insensitively, and FindSetConst (which
  is case-insensitive) must not win over a real variable
  (bug-set-of-char-const-corrupts-char-codegen). }
type T = set of char;
const C: T = [#65];                 { name collides case-insensitively with `c` }
const Vowels: T = ['a', 'e', 'i', 'o', 'u'];
const Digits = ['0'..'9'];          { untyped set const }
var c: char;
begin
  c := #65;
  writeln(Ord(c));                  { 65 — must be the char var, not the set }
  c := 'e';
  writeln(Ord(c in Vowels));        { 1 }
  c := 'x';
  writeln(Ord(c in Vowels));        { 0 }
  writeln(Ord('7' in Digits));      { 1 }
  writeln(Ord('a' in Digits));      { 0 }
  writeln(Ord(c));                  { 120 — still the char var }
end.
