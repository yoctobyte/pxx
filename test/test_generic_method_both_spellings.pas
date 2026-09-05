{ A generic METHOD, in the three positions the same declaration can occupy and
  in both surfaces. Every row here was `expected ':' before '<'` or
  `expected ':' before 'function'` before
  feature-p-generic-routines-in-a-class-body-and-in-delphi-spelling; the
  identical generic FREE routine had worked since 71deb21d4, which is what kept
  the gap looking like two features instead of one normalisation.

    objfpc instance   generic function Add<T>      t.specialize Add<C>(..)
    objfpc class      generic class function ..    TTest.specialize AddC<C>(..)
    Delphi instance           function Add<T>      t.Add<C>(..)
    Delphi class        class function AddC<T>     TTest.AddC<C>(..)

  Two type arguments per method on purpose: one specialization proves the
  substitution happened, two prove the EXPANSION did -- a rewrite that emitted
  the method once and reused it would print the same first line and fail here.

  Two classes declare a method of the same NAME on purpose. A use site names a
  method and a receiver whose type the token stream cannot resolve, so the first
  class to expand rewrites the OTHER class's uses along with its own; without the
  by-name specialization memo the second class silently kept its generic
  declaration and the program did not compile. This row is the only thing that
  exercises that path.

  fpc 3.2.2 cannot hold both surfaces in one compilation (`-Mobjfpc` refuses the
  Delphi header, `-Mdelphi` refuses the `generic` keyword), so each surface was
  diffed against fpc in its own program -- byte-identical, 2026-09-05 -- and this
  row asserts the union. }
program test_generic_method_both_spellings;

type
  TObjFpc = class
    generic function Add<T>(a, b: T): T;
    generic class function Twice<T>(a: T): T;
  end;

  TDelphi = class
    function Add<T>(a, b: T): T;
    class function Twice<T>(a: T): T;
  end;

generic function TObjFpc.Add<T>(a, b: T): T;
begin
  Result := a + b;
end;

generic class function TObjFpc.Twice<T>(a: T): T;
begin
  Result := a + a;
end;

function TDelphi.Add<T>(a, b: T): T;
begin
  Result := a + b;
end;

class function TDelphi.Twice<T>(a: T): T;
begin
  Result := a + a;
end;

var
  o: TObjFpc;
  d: TDelphi;
begin
  o := TObjFpc.Create;
  d := TDelphi.Create;
  WriteLn('objfpc ', o.specialize Add<Integer>(2, 3));
  WriteLn('objfpc ', o.specialize Add<String>('Hello', 'World'));
  WriteLn('objfpc ', TObjFpc.specialize Twice<Integer>(21));
  WriteLn('objfpc ', TObjFpc.specialize Twice<String>('ab'));
  WriteLn('delphi ', d.Add<Integer>(2, 3));
  WriteLn('delphi ', d.Add<String>('Hello', 'World'));
  WriteLn('delphi ', TDelphi.Twice<Integer>(21));
  WriteLn('delphi ', TDelphi.Twice<String>('ab'));
end.
