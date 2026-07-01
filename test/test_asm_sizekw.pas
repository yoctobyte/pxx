program AsmSizeKw;
{ Inline asm operand-size keywords (feature-inline-asm-depth TODO #4):
  byte/word/dword/qword [ptr] [reg...] disambiguate a bare-memory
  instruction's width when no register operand is present to infer it
  from. `byte` lexes as tkInteger_T (shared with `integer`), not tkIdent --
  the same keyword-collision class already hit for and/or/div/dec this
  session (see AsmTokIsWordLike); CurTok.SVal still holds the right text
  regardless of Kind. word/dword/qword/ptr are plain tkIdent. }
var
  buf: array[0..7] of byte;
  w: word;
  p: ^byte;
  pw: ^word;

begin
  buf[0] := 5; buf[1] := 0; buf[2] := 0; buf[3] := 0;
  p := @buf[0];

  { inc byte [p] -- no register anywhere, size MUST come from the keyword }
  asm
    mov rbx, p
    inc byte [rbx]
  end;
  writeln(buf[0]);   { 6 }

  { the optional 'ptr' form }
  asm
    mov rbx, p
    inc byte ptr [rbx]
  end;
  writeln(buf[0]);   { 7 }

  { mov dword ptr [rbx], imm -- explicit dword, no register operand }
  asm
    mov rbx, p
    mov dword ptr [rbx], 1000
  end;
  writeln(buf[0], ' ', buf[1], ' ', buf[2], ' ', buf[3]);  { 1000 = E8 03 00 00 LE }

  { word keyword }
  w := 0;
  pw := @w;
  asm
    mov rbx, pw
    mov word [rbx], 300
  end;
  writeln(w);        { 300 }
end.
