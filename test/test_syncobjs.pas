{ syncobjs API shape, and that the lock really excludes.

  THIS TEST USED TO ASSERT THE BUG. TCriticalSection was a no-op stub whose
  TryEnter returned True unconditionally, so `cs.Acquire; if cs.TryEnter then
  writeln(2)` printed 2 — and the expectation recorded that as correct. A real
  lock answers False there, which is the whole point of TryEnter
  (bug-b-criticalsection-was-a-no-op-stub). Expectation updated with the fix:
  the old one was the stub's behaviour written down. }
program test_syncobjs;

uses syncobjs;

var
  cs: TCriticalSection;
begin
  cs := TCriticalSection.Create;
  cs.Enter;
  writeln(1);
  cs.Leave;
  cs.Acquire;
  if cs.TryEnter then writeln('BUG: TryEnter succeeded on a held lock')
  else writeln(2);
  cs.Release;
  if cs.TryEnter then writeln(3) else writeln('BUG: TryEnter failed on a free lock');
  cs.Release;
  writeln(4);
end.
