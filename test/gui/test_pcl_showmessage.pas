program test_pcl_showmessage;

{ Dialogs.ShowMessage over a real GTK message dialog.

  ShowMessage blocks in gtk_dialog_run's nested loop, so a g_timeout fires
  DismissCB after 400ms to tear the dialog down (the synthetic equivalent of
  clicking OK). Prints before/after to prove the call returned cleanly. }

{ `interfaces` is REQUIRED and is not decoration: ShowMessage is
  WidgetSet.MessageBox, and WidgetSet is assigned in gtk3widgets'
  `initialization` -- which never runs unless something links that unit in.
  `interfaces` is the unit that selects it. Without it WidgetSet is nil and
  this dies with runtime error 216 on the ShowMessage line, which is exactly
  what it did for as long as nothing ran it
  (chore-t-six-orphan-gui-tests-the-blanket-was-hiding). }
uses interfaces, gtk3, dialogs, gtk3_c;

function DismissCB(data: Pointer): Integer; cdecl;
begin
  writeln('dismiss dialog');
  DismissActiveDialog;
  DismissCB := 0; { G_SOURCE_REMOVE }
end;

begin
  gtk_init(nil, nil);
  g_timeout_add(400, @DismissCB, nil);
  writeln('before ShowMessage');
  ShowMessage('Hello World');
  writeln('after ShowMessage');
end.
