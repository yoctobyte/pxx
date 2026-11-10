program test_set_of_char_const;
{ Regression: a `set of char` typed const must not allocate a phantom var that
  shadows a same-named char variable case-insensitively, and FindSetConst (which
  is case-insensitive) must not win over a real variable
  (bug-set-of-char-const-corrupts-char-codegen). }
type T = set of char;
const C: T = [#65];                 { a same-named var in this scope is a duplicate identifier now (fpc agrees) }
const Vowels: T = ['a', 'e', 'i', 'o', 'u'];
const Digits = ['0'..'9'];          { untyped set const }
var ch: char;
begin
  ch := #65;
  writeln(Ord(ch));                  { 65 — must be the char var, not the set }
  ch := 'e';
  writeln(Ord(ch in Vowels));        { 1 }
  ch := 'x';
  writeln(Ord(ch in Vowels));        { 0 }
  writeln(Ord('7' in Digits));      { 1 }
  writeln(Ord('a' in Digits));      { 0 }
  writeln(Ord(ch));                  { 120 — still the char var }
end.
