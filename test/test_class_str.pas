program test_class_str;

type
  TFoo = class
    FStr: string;
  end;

var
  obj: TFoo;
begin
  obj := TFoo.Create;
  obj.FStr := 'hello';
  writeln('FStr: ', obj.FStr);
end.
