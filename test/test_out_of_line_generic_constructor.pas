program test_out_of_line_generic_constructor;
{ An out-of-line method implementation between a mode-Delphi template and a use
  of its specialization. DGenDeclAnchor walks forward from the template to the
  use to place the minted alias, and ends the type section at a bare routine
  HEADING at depth 0 -- but its heading list held only tkProcedure/tkFunction.
  `constructor` and `destructor` are SOFT keywords here (tkIdent, compared by
  text), so there is no tkConstructor for a reader to notice missing, and the
  walk ran straight through the constructor and its body and anchored the alias
  after the use: `unknown type: TFoo$Integer`.

  A `procedure` between the two was unaffected, which is what made this look
  like a specialization bug instead of a four-entry list with two entries.
  Both soft keywords are covered here for that reason, and a plain `procedure`
  stays in the file as the control that was already passing.
  bug-p-an-out-of-line-generic-constructor-breaks-specialization }
{$MODE DELPHI}
type
  TCtor<T> = class
    V: Integer;
    constructor Create;
  end;

  TDtor<T> = class
    destructor Destroy; override;
  end;

  TProc<T> = class          { the control: this arm always worked }
    procedure P;
  end;

constructor TCtor<T>.Create;
begin
  inherited Create;
  V := 7;
end;

destructor TDtor<T>.Destroy;
begin
  inherited Destroy;
end;

procedure TProc<T>.P;
begin
end;

var
  c: TCtor<Integer>;
  d: TDtor<Integer>;
  p: TProc<Integer>;
begin
  c := TCtor<Integer>.Create;
  d := TDtor<Integer>.Create;
  p := TProc<Integer>.Create;
  if (c <> nil) and (c.V = 7) and (d <> nil) and (p <> nil) then
    WriteLn('ALL OK')
  else
    WriteLn('FAIL');
  d.Free; p.Free; c.Free;
end.
