program test_a_specialization_reports_its_canonical_class_name;
{$mode objfpc}{$H+}
{ A SPECIALIZATION'S ClassName IS THE SPECIALIZATION'S NAME, NOT THE ALIAS'S.

  `TIntBox = specialize TBox<Integer>` declares an ALIAS for a specialization.
  pxx implements one by splicing the template's tokens out under the alias's
  name, so the class was REGISTERED as `TIntBox` and reported that way. That is
  wrong twice over, and the second reason is the one that makes it a defect on
  our own terms rather than FPC parity:

    * it is not the language's answer -- fpc 3.2.2 and Delphi both report
      `Template<Args>`;
    * with TWO aliases of one specialization only the FIRST mints, the second
      becoming a UClass alias of it, so ClassName answered whichever name was
      declared first. An observable that moves when two unrelated declarations
      swap places is not reporting a property of the TYPE at all.

  `alias-a` and `alias-b` are that pair, and they are the rows that fail at HEAD
  in the interesting way: both printed `TIntBox`. The canonical name mentions
  NEITHER alias, which is the whole point -- there is no declaration order it
  could be reporting.

  `plain` and `derived` are the controls in the other direction: an ordinary
  class, and a real class DESCENDING from an inline specialization, must keep
  their own names. Without them a change that canonicalised every class would
  pass every row above.

  DELIBERATELY NOT HERE, both measured rather than assumed:

    * `PtrInt` / `SizeInt`. fpc resolves them to the pointer-width integer --
      System.Int64 on x86-64, System.LongInt on i386 -- so its answer is
      TARGET-DEPENDENT. A row asserting System.Int64 would pass on the host and
      fail on i386, which is the native-only defect class this repo keeps
      getting bitten by. We keep the written name; the divergence is recorded on
      the ticket, not hidden in a fixture that cannot travel.
    * `TAliasRec = TMyRec` as an argument. fpc answers `TMyRec`; we answer
      `TAliasRec`, because a RECORD alias -- unlike a class alias -- is not
      registered in the UClass alias table, so nothing here can resolve it. A
      separate gap, banked on the ticket rather than half-plumbed from the RTTI
      emitter.

  Oracle: fpc 3.2.2 -Mobjfpc -Sh.
  bug-p-a-nested-specialization-is-named-by-its-alias-so-one-name-serves-every-outer-specialization }
type
  TCls = class end;
  TMyEnum = (ma, mb);
  TSub = 0..7;
  TMyInt = Integer;

  generic TBox<T> = class F: T; end;
  generic TPair<K, V> = class F: K; G: V; end;

  { the pair: two aliases, ONE specialization }
  TIntBox  = specialize TBox<Integer>;
  TIntBox2 = specialize TBox<Integer>;

  { the builtin folds fpc performs, and the spellings it keeps }
  BLong  = specialize TBox<LongInt>;
  BMyInt = specialize TBox<TMyInt>;
  BStr   = specialize TBox<string>;
  BAnsi  = specialize TBox<AnsiString>;
  BShort = specialize TBox<ShortString>;
  BWide  = specialize TBox<WideString>;
  BCard  = specialize TBox<Cardinal>;
  BByte  = specialize TBox<Byte>;
  BI64   = specialize TBox<Int64>;
  BDbl   = specialize TBox<Double>;
  BBool  = specialize TBox<Boolean>;
  BChar  = specialize TBox<Char>;

  { user types keep their own name, under the declaring unit }
  BCls   = specialize TBox<TCls>;
  BEnum  = specialize TBox<TMyEnum>;
  BSub   = specialize TBox<TSub>;

  { recursive: a specialization used as an argument is qualified }
  BNest  = specialize TBox<specialize TBox<Integer>>;
  BPair  = specialize TPair<Integer, string>;

  { controls }
  TDerived = class(specialize TBox<Integer>) end;

var p: TCls;
begin
  Write('alias-a  '); WriteLn(TIntBox.Create.ClassName);
  Write('alias-b  '); WriteLn(TIntBox2.Create.ClassName);
  Write('long     '); WriteLn(BLong.Create.ClassName);
  Write('myint    '); WriteLn(BMyInt.Create.ClassName);
  Write('str      '); WriteLn(BStr.Create.ClassName);
  Write('ansi     '); WriteLn(BAnsi.Create.ClassName);
  Write('short    '); WriteLn(BShort.Create.ClassName);
  Write('wide     '); WriteLn(BWide.Create.ClassName);
  Write('card     '); WriteLn(BCard.Create.ClassName);
  Write('byte     '); WriteLn(BByte.Create.ClassName);
  Write('int64    '); WriteLn(BI64.Create.ClassName);
  Write('double   '); WriteLn(BDbl.Create.ClassName);
  Write('bool     '); WriteLn(BBool.Create.ClassName);
  Write('char     '); WriteLn(BChar.Create.ClassName);
  Write('cls      '); WriteLn(BCls.Create.ClassName);
  Write('enum     '); WriteLn(BEnum.Create.ClassName);
  Write('sub      '); WriteLn(BSub.Create.ClassName);
  Write('nested   '); WriteLn(BNest.Create.ClassName);
  Write('pair     '); WriteLn(BPair.Create.ClassName);
  p := TCls.Create;
  Write('plain    '); WriteLn(p.ClassName);
  Write('derived  '); WriteLn(TDerived.Create.ClassName);
end.
