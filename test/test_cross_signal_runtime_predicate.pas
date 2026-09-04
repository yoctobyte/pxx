program test_cross_signal_runtime_predicate;
{ PXX_HAS_SIGNALS, asked on every target -- because the bug this covers was the
  predicate behind that define answering for a population nobody had asked it
  about.

  TargetHasSignalRuntime (ir_codegen.inc) is the one predicate five signal sites
  share. It had no wasm32 arm and fell through to True. Nothing looked wrong:
  EmitSignalRuntimeForTarget's wasm32 arm is deliberately EMPTY, so no runtime
  was emitted either way, and the two answers agreed by accident on every target
  that had ever asked. The disagreement only became visible when a third
  consumer -- this define -- asked the predicate directly: pxxcio.pas's
  __pxx_c_signal took its live arm on wasm32, emitted IR_SET_SIGNAL, and the
  backend refused the whole body. 55 sources in the corpus census gained a
  wasm32 gap in one commit, from a change that was correct everywhere it looked.

  So this test asks the question a build can actually answer about itself, on
  each target, and the ANSWERS DIFFER -- which is the point. A row that read the
  same everywhere would be one that could not have caught this. The expected
  string is per target and the Makefile holds the table:

    x86-64, i386, arm32, aarch64, riscv32   signals yes
    wasm32                                  signals no
    xtensa --xtensa-abi=windowed            signals no   (Call0-only emitter)
    any ESP platform                        signals no   (FreeRTOS is not a Unix)

  It also RUNS, so on wasm32 it doubles as proof the module is valid and
  executes -- before the fix this program compiled, validated, and its
  SetSignalHandler sibling trapped at run time. }
begin
{$ifdef PXX_HAS_SIGNALS}
  WriteLn('signals yes');
{$else}
  WriteLn('signals no');
{$endif}
end.
