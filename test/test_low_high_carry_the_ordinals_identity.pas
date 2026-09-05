{ `Low`/`High` answer the right ORDINAL and forget WHICH ordinal it is.

  An enum value in this compiler is a storage kind PLUS an identity, and a
  Char's kind is the identity. Every row below had the right NUMBER before this
  fix and printed it as an integer: `Low(a)` for `var a: D` gave 0 where fpc
  gives mon, and `Low(s)` for `var s: set of 'c'..'k'` gave 99 where fpc gives
  c. A bound that is right and prints wrong is the shape a value assertion on
  Ord() cannot see -- row K is here to say that explicitly, since it passed
  throughout.

  THE TWO SPELLINGS ARE THE POINT. `Low(D)` over the TYPE NAME was correct the
  whole time, because TryFoldHighLowType stamps the enum identity on the node it
  builds; `Low(a)` over a VARIABLE went through TryOrdinalVarBound, which had no
  channel for the answer at all. One intrinsic, one question, two spellings, and
  only one of them could carry the reply. Rows 1-2 and 3-4 are that pair, and
  rows A-D pair with F the same way for a set.

  TWO CAUSES, and they are not the same defect wearing two hats:

  (1) The SET rows were not a lost element kind. `set of 'c'..'k'` left
  LastTypeIsSub set from parsing its ELEMENT, and AllocVar copied it onto the
  SET symbol -- so the set variable was flagged as a subrange with the element's
  bounds, and TryOrdinalVarBound's subrange arm (which runs first) answered 99
  typed with the SET's own kind. SymSetElemTk was tyChar the entire time.
  Row E is the measurement that separates those two explanations: `for c in s`
  reads that same field and was green throughout.

  (2) The ENUM rows were a missing channel: TryOrdinalVarBound reported tkOut
  and nothing else, so the identity had nowhere to travel.

  Row G is a named SET TYPE, which answered `undefined variable (TS)` outright
  -- the third spelling of the same question, and the one with no arm at all.
  Row H takes it through a CONST expression, which is a different evaluator
  (TryConstHighLowValue) and so a genuinely second reader, not a second phrasing.

  Row I is the CONTROL that must not move: an integer subrange prints as an
  integer either way, so it cannot distinguish a fix from a no-op and is here
  only to catch a widening that breaks it. Row J is the same for a Boolean set,
  whose element kind was never dropped.

  Every row is fpc 3.2.2's own output, byte for byte. }
program test_low_high_carry_the_ordinals_identity;

type
  D    = (mon, tue, wed);
  TD   = D;
  TCS  = set of 'c'..'k';
  TIS  = set of 1..10;
  TES  = set of D;
  TBS  = set of Boolean;
  CS   = 'c'..'k';

const
  KLO = Low(TCS);
  KHI = High(TCS);
  ELO = Low(TES);
  EHI = High(TES);

var
  a  : D;
  b  : TD;
  s  : set of 'c'..'k';
  t  : set of CS;
  u  : set of D;
  bs : TBS;
  i  : 1..10;
  c  : Char;
  n  : Integer;

begin
  writeln('1 enum type name   : ', Low(D),  ' ', High(D));
  writeln('2 enum alias name  : ', Low(TD), ' ', High(TD));
  writeln('3 enum variable    : ', Low(a),  ' ', High(a));
  writeln('4 enum alias var   : ', Low(b),  ' ', High(b));

  writeln('A set of charsub   : ', Low(s),  ' ', High(s));
  writeln('B set of named sub : ', Low(t),  ' ', High(t));
  writeln('C set of enum      : ', Low(u),  ' ', High(u));
  writeln('D set of Boolean   : ', Low(bs), ' ', High(bs));

  s := ['d', 'f'];
  write('E for-in was green :');
  for c in s do write(' ', c);
  writeln;

  writeln('F set type charsub : ', Low(TCS), ' ', High(TCS));
  writeln('G set type enum    : ', Low(TES), ' ', High(TES));
  writeln('H const from type  : ', KLO, ' ', KHI, ' ', ELO, ' ', EHI);

  writeln('I CONTROL int sub  : ', Low(i),  ' ', High(i));
  writeln('J CONTROL set int  : ', Low(TIS), ' ', High(TIS));

  n := 0;
  for c := Low(s) to High(s) do Inc(n);
  writeln('K ordinals unmoved : ', n, ' ', Ord(Low(u)), ' ', Ord(High(u)));
end.
