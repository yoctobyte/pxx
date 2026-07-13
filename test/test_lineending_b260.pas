program test_lineending_b260;
{ System.LineEnding — FPC provides it with no `uses`, and fcl-fpcunit builds its message
  formats out of it (`'Expected:' + LineEnding + '"%s"'`), which failed with "const string
  concatenation: expected a string/char literal or string constant".

  Added as a FALLBACK, reached only after the normal lookup misses, so a source that
  declares its own LineEnding still WINS. Registering it up front instead would shadow the
  source's declaration — that is the trap bug-pascal-builtin-pointer-type-cast records,
  where a builtin PWord silently re-typed the compiler's own PWord = ^NativeInt and only
  the self-host byte-identical gate caught it. }
const
  S = 'a' + LineEnding + 'b';
var
  t: string;
begin
  writeln('const-concat-len=', Length(S));      { 'a' + LF + 'b' = 3 }
  writeln('is-lf=', S[2] = #10);
  t := 'x' + LineEnding;                        { and as an ordinary expression }
  writeln('expr-len=', Length(t));
  writeln('le-len=', Length(LineEnding));
end.
