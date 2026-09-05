program test_cond_compare_names_symbol_fail;
{ A `{$if}` comparison against a symbol that has no VALUE must NAME the symbol.

  It used to say only `comparison requires integer operands`, which is a true
  statement about the evaluator's value stack and a useless one about the
  program. An identifier with no value pushes as a BOOLEAN — the slot answers
  "is it defined?" — so a plain missing define presents as a TYPE MIX, and the
  message points at the type system rather than at the absent define.

  Measured 2026-09-05 on FPC's own cfileutl.pas, whose line 155 is
  `{$if FPC_FULLVERSION < 20701}`. The march invocation had not applied the FPC
  define profile, so FPC_FULLVERSION was simply absent; the message sent the
  reader into the conditional-expression evaluator, where nothing was wrong, and
  the actual fix was a compiler FLAG (--mimic-fpc-compiler). The diagnostic was
  correct about the wrong layer.

  This is a REFUSAL test and it greps the MESSAGE, never the exit code: the
  program is expected to fail either way, so an exit-status check would pass
  against the old wording and against any other error the file might acquire.
  bug-p-an-unqualified-call-to-a-user-routine-named-read-or-write-is-eaten-by-the-intrinsic }
{$if THIS_SYMBOL_IS_NOT_DEFINED > 2}
{$endif}
begin
end.
