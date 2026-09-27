{ SPDX-License-Identifier: Zlib }
unit gtk3widgets;

{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
interface

uses classes_lite, uwidgetset;

type
  TGtk3WidgetSet = class(TWidgetSet)
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
    procedure SetMenuItemEnabled(AItem: TComponent; AEnabled: Boolean); override;
    procedure SetMenuItemVisible(AItem: TComponent; AVisible: Boolean); override;

    { ---- the sealed seam (feature-pcl-seam-seal) ---- }
    procedure ShowHandle(AWidget: Pointer); override;
    procedure HideHandle(AWidget: Pointer); override;
    function HandleWidth(AWidget: Pointer): Integer; override;
    function HandleHeight(AWidget: Pointer): Integer; override;

    function CreatePaned(AVertical: Boolean): Pointer; override;
    procedure PanedSetPosition(APaned: Pointer; APos: Integer); override;
    function PanedGetPosition(APaned: Pointer): Integer; override;
    function PanedChild(APaned: Pointer; APane: Integer): Pointer; override;

    function CreateBox(AVertical: Boolean; ASpacing: Integer): Pointer; override;
    procedure BoxPack(ABox, AChild: Pointer; AExpand, AFill: Boolean; APadding: Integer); override;

    function CreateToolBar(AToolBar: TComponent): Pointer; override;
    procedure SetLabelEllipsis(ALabel: TComponent; AOn: Boolean); override;
    procedure ToolBarAddSeparator(AToolBar: TComponent); override;
    procedure SetFormHeader(AForm: TComponent; AControl: TComponent); override;
    function CreateTreeView(ATree: TComponent): Pointer; override;
    function TreeAdd(ATree: TComponent; const AParent, AText: string): string; override;
    procedure TreeClear(ATree: TComponent); override;
    procedure TreeExpand(ATree: TComponent; const ANode: string; ADeep: Boolean); override;
    procedure TreeCollapse(ATree: TComponent; const ANode: string); override;
    procedure TreeSetText(ATree: TComponent; const ANode, AText: string); override;
    function TreeSelected(ATree: TComponent): string; override;
    procedure TreeSelect(ATree: TComponent; const ANode: string); override;

    function CreateNotebook: Pointer; override;
    function NotebookAddPage(ANotebook: Pointer; const ACaption: string): Pointer; override;
    function NotebookGetPage(ANotebook: Pointer): Integer; override;
    procedure NotebookSetPage(ANotebook: Pointer; AIndex: Integer); override;

    procedure MessageBox(const AText: string); override;
    procedure DismissModal; override;


  end;

implementation

uses gtk3_c, gtk3, controls, typinfo, graphics, extctrls, menus;

var
  { The dialog gtk_dialog_run is currently spinning on, so a test harness can
    tear it down from a timer. Lives here now rather than in dialogs.pas —
    the handle is GTK's, so it belongs to the GTK widgetset. }
  ActiveDialogHandle: Pointer;

function PCharToStr(p: Pointer): string;
var
  s: string;
  c: PChar;
begin
  s := '';
  if p <> nil then
  begin
    c := p;
    while c^ <> #0 do
    begin
      s := s + c^;
      p := p + 1;
      c := p;
    end;
  end;
  Result := s;
end;

function PointerToString(p: Pointer): string;
var
  val: Int64;
  s: string;
  digit: Integer;
begin
  val := Int64(p);
  s := '';
  if val = 0 then
  begin
    Result := '0';
    Exit;
  end;
  while val > 0 do
  begin
    digit := val mod 16;
    if digit < 10 then
      s := Chr(48 + digit) + s
    else
      s := Chr(55 + digit) + s;
    val := val div 16;
  end;
  Result := s;
end;

function StringToPointer(const s: string): Pointer;
var
  val: Int64;
  i, digit: Integer;
begin
  val := 0;
  for i := 1 to Length(s) do
  begin
    digit := Ord(s[i]);
    if (digit >= 48) and (digit <= 57) then
      val := val * 16 + (digit - 48)
    else if (digit >= 65) and (digit <= 70) then
      val := val * 16 + (digit - 55)
    else if (digit >= 97) and (digit <= 102) then
      val := val * 16 + (digit - 87);
  end;
  Result := Pointer(val);
end;

function GetSubStr(const s: string; start: Integer): string;
var
  i: Integer;
  r: string;
begin
  r := '';
  for i := start to Length(s) do
    r := r + s[i];
  Result := r;
end;

function GetVBoxPtr(win: Pointer): Pointer;
var
  namePtr: Pointer;
  s: string;
begin
  Result := nil;
  namePtr := gtk_widget_get_name(win);
  if namePtr <> nil then
  begin
    s := PCharToStr(namePtr);
    if (Length(s) > 5) and (s[1] = 'V') and (s[2] = 'B') and (s[3] = 'O') and (s[4] = 'X') and (s[5] = '_') then
    begin
      Result := StringToPointer(GetSubStr(s, 6));
    end;
  end;
end;

procedure SetVBoxPtr(win: Pointer; vbox: Pointer);
var
  s: string;
begin
  if vbox = nil then
    gtk_widget_set_name(win, PChar(''))
  else
  begin
    s := 'VBOX_' + PointerToString(vbox);
    gtk_widget_set_name(win, PChar(s));
  end;
end;

{ GetMenuBarPtr/SetMenuBarPtr USED TO LIVE HERE AND COULD NEVER HAVE WORKED.
  They stored the menubar pointer in the vbox's widget NAME -- the same single
  slot GetFixedPtr/SetFixedPtr use for the fixed container, as SetFormMenu's
  own comment says. Only one prefix can be in a name at a time, SetFixedPtr
  wins (CreateForm calls it), and SetMenuBarPtr was never called by anything,
  so GetMenuBarPtr answered nil for every form that has ever existed. Deleted
  rather than left as a working-looking helper: verified 2026-09-27 that
  SetMenuBarPtr had no callers at all and GetMenuBarPtr none either. Whoever
  needs "is there a menu bar" should ask GTK -- HasMenuBarFirst below does.
  bug-b-a-getter-whose-setter-is-never-called-answers-nil-forever }

{ Is the vbox's first child a GtkMenuBar? Asked of GTK by TYPE, because the
  answer has to survive a form that never set a menu and a form that did. }
function HasMenuBarFirst(vbox: Pointer): Boolean;
var lst, first: Pointer;
begin
  HasMenuBarFirst := False;
  if vbox = nil then Exit;
  lst := gtk_container_get_children(vbox);
  if lst = nil then Exit;
  first := g_list_nth_data(lst, 0);
  if (first <> nil)
     and (g_type_check_instance_is_a(first, gtk_menu_bar_get_type) <> 0) then
    HasMenuBarFirst := True;
  g_list_free(lst);
end;

function GetFixedPtr(widget: Pointer): Pointer;
var
  namePtr: Pointer;
  s: string;
begin
  Result := nil;
  namePtr := gtk_widget_get_name(widget);
  if namePtr <> nil then
  begin
    s := PCharToStr(namePtr);
    if (Length(s) > 6) and (s[1] = 'F') and (s[2] = 'I') and (s[3] = 'X') and (s[4] = 'E') and (s[5] = 'D') and (s[6] = '_') then
      Result := StringToPointer(GetSubStr(s, 7));
  end;
end;

procedure SetFixedPtr(widget: Pointer; fixed: Pointer);
var
  s: string;
begin
  if fixed = nil then
    gtk_widget_set_name(widget, PChar(''))
  else
  begin
    s := 'FIXED_' + PointerToString(fixed);
    gtk_widget_set_name(widget, PChar(s));
  end;
end;

function GetContainerFixed(ph: Pointer; cls: PClassRTTI): Pointer;
var
  vbox: Pointer;
begin
  if IsSubclassOf(cls, 'TForm') then
  begin
    vbox := GetVBoxPtr(ph);
    if vbox <> nil then
      Result := GetFixedPtr(vbox)
    else
      Result := GetFixedPtr(ph);
  end
  else if IsSubclassOf(cls, 'TPanel') then
  begin
    Result := GetFixedPtr(ph);
  end
  else
    Result := ph;
end;

function GetInstanceClassName(inst: Pointer): string;
var
  reg: PRegistry;
  entries: PRTTIEntry;
  vmt: Pointer;
  i: Integer;
begin
  Result := '';
  if inst = nil then Exit;
  vmt := PPointer(inst)^;
  reg := __rttireg();
  if reg = nil then Exit;
  entries := @reg^.Dummy;
  for i := 0 to Integer(reg^.Count) - 1 do
  begin
    if entries[i].RTTIPtr^.VMTPtr = vmt then
    begin
      Result := entries[i].NamePtr^;
      Exit;
    end;
  end;
end;

function IsSubclassOf(cls: PClassRTTI; const ABaseName: string): Boolean;
var
  curr: PClassRTTI;
begin
  Result := False;
  curr := cls;
  while curr <> nil do
  begin
    if curr^.NamePtr^ = ABaseName then
    begin
      Result := True;
      Exit;
    end;
    curr := PClassRTTI(curr^.ParentRTTI);
  end;
end;

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

procedure ControlClickTramp(widget: Pointer; userdata: Pointer); cdecl;
var ctl: TControl; m: TMethod;
begin
  ctl := userdata;
  m := ctl.OnClick;
  if m.Code <> nil then
    CallMethod(m.Code, m.Data, userdata);
end;

{ Fire a published `procedure(Sender: TObject) of object` by NAME, if the
  class has one and it is assigned. The by-name route is what lets a control
  carry an event the seam knows nothing about. }
procedure FireNamedEvent(userdata: Pointer; const AName: string);
var m: TMethod; p: PPropInfo; cls: PClassRTTI;
begin
  cls := GetClass(GetInstanceClassName(userdata));
  p := GetPropInfo(cls, AName);
  if p = nil then Exit;
  m := GetMethodProp(userdata, p);
  if m.Code <> nil then
    CallMethod(m.Code, m.Data, userdata);
end;

{ GtkListBox 'row-selected' passes (listbox, row, userdata). A cleared
  selection passes nil and is not a pick.

  BOTH OnClick and OnChange fire, and that is a FIX, not belt and braces.
  TListBox published an OnChange that nothing ever called: eliah's .lfm binds
  OnClick and works, espide bound OnChange and its tree was DEAD -- clicking a
  file selected the row and never opened it (seen on a screenshot 2026-09-27,
  the row highlighted and the editor empty). A published event that silently
  does nothing is worse than an absent one, because the caller has no way to
  find out. Assigning both is harmless: a caller sets one. }
procedure ListBoxRowSelectedTramp(widget: Pointer; row: Pointer; userdata: Pointer); cdecl;
var ctl: TControl; m: TMethod;
begin
  if row = nil then Exit;
  ctl := userdata;
  m := ctl.OnClick;
  if m.Code <> nil then
    CallMethod(m.Code, m.Data, userdata);
  FireNamedEvent(userdata, 'OnChange');
end;

{ Dispatch a method procedure(Sender; Button, X, Y: Integer) of object: SysV
  rdi=Self(data), rsi=Sender, edx=Button, ecx=X, r8d=Y. }
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

function ControlMouseDownTramp(widget: Pointer; event: Pointer; userdata: Pointer): Integer; cdecl;
var ctl: TControl; m: TMethod; btn: LongWord; xd, yd: Double; r: Integer;
begin
  ctl := userdata;
  m := ctl.OnMouseDown;
  if m.Code <> nil then
  begin
    btn := 0; xd := 0; yd := 0;
    r := gdk_event_get_button(event, @btn);
    r := gdk_event_get_coords(event, @xd, @yd);
    CallMouseMethod(m.Code, m.Data, userdata, Integer(btn), Trunc(xd), Trunc(yd));
  end;
  ControlMouseDownTramp := 0;   { 0 = let the event propagate }
end;

function ControlMouseUpTramp(widget: Pointer; event: Pointer; userdata: Pointer): Integer; cdecl;
var ctl: TControl; m: TMethod; btn: LongWord; xd, yd: Double; r: Integer;
begin
  ctl := userdata;
  m := ctl.OnMouseUp;
  if m.Code <> nil then
  begin
    btn := 0; xd := 0; yd := 0;
    r := gdk_event_get_button(event, @btn);
    r := gdk_event_get_coords(event, @xd, @yd);
    CallMouseMethod(m.Code, m.Data, userdata, Integer(btn), Trunc(xd), Trunc(yd));
  end;
  ControlMouseUpTramp := 0;
end;

function ControlMouseMoveTramp(widget: Pointer; event: Pointer; userdata: Pointer): Integer; cdecl;
var ctl: TControl; m: TMethod; xd, yd: Double; r: Integer;
begin
  ctl := userdata;
  m := ctl.OnMouseMove;
  if m.Code <> nil then
  begin
    xd := 0; yd := 0;
    r := gdk_event_get_coords(event, @xd, @yd);
    CallMouseMethod(m.Code, m.Data, userdata, 0, Trunc(xd), Trunc(yd));
  end;
  ControlMouseMoveTramp := 0;
end;

function ControlKeyDownTramp(widget: Pointer; event: Pointer; userdata: Pointer): Integer; cdecl;
var ctl: TControl; m: TMethod; keyval: LongWord; r: Integer;
begin
  ctl := userdata;
  m := ctl.OnKeyDown;
  if m.Code <> nil then
  begin
    keyval := 0;
    r := gdk_event_get_keyval(event, @keyval);
    { reuse the mouse dispatcher: the handler procedure(Sender; Key) reads the
      first int (edx); the extra slots are ignored. }
    CallMouseMethod(m.Code, m.Data, userdata, Integer(keyval), 0, 0);
  end;
  ControlKeyDownTramp := 0;
end;

type PInt = ^Integer;

procedure ControlSizeAllocateTramp(widget: Pointer; alloc: Pointer; userdata: Pointer); cdecl;
var ctl: TControl; m: TMethod; w, h: Integer;
begin
  ctl := userdata;
  m := ctl.OnResize;
  if m.Code <> nil then
  begin
    { GtkAllocation is gint x,y,width,height -> width at offset 8, height at 12 }
    w := PInt(Pointer(Int64(alloc) + 8))^;
    h := PInt(Pointer(Int64(alloc) + 12))^;
    CallMouseMethod(m.Code, m.Data, userdata, w, h, 0);
  end;
end;

procedure MenuItemActivateTramp(widget: Pointer; userdata: Pointer); cdecl;
var item: TMenuItem; m: TMethod;
begin
  item := TMenuItem(userdata);
  m := item.OnClick;
  if m.Code <> nil then
    CallMethod(m.Code, m.Data, userdata);
end;

function ControlDrawTramp(widget: Pointer; cr: Pointer; userdata: Pointer): Boolean; cdecl;
var
  ctl: TControl;
  paintBox: TPaintBox;
  m: TMethod;
  cls: PClassRTTI;
begin
  asm
    push rbx
    push r12
    push r13
    push r14
    push r15
  end;
  Result := False;
  ctl := TControl(userdata);
  cls := GetClass(GetInstanceClassName(userdata));
  if IsSubclassOf(cls, 'TPaintBox') then
  begin
    paintBox := TPaintBox(userdata);
    paintBox.Canvas.Handle := cr;
    m := paintBox.OnPaint;
    if m.Code <> nil then
    begin
      CallPaintMethod(m.Code, m.Data, userdata, Pointer(paintBox.Canvas));
    end;
    paintBox.Canvas.Handle := nil;
  end;
  asm
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
  end;
end;

procedure ControlToggleTramp(widget: Pointer; userdata: Pointer); cdecl;
var
  ctl: TControl;
  m: TMethod;
  p: PPropInfo;
  cls: PClassRTTI;
begin
  ctl := userdata;
  cls := GetClass(GetInstanceClassName(userdata));
  p := GetPropInfo(cls, 'Checked');
  if p <> nil then
  begin
    if gtk_toggle_button_get_active(widget) <> 0 then
      SetOrdProp(userdata, p, 1)
    else
      SetOrdProp(userdata, p, 0);
  end;
    
  p := GetPropInfo(cls, 'OnChange');
  if p <> nil then
  begin
    m := GetMethodProp(userdata, p);
    if m.Code <> nil then
      CallMethod(m.Code, m.Data, userdata);
  end;
end;

procedure ControlChangeTramp(widget: Pointer; userdata: Pointer); cdecl;
var
  ctl: TControl;
  m: TMethod;
  p: PPropInfo;
  cls: PClassRTTI;
  textPtr: Pointer;
begin
  ctl := userdata;
  cls := GetClass(GetInstanceClassName(userdata));
  p := GetPropInfo(cls, 'Text');
  textPtr := gtk_entry_get_text(widget);
  if (p <> nil) and (textPtr <> nil) then
    SetStrProp(userdata, p, PCharToStr(textPtr));
    
  p := GetPropInfo(cls, 'OnChange');
  if p <> nil then
  begin
    m := GetMethodProp(userdata, p);
    if m.Code <> nil then
      CallMethod(m.Code, m.Data, userdata);
  end;
end;

procedure TGtk3WidgetSet.AppInit;
begin
  gtk_init(nil, nil);
end;

procedure TGtk3WidgetSet.AppRun;
begin
  gtk_main;
end;

procedure TGtk3WidgetSet.AppQuit;
begin
  gtk_main_quit;
end;

function TGtk3WidgetSet.CreateForm(AForm: TComponent): Pointer;
var win, vbox, fixed: Pointer;
begin
  win := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_default_size(win, 320, 240);
  { GTK's own default, stated rather than assumed: a form that could not be
    resized was diagnosed at this line twice before the cause turned out to be a
    size request in SetBounds, so the explicit call is worth the byte. }
  gtk_window_set_resizable(win, 1);
  vbox := gtk_box_new(1, 0);
  gtk_container_add(win, vbox);
  SetVBoxPtr(win, vbox);
  fixed := gtk_fixed_new();
  gtk_box_pack_start(vbox, fixed, 1, 1, 0);
  SetFixedPtr(vbox, fixed);
  { fire the form's OnResize with the content area's new allocation so apps can
    reflow their panes (the fixed container is where child widgets are placed) }
  SignalConnectData(fixed, 'size-allocate', @ControlSizeAllocateTramp, Pointer(AForm));
  Result := win;
end;

function TGtk3WidgetSet.CreateButton(AButton: TComponent): Pointer;
begin
  Result := gtk_button_new_with_label(PChar(''));
end;

function TGtk3WidgetSet.CreateLabel(ALabel: TComponent): Pointer;
begin
  Result := gtk_label_new(PChar(''));
  { LEFT-ALIGNED, like Delphi's and Lazarus' TLabel. GTK centres a label in
    whatever space it is given, which is invisible in a GtkFixed -- the label
    gets exactly its natural size there -- and wrong the moment one is packed
    in a box, where it drifts to the middle of the row. }
  gtk_label_set_xalign(Result, 0.0);
end;

function TGtk3WidgetSet.CreateEdit(AEdit: TComponent): Pointer;
begin
  Result := gtk_entry_new();
end;

function TGtk3WidgetSet.CreateCheckBox(ACheckBox: TComponent): Pointer;
begin
  Result := gtk_check_button_new_with_label(PChar(''));
end;

function TGtk3WidgetSet.CreatePanel(APanel: TComponent): Pointer;
var frame, fixed: Pointer;
begin
  frame := gtk_frame_new(nil);
  fixed := gtk_fixed_new();
  gtk_container_add(frame, fixed);
  Result := frame;
end;

procedure TGtk3WidgetSet.SetText(AControl: TComponent; const AText: string);
var h: Pointer; className: string; ctl: TControl; cls: PClassRTTI; p: PChar;
begin
  ctl := TControl(AControl);
  h := ctl.Handle;
  if h = nil then Exit;

  { PChar of an empty AnsiString now yields a static #0 pointer (never nil), so
    gtk_*_set_text sees a valid empty C string with no guard — see
    devdocs/progress/done/bug-pchar-empty-managed-string-nil.md. }
  p := PChar(AText);

  className := GetInstanceClassName(Pointer(AControl));
  cls := GetClass(className);
  if IsSubclassOf(cls, 'TForm') then
    gtk_window_set_title(h, p)
  else if IsSubclassOf(cls, 'TButton') then
    gtk_button_set_label(h, p)
  else if IsSubclassOf(cls, 'TLabel') then
    gtk_label_set_text(h, p)
  else if IsSubclassOf(cls, 'TEdit') then
    gtk_entry_set_text(h, p)
  else if IsSubclassOf(cls, 'TCheckBox') then
    gtk_button_set_label(h, p)
  else if IsSubclassOf(cls, 'TPanel') then
    { A TPanel's handle is a GtkFrame, not a button. This was
      gtk_button_set_label, which GTK rejects with
      `assertion 'GTK_IS_BUTTON (button)' failed` on stderr and no caption --
      found 2026-09-27 by a test that constructs a panel and reads it back, not
      by anyone looking at a panel. A GTK-CRITICAL is not a crash, so it had
      survived in plain sight. }
    gtk_frame_set_label(h, p);
end;

procedure TGtk3WidgetSet.Invalidate(AControl: TComponent);
var
  ctl: TControl;
  h: Pointer;
begin
  if AControl = nil then Exit;
  ctl := TControl(AControl);
  h := ctl.Handle;
  if h <> nil then
    gtk_widget_queue_draw(h);
end;

procedure TGtk3WidgetSet.SetBounds(AControl: TComponent; ALeft, ATop, AWidth, AHeight: Integer);
var
  ch, ph, container: Pointer;
  ctl: TControl;
  pctl: TControl;
  cls: PClassRTTI;
begin
  ctl := TControl(AControl);
  ch := ctl.Handle;
  if ch = nil then Exit;

  { A FORM IS A WINDOW, AND A WINDOW'S SIZE IS NOT A SIZE REQUEST.
    gtk_widget_set_size_request sets a MINIMUM, so `Form.SetBounds(0,0,1100,720)`
    used to mean "this window may never be smaller than 1100x720" -- which is
    what "the window cannot be freely resized" looks like from outside. The
    window manager owns a toplevel's size; we state the size we want it to OPEN
    at and leave the user free after that. gtk_window_resize in addition, and
    only once realized, so an app that resizes a window already on screen still
    works. }
  if IsSubclassOf(GetClass(GetInstanceClassName(Pointer(ctl))), 'TForm') then
  begin
    if (AWidth > 0) and (AHeight > 0) then
    begin
      gtk_window_set_default_size(ch, AWidth, AHeight);
      if gtk_widget_get_realized(ch) <> 0 then
        gtk_window_resize(ch, AWidth, AHeight);
    end;
    Exit;
  end;

  if (AWidth > 0) or (AHeight > 0) then
    gtk_widget_set_size_request(ch, AWidth, AHeight);

  if ctl.Parent <> nil then
  begin
    pctl := ctl.Parent;
    ph := pctl.Handle;
    if ph <> nil then
    begin
      cls := GetClass(GetInstanceClassName(Pointer(pctl)));
      if IsSubclassOf(cls, 'TForm') or IsSubclassOf(cls, 'TPanel') then
      begin
        container := GetContainerFixed(ph, cls);
        if (container <> nil) and (gtk_widget_get_parent(ch) = container) then
          gtk_fixed_move(container, ch, ALeft, ATop);
      end;
    end;
  end;
end;

procedure TGtk3WidgetSet.SetParent(AControl: TComponent; AParent: TComponent);
var
  ch, ph, container, lst: Pointer;
  ctl: TControl;
  pctl: TControl;
  cls: PClassRTTI;
  prop: PPropInfo;
  n: LongWord;
  expandRest: Integer;
begin
  ctl := TControl(AControl);
  pctl := TControl(AParent);
  ch := ctl.Handle;
  ph := pctl.Handle;
  if (ch = nil) or (ph = nil) then Exit;

  cls := GetClass(GetInstanceClassName(Pointer(pctl)));

  { TPaned: two children, no absolute coords. First child fills pack1, second
    fills pack2; the draggable handle sits between them. resize=1 (child grows
    with the paned), shrink=0 (respect the child's size request). A re-parent
    (Realize re-entry) where the child is already in this paned is a no-op. }
  if IsSubclassOf(cls, 'TPaned') then
  begin
    if gtk_widget_get_parent(ch) = ph then Exit;
    if gtk_paned_get_child1(ph) = nil then
      gtk_paned_pack1(ph, ch, 1, 0)
    else if gtk_paned_get_child2(ph) = nil then
      gtk_paned_pack2(ph, ch, 1, 0);
    Exit;
  end;

  { TBox: gtk_box, any number of children, packed in Add order along its axis.
    Header-then-content when ExpandRest (the default): the first child keeps
    its natural size and every later one expands to fill the rest, which is
    what a header strip above a content area wants. ExpandRest=False packs
    every child at its natural size -- a row of buttons, a stack of fields. }
  if IsSubclassOf(cls, 'TBox') then
  begin
    if gtk_widget_get_parent(ch) = ph then Exit;
    lst := gtk_container_get_children(ph);
    n := g_list_length(lst);
    if lst <> nil then g_list_free(lst);
    expandRest := 1;
    prop := GetPropInfo(cls, 'ExpandRest');
    if (prop <> nil) and (GetOrdProp(Pointer(pctl), prop) = 0) then expandRest := 0;
    if (n = 0) or (expandRest = 0) then
      gtk_box_pack_start(ph, ch, 0, 0, 0)
    else
      gtk_box_pack_start(ph, ch, 1, 1, 0);
    Exit;
  end;

  { TToolBar: a GtkToolbar takes GtkToolItems and nothing else, so an ordinary
    widget is WRAPPED in one -- which is how a GtkEntry or a GtkComboBox gets
    into a real toolbar too. The wrapper is what GTK moves into the overflow
    menu when the row no longer fits, so it is not a formality. }
  if IsSubclassOf(cls, 'TToolBar') then
  begin
    { the caption is the overflow menu's label, and only a BUTTON gets one --
      see ToolBarWrapAndInsert for why the others must stay in the row }
    if IsSubclassOf(GetClass(GetInstanceClassName(Pointer(ctl))), 'TButton') then
      ToolBarWrapAndInsert(ph, ch, ctl.Caption)
    else
      ToolBarWrapAndInsert(ph, ch, '');
    Exit;
  end;

  container := GetContainerFixed(ph, cls);
  if container = nil then Exit;

  { Realize re-parents children, so a widget may already be in the container;
    re-putting it trips gtk_fixed_put's 'parent == NULL' assertion. Move instead. }
  if gtk_widget_get_parent(ch) = container then
    gtk_fixed_move(container, ch, ctl.Left, ctl.Top)
  else
    gtk_fixed_put(container, ch, ctl.Left, ctl.Top);
end;

procedure TGtk3WidgetSet.ShowWidget(AControl: TComponent);
var h: Pointer; ctl: TControl;
begin
  ctl := TControl(AControl);
  h := ctl.Handle;
  if h <> nil then
    gtk_widget_show_all(h);
end;

procedure TGtk3WidgetSet.ConnectClick(AControl: TComponent);
var h: Pointer; ctl: TControl;
begin
  ctl := TControl(AControl);
  h := ctl.Handle;
  if h <> nil then
    SignalConnectData(h, 'clicked', @ControlClickTramp, Pointer(AControl));
end;

procedure AppDestroy(widget: Pointer; data: Pointer); cdecl;
begin
  WidgetSet.AppQuit;
end;

procedure TGtk3WidgetSet.ConnectAppQuit(AForm: TComponent);
var h: Pointer; ctl: TControl;
begin
  ctl := TControl(AForm);
  h := ctl.Handle;
  if h <> nil then
    SignalConnect(h, 'destroy', @AppDestroy);
end;

procedure TGtk3WidgetSet.ConnectChange(AControl: TComponent);
var h: Pointer; className: string; ctl: TControl; cls: PClassRTTI;
begin
  ctl := TControl(AControl);
  h := ctl.Handle;
  if h = nil then Exit;
  
  className := GetInstanceClassName(Pointer(AControl));
  cls := GetClass(className);
  if IsSubclassOf(cls, 'TEdit') then
    SignalConnectData(h, 'changed', @ControlChangeTramp, Pointer(AControl))
  else if IsSubclassOf(cls, 'TCheckBox') then
    SignalConnectData(h, 'toggled', @ControlToggleTramp, Pointer(AControl));
end;

procedure TGtk3WidgetSet.SetChecked(AControl: TComponent; AChecked: Boolean);
var h: Pointer; val: Integer; current: Boolean; ctl: TControl;
begin
  ctl := TControl(AControl);
  h := ctl.Handle;
  if h = nil then Exit;
  
  if AChecked then val := 1 else val := 0;
  current := GetChecked(AControl);
  if current <> AChecked then
    gtk_toggle_button_set_active(h, val);
end;

function TGtk3WidgetSet.GetChecked(AControl: TComponent): Boolean;
var h: Pointer; ctl: TControl;
begin
  ctl := TControl(AControl);
  h := ctl.Handle;
  if (h <> nil) and (gtk_toggle_button_get_active(h) <> 0) then
    Result := True
  else
    Result := False;
end;

function TimerTramp(userdata: Pointer): Integer; cdecl;
var
  m: TMethod;
  p: PPropInfo;
  cls: PClassRTTI;
  enabledVal: Int64;
begin
  cls := GetClass(GetInstanceClassName(userdata));
  p := GetPropInfo(cls, 'OnTimer');
  if p <> nil then
  begin
    m := GetMethodProp(userdata, p);
    if m.Code <> nil then
      CallMethod(m.Code, m.Data, userdata);
  end;
  
  p := GetPropInfo(cls, 'Enabled');
  if p <> nil then
  begin
    enabledVal := GetOrdProp(userdata, p);
    if enabledVal <> 0 then
      Result := 1
    else
      Result := 0;
  end
  else
    Result := 0;
end;

function TGtk3WidgetSet.StartTimer(AInterval: Integer; ACallback: Pointer; AData: Pointer): LongWord;
begin
  Result := g_timeout_add(AInterval, @TimerTramp, AData);
end;

procedure TGtk3WidgetSet.StopTimer(AId: LongWord);
begin
  if AId <> 0 then
    g_source_remove(AId);
end;

function TGtk3WidgetSet.CreateMemo(AMemo: TComponent): Pointer;
var scroll, tv: Pointer;
begin
  scroll := gtk_scrolled_window_new(nil, nil);
  gtk_scrolled_window_set_policy(scroll, GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
  gtk_scrolled_window_set_shadow_type(scroll, 1);   { GTK_SHADOW_IN: a visible border }
  tv := gtk_text_view_new();
  gtk_container_add(scroll, tv);
  Result := scroll;
end;

function TGtk3WidgetSet.CreateListBox(AListBox: TComponent): Pointer;
begin
  Result := gtk_list_box_new();
  { fire OnClick on row selection (OnClick is read live at signal time) }
  SignalConnectData(Result, 'row-selected', @ListBoxRowSelectedTramp, Pointer(AListBox));
end;

function TGtk3WidgetSet.CreateComboBox(AComboBox: TComponent): Pointer;
begin
  Result := gtk_combo_box_text_new();
end;

function TGtk3WidgetSet.CreatePaintBox(APaintBox: TComponent): Pointer;
begin
  Result := gtk_drawing_area_new();
  SignalConnectData(Result, 'draw', @ControlDrawTramp, Pointer(APaintBox));
  { request pointer events and route them to the OnMouse* handlers.
    masks: BUTTON_PRESS(256) | BUTTON_RELEASE(512) | POINTER_MOTION(4) = 772 }
  gtk_widget_add_events(Result, 772 or 1024);   { + KEY_PRESS_MASK(1024) }
  SignalConnectData(Result, 'button-press-event',   @ControlMouseDownTramp, Pointer(APaintBox));
  SignalConnectData(Result, 'button-release-event', @ControlMouseUpTramp,   Pointer(APaintBox));
  SignalConnectData(Result, 'motion-notify-event',  @ControlMouseMoveTramp, Pointer(APaintBox));
  { keyboard: make the drawing area focusable + route key presses }
  gtk_widget_set_can_focus(Result, 1);
  SignalConnectData(Result, 'key-press-event',      @ControlKeyDownTramp,   Pointer(APaintBox));
  SignalConnectData(Result, 'size-allocate',        @ControlSizeAllocateTramp, Pointer(APaintBox));
end;

function TGtk3WidgetSet.GetMemoText(AMemo: TComponent): string;
var
  h, tv, buf: Pointer;
  startIter, endIter: array[0..19] of Pointer;
  textPtr: Pointer;
  ctl: TControl;
begin
  ctl := TControl(AMemo);
  h := ctl.Handle;
  if h = nil then begin Result := ''; Exit; end;
  tv := gtk_bin_get_child(h);
  buf := gtk_text_view_get_buffer(tv);
  gtk_text_buffer_get_start_iter(buf, @startIter);
  gtk_text_buffer_get_end_iter(buf, @endIter);
  textPtr := gtk_text_buffer_get_text(buf, @startIter, @endIter, 0);
  Result := PCharToStr(textPtr);
end;

procedure TGtk3WidgetSet.SetMemoText(AMemo: TComponent; const AText: string);
var
  h, tv, buf: Pointer;
  ctl: TControl;
begin
  ctl := TControl(AMemo);
  h := ctl.Handle;
  if h = nil then Exit;
  tv := gtk_bin_get_child(h);
  buf := gtk_text_view_get_buffer(tv);
  gtk_text_buffer_set_text(buf, PChar(AText), -1);
end;

procedure TGtk3WidgetSet.MemoCaretToLine(AMemo: TComponent; line: Integer);
var
  h, tv, buf, mark: Pointer;
  iter: array[0..19] of Pointer;   { GtkTextIter blob, as in GetMemoText }
  ctl: TControl;
begin
  ctl := TControl(AMemo);
  h := ctl.Handle;
  if h = nil then Exit;
  tv := gtk_bin_get_child(h);
  buf := gtk_text_view_get_buffer(tv);
  gtk_text_buffer_get_iter_at_line(buf, @iter, line);
  gtk_text_buffer_place_cursor(buf, @iter);
  mark := gtk_text_buffer_get_insert(buf);
  gtk_text_view_scroll_mark_onscreen(tv, mark);
end;

function TGtk3WidgetSet.MemoCaretLine(AMemo: TComponent): Integer;
var
  h, tv, buf, mark: Pointer;
  iter: array[0..19] of Pointer;   { GtkTextIter blob, as in MemoCaretToLine }
  ctl: TControl;
begin
  MemoCaretLine := 0;
  ctl := TControl(AMemo);
  h := ctl.Handle;
  if h = nil then Exit;
  tv := gtk_bin_get_child(h);
  buf := gtk_text_view_get_buffer(tv);
  mark := gtk_text_buffer_get_insert(buf);
  gtk_text_buffer_get_iter_at_mark(buf, @iter, mark);
  MemoCaretLine := gtk_text_iter_get_line(@iter);
end;

function TGtk3WidgetSet.AddListItem(AListBox: TComponent; const AText: string): Pointer;
var
  h, row, label_: Pointer;
  ctl: TControl;
begin
  ctl := TControl(AListBox);
  h := ctl.Handle;
  if h = nil then begin Result := nil; Exit; end;
  row := gtk_list_box_row_new();
  label_ := gtk_label_new(PChar(AText));
  gtk_widget_set_halign(label_, 1);   { GTK_ALIGN_START: left-align row text }
  gtk_container_add(row, label_);
  gtk_list_box_insert(h, row, -1);
  gtk_widget_show_all(row);
  Result := row;
end;

function TGtk3WidgetSet.GetListIndex(AListBox: TComponent): Integer;
var
  h, row: Pointer;
  ctl: TControl;
begin
  ctl := TControl(AListBox);
  h := ctl.Handle;
  if h = nil then begin Result := -1; Exit; end;
  row := gtk_list_box_get_selected_row(h);
  if row = nil then
    Result := -1
  else
    Result := gtk_list_box_row_get_index(row);
end;

procedure TGtk3WidgetSet.SetListIndex(AListBox: TComponent; AIndex: Integer);
var
  h, row: Pointer;
  ctl: TControl;
begin
  ctl := TControl(AListBox);
  h := ctl.Handle;
  if h = nil then Exit;
  if AIndex < 0 then
    gtk_list_box_select_row(h, nil)
  else
  begin
    row := gtk_list_box_get_row_at_index(h, AIndex);
    if row <> nil then
      gtk_list_box_select_row(h, row);
  end;
end;

{ One group of a Delphi-shaped filter: a description and its ';'-separated
  patterns, e.g. ('Pascal', '*.pas;*.inc'). File-level and not nested, because
  the pinned compiler has no nested routines. }
procedure AddOneChooserFilter(dlg: Pointer; const ADesc, APatterns: string);
var filt: Pointer; pat: string; j: Integer;
begin
  if APatterns = '' then Exit;
  filt := gtk_file_filter_new;
  gtk_file_filter_set_name(filt, PC(ADesc + ' (' + APatterns + ')'));
  pat := '';
  for j := 1 to Length(APatterns) + 1 do
  begin
    if (j > Length(APatterns)) or (APatterns[j] = ';') then
    begin
      if pat <> '' then gtk_file_filter_add_pattern(filt, PC(pat));
      pat := '';
    end
    else
      pat := pat + APatterns[j];
  end;
  gtk_file_chooser_add_filter(dlg, filt);
end;

{ 'Pascal|*.pas;*.inc|All files|*' -> two filters, in order.

  A trailing description with no patterns is DROPPED, not refused. A modal the
  caller has not opened yet cannot report an error anywhere the caller will
  see it, and a chooser that is missing one filter is still a working chooser;
  refusing would turn a typo in a literal into a dead File menu. }
procedure AddChooserFilters(dlg: Pointer; const AFilter: string);
var i, fieldIdx: Integer; cur, desc: string;
begin
  if AFilter = '' then Exit;
  fieldIdx := 0;
  cur := '';
  desc := '';
  for i := 1 to Length(AFilter) + 1 do
  begin
    if (i > Length(AFilter)) or (AFilter[i] = '|') then
    begin
      if (fieldIdx mod 2) = 0 then
        desc := cur
      else
        AddOneChooserFilter(dlg, desc, cur);
      fieldIdx := fieldIdx + 1;
      cur := '';
    end
    else
      cur := cur + AFilter[i];
  end;
end;

function TGtk3WidgetSet.ChooseFile(AMode: TChooserMode;
  const ATitle, AInitialDir, AFileName, AFilter: string): string;
var dlg, fname: Pointer; resp, act: Integer; accept: string;
begin
  Result := '';
  if AMode = cmSaveFile then
  begin
    act := GTK_FILE_CHOOSER_ACTION_SAVE;
    accept := 'Save';
  end
  else if AMode = cmSelectFolder then
  begin
    act := GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER;
    accept := 'Open';
  end
  else
  begin
    act := GTK_FILE_CHOOSER_ACTION_OPEN;
    accept := 'Open';
  end;

  { gtk_file_chooser_dialog_new is VARIADIC and its button list is the tail,
    which pxx's C import drops (bug-a-c-header-import-drops-the-variadic-tail)
    -- so the buttons go on afterwards, one gtk_dialog_add_button each. }
  dlg := gtk_file_chooser_dialog_new(PC(ATitle), nil, act, nil);
  gtk_dialog_add_button(dlg, PC('Cancel'), GTK_RESPONSE_CANCEL);
  gtk_dialog_add_button(dlg, PC(accept), GTK_RESPONSE_ACCEPT);

  if AInitialDir <> '' then
    gtk_file_chooser_set_current_folder(dlg, PC(AInitialDir));
  if AFileName <> '' then
  begin
    { set_current_name fills the name BOX (a file that need not exist);
      set_filename selects an existing one. Using the wrong one for the mode
      silently does nothing, which is why the branch is here and not at the
      call sites. }
    if AMode = cmSaveFile then
      gtk_file_chooser_set_current_name(dlg, PC(AFileName))
    else
      gtk_file_chooser_set_filename(dlg, PC(AFileName));
  end;
  if AMode = cmSaveFile then
    gtk_file_chooser_set_do_overwrite_confirmation(dlg, 1);
  AddChooserFilters(dlg, AFilter);

  { The same slot MessageBox uses: one modal at a time, one DismissModal. }
  ActiveDialogHandle := dlg;
  resp := gtk_dialog_run(dlg);
  { If a harness dismissed it from a timer the widget is already destroyed and
    gtk_dialog_run returned GTK_RESPONSE_NONE, so the handle check is not
    tidiness -- reading the filename off dlg there is a use-after-free. }
  if (ActiveDialogHandle = dlg) and (resp = GTK_RESPONSE_ACCEPT) then
  begin
    fname := gtk_file_chooser_get_filename(dlg);
    if fname <> nil then
    begin
      Result := PCharToStr(fname);
      g_free(fname);   { newly-allocated; the old SelectFolder leaked it }
    end;
  end;
  if ActiveDialogHandle = dlg then
  begin
    gtk_widget_destroy(dlg);
    ActiveDialogHandle := nil;
  end;
end;

procedure TGtk3WidgetSet.ClearList(AListBox: TComponent);
var h, row: Pointer; ctl: TControl;
begin
  ctl := TControl(AListBox);
  h := ctl.Handle;
  if h = nil then Exit;
  row := gtk_list_box_get_row_at_index(h, 0);
  while row <> nil do
  begin
    gtk_widget_destroy(row);
    row := gtk_list_box_get_row_at_index(h, 0);
  end;
end;

procedure TGtk3WidgetSet.AddComboItem(AComboBox: TComponent; const AText: string);
var h: Pointer; ctl: TControl;
begin
  ctl := TControl(AComboBox);
  h := ctl.Handle;
  if h <> nil then
    gtk_combo_box_text_append_text(h, PChar(AText));
end;

function TGtk3WidgetSet.GetActiveIndex(AComboBox: TComponent): Integer;
var h: Pointer; ctl: TControl;
begin
  ctl := TControl(AComboBox);
  h := ctl.Handle;
  if h <> nil then
    Result := gtk_combo_box_get_active(h)
  else
    Result := -1;
end;

procedure TGtk3WidgetSet.SetActiveIndex(AComboBox: TComponent; AIndex: Integer);
var h: Pointer; ctl: TControl;
begin
  ctl := TControl(AComboBox);
  h := ctl.Handle;
  if h <> nil then
    gtk_combo_box_set_active(h, AIndex);
end;

procedure TGtk3WidgetSet.ClearCombo(AComboBox: TComponent);
var h: Pointer; ctl: TControl;
begin
  ctl := TControl(AComboBox);
  h := ctl.Handle;
  if h <> nil then
    gtk_combo_box_text_remove_all(h);
end;

procedure TGtk3WidgetSet.DestroyWidget(AWidget: Pointer);
begin
  if AWidget <> nil then
    gtk_widget_destroy(AWidget);
end;

function ConvertAmpersand(const s: string): string;
var i: Integer; r: string;
begin
  r := '';
  for i := 1 to Length(s) do
    if s[i] = '&' then
      r := r + '_'
    else
      r := r + s[i];
  Result := r;
end;

procedure BuildSubMenu(parentItem: TMenuItem; parentMenuWidget: Pointer);
var
  i: Integer;
  item: TMenuItem;
  subWidget, subMenu: Pointer;
begin
  for i := 0 to parentItem.Count - 1 do
  begin
    item := parentItem.Item(i);
    { A LONE HYPHEN IS A SEPARATOR -- the Delphi/Lazarus spelling, so it costs no
      new type and a caller who already knows the convention gets it for free.
      Checked before the mnemonic conversion, which would otherwise turn it into
      a menu entry captioned '-' that you can click. }
    if item.Caption = '-' then
    begin
      subWidget := gtk_separator_menu_item_new();
      item.Handle := subWidget;
      gtk_menu_shell_append(parentMenuWidget, subWidget);
      gtk_widget_show(subWidget);
      Continue;
    end;
    subWidget := gtk_menu_item_new_with_mnemonic(PChar(ConvertAmpersand(item.Caption)));
    item.Handle := subWidget;
    gtk_menu_shell_append(parentMenuWidget, subWidget);

    if item.Count > 0 then
    begin
      subMenu := gtk_menu_new();
      gtk_menu_item_set_submenu(subWidget, subMenu);
      BuildSubMenu(item, subMenu);
    end
    else
    begin
      SignalConnectData(subWidget, 'activate', @MenuItemActivateTramp, Pointer(item));
    end;
    { Enabled/Visible are applied HERE as well as from their setters, because
      Realize rebuilds the menubar from scratch: an item disabled before the
      window was shown would come back sensitive otherwise. }
    gtk_widget_set_sensitive(subWidget, Ord(item.Enabled));
    if item.Visible then gtk_widget_show(subWidget) else gtk_widget_hide(subWidget);
  end;
end;

{ A menu item's Enabled/Visible used to be stored and nothing else -- the field
  changed, the menu did not, so a greyed-out entry was not expressible at all.
  Both setters now reach the widget when there IS one; before the menubar is
  built the field is all there is, and BuildSubMenu applies it on the way
  through, because Realize rebuilds the menubar from scratch. }
procedure TGtk3WidgetSet.SetMenuItemEnabled(AItem: TComponent; AEnabled: Boolean);
var it: TMenuItem;
begin
  it := TMenuItem(AItem);
  if (it = nil) or (it.Handle = nil) then Exit;
  gtk_widget_set_sensitive(it.Handle, Ord(AEnabled));
end;

procedure TGtk3WidgetSet.SetMenuItemVisible(AItem: TComponent; AVisible: Boolean);
var it: TMenuItem;
begin
  it := TMenuItem(AItem);
  if (it = nil) or (it.Handle = nil) then Exit;
  if AVisible then gtk_widget_show(it.Handle) else gtk_widget_hide(it.Handle);
end;

function TGtk3WidgetSet.SetFormMenu(AForm: TComponent; AMenu: TComponent): Integer;
var
  win, vbox, menubar: Pointer;
  topLevelItem: TMenuItem;
  topWidget, submenuWidget: Pointer;
  menu: TMainMenu;
  i: Integer;
  ctl: TControl;
begin
  ctl := TControl(AForm);
  win := ctl.GetHandle;
  if win = nil then begin Result := 0; Exit; end;
  menu := TMainMenu(AMenu);
  if menu = nil then begin Result := 0; Exit; end;
  
  vbox := GetVBoxPtr(win);
  if vbox = nil then begin Result := 0; Exit; end;

  { Track the menubar on the menu's root-item Handle, NOT the vbox widget-name:
    that name slot already holds the fixed-container pointer (SetFixedPtr), and
    overwriting it makes GetFixedPtr return nil (no child can enter the fixed).
    Realize re-applies the menu, so destroy any prior menubar to avoid dupes. }
  menubar := menu.Items.Handle;
  if menubar <> nil then
    gtk_widget_destroy(menubar);
  menubar := gtk_menu_bar_new();
  menu.Items.Handle := menubar;
  
  for i := 0 to menu.Items.Count - 1 do
  begin
    topLevelItem := menu.Items.Item(i);
    topWidget := gtk_menu_item_new_with_mnemonic(PChar(ConvertAmpersand(topLevelItem.Caption)));
    topLevelItem.Handle := topWidget;
    gtk_menu_shell_append(menubar, topWidget);
    
    if topLevelItem.Count > 0 then
    begin
      submenuWidget := gtk_menu_new();
      gtk_menu_item_set_submenu(topWidget, submenuWidget);
      BuildSubMenu(topLevelItem, submenuWidget);
    end
    else
    begin
      SignalConnectData(topWidget, 'activate', @MenuItemActivateTramp, Pointer(topLevelItem));
    end;
    gtk_widget_show(topWidget);
  end;
  
  gtk_box_pack_start(vbox, menubar, 0, 0, 0);
  gtk_box_reorder_child(vbox, menubar, 0);
  gtk_widget_show(menubar);
  Result := 0;
end;

procedure TGtk3WidgetSet.SetFormClient(AForm: TComponent; AControl: TComponent;
                                       AHeaderHeight: Integer);
var
  win, vbox, fixed, ch, oldParent: Pointer;
  fctl, ctl: TControl;
begin
  fctl := TControl(AForm);
  ctl := TControl(AControl);
  if (fctl = nil) or (ctl = nil) then Exit;
  win := fctl.GetHandle;
  ch := ctl.GetHandle;
  if (win = nil) or (ch = nil) then Exit;
  vbox := GetVBoxPtr(win);
  if vbox = nil then Exit;
  fixed := GetFixedPtr(vbox);

  { The header keeps its own height and STOPS EXPANDING. CreateForm packs the
    fixed with expand=1 because, with nothing else in the vbox, it is the whole
    content area; once there is a client it must not take a share of the growth,
    or dragging the window taller grows the empty toolbar strip instead of the
    editor. }
  if fixed <> nil then
  begin
    if AHeaderHeight > 0 then
      gtk_widget_set_size_request(fixed, -1, AHeaderHeight);
    gtk_box_set_child_packing(vbox, fixed, 0, 0, 0, GTK_PACK_START);
  end;

  { Out of the absolute-coordinate container and into the box. Idempotent,
    because TForm.Realize re-applies this every time: if it is already the
    vbox's child there is nothing to move, and re-packing a widget GTK already
    holds would be a warning and a lost widget. }
  oldParent := gtk_widget_get_parent(ch);
  if oldParent = vbox then
  begin
    gtk_widget_show(ch);
    Exit;
  end;
  { REF ACROSS THE MOVE, OR THE MOVE IS A DESTROY. gtk_container_remove drops
    the container's reference, and the container held the only one -- so without
    this the widget is finalized here and every later call through its stale
    Handle lands on freed memory. Measured 2026-09-27: it surfaced as
    `gtk_paned_set_position: assertion 'GTK_IS_PANED (paned)' failed` from the
    splitter seeding a moment later, and --gui-smoke still printed OK, because
    what it asserts is the status line. }
  if oldParent <> nil then
  begin
    g_object_ref(ch);
    gtk_container_remove(oldParent, ch);
    { NO SIZE REQUEST ON THE CLIENT, and this is the half that makes the window
      shrinkable: a request here becomes the window's minimum. -1 clears one the
      app may have set through SetBounds before handing the control over. }
    gtk_widget_set_size_request(ch, -1, -1);
    gtk_box_pack_start(vbox, ch, 1, 1, 0);
    g_object_unref(ch);
  end
  else
  begin
    gtk_widget_set_size_request(ch, -1, -1);
    gtk_box_pack_start(vbox, ch, 1, 1, 0);
  end;
  gtk_widget_show(ch);
end;


{ ================= the sealed seam: GTK bodies =============================
  These moved here verbatim from extctrls.pas, dialogs.pas and glarea.pas.
  Those units used to call GTK raw, which meant a second widgetset could only
  implement PART of PCL. Nothing about the GTK behaviour changed. }

{ GTK's orientation enum: 0 = horizontal, 1 = vertical. }
function Gtk3Orient(AVertical: Boolean): Integer;
begin
  if AVertical then Gtk3Orient := 1 else Gtk3Orient := 0;
end;

procedure TGtk3WidgetSet.ShowHandle(AWidget: Pointer);
begin
  if AWidget <> nil then gtk_widget_show(AWidget);
end;

procedure TGtk3WidgetSet.HideHandle(AWidget: Pointer);
begin
  if AWidget <> nil then gtk_widget_hide(AWidget);
end;

function TGtk3WidgetSet.HandleWidth(AWidget: Pointer): Integer;
begin
  if AWidget = nil then HandleWidth := 0
  else HandleWidth := gtk_widget_get_allocated_width(AWidget);
end;

function TGtk3WidgetSet.HandleHeight(AWidget: Pointer): Integer;
begin
  if AWidget = nil then HandleHeight := 0
  else HandleHeight := gtk_widget_get_allocated_height(AWidget);
end;

function TGtk3WidgetSet.CreatePaned(AVertical: Boolean): Pointer;
begin
  CreatePaned := gtk_paned_new(Gtk3Orient(AVertical));
end;

procedure TGtk3WidgetSet.PanedSetPosition(APaned: Pointer; APos: Integer);
begin
  if APaned <> nil then gtk_paned_set_position(APaned, APos);
end;

function TGtk3WidgetSet.PanedGetPosition(APaned: Pointer): Integer;
begin
  if APaned = nil then PanedGetPosition := 0
  else PanedGetPosition := gtk_paned_get_position(APaned);
end;

function TGtk3WidgetSet.PanedChild(APaned: Pointer; APane: Integer): Pointer;
begin
  PanedChild := nil;
  if APaned = nil then Exit;
  if APane = 2 then PanedChild := gtk_paned_get_child2(APaned)
  else PanedChild := gtk_paned_get_child1(APaned);
end;

function TGtk3WidgetSet.CreateBox(AVertical: Boolean; ASpacing: Integer): Pointer;
begin
  CreateBox := gtk_box_new(Gtk3Orient(AVertical), ASpacing);
end;

procedure TGtk3WidgetSet.BoxPack(ABox, AChild: Pointer; AExpand, AFill: Boolean; APadding: Integer);
var e, f: Integer;
begin
  if (ABox = nil) or (AChild = nil) then Exit;
  if AExpand then e := 1 else e := 0;
  if AFill then f := 1 else f := 0;
  gtk_box_pack_start(ABox, AChild, e, f, APadding);
end;

{ Put an ordinary widget into a GtkToolbar by wrapping it in a GtkToolItem.
  Shared by SetParent and nothing else today, but it is the one place that
  knows the wrapping rule. }
{ The overflow menu's stand-in for a button that no longer fits. Clicking it
  has to do what clicking the button does, so it emits the button's own
  'clicked'; an overflow menu whose entries do nothing is worse than no
  overflow at all. }
procedure ToolProxyActivateTramp(item: Pointer; userdata: Pointer); cdecl;
begin
  if userdata <> nil then gtk_button_clicked(userdata);
end;

procedure ToolBarWrapAndInsert(tb, ch: Pointer; const ACaption: string);
var item, old, proxy: Pointer;
begin
  if (tb = nil) or (ch = nil) then Exit;
  { already wrapped and in this toolbar? Realize re-parents on every pass }
  old := gtk_widget_get_parent(ch);
  if (old <> nil) and (gtk_widget_get_parent(old) = tb) then Exit;
  item := gtk_tool_item_new;
  if old <> nil then
  begin
    { ref across the move, or gtk_container_remove drops the last reference
      and finalizes the widget -- the same hazard SetFormClient documents }
    g_object_ref(ch);
    gtk_container_remove(old, ch);
    gtk_container_add(item, ch);
    g_object_unref(ch);
  end
  else
    gtk_container_add(item, ch);

  { AN ITEM WITH NO PROXY MENU ITEM IS UNREACHABLE ONCE IT NO LONGER FITS.
    GTK will only put an item in the arrow menu if it has been given something
    to show there; without a proxy the item is simply not displayed and the
    button cannot be pressed at all.

    IT IS NOT WHAT LETS THE TOOLBAR SHRINK, and this comment said it was for
    twenty minutes. Measured 2026-09-27 with the proxies disabled: the
    toolbar's minimum width is 7px either way. The 505px floor espide had at
    that point was its STATUS LABEL, whose minimum is its whole text -- a
    different subsystem entirely, found by measuring each widget instead of
    believing the first plausible cause. So: proxies buy REACHABILITY,
    TLabel.Ellipsize buys the width.

    Only captioned controls get one. An entry or a combo box has no sensible
    menu form, and hiding the one you are typing in would be worse. }
  if ACaption <> '' then
  begin
    proxy := gtk_menu_item_new_with_label(PC(ACaption));
    gtk_tool_item_set_proxy_menu_item(item, PC('pcl-' + ACaption), proxy);
    SignalConnectData(proxy, 'activate', @ToolProxyActivateTramp, ch);
  end;

  gtk_toolbar_insert(tb, item, -1);
  gtk_widget_show_all(item);
end;

procedure TGtk3WidgetSet.SetLabelEllipsis(ALabel: TComponent; AOn: Boolean);
var h: Pointer;
begin
  h := TControl(ALabel).Handle;
  if h = nil then Exit;
  if AOn then
  begin
    gtk_label_set_ellipsize(h, 3);   { PANGO_ELLIPSIZE_END }
    { left-aligned, or an ellipsized label centres its remains in the row }
    gtk_label_set_xalign(h, 0.0);
  end
  else
    gtk_label_set_ellipsize(h, 0);   { PANGO_ELLIPSIZE_NONE }
end;

function TGtk3WidgetSet.CreateToolBar(AToolBar: TComponent): Pointer;
begin
  CreateToolBar := gtk_toolbar_new;
  { THE WHOLE POINT: with show-arrow set, a toolbar narrower than its items
    puts the tail in its own menu instead of forcing its container wider. }
  gtk_toolbar_set_show_arrow(CreateToolBar, 1);
end;

procedure TGtk3WidgetSet.ToolBarAddSeparator(AToolBar: TComponent);
var tb, item: Pointer;
begin
  tb := TControl(AToolBar).Handle;
  if tb = nil then Exit;
  item := gtk_separator_tool_item_new;
  gtk_toolbar_insert(tb, item, -1);
  gtk_widget_show(item);
end;

procedure TGtk3WidgetSet.SetFormHeader(AForm: TComponent; AControl: TComponent);
var win, vbox, ch, oldParent: Pointer;
    fctl, ctl: TControl;
    slot: Integer;
begin
  fctl := TControl(AForm);
  ctl := TControl(AControl);
  if (fctl = nil) or (ctl = nil) then Exit;
  win := fctl.GetHandle;
  ch := ctl.GetHandle;
  if (win = nil) or (ch = nil) then Exit;
  vbox := GetVBoxPtr(win);
  if vbox = nil then Exit;

  { below the menu bar when there is one, first otherwise }
  if HasMenuBarFirst(vbox) then slot := 1 else slot := 0;

  oldParent := gtk_widget_get_parent(ch);
  if oldParent = vbox then
  begin
    gtk_box_reorder_child(vbox, ch, slot);
    gtk_widget_show(ch);
    Exit;
  end;
  if oldParent <> nil then
  begin
    g_object_ref(ch);
    gtk_container_remove(oldParent, ch);
    gtk_box_pack_start(vbox, ch, 0, 0, 0);
    g_object_unref(ch);
  end
  else
    gtk_box_pack_start(vbox, ch, 0, 0, 0);
  gtk_box_reorder_child(vbox, ch, slot);
  gtk_widget_show(ch);
end;

{ ---- TTreeView over GtkTreeView + GtkTreeStore ----

  LAYOUTS DECLARED HERE, NOT IMPORTED, AND THAT IS NOT A PREFERENCE. The C
  import gives these two structs no layout at all: measured 2026-09-27,
  SizeOf(GtkTreeIter) off gtk3_c answers 4 and so does SizeOf(GValue). 4 is
  TypeStorageSize(tyUnknown) -- "nothing was recorded" -- and it is not an
  error, it is a number. Passing a 4-byte iter to gtk_tree_store_append, which
  writes 32, smashes the stack silently.

  GtkTreeIter's layout is public and stable: { gint stamp; gpointer user_data,
  user_data2, user_data3; }. GValue's is { GType g_type; union { ... }
  data[2]; }, 8 + 2*8. pxx pads both exactly as C does -- verified, 32 and 24
  with user_data at offset 8. }
type
  TTreeIterRec = record
    stamp: LongInt;
    d1, d2, d3: Pointer;
  end;
  TGValueRec = record
    g_type: QWord;
    d0, d1: Int64;
  end;

const
  { G_TYPE_STRING lives in gtk3.pas, one spelling, and the tree test asserts
    g_type_name of THAT constant is 'gchararray'. }
  TREE_COL_TEXT = 0;

{ The GtkTreeView inside the scrolled window that IS the handle (same shape as
  CreateMemo: the scroller is what gets parented and sized). }
function TreeInner(ATree: TComponent): Pointer;
var ctl: TControl;
begin
  TreeInner := nil;
  ctl := TControl(ATree);
  if ctl.Handle = nil then Exit;
  TreeInner := gtk_bin_get_child(ctl.Handle);
end;

function TreeModel(ATree: TComponent): Pointer;
var tv: Pointer;
begin
  TreeModel := nil;
  tv := TreeInner(ATree);
  if tv <> nil then TreeModel := gtk_tree_view_get_model(tv);
end;

{ gtk_tree_store_set is variadic and pxx drops the tail, so the one non-
  variadic sibling that can store a string is set_value + a GValue. }
procedure TreeStoreSetText(store, iter: Pointer; const AText: string);
var v: TGValueRec;
begin
  v.g_type := 0;   { g_value_init REQUIRES a zeroed GValue }
  v.d0 := 0;
  v.d1 := 0;
  g_value_init(@v, G_TYPE_STRING);
  g_value_set_string(@v, PC(AText));
  gtk_tree_store_set_value(store, iter, TREE_COL_TEXT, @v);
  g_value_unset(@v);
end;

{ Same two events as a list box, for the same reason: a caller coming from
  Lazarus reaches for OnChange, one coming from this binding reaches for
  OnClick, and neither should meet a dead property. }
procedure TreeSelectionChangedTramp(sel: Pointer; userdata: Pointer); cdecl;
var ctl: TControl; m: TMethod;
begin
  ctl := userdata;
  m := ctl.OnClick;
  if m.Code <> nil then
    CallMethod(m.Code, m.Data, userdata);
  FireNamedEvent(userdata, 'OnChange');
end;

function TGtk3WidgetSet.CreateTreeView(ATree: TComponent): Pointer;
var scroll, tv, store, col, rend, sel: Pointer;
    types: array[0..0] of QWord;
begin
  scroll := gtk_scrolled_window_new(nil, nil);
  gtk_scrolled_window_set_policy(scroll, GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC);
  gtk_scrolled_window_set_shadow_type(scroll, 1);   { GTK_SHADOW_IN }

  { gtk_tree_store_new is variadic; _newv takes the same types as an array. }
  types[0] := G_TYPE_STRING;
  store := gtk_tree_store_newv(1, @types[0]);
  tv := gtk_tree_view_new_with_model(store);
  g_object_unref(store);   { the view holds the only reference we need }

  { gtk_tree_view_insert_column_with_attributes is variadic too: build the
    column, pack a text renderer, bind column 0 to its 'text' property. }
  col := gtk_tree_view_column_new;
  rend := gtk_cell_renderer_text_new;
  gtk_tree_view_column_pack_start(col, rend, 1);
  gtk_tree_view_column_add_attribute(col, rend, PC('text'), TREE_COL_TEXT);
  gtk_tree_view_append_column(tv, col);
  { one nameless column, so no header row to waste a line on }
  gtk_tree_view_set_headers_visible(tv, 0);

  sel := gtk_tree_view_get_selection(tv);
  SignalConnectData(sel, 'changed', @TreeSelectionChangedTramp, Pointer(ATree));

  gtk_container_add(scroll, tv);
  CreateTreeView := scroll;
end;

function TGtk3WidgetSet.TreeAdd(ATree: TComponent; const AParent, AText: string): string;
var store, s: Pointer;
    it, pit: TTreeIterRec;
    pp: Pointer;
begin
  TreeAdd := '';
  store := TreeModel(ATree);
  if store = nil then Exit;
  pp := nil;
  if AParent <> '' then
  begin
    if gtk_tree_model_get_iter_from_string(store, @pit, PC(AParent)) = 0 then Exit;
    pp := @pit;
  end;
  gtk_tree_store_append(store, @it, pp);
  TreeStoreSetText(store, @it, AText);
  s := gtk_tree_model_get_string_from_iter(store, @it);
  if s <> nil then
  begin
    TreeAdd := PCharToStr(s);
    g_free(s);
  end;
end;

procedure TGtk3WidgetSet.TreeClear(ATree: TComponent);
var store: Pointer;
begin
  store := TreeModel(ATree);
  if store <> nil then gtk_tree_store_clear(store);
end;

procedure TGtk3WidgetSet.TreeExpand(ATree: TComponent; const ANode: string; ADeep: Boolean);
var tv, path: Pointer; d: Integer;
begin
  tv := TreeInner(ATree);
  if tv = nil then Exit;
  if ANode = '' then
  begin
    gtk_tree_view_expand_all(tv);
    Exit;
  end;
  path := gtk_tree_path_new_from_string(PC(ANode));
  if path = nil then Exit;
  if ADeep then d := 1 else d := 0;
  gtk_tree_view_expand_row(tv, path, d);
  gtk_tree_path_free(path);
end;

procedure TGtk3WidgetSet.TreeCollapse(ATree: TComponent; const ANode: string);
var tv, path: Pointer;
begin
  tv := TreeInner(ATree);
  if tv = nil then Exit;
  if ANode = '' then
  begin
    gtk_tree_view_collapse_all(tv);
    Exit;
  end;
  path := gtk_tree_path_new_from_string(PC(ANode));
  if path = nil then Exit;
  gtk_tree_view_collapse_row(tv, path);
  gtk_tree_path_free(path);
end;

procedure TGtk3WidgetSet.TreeSetText(ATree: TComponent; const ANode, AText: string);
var store: Pointer; it: TTreeIterRec;
begin
  store := TreeModel(ATree);
  if store = nil then Exit;
  if gtk_tree_model_get_iter_from_string(store, @it, PC(ANode)) = 0 then Exit;
  TreeStoreSetText(store, @it, AText);
end;

function TGtk3WidgetSet.TreeSelected(ATree: TComponent): string;
var tv, sel, s: Pointer;
    it: TTreeIterRec;
    model: Pointer;
begin
  TreeSelected := '';
  tv := TreeInner(ATree);
  if tv = nil then Exit;
  sel := gtk_tree_view_get_selection(tv);
  if sel = nil then Exit;
  model := nil;
  if gtk_tree_selection_get_selected(sel, @model, @it) = 0 then Exit;
  s := gtk_tree_model_get_string_from_iter(model, @it);
  if s <> nil then
  begin
    TreeSelected := PCharToStr(s);
    g_free(s);
  end;
end;

procedure TGtk3WidgetSet.TreeSelect(ATree: TComponent; const ANode: string);
var tv, sel, path: Pointer;
begin
  tv := TreeInner(ATree);
  if tv = nil then Exit;
  sel := gtk_tree_view_get_selection(tv);
  if sel = nil then Exit;
  if ANode = '' then
  begin
    gtk_tree_selection_unselect_all(sel);
    Exit;
  end;
  path := gtk_tree_path_new_from_string(PC(ANode));
  if path = nil then Exit;
  { a row inside a collapsed parent cannot be selected, so open the way to it }
  gtk_tree_view_expand_to_path(tv, path);
  gtk_tree_selection_select_path(sel, path);
  gtk_tree_path_free(path);
end;

function TGtk3WidgetSet.CreateNotebook: Pointer;
begin
  CreateNotebook := gtk_notebook_new();
end;

{ Returns the page's content box — the caller packs into it and never sees the
  label widget, which is what keeps the toolkit out of extctrls. }
function TGtk3WidgetSet.NotebookAddPage(ANotebook: Pointer; const ACaption: string): Pointer;
var box, lbl: Pointer;
begin
  NotebookAddPage := nil;
  if ANotebook = nil then Exit;
  box := gtk_box_new(0, 2);                    { a horizontal row of children }
  lbl := gtk_label_new(PChar(ACaption));
  gtk_notebook_append_page(ANotebook, box, lbl);
  gtk_widget_show(box);
  NotebookAddPage := box;
end;

function TGtk3WidgetSet.NotebookGetPage(ANotebook: Pointer): Integer;
begin
  if ANotebook = nil then NotebookGetPage := 0
  else NotebookGetPage := gtk_notebook_get_current_page(ANotebook);
end;

procedure TGtk3WidgetSet.NotebookSetPage(ANotebook: Pointer; AIndex: Integer);
begin
  if ANotebook <> nil then gtk_notebook_set_current_page(ANotebook, AIndex);
end;

{ gtk_dialog_run spins its own nested main loop, so a test harness cannot click
  OK — it dismisses from a g_timeout via DismissModal, which returns
  control from the run exactly as a real click would. }
procedure TGtk3WidgetSet.MessageBox(const AText: string);
var dlg, esc: Pointer;
begin
  { Two calls rather than one because gtk_message_dialog_new is VARIADIC in the
    real headers and pxx's C import drops the variadic tail, so only the fixed
    prefix is callable (bug-a-c-header-import-drops-the-variadic-tail). The
    curated binding used to declare a fixed 6-arity form and pass ("%s", text).

    NULL as the format gives a dialog with no message, and set_markup then
    supplies it -- but set_markup INTERPRETS Pango markup where "%s" did not,
    so the text is escaped first. Without the escape a message containing & or
    < renders wrong or is dropped entirely, which is the silent half of this
    change and the reason it is not just "call set_markup". }
  dlg := gtk_message_dialog_new(nil, GTK_DIALOG_MODAL, GTK_MESSAGE_INFO,
                                GTK_BUTTONS_OK, nil);
  esc := g_markup_escape_text(PC(AText), -1);
  gtk_message_dialog_set_markup(dlg, esc);
  g_free(esc);
  ActiveDialogHandle := dlg;
  gtk_dialog_run(dlg);
  { a timeout may already have destroyed it — do not free it twice }
  if ActiveDialogHandle = dlg then
  begin
    gtk_widget_destroy(dlg);
    ActiveDialogHandle := nil;
  end;
end;

procedure TGtk3WidgetSet.DismissModal;
begin
  if ActiveDialogHandle <> nil then
    gtk_widget_destroy(ActiveDialogHandle);
  ActiveDialogHandle := nil;
end;

initialization
  WidgetSet := TGtk3WidgetSet.Create;
end.
