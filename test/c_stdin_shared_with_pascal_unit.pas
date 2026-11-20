{ The Pascal half of test/c_stdin_shared_with_pascal.c: each stdin reader
  Pascal has (the bare console reader and textfile's Input), wrapped so C can
  interleave them with getchar/ungetc/fgets.
  bug-c-crtl-stdin-and-pascal-input-do-not-share-a-peeked-byte }
unit c_stdin_shared_with_pascal_unit;
interface
uses textfile;   { Input; a unit pulled from C gets no ambient textfile }
function PEof: Integer;          { bare Eof: peeks one byte }
function PEofInput: Integer;     { Eof(Input): textfile peeks one byte }
procedure PReadLn;               { bare ReadLn(s) }
procedure PReadLnInput;          { ReadLn(Input, s) }
implementation
function PEof: Integer;
begin
  Result := Ord(Eof);
end;
function PEofInput: Integer;
begin
  Result := Ord(Eof(Input));
end;
procedure PReadLn;
var s: AnsiString;
begin
  ReadLn(s);
  WriteLn('P:', s);
end;
procedure PReadLnInput;
var s: AnsiString;
begin
  ReadLn(Input, s);
  WriteLn('PI:', s);
end;
end.
