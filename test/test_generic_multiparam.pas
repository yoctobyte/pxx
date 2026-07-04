program test_generic_multiparam;
{ Multi-parameter generic templates (<TKey, TData>) + constrained type
  parameters (<T: TObject>, parse-and-ignore) — FPC fgl's TFPGMap /
  TFPGObjectList shapes. Also covers a semicolon-separated constrained group
  (<TKey; TData: TObject>) and cross-param method bodies. }

type
  generic TPair<TKey, TData> = class
    FK: TKey;
    FD: TData;
    procedure SetBoth(k: TKey; d: TData);
    function GetK: TKey;
  end;
  TBase = class
    FV: Integer;
  end;
  generic TCon<T: TBase> = class
    FO: T;
  end;
  generic TMixed<TKey; TData: TBase> = class
    FKey: TKey;
    FObj: TData;
  end;
  TSI = specialize TPair<String, Integer>;
  TII = specialize TPair<Integer, Integer>;
  TCB = specialize TCon<TBase>;
  TMX = specialize TMixed<Integer, TBase>;

var
  total, okc: Integer;

procedure Check(name: string; ok: Boolean);
begin
  total := total + 1;
  if ok then
  begin
    okc := okc + 1;
    writeln('ok ', name);
  end
  else
    writeln('FAIL ', name);
end;

procedure TPair.SetBoth(k: TKey; d: TData);
begin
  FK := k;
  FD := d;
end;

function TPair.GetK: TKey;
begin
  GetK := FK;
end;

var
  p: TSI;
  q: TII;
  c: TCB;
  m: TMX;
  o: TBase;
begin
  total := 0; okc := 0;

  p := TSI.Create;
  p.SetBoth('hello', 7);
  Check('string-int-pair', (p.GetK = 'hello') and (p.FD = 7));
  p.Free;

  q := TII.Create;
  q.SetBoth(3, 4);
  Check('int-int-pair', q.FK + q.FD = 7);
  q.Free;

  o := TBase.Create;
  c := TCB.Create;
  c.FO := o;
  Check('constrained-param', c.FO = o);
  c.Free;

  m := TMX.Create;
  m.FKey := 9;
  m.FObj := o;
  Check('mixed-group-params', (m.FKey = 9) and (m.FObj = o));
  m.Free;
  o.Free;

  writeln('total ok ', okc, ' / ', total);
end.
