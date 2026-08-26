{ A TYPED string constant is storage, not a literal alias.

  `const S: string = 'a';` then `S := 'b'` used to answer
  *undefined variable (S)* — a NAME-RESOLUTION error, which is the tell: a
  genuine read-only constant would have said "cannot assign". There was no
  storage to be read-only. The constant was registered in the StrConst table and
  a use of the name expanded to the literal span, so READING worked and only the
  store failed, and only for this one type: Integer, Char and array typed
  constants have always been assignable here.

  This is also what FPC does — a typed const is an initialised variable there,
  which is why `const A: string = 'x'; B = A + 'y';` is *Illegal expression* in
  FPC and why the UNTYPED `U` row below, which IS a literal alias in both
  compilers, keeps working unchanged.

  The `local` rows are the shape that would break if the storage were allocated
  per call rather than once: a routine-local typed const is STATIC, so its
  mutation is visible on the next call. R is called twice and the second call
  starts where the first left off — in pxx and in fpc alike.

  bug-p-a-typed-string-constant-cannot-be-assigned
  bug-p-typed-constants-cannot-hold-a-pointer-a-nested-aggregate-or-storage }
program test_writeable_typed_string_const;

{$WRITEABLECONST ON}

type
  TFoo = class
  const
    Tag: string  = 'foo';
    Num: Integer = 7;
  public
    procedure Show;
  end;

const
  S: string     = 'a';
  A: AnsiString = 'ab' + 'cd';     { the concatenation form }
  F: string[8]  = 'frz';           { a FROZEN string slot }
  C: Char       = 'x';             { unchanged: never was a literal alias }
  N: Integer    = 0;               { likewise }
  U             = 'untyped';       { UNTYPED: still a literal alias, both compilers }

procedure TFoo.Show;
begin
  WriteLn('meth  : ', Tag, ' ', Num);
end;

procedure R;
const
  LS: string = 'rl';
begin
  LS := LS + '!';
  WriteLn('local : ', LS);
end;

var
  obj: TFoo;
begin
  WriteLn('read  : ', S, ' ', A, ' ', F, ' ', C, ' ', N, ' ', U);
  S := 'b'; A := 'zz'; F := 'q'; C := 'y'; N := 1;
  WriteLn('write : ', S, ' ', A, ' ', F, ' ', C, ' ', N);
  WriteLn('len   : ', Length(S), ' ', Length(A), ' ', Length(F));
  WriteLn('qual  : ', TFoo.Tag, ' ', TFoo.Num);
  obj := TFoo.Create;
  obj.Show;
  R;
  R;
end.
