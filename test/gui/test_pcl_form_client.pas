program test_pcl_form_client;

{ TForm.SetClient — the control that fills the window and resizes with it.

  WHAT THIS MEASURES, AND WHY IT IS NOT A SCREENSHOT. "Can the user resize the
  window" is a question about the window's MINIMUM size, and GTK will answer it
  directly: gtk_widget_get_preferred_width/height return (minimum, natural). No
  window manager, no event loop, no xdotool, and the answer is a number rather
  than a picture. A window whose minimum is its opening size cannot be dragged
  smaller, which is exactly the report this was written for — espide opened at
  1100x720 and would not shrink, because a FORM's SetBounds was reaching
  gtk_widget_set_size_request, which is a minimum and not a size.

  THREE ROWS, AND THE MIDDLE ONE IS THE CONTROL. The risk in that fix is
  over-reach: children ARE positioned absolutely and DO need size requests, so
  row 2 asserts that a child's request still raises the window's minimum.
  Without row 2, rows 1 and 3 would pass just as well if SetBounds had been
  broken for everything.

  TWO THINGS THIS TEST GOT WRONG FIRST, both worth keeping in view because
  either one reads as the fix over-reaching:
    * a child reached 900 only after Realize — setting Parent records the model,
      and WidgetSet.SetParent (the call that puts a widget in the container) runs
      in Realize;
    * and only after being SHOWN — GtkContainer skips invisible children when it
      computes a preferred size, so an unshown 900-wide panel contributes 0. The
      real app never sees this because Application.Run shows the whole tree.
  Both made row 2 read 52 instead of 952.

  Headless: constructs, realizes and shows widgets, never enters the main loop.
  The +52 in the numbers below is the window chrome GTK adds. }

uses gtk3_c, gtk3, controls, stdctrls, extctrls, forms;

var
  FormA, FormB, FormC: TForm;
  Big, Client: TPanel;
  minW, natW, minH, natH, dummy: Integer;
  fails: Integer;

procedure Fail(const what: AnsiString);
begin
  writeln('FAIL: ', what);
  Inc(fails);
end;

{ Show a widget and every non-toplevel container above it. The form's vbox and
  fixed are created unshown (Application.Run shows the tree), and an invisible
  container reports no preferred size — so without this the window's minimum is
  bare chrome whatever its children ask for, and every row passes for the wrong
  reason. The toplevel is deliberately NOT shown: mapping a window is not needed
  to ask what size it would accept. }
procedure ShowChain(w: Pointer);
var p: Pointer;
begin
  gtk_widget_show(w);
  p := gtk_widget_get_parent(w);
  while p <> nil do
  begin
    if gtk_widget_is_toplevel(p) = 0 then gtk_widget_show(p);
    p := gtk_widget_get_parent(p);
  end;
end;

begin
  fails := 0;
  Application := TApplication.Create;
  Application.Initialize;

  { ---- row 1: a form's own SetBounds is an OPENING size, not a minimum ---- }
  FormA := TForm.Create(nil);
  FormA.Caption := 'A';
  FormA.SetBounds(0, 0, 800, 600);
  dummy := FormA.Realize;
  gtk_widget_get_preferred_width(FormA.Handle, @minW, @natW);
  gtk_widget_get_preferred_height(FormA.Handle, @minH, @natH);
  writeln('empty form, SetBounds 800x600: minimum ', minW, 'x', minH);
  if minW >= 800 then
    Fail('the window cannot be dragged narrower than it opened (its minimum ' +
         'width is its SetBounds width)');
  if minH >= 600 then
    Fail('the window cannot be dragged shorter than it opened (its minimum ' +
         'height is its SetBounds height)');

  { ---- row 2 (THE CONTROL): an absolutely-placed child still constrains ---- }
  FormB := TForm.Create(nil);
  FormB.Caption := 'B';
  FormB.SetBounds(0, 0, 800, 600);
  Big := TPanel.Create(nil);
  Big.Parent := FormB;
  Big.SetBounds(0, 0, 900, 700);
  dummy := FormB.Realize;
  ShowChain(Big.Handle);
  gtk_widget_get_preferred_width(FormB.Handle, @minW, @natW);
  writeln('form with a 900-wide absolutely-placed child: minimum ', minW);
  if minW < 900 then
    Fail('a child size request no longer reaches the window -- SetBounds is ' +
         'broken for CHILDREN, which rows 1 and 3 cannot see');

  { ---- row 3: the client fills the window and imposes no minimum ----
    ITS OWN FORM, not FormB: Big is still in FormB's container asking for 900, so
    a client added there could not lower that form's minimum and the row would
    fail for a reason that has nothing to do with SetClient. }
  FormC := TForm.Create(nil);
  FormC.Caption := 'C';
  FormC.SetBounds(0, 0, 800, 600);
  Client := TPanel.Create(nil);
  Client.Parent := FormC;
  Client.SetBounds(0, 0, 900, 700);
  dummy := FormC.Realize;
  ShowChain(Client.Handle);
  FormC.SetClient(Client, 0);
  gtk_widget_get_preferred_width(FormC.Handle, @minW, @natW);
  writeln('after SetClient of a 900-wide control: minimum ', minW);
  if minW >= 900 then
    Fail('the client still imposes its size request as the window minimum');

  { The client must still BE there. gtk_container_remove drops the container's
    reference, and the container held the only one, so a reparent that does not
    hold a reference across the move is a DESTROY -- and that bug passed
    --gui-smoke, because what --gui-smoke asserts is the status line. }
  if Client.Handle = nil then
    Fail('the client lost its handle');
  if gtk_widget_get_parent(Client.Handle) = nil then
    Fail('the client has no parent after SetClient: it was destroyed by the ' +
         'reparent rather than moved');

  if fails > 0 then
  begin
    writeln('test_pcl_form_client: ', fails, ' failure(s)');
    Halt(1);
  end;
  writeln('test_pcl_form_client: OK');
end.
