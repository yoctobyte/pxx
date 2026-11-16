{ SPDX-License-Identifier: Zlib }
unit win32widgets;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }

{ The native Win32 widgetset (feature-pcl-win32-widgetset): PCL over
  user32/gdi32/comdlg32, the DLLs every Windows and ReactOS has, so a PCL
  program is one .exe with nothing beside it. Selected by interfaces.pas for
  --os=windows.

  HOW IT HANGS TOGETHER
  - Every window this unit creates carries its TControl in GWLP_USERDATA, so
    a message finds its control without a table.
  - Forms, panels and paint boxes are windows of this unit's own classes and
    share one window procedure (PxxWndProc), a pxx `stdcall` routine: taking
    its address gives Windows a Microsoft-convention adapter (winabi
    PxxWinCallback). Buttons, edits, lists and combos are the system's own
    classes; their notifications (WM_COMMAND) arrive at the parent, which is
    always one of ours.
  - A control is created before it has a parent (Realize creates the handle,
    then calls SetParent), and a WS_CHILD window needs one, so new controls
    start on a hidden parking window and SetParent moves them.
  - A form's size is its client size INCLUDING the menu bar, as on GTK, where
    the menu is packed into the window's box: the menu then takes its height
    from the client, and a 820x640 form shows the same board on both.
  - Paint boxes draw into a memory bitmap and copy it to the screen in one
    BitBlt: no flicker while a card is dragged.
  - Keys reach OnKeyDown as GDK keyvals, which is what the GTK set delivers
    and what programs test against: printable characters as their code,
    Enter/Escape/Backspace/Tab and the cursor keys as their 0xffxx values.
  - Strings are UTF-8 in PCL and UTF-16 in the *W calls.

  NOT YET (base class behaviour: no widget): TPaned, TBox, TToolBar,
  TTreeView, TNotebook, the folder chooser, GL areas. }

interface

uses classes_lite, uwidgetset;

type
  TWin32WidgetSet = class(TWidgetSet)
  public
    procedure AppInit; override;
    procedure AppRun; override;
    procedure AppQuit; override;
    function CreateForm(AForm: TComponent): Pointer; override;
    function CreateButton(AButton: TComponent): Pointer; override;
    function CreateLabel(ALabel: TComponent): Pointer; override;
    function CreateEdit(AEdit: TComponent): Pointer; override;
    function CreateCheckBox(ACheckBox: TComponent): Pointer; override;
    function CreatePanel(APanel: TComponent): Pointer; override;
    function CreateMemo(AMemo: TComponent): Pointer; override;
    function CreateListBox(AListBox: TComponent): Pointer; override;
    function CreateComboBox(AComboBox: TComponent): Pointer; override;
    function CreatePaintBox(APaintBox: TComponent): Pointer; override;
    procedure SetText(AControl: TComponent; const AText: string); override;
    procedure Invalidate(AControl: TComponent); override;
    procedure SetBounds(AControl: TComponent; ALeft, ATop, AWidth, AHeight: Integer); override;
    procedure SetParent(AControl: TComponent; AParent: TComponent); override;
    procedure ShowWidget(AControl: TComponent); override;
    procedure ConnectClick(AControl: TComponent); override;
    procedure ConnectChange(AControl: TComponent); override;
    procedure ConnectAppQuit(AForm: TComponent); override;
    procedure SetChecked(AControl: TComponent; AChecked: Boolean); override;
    function GetChecked(AControl: TComponent): Boolean; override;
    function GetMemoText(AMemo: TComponent): string; override;
    procedure SetMemoText(AMemo: TComponent; const AText: string); override;
    procedure MemoCaretToLine(AMemo: TComponent; line: Integer); override;
    function MemoCaretLine(AMemo: TComponent): Integer; override;
    function AddListItem(AListBox: TComponent; const AText: string): Pointer; override;
    function GetListIndex(AListBox: TComponent): Integer; override;
    procedure SetListIndex(AListBox: TComponent; AIndex: Integer); override;
    procedure ClearList(AListBox: TComponent); override;
    procedure DestroyWidget(AWidget: Pointer); override;
    function ChooseFile(AMode: TChooserMode;
                        const ATitle, AInitialDir, AFileName, AFilter: string): string; override;
    procedure AddComboItem(AComboBox: TComponent; const AText: string); override;
    function GetActiveIndex(AComboBox: TComponent): Integer; override;
    procedure SetActiveIndex(AComboBox: TComponent; AIndex: Integer); override;
    procedure ClearCombo(AComboBox: TComponent); override;
    function StartTimer(AInterval: Integer; ACallback: Pointer; AData: Pointer): LongWord; override;
    procedure StopTimer(AId: LongWord); override;
    function SetFormMenu(AForm: TComponent; AMenu: TComponent): Integer; override;
    procedure SetFormClient(AForm: TComponent; AControl: TComponent;
                            AHeaderHeight: Integer); override;
    procedure SetFormHeader(AForm: TComponent; AControl: TComponent); override;
    procedure SetMenuItemEnabled(AItem: TComponent; AEnabled: Boolean); override;
    procedure SetMenuItemVisible(AItem: TComponent; AVisible: Boolean); override;
    procedure ShowHandle(AWidget: Pointer); override;
    procedure HideHandle(AWidget: Pointer); override;
    function HandleWidth(AWidget: Pointer): Integer; override;
    function HandleHeight(AWidget: Pointer): Integer; override;
    procedure MessageBox(const AText: string); override;
    procedure DismissModal; override;
  end;

implementation

uses controls, typinfo, graphics, extctrls, menus;

{ ---- user32 / gdi32 / kernel32 / comdlg32 ---------------------------------- }
type
  TWndClassExW = record
    cbSize, style: LongWord;
    lpfnWndProc: Pointer;
    cbClsExtra, cbWndExtra: LongInt;
    hInstance, hIcon, hCursor, hbrBackground: Pointer;
    lpszMenuName, lpszClassName: PWideChar;
    hIconSm: Pointer;
  end;
  TWMsg = record
    hwnd: Pointer;
    message: LongWord;
    wParam, lParam: Int64;
    time: LongWord;
    ptx, pty: LongInt;
    priv: LongWord;
  end;
  TWRect = record
    l, t, r, b: LongInt;
  end;
  TPaintStruct = record
    hdc: Pointer;
    fErase: LongInt;
    rc: TWRect;
    fRestore, fIncUpdate: LongInt;
    rgb: array[0..31] of Byte;
  end;
  TOpenFileNameW = record
    lStructSize: LongWord;
    hwndOwner, hInstance: Pointer;
    lpstrFilter, lpstrCustomFilter: PWideChar;
    nMaxCustFilter, nFilterIndex: LongWord;
    lpstrFile: PWideChar;
    nMaxFile: LongWord;
    lpstrFileTitle: PWideChar;
    nMaxFileTitle: LongWord;
    lpstrInitialDir, lpstrTitle: PWideChar;
    Flags: LongWord;
    nFileOffset, nFileExtension: Word;
    lpstrDefExt: PWideChar;
    lCustData: Int64;
    lpfnHook: Pointer;
    lpTemplateName: PWideChar;
    pvReserved: Pointer;
    dwReserved, FlagsEx: LongWord;
  end;
  TWBuf = array of WideChar;

