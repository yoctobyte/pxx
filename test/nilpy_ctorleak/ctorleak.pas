{ SPDX-License-Identifier: Zlib }
unit ctorleak;
{$MODE PXX}
{ For test/test_nilpy_an_object_from_a_named_constructor_is_freed.npy: a class
  built through a constructor NOT named Create, returned by a unit function
  directly and through a local that sets a field first. It counts its own
  destructions, so the test can read how many are still alive. }
interface
type
  TBase = class
  public
    F: Integer;
    constructor Create;
    constructor Adopt(h: Integer);
  end;
  TSub = class(TBase)
  public
    destructor Destroy; override;
  end;
function ViaAdopt(x: TBase): TSub;
function ViaLocal(x: TBase): TSub;
function made: Integer;
function gone: Integer;
implementation
var
  NMade, NGone: Integer;
constructor TBase.Create; begin F := 0; end;
constructor TBase.Adopt(h: Integer); begin F := h; NMade := NMade + 1; end;
destructor TSub.Destroy; begin NGone := NGone + 1; inherited Destroy; end;
function ViaAdopt(x: TBase): TSub;
begin
  ViaAdopt := TSub.Adopt(1);
end;
function ViaLocal(x: TBase): TSub;
var r: TSub;
begin
  r := TSub.Adopt(2);
  r.F := 3;
  ViaLocal := r;
end;
function made: Integer; begin made := NMade; end;
function gone: Integer; begin gone := NGone; end;
end.
