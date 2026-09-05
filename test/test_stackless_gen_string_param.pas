{ A managed STRING argument to a `generator; stackless;` routine, and the
  all-parameter-kinds row.

  A string LITERAL was stored into the instance slot RAW — the literal's own
  address, whose [-8] is the never-free refcount sentinel rather than a length —
  so `Length` in the body read 1073741824 instead of 4. The ordinary call path
  materialises a literal into a handle; the slot store went through
  SlSet(g, off, val: Int64), where nothing asks what the parameter's type needs.

  `from_variable` is why this is filed narrowly: it was ALWAYS correct, so the
  defect is `a literal never becomes a handle here`, not `AnsiString parameters
  are broken` — which is what the first measurement looked like.

  all_kinds is the row that would have found all three defects in this group at
  once. Every parameter kind that reaches a stackless generator, in one
  signature: a Variant (16 bytes behind a pointer), a record (by-ref, address
  already), an AnsiString (a handle), a scalar `var` (an address), and a plain
  ordinal (a value). Each of the five is answered by a different rule and the
  caller and the generator have to agree on all five.
  bug-a-a-string-literal-passed-to-a-stackless-generator-is-stored-without-being-materialised }
program test_stackless_gen_string_param;
uses slgen;

type TR = record a, b: Int64; end;

function GStr(s: AnsiString): Integer; generator; stackless;
begin yield Length(s); yield Length(s) * 2; end;

function GAllKinds(v: Variant; r: TR; s: AnsiString; var m: Int64; n: Integer): Integer;
  generator; stackless;
begin yield Integer(v); yield r.a; yield Length(s); yield m; yield n; end;

var x: Integer; sv: AnsiString; rr: TR; mm: Int64;
begin
  { a LITERAL: the failing case — read twice, so it must survive a yield too }
  for x in GStr('abcd') do write(x, ' ');
  writeln;

  { from a VARIABLE: always worked, and must keep working }
  sv := 'abcd';
  for x in GStr(sv) do write(x, ' ');
  writeln;

  { built at runtime: a real heap handle rather than a static one }
  sv := 'ab'; sv := sv + 'cd';
  for x in GStr(sv) do write(x, ' ');
  writeln;

  rr.a := 10; rr.b := 20; mm := 40;
  for x in GAllKinds(1, rr, 'abcd', mm, 5) do write(x, ' ');
  writeln;
end.
