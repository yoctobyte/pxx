{ feature-classes-tlist-notify-hook: TList.Notify virtual hook fires on
  add/remove so a descendant can react (the mechanism an owning list uses to
  free its objects). Self-checking: prints "total ok N / N". }
program test_tlist_notify;
uses classes;

type
  { observes the notifications into a trace string }
  TTracedList = class(TList)
  protected
    procedure Notify(Ptr: Pointer; Action: TListNotification); override;
  public
    Trace: string;
  end;

  { an owning list: frees the (heap Integer) it removes, proving lnDeleted fires
    at the right moments }
  PInt = ^Integer;
  TOwnList = class(TList)
  protected
    procedure Notify(Ptr: Pointer; Action: TListNotification); override;
  public
    Freed: Integer;
  end;

procedure TTracedList.Notify(Ptr: Pointer; Action: TListNotification);
begin
  if Action = lnAdded then Trace := Trace + 'A'
  else if Action = lnDeleted then Trace := Trace + 'D'
  else Trace := Trace + 'X';
end;

procedure TOwnList.Notify(Ptr: Pointer; Action: TListNotification);
begin
  if (Action = lnDeleted) and (Ptr <> nil) then
  begin
    Dispose(PInt(Ptr));
    Freed := Freed + 1;
  end;
end;

var
  tl: TTracedList;
  ol: TOwnList;
  p: PInt;
  i, pass, total: Integer;
begin
  pass := 0; total := 0;

  { 1. add fires lnAdded, delete/clear fire lnDeleted, in order }
  tl := TTracedList.Create;
  tl.Trace := '';
  tl.Add(Pointer(1)); tl.Add(Pointer(2)); tl.Add(Pointer(3));  { AAA }
  tl.Delete(0);                                                { D }
  tl.Insert(0, Pointer(9));                                    { A }
  tl.Clear;                                                    { DDD (3 left) }
  Inc(total); if tl.Trace = 'AAADADDD' then Inc(pass);

  { 2. owning list frees each removed element exactly once }
  ol := TOwnList.Create;
  ol.Freed := 0;
  for i := 1 to 5 do begin New(p); p^ := i; ol.Add(p); end;
  ol.Delete(0);      { frees 1 }
  ol.Clear;          { frees remaining 4 }
  Inc(total); if ol.Freed = 5 then Inc(pass);

  writeln('total ok ', pass, ' / ', total);
end.
