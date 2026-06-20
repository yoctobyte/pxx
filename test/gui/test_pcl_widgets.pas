program test_pcl_widgets;

{ Test creation, manipulation, and properties of TMemo, TListBox, and TComboBox. }

uses gtk3, controls, stdctrls, forms;

var
  Form1: TForm;
  Memo: TMemo;
  ListBox: TListBox;
  ComboBox: TComboBox;
  s: string;

begin
  Application := TApplication.Create;
  Application.Initialize;

  Form1 := TForm.Create;
  Form1.Caption := 'Widgets Test';

  { 1. Test TMemo }
  Memo := TMemo.Create;
  Memo.Parent := Form1;
  s := 'Line 1' + #10 + 'Line 2';
  Memo.Text := s;
  writeln('Memo.Text: ', Memo.Text);
  if Memo.Text <> s then
  begin
    writeln('FAIL: Memo text mismatch');
    Halt(1);
  end;

  { 2. Test TListBox }
  ListBox := TListBox.Create;
  ListBox.Parent := Form1;
  ListBox.AddItem('Apple');
  ListBox.AddItem('Banana');
  ListBox.AddItem('Cherry');
  writeln('ListBox Count: ', ListBox.Count);
  writeln('ListBox.Item(0): ', ListBox.Item(0));
  writeln('ListBox.Item(1): ', ListBox.Item(1));
  writeln('ListBox.Item(2): ', ListBox.Item(2));
  if ListBox.Count <> 3 then begin writeln('FAIL: ListBox Count mismatch'); Halt(1); end;
  if ListBox.Item(1) <> 'Banana' then begin writeln('FAIL: ListBox Item mismatch'); Halt(1); end;
  
  ListBox.ItemIndex := 1;
  writeln('ListBox.ItemIndex: ', ListBox.ItemIndex);
  if ListBox.ItemIndex <> 1 then begin writeln('FAIL: ListBox ItemIndex mismatch'); Halt(1); end;

  { 3. Test TComboBox }
  ComboBox := TComboBox.Create;
  ComboBox.Parent := Form1;
  ComboBox.AddItem('Red');
  ComboBox.AddItem('Green');
  ComboBox.AddItem('Blue');
  writeln('ComboBox Count: ', ComboBox.Count);
  if ComboBox.Count <> 3 then begin writeln('FAIL: ComboBox Count mismatch'); Halt(1); end;
  
  ComboBox.ItemIndex := 2;
  writeln('ComboBox.ItemIndex: ', ComboBox.ItemIndex);
  if ComboBox.ItemIndex <> 2 then begin writeln('FAIL: ComboBox ItemIndex mismatch'); Halt(1); end;
  writeln('ComboBox.Text: ', ComboBox.Text);
  if ComboBox.Text <> 'Blue' then begin writeln('FAIL: ComboBox Text mismatch'); Halt(1); end;

  writeln('ALL WIDGET TESTS PASSED');
end.
