{ A nested type inherited from a GENERIC ancestor, named as a generic argument
  in the descendant's body. fpc compiles and runs it; we refused it with
  `unknown type: PT` -- the rtl-generics shape, and the wall the
  Generics.Collections driver stood at.

  bug-p-a-class-nested-type-as-a-specialization-argument-resolves-at-unit-scope

  `PT` is in NEITHER table NestedSpecArg consults: it is not a parameter of the
  enclosing template, and it is not declared in the enclosing template's OWN
  body -- CollectHoistCandidates walked one body and stopped. So the bare
  spelling survived into the minted alias and then into the template body that
  materialises at unit scope.

  TWO RUNGS, NOT ONE, on purpose. One rung passes with a walk that handles only
  the immediate parent; the corpus shape is a chain and the walk has to reach
  past the middle of it. `deep` is the row that fails when it does not.

  `class abstract(...)`, NOT `class(...)`, for the same kind of reason. The hint
  words sit BETWEEN the keyword and the parenthesis, and an ancestor walk that
  tests the token right after `class` for `(` refuses every one of them.
  rtl-generics writes nearly all of these classes that way and no hand-written
  reduction does, so the entire corpus failed while every repro passed. Both
  spellings are on the ladder here.

  THE SECOND INSTANTIATION WAS DEFERRED AND IS NOW HERE (2026-09-09). It tripped
  bug-p-a-hoisted-nested-type-name-leaks-between-two-specializations-of-one-template,
  which was pre-existing and separate -- verified by reproducing it on a binary
  without this fix -- so the row would have gone red for the other defect's
  reason. That one is fixed, so `two` and `ptr2` close the gap.

  THE TWO POINTEES DIFFER, WHICH IS THE WHOLE POINT OF THE ROW. Give both
  instantiations the same argument and the two hoisted names coincide, and the
  test prints the right answer while reading the wrong row. `ptr2` assigns
  `by.First` into a `^Byte`: under the leak that expression is typed `^LongInt`
  and the program does not compile at all, so the discriminator is the type and
  not only the value.

  `ptr` is what makes this more than a parse test: it stores through the
  inherited PT and reads the value back, so the hoisted type has to really be
  `^LongInt` and not merely a name that resolves. A row asserting only that the
  program compiles would pass on a hoist that carried the wrong substitution. }
program test_an_inherited_nested_type_is_a_specialization_argument;
{$mode delphi}
type
  TEnumerable<T> = class
  public type
    PT = ^T;
  public
    function Zero: T;
  end;

  TPtrs<T, P> = class
    Q: P;
  end;

  TWithPointers<T> = class abstract(TEnumerable<T>)
  public
    FItem: T;
    function Ptrs: TPtrs<T, PT>;
    function First: PT;
  end;

  { the second rung -- PT reaches this body through TWithPointers, and this one
    is spelled without `abstract` so both spellings are on the ladder }
  TQueueLike<T> = class(TWithPointers<T>)
  public
    function Deep: TPtrs<T, PT>;
  end;

function TEnumerable<T>.Zero: T; begin Result := Default(T); end;
function TWithPointers<T>.Ptrs: TPtrs<T, PT>; begin Result := nil; end;
function TWithPointers<T>.First: PT; begin Result := @FItem; end;
function TQueueLike<T>.Deep: TPtrs<T, PT>; begin Result := nil; end;

var
  li: TQueueLike<LongInt>;
  by: TQueueLike<Byte>;
  p:  ^LongInt;
  pb: ^Byte;
begin
  li := TQueueLike<LongInt>.Create;
  li.FItem := 7;

  WriteLn('one ', Ord(li.Ptrs = nil));
  WriteLn('deep ', Ord(li.Deep = nil));

  { the inherited PT is a REAL pointer to the substituted type, not a name that
    happens to resolve -- assign through it and read the value back }
  p := li.First;
  p^ := 9;
  WriteLn('ptr ', li.FItem);

  WriteLn('zero ', li.Zero);

  { a SECOND specialization of every template on the chain, with a different
    pointee -- see the note at the top }
  by := TQueueLike<Byte>.Create;
  by.FItem := 3;
  WriteLn('two ', Ord(by.Ptrs = nil));
  pb := by.First;
  pb^ := 200;
  WriteLn('ptr2 ', by.FItem);
end.
