program test_overload_no_narrowing;
{ Overload resolution must not pick a candidate that TRUNCATES the argument.
  It used to take the first COMPATIBLE candidate in chain order, so with p(Byte)
  declared before p(Word), `p(40000)` printed 64 — a silent wrong value in
  ordinary user code (found while fixing Hi/Lo, which hit the same machinery).

  A lossless candidate now wins whatever the declaration order. Where the
  argument HAS a narrow type, the exact match still wins, and a narrowing
  candidate is still selected when it is the only one that fits. }

procedure p(v: Byte); overload; begin writeln('byte ', v); end;
procedure p(v: Word); overload; begin writeln('word ', v); end;
procedure p(v: LongInt); overload; begin writeln('longint ', v); end;
procedure p(v: Int64); overload; begin writeln('int64 ', v); end;

{ Only a narrow candidate exists: it must still be chosen, not rejected. }
procedure q(v: Byte); overload; begin writeln('byte ', v); end;

var
  b: Byte;
  w: Word;
  n: Integer;
begin
  { Untyped literals type as LongInt here (FPC sizes them to the value, so it
    would say byte/word for the middle two — same VALUES, different overload;
    see bug-a-integer-literal-not-typed-by-its-value-for-overload-resolution). }
  p(5);
  p(200);
  p(40000);
  p(100000);
  p(5000000000);
  { A real narrow type still takes its exact overload. }
  b := 200; p(b);
  w := 40000; p(w);
  { Narrowing is a last resort, not a refusal. }
  n := 7; q(n);
end.
