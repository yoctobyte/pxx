{ SPDX-License-Identifier: Zlib }
unit dialogs;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ PCL-compatible Dialogs.

  ShowMessage pops a modal "info + OK" box and blocks until it is closed,
  matching the PCL contract. It goes through the WidgetSet seam like every
  other control, so this unit names no toolkit and a second widgetset gets
  dialogs by implementing two methods rather than not having them at all
  (feature-pcl-seam-seal).

  TOpenDialog / TSaveDialog / TSelectDirectoryDialog are the file choosers, in
  the same shape Delphi and Lazarus use: set the properties, call Execute,
  read FileName if it returned True. They are ONE seam entry underneath
  (WidgetSet.ChooseFile with a mode) because a toolkit's chooser is one widget
  with a mode argument -- three entry points would make the next widgetset
  implement the same dialog three times.

  Execute returning False and FileName being '' are the SAME condition, so a
  caller may test either. That is deliberate: a widgetset with no chooser
  returns '' from the seam, and a caller written against a backend that has
  one still behaves correctly against a backend that does not.

  A modal box runs its own nested event loop, so an automated test cannot
  click OK. DismissActiveDialog tears it down from a timer callback, which
  returns control from that loop exactly as a real OK click would -- for a
  message box and for a chooser alike, since only one modal is up at a time.
  The dialog HANDLE lives in the widgetset, because it is the widgetset's. }

interface

uses uwidgetset;

type
  { The three choosers share every property; only the mode differs, and the
    mode is set by the constructor rather than exposed, so a TSaveDialog
    cannot be talked into opening.

    Not a TComponent: a dialog owns no children and is never streamed, and
    TComponent's constructor is virtual and takes an owner, so descending
    would cost every caller a nil it has no use for. }
  TFileDialog = class
  private
    FMode: TChooserMode;
  public
    Title: AnsiString;
    InitialDir: AnsiString;
    { In: the name to preselect (open) or offer (save). Out: what was chosen. }
    FileName: AnsiString;
    { 'Pascal|*.pas;*.inc|All files|*' -- description and patterns in pairs.
      Ignored in folder mode, where there are no files to filter. }
    Filter: AnsiString;
    constructor Create(AMode: TChooserMode; const ATitle: AnsiString);
    { True when the user chose something; FileName then holds it. }
    function Execute: Boolean;
    property Mode: TChooserMode read FMode;
  end;

  TOpenDialog = class(TFileDialog)
  public
    constructor Create(const ATitle: AnsiString);
  end;

  TSaveDialog = class(TFileDialog)
  public
    constructor Create(const ATitle: AnsiString);
  end;

  TSelectDirectoryDialog = class(TFileDialog)
  public
    constructor Create(const ATitle: AnsiString);
  end;

procedure ShowMessage(const Msg: AnsiString);

{ One-shot forms, for the common case that needs no object. Each returns ''
  on cancel. }
function OpenFileDialog(const ATitle, AInitialDir, AFilter: AnsiString): AnsiString;
function SaveFileDialog(const ATitle, AInitialDir, AFileName, AFilter: AnsiString): AnsiString;
function SelectDirectoryDialog(const ATitle, AInitialDir: AnsiString): AnsiString;

{ Destroy the currently-shown modal, if any -- message box or file chooser.
  For test harnesses driving a synthetic dismiss from a timeout. }
procedure DismissActiveDialog;

implementation

constructor TFileDialog.Create(AMode: TChooserMode; const ATitle: AnsiString);
begin
  FMode := AMode;
  Title := ATitle;
  InitialDir := '';
  FileName := '';
  Filter := '';
end;

function TFileDialog.Execute: Boolean;
var chosen: AnsiString;
begin
  chosen := WidgetSet.ChooseFile(FMode, Title, InitialDir, FileName, Filter);
  { FileName is left ALONE on cancel: a caller that set it as the preselection
    would otherwise have it silently cleared by a dialog the user dismissed. }
  if chosen <> '' then FileName := chosen;
  Execute := chosen <> '';
end;

constructor TOpenDialog.Create(const ATitle: AnsiString);
begin
  inherited Create(cmOpenFile, ATitle);
end;

constructor TSaveDialog.Create(const ATitle: AnsiString);
begin
  inherited Create(cmSaveFile, ATitle);
end;

constructor TSelectDirectoryDialog.Create(const ATitle: AnsiString);
begin
  inherited Create(cmSelectFolder, ATitle);
end;

procedure ShowMessage(const Msg: AnsiString);
begin
  WidgetSet.MessageBox(Msg);
end;

function OpenFileDialog(const ATitle, AInitialDir, AFilter: AnsiString): AnsiString;
begin
  OpenFileDialog := WidgetSet.ChooseFile(cmOpenFile, ATitle, AInitialDir, '', AFilter);
end;

function SaveFileDialog(const ATitle, AInitialDir, AFileName, AFilter: AnsiString): AnsiString;
begin
  SaveFileDialog := WidgetSet.ChooseFile(cmSaveFile, ATitle, AInitialDir, AFileName, AFilter);
end;

function SelectDirectoryDialog(const ATitle, AInitialDir: AnsiString): AnsiString;
begin
  SelectDirectoryDialog := WidgetSet.ChooseFile(cmSelectFolder, ATitle, AInitialDir, '', '');
end;

procedure DismissActiveDialog;
begin
  WidgetSet.DismissModal;
end;

end.
