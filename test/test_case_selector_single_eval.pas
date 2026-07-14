{ `case` must evaluate its selector expression EXACTLY ONCE (b346).

  `case` lowers to a compare-chain, and the selector's IR value node was used as an
  operand of every label test. A value node is not a register — it is a subtree, and
  each backend re-EMITS it per use. So `case F(x) of` ran F once per label ELEMENT
  (a range costing two), stopping at the first match.

  That last part is what hid it: whenever the FIRST label matched, the count was 1 and
  everything looked right. It only showed when execution fell past a label — so the more
  labels a case had, the more times its selector ran.

  Found by Track T's pasmith differential fuzzer, which filed ~510 divergences against
  FPC. Every one of them was this: the generated programs call a checksum Mix() from
  every function, so a re-evaluated selector mixed extra values and the final checksum
  drifted while every global still matched.

  This test counts the evaluations directly rather than checking a result, because the
  RESULT was always right — only the side effects were wrong. }
program test_case_selector_single_eval;

var
  calls: LongInt;
  fails: LongInt;

function F(v: LongInt): LongInt;
begin
  calls := calls + 1;
  F := v;
end;

function FS: AnsiString;
begin
  calls := calls + 1;
  FS := 'beta';
end;

procedure Check(const what: AnsiString; got: LongInt);
begin
  if got = 1 then
    writeln('ok   ', what, ' evals=', got)
  else
  begin
    writeln('FAIL ', what, ' evals=', got, ' (want 1)');
    fails := fails + 1;
  end;
end;

procedure Ordinal(const what: AnsiString; v: LongInt);
begin
  calls := 0;
  case F(v) of
    0:       ;
    1, 2, 3: ;
    5..7:    ;
  else
    ;
  end;
  Check(what, calls);
end;

begin
  fails := 0;

  { every arm, because the bug's cost scaled with how far the chain was walked }
  Ordinal('selector matches the FIRST label', 0);   { the case that always "worked" }
  Ordinal('selector matches a label LIST', 2);
  Ordinal('selector matches a RANGE', 6);           { a range tested the selector twice }
  Ordinal('selector matches NOTHING (else)', 9);    { the worst case: the whole chain }

  { a string selector takes the full-string comparison path, not the ordinal one }
  calls := 0;
  case FS of
    'alpha': ;
    'beta':  ;
  else
    ;
  end;
  Check('STRING selector', calls);

  if fails = 0 then writeln('PASS') else writeln('FAILED ', fails);
end.
