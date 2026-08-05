{ syncobjs.TCriticalSection must actually exclude. It was a no-op stub -- every
  method an empty body, TryEnter always True -- so threaded code locked with
  nothing and lost updates in silence
  (bug-b-criticalsection-was-a-no-op-stub).

  Single-threaded on purpose: the multi-threaded lost-update case lives in
  tools/fpc_diff_probe.sh (thread-critical-section, 4x2000 increments = 8000).
  What a stub cannot fake is TryEnter answering False while the lock is held,
  and that needs no threads at all. }
program test_criticalsection;
uses syncobjs;
var c: TCriticalSection; a, b, d: Boolean;
begin
  c := TCriticalSection.Create;
  a := c.TryEnter;      { free -> takes it }
  b := c.TryEnter;      { held -> must fail }
  c.Release;
  d := c.TryEnter;      { free again }
  c.Release;
  c.Acquire;
  c.Release;
  c.Enter;
  c.Leave;
  writeln(a, '|', b, '|', d);
  if a and (not b) and d then writeln('PASS') else writeln('FAIL');
  c.Free;
end.
