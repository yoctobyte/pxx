program test_a_unit_free_program_pays_no_threadvar_area;
{ A Pascal program that names neither the per-thread storage keyword nor an
  import clause cannot reach the per-thread allocator, so it is given none of
  that area — with no flag. __pxxTlsBlockSize is then the compiler-owned slot
  map alone: 1152 = (TLS_SLOT_HEAP_MAGN + HEAP_MAG_BINS) * 8, which is
  TLS_USER_FIRST_OFF.

  READ THE PROSE ABOVE BEFORE EDITING IT. This comment deliberately does not
  SPELL either keyword, because the prescan reads the SOURCE TEXT and does not
  care that a word is inside a comment. An earlier draft of this file explained
  itself using both words and therefore reserved the full area and printed 4224
  — the test asserting the feature disabled the feature. That is the scan's
  conservatism working exactly as intended (every way it can be wrong costs
  bytes, never correctness), and this file is the cheapest demonstration of it
  anyone will find. The program NAME is safe: the word inside it is flanked by
  underscores, which are identifier characters, so the whole-word test rejects
  it — and that is worth keeping as the live check on the boundary logic.

  THIS ROW IS ALSO THE GUARD ON THE FACT THE PRESCAN RESTS ON. An import-free
  program still pulls builtinheap, softfloat and builtin AMBIENTLY, so the
  prescan is only correct while no unit under lib/ or compiler/builtin/ declares
  per-thread storage — counted 2026-09-19, none does. If one is ever added, its
  first declaration meets the 0-byte cap and THIS ROW GOES RED with a diagnostic
  naming the flag, instead of a wrong size shipping quietly. That is the whole
  reason the area is a cap and not a budget.

  The companion rows in the Makefile assert the other direction: an importing
  program and a per-thread-declaring program each keep the area. }
begin
  WriteLn('block=', __pxxTlsBlockSize);
end.
