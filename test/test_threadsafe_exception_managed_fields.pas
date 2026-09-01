{ A CAUGHT exception must release its managed fields under --threadsafe.

  The object itself was already freed at handler exit (620989250); its FIELDS
  were not. PXXObjFree runs PXXClassFinalize, whose managed pass is compiled out
  under PXX_TS_HARDLOCK -- x86-64 --threadsafe -- because there the heap lock is
  the codegen BSS spinlock and Pascal cannot take it. The `Free` desugar
  compensates by emitting PXXClassFinalizeManaged as a second call under the
  emitted lock; the exception lowering did not, so every managed field of every
  caught exception leaked. An exception class with a string message is the
  ordinary case, not a corner.

  Measured before the fix, this program at 3000 iterations:

      --threadsafe   allocs=10975 frees=8230  live=2745
      plain          allocs=10975 frees=10972 live=3

  Identical allocation counts, so it is the free side alone.

  THE STRING MUST BE BUILT AT RUNTIME. A folded literal is a static-rc string
  that nothing frees on either path, so the first version of this probe used
  'a' + 'b' and measured NOTHING -- allocs identical, live=1, fix or no fix.
  The Chr() concatenation below defeats folding, and it is the only reason this
  test can fail at all. Do not "simplify" it to a literal.

  THIS TEST IS x86-64 --threadsafe ONLY, and needs the FLAG, not the directive:
  the compiler refuses `{$threadsafe on}` without it precisely because the two
  used to disagree about PXX_TS_HARDLOCK (see lexer.inc). Wired with
  assert_no_leak rather than a cross-target differential, for the reason that
  script's own header gives: every backend leaked the same way, so a
  target-vs-target compare would have matched two equally wrong numbers. }
program test_threadsafe_exception_managed_fields;

type
  TMsgErr = class
    Msg: AnsiString;
  end;

var
  i, caught: Integer;
  e: TMsgErr;
  s: AnsiString;

begin
  caught := 0;
  for i := 1 to 3000 do
    try
      s := 'msg number ' + Chr(48 + (i mod 10)) + Chr(48 + (i mod 7)) + '----------------';
      e := TMsgErr.Create;
      e.Msg := s;
      raise e;
    except
      on E: TMsgErr do caught := caught + 1;
    end;
  WriteLn('caught=', caught);
end.
