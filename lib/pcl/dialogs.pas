{ SPDX-License-Identifier: Zlib }
unit dialogs;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ PCL-compatible Dialogs.

  ShowMessage pops a modal "info + OK" box and blocks until it is closed,
  matching the PCL contract. It goes through the WidgetSet seam like every
  other control, so this unit names no toolkit and a second widgetset gets
  dialogs by implementing two methods rather than not having them at all
  (feature-pcl-seam-seal).

  A modal box runs its own nested event loop, so an automated test cannot
  click OK. DismissActiveDialog tears it down from a timer callback, which
  returns control from that loop exactly as a real OK click would. The dialog
  HANDLE now lives in the widgetset, because it is the widgetset's — the
  `ActiveDialog` variable this unit used to export is gone with it; callers
  only ever used DismissActiveDialog. }

interface

uses uwidgetset;

procedure ShowMessage(const Msg: AnsiString);

{ Destroy the currently-shown dialog, if any. For test harnesses driving a
  synthetic dismiss from a timeout. }
procedure DismissActiveDialog;

implementation

procedure ShowMessage(const Msg: AnsiString);
begin
  WidgetSet.MessageBox(Msg);
end;

procedure DismissActiveDialog;
begin
  WidgetSet.DismissMessageBox;
end;

end.
