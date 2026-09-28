{ Every unit's finalization runs at normal program end, in reverse
  initialisation order -- on wasm32 too.

  The drivers end the program by calling the finalizer runner through
  EmitCallProc, i.e. as machine code; a wasm32 `main` is synthesised from the
  body's chunks, so on wasm32 no finalization ever ran (and with it no Nil
  Python atexit handler: test_nilpy_atexit_runs_on_wasm32).

  The expected output is PXX's on x86-64, NOT FPC's: FPC 3.2.2 does run these
  finalizers (a file written from one appears), but console output from a
  unit's finalization is lost there, on stdout and stderr alike -- measured,
  and a separate question. }
program test_a_unit_finalization_runs_on_wasm32;
uses uwasmfini2;

begin
  WriteLn('body');
end.
