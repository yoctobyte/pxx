{ THE COPY-ON-WRITE RULE FOR AN INDEXED MANAGED STRING, on every backend.

  Guards IRIndexNeedsStrCOW, the one predicate behind `s[i] := c`. That rule
  used to be written out independently in all SEVEN backends and was guarded
  NOWHERE -- refactor-a-the-managed-string-index-cow-rule-is-spelled-seven-times
  and its sibling tickets record that both halves of the sibling predicate's
  matrix were found by heap measurements months apart, and neither by a test.
  This is that missing test.

  WHAT MAKES IT A TEST AND NOT A SMOKE CHECK: every line writes through one
  alias and reads back the OTHER. `t := s; s[1] := 'H'` must leave t as 'hello'.
  If COW stops firing, the write lands in the shared buffer and t changes too --
  so a broken predicate produces a WRONG STRING, not a crash, which is the
  failure mode these tickets kept meeting.

  Its positive control was run rather than assumed (frankB, 2026-09-01): with
  the predicate forced False, x86-64 output becomes garbage and arm32/riscv32
  print `lea s= t=hello` instead of `lea s=Hello t=hello`. So this file can
  fail. The three base shapes are deliberate -- LEA (a plain local), FIELD (a
  string in a record) and INDEX (a string that is an array element) are three
  separate arms of the predicate. The last row is the excluded case: an
  `array of AnsiString` has stride 8 and must NOT be treated as an indexed
  string, because its IRTk is tyAnsiString for the ELEMENT, not the base. }
program test_string_index_cow;
type
  TRec = record s: AnsiString; end;
var
  s, t: AnsiString;
  r: TRec;
  arr: array[0..2] of AnsiString;
  i: Integer;
begin
  { LEA base: a plain local. The COW itself -- t must NOT see the write. }
  s := 'hello';
  t := s;
  s[1] := 'H';
  Writeln('lea    s=', s, ' t=', t);

  { FIELD base: a string inside a record, same COW obligation. }
  r.s := 'world';
  t := r.s;
  r.s[1] := 'W';
  Writeln('field  r.s=', r.s, ' t=', t);

  { INDEX base: a string that is an array ELEMENT. }
  arr[0] := 'alpha';
  arr[1] := arr[0];
  arr[0][1] := 'A';
  Writeln('index  a0=', arr[0], ' a1=', arr[1]);

  { READS, not writes -- the non-lvalue path through the same predicate. }
  s := 'abcde';
  t := '';
  for i := 1 to 5 do t := t + s[i];
  Writeln('read   t=', t);

  { array of AnsiString: stride 8, deliberately NOT the COW case. }
  arr[2] := 'keep';
  Writeln('stride a2=', arr[2], ' len=', Length(arr[2]));
end.
