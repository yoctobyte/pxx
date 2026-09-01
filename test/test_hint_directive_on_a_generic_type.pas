program test_hint_directive_on_a_generic_type;
{ A hint directive on a GENERIC type declaration. The non-generic path has gone
  through SkipHintDirectives since it was written; the template capture in
  pasparser_generic.inc scans the token array itself and had no equivalent, so
  every one of these was `expected 'begin' before 'deprecated'`.

  Both capture terminators are covered, because only one of them was safe and
  reasoning about it got that wrong:
    - the `end`-counted body (TG*, TRec*) -- stopped ON the directive;
    - the BODYLESS form (TBodyless*) -- its "is the next token ';'" test failed,
      so the declaration was ruled to HAVE a body, and the depth loop had no
      `end` to find and swallowed the rest of the file.
  The second failed WORSE (`expected 'begin' before '.'`, blaming the last line
  of the program) which is why it is pinned here by shape and not by hope.

  All five directives are exercised because IsHintDirectiveName lists five and a
  test that only ever says `deprecated` cannot notice the list drifting.
  bug-p-a-hint-directive-on-a-generic-type-is-a-parse-error }
{$mode delphi}
type
  TGDeprMsg<T>  = class end deprecated 'use TOther';
  TGDepr<T>     = class end deprecated;
  TGPlat<T>     = class end platform;
  TGExp<T>      = class end experimental;
  TGLib<T>      = class end library;
  TGUnimp<T>    = class end unimplemented;
  TRecDepr<T>   = record x: T; end deprecated 'msg';
  TGTwo<T>      = class end deprecated platform;

  TBase = class end;
  TBodyless<T>      = class(TBase) deprecated;
  TBodylessAbs<T>   = class abstract(TBase) deprecated 'msg';
  TBodylessOf<T>    = class of TBase deprecated;
  TArrHint<T>       = array of T deprecated;

  { the no-hint forms must still work -- the fix advances a cursor, and a
    cursor that advances when it should not is the other way to break this }
  TPlain<T>     = class end;
  TPlainBl<T>   = class(TBase);
var
  a: TGDeprMsg<Integer>;
  b: TRecDepr<Integer>;
  c: TBodyless<Integer>;
  d: TPlain<Integer>;
  e: TArrHint<Integer>;
begin
  a := TGDeprMsg<Integer>.Create;
  b.x := 42;
  c := TBodyless<Integer>.Create;
  d := TPlain<Integer>.Create;
  SetLength(e, 2); e[1] := 7;
  if (a <> nil) and (b.x = 42) and (c <> nil) and (d <> nil) and (e[1] = 7) then
    WriteLn('ALL OK')
  else
    WriteLn('FAIL');
end.
