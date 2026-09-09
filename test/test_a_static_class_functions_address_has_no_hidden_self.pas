program test_a_static_class_functions_address_has_no_hidden_self;
{ FPC's `static` directive on a class method means NO Self at all -- not "a class
  method", which is what pxx's UMthIsStatic answers and which DOES carry a hidden
  Self (the metaclass, and `class function TAssert.Suite` depends on seeing the
  runtime class through it).

  The two were one flag, so every `static` method's address carried a Self that
  its source does not declare. Invisible on an ordinary call, because the
  compiler emits the Self it also expects -- so the `direct` row below was
  ALREADY correct before the fix and cannot fail. The divergence needs the
  ADDRESS to escape into a plain function pointer, which is what a dispatch
  table does and what rtl-generics' TComparerService does to reach its
  comparers.

  `selfptr` is the POSITIVE CONTROL and it is the row that matters: a cast that
  hands the routine one extra leading argument must produce the WRONG answer.
  Before the fix the two compilers were exactly inverted here -- pxx 107/119/107
  against fpc 107/107/100 -- which is what proves the routine itself was fine
  and only its arity was off.

  Both a CLASS and a RECORD host, because the two are parsed by different
  declaration parsers (ParseTypeSection's member loop and ParseRecordMethodDecl)
  and each writes param 0 before it has read the directives.
  bug-p-a-static-class-functions-address-carries-a-hidden-self }
{$mode delphi}
type
  TPlainFunc = function (A: Pointer; ASize: SizeInt): Pointer;
  TSelfFunc  = function (S: Pointer; A: Pointer; ASize: SizeInt): Pointer;

  TSvc = class
    class function Pick(A: Pointer; ASize: SizeInt): Pointer; static;
    class function Plain(ASize: SizeInt): Pointer;   { NOT static: keeps its metaclass Self }
  end;

  TRecSvc = record
    class function Pick(A: Pointer; ASize: SizeInt): Pointer; static;
  end;

class function TSvc.Pick(A: Pointer; ASize: SizeInt): Pointer;
begin
  Result := Pointer(PtrUInt(ASize) + 100);
end;

class function TSvc.Plain(ASize: SizeInt): Pointer;
begin
  Result := Pointer(PtrUInt(ASize) + 200);
end;

class function TRecSvc.Pick(A: Pointer; ASize: SizeInt): Pointer;
begin
  Result := Pointer(PtrUInt(ASize) + 300);
end;

const
  { the address of a static method as a const-array ELEMENT -- the dispatch-table
    shape, and the only shape that can see this defect }
  Table: array[0..2] of Pointer = (@TSvc.Pick, @TRecSvc.Pick, @TSvc.Plain);

var
  p: Pointer;
begin
  p := TSvc.Pick(nil, 7);
  WriteLn('direct   ', PtrUInt(p));
  p := TPlainFunc(Table[0])(nil, 7);
  WriteLn('plainptr ', PtrUInt(p));
  p := TSelfFunc(Table[0])(nil, nil, 7);
  WriteLn('selfptr  ', PtrUInt(p));

  p := TRecSvc.Pick(nil, 7);
  WriteLn('rec direct   ', PtrUInt(p));
  p := TPlainFunc(Table[1])(nil, 7);
  WriteLn('rec plainptr ', PtrUInt(p));

  { THE NEGATIVE CONTROL, and it is the row the three above cannot supply: an
    ordinary `class function` -- no `static` -- must KEEP its hidden metaclass
    Self. A fix that simply stripped Self from every class method would pass all
    three rows above and silently break the FPC idiom that depends on the
    runtime class (`class function TAssert.Suite` reads Self to build the right
    suite). So this one is read BOTH ways: directly, and through the same
    two-argument plain-function cast, where the two arguments must land on
    (Self, ASize) and not on (ASize, junk). }
  p := TSvc.Plain(7);
  WriteLn('nonstatic ', PtrUInt(p));
  p := TPlainFunc(Table[2])(nil, 7);
  WriteLn('nonstatic via cast ', PtrUInt(p));
end.