function GetModuleHandleW(name: PWideChar): Pointer; stdcall; external 'kernel32.dll';
function MultiByteToWideChar(cp, flags: LongWord; s: PChar; n: LongInt; w: PWideChar; wn: LongInt): LongInt; stdcall; external 'kernel32.dll';
function WideCharToMultiByte(cp, flags: LongWord; w: PWideChar; wn: LongInt; s: PChar; n: LongInt; def, used: Pointer): LongInt; stdcall; external 'kernel32.dll';
function RegisterClassExW(const wc: TWndClassExW): Word; stdcall; external 'user32.dll';
function CreateWindowExW(ex: LongWord; cls, title: PWideChar; style: LongWord; x, y, w, h: LongInt;
  parent, menu, inst, param: Pointer): Pointer; stdcall; external 'user32.dll';
function DefWindowProcW(h: Pointer; m: LongWord; wp, lp: Int64): Int64; stdcall; external 'user32.dll';
function DestroyWindow(h: Pointer): LongInt; stdcall; external 'user32.dll';
function ShowWindow(h: Pointer; cmd: LongInt): LongInt; stdcall; external 'user32.dll';
function UpdateWindow(h: Pointer): LongInt; stdcall; external 'user32.dll';
function GetMessageW(var m: TWMsg; h: Pointer; a, b: LongWord): LongInt; stdcall; external 'user32.dll';
function TranslateMessage(const m: TWMsg): LongInt; stdcall; external 'user32.dll';
function DispatchMessageW(const m: TWMsg): Int64; stdcall; external 'user32.dll';
procedure PostQuitMessage(code: LongInt); stdcall; external 'user32.dll';
function SendMessageW(h: Pointer; m: LongWord; wp, lp: Int64): Int64; stdcall; external 'user32.dll';
function SetWindowLongPtrW(h: Pointer; idx: LongInt; v: Int64): Int64; stdcall; external 'user32.dll';
function GetWindowLongPtrW(h: Pointer; idx: LongInt): Int64; stdcall; external 'user32.dll';
function SetWindowTextW(h: Pointer; s: PWideChar): LongInt; stdcall; external 'user32.dll';
function GetWindowTextW(h: Pointer; s: PWideChar; n: LongInt): LongInt; stdcall; external 'user32.dll';
function GetWindowTextLengthW(h: Pointer): LongInt; stdcall; external 'user32.dll';
function MoveWindow(h: Pointer; x, y, w, hh: LongInt; repaint: LongInt): LongInt; stdcall; external 'user32.dll';
function SetWindowPos(h, after: Pointer; x, y, w, hh: LongInt; flags: LongWord): LongInt; stdcall; external 'user32.dll';
function GetClientRect(h: Pointer; var r: TWRect): LongInt; stdcall; external 'user32.dll';
function GetWindowRect(h: Pointer; var r: TWRect): LongInt; stdcall; external 'user32.dll';
function AdjustWindowRectEx(var r: TWRect; style: LongWord; menu: LongInt; ex: LongWord): LongInt; stdcall; external 'user32.dll';
function SetParentW(child, parent: Pointer): Pointer; stdcall; external 'user32.dll' name 'SetParent';
function InvalidateRect(h: Pointer; r: Pointer; erase: LongInt): LongInt; stdcall; external 'user32.dll';
function BeginPaint(h: Pointer; var ps: TPaintStruct): Pointer; stdcall; external 'user32.dll';
function EndPaint(h: Pointer; const ps: TPaintStruct): LongInt; stdcall; external 'user32.dll';
function SetTimer(h: Pointer; id: Int64; ms: LongWord; fn: Pointer): Int64; stdcall; external 'user32.dll';
function KillTimer(h: Pointer; id: Int64): LongInt; stdcall; external 'user32.dll';
function SetFocus(h: Pointer): Pointer; stdcall; external 'user32.dll';
function SetCapture(h: Pointer): Pointer; stdcall; external 'user32.dll';
function ReleaseCapture: LongInt; stdcall; external 'user32.dll';
function LoadCursorW(inst: Pointer; name: Int64): Pointer; stdcall; external 'user32.dll';
function CreateMenu: Pointer; stdcall; external 'user32.dll';
function CreatePopupMenu: Pointer; stdcall; external 'user32.dll';
function AppendMenuW(m: Pointer; flags: LongWord; id: Int64; s: PWideChar): LongInt; stdcall; external 'user32.dll';
function SetMenu(h, m: Pointer): LongInt; stdcall; external 'user32.dll';
function GetMenu(h: Pointer): Pointer; stdcall; external 'user32.dll';
function DestroyMenu(m: Pointer): LongInt; stdcall; external 'user32.dll';
function DrawMenuBar(h: Pointer): LongInt; stdcall; external 'user32.dll';
function EnableMenuItem(m: Pointer; id, flags: LongWord): LongInt; stdcall; external 'user32.dll';
function MessageBoxW(h: Pointer; text, title: PWideChar; flags: LongWord): LongInt; stdcall; external 'user32.dll';
function IsWindowVisible(h: Pointer): LongInt; stdcall; external 'user32.dll';
function GetStockObject(i: LongInt): Pointer; stdcall; external 'gdi32.dll';
function CreateCompatibleDC(dc: Pointer): Pointer; stdcall; external 'gdi32.dll';
function CreateCompatibleBitmap(dc: Pointer; w, h: LongInt): Pointer; stdcall; external 'gdi32.dll';
function SelectObject(dc, obj: Pointer): Pointer; stdcall; external 'gdi32.dll';
function DeleteObject(obj: Pointer): LongInt; stdcall; external 'gdi32.dll';
function DeleteDC(dc: Pointer): LongInt; stdcall; external 'gdi32.dll';
function BitBlt(dst: Pointer; x, y, w, h: LongInt; src: Pointer; sx, sy: LongInt; rop: LongWord): LongInt; stdcall; external 'gdi32.dll';
function GetOpenFileNameW(var ofn: TOpenFileNameW): LongInt; stdcall; external 'comdlg32.dll';
function GetSaveFileNameW(var ofn: TOpenFileNameW): LongInt; stdcall; external 'comdlg32.dll';

