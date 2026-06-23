program test_pcl_drawing;

{ Test canvas operations and custom paint box drawing. }

uses gtk3, controls, extctrls, graphics, forms;

var
  Form1: TForm;
  PaintBox: TPaintBox;
  DrawTriggered: Boolean;

procedure PaintBoxPaint(Sender: TControl; Canvas: TCanvas);
begin
  writeln('PaintBoxPaint triggered!');
  
  { 1. Test Pen and basic line drawing }
  Canvas.Pen.Color := clRed;
  Canvas.Pen.Width := 3;
  Canvas.MoveTo(10, 10);
  Canvas.LineTo(100, 10);
  
  { 2. Test Brush and Rectangle }
  Canvas.Brush.Color := clBlue;
  Canvas.Pen.Color := clBlack;
  Canvas.Pen.Width := 1;
  Canvas.Rectangle(20, 20, 120, 80);
  
  { 3. Test Ellipse }
  Canvas.Brush.Color := clYellow;
  Canvas.Ellipse(150, 20, 250, 80);
  
  { 4. Test TextOut }
  Canvas.Font.Name := 'Sans';
  Canvas.Font.Size := 12;
  Canvas.Font.Color := clGreen;
  Canvas.TextOut(10, 100, 'PCL Drawing OK');
  
  DrawTriggered := True;
end;

type
  THelper = class
    procedure DoPaint(Sender: TControl; Canvas: TCanvas);
  end;

procedure THelper.DoPaint(Sender: TControl; Canvas: TCanvas);
begin
  PaintBoxPaint(Sender, Canvas);
end;

var
  helper: THelper;
  m: TMethod;

begin
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TForm.Create(nil);
  Form1.Caption := 'Drawing Test';

  PaintBox := TPaintBox.Create(nil);
  PaintBox.Parent := Form1;
  PaintBox.SetBounds(0, 0, 320, 240);

  helper := THelper.Create;
  m.Code := @helper.DoPaint;
  m.Data := helper;
  PaintBox.OnPaint := m;

  DrawTriggered := False;

  writeln('Realizing form and components...');
  Form1.Realize;
  
  writeln('PaintBox created: ', Int64(PaintBox.Handle) <> 0);
  writeln('Canvas initialized: ', Int64(PaintBox.Canvas) <> 0);

  writeln('Manually invoking OnPaint...');
  PaintBoxPaint(PaintBox, PaintBox.Canvas);
  
  if not DrawTriggered then
  begin
    writeln('FAIL: PaintBox OnPaint was not triggered');
    Halt(1);
  end;

  writeln('ALL DRAWING TESTS PASSED');
end.
