program test_pcl_toolbar;

{ TToolBar and TLabel.Ellipsize -- the two things that decide a window's
  MINIMUM WIDTH, which is what a user meets when they drag the window edge.

  EVERY ROW CARRIES ITS OWN CONTROL, in the same run, because the absolute
  numbers are theme- and font-dependent and a bare threshold would either be
  slack enough to pass anything or tight enough to fail on another box. Each
  row is a PAIR: the wide thing and the narrow thing, measured together.

    - a toolbar's natural width is the sum of its items (>= 400 here) while
      its MINIMUM is a few pixels: a GtkToolbar does not demand room for
      items it can drop.
    - each BUTTON has a proxy menu item, which is what makes a dropped button
      REACHABLE in the arrow menu. Separate from the width, and this test
      says so because the first version of it did not: with the proxies
      disabled the toolbar's minimum is 7px just the same, so a width row
      alone would pass while every button that did not fit was unreachable.
    - an ellipsized label's minimum is a few pixels; the SAME TEXT in a plain
      label is its full width. THAT is what the window's floor was made of --
      505px of status line, not the toolbar. The plain label is the control.

  Absolute coordinates are the thing being replaced, so the form here uses
  none: header box, toolbar, client. }

uses interfaces, gtk3, gtk3_c, controls, stdctrls, extctrls, comctrls, forms;

const
  LONG_TEXT = 'Project hello-esp32 builds for the ESP32 | Board: not detected yet (press Detect)';

var
  F: TForm;
  HeadBox: TBox;
  Bar: TToolBar;
  Ell, Plain: TLabel;
  E: TEdit;
  B: TButton;
  Cb: TComboBox;
  Client: TPaned;
  M1, M2: TMemo;
  d: Integer;
  fail: Integer;

function MinW(w: Pointer): Integer;
var a, b: Integer;
begin
  a := 0; b := 0;
  if w <> nil then gtk_widget_get_preferred_width(w, @a, @b);
  MinW := a;
end;

function NatW(w: Pointer): Integer;
var a, b: Integer;
begin
  a := 0; b := 0;
  if w <> nil then gtk_widget_get_preferred_width(w, @a, @b);
  NatW := b;
end;

procedure Say(const nm: AnsiString; v: Integer);
begin
  writeln(nm, '=', v);
end;

procedure Require(const what: AnsiString; ok: Boolean);
begin
  if ok then writeln('ok   ', what)
  else begin writeln('FAIL ', what); fail := 1; end;
end;

{ How many of the toolbar's items GTK could put in its arrow menu. }
function ProxyCount: Integer;
var i, n, r: Integer; item: Pointer;
begin
  r := 0;
  n := gtk_toolbar_get_n_items(Bar.Handle);
  for i := 0 to n - 1 do
  begin
    item := gtk_toolbar_get_nth_item(Bar.Handle, i);
    if (item <> nil) and (gtk_tool_item_retrieve_proxy_menu_item(item) <> nil) then
      r := r + 1;
  end;
  ProxyCount := r;
end;

function MkB(const c: AnsiString): TButton;
var x: TButton;
begin
  x := TButton.Create(nil);
  x.Caption := c;
  x.Parent := Bar;
  MkB := x;
end;

begin
  fail := 0;
  Application := TApplication.Create;
  Application.Initialize;

  F := TForm.Create(nil);
  F.Caption := 'toolbar';

  HeadBox := TBox.Create(nil);
  HeadBox.Vertical := True;
  HeadBox.Parent := F;

  Bar := TToolBar.Create(nil);
  Bar.Parent := HeadBox;

  { the one sized item, exactly as espide has it: an entry has no sensible
    menu form, so it stays in the row and is the row's real floor }
  E := TEdit.Create(nil);
  E.Parent := Bar;
  E.SetBounds(0, 0, 240, 28);
  B := MkB('Open');
  Bar.AddSeparator;
  Cb := TComboBox.Create(nil);
  Cb.Parent := Bar;
  Cb.AddItem('auto');
  Cb.AddItem('ESP32-S3');
  B := MkB('Detect');
  B := MkB('Save');
  B := MkB('Build+Flash');
  B := MkB('Monitor');
  B := MkB('Stop');

  Ell := TLabel.Create(nil);
  Ell.Ellipsize := True;
  Ell.Caption := LONG_TEXT;
  Ell.Parent := HeadBox;

  { THE CONTROL: the same text without Ellipsize. IT IS IN NO CONTAINER AT
    ALL, and that is not tidiness -- the first draft parented it to the form,
    and a 493px label on the form's absolute area became the WINDOW's minimum
    width, so the last row failed at 493 while measuring the control instead
    of the subject. A setup line that quietly removes the condition under
    test; a widget answers gtk_widget_get_preferred_width with no parent. }
  Plain := TLabel.Create(nil);
  Plain.Caption := LONG_TEXT;
  { TWO steps a parented control gets for free, and BOTH silently answer 0.
    Caption only reaches the widget at Realize, and gtk_widget_get_preferred_
    width of a widget that has never been SHOWN is 0 -- measured 2026-09-27,
    381 once shown. 0 passes a "< 100" row, so getting this wrong would have
    made the ellipsize row green while measuring nothing at all. The
    `plain_min` number is printed for exactly that reason: a control that
    reads 0 is a control that did not run. }
  d := Plain.Realize;
  Plain.Show;

  Client := TPaned.Create(nil);
  Client.Parent := F;
  M1 := TMemo.Create(nil); M1.Parent := Client;
  M2 := TMemo.Create(nil); M2.Parent := Client;

  F.SetBounds(0, 0, 1000, 600);
  F.SetHeader(HeadBox);
  F.SetClient(Client, 0);
  d := F.Realize;
  F.Show;
  { let GTK settle: a preferred size before the first allocation is not the
    one the window manager will honour }
  while gtk_events_pending <> 0 do d := gtk_main_iteration;

  Say('toolbar_min', MinW(Bar.Handle));
  Say('toolbar_nat', NatW(Bar.Handle));
  Say('ellipsized_min', MinW(Ell.Handle));
  Say('plain_min', MinW(Plain.Handle));
  Say('window_min', MinW(F.Handle));

  Require('the toolbar really is wide (its items are there)',
          NatW(Bar.Handle) >= 400);
  Require('but its MINIMUM is not: the buttons overflow',
          MinW(Bar.Handle) < 100);
  Require('a plain label of this text is wide',
          MinW(Plain.Handle) >= 300);
  Require('the same text ellipsized is not',
          MinW(Ell.Handle) < 100);
  Require('ellipsized is strictly narrower than plain',
          MinW(Ell.Handle) < MinW(Plain.Handle));
  Require('so the window can be dragged well below its natural width',
          MinW(F.Handle) < 280);

  { Reachability, which no width row can see. Every button must have a proxy
    menu item -- the thing GTK shows in the arrow menu -- and the entry must
    NOT, because hiding the field you are typing in is worse than a wider
    row. The second half is the control: a blanket "give everything a proxy"
    would satisfy the first. }
  Say('proxied_items', ProxyCount);
  Require('every button can be reached from the overflow menu',
          ProxyCount >= 6);
  Require('the entry is not overflowable',
          gtk_tool_item_retrieve_proxy_menu_item(
            gtk_widget_get_parent(E.Handle)) = nil);

  if fail <> 0 then Halt(1);
  writeln('TOOLBAR OK');
end.
