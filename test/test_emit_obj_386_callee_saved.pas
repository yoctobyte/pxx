program TestEmitObj386CalleeSaved;
{ i386 psABI: ebx, esi and edi are CALLEE-saved. The pxx i386 backend writes all
  three freely (ebx doubles as the `int 0x80` arg0 register), and until
  bug-a-i386-clobbers-ebx-across-a-cdecl-exported-function it restored none of
  them -- so a gcc -m32 caller got a wrong value or a SIGSEGV inside printf,
  which keeps the GOT pointer in ebx.

  THE BODY IS DELIBERATELY RICH. The ticket's own repro was `a*10+b`, and that
  shape only ever reaches ebx: it measured a clobber mask of 0x1 and the ticket
  recorded "ESI and EDI ARE preserved" as a fact. int64, div/mod, shifts, array
  indexing and string building reach all three (mask 0x7). A simple body here
  would give a row that passes on a compiler that still corrupts two of the
  three registers. The neighbouring test_emit_obj.pas row links a printf caller
  already and did NOT catch this, for exactly that reason. }

function cs_probe(a, b: Integer): Integer; cdecl;
var i, acc: Integer; q: Int64; arr: array[0..7] of Integer; s: AnsiString;
begin
  acc := 0; s := '';
  for i := 0 to 7 do arr[i] := i * a + b;
  for i := 0 to 7 do
  begin
    acc := acc + (arr[i] div 3) + (arr[i] mod 5);
    acc := acc xor (acc shl 3) xor (acc shr 2);
    s := s + 'x';
  end;
  q := Int64(acc) * Int64(a + 1);
  cs_probe := Integer(q and $FFFF) + Length(s);
end;

begin
end.
