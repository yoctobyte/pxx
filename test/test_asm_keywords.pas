program AsmKeywordMnemonics;
{ Regression for bug-asm-keyword-mnemonic-collision: `and`/`or`/`xor`/`not`/
  `div`/`mod`/`shl`/`inc`/`dec` lex as Pascal keyword tokens (tkAnd, tkDec,
  ...), not tkIdent — AsmParseBody's "skip stray punctuation" gate used to
  silently swallow them and desync the parser onto the next token. }

function Compute(a, b: longint): longint; assembler;
{$asmMode intel}
asm
  mov eax, a       { eax = a and b            =  8 }
  and eax, b
  mov ecx, a       { ecx = a or b             = 14 }
  or ecx, b
  add eax, ecx     { eax = 22 }
  mov ecx, a       { ecx = a xor b            =  6 }
  xor ecx, b
  add eax, ecx     { eax = 28 }
  mov ecx, b       { ecx = not b, then -1     = -12 }
  not ecx
  dec ecx
  add eax, ecx     { eax = 16 }
  xor edx, edx
  mov ecx, 4
  div ecx          { eax = 16 div 4 = 4 }
end;

var
  r: longint;
begin
  r := Compute(12, 10);
  writeln(r);       { expect 4 }
end.
