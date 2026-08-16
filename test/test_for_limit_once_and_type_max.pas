{ Regression: the AN_FOR lowering had three defects in one shape
  (bug-a-for-loop-limit-reevaluated-and-overflows-at-type-max):
  the limit expression was re-emitted inside the loop and so ran once per
  iteration, a limit at the counter type's MAXIMUM looped forever (i+1 wraps),
  and the counter was left at limit+/-1 instead of FPC's limit.
  Every value below is what `fpc -O- -Mobjfpc` prints. }
program test_for_limit_once_and_type_max;
var calls, i, n, k: integer; c: char; b: byte; si: shortint; w: word;

function Limit: integer; begin Inc(calls); Limit := 3; end;

begin
  { 1. the limit expression is evaluated exactly once }
  calls := 0; n := 0;
  for i := 1 to Limit do n := n + i;
  writeln('sum=', n, ' calls=', calls);
  calls := 0;
  for i := 1 to Limit do ;
  writeln('emptybody-calls=', calls);

  { a limit VARIABLE is read once too -- mutating it in the body must not
    change the trip count }
  n := 3; k := 0;
  for i := 1 to n do begin Inc(k); n := 0; end;
  writeln('iters=', k);
  n := 3; k := 0;
  for i := n downto 1 do begin Inc(k); n := 99; end;
  writeln('itersdown=', k);

  { 2. a limit at the counter type's maximum terminates }
  n := 0; for c := #0 to #255 do Inc(n); writeln('char=', n);
  n := 0; for b := 0 to 255 do Inc(n); writeln('byte=', n);
  n := 0; for si := -128 to 127 do Inc(n); writeln('shortint=', n);
  n := 0; for b := 255 downto 0 do Inc(n); writeln('bytedown=', n);
  n := 0; for w := 0 to 65535 do Inc(n); writeln('word=', n);
  n := 0; for i := 2147483645 to 2147483647 do Inc(n); writeln('int=', n);

  { 3. the counter is left AT the limit after a normal exit (FPC's value) }
  for i := 1 to 5 do ; writeln('after-to=', i);
  for i := 5 downto 1 do ; writeln('after-down=', i);
  for b := 250 to 254 do ; writeln('after-byte=', b);
  for i := 1 to 5 do if i = 3 then break; writeln('after-break=', i);
end.
