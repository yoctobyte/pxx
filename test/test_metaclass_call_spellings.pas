program test_metaclass_call_spellings;
{ A call whose RESULT is a metaclass (`class of T`) must be usable as a receiver
  in all the ways a call can be spelled. NodeMetaclassCi's "function RESULT" row
  tested only AN_CALL, but a call is BUILT as AN_CALL and rewritten in place when
  dispatch is not static: AN_CLASS_VIRTUAL_CALL (virtual class method),
  AN_VIRTUAL_CALL (virtual instance method), AN_INTF_CALL (interface method).
  The two virtual spellings died as "a pointer has no members"; the interface one
  silently yielded the metaclass POINTER because its arm exited instead of
  continuing the selector loop. Every row below is 42 under fpc 3.2.2.
  bug-a-nodemetaclassci-does-not-know-a-virtual-class-method-call }
{$MODE OBJFPC}
type
  TSvc = class
    class function Lookup(n: Integer): Integer; static;
  end;
  TSvcClass = class of TSvc;

  IGiver = interface
    function IGet: TSvcClass;
  end;

  TFactory = class(TInterfacedObject, IGiver)
    class function CNonVirt: TSvcClass;
    class function CVirt: TSvcClass; virtual;
    function INonVirt: TSvcClass;
    function IVirt: TSvcClass; virtual;
    function IGet: TSvcClass;
  end;
  TFactoryClass = class of TFactory;

class function TSvc.Lookup(n: Integer): Integer; begin Lookup := n * 2; end;
class function TFactory.CNonVirt: TSvcClass;     begin CNonVirt := TSvc; end;
class function TFactory.CVirt: TSvcClass;        begin CVirt := TSvc; end;
function TFactory.INonVirt: TSvcClass;           begin INonVirt := TSvc; end;
function TFactory.IVirt: TSvcClass;              begin IVirt := TSvc; end;
function TFactory.IGet: TSvcClass;               begin IGet := TSvc; end;

function PlainFn: TSvcClass; begin PlainFn := TSvc; end;

var
  f: TFactory;
  g: IGiver;
  cf: TFactoryClass;
begin
  f := TFactory.Create;
  g := f;
  cf := TFactory;
  { the two that always worked -- controls, so a fix cannot trade one for another }
  Writeln('plain fn      : ', PlainFn.Lookup(21));
  Writeln('class nonvirt : ', cf.CNonVirt.Lookup(21));
  Writeln('inst  nonvirt : ', f.INonVirt.Lookup(21));
  { the three that did not }
  Writeln('class VIRTUAL : ', cf.CVirt.Lookup(21));
  Writeln('inst  VIRTUAL : ', f.IVirt.Lookup(21));
  Writeln('interface     : ', g.IGet.Lookup(21));
end.
