program test_with;

type
  TPoint = record
    x: Integer;
    y: Integer;
  end;

  TRect = record
    topleft: TPoint;
    bottomright: TPoint;
    area: Integer;
  end;

var
  p: TPoint;
  r: TRect;
  x: Integer;

begin
  x := 42;
  
  p.x := 10;
  p.y := 20;

  { Test simple with }
  with p do
  begin
    writeln('x: ', x);
    writeln('y: ', y);
    
    x := 100;
    y := 200;
  end;

  writeln('p.x after with: ', p.x);
  writeln('p.y after with: ', p.y);
  writeln('global x: ', x);

  { Test nested with }
  r.topleft.x := 1;
  r.topleft.y := 2;
  r.bottomright.x := 3;
  r.bottomright.y := 4;
  r.area := 1000;

  with r do
  begin
    with topleft do
    begin
      writeln('nested x: ', x);
      writeln('nested y: ', y);
      writeln('nested area: ', area);
    end;
  end;

  { Test multiple with in one line }
  with r, bottomright do
  begin
    writeln('multi x: ', x);
    writeln('multi y: ', y);
    writeln('multi area: ', area);
  end;

  writeln('all with tests completed!');
end.
