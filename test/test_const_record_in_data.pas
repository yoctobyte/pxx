program test_const_record_in_data;
{ A typed const RECORD, and an array of them, is initialised .data -- not BSS
  plus one generated store per field at startup.
  bug-a-a-typed-const-record-is-built-by-startup-code-not-stored-as-data

  Two rows in the Makefile, because values alone cannot fail: the startup
  stores produce the same values, so a value row passes whether or not
  anything was baked. The second row reads PXXDBG=a.constdata and asserts WHICH
  consts were baked -- and which were REFUSED (a string field, a float field),
  so a baker that took everything would fail it too. }
{$J+}
type
  TColor = (cRed, cGreen, cBlue);
  TInner = record X, Y: SmallInt; end;
  TOuter = record Pre: Byte; In1: TInner; Post: Int64; In2: TInner; end;
  TVar = record Tag: Integer; case Integer of 0: (A: Int64); 1: (L, H: Integer); end;
  TEn = record K: TColor; N: Integer; end;
  TStr = record N: Integer; S: string; end;
  TFl = record D: Double; end;
const
  cOuter: TOuter = (Pre: 1; In1: (X: -2; Y: 3); Post: -9000000000; In2: (X: 5; Y: -6));
  cVar: TVar = (Tag: 1; L: -1; H: 2);
  cEn: TEn = (K: cBlue; N: 5);
  cPart: TOuter = (Pre: 7);
  aNeg: array[-2..0] of TEn = ((K: cRed; N: 1), (K: cGreen; N: 2), (K: cBlue; N: 3));
  cStr: TStr = (N: 1; S: 'hello');
  cFl: TFl = (D: 2.5);
begin
  WriteLn(cOuter.Pre, ' ', cOuter.In1.X, ' ', cOuter.In1.Y, ' ', cOuter.Post, ' ',
          cOuter.In2.X, ' ', cOuter.In2.Y);
  WriteLn(cVar.Tag, ' ', cVar.L, ' ', cVar.H);
  WriteLn(Ord(cEn.K), ' ', cEn.N, ' ', cPart.Pre, ' ', cPart.Post, ' ', cPart.In2.Y);
  WriteLn(Ord(aNeg[-2].K), aNeg[-2].N, ' ', Ord(aNeg[0].K), aNeg[0].N);
  WriteLn(cStr.S, ' ', cFl.D:0:1);
  { {$J+}: baked into .data, still writable }
  cOuter.In2.Y := 42; aNeg[-1].N := 99;
  WriteLn(cOuter.In2.Y, ' ', aNeg[-1].N);
end.
