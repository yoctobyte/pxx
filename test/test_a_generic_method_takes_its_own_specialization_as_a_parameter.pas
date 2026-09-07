program test_a_generic_method_takes_its_own_specialization_as_a_parameter;
{ A GENERIC CONTAINER COULD NOT HAVE A METHOD TAKING ANOTHER INSTANCE OF
  ITSELF, whenever the user named the specialization with an alias -- which is
  how everyone writes one.

    generic TList<_T> = class
      procedure Assign(Source: specialize TList<_T>);
    end;
    type TMyIntList = specialize TList<Integer>;
    ...  l2.Assign(l1);
    -> no overload of Assign matches these arguments
       argument types: (class)

  The class is streamed under the name the user gave it, `TMyIntList`, while the
  parameter's `specialize TList<_T>` substitutes to the CANONICAL key
  `TList$Integer`. The two names differ, the group was left uncollapsed, and the
  literal `specialize TList<Integer>` in the stream minted a SECOND class. The
  argument and the parameter were then two unrelated classes.

  THE DISCRIMINATOR THAT SAYS IT IS THE NAME AND NOT THE MECHANISM: spell the
  variables inline -- `var l1, l2: specialize TList<Integer>` -- and the
  identical program compiles and runs on the compiler that refuses this one,
  because then the user's name IS the canonical one. Both spellings are rows
  below.

  THE LAST TWO ROWS ARE THE POSITIVE CONTROL AND THEY CARRY THE RISK. Collapsing
  a self-reference to "the class being built" is only correct if it fires for
  the RIGHT specialization: two specializations of one template, made with
  different type arguments, must each get their own. If the collapse leaked, the
  AnsiString list's Assign would take an Integer list -- so the two are given
  different type arguments AND different values, and both are read back. Equal
  arguments would make a leak invisible.

  Oracle: fpc 3.2.2 prints all five rows exactly as below.
  bug-p-a-nested-specialization-is-named-by-its-alias-so-one-name-serves-every-outer-specialization }
{$mode objfpc}{$H+}
type
  generic TList<_T> = class
    data: _T;
    procedure Put(item: _T);
    procedure Assign(Source: specialize TList<_T>);   { names its OWN specialization }
    function  Same(Other: specialize TList<_T>): Boolean;
  end;

procedure TList.Put(item: _T);
begin
  data := item;
end;

procedure TList.Assign(Source: specialize TList<_T>);
begin
  data := Source.data;
end;

function TList.Same(Other: specialize TList<_T>): Boolean;
begin
  Result := Other.data = data;
end;

type
  TIntList = specialize TList<Integer>;
  TStrList = specialize TList<AnsiString>;      { a DIFFERENT type argument }

var
  a, b: TIntList;
  s, t: TStrList;
  inl1, inl2: specialize TList<Int64>;          { the INLINE spelling, no alias }
begin
  a := TIntList.Create; a.Put(10);
  b := TIntList.Create; b.Put(20);
  b.Assign(a);
  WriteLn('alias  int  = ', b.data);
  WriteLn('alias  same = ', b.Same(a));

  s := TStrList.Create; s.Put('one');
  t := TStrList.Create; t.Put('two');
  t.Assign(s);
  WriteLn('alias  str  = ', t.data);

  inl1 := specialize TList<Int64>.Create; inl1.Put(1000000);
  inl2 := specialize TList<Int64>.Create; inl2.Put(2000000);
  inl2.Assign(inl1);
  WriteLn('inline int64= ', inl2.data);
  WriteLn('inline same = ', inl2.Same(inl1));
end.
