{ An `array of const` LITERAL passed to an OVERLOADED constructor:
  `TJSONArray.Create([0, 'string', ...])` (fcl-json).

  The `TFoo.Create(args)` path parses its arguments BEFORE it picks the overload -- it has to,
  since it ranks the overloads by argument TYPE. So it could not ask the chosen signature
  whether a '[' was an array-of-const literal or a set, and it always assumed a SET.

  With a single ctor that merely failed loudly ("set item must be one character"). With an
  OVERLOADED one it was worse: it quietly selected the parameterless Create and passed
  garbage -- `Length(e)` returned -1816133624. Compiled, ran, wrong.

  Asking whether ANY ctor overload wants an open array at that position is enough: a '[' in a
  constructor argument has no other meaning. }
program test_ctor_arrayofconst_overload_b298;
uses sysutils;
type TC = class
  N: Integer;
  constructor Create; overload;
  constructor Create(const e: array of const); overload;
end;
constructor TC.Create;
begin N := -1; end;
constructor TC.Create(const e: array of const);
begin N := Length(e); end;
var c: TC;
begin
  c := TC.Create;
  writeln('noarg n=', c.N);
  c := TC.Create(['a', 1, True]);
  writeln('arr n=', c.N);
end.
