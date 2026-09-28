program test_a_handled_exception_runs_its_destructor_once;
{ A handled exception object is DESTROYED, not just freed: fpc runs its
  destructor when the handler that owns it finishes, so anything the
  destructor releases (an owned list, a handle) is released too. pxx used to
  finalize and free the memory without calling Destroy -- allocs matched frees
  and every owned field leaked.

  Each object counts its own Destroy calls, and the table must read exactly 1
  for every shape: 0 is the old leak, 2 would be a re-raise destroyed by both
  the inner and the outer handler. (`raise E` of the object being handled is
  not a row: fpc 3.2.2 frees it at the inner handler's end and then faults in
  the outer one, so there is no oracle.) The census half raises an exception that
  owns a TStringList N times; with `keep` its destructor skips the list's Free,
  the deliberate leak the bound must catch. Expected output is fpc 3.2.2's. }
{$mode objfpc}
uses sysutils, classes;

type
  TV = class(Exception)
    Id: Integer;
    constructor Make(i: Integer);
    destructor Destroy; override;
  end;
  TOwner = class(Exception)
    Items: TStringList;
    constructor Make(i: Integer);
    destructor Destroy; override;
  end;

var
  Destroys: array[1..6] of Integer;
  keep: Boolean;

constructor TV.Make(i: Integer);
begin
  inherited Create('v');
  Id := i;
end;

destructor TV.Destroy;
begin
  Inc(Destroys[Id]);
  inherited;
end;

constructor TOwner.Make(i: Integer);
begin
  inherited Create('owner');
  Items := TStringList.Create;
  Items.Add('row ' + IntToStr(i));
  Items.Add('more ' + IntToStr(i * 7));
end;

destructor TOwner.Destroy;
begin
  if not keep then Items.Free;
  inherited;
end;

procedure BareReraise;
begin
  try
    raise TV.Make(3);
  except
    on E: TV do raise;
  end;
end;

procedure InFinally;
begin
  try
    try
      raise TV.Make(5);
    finally
      Destroys[6] := Destroys[6] + 0;
    end;
  except
    on E: TV do ;
  end;
end;

var i: Integer;
begin
  keep := (ParamCount > 0) and (ParamStr(1) = 'keep');
  try raise TV.Make(1); except on E: TV do ; end;
  try raise TV.Make(2); except end;
  try BareReraise; except on E: TV do ; end;
  InFinally;
  WriteLn('on-E ', Destroys[1]);
  WriteLn('bare-except ', Destroys[2]);
  WriteLn('bare-reraise ', Destroys[3]);
  WriteLn('nested-finally ', Destroys[5]);
  for i := 1 to 500 do
    try
      raise TOwner.Make(i);
    except
      on E: TOwner do
        if E.Items.Count <> 2 then WriteLn('bad count');
    end;
  WriteLn('owner loop done');
end.
