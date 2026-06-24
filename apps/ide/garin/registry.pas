unit registry;

{ garin core — component registry enumeration. Render-agnostic: walks the
  compiler-emitted RTTI registry (__rttireg, via lib/rtl/typinfo) and reports the
  registered classes that descend from a named ancestor. Knows nothing about GTK,
  ANSI, or any concrete widget — the caller (eliah, ilja, ...) decides which
  ancestor names mean "component" / "visual" for its world.

  A component, in Eliah's model, is any registered class descending from
  TComponent with published RTTI; a visual one additionally descends from
  TControl. Both of those are PCL names, so the policy lives in the face, not
  here — this unit only answers "does class X descend from a class named A?" and
  "list every registered class descending from A". }

interface

uses typinfo;

type
  TRegEntry = record
    Name: AnsiString;
    Cls:  PClassRTTI;
  end;
  TRegEntryArr = array of TRegEntry;

{ True if cls, or any ancestor reachable via ParentRTTI, is named ancestorName.
  A class is considered to descend from itself. nil cls -> False. }
function ClassDescendsFrom(cls: PClassRTTI; const ancestorName: AnsiString): Boolean;

{ Every class in the RTTI registry that descends from ancestorName (excluding the
  ancestor itself unless includeSelf). Order follows the registry. }
function EnumDescendants(const ancestorName: AnsiString; includeSelf: Boolean): TRegEntryArr;

{ Convenience: total number of registered classes (any kind). }
function RegisteredClassCount: Integer;

implementation

function ClassDescendsFrom(cls: PClassRTTI; const ancestorName: AnsiString): Boolean;
var cur: PClassRTTI;
begin
  ClassDescendsFrom := False;
  cur := cls;
  while cur <> nil do
  begin
    if GetClassName(cur) = ancestorName then
    begin
      ClassDescendsFrom := True;
      Exit;
    end;
    cur := PClassRTTI(cur^.ParentRTTI);
  end;
end;

function RegisteredClassCount: Integer;
var reg: PRegistry;
begin
  RegisteredClassCount := 0;
  reg := __rttireg();
  if reg = nil then Exit;
  RegisteredClassCount := Integer(reg^.Count);
end;

function EnumDescendants(const ancestorName: AnsiString; includeSelf: Boolean): TRegEntryArr;
var
  reg: PRegistry;
  entries: PRTTIEntry;
  i, n: Integer;
  cls: PClassRTTI;
  nm: AnsiString;
  res: TRegEntryArr;
begin
  SetLength(res, 0);
  n := 0;
  reg := __rttireg();
  if reg <> nil then
  begin
    entries := @reg^.Dummy;
    for i := 0 to Integer(reg^.Count) - 1 do
    begin
      cls := entries[i].RTTIPtr;
      if cls = nil then Continue;
      if not ClassDescendsFrom(cls, ancestorName) then Continue;
      nm := GetClassName(cls);
      if (not includeSelf) and (nm = ancestorName) then Continue;
      SetLength(res, n + 1);
      res[n].Name := nm;
      res[n].Cls := cls;
      n := n + 1;
    end;
  end;
  EnumDescendants := res;
end;

end.