const
  GWLP_USERDATA = -21;
  WS_OVERLAPPEDWINDOW = $00CF0000;
  WS_CHILD = $40000000; WS_VISIBLE = $10000000; WS_BORDER = $00800000;
  WS_VSCROLL = $00200000; WS_HSCROLL = $00100000; WS_TABSTOP = $00010000;
  WS_CLIPCHILDREN = $02000000; WS_CLIPSIBLINGS = $04000000;
  WS_EX_CLIENTEDGE = $200;
  CW_USEDEFAULT = LongInt($80000000);
  WM_DESTROY = $0002; WM_SIZE = $0005; WM_SETFOCUS = $0007; WM_PAINT = $000F;
  WM_CLOSE = $0010; WM_ERASEBKGND = $0014; WM_SETFONT = $0030;
  WM_KEYDOWN = $0100; WM_CHAR = $0102; WM_COMMAND = $0111; WM_TIMER = $0113;
  WM_MOUSEMOVE = $0200; WM_LBUTTONDOWN = $0201; WM_LBUTTONUP = $0202;
  WM_RBUTTONDOWN = $0204; WM_RBUTTONUP = $0205; WM_MBUTTONDOWN = $0207; WM_MBUTTONUP = $0208;
  BM_GETCHECK = $00F0; BM_SETCHECK = $00F1;
  EM_SETSEL = $00B1; EM_LINEFROMCHAR = $00C9; EM_LINEINDEX = $00BB; EM_SCROLLCARET = $00B7;
  LB_ADDSTRING = $0180; LB_RESETCONTENT = $0184; LB_SETCURSEL = $0186; LB_GETCURSEL = $0188;
  CB_ADDSTRING = $0143; CB_GETCURSEL = $0147; CB_RESETCONTENT = $014B; CB_SETCURSEL = $014E;
  BN_CLICKED = 0; EN_CHANGE = $0300; LBN_SELCHANGE = 1; CBN_SELCHANGE = 1;
  MF_STRING = 0; MF_GRAYED = 1; MF_POPUP = $10; MF_SEPARATOR = $800; MF_BYCOMMAND = 0;
  SWP_NOMOVE = 2; SWP_NOZORDER = 4; SWP_NOACTIVATE = $10;
  SRCCOPY = $00CC0020;
  CP_UTF8 = 65001;
  MENU_ID_BASE = 1000;
  MAX_TIMERS = 64;
  MAX_MENU_IDS = 1024;
  ROW_MAGIC = $50585852;   { 'PXXR' }

type
  { a list row: what AddListItem hands TListBox to give back to DestroyWidget }
  PListRow = ^TListRow;
  TListRow = record
    magic: LongWord;
    list: Pointer;
  end;

var
  Inst: Pointer;
  Parking: Pointer;                      { hidden owner of controls not yet parented, and of timers }
  MainForm: Pointer;                     { the form whose destruction ends the loop }
  ClsForm, ClsPanel, ClsPaint, ClsParking: array[0..15] of WideChar;
  TimerIds: array[0..MAX_TIMERS - 1] of LongWord;
  TimerData: array[0..MAX_TIMERS - 1] of Pointer;
  TimerNext: LongWord = 1;
  MenuItems: array[0..MAX_MENU_IDS - 1] of Pointer;   { command id - MENU_ID_BASE -> TMenuItem }
  MenuForms: array[0..MAX_MENU_IDS - 1] of Pointer;   { ... and the form whose menu holds it }
  MenuNext: Integer;
  { per form: the control that fills the client area, the header strip, the
    paint box that should get the keyboard }
  LayForm, LayClient, LayHeader, LayFocus: array[0..31] of Pointer;
  LayHeaderH: array[0..31] of Integer;
  LayN: Integer;

{ ---- strings --------------------------------------------------------------- }

procedure ToW(const s: string; var w: TWBuf);
var n: LongInt;
begin
  if Length(s) = 0 then
  begin
    SetLength(w, 1);
    w[0] := #0;
    Exit;
  end;
  n := MultiByteToWideChar(CP_UTF8, 0, PChar(s), Length(s), nil, 0);
  SetLength(w, n + 1);
  MultiByteToWideChar(CP_UTF8, 0, PChar(s), Length(s), @w[0], n);
  w[n] := #0;
end;

function FromW(w: PWideChar): string;
var n: LongInt; s: string;
begin
  s := '';
  if w <> nil then
  begin
    n := WideCharToMultiByte(CP_UTF8, 0, w, -1, nil, 0, nil, nil);
    if n > 1 then
    begin
      SetLength(s, n - 1);
      WideCharToMultiByte(CP_UTF8, 0, w, -1, @s[1], n - 1, nil, nil);
    end;
  end;
  Result := s;
end;

procedure ASCIIW(var a: array of WideChar; const s: string);
var i: Integer;
begin
  for i := 1 to Length(s) do a[i - 1] := WideChar(Ord(s[i]));
  a[Length(s)] := #0;
end;

