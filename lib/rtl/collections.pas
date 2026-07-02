{ SPDX-License-Identifier: Zlib }
unit collections;

{ A generic growable list backed by a managed `array of T` field. The element
  storage is reference-counted dynamic-array memory, so there is no manual
  allocation, freeing, or capacity bookkeeping exposed to the user: the list
  owns its storage and the array machinery finalizes it on scope exit.

  Use it by specializing the template for a concrete element type:

      uses collections;
      type
        TIntList = specialize TList<Integer>;
        TStrList = specialize TList<AnsiString>;

  An AnsiString element type requires the program to define PXX_MANAGED_STRING.

  The template and its method bodies live here; a `specialize` in any using
  program materialises a concrete class with its own methods.

  Dialect notes: methods assign Result (never the method name); the element
  field is a dynamic array, grown in chunks (doubling) rather than one element
  at a time; managed element types (AnsiString) are retained/released by the
  array runtime, so Add/Get copy values with normal assignment. }

interface

type
  generic TList<T> = class
    FItems: array of T;
    FCount: Integer;
    { Append a value, growing the backing array in chunks when full. }
    procedure Add(v: T);
    { Element at index i (0-based); no bounds check beyond the array's own. }
    function Get(i: Integer): T;
    { Overwrite the element at index i. }
    procedure Put(i: Integer; v: T);
    { Number of appended elements. }
    function Count: Integer;
    { Logical length reset to zero; storage is kept for reuse. }
    procedure Clear;
  end;

implementation

procedure TList.Add(v: T);
begin
  if Self.FCount >= Length(Self.FItems) then
    SetLength(Self.FItems, Length(Self.FItems) * 2 + 8);
  Self.FItems[Self.FCount] := v;
  Self.FCount := Self.FCount + 1;
end;

function TList.Get(i: Integer): T;
begin
  Result := Self.FItems[i];
end;

procedure TList.Put(i: Integer; v: T);
begin
  Self.FItems[i] := v;
end;

function TList.Count: Integer;
begin
  Result := Self.FCount;
end;

procedure TList.Clear;
begin
  Self.FCount := 0;
end;

end.
