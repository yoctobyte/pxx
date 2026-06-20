unit dialogs;

{ Minimal PCL-compatible Dialogs unit over GTK message dialogs.

  ShowMessage pops a modal "info + OK" dialog and blocks (via gtk_dialog_run)
  until the user closes it, matching the PCL contract.

  Because gtk_dialog_run runs its own nested main loop, automated tests can't
  click OK. The active dialog is tracked in ActiveDialog and can be torn down
  from a g_timeout callback via DismissActiveDialog — that returns control to
  gtk_dialog_run exactly as a real OK click would. }

interface

uses gtk3;

var
  ActiveDialog: Pointer;

procedure ShowMessage(const Msg: AnsiString);

{ Destroy the currently-shown dialog, if any. For test harnesses driving a
  synthetic dismiss from a timeout. }
procedure DismissActiveDialog;

implementation

procedure ShowMessage(const Msg: AnsiString);
var dlg: Pointer;
begin
  dlg := gtk_message_dialog_new(nil, GTK_DIALOG_MODAL, GTK_MESSAGE_INFO,
                                GTK_BUTTONS_OK, PC('%s'), PC(Msg));
  ActiveDialog := dlg;
  gtk_dialog_run(dlg);
  { If a timeout already dismissed (destroyed) it, ActiveDialog was cleared —
    don't destroy a freed widget. }
  if ActiveDialog = dlg then
  begin
    gtk_widget_destroy(dlg);
    ActiveDialog := nil;
  end;
end;

procedure DismissActiveDialog;
begin
  if ActiveDialog <> nil then
    gtk_widget_destroy(ActiveDialog);
  ActiveDialog := nil;
end;

end.
