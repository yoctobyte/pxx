program test_dynarray_var_param_forwarded;
{ Forwarding a by-ref dynamic-array parameter onward as another by-ref
  argument. The arg path deliberately EXCLUDED a forwarded by-ref param, on the
  reasoning that its slot already holds &caller_slot — true of the slot, false
  of what IRLowerAddress hands back: IR_LEA's dyn-array arm derefs TWICE on a
  read, so the callee got the DATA pointer and read element 0 as a handle.
  A nested routine is a lambda-lifted call with the captures as by-ref params,
  so every nested write to a captured var-param dynarray had it too.
  bug-a-a-dynarray-var-param-written-from-a-nested-routine-is-discarded }
type
  TDA = array of Integer;
  TD2 = array of TDA;

procedure Sink(var d: TDA); begin SetLength(d, 3); d[0] := 8; end;
procedure Fwd(var d: TDA);  begin Sink(d); end;

procedure NestAssign(var d: TDA; const e: TDA);
  procedure Inner; begin d := e; end;
begin Inner; end;

procedure NestSet(var d: TDA);
  procedure Inner; begin SetLength(d, 3); d[1] := 7; end;
begin Inner; end;

procedure Nest2(var d: TD2);
  procedure Inner; begin SetLength(d, 2); SetLength(d[0], 2); d[0][1] := 4; end;
begin Inner; end;

procedure NestStr(var s: AnsiString);
  procedure Inner; begin s := s + 'x'; end;
begin Inner; end;

procedure NestLocal(var d: TDA);
var loc: TDA;
  procedure Inner; begin SetLength(loc, 4); loc[0] := 1; end;
begin Inner; d := loc; end;

var d, e: TDA; d2: TD2; s: AnsiString; ok: Integer;
begin
  ok := 0;
  { forwarding, no nesting at all — the general case }
  SetLength(d, 5); Fwd(d);
  if (Length(d) = 3) and (d[0] = 8) then Inc(ok);
  { a LOCAL forwarded the same way is the control: it always worked }
  SetLength(e, 5); Sink(e);
  if (Length(e) = 3) and (e[0] = 8) then Inc(ok);

  SetLength(d, 5); SetLength(e, 2); NestAssign(d, e);
  if Length(d) = 2 then Inc(ok);
  SetLength(d, 5); NestSet(d);
  if (Length(d) = 3) and (d[1] = 7) then Inc(ok);
  Nest2(d2);
  if (Length(d2) = 2) and (Length(d2[0]) = 2) and (d2[0][1] = 4) then Inc(ok);
  { a by-ref AnsiString captured the same way — that arm excludes forwarded
    ref params too and is CORRECT there, so this row pins it stays correct }
  s := 'a'; NestStr(s);
  if s = 'ax' then Inc(ok);
  { a nested routine writing an enclosing LOCAL, not a param }
  NestLocal(d);
  if (Length(d) = 4) and (d[0] = 1) then Inc(ok);
  WriteLn('total ok ', ok, ' / 7');
end.
