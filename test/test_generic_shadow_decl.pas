program test_generic_shadow_decl;
{ bug-p-the-delphi-generic-rewrite-rewrites-a-shadowing-declaration-as-a-use.

  In mode Delphi the generic-use rewrite scans for `TName<...>` by name and
  arity and splices `specialize` in front of it. It matched a DECLARATION whose
  name was already registered as a template -- here `TBox<T>` redeclared by a
  program that also imports one -- and the parse died with
  `Expected: =, but got: TBox`. FPC compiles this file, so it is valid Pascal
  we rejected.

  The rewrite's only observable is the token stream it edits, so "it compiles"
  cannot tell a correct rewrite from one that injects in the wrong place. The
  Makefile rule therefore also asserts, via PXXDBG=p.dgen, that NO `specialize`
  is injected in front of the declaration -- while TPairU below keeps a real
  specialization in the file, so the assertion cannot pass by the rewrite
  having stopped working altogether.

  SCOPE: this asserts the PARSE only. Which of the two same-named generics wins
  name resolution is a SEPARATE open defect -- pxx currently resolves to the
  IMPORTED one where FPC takes the local redeclaration -- so both records below
  deliberately declare the same member `V`, and this test's result cannot depend
  on that question. See
  bug-p-a-generic-declaration-does-not-shadow-an-imported-one-of-the-same-name. }
{$MODE DELPHI}
uses ugenericshadow;

type
  { shadows ugenericshadow's TBox<T> — same name, same arity }
  TBox<T> = record
    V: T;
  end;

  { A PARAMFORM use: TPairU is specialized with TWrap's OWN parameter name, so
    it goes down the in-place arm that splices `specialize` into the stream --
    the exact arm this bug lived in. It keeps a real injection in this file, so
    the zero-injection assertion on the declaration above cannot be satisfied by
    a rewrite that has stopped firing altogether. }
  TWrap<T> = record
    Inner: TPairU<T, T>;
  end;

var
  b: TBox<Integer>;
  p: TPairU<Integer, Integer>;
  w: TWrap<Integer>;

begin
  b.V := 5;
  p.L := 3;
  p.R := 4;
  w.Inner.L := 10;
  writeln('shadow ', b.V + p.L + p.R, ' ', w.Inner.L);
end.
