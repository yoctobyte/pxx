unit rootmethunit;
{ TObject's root methods (Equals/GetHashCode/ToString) reached from inside a
  UNIT. Their default bodies live in the `builtin` unit, which the compiler pulls
  by pre-scanning for a dot-preceded `.Equals`/`.GetHashCode`/`.ToString` — and
  that pre-scan used to see only the PROGRAM's tokens. So the same call compiled
  in a program and failed with `"Equals": no such member on this record/class`
  here. rtl-generics' Generics.Defaults hits it at TEquals.&Class.
  bug-p-tobject-root-methods-are-invisible-inside-a-unit }
{$mode objfpc}
interface

type
  TNamed = class(TObject)
    Tag: LongInt;
    function Equals(Obj: TObject): Boolean; override;
    function ToString: AnsiString; override;
  end;

function EqRoot(constref L, R: TObject): Boolean;
function HashOf(o: TObject): PtrInt;
function TextOf(o: TObject): AnsiString;

implementation

function TNamed.Equals(Obj: TObject): Boolean;
begin
  Result := (Obj is TNamed) and (TNamed(Obj).Tag = Tag);
end;

function TNamed.ToString: AnsiString;
begin
  Result := 'TNamed#' + Chr(Ord('0') + Tag);
end;

{ the shape TEquals.&Class has: a constref TObject pair, virtual dispatch }
function EqRoot(constref L, R: TObject): Boolean;
begin
  if L <> nil then
    Exit(L.Equals(R))
  else
    Exit(R = nil);
end;

function HashOf(o: TObject): PtrInt;
begin
  Result := o.GetHashCode;
end;

function TextOf(o: TObject): AnsiString;
begin
  Result := o.ToString;
end;

end.
