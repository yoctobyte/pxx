program openarr_slice;
{ Open-array parameters on wasm32, and the deref depth they share with dynamic
  array parameters. 27 refusal lines in compiler.pas, plus 6 of the 8 `Length
  of Pointer` ones — the two classes could not be tested apart, because every
  probe refused on Length/High before it reached the parameter.

  THE REFUSAL THIS REPLACED WAS STALE IN ITS REASON AND RIGHT IN ITS VERDICT.
  It said the dyn-array layout was not implemented; that landed in Phase 9a.
  The one-line fix its reason invites — treat the slot as a dyn-array handle —
  compiles, reports full coverage, and traps. What it missed is that the
  argument node differs per path, so the number of derefs does too:

    local dyn array            slot -> handle                    1
    var/out of a NAMED dyn     slot -> caller's slot -> handle   2
    by-value/const NAMED dyn   slot -> handle                    1
    open array, any mode       slot -> handle                    1

  The last row is the one that surprises: a `var` OPEN array is still one
  deref, because the caller emits IR_LEA (the handle) for it where a `var`
  parameter of a named dyn-array type emits IR_SLOTADDR (an address). Checked
  in the IR, not inferred — `IsRef` alone gets this wrong, and ArrLen is what
  separates the two. }
type TIA = array of Integer;

procedure SumOpen(const a: array of Integer);
var i, s: Integer;
begin
  s := 0;
  for i := 0 to High(a) do s := s + a[i];
  writeln('open  n=', Length(a), ' high=', High(a), ' sum=', s);
end;

{ by-value open array: the same one deref as const } 
procedure FirstOpen(a: array of Integer);
begin
  if Length(a) = 0 then writeln('byval n=0') 
  else writeln('byval n=', Length(a), ' a0=', a[0]);
end;

{ var open array: writes must reach the caller's storage } 
procedure BumpOpen(var a: array of Integer);
var i: Integer;
begin
  for i := 0 to High(a) do a[i] := a[i] + 100;
  writeln('var   n=', Length(a), ' a0=', a[0]);
end;

{ a NAMED dyn-array parameter is a different deref depth and must not regress } 
procedure SumNamed(const a: TIA);
var i, s: Integer;
begin
  s := 0;
  for i := 0 to High(a) do s := s + a[i];
  writeln('named n=', Length(a), ' sum=', s);
end;

procedure BumpNamed(var a: TIA);
begin a[0] := a[0] + 1000; writeln('namedvar n=', Length(a), ' a0=', a[0]); end;

{ managed elements through an open array } 
procedure JoinOpen(const a: array of string);
var i: Integer; r: string;
begin
  r := '';
  for i := 0 to High(a) do r := r + a[i] + '.';
  writeln('strs  n=', Length(a), ' r=', r);
end;

type
  TSA = array of string;

var
  d: TIA;
  ds: TSA;
  st: array[0..2] of Integer;
  i: Integer;
begin
  { the four ARGUMENT paths, which differ in what the caller materialises } 
  SumOpen([1, 2, 3, 4]);                 { array constructor }
  SetLength(d, 3);
  for i := 0 to 2 do d[i] := (i + 1) * 10;
  SumOpen(d);                            { a dynamic array }
  st[0] := 5; st[1] := 6; st[2] := 7;
  SumOpen(st);                           { a static array, copied to a headered one }
  SumOpen([]);                           { empty }

  FirstOpen(d);
  FirstOpen([42]);

  BumpOpen(d);
  writeln('caller sees a0=', d[0], ' a2=', d[2]);

  { the named-type modes, the other deref depth } 
  SumNamed(d);
  BumpNamed(d);
  writeln('caller sees a0=', d[0]);

  { Managed elements, fed from a dynamic array rather than a `[...]`
    constructor. The constructor form is NOT here on purpose: it hits a
    frontend mistyping that is not this backend's to fix — see
    bug-a-open-array-of-string-arg-spilled-through-a-managed-string-temp. }
  SetLength(ds, 3);
  ds[0] := 'x'; ds[1] := 'yy'; ds[2] := 'zzz';
  JoinOpen(ds);
  writeln('done');
end.