{ A window's text, as UTF-8. }
function WindowText(h: Pointer): string;
var w: TWBuf; n: LongInt;
begin
  n := GetWindowTextLengthW(h);
  SetLength(w, n + 1);
  w[0] := #0;
  GetWindowTextW(h, @w[0], n + 1);
  Result := FromW(@w[0]);
end;

{ LF -> CRLF for an edit control, which shows a bare LF as nothing. }
function ToCRLF(const s: string): string;
var i: Integer; r: string;
begin
  r := '';
  for i := 1 to Length(s) do
  begin
    if (s[i] = #10) and ((i = 1) or (s[i - 1] <> #13)) then r := r + #13;
    r := r + s[i];
  end;
  Result := r;
end;

function FromCRLF(const s: string): string;
var i: Integer; r: string;
begin
  r := '';
  for i := 1 to Length(s) do
    if s[i] <> #13 then r := r + s[i];
  Result := r;
end;

{ ---- RTTI helpers (as in gtk3widgets) --------------------------------------- }

function GetInstanceClassName(inst: Pointer): string;
var reg: PRegistry; entries: PRTTIEntry; vmt: Pointer; i: Integer;
begin
  Result := '';
  if inst = nil then Exit;
  vmt := PPointer(inst)^;
  reg := __rttireg();
  if reg = nil then Exit;
  entries := @reg^.Dummy;
  for i := 0 to Integer(reg^.Count) - 1 do
    if entries[i].RTTIPtr^.VMTPtr = vmt then
    begin
      Result := entries[i].NamePtr^;
      Exit;
    end;
end;

function IsSubclassOf(cls: PClassRTTI; const ABaseName: string): Boolean;
var curr: PClassRTTI;
begin
  Result := False;
  curr := cls;
  while curr <> nil do
  begin
    if curr^.NamePtr^ = ABaseName then begin Result := True; Exit; end;
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
end;

function IsA(inst: Pointer; const ABaseName: string): Boolean;
begin
  Result := (inst <> nil) and IsSubclassOf(GetClass(GetInstanceClassName(inst)), ABaseName);
end;

{ Method calls into PCL handlers. pxx code calls itself with the System V
  convention on every target, Windows included (only DLL boundaries use
  Microsoft's), so these are gtk3widgets' dispatchers unchanged. }
procedure CallMethod(code: Pointer; data: Pointer; sender: Pointer);
begin
  asm
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rdi, data
    mov rsi, sender
    mov rax, code
    mov r11, rsp
    db 72, 131, 228, 240   { and rsp, -16 }
    sub rsp, 8
    push r11
    db 255, 208
    pop r11
    mov rsp, r11
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
  end;
end;

procedure CallPaintMethod(code: Pointer; data: Pointer; sender: Pointer; canvas: Pointer);
begin
  asm
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rdi, data
    mov rsi, sender
    mov rdx, canvas
    mov rax, code
    mov r11, rsp
    db 72, 131, 228, 240   { and rsp, -16 }
    sub rsp, 8
    push r11
    db 255, 208
    pop r11
    mov rsp, r11
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
  end;
end;

procedure CallMouseMethod(code: Pointer; data: Pointer; sender: Pointer; button, x, y: Integer);
begin
  asm
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rdi, data
    mov rsi, sender
    mov edx, button
    mov ecx, x
    mov r8d, y
    mov rax, code
    mov r11, rsp
    db 72, 131, 228, 240   { and rsp, -16 }
    sub rsp, 8
    push r11
    db 255, 208            { call rax }
    pop r11
    mov rsp, r11
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
  end;
end;

{ Fire a published `procedure(Sender: TObject) of object` by NAME. }
procedure FireNamedEvent(inst: Pointer; const AName: string);
var m: TMethod; p: PPropInfo; cls: PClassRTTI;
begin
  cls := GetClass(GetInstanceClassName(inst));
  p := GetPropInfo(cls, AName);
  if p = nil then Exit;
  m := GetMethodProp(inst, p);
  if m.Code <> nil then CallMethod(m.Code, m.Data, inst);
end;

{ ---- windows and their controls ------------------------------------------- }

function CtlOf(h: Pointer): TControl;
begin
  if h = nil then Result := nil
  else Result := TControl(Pointer(GetWindowLongPtrW(h, GWLP_USERDATA)));
end;

procedure Bind(h: Pointer; ctl: TComponent);
begin
  if h <> nil then SetWindowLongPtrW(h, GWLP_USERDATA, Int64(Pointer(ctl)));
end;

function LayIndex(form: Pointer; create: Boolean): Integer;
var i: Integer;
begin
  Result := -1;
  for i := 0 to LayN - 1 do
    if LayForm[i] = form then begin Result := i; Exit; end;
  if create and (LayN < 32) then
  begin
    Result := LayN;
    LayForm[LayN] := form;
    LayClient[LayN] := nil; LayHeader[LayN] := nil; LayFocus[LayN] := nil;
    LayHeaderH[LayN] := 0;
    LayN := LayN + 1;
  end;
end;

{ Re-lay a form's client and header controls to its client area. }
procedure FormLayout(form: Pointer);
var k: Integer; r: TWRect; hh: Integer;
begin
  k := LayIndex(form, False);
  if k < 0 then Exit;
  r.l := 0; r.t := 0; r.r := 0; r.b := 0;
  GetClientRect(form, r);
  hh := LayHeaderH[k];
  if LayHeader[k] <> nil then
  begin
    if hh = 0 then hh := CtlOf(LayHeader[k]).Height;
    MoveWindow(LayHeader[k], 0, 0, r.r, hh, 1);
  end;
  if LayClient[k] <> nil then
    MoveWindow(LayClient[k], 0, hh, r.r, r.b - hh, 1);
end;

function NewChild(cls: PWideChar; style, ex: LongWord; ctl: TComponent): Pointer;
begin
  Result := CreateWindowExW(ex, cls, nil, WS_CHILD or WS_VISIBLE or style, 0, 0, 80, 24,
                            Parking, nil, Inst, nil);
  Bind(Result, ctl);
  if Result <> nil then SendMessageW(Result, WM_SETFONT, Int64(GetStockObject(17)), 0);   { DEFAULT_GUI_FONT }
end;

{ GDK keyvals for the keys that have no character. }
function VkToKeyval(vk: Int64): Integer;
begin
  case vk of
    $25: Result := $FF51;   { Left }
    $26: Result := $FF52;   { Up }
    $27: Result := $FF53;   { Right }
    $28: Result := $FF54;   { Down }
    $24: Result := $FF50;   { Home }
    $23: Result := $FF57;   { End }
    $21: Result := $FF55;   { Page Up }
    $22: Result := $FF56;   { Page Down }
    $2D: Result := $FF63;   { Insert }
    $2E: Result := $FFFF;   { Delete }
  else
    if (vk >= $70) and (vk <= $7B) then Result := $FFBE + (vk - $70)   { F1..F12 }
    else Result := 0;
  end;
end;

procedure FireKey(ctl: TControl; keyval: Integer);
var m: TMethod;
begin
  if (ctl = nil) or (keyval = 0) then Exit;
  m := ctl.OnKeyDown;
  if m.Code <> nil then CallMouseMethod(m.Code, m.Data, Pointer(ctl), keyval, 0, 0);
end;

procedure FireMouse(ctl: TControl; which: Integer; button: Integer; lp: Int64);
var m: TMethod; x, y: Integer;
begin
  if ctl = nil then Exit;
  x := SmallInt(lp and $FFFF);
  y := SmallInt((lp shr 16) and $FFFF);
  if which = 0 then m := ctl.OnMouseDown
  else if which = 1 then m := ctl.OnMouseUp
  else m := ctl.OnMouseMove;
  if m.Code <> nil then CallMouseMethod(m.Code, m.Data, Pointer(ctl), button, x, y);
end;

procedure PaintBoxPaint(h: Pointer; pb: TPaintBox);
var ps: TPaintStruct; dc, mem, bmp, old: Pointer; r: TWRect; m: TMethod;
begin
  dc := BeginPaint(h, ps);
  r.l := 0; r.t := 0; r.r := 0; r.b := 0;
  GetClientRect(h, r);
  if (r.r > 0) and (r.b > 0) then
  begin
    mem := CreateCompatibleDC(dc);
    bmp := CreateCompatibleBitmap(dc, r.r, r.b);
    old := SelectObject(mem, bmp);
    m := pb.OnPaint;
    if m.Code <> nil then
    begin
      pb.Canvas.Handle := mem;
      CallPaintMethod(m.Code, m.Data, Pointer(pb), Pointer(pb.Canvas));
      pb.Canvas.Handle := nil;
    end;
    BitBlt(dc, 0, 0, r.r, r.b, mem, 0, 0, SRCCOPY);
    SelectObject(mem, old);
    DeleteObject(bmp);
    DeleteDC(mem);
  end;
  EndPaint(h, ps);
end;

{ WM_COMMAND from a child control or a menu. }
procedure OnCommand(wp, lp: Int64);
var code, id: Int64; child: Pointer; ctl: TControl; p: PPropInfo; cls: PClassRTTI; m: TMethod; it: TMenuItem;
begin
  code := (wp shr 16) and $FFFF;
  id := wp and $FFFF;
  if lp = 0 then
  begin
    { a menu item }
    if (id >= MENU_ID_BASE) and (id < MENU_ID_BASE + MAX_MENU_IDS) then
    begin
      it := TMenuItem(MenuItems[id - MENU_ID_BASE]);
      if it <> nil then
      begin
        m := it.OnClick;
        if m.Code <> nil then CallMethod(m.Code, m.Data, Pointer(it));
      end;
    end;
    Exit;
  end;
  child := Pointer(lp);
  ctl := CtlOf(child);
  if ctl = nil then Exit;
  cls := GetClass(GetInstanceClassName(Pointer(ctl)));
  if IsSubclassOf(cls, 'TCheckBox') then
  begin
    if code = BN_CLICKED then
    begin
      p := GetPropInfo(cls, 'Checked');
      if p <> nil then SetOrdProp(Pointer(ctl), p, SendMessageW(child, BM_GETCHECK, 0, 0) and 1);
      FireNamedEvent(Pointer(ctl), 'OnChange');
      m := ctl.OnClick;
      if m.Code <> nil then CallMethod(m.Code, m.Data, Pointer(ctl));
    end;
  end
  else if IsSubclassOf(cls, 'TButton') then
  begin
    if code = BN_CLICKED then
    begin
      m := ctl.OnClick;
      if m.Code <> nil then CallMethod(m.Code, m.Data, Pointer(ctl));
    end;
  end
  else if IsSubclassOf(cls, 'TListBox') then
  begin
    if code = LBN_SELCHANGE then
    begin
      m := ctl.OnClick;
      if m.Code <> nil then CallMethod(m.Code, m.Data, Pointer(ctl));
      FireNamedEvent(Pointer(ctl), 'OnChange');
    end;
  end
  else if IsSubclassOf(cls, 'TComboBox') then
  begin
    if code = CBN_SELCHANGE then FireNamedEvent(Pointer(ctl), 'OnChange');
  end
  else if IsSubclassOf(cls, 'TEdit') then
  begin
    if code = EN_CHANGE then
    begin
      p := GetPropInfo(cls, 'Text');
      if p <> nil then SetStrProp(Pointer(ctl), p, WindowText(child));
      FireNamedEvent(Pointer(ctl), 'OnChange');
    end;
  end;
end;

procedure OnTimerMsg(id: Int64);
var k: Integer; data: Pointer; p: PPropInfo; cls: PClassRTTI;
begin
  for k := 0 to MAX_TIMERS - 1 do
    if TimerIds[k] = id then
    begin
      data := TimerData[k];
      FireNamedEvent(data, 'OnTimer');
      { a TTimer whose Enabled went false in its own handler stops, as the GTK
        set's source does by returning 0 }
      cls := GetClass(GetInstanceClassName(data));
      p := GetPropInfo(cls, 'Enabled');
      if (p <> nil) and (GetOrdProp(data, p) = 0) and (TimerIds[k] = id) then
      begin
        KillTimer(Parking, id);
        TimerIds[k] := 0;
      end;
      Exit;
    end;
end;

{ The one window procedure for forms, panels, paint boxes and the parking
  window. `stdcall`: Windows calls it, so its address is the Microsoft-
  convention adapter (winabi PxxWinCallback). }
function PxxWndProc(h: Pointer; msg: LongWord; wp, lp: Int64): Int64; stdcall;
var ctl: TControl; m: TMethod; k: Integer; isPaint: Boolean;
begin
  Result := 0;
  ctl := CtlOf(h);
  isPaint := (ctl <> nil) and IsA(Pointer(ctl), 'TPaintBox');
  case msg of
    WM_COMMAND: OnCommand(wp, lp);
    WM_TIMER: if h = Parking then OnTimerMsg(wp) else Result := DefWindowProcW(h, msg, wp, lp);
    WM_PAINT:
      if isPaint then PaintBoxPaint(h, TPaintBox(ctl))
      else Result := DefWindowProcW(h, msg, wp, lp);
    WM_ERASEBKGND:
      if isPaint then Result := 1                     { the paint covers it: no flicker }
      else Result := DefWindowProcW(h, msg, wp, lp);
    WM_SIZE:
      begin
        if (ctl <> nil) and IsA(Pointer(ctl), 'TForm') then FormLayout(h);
        if ctl <> nil then
        begin
          m := ctl.OnResize;
          if m.Code <> nil then
            CallMouseMethod(m.Code, m.Data, Pointer(ctl), Integer(lp and $FFFF), Integer((lp shr 16) and $FFFF), 0);
        end;
      end;
    WM_SETFOCUS:
      begin
        k := LayIndex(h, False);
        if (k >= 0) and (LayFocus[k] <> nil) then SetFocus(LayFocus[k]);
      end;
    WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN:
      begin
        if isPaint then begin SetFocus(h); SetCapture(h); end;
        if msg = WM_LBUTTONDOWN then FireMouse(ctl, 0, 1, lp)
        else if msg = WM_MBUTTONDOWN then FireMouse(ctl, 0, 2, lp)
        else FireMouse(ctl, 0, 3, lp);
      end;
    WM_LBUTTONUP, WM_RBUTTONUP, WM_MBUTTONUP:
      begin
        if isPaint then ReleaseCapture;
        if msg = WM_LBUTTONUP then FireMouse(ctl, 1, 1, lp)
        else if msg = WM_MBUTTONUP then FireMouse(ctl, 1, 2, lp)
        else FireMouse(ctl, 1, 3, lp);
      end;
    WM_MOUSEMOVE: FireMouse(ctl, 2, 0, lp);
    WM_KEYDOWN:
      begin
        FireKey(ctl, VkToKeyval(wp));
        Result := DefWindowProcW(h, msg, wp, lp);
      end;
    WM_CHAR:
      begin
        { Enter, Escape, Backspace, Tab as GDK keyvals; characters as themselves }
        if (wp = 13) or (wp = 27) or (wp = 8) or (wp = 9) then FireKey(ctl, $FF00 or Integer(wp))
        else if wp >= 32 then FireKey(ctl, Integer(wp));
      end;
    WM_DESTROY:
      if (h = MainForm) and (MainForm <> nil) then
      begin
        MainForm := nil;
        PostQuitMessage(0);
      end;
  else
    Result := DefWindowProcW(h, msg, wp, lp);
  end;
end;

procedure RegisterOne(var name: array of WideChar; const s: string; brush: Int64; cursor: Boolean);
var wc: TWndClassExW;
begin
  ASCIIW(name, s);
  FillChar(wc, SizeOf(wc), 0);
  wc.cbSize := SizeOf(wc);
  wc.style := 3;                                   { CS_VREDRAW | CS_HREDRAW }
  wc.lpfnWndProc := @PxxWndProc;
  wc.hInstance := Inst;
  if cursor then wc.hCursor := LoadCursorW(nil, 32512);   { IDC_ARROW }
  wc.hbrBackground := Pointer(brush);
  wc.lpszClassName := @name[0];
  RegisterClassExW(wc);
end;

{ ---- the widgetset ---------------------------------------------------------- }

procedure TWin32WidgetSet.AppInit;
begin
  if Inst <> nil then Exit;
  Inst := GetModuleHandleW(nil);
  RegisterOne(ClsForm, 'PxxForm', 16, True);       { COLOR_BTNFACE + 1 }
  RegisterOne(ClsPanel, 'PxxPanel', 16, True);
  RegisterOne(ClsPaint, 'PxxPaint', 0, True);
  RegisterOne(ClsParking, 'PxxParking', 0, False);
  Parking := CreateWindowExW(0, @ClsParking[0], nil, WS_OVERLAPPEDWINDOW, 0, 0, 10, 10, nil, nil, Inst, nil);
end;

procedure TWin32WidgetSet.AppRun;
var msg: TWMsg;
begin
  while GetMessageW(msg, nil, 0, 0) > 0 do
  begin
    TranslateMessage(msg);
    DispatchMessageW(msg);
  end;
end;

procedure TWin32WidgetSet.AppQuit;
begin
  PostQuitMessage(0);
end;

function TWin32WidgetSet.CreateForm(AForm: TComponent): Pointer;
begin
  Result := CreateWindowExW(0, @ClsForm[0], nil, WS_OVERLAPPEDWINDOW or WS_CLIPCHILDREN,
                            CW_USEDEFAULT, CW_USEDEFAULT, 320, 240, nil, nil, Inst, nil);
  Bind(Result, AForm);
end;

function TWin32WidgetSet.CreateButton(AButton: TComponent): Pointer;
var cls: array[0..15] of WideChar;
begin
  ASCIIW(cls, 'BUTTON');
  Result := NewChild(@cls[0], WS_TABSTOP, 0, AButton);                     { BS_PUSHBUTTON }
end;

function TWin32WidgetSet.CreateLabel(ALabel: TComponent): Pointer;
var cls: array[0..15] of WideChar;
begin
  ASCIIW(cls, 'STATIC');
  Result := NewChild(@cls[0], 0, 0, ALabel);                               { SS_LEFT }
end;

function TWin32WidgetSet.CreateEdit(AEdit: TComponent): Pointer;
var cls: array[0..15] of WideChar;
begin
  ASCIIW(cls, 'EDIT');
  Result := NewChild(@cls[0], WS_TABSTOP or $80, WS_EX_CLIENTEDGE, AEdit); { ES_AUTOHSCROLL }
end;

function TWin32WidgetSet.CreateCheckBox(ACheckBox: TComponent): Pointer;
var cls: array[0..15] of WideChar;
begin
  ASCIIW(cls, 'BUTTON');
  Result := NewChild(@cls[0], WS_TABSTOP or 3, 0, ACheckBox);              { BS_AUTOCHECKBOX }
end;

function TWin32WidgetSet.CreatePanel(APanel: TComponent): Pointer;
begin
  Result := NewChild(@ClsPanel[0], WS_CLIPCHILDREN, WS_EX_CLIENTEDGE, APanel);
end;

function TWin32WidgetSet.CreateMemo(AMemo: TComponent): Pointer;
var cls: array[0..15] of WideChar;
begin
  ASCIIW(cls, 'EDIT');
  { ES_MULTILINE | ES_AUTOVSCROLL | ES_AUTOHSCROLL | ES_WANTRETURN }
  Result := NewChild(@cls[0], WS_TABSTOP or WS_VSCROLL or WS_HSCROLL or $4 or $40 or $80 or $1000,
                     WS_EX_CLIENTEDGE, AMemo);
end;

function TWin32WidgetSet.CreateListBox(AListBox: TComponent): Pointer;
var cls: array[0..15] of WideChar;
begin
  ASCIIW(cls, 'LISTBOX');
  Result := NewChild(@cls[0], WS_TABSTOP or WS_VSCROLL or 1, WS_EX_CLIENTEDGE, AListBox);   { LBS_NOTIFY }
end;

function TWin32WidgetSet.CreateComboBox(AComboBox: TComponent): Pointer;
var cls: array[0..15] of WideChar;
begin
  ASCIIW(cls, 'COMBOBOX');
  Result := NewChild(@cls[0], WS_TABSTOP or WS_VSCROLL or 3, 0, AComboBox);   { CBS_DROPDOWNLIST }
end;

function TWin32WidgetSet.CreatePaintBox(APaintBox: TComponent): Pointer;
begin
  Result := NewChild(@ClsPaint[0], WS_TABSTOP, 0, APaintBox);
end;

procedure TWin32WidgetSet.SetText(AControl: TComponent; const AText: string);
var h: Pointer; w: TWBuf;
begin
  h := TControl(AControl).Handle;
  if h = nil then Exit;
  if IsA(Pointer(AControl), 'TMemo') then ToW(ToCRLF(AText), w) else ToW(AText, w);
  { Unchanged text is not set again, as gtk_entry_set_text does not emit
    "changed" for it. An edit's EN_CHANGE stores the text back through
    TEdit.Text, whose setter lands here; ReactOS sends EN_CHANGE even for the
    same text (Wine does not), and without this check the two recurse until
    the stack is gone. }
  if FromW(@w[0]) = WindowText(h) then Exit;
  SetWindowTextW(h, @w[0]);
end;

procedure TWin32WidgetSet.Invalidate(AControl: TComponent);
var h: Pointer;
begin
  if AControl = nil then Exit;
  h := TControl(AControl).Handle;
  if h <> nil then InvalidateRect(h, nil, 0);
end;

procedure TWin32WidgetSet.SetBounds(AControl: TComponent; ALeft, ATop, AWidth, AHeight: Integer);
var h: Pointer; r, wr: TWRect; flags: LongWord; w, hh: Integer;
begin
  h := TControl(AControl).Handle;
  if h = nil then Exit;
  if IsA(Pointer(AControl), 'TForm') then
  begin
    if (AWidth <= 0) or (AHeight <= 0) then Exit;
    { the client size asked for, menu bar included (see the unit header) }
    r.l := 0; r.t := 0; r.r := AWidth; r.b := AHeight;
    AdjustWindowRectEx(r, WS_OVERLAPPEDWINDOW, 0, 0);
    flags := SWP_NOZORDER or SWP_NOACTIVATE;
    if (ALeft = 0) and (ATop = 0) then flags := flags or SWP_NOMOVE;
    SetWindowPos(h, nil, ALeft, ATop, r.r - r.l, r.b - r.t, flags);
    Exit;
  end;
  w := AWidth; hh := AHeight;
  if (w <= 0) or (hh <= 0) then
  begin
    wr.l := 0; wr.t := 0; wr.r := 0; wr.b := 0;
    GetWindowRect(h, wr);
    if w <= 0 then w := wr.r - wr.l;
    if hh <= 0 then hh := wr.b - wr.t;
  end;
  if IsA(Pointer(AControl), 'TComboBox') then hh := hh + 200;   { the drop-down list }
  MoveWindow(h, ALeft, ATop, w, hh, 1);
end;

procedure TWin32WidgetSet.SetParent(AControl: TComponent; AParent: TComponent);
var ch, ph: Pointer; ctl: TControl; k: Integer;
begin
  ctl := TControl(AControl);
  ch := ctl.Handle;
  ph := TControl(AParent).Handle;
  if (ch = nil) or (ph = nil) then Exit;
  SetParentW(ch, ph);
  SetBounds(AControl, ctl.Left, ctl.Top, ctl.Width, ctl.Height);
  if IsA(Pointer(AControl), 'TPaintBox') and IsA(Pointer(AParent), 'TForm') then
  begin
    k := LayIndex(ph, True);
    if k >= 0 then LayFocus[k] := ch;
  end;
end;

procedure TWin32WidgetSet.ShowWidget(AControl: TComponent);
var h: Pointer; k: Integer;
begin
  h := TControl(AControl).Handle;
  if h = nil then Exit;
  ShowWindow(h, 5);                                { SW_SHOW }
  UpdateWindow(h);
  k := LayIndex(h, False);
  if (k >= 0) and (LayFocus[k] <> nil) then SetFocus(LayFocus[k]);
end;

{ Clicks and changes are routed for every control from WM_COMMAND (OnCommand);
  there is nothing to connect. }
procedure TWin32WidgetSet.ConnectClick(AControl: TComponent); begin end;
procedure TWin32WidgetSet.ConnectChange(AControl: TComponent); begin end;

procedure TWin32WidgetSet.ConnectAppQuit(AForm: TComponent);
begin
  MainForm := TControl(AForm).Handle;
end;

procedure TWin32WidgetSet.SetChecked(AControl: TComponent; AChecked: Boolean);
var h: Pointer;
begin
  h := TControl(AControl).Handle;
  if h <> nil then SendMessageW(h, BM_SETCHECK, Ord(AChecked), 0);
end;

function TWin32WidgetSet.GetChecked(AControl: TComponent): Boolean;
var h: Pointer;
begin
  h := TControl(AControl).Handle;
  Result := (h <> nil) and ((SendMessageW(h, BM_GETCHECK, 0, 0) and 1) <> 0);
end;

function TWin32WidgetSet.GetMemoText(AMemo: TComponent): string;
var h: Pointer;
begin
  h := TControl(AMemo).Handle;
  if h = nil then Result := '' else Result := FromCRLF(WindowText(h));
end;

procedure TWin32WidgetSet.SetMemoText(AMemo: TComponent; const AText: string);
var h: Pointer; w: TWBuf;
begin
  h := TControl(AMemo).Handle;
  if h = nil then Exit;
  ToW(ToCRLF(AText), w);
  SetWindowTextW(h, @w[0]);
end;

procedure TWin32WidgetSet.MemoCaretToLine(AMemo: TComponent; line: Integer);
var h: Pointer; pos: Int64;
begin
  h := TControl(AMemo).Handle;
  if h = nil then Exit;
  pos := SendMessageW(h, EM_LINEINDEX, line, 0);
  if pos < 0 then Exit;
  SendMessageW(h, EM_SETSEL, pos, pos);
  SendMessageW(h, EM_SCROLLCARET, 0, 0);
end;

function TWin32WidgetSet.MemoCaretLine(AMemo: TComponent): Integer;
var h: Pointer;
begin
  h := TControl(AMemo).Handle;
  if h = nil then Result := 0
  else Result := SendMessageW(h, EM_LINEFROMCHAR, -1, 0);
end;

function TWin32WidgetSet.AddListItem(AListBox: TComponent; const AText: string): Pointer;
var h: Pointer; w: TWBuf; row: PListRow;
begin
  Result := nil;
  h := TControl(AListBox).Handle;
  if h = nil then Exit;
  ToW(AText, w);
  SendMessageW(h, LB_ADDSTRING, 0, Int64(@w[0]));
  { TListBox clears by destroying the rows it was handed; a Win32 list has no
    row windows, so the row is a marker that empties its list }
  New(row);
  row^.magic := ROW_MAGIC;
  row^.list := h;
  Result := row;
end;

function TWin32WidgetSet.GetListIndex(AListBox: TComponent): Integer;
var h: Pointer;
begin
  h := TControl(AListBox).Handle;
  if h = nil then Result := -1 else Result := SendMessageW(h, LB_GETCURSEL, 0, 0);
end;

procedure TWin32WidgetSet.SetListIndex(AListBox: TComponent; AIndex: Integer);
var h: Pointer;
begin
  h := TControl(AListBox).Handle;
  if h <> nil then SendMessageW(h, LB_SETCURSEL, AIndex, 0);
end;

procedure TWin32WidgetSet.ClearList(AListBox: TComponent);
var h: Pointer;
begin
  h := TControl(AListBox).Handle;
  if h <> nil then SendMessageW(h, LB_RESETCONTENT, 0, 0);
end;

procedure TWin32WidgetSet.DestroyWidget(AWidget: Pointer);
var row: PListRow;
begin
  if AWidget = nil then Exit;
  row := PListRow(AWidget);
  if row^.magic = ROW_MAGIC then
  begin
    SendMessageW(row^.list, LB_RESETCONTENT, 0, 0);
    row^.magic := 0;
    Dispose(row);
    Exit;
  end;
  DestroyWindow(AWidget);
end;

{ 'Pascal|*.pas;*.inc|All files|*' -> the NUL-separated, NUL-NUL-ended form
  comdlg32 takes. }
procedure FilterW(const AFilter: string; var w: TWBuf);
var s: string; i, n: Integer;
begin
  s := AFilter;
  if s = '' then s := 'All files|*';
  ToW(s + '||', w);
  n := Length(w);
  for i := 0 to n - 1 do
    if w[i] = '|' then w[i] := #0;
end;

function TWin32WidgetSet.ChooseFile(AMode: TChooserMode;
                                    const ATitle, AInitialDir, AFileName, AFilter: string): string;
var ofn: TOpenFileNameW; fileBuf: array[0..1023] of WideChar; fw, tw, dw, nw: TWBuf; i: Integer; ok: LongInt;
begin
  Result := '';
  if AMode = cmSelectFolder then Exit;             { not yet: SHBrowseForFolder }
  FilterW(AFilter, fw);
  ToW(ATitle, tw);
  ToW(AInitialDir, dw);
  ToW(AFileName, nw);
  for i := 0 to 1023 do fileBuf[i] := #0;
  i := 0;
  while (i < Length(nw) - 1) and (i < 1023) do begin fileBuf[i] := nw[i]; i := i + 1; end;
  FillChar(ofn, SizeOf(ofn), 0);
  ofn.lStructSize := SizeOf(ofn);
  ofn.hwndOwner := MainForm;
  ofn.lpstrFilter := @fw[0];
  ofn.nFilterIndex := 1;
  ofn.lpstrFile := @fileBuf[0];
  ofn.nMaxFile := 1024;
  if AInitialDir <> '' then ofn.lpstrInitialDir := @dw[0];
  if ATitle <> '' then ofn.lpstrTitle := @tw[0];
  if AMode = cmSaveFile then
  begin
    ofn.Flags := $2 or $800;                       { OFN_OVERWRITEPROMPT | OFN_PATHMUSTEXIST }
    ok := GetSaveFileNameW(ofn);
  end
  else
  begin
    ofn.Flags := $1000 or $800;                    { OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST }
    ok := GetOpenFileNameW(ofn);
  end;
  if ok <> 0 then Result := FromW(@fileBuf[0]);
end;

procedure TWin32WidgetSet.AddComboItem(AComboBox: TComponent; const AText: string);
var h: Pointer; w: TWBuf;
begin
  h := TControl(AComboBox).Handle;
  if h = nil then Exit;
  ToW(AText, w);
  SendMessageW(h, CB_ADDSTRING, 0, Int64(@w[0]));
end;

function TWin32WidgetSet.GetActiveIndex(AComboBox: TComponent): Integer;
var h: Pointer;
begin
  h := TControl(AComboBox).Handle;
  if h = nil then Result := -1 else Result := SendMessageW(h, CB_GETCURSEL, 0, 0);
end;

procedure TWin32WidgetSet.SetActiveIndex(AComboBox: TComponent; AIndex: Integer);
var h: Pointer;
begin
  h := TControl(AComboBox).Handle;
  if h <> nil then SendMessageW(h, CB_SETCURSEL, AIndex, 0);
end;

procedure TWin32WidgetSet.ClearCombo(AComboBox: TComponent);
var h: Pointer;
begin
  h := TControl(AComboBox).Handle;
  if h <> nil then SendMessageW(h, CB_RESETCONTENT, 0, 0);
end;

function TWin32WidgetSet.StartTimer(AInterval: Integer; ACallback: Pointer; AData: Pointer): LongWord;
var k: Integer;
begin
  Result := 0;
  if Parking = nil then Exit;
  for k := 0 to MAX_TIMERS - 1 do
    if TimerIds[k] = 0 then
    begin
      TimerIds[k] := TimerNext;
      TimerData[k] := AData;
      TimerNext := TimerNext + 1;
      if AInterval < 1 then AInterval := 1;
      SetTimer(Parking, TimerIds[k], AInterval, nil);
      Result := TimerIds[k];
      Exit;
    end;
end;

procedure TWin32WidgetSet.StopTimer(AId: LongWord);
var k: Integer;
begin
  if AId = 0 then Exit;
  for k := 0 to MAX_TIMERS - 1 do
    if TimerIds[k] = AId then
    begin
      KillTimer(Parking, AId);
      TimerIds[k] := 0;
    end;
end;

{ Append item's children to the menu hm, giving each leaf a command id. }
procedure BuildMenu(hm: Pointer; parent: TMenuItem; form: Pointer);
var i: Integer; it: TMenuItem; sub: Pointer; w: TWBuf; flags: LongWord; id: Integer;
begin
  for i := 0 to parent.Count - 1 do
  begin
    it := parent.Item(i);
    if not it.Visible then Continue;
    if it.Caption = '-' then
    begin
      AppendMenuW(hm, MF_SEPARATOR, 0, nil);
      Continue;
    end;
    ToW(it.Caption, w);                            { `&` marks the mnemonic, as in Win32 itself }
    flags := MF_STRING;
    if not it.Enabled then flags := flags or MF_GRAYED;
    if it.Count > 0 then
    begin
      sub := CreatePopupMenu;
      BuildMenu(sub, it, form);
      AppendMenuW(hm, flags or MF_POPUP, Int64(sub), @w[0]);
      it.Handle := nil;
    end
    else
    begin
      id := -1;
      if MenuNext < MAX_MENU_IDS then
      begin
        id := MenuNext;
        MenuNext := MenuNext + 1;
        MenuItems[id] := Pointer(it);
        MenuForms[id] := form;
      end;
      if id >= 0 then
      begin
        AppendMenuW(hm, flags, MENU_ID_BASE + id, @w[0]);
        it.Handle := Pointer(Int64(MENU_ID_BASE + id));
      end;
    end;
  end;
end;

function TWin32WidgetSet.SetFormMenu(AForm: TComponent; AMenu: TComponent): Integer;
var h, old, bar: Pointer; menu: TMainMenu; i: Integer;
begin
  Result := 0;
  h := TControl(AForm).Handle;
  menu := TMainMenu(AMenu);
  if (h = nil) or (menu = nil) then Exit;
  { Realize re-applies the menu: drop the ids the old bar held }
  for i := 0 to MAX_MENU_IDS - 1 do
    if MenuForms[i] = h then begin MenuItems[i] := nil; MenuForms[i] := nil; end;
  old := GetMenu(h);
  bar := CreateMenu;
  BuildMenu(bar, menu.Items, h);
  SetMenu(h, bar);
  if old <> nil then DestroyMenu(old);
  DrawMenuBar(h);
end;

procedure TWin32WidgetSet.SetMenuItemEnabled(AItem: TComponent; AEnabled: Boolean);
var it: TMenuItem; id: Int64; form: Pointer; flags: LongWord;
begin
  it := TMenuItem(AItem);
  if (it = nil) or (it.Handle = nil) then Exit;
  id := Int64(it.Handle);
  if (id < MENU_ID_BASE) or (id >= MENU_ID_BASE + MAX_MENU_IDS) then Exit;
  form := MenuForms[id - MENU_ID_BASE];
  if form = nil then Exit;
  if AEnabled then flags := MF_BYCOMMAND else flags := MF_BYCOMMAND or MF_GRAYED;
  EnableMenuItem(GetMenu(form), id, flags);
  DrawMenuBar(form);
end;

{ A Win32 menu has no hidden items; Visible is applied when the bar is built,
  which Realize does. }
procedure TWin32WidgetSet.SetMenuItemVisible(AItem: TComponent; AVisible: Boolean); begin end;

procedure TWin32WidgetSet.SetFormClient(AForm: TComponent; AControl: TComponent; AHeaderHeight: Integer);
var k: Integer;
begin
  k := LayIndex(TControl(AForm).Handle, True);
  if k < 0 then Exit;
  LayClient[k] := TControl(AControl).Handle;
  LayHeaderH[k] := AHeaderHeight;
  FormLayout(TControl(AForm).Handle);
end;

procedure TWin32WidgetSet.SetFormHeader(AForm: TComponent; AControl: TComponent);
var k: Integer;
begin
  k := LayIndex(TControl(AForm).Handle, True);
  if k < 0 then Exit;
  LayHeader[k] := TControl(AControl).Handle;
  FormLayout(TControl(AForm).Handle);
end;

procedure TWin32WidgetSet.ShowHandle(AWidget: Pointer);
begin
  if AWidget <> nil then ShowWindow(AWidget, 5);
end;

procedure TWin32WidgetSet.HideHandle(AWidget: Pointer);
begin
  if AWidget <> nil then ShowWindow(AWidget, 0);
end;

function TWin32WidgetSet.HandleWidth(AWidget: Pointer): Integer;
var r: TWRect;
begin
  Result := 0;
  if AWidget = nil then Exit;
  r.l := 0; r.t := 0; r.r := 0; r.b := 0;
  GetClientRect(AWidget, r);
  Result := r.r;
end;

function TWin32WidgetSet.HandleHeight(AWidget: Pointer): Integer;
var r: TWRect;
begin
  Result := 0;
  if AWidget = nil then Exit;
  r.l := 0; r.t := 0; r.r := 0; r.b := 0;
  GetClientRect(AWidget, r);
  Result := r.b;
end;

procedure TWin32WidgetSet.MessageBox(const AText: string);
var w, t: TWBuf;
begin
  ToW(AText, w);
  ToW('Message', t);
  MessageBoxW(MainForm, @w[0], @t[0], $40);        { MB_ICONINFORMATION | MB_OK }
end;

{ MessageBoxW runs its own modal loop that this unit cannot reach into; the
  GTK set's test hook has no Win32 counterpart yet. }
procedure TWin32WidgetSet.DismissModal; begin end;

initialization
  WidgetSet := TWin32WidgetSet.Create;
end.
