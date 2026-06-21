{ Regression: {$IF DECLARED(name)} conditional directive.
  DECLARED(x) is resolved at directive-evaluation (lex) time against the symbols
  whose declaration has already been emitted into the token stream — "visible at
  this source location". Qualified names match on their final component (precise
  namespace resolution is deferred to dotted-unit-names). See
  feature-conditional-declared-directive. }
program test_declared_directive;
const
  LocalConst = 5;
  FIONREAD = $4004667F;   { stands in for a stub dotted-unit export, in-stream }
begin
  {$IF DECLARED(LocalConst)}
  writeln('1');           { declared earlier in this file -> true }
  {$ELSE}
  writeln('x1');
  {$ENDIF}

  {$IF DECLARED(MissingConst)}
  writeln('x2');
  {$ELSE}
  writeln('2');           { never declared -> false }
  {$ENDIF}

  {$IF DECLARED(Posix.StrOpts.FIONREAD)}
  writeln('3');           { qualified, final component visible in-stream -> true }
  {$ELSE}
  writeln('x3');
  {$ENDIF}

  {$IF DECLARED(Posix.StrOpts.NOPE)}
  writeln('x4');
  {$ELSE}
  writeln('4');           { absent qualified -> false (Synapse POSIX fallback) }
  {$ENDIF}

  {$IF not DECLARED(MissingConst) and DECLARED(LocalConst)}
  writeln('5');           { composes with not/and }
  {$ELSE}
  writeln('x5');
  {$ENDIF}
end.
