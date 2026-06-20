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
    
    procedure SetText(AControl: TComponent; const AText: string); override;
    procedure SetBounds(AControl: TComponent; ALeft, ATop, AWidth, AHeight: Integer); override;
    procedure SetParent(AControl: TComponent; AParent: TComponent); override;
    procedure ShowWidget(AControl: TComponent); override;
    
    procedure ConnectClick(AControl: TComponent); override;
    procedure ConnectChange(AControl: TComponent); override;
    procedure ConnectAppQuit(AForm: TComponent); override;
    
    procedure SetChecked(AControl: TComponent; AChecked: Boolean); override;
    function GetChecked(AControl: TComponent): Boolean; override;
    
    function StartTimer(AInterval: Integer; ACallback: Pointer; AData: Pointer): LongWord; override;
    procedure StopTimer(AId: LongWord); override;
  end;

implementation

uses gtk3_c, gtk3, controls, typinfo;

type
  PC = ^Char;

function PCharToStr(p: Pointer): string;
var
  s: string;
  c: PC;
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
var win, fixed: Pointer;
begin
  win := gtk_window_new(GTK_WINDOW_TOPLEVEL);
  writeln('TGtk3WidgetSet.CreateForm: win=', Int64(win));
  gtk_window_set_default_size(win, 320, 240);
  fixed := gtk_fixed_new();
  gtk_container_add(win, fixed);
  Result := win;
end;

function TGtk3WidgetSet.CreateButton(AButton: TComponent): Pointer;
begin
  Result := gtk_button_new_with_label(PC(''));
end;

function TGtk3WidgetSet.CreateLabel(ALabel: TComponent): Pointer;
begin
  Result := gtk_label_new(PC(''));
end;

function TGtk3WidgetSet.CreateEdit(AEdit: TComponent): Pointer;
begin
  Result := gtk_entry_new();
end;

function TGtk3WidgetSet.CreateCheckBox(ACheckBox: TComponent): Pointer;
begin
  Result := gtk_check_button_new_with_label(PC(''));
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
var h: Pointer; className: string; ctl: TControl; cls: PClassRTTI;
begin
  writeln('TGtk3WidgetSet.SetText: AControl=', Int64(AControl));
  ctl := TControl(AControl);
  h := ctl.Handle;
  writeln('TGtk3WidgetSet.SetText: h=', Int64(h));
  if h = nil then Exit;
  
  className := GetInstanceClassName(Pointer(AControl));
  cls := GetClass(className);
  if IsSubclassOf(cls, 'TForm') then
    gtk_window_set_title(h, PC(AText))
  else if IsSubclassOf(cls, 'TButton') then
    gtk_button_set_label(h, PC(AText))
  else if IsSubclassOf(cls, 'TLabel') then
    gtk_label_set_text(h, PC(AText))
  else if IsSubclassOf(cls, 'TEdit') then
    gtk_entry_set_text(h, PC(AText))
  else if IsSubclassOf(cls, 'TCheckBox') then
    gtk_button_set_label(h, PC(AText))
  else if IsSubclassOf(cls, 'TPanel') then
    gtk_button_set_label(h, PC(AText));
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
        container := gtk_bin_get_child(ph);
        if container <> nil then
          gtk_fixed_move(container, ch, ALeft, ATop);
      end;
    end;
  end;
end;

procedure TGtk3WidgetSet.SetParent(AControl: TComponent; AParent: TComponent);
var
  ch, ph, container: Pointer;
  ctl: TControl;
  pctl: TControl;
  cls: PClassRTTI;
begin
  ctl := TControl(AControl);
  pctl := TControl(AParent);
  ch := ctl.Handle;
  ph := pctl.Handle;
  if (ch = nil) or (ph = nil) then Exit;
  
  cls := GetClass(GetInstanceClassName(Pointer(pctl)));
  if IsSubclassOf(cls, 'TForm') or IsSubclassOf(cls, 'TPanel') then
    container := gtk_bin_get_child(ph)
  else
    container := ph;
    
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

initialization
  writeln('INITIALIZING gtk3widgets!');
  WidgetSet := TGtk3WidgetSet.Create;
end.
