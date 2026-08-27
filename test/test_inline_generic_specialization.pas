{ FPC's INLINE specialization of a generic ROUTINE: `specialize F<C>(args)`
  written at the call site, in expression AND statement position, instead of
  pxx's older declaration form `specialize F<C> as Name;`.

  Rows:

    a  expression position, twice in one statement, one concrete type
    b  a SECOND concrete type for the same template — two specializations of
       one generic routine coexist
    c  statement position, a generic PROCEDURE with var parameters
    d  ...and a second concrete type for it, so the distinct-argument
       collection is exercised on the procedure side too
    e  the declaration form still works, and coexists with inline uses of the
       same template in the same program (a pxx extension FPC does not accept,
       so this row is not part of the FPC oracle below)
    f  the specialization is a plain routine downstream: it takes part in
       ordinary expression nesting

  Rows a-d are oracled against FPC 3.2.2 -Mobjfpc (the same shapes the
  gen-func-int / gen-func-string / gen-swap-var probe cases carry).
  compat-pascal-inline-generic-specialization }
program test_inline_generic_specialization;

generic function MaxOf<T>(a, b: T): T;
begin
  if a < b then Result := b else Result := a;
end;

generic procedure Swp<T>(var a, b: T);
var
  tmp: T;
begin
  tmp := a; a := b; b := tmp;
end;

specialize MaxOf<Char> as MaxCh;

var
  x, y: Integer;
  s1, s2: string;
begin
  WriteLn('a ', specialize MaxOf<Integer>(3, 9), '|', specialize MaxOf<Integer>(9, 3));
  WriteLn('b ', specialize MaxOf<string>('abc', 'abd'));

  x := 1; y := 2;
  specialize Swp<Integer>(x, y);
  WriteLn('c ', x, '|', y);

  s1 := 'p'; s2 := 'q';
  specialize Swp<string>(s1, s2);
  WriteLn('d ', s1, '|', s2);

  WriteLn('e ', MaxCh('m', 'z'));
  WriteLn('f ', specialize MaxOf<Integer>(1, 2) + specialize MaxOf<Integer>(10, 20));
end.
