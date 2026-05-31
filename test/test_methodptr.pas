program test_methodptr;
{ @obj.method builds a TMethod: Code = method address, Data = instance. }
type
  TMethod = record
    Code: Pointer;
    Data: Pointer;
  end;
  THandler = class
    n: Integer;
    procedure Go(Sender: TObject);
  end;
procedure THandler.Go(Sender: TObject);
begin
  Self.n := 1;
end;
var
  h: THandler;
  m: TMethod;
  hp: Pointer;
begin
  h := THandler.Create;
  m := @h.Go;
  hp := h;
  if m.Code <> nil then writeln('code set') else writeln('code NIL');
  if m.Data = hp then writeln('data ok') else writeln('data BAD');
end.
