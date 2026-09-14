program test_gtk3_pc_pchar_conversion;
{ gtk3.PC() converts a Pascal string to a `const char*` for a C call.

  It was a four-slot 4096-byte static ring until 2026-09-14. Three rows here,
  and the first two FAIL against that ring -- single-threaded, no GTK, no
  display. The owner named the first one himself, 2026-08-31: "issues arise if
  any function call takes more than one pchar parameter."

    MANY   a call taking more than four PChar arguments reused a slot the
           caller still held. Six conversions live at once here (the format
           plus five arguments), against a ring four deep.
    LONG   1024 chars wrote the NUL one past the slot; longer than that ran
           into the NEXT slot, which exists precisely so two conversions can
           be live at once. 4096 chars ran off the array.
    EMPTY  the one job the ring did that a naive @s[1] cannot: an empty
           AnsiString has a NIL handle, and NULL is not the same argument as
           a pointer to "". This row is what stops PC() being deleted
           outright, so it must keep passing whatever PC() is made of.

  bug-b-gtk3-pc-writes-past-its-buffer-on-a-long-string }
uses gtk3;

function snprintf(buf: Pointer; n: NativeUInt; fmt: Pointer;
                  a, b, c, d, e: Pointer): Integer; cdecl;
  external 'libc.so.6' name 'snprintf';
function strlen(s: Pointer): NativeUInt; cdecl; external 'libc.so.6' name 'strlen';

var
  buf: array[0..8191] of Char;
  long, got: AnsiString;
  i, n: Integer;
  p: Pointer;

function Gather(count: Integer): AnsiString;
var k: Integer;
begin
  Gather := '';
  k := 0;
  while (k < count) and (k < 8192) and (buf[k] <> #0) do
  begin
    Gather := Gather + buf[k];
    Inc(k);
  end;
end;

begin
  { MANY: six conversions live across one call. }
  n := snprintf(@buf[0], 8192, PC('%s,%s,%s,%s,%s'),
                PC('one'), PC('two'), PC('three'), PC('four'), PC('five'));
  got := Gather(n);
  if got = 'one,two,three,four,five' then Writeln('MANY ok')
  else Writeln('MANY FAIL: ', got);

  { LONG: a string four times the old slot size, round-tripped through C. }
  long := '';
  for i := 1 to 4096 do long := long + 'x';
  p := PC(long);
  if (strlen(p) = 4096) and (Length(long) = 4096) then Writeln('LONG ok')
  else Writeln('LONG FAIL: strlen=', strlen(p));

  { EMPTY: a valid pointer to "", never NULL. }
  p := PC('');
  if p = nil then Writeln('EMPTY FAIL: NULL')
  else if strlen(p) = 0 then Writeln('EMPTY ok')
  else Writeln('EMPTY FAIL: strlen=', strlen(p));
end.
