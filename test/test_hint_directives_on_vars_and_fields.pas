{ Hint directives -- deprecated / platform / experimental / unimplemented /
  library -- on VARIABLE declarations and on record and class FIELDS.

  They already worked on `type` and `const` declarations and on routine
  headers. On a var declaration pxx answered

      unknown type: deprecated

  because the var section's type loop kept calling ParseTypeKind until it hit a
  stop token, and a hint directive is a plain identifier, so it was read as a
  SECOND type name. `absolute` had needed the same stop for the same reason;
  the two now share IsHintDirectiveName / the same guard.

  Record fields and class fields have separate parsers and each needed its own
  skip.

  Behaviour is parse-and-ignore, like fpc's with hints off: the directive must
  not change what the declaration means. Every value below is asserted so a
  skip that swallowed something real would fail rather than merely compile. }
program test_hint_directives_on_vars_and_fields;

{$mode objfpc}

type
  TOld = Integer deprecated;              { already worked }

  TRec = record
    f: Integer deprecated;
    g: string platform;
    h: array[0..2] of Integer experimental;
    i: Integer;                           { no hint, after ones that have them }
  end;

  TCls = class
    f: Integer deprecated;
    g: string platform;
    i: Integer;
  end;

const
  KOld = 7 deprecated;                    { already worked }

var
  target: Integer;
  a: Integer deprecated;
  b: Integer platform;
  c: Integer experimental;
  d: Integer unimplemented;
  e: Integer deprecated 'use a instead';  { the optional message form }
  init: Integer = 5 deprecated;           { a hint AFTER an initialiser }
  over: Integer absolute target deprecated;  { …and after `absolute` }
  plain: Integer;                         { no hint, declared after ones with }
  t: TOld;
  r: TRec;
  o: TCls;
  deprecated: Integer;                    { still a legal IDENTIFIER, as in fpc }
  fails: Integer;

procedure Chk(const nm: string; got, want: Int64);
begin
  if got = want then WriteLn(nm, ' ok')
  else begin WriteLn(nm, ' FAIL got=', got, ' want=', want); Inc(fails); end;
end;

begin
  fails := 0;

  a := 1; b := 2; c := 3; d := 4; e := 5; plain := 6; t := 7;
  Chk('var.deprecated', a, 1);
  Chk('var.platform', b, 2);
  Chk('var.experimental', c, 3);
  Chk('var.unimplemented', d, 4);
  Chk('var.message', e, 5);
  Chk('var.plain-after', plain, 6);
  Chk('var.init', init, 5);
  Chk('type.alias', t, 7);
  Chk('const', KOld, 7);

  { `absolute` and a hint together -- the overlay must still be an overlay }
  target := 42;
  Chk('var.absolute', over, 42);

  { an identifier that happens to BE a directive name is still an identifier }
  deprecated := 9;
  Chk('ident.named-deprecated', deprecated, 9);

  r.f := 10; r.g := 'g'; r.h[1] := 11; r.i := 12;
  Chk('rec.deprecated', r.f, 10);
  Chk('rec.platform', Length(r.g), 1);
  Chk('rec.array', r.h[1], 11);
  Chk('rec.plain-after', r.i, 12);

  o := TCls.Create;
  o.f := 20; o.g := 'gg'; o.i := 21;
  Chk('cls.deprecated', o.f, 20);
  Chk('cls.platform', Length(o.g), 2);
  Chk('cls.plain-after', o.i, 21);
  o.Free;

  if fails = 0 then WriteLn('ALL OK') else WriteLn('FAILURES ', fails);
end.
