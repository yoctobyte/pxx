{ FPC-compat dialect fixes found bisecting the fgl "generics" wall (which was
  never generics):
  - hint directives (deprecated ['msg'] / platform / experimental) on
    const / type / proc are parse-and-ignore
    (feature-hint-directives-deprecated-platform);
  - SizeOf(TypeName) folds in a const / default-parameter position
    (feature-sizeof-const-intrinsic-in-const-eval).
  Self-checking: prints "total ok N / N". }
program test_hint_sizeof;

const
  KDep   = 5 deprecated;                      { hint on a const value }
  KPlat  = 7 platform;                        { another hint word }
  KSize  = sizeof(Int64);                      { SizeOf in a const }
  KMax   = MaxInt div 1024 deprecated;         { predefined MaxInt + hint }

type
  TOldAlias = Integer deprecated;              { hint on a type alias }

{ hint directives on a routine, incl. an optional message and interleaving }
procedure Old; deprecated; begin end;
procedure Older; deprecated 'use Newer'; begin end;
procedure Mixed; inline; deprecated; begin end;

{ SizeOf as a default parameter value (free-function path) }
function WithSize(a: Integer; b: Integer = sizeof(Pointer)): Integer;
begin WithSize := a + b; end;

var
  pass, total: Integer;
begin
  pass := 0; total := 0;
  Old; Older; Mixed;

  Inc(total); if KDep = 5 then Inc(pass);
  Inc(total); if KPlat = 7 then Inc(pass);
  Inc(total); if KSize = 8 then Inc(pass);
  Inc(total); if KMax = 2097151 then Inc(pass);           { 2147483647 div 1024 }
  Inc(total); if MaxInt = 2147483647 then Inc(pass);
  Inc(total); if MaxSmallInt = 32767 then Inc(pass);
  Inc(total); if WithSize(1) = 9 then Inc(pass);          { 1 + sizeof(Pointer)=8 }
  Inc(total); if WithSize(1, 4) = 5 then Inc(pass);

  writeln('total ok ', pass, ' / ', total);
end.
