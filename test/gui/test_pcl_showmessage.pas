program test_pcl_showmessage;

{ Dialogs.ShowMessage over a real GTK message dialog.

  ShowMessage blocks in gtk_dialog_run's nested loop, so a g_timeout fires
  DismissCB after 400ms to tear the dialog down (the synthetic equivalent of
  clicking OK). Prints before/after to prove the call returned cleanly. }

uses gtk3, dialogs;

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
