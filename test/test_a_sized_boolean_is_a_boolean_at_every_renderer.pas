program test_a_sized_boolean_is_a_boolean_at_every_renderer;
{ ByteBool/WordBool/LongBool are integers of their own width carrying their
  booleanness in the SemId channel, so every renderer that dispatches on the
  KIND alone answers correctly about what it was handed and prints the ordinal.
  Four of them lose it independently, which is why this file asserts four rows
  and not one: the third was found only because someone fixed the first two.
  fpc 3.2.2 prints TRUE/FALSE at all four.
  bug-a-the-sized-booleans-render-as-a-digit-in-both-str-and-writeln }
var
  bb: ByteBool; w: WordBool; l: LongBool; s: ShortString; back: string; f: Text;

{ array of const: the tag is the assertion. A sized boolean boxed as vtInteger
  (0) rather than vtBoolean (1) hands sysutils.Format and every other VType
  consumer a wrong answer with no rendering code involved at all. }
procedure P(const a: array of const);
var i: Integer;
begin
  for i := 0 to High(a) do Write(a[i].VType, ' ');
  WriteLn;
end;

begin
  bb := True; w := True; l := False;

  { 1 -- stdout write }
  WriteLn(bb, ' ', w, ' ', l);
  { 2 -- Str, whose dispatch table is a hand-written copy of write's }
  Str(bb, s); Write(s, ' ');
  Str(w, s);  Write(s, ' ');
  Str(l, s);  WriteLn(s);
  { ...and with a field width, which takes a different arm again }
  Str(l:7, s); WriteLn('[', s, ']');
  { 3 -- the Text-file writer }
  Assign(f, 'sizedbool_renderers.tmp'); Rewrite(f);
  WriteLn(f, bb, ' ', w, ' ', l);
  Close(f);
  { read it back and PRINT it -- a file written and never inspected asserts
    nothing, and this row is the one renderer whose output does not reach
    stdout on its own. `back` is a string and not a ShortString deliberately:
    ReadLn(f, <ShortString>) SEGFAULTS at HEAD and on pin v405 alike, which is
    bug-b-readln-from-a-text-file-into-a-shortstring-segfaults and is nothing
    to do with this file's subject. }
  Assign(f, 'sizedbool_renderers.tmp'); Reset(f); ReadLn(f, back); Close(f);
  WriteLn(back);
  Erase(f);
  { 4 -- array of const boxing }
  P([bb, w, l]);

  { and the CONTROL: a plain Boolean, which has always been right. A row set
    that only asserts the sized types cannot tell a fixed renderer from one
    that has started printing TRUE for everything. }
  WriteLn(True, ' ', False);
end.
