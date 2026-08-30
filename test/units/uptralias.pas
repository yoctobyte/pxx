{ Companion unit for test_pointer_alias_identity.pas — the CROSS-UNIT arm.

  Exports both spellings of the same parameter type so the caller can vary the
  one factor that matters: a formal typed by a `Pointer` ALIAS against a formal
  typed by literal `Pointer`. The alias arm is the one that regressed; the plain
  arm is the control that stayed green throughout and proves the caller's
  argument was always acceptable.
  bug-p-a-pointer-type-alias-rejects-a-class-instance-that-plain-pointer-accepts }
unit uptralias;
interface

type
  TRecX  = record a: Integer; b: Integer; end;
  PRecX  = ^TRecX;
  SslPtr = Pointer;      { the Synapse spelling that filed the ticket }
  SslPtr2 = SslPtr;      { alias OF an alias — the erasure used to propagate }
  PRecA  = PRecX;        { alias of a TYPED pointer: pointee must survive }

function TakesAlias(p: SslPtr): Integer;
function TakesAlias2(p: SslPtr2): Integer;
function TakesPlain(p: Pointer): Integer;
function SumVia(p: PRecA): Integer;

implementation

function TakesAlias(p: SslPtr): Integer;
begin if p = nil then TakesAlias := 0 else TakesAlias := 7411; end;

function TakesAlias2(p: SslPtr2): Integer;
begin if p = nil then TakesAlias2 := 0 else TakesAlias2 := 7422; end;

function TakesPlain(p: Pointer): Integer;
begin if p = nil then TakesPlain := 0 else TakesPlain := 7433; end;

{ Reads the pointee THROUGH the alias. If the alias erases its element this
  does not compile at all ("a pointer has no members"), which is why the
  cross-unit deref arm is here and not only in the main program. }
function SumVia(p: PRecA): Integer;
begin SumVia := p^.a + p^.b; end;

end.
