{ A bare ALL-DEFAULTED function name in ARGUMENT position, under delphi mode —
  where a bare name may also mean the routine's ADDRESS. Every value here is
  FPC 3.2.2's on this same source, compiled -Mdelphi.

  (The mode directive is spelled out below rather than quoted in this comment: a
  brace directive written INSIDE a brace comment ends the comment early under
  FPC, which reported a syntax error forty lines away.)

  Two defects, one shape.

  1. `Chk('x', F, 6)` passed F's ADDRESS into an Integer sink and printed
     4247470 — a pointer as a number, silently. TryDelphiBareProcArg took the
     address for any function with parameters, and an all-defaulted function is
     paramless AT THE CALL SITE, so it belongs with the paramless ones that
     parse as a call and reach @F only through the retry.

  2. `C2(Apply(F, 5), 10)` then jumped to address 6 — F's RESULT, called as a
     function pointer — while the identical `Apply(F, 5)` at statement level was
     fine. The retry's "did this land on a procedural parameter" test read
     SymProcSig off the param SYMBOL, which does not outlive the callee's scope;
     in a program with enough symbols to recycle it, it answered "not
     procedural" and the spurious numeric match stood. ProcParamProcSig is the
     parallel array that answers from a caller, and its own comment says so.
     Hence the nesting below: the bug needed a program big enough to recycle.
  bug-p-bare-all-defaulted-routine-refused-in-argument-position }
{$MODE DELPHI}
program test_delphi_bare_alldefaulted_arg;

type TFn = function(k: Integer): Integer;

var okc, total: Integer;

function F(k: Integer = 3): Integer;
begin Result := k * 2; end;

function G: Integer;
begin Result := 9; end;

function Apply(f2: TFn; v: Integer): Integer;
begin Result := f2(v); end;

procedure Check(const nm: string; got, want: Integer);
begin
  Inc(total);
  if got = want then begin Inc(okc); writeln('ok ', nm); end
  else writeln('FAIL ', nm, ' got ', got, ' want ', want);
end;

procedure C2(v, want: Integer);
begin Check('nested-through-a-user-proc', v, want); end;

var a: Integer;
begin
  okc := 0; total := 0;

  { the INTEGER sink: a call, not an address }
  Check('bare-arg-int-sink', F, 6);
  Check('bare-arg-explicit', F(10), 20);

  { the PROCEDURAL sink: the address, reached through the @-optional retry }
  Check('bare-arg-proc-sink', Apply(F, 5), 10);
  Check('explicit-addr-still-works', Apply(@F, 5), 10);

  { nested one level deeper, which is where the recycled param symbol bit }
  C2(Apply(F, 5), 10);

  { a paramless function keeps both readings, unchanged by any of this }
  Check('paramless-int-sink', G, 9);

  { statement and expression position, the two that already worked }
  a := F;
  Check('expr-position', a, 6);
  a := F(4);
  Check('expr-explicit', a, 8);

  writeln('total ok ', okc, ' / ', total);
end.
