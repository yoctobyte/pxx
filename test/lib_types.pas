{ types unit smoke: geometry records, helpers, TDuplicates, TValueRelationship. }
program lib_types;
uses types;
var p: TPoint; r: TRect; d: TDuplicates;
begin
  p := Point(3, 4);
  r := Rect(0, 0, 10, 20);
  d := dupIgnore;
  writeln(p.X, ' ', p.Y, ' ', RectWidth(r), ' ', RectHeight(r), ' ', Ord(d), ' ', Ord(GreaterThanValue));
end.
