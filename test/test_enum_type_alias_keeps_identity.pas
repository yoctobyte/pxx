{ `type TDays = D` where D is an enum: the ALIAS must carry the enum's identity,
  not just its integer storage kind.

  An enum in pxx is an integer kind PLUS an id. Every alias carried the kind and
  dropped the id, so a variable declared through the alias printed its ORDINAL
  where fpc prints the member name -- `1`, not `tue`. `case` kept working the
  whole time, because members resolve globally rather than through the
  variable's type, and that is what hid it: the type looked fine everywhere you
  would normally check.

  RegisterGeneralAlias already carried five such facts -- a frozen string's
  capacity, a subrange's bounds, a file's element width, a managed string's
  element width, a pointer's target -- each written as its own guarded block
  saying "same window and same reason". The enum id is the sixth and it was
  never written. That is the omission class: reading the five copies against
  each other cannot find it, because they agree.

  The rows walk every place the identity has to arrive: a variable, a chain of
  aliases, a record field, a value parameter, a var parameter, a function
  result, an array element, and the ordinal operators.

  Row `set alias` is the NEGATIVE CONTROL and it is the load-bearing one.
  `set of C` leaves the ELEMENT's enum id in LastTypeEnumId, so an unguarded
  capture would stamp a SET alias with its element's identity and try to print
  a bitset as a member name. The guard is EnumKindMatches -- the predicate seven
  other sites already use for exactly this -- and this row is what fails if it
  is dropped for a bare `LastTypeEnumId >= 0`.

  Every row is fpc 3.2.2's own output, byte for byte. }
program test_enum_type_alias_keeps_identity;

type
  D      = (mon, tue, wed, thu);
  TDays  = D;
  TChain = TDays;
  TSet   = set of D;
  TWork  = tue..thu;
  TRec   = record
    day : TDays;
  end;
  TArr   = array[0..2] of TDays;

var
  a  : TDays;
  c  : TChain;
  r  : TRec;
  arr: TArr;
  s  : TSet;
  w  : TWork;
  i  : Integer;

function PickThrough(x: TDays): TDays;
begin
  PickThrough := x;
end;

procedure Bump(var x: TDays);
begin
  x := Succ(x);
end;

begin
  a := tue;
  writeln('variable      : ', a);

  c := wed;
  writeln('alias chain   : ', c);

  r.day := thu;
  writeln('record field  : ', r.day);

  writeln('value param   : ', PickThrough(mon));

  a := mon;
  Bump(a);
  writeln('var param     : ', a);

  for i := 0 to 2 do
    arr[i] := D(i);
  writeln('array element : ', arr[0], ' ', arr[1], ' ', arr[2]);

  writeln('ord / succ    : ', Ord(wed), ' ', Succ(mon), ' ', Pred(thu));
  writeln('low / high    : ', Low(TDays), ' ', High(TDays));

  { The ticket's own suggested positive control: a NAMED subrange OF an enum
    goes through the AliasIsSub arm, not the enum arm, and had the same hole --
    while the INLINE spelling `var v: tue..thu` printed the member name all
    along, because there LastTypeEnumId reaches the symbol directly. The
    asymmetry is what says the fix is at the alias boundary and not in the
    formatter. }
  w := thu;
  writeln('named subrange: ', w);

  a := wed;
  case a of
    mon: writeln('case          : M');
    wed: writeln('case          : W');
  else
    writeln('case          : ?');
  end;

  s := [mon, wed];
  write('CONTROL set alias:');
  for a := mon to thu do
    if a in s then write(' ', a);
  writeln;
end.
