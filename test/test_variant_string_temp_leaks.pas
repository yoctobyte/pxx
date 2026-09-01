program TestVariantStringTempLeaks;
{ A MANAGED STRING HANDED TO THE VARIANT BOUNDARY WITH NOBODY OWNING IT.

  Two lowerings produced a fresh AnsiString and left it unowned, so no
  scope-exit scan could ever find it -- it was never a symbol:

  - IRLowerVariantAsScalar converts a Variant to a string by calling
    VariantToStrPas, whose result is brand new. `Take(v)` where Take wants a
    `const AnsiString` leaked one handle per call: allocs=921 frees=0 live=921
    over 1000 trips.
  - The scalar side of a variant binop is boxed into a temp Variant, and a
    COMPUTED operand arrives as a concat result with a +1 belonging to nobody.
    `v = ('lit' + Chr(c))` leaked 936 in 1000 trips, and so did the mirrored
    `('lit' + Chr(c)) = v` -- two call sites, one for each operand.

  WHY THE FIX IS NOT AT THE CALL-ARGUMENT SITES. ir.inc materialises a managed
  string argument into an owning temp only when the argument AST is NOT one of
  AN_IDENT/AN_FIELD/AN_INDEX/AN_DEREF -- sound reasoning, because those name
  storage somebody else owns. `Take(v)` with `v: Variant` IS an AN_IDENT, so
  the exclusion fired on a node that the variant lowering had already replaced
  with a new string. The predicate asks the AST SHAPE; ownership is a property
  of what the LOWERING produced. There are seven such sites, so a clause added
  at one fixes one spelling and leaves six; both fixes here are at the seam
  that creates the value instead.

  THE ARMS THAT ALWAYS PASSED ARE THE POINT, not filler. They are what says the
  temp machinery was never broken and the boundary was:

  - vv      Variant vs Variant. No box temp is built at all. Always clean, so
            a failure here means the fix reached a path it has no business on.
  - vs      Variant vs a NAMED AnsiString local. A box temp IS built and was
            always released correctly (1871/1870 before the fix). This is the
            arm that rules out the box temp itself as the leak -- without it
            the obvious reading of `cmpright` is "temp variants leak".
  - into    `s := v`, the same conversion as `arg` landing in a variable that
            owns it. Clean before and after: the conversion was fine, the
            OWNERSHIP of its result was not.
  - ctlstr  the identical computed temporary compared against an AnsiString
            instead of a Variant. Clean before the fix, which is what localises
            the defect to the variant boundary rather than to concat temps.

  AND TWO THAT FAIL IN THE OTHER DIRECTION, because the fix adds releases:

  - fnres   a function-result operand. IR_STORE_SYM MOVES a fresh call result
            and RETAINS anything else (IRNodeOwnsFreshCallResult), so if that
            discrimination and this parking ever disagree, this is the arm that
            double-frees rather than leaks.
  - lit     a static literal operand, whose refcount is saturated. A spurious
            release must not drive it to zero. Allocates nothing, so it
            contributes no leak evidence at all -- it is here as a crash and
            over-release control only, and the census cannot speak for it.

  MEASURED. The four leaking arms in isolation, x86-64, 1000 trips each:
  arg 921 -> 1, cmp-right 936 -> 1, cmp-left 936 -> 1, fn-result 936 -> 1, with
  `allocs` unchanged on every row -- the same traffic, so the delta is ownership
  and not a changed evaluation. This program as a whole, live before -> after:

      x86-64 1549 -> 2   aarch64 1549 -> 2   i386 3616 -> 1
      arm32  3856 -> 2   riscv32  364 -> 1

  Every one of those is above the bound before and far below it after, so no row
  here is decoration. They are NOT equal to each other, and the differences are
  not this defect: i386 and arm32 carry additional per-target holes in these
  same shapes, and the total allocation COUNT moves on i386, arm32 and riscv32
  (8671 -> 6850 on i386) where it is unchanged on x86-64 and aarch64. Do not
  read those three numbers as a measurement of this fix.

  A CROSS-TARGET DIFFERENTIAL IS BLIND TO THIS BY CONSTRUCTION, and that is
  measured rather than assumed: the pre-fix binary prints hits=2800 sink=44800
  and the identical tail string on all five targets while leaking 1549 blocks.
  Only the absolute bound can see it.
  bug-a-a-variant-converted-to-ansistring-leaks-whenever-the-result-is-a-temporary }

