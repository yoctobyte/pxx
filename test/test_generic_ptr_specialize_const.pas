program test_generic_ptr_specialize_const;
{ A typed constant whose type is a POINTER to an inline specialization:

    const PC: ^specialize TCell<Integer> = Nil;

  The token group `TCell<Integer>` here is followed by `=`, which is the shape
  a "is this a declaration or a use?" test keys on -- and this is a USE. It is
  preceded by `specialize`, not by `:`, so a guard that excludes only the typed
  const spelling `x: TFoo<Integer> = (...)` lets this one through and suppresses
  the rewrite, after which `^specialize` parses as the pointed-to type and the
  program does not compile.

  That is not hypothetical: a blacklist-style guard added on 2026-08-30 did
  exactly this and widened
  regression-test-pascal-conformance-shard0-6-2 from the few type names that
  lex as tkIdent to EVERY type name. This test is the control that was missing.

  `Integer` deliberately: it lexes as a dedicated token kind rather than an
  identifier. The tkIdent-spelled names (LongInt, Cardinal, Int64, QWord,
  SmallInt, Word, ShortInt, and any user alias) are still broken by that
  conformance ticket, which is a separate and older defect -- so gating this
  test on one of those would make it fail for the wrong reason. }
type
  generic TCell<T> = record
    v: T;
  end;

const
  PC: ^specialize TCell<Integer> = Nil;

var
  c: specialize TCell<Integer>;

begin
  c.v := 7;
  writeln('ptrspec ', c.v, ' ', Ord(PC = Nil));
end.
