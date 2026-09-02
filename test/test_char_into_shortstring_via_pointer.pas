program test_char_into_shortstring_via_pointer;
{ `char VALUE + string DEST + POINTER store` was lowered on x86-64 and riscv32
  only; i386, aarch64 and arm32 raised
    'target <t>: char-to-inline-string store through pointer not yet supported'
  at their IR_STORE_MEM arm, while all five already handled the IR_STORE_SYM
  spelling (`s := c`, row f). One concept, two lowering sites, the second left
  behind -- normalise-dont-special-case.
  bug-a-char-into-shortstring-through-a-pointer-is-x86-64-only

  This test MUST run on the cross targets to mean anything: the defect was
  x86-64-clean by definition, so a native-only row is a guard that cannot fail
  for the bug it is named after. Wired into test-i386/-aarch64/-arm32/-riscv32.

  Every string is PRE-LOADED with a 5-char value before the store under test,
  so a store that does nothing at all prints `5 abcde` rather than the expected
  `1 X`. Without that, an unwritten slot could read back as a plausible pass. }
{$mode objfpc}
type
  TS = string[8];
  TR = record s: TS; n: LongInt; end;
var
  s: TS; p: ^TS; c: char;
  r: TR; pr: ^TR;
  fails: Integer;

procedure Want(const tag: string; ok: Boolean);
begin
  if not ok then begin WriteLn(tag, ' FAIL'); Inc(fails); end;
end;

begin
  fails := 0;
  c := 'X';

  { a -- the ticket's own shape: bare pointer to a string[N] }
  s := 'abcde';
  p := @s;
  p^ := c;
  WriteLn('a ', Length(s), ' ', s);
  Want('a', (Length(s) = 1) and (s = 'X'));

  { b -- the sibling the ticket had not recorded: the same store reached
    through a record FIELD. Confirmed to ride the same IR_STORE_MEM arm (the
    pinned compiler refuses it in isolation on all three targets), so one edit
    per backend covers both. `n` is checked because a wrong length word or a
    stray byte would land on the neighbouring field. }
  r.s := 'abcde';
  r.n := 77;
  pr := @r;
  pr^.s := c;
  WriteLn('b ', Length(r.s), ' ', r.s, ' ', r.n);
  Want('b', (Length(r.s) = 1) and (r.s = 'X') and (r.n = 77));

  { c -- the control that this is not the char-to-string conversion: the same
    assignment WITHOUT a pointer worked on every target throughout. }
  s := 'abcde';
  s := c;
  WriteLn('c ', Length(s), ' ', s);
  Want('c', (Length(s) = 1) and (s = 'X'));

  { d -- the control that this is not the pointer store: a string source
    through the same pointer worked on every target throughout. }
  s := 'abcde';
  p := @s;
  p^ := 'zy';
  WriteLn('d ', Length(s), ' ', s);
  Want('d', (Length(s) = 2) and (s = 'zy'));

  Halt(fails);
end.