var
  n, hits, sink: Integer;
  gs: AnsiString;

procedure Take(const s: AnsiString);
begin
  sink := sink + Length(s);
end;

function Payload(k: Integer): AnsiString;
begin
  Payload := 'a payload long enough to be a heap tier string, really ' + Chr(65 + (k mod 8));
end;

{ COVERAGE: a Variant where a const AnsiString is wanted. AN_IDENT arg. }
procedure ArmArg(k: Integer);
var v: Variant;
begin
  v := Payload(k);
  Take(v);
end;

{ COVERAGE: computed operand on the RIGHT of a variant compare. }
procedure ArmCmpRight(k: Integer);
var v: Variant;
begin
  v := Payload(k);
  if v = ('a payload long enough to be a heap tier string, really ' + Chr(65 + (k mod 8))) then
    hits := hits + 1;
end;

{ COVERAGE: the same operand on the LEFT -- a separate call site that the
  right-hand shape never reaches, and it leaked identically. }
procedure ArmCmpLeft(k: Integer);
var v: Variant;
begin
  v := Payload(k);
  if ('a payload long enough to be a heap tier string, really ' + Chr(65 + (k mod 8))) = v then
    hits := hits + 1;
end;

{ COVERAGE + double-free control: a fresh call result as the boxed operand. }
procedure ArmFnRes(k: Integer);
var v: Variant;
begin
  v := Payload(k);
  if v = Payload(k) then hits := hits + 1;
end;

{ CONTROL, always clean: no box temp is built. }
procedure ArmVV(k: Integer);
var v, w: Variant;
begin
  v := Payload(k);
  w := Payload(k);
  if v = w then hits := hits + 1;
end;

{ CONTROL, always clean: a box temp IS built, around storage someone owns. }
procedure ArmVS(k: Integer);
var v: Variant; s: AnsiString;
begin
  v := Payload(k);
  s := Payload(k);
  if v = s then hits := hits + 1;
end;

{ CONTROL, always clean: the conversion result lands in an owning variable. }
procedure ArmInto(k: Integer);
var v: Variant; s: AnsiString;
begin
  v := Payload(k);
  s := v;
  sink := sink + Length(s);
end;

{ CONTROL, always clean: the same temporary, against an AnsiString. }
procedure ArmCtlStr(k: Integer);
var s: AnsiString;
begin
  s := Payload(k);
  if s = ('a payload long enough to be a heap tier string, really ' + Chr(65 + (k mod 8))) then
    hits := hits + 1;
end;

{ OVER-RELEASE control: a saturated literal must survive being boxed. }
procedure ArmLit(k: Integer);
var v: Variant;
begin
  v := 'a fixed literal payload that is comfortably heap tier in length';
  if v = 'a fixed literal payload that is comfortably heap tier in length' then
    hits := hits + 1
  else
    sink := sink + k;
end;

begin
  hits := 0;
  sink := 0;
  for n := 1 to 400 do
  begin
    ArmArg(n);
    ArmCmpRight(n);
    ArmCmpLeft(n);
    ArmFnRes(n);
    ArmVV(n);
    ArmVS(n);
    ArmInto(n);
    ArmCtlStr(n);
    ArmLit(n);
  end;
  { Read a payload back after all the releasing, so an over-release that did
    not crash still has to answer for the CONTENT. }
  gs := Payload(3);
  WriteLn('variant string temp arms');
  WriteLn('hits=', hits);
  WriteLn('sink=', sink);
  WriteLn('tail=', gs);
end.
