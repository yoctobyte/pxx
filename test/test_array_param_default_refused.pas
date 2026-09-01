{$mode objfpc}
program test_array_param_default_refused;

{ A default value on an OPEN-ARRAY parameter must be refused. There is no array
  literal to write there, so whatever is parsed is a scalar, and the callee then
  reads its length header out of that scalar's bytes: this compiled and printed
  High(a) = 1073741823 (a frozen string literal's inline length prefix read as
  an array header) until 2026-09-01. FPC refuses it at the `=`.
  bug-a-managed-string-arg-temp-predicate-is-duplicated-seven-times-and-guarded-nowhere

  The POSITIVE side of this guard is test_array_param_default_allowed, which
  must keep compiling: a named DYNAMIC array type is a handle and `nil` is a
  meaningful default for it. A guard tested only by what it rejects cannot tell
  you it rejects too much, and the first version of this one did. }

procedure P(const a: array of string = 'x');
begin
  writeln('high=', High(a));
end;

begin
  P;
end.
