program test_sizeof_of_a_frozen_string_type_name;
{$mode delphi}{$H+}
{ `SizeOf(<a type NAME>)` for a frozen string. The kind alone cannot express the
  width -- tyShortString says nothing about N -- so the arm that answers this
  parses the name and reads a COMPANION beside the kind. Both now arrive from
  one call (ParseTypeKindSized); they used to be a call and two globals.

  THE INTERLEAVING IS THE TEST, not the individual widths. Each row parses a
  type and then another one, so a capacity that outlived its own parse would be
  read by the NEXT SizeOf: `rev` asks for 201 and then for 11, and a leaked cap
  answers 201 twice. `mix` puts a RECORD between two frozen strings, which is
  the shape the changed site actually takes -- the record arm and the cap arm are
  two branches of one `if`, and the cap used to be read in the second branch
  after a call in the first.

  WHICH ROWS AIM AT THE CHANGED SITE, MEASURED RATHER THAN ASSUMED. A probe in
  ParseTypeKindSized (`PXXDBG=p.sized`) fires exactly TWICE for this program,
  and BOTH times from the `file of` element site: `tk=25 cap=10` for
  `file of S10` and `tk=5 rec=29` for `file of TRec`. The four SizeOf rows do
  NOT reach it -- `SizeOf(S10)` is answered by the ALIAS arm at
  pasparser_expr.inc:3987, which already takes kind and cap from ONE indexed
  carrier (`AliasTk[i]` / `AliasStrCap[i]`) and therefore never had the window
  this refactor closes. They are kept as an unchanged-observable pin for a
  neighbouring path, and they are NOT a control.

  THE `bytes` ROWS ARE THE CONTROL, AND THE ROWS ABOVE THEM CANNOT BE ONE.
  Measured: with the alias cap write removed from ParseTypeKind, `file` still
  prints `3 cc 3`. A file is written and read through the SAME element width,
  so an element count, a value and a position are all INVARIANT to that width
  being wrong -- the readout collapses the two answers. Only the BYTE length
  separates them, which is why the file is reopened as `file of Byte`:
  3 * (10 + 1) = 33 and 1 * 12 = 12, and neither number is a default, a zero,
  or a pointer width.

  WHAT THIS FIXTURE IS NOT: a control for a FUTURE window violation. That
  population is "callers added later", and no Pascal program can sample it.
  refactor-p-the-frozen-string-cap-travels-to-its-sizer-in-a-global-whose-window-nobody-enforces }
type
  S10 = string[10];
  S200 = string[200];
  TRec = record a, b, c: Integer; end;
var f10: file of S10; frec: file of TRec; s: S10; r: TRec; fb: file of Byte;
begin
  WriteLn('fwd   ', SizeOf(S10), ' ', SizeOf(S200));
  WriteLn('rev   ', SizeOf(S200), ' ', SizeOf(S10));
  WriteLn('mix   ', SizeOf(S10), ' ', SizeOf(TRec), ' ', SizeOf(S200));
  WriteLn('plain ', SizeOf(TRec), ' ', SizeOf(Integer));

  { the OTHER site that took the same pair from the same globals: a typed
    file's ELEMENT. Positions count in element widths, so a wrong cap moves
    them -- a value-only assertion would not see it. }
  Assign(f10, 'sizeoffrozen.dat'); Rewrite(f10);
  s := 'aa'; Write(f10, s);
  s := 'bb'; Write(f10, s);
  s := 'cc'; Write(f10, s);
  Seek(f10, 2); Read(f10, s);
  WriteLn('file  ', FileSize(f10), ' ', s, ' ', FilePos(f10));
  Close(f10);
  r.a := 1; r.b := 2; r.c := 3;
  Assign(frec, 'sizeoffrozen2.dat'); Rewrite(frec); Write(frec, r); Close(frec);

  { the readout that does not collapse: the element WIDTH, in bytes on disk.
    Both scratch files are Erased here, so the test leaves the CWD as it found
    it however it is wired. }
  Assign(fb, 'sizeoffrozen.dat'); Reset(fb);
  Write('bytes ', FileSize(fb));
  Close(fb); Erase(fb);
  Assign(fb, 'sizeoffrozen2.dat'); Reset(fb);
  WriteLn(' ', FileSize(fb));
  Close(fb); Erase(fb);
end.
