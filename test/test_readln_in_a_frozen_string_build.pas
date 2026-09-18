program test_readln_in_a_frozen_string_build;
{ read/readln must work under -uPXX_MANAGED_STRING, the frozen-string model
  the compiler itself is built with.

  It did not, on any target, and it failed two DIFFERENT ways for the same
  reason — a driver that never pulls builtinheap:

    - the five cross backends lower IR_READLINE onto PXXReadLine and got
      `compiler error: PXXReadLine not found`. That predates the buffer work;
      it reproduces on the pinned compiler.
    - x86-64 emitted its own reader and was fine until that reader started
      sharing the builtin's demand-allocated line buffer, and then got
      `compiler error: PXXLineEnsure not found in builtin unit`.

  A frozen-STRING target then found a third arm of the same split: the builtin
  reads one correctly, and the deleted x86-64 asm sent it through the managed
  arm, which calls an AnsiString stub a frozen build never emits — so on the
  pinned compiler this program does not compile on x86-64 either, with a third
  message again.

  Three messages, one cause, and the row that catches all three is simply
  building this at all. Both target kinds are here because the frozen string is
  what separated the two readers. }
var
  i: Integer;
  c: Char;
  s: string[20];
begin
  readln(i);
  readln(s);
  read(c);
  writeln('i=', i + 1);
  writeln('s=[', s, ']');
  writeln('c=', Ord(c));
end.
