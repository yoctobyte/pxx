{$mode objfpc}
program test_keyword_case;

{ Keywords are case-insensitive in user code. The lexer keyword table used to
  hard-code lowercase (with ad-hoc Capital variants for only some), so mixed- and
  upper-case keywords (Then, Else, Type, Mod, Case, BEGIN/END, For/To/Do, ...)
  fell through to identifiers. Now lowercased before lookup (user mode only).
  FPC oracle: 9 / 22. }

Type
  TNum = Integer;

Var
  i, s: TNum;
Begin
  s := 0;
  For i := 1 To 5 Do
    If (i Mod 2) = 0 Then
      s := s + i
    Else
      s := s + 1;
  WriteLn(s);                 { 1+2+1+4+1 = 9 }
  Case s Of
    9: WriteLn(22);
  End;
End.
