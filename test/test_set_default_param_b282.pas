{ SET-typed DEFAULT PARAMETERS: `procedure P(o: TOpts = DefaultOpts)`.

  A set is a 32-byte mask, not an ordinal, so a set default cannot ride in the ordinal
  ProcParamDefaultVal slot the way an Integer does. It is baked at the DECLARATION and the
  slot carries the mask's Data[] OFFSET; the call rebuilds the reference from it. Emitting
  an ordinary integer constant passed the OFFSET ITSELF as if it were the set, and the
  callee dereferenced it -- a segfault, not a wrong answer.

  Note the fill happens in TWO places -- the parser (FillDefaultArgs, for method calls) and
  the IR lowering (for plain routine calls) -- and both had to learn it. The parser one is
  the obvious one; the IR one is where `P()` for a plain procedure actually goes.

  fpjson: `Function FormatJSON(Options: TFormatOptions = DefaultFormat; ...)`. }
program test_set_default_param_b282;
type
  TOpt = (oA, oB, oC);
  TOpts = set of TOpt;
const
  DefaultOpts = [];
  Preset = [oA, oC];
procedure Show(const nm: string; o: TOpts);
begin
  write(nm, ': ');
  if oA in o then write('A');
  if oB in o then write('B');
  if oC in o then write('C');
  if o = [] then write('(empty)');
  writeln;
end;
{ set-typed default params: an empty literal, a named set const, a literal set }
procedure P1(o: TOpts = DefaultOpts);
begin Show('P1', o); end;
procedure P2(o: TOpts = []);
begin Show('P2', o); end;
procedure P3(o: TOpts = Preset);
begin Show('P3', o); end;
procedure P4(o: TOpts = [oB]);
begin Show('P4', o); end;
procedure P5(n: Integer; o: TOpts = Preset - [oA]);
begin write('P5 n=', n, ' '); Show('', o); end;
begin
  P1();                 { empty }
  P2();                 { empty }
  P3();                 { A C }
  P4();                 { B }
  P5(1);              { C }
  P3([oB]);           { explicit arg still wins }
  P5(2, [oA, oB]);
end.
