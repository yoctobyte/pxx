{ A metaclass ARRAY ELEMENT is a real receiver (b328).

  `Map[0].Tag` (a virtual class method through an element of an array of class
  references) fell through the metaclass-receiver detection — which only knew
  AN_IDENT variables and inline casts — into the plain-pointer member paths,
  and returned an integer-looking garbage value. SILENT. Assigning the element
  to a `class of T` variable first worked, so the stored value was fine; only
  the receiver handling was wrong. The array symbol carries the element class
  in PtrElemTk/PtrElemRec, exactly like a metaclass variable. fpjson's factory
  (`TJSONNullClass(DefaultJSONInstanceTypes[jitNull]).Create`) spells the same
  shape with a cast, which already worked; the bare element now does too.
  Verified against FPC. }
program test_metaclass_array_element_b328;
{$mode objfpc}{$h+}

type
  TBase = class
    class function Tag: string; virtual;
    constructor Create; virtual;
  end;
  TBaseClass = class of TBase;
  TA = class(TBase)
    class function Tag: string; override;
    constructor Create; override;
  end;

var
  MadeBy: string;

class function TBase.Tag: string; begin Tag := 'base'; end;
constructor TBase.Create; begin MadeBy := 'base'; end;
class function TA.Tag: string; begin Tag := 'A'; end;
constructor TA.Create; begin MadeBy := 'A'; end;

const
  Map: array[0..1] of TBaseClass = (TA, TBase);
var
  c: TBaseClass;
  o: TBase;
begin
  c := Map[0];
  Writeln('via var:   ', c.Tag);
  Writeln('via elem0: ', Map[0].Tag);        { virtual class method }
  Writeln('via elem1: ', Map[1].Tag);
  Writeln('name:      ', Map[0].ClassName);  { class-ref op (worked before, must keep) }
  o := Map[0].Create;                        { virtual ctor through the element }
  Writeln('made:      ', MadeBy, ' inst=', o.ClassName);
end.
