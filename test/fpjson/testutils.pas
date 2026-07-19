{ SPDX-License-Identifier: Zlib }
unit testutils;
{ pxx-native replacement for fcl-fpcunit's `testutils`.

  WHY THIS EXISTS, and why it is not a fork of the vendor source:

  FPC's testutils is the one unit in the fpcunit chain that is PLATFORM-INTERNALS code.
  Its GetMethodList does not use any public API — it hand-walks FPC's internal VMT:

      vmt := PVmt(aClass);
      methodTable := pMethodNameTable(vmt^.vMethodTable);
      pmr := @methodTable^.entries[0];

  `PVmt` / `vMethodTable` / `TMethodNameTable` are FPC System internals. pxx has its own
  VMT and its own RTTI blob and will never match FPC's byte layout — nor should it grow a
  fake one to satisfy one helper. So this unit supplies the platform half, which is
  exactly what that unit IS. Everything above it (fpcunit.pp itself, and every suite
  written against it) is used unmodified: fpcunit discovers its tests through
  `Self.MethodAddress(FName)`, which works.

  Same public surface as the FPC unit: FreeObjects, the two GetMethodList overloads, and
  TNoRefCountObject. Implemented over `rtti`, which reads the published-method table the
  compiler already emits. A pxx TClass value IS the RTTI blob pointer, so the class-level
  overload needs no instance.

  See feature-pascal-corpus-fpcunit / feature-rtti-method-reflection. }

interface

uses classes, rtti;

type
  { A TObject that implements IInterface without reference counting — the base fpcunit
    listeners derive from. _AddRef/_Release return -1, as in FPC. }
  TNoRefCountObject = class(TObject, IInterface)
  public
    function QueryInterface(constref IID: TGuid; out Obj): HResult;
    function _AddRef: Integer;
    function _Release: Integer;
  end;

{ Free every object in the list, then clear it. Nil slots are skipped. }
procedure FreeObjects(List: TFPList);

{ The PUBLISHED method names of a class, appended to AList. An overridden method appears
  once: the walk is own-then-parent and a name already present is not added again — the
  same dedup FPC's VMT walk does, and the reason it walked parent-ward at all. }
procedure GetMethodList(AObject: TObject; AList: TStrings); overload;
procedure GetMethodList(AClass: TClass; AList: TStrings); overload;

implementation

function TNoRefCountObject.QueryInterface(constref IID: TGuid; out Obj): HResult;
begin
  if GetInterface(IID, Obj) then
    QueryInterface := 0
  else
    QueryInterface := HResult($80004002);   { E_NOINTERFACE }
end;

function TNoRefCountObject._AddRef: Integer;
begin
  _AddRef := -1;                            { no reference counting }
end;

function TNoRefCountObject._Release: Integer;
begin
  _Release := -1;
end;

procedure FreeObjects(List: TFPList);
var
  i: Integer;
  o: TObject;
begin
  if List = nil then Exit;
  for i := 0 to List.Count - 1 do
  begin
    o := TObject(List[i]);
    if o <> nil then o.Free;
  end;
  List.Clear;
end;

procedure GetMethodList(AClass: TClass; AList: TStrings);
var
  i, n: Integer;
  nm: string;
begin
  if (AClass = nil) or (AList = nil) then Exit;
  n := ClassPublishedMethodCount(AClass);
  for i := 0 to n - 1 do
  begin
    nm := ClassPublishedMethodName(AClass, i);
    { own methods come first, so a later (inherited) entry of the same name is the
      one that was overridden — keep the first, drop the duplicate }
    if (nm <> '') and (AList.IndexOf(nm) < 0) then
      AList.Add(nm);
  end;
end;

procedure GetMethodList(AObject: TObject; AList: TStrings);
var
  i, n: Integer;
  nm: string;
begin
  { Reads the instance's own blob rather than casting its class reference: a TClass
    CAST does not parse yet (bug-pascal-builtin-pointer-type-cast), and the two walks
    are the same one anyway. }
  if (AObject = nil) or (AList = nil) then Exit;
  n := PublishedMethodCount(AObject);
  for i := 0 to n - 1 do
  begin
    nm := PublishedMethodName(AObject, i);
    if (nm <> '') and (AList.IndexOf(nm) < 0) then
      AList.Add(nm);
  end;
end;

end.
