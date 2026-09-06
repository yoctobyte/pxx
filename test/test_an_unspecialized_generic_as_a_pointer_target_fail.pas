{ A generic's BARE name used as the target of a `^`, outside the generic itself.

  `TTest` names a template, not a type: there is no such record until someone
  says which T. pxx accepted this and sized the pointee as nothing, which is the
  fpc test suite's tgeneric83 / tgeneric84 / tgeneric85 -- three `%FAIL` rows,
  all three of which pxx compiled clean. fpc 3.2.2: `Generics without
  specialization cannot be used as a type for a variable`.

  THE SPECIALIZATION BELOW IS LOAD-BEARING, not decoration. The refusal must not
  be "this name is unknown": TTest IS specialized in this very program, so a
  drain that only asked whether the name ever became a type in some form could
  have been satisfied by the specialization and let the bare use through. The
  message is checked for the generic wording, not just for a nonzero exit.

  The legal inside-the-body use (`generic TNode<T> = record next: ^TNode; end`)
  is covered by test_forward_pointer_targets_that_resolve_late's sibling rows and
  by the corpus; it must keep compiling, and it does, because SpecializeTemplate
  rewrites the bare name to the specialization's before that body is parsed. }
program test_an_unspecialized_generic_as_a_pointer_target_fail;
{$mode objfpc}

type
  generic TTest<T> = record
    v: T;
  end;

  PTest = ^TTest;                        { <-- the refusal }
  TIntTest = specialize TTest<Integer>;  { and TTest IS specialized here }

var
  x: TIntTest;
  p: PTest;

begin
  x.v := 7;
  p := nil;
  writeln(x.v);
end.
