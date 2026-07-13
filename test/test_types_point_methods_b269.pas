{ TPoint/TRect in lib/rtl/types.pas are ADVANCED RECORDS: they carry methods.
  Regression for the whole path -- record methods reached through a UNIT, with
  overloads, a by-ref Self that really mutates the receiver, and a record-typed
  result. }
program b269_types_point_methods;
uses types;
var
  p, q: TPoint;
  r: TRect;
  s: TSize;
begin
  p.SetLocation(3, 4);
  writeln('p=', p.X, ',', p.Y);

  q.SetLocation(p);          { overload on a TPoint }
  writeln('q=', q.X, ',', q.Y);

  p.Offset(10, 20);          { by-ref Self must mutate p itself }
  writeln('off=', p.X, ',', p.Y);

  q.Offset(p);               { overloaded Offset }
  writeln('offp=', q.X, ',', q.Y);

  writeln('zero=', p.IsZero);
  q.SetLocation(0, 0);
  writeln('zero0=', q.IsZero);

  q := p.Add(Point(1, 2));   { record-typed result }
  writeln('add=', q.X, ',', q.Y);
  q := q.Subtract(Point(4, 6));
  writeln('sub=', q.X, ',', q.Y);

  r.Left := 0; r.Top := 0; r.Right := 20; r.Bottom := 10;
  writeln('rect=', r.GetWidth, 'x', r.GetHeight, ' w=', r.Width, ' h=', r.Height);
  writeln('empty=', r.IsEmpty);
  writeln('in=', r.Contains(Point(5, 5)), ' out=', r.Contains(Point(50, 5)));

  s.cx := 7; s.cy := 9;
  writeln('size=', s.Width, 'x', s.Height);   { property over a field }
  s.Width := 11;
  writeln('sizew=', s.cx);
end.
