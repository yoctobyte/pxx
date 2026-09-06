{ A class REFERENCE in `array of const` is vtClass (8), not vtPointer (5), and
  the QWord arm is vtQWord (17), not vtInt64 (16).

  Both defects have the same shape: the tag is picked from the element's static
  TYPE KIND, and a metaclass is a tyPointer while a QWord is "a 64-bit int".
  So each fell into a neighbouring arm that is right about the WIDTH and wrong
  about the READ -- VClass came back as a bare address with no members, and the
  QWord came back through a PInt64.

  The QWord row deliberately carries a value ABOVE High(Int64): 1234 reads the
  same through either pointer, so a small probe cannot tell the fixed compiler
  from the broken one. -2 is what the old path prints.
  feature-pascal-corpus-fpc-testsuite, tarray2 row }
{$mode objfpc}
type
  TFoo = class
  end;
  TFooClass = class of TFoo;

procedure Tags(Args: array of const);
var i: Integer;
begin
  for i := 0 to High(Args) do
  begin
    Write('[', i, '] vtype=', Args[i].VType);
    case Args[i].VType of
      vtClass:  Writeln(' class=', Args[i].VClass.ClassName);
      vtObject: Writeln(' object=', Args[i].VObject.ClassName);
      vtPChar:  Writeln(' pchar=', Args[i].VPChar);
      vtQWord:  Writeln(' qword=', Args[i].VQWord^);
      vtInt64:  Writeln(' int64=', Args[i].VInt64^);
    else
      Writeln;
    end;
  end;
end;

var
  c: TClass;
  fc: TFooClass;
  o: TObject;
  f: TFoo;
  p: Pointer;
  pc: PChar;
  q: QWord;
  n: Int64;
begin
  c := TObject;
  fc := TFoo;
  o := TObject.Create;
  f := TFoo.Create;
  p := nil;
  pc := 'text';
  q := High(QWord) - 1;
  n := -1234567890123;
  Tags([TObject]);
  Tags([TFoo]);
  Tags([c]);
  Tags([fc]);
  Tags([o]);
  Tags([f]);
  Tags([p]);
  Tags([pc]);
  Tags([q]);
  Tags([n]);
  f.Free;
  o.Free;
end.
