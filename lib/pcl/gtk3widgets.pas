{ SPDX-License-Identifier: Zlib }
unit gtk3widgets;

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
    function SelectFolder(const ATitle: string): string; override;
    
    procedure AddComboItem(AComboBox: TComponent; const AText: string); override;
    function GetActiveIndex(AComboBox: TComponent): Integer; override;
    procedure SetActiveIndex(AComboBox: TComponent; AIndex: Integer); override;
    procedure ClearCombo(AComboBox: TComponent); override;
    
    function StartTimer(AInterval: Integer; ACallback: Pointer; AData: Pointer): LongWord; override;
    procedure StopTimer(AId: LongWord); override;
    function SetFormMenu(AForm: TComponent; AMenu: TComponent): Integer; override;
  end;

implementation

uses gtk3_c, gtk3, controls, typinfo, graphics, extctrls, menus;

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

function GetMenuBarPtr(vbox: Pointer): Pointer;
var
  namePtr: Pointer;
  s: string;
begin
  Result := nil;
  namePtr := gtk_widget_get_name(vbox);
  if namePtr <> nil then
  begin
    s := PCharToStr(namePtr);
    if (Length(s) > 5) and (s[1] = 'M') and (s[2] = 'B') and (s[3] = 'A') and (s[4] = 'R') and (s[5] = '_') then
      Result := StringToPointer(GetSubStr(s, 6));
  end;
end;

procedure SetMenuBarPtr(vbox: Pointer; menubar: Pointer);
var
  s: string;
begin
  if menubar = nil then
    gtk_widget_set_name(vbox, PChar(''))
  else
  begin
    s := 'MBAR_' + PointerToString(menubar);
    gtk_widget_set_name(vbox, PChar(s));
  end;
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

{ GtkListBox 'row-selected' passes (listbox, row, userdata). Fire OnClick when a
  row is actually selected (row <> nil; a cleared selection passes nil). }
procedure ListBoxRowSelectedTramp(widget: Pointer; row: Pointer; userdata: Pointer); cdecl;
var ctl: TControl; m: TMethod;
begin
  if row = nil then Exit;
  ctl := userdata;
  m := ctl.OnClick;
  if m.Code <> nil then
    CallMethod(m.Code, m.Data, userdata);
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
    gtk_button_set_label(h, p);
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
  n: LongWord;
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
    Header-then-content convention: the first child packed keeps its natural
    size (a fixed header row); every child packed after it expands/fills to
    take the remaining space. Matches this box's only current use (a pane
    header strip above its content) — revisit if a caller needs a different
    split. }
  if IsSubclassOf(cls, 'TBox') then
  begin
    if gtk_widget_get_parent(ch) = ph then Exit;
    lst := gtk_container_get_children(ph);
    n := g_list_length(lst);
    if lst <> nil then g_list_free(lst);
    if n = 0 then
      gtk_box_pack_start(ph, ch, 0, 0, 0)
    else
      gtk_box_pack_start(ph, ch, 1, 1, 0);
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

function TGtk3WidgetSet.SelectFolder(const ATitle: string): string;
var dlg, fname: Pointer; resp: Integer;
begin
  Result := '';
  dlg := gtk_file_chooser_dialog_new(PChar(ATitle), nil,
    GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER, nil);
  gtk_dialog_add_button(dlg, PChar('Cancel'), GTK_RESPONSE_CANCEL);
  gtk_dialog_add_button(dlg, PChar('Open'), GTK_RESPONSE_ACCEPT);
  resp := gtk_dialog_run(dlg);
  if resp = GTK_RESPONSE_ACCEPT then
  begin
    fname := gtk_file_chooser_get_filename(dlg);
    if fname <> nil then Result := PCharToStr(fname);
  end;
  gtk_widget_destroy(dlg);
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
    gtk_widget_show(subWidget);
  end;
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

initialization
  WidgetSet := TGtk3WidgetSet.Create;
end.
