{ Regression: bug-property-setter-resolution-uses-order — MAX_UPROP was 64
  with no bounds check in AddUProperty; property #65+ silently corrupted the
  sibling UProp* parallel arrays (flipping e.g. UPropIsIndexed on unrelated
  properties), so a class-typed property write behind a big-enough unit graph
  mis-parsed with 'Expected: ['. This declares >64 properties, then exercises
  a class-typed setter-backed property write on the FIRST class registered. }
program test_many_properties;
type
  TNode = class
  public
    FParent: TNode;
    FTag: Integer;
    procedure SetParent(v: TNode);
    property Parent: TNode read FParent write SetParent;
    property Tag: Integer read FTag write FTag;
  end;
  TFiller0 = class
  public
    FP0_0: Integer;
    FP0_1: Integer;
    FP0_2: Integer;
    FP0_3: Integer;
    FP0_4: Integer;
    FP0_5: Integer;
    FP0_6: Integer;
    FP0_7: Integer;
    FP0_8: Integer;
    property P0: Integer read FP0_0 write FP0_0;
    property P1: Integer read FP0_1 write FP0_1;
    property P2: Integer read FP0_2 write FP0_2;
    property P3: Integer read FP0_3 write FP0_3;
    property P4: Integer read FP0_4 write FP0_4;
    property P5: Integer read FP0_5 write FP0_5;
    property P6: Integer read FP0_6 write FP0_6;
    property P7: Integer read FP0_7 write FP0_7;
    property P8: Integer read FP0_8 write FP0_8;
  end;
  TFiller1 = class
  public
    FP1_0: Integer;
    FP1_1: Integer;
    FP1_2: Integer;
    FP1_3: Integer;
    FP1_4: Integer;
    FP1_5: Integer;
    FP1_6: Integer;
    FP1_7: Integer;
    FP1_8: Integer;
    property P0: Integer read FP1_0 write FP1_0;
    property P1: Integer read FP1_1 write FP1_1;
    property P2: Integer read FP1_2 write FP1_2;
    property P3: Integer read FP1_3 write FP1_3;
    property P4: Integer read FP1_4 write FP1_4;
    property P5: Integer read FP1_5 write FP1_5;
    property P6: Integer read FP1_6 write FP1_6;
    property P7: Integer read FP1_7 write FP1_7;
    property P8: Integer read FP1_8 write FP1_8;
  end;
  TFiller2 = class
  public
    FP2_0: Integer;
    FP2_1: Integer;
    FP2_2: Integer;
    FP2_3: Integer;
    FP2_4: Integer;
    FP2_5: Integer;
    FP2_6: Integer;
    FP2_7: Integer;
    FP2_8: Integer;
    property P0: Integer read FP2_0 write FP2_0;
    property P1: Integer read FP2_1 write FP2_1;
    property P2: Integer read FP2_2 write FP2_2;
    property P3: Integer read FP2_3 write FP2_3;
    property P4: Integer read FP2_4 write FP2_4;
    property P5: Integer read FP2_5 write FP2_5;
    property P6: Integer read FP2_6 write FP2_6;
    property P7: Integer read FP2_7 write FP2_7;
    property P8: Integer read FP2_8 write FP2_8;
  end;
  TFiller3 = class
  public
    FP3_0: Integer;
    FP3_1: Integer;
    FP3_2: Integer;
    FP3_3: Integer;
    FP3_4: Integer;
    FP3_5: Integer;
    FP3_6: Integer;
    FP3_7: Integer;
    FP3_8: Integer;
    property P0: Integer read FP3_0 write FP3_0;
    property P1: Integer read FP3_1 write FP3_1;
    property P2: Integer read FP3_2 write FP3_2;
    property P3: Integer read FP3_3 write FP3_3;
    property P4: Integer read FP3_4 write FP3_4;
    property P5: Integer read FP3_5 write FP3_5;
    property P6: Integer read FP3_6 write FP3_6;
    property P7: Integer read FP3_7 write FP3_7;
    property P8: Integer read FP3_8 write FP3_8;
  end;
  TFiller4 = class
  public
    FP4_0: Integer;
    FP4_1: Integer;
    FP4_2: Integer;
    FP4_3: Integer;
    FP4_4: Integer;
    FP4_5: Integer;
    FP4_6: Integer;
    FP4_7: Integer;
    FP4_8: Integer;
    property P0: Integer read FP4_0 write FP4_0;
    property P1: Integer read FP4_1 write FP4_1;
    property P2: Integer read FP4_2 write FP4_2;
    property P3: Integer read FP4_3 write FP4_3;
    property P4: Integer read FP4_4 write FP4_4;
    property P5: Integer read FP4_5 write FP4_5;
    property P6: Integer read FP4_6 write FP4_6;
    property P7: Integer read FP4_7 write FP4_7;
    property P8: Integer read FP4_8 write FP4_8;
  end;
  TFiller5 = class
  public
    FP5_0: Integer;
    FP5_1: Integer;
    FP5_2: Integer;
    FP5_3: Integer;
    FP5_4: Integer;
    FP5_5: Integer;
    FP5_6: Integer;
    FP5_7: Integer;
    FP5_8: Integer;
    property P0: Integer read FP5_0 write FP5_0;
    property P1: Integer read FP5_1 write FP5_1;
    property P2: Integer read FP5_2 write FP5_2;
    property P3: Integer read FP5_3 write FP5_3;
    property P4: Integer read FP5_4 write FP5_4;
    property P5: Integer read FP5_5 write FP5_5;
    property P6: Integer read FP5_6 write FP5_6;
    property P7: Integer read FP5_7 write FP5_7;
    property P8: Integer read FP5_8 write FP5_8;
  end;
  TFiller6 = class
  public
    FP6_0: Integer;
    FP6_1: Integer;
    FP6_2: Integer;
    FP6_3: Integer;
    FP6_4: Integer;
    FP6_5: Integer;
    FP6_6: Integer;
    FP6_7: Integer;
    FP6_8: Integer;
    property P0: Integer read FP6_0 write FP6_0;
    property P1: Integer read FP6_1 write FP6_1;
    property P2: Integer read FP6_2 write FP6_2;
    property P3: Integer read FP6_3 write FP6_3;
    property P4: Integer read FP6_4 write FP6_4;
    property P5: Integer read FP6_5 write FP6_5;
    property P6: Integer read FP6_6 write FP6_6;
    property P7: Integer read FP6_7 write FP6_7;
    property P8: Integer read FP6_8 write FP6_8;
  end;
  TFiller7 = class
  public
    FP7_0: Integer;
    FP7_1: Integer;
    FP7_2: Integer;
    FP7_3: Integer;
    FP7_4: Integer;
    FP7_5: Integer;
    FP7_6: Integer;
    FP7_7: Integer;
    FP7_8: Integer;
    property P0: Integer read FP7_0 write FP7_0;
    property P1: Integer read FP7_1 write FP7_1;
    property P2: Integer read FP7_2 write FP7_2;
    property P3: Integer read FP7_3 write FP7_3;
    property P4: Integer read FP7_4 write FP7_4;
    property P5: Integer read FP7_5 write FP7_5;
    property P6: Integer read FP7_6 write FP7_6;
    property P7: Integer read FP7_7 write FP7_7;
    property P8: Integer read FP7_8 write FP7_8;
  end;

procedure TNode.SetParent(v: TNode);
begin
  FParent := v;
  FTag := FTag + 1;
end;

var a, b: TNode; f: TFiller7;
begin
  a := TNode.Create;
  b := TNode.Create;
  a.Tag := 10;
  a.Parent := b;          { class-typed setter write — the broken shape }
  writeln(a.Tag);         { 11: setter ran }
  writeln(a.Parent = b);  { TRUE: value stored }
  f := TFiller7.Create;
  f.P8 := 99;
  writeln(f.P8);
end.
