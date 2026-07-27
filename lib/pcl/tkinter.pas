{ SPDX-License-Identifier: Zlib }
unit tkinter;
{ Python's `tkinter` for the Nil-Python frontend — first slice.

  Named `tkinter` so `import tkinter` resolves through the unit resolver, like
  lib/rtl/re.pas and configparser.pas. Backed by lib/pcl/tk.pas, i.e. real Tcl/Tk
  command strings through TkEval — which is exactly how CPython's tkinter works
  underneath, minus tkinter's weight.

  WHAT THIS SLICE IS. The widget types and methods songformatter's settings.py
  and convertrawtext.py actually touch, no more: enough for those modules to
  COMPILE and for simple widget trees to really appear. It is not a complete
  tkinter. Missing pieces fail at their use site as an unresolved name rather
  than silently doing nothing, which is the property that matters while the rest
  is filled in.

  HOW OPTIONS WORK. Python passes widget options as keyword arguments, and any
  subset of them: `Canvas(self, highlightthickness=0)`. So every constructor here
  declares the common options as optional parameters with Tk's own defaults, and
  keyword arguments bind by NAME (that binding is what commit "keyword arguments
  bind by name, any subset" made possible — before it, skipping one was an error).
  An option left out is not emitted, so Tk keeps its default.

  WIDGET IDENTITY. Each widget owns a Tcl path name (`.w3`, `.w3.w7`), allocated
  from a counter, so the object on the Python side and the widget inside Tk stay
  in step. `master` is the parent widget or None for a child of the root window.

  CALLBACKS. `command=` and `bind` take a STRING here, not a function — the Tcl
  script to run. Python passes a function, which needs the dispatch-table work in
  feature-nilpy-tkinter-facade; taking a string keeps this slice honest instead of
  accepting a callable and dropping it. }

interface

uses tk;

type
  Widget = class
  public
    path: AnsiString;         { the Tcl path name, e.g. `.w4.w9` }
    kind: AnsiString;         { `frame`, `canvas`, ... — for diagnostics }
    constructor Create;

    { geometry managers }
    procedure pack(const side: AnsiString = ''; const fill: AnsiString = '';
                   expand: Integer = -1; padx: Integer = -1; pady: Integer = -1);
    procedure grid(row: Integer = -1; column: Integer = -1;
                   const sticky: AnsiString = '');
    procedure grid_columnconfigure(index: Integer = 0; weight: Integer = -1);
    procedure grid_rowconfigure(index: Integer = 0; weight: Integer = -1);

    { common configuration. Two spellings on purpose: Python writes
      `w.configure(state="disabled")`, i.e. OPTIONS BY NAME, and NilPy binds
      keyword arguments by name over any subset — so the options an application
      actually sets are declared here as optional parameters. The raw-string form
      stays for anything not yet named (and is what the named form builds).
      An option this façade does not know is a compile error at the call site,
      which is the point: silently dropping a widget option would show up as a
      layout that is subtly wrong rather than as a diagnostic. }
    procedure configure(const state: AnsiString = ''; const scrollregion: AnsiString = '';
                        const yscrollcommand: AnsiString = '';
                        const xscrollcommand: AnsiString = '';
                        const text: AnsiString = ''; const background: AnsiString = '';
                        width: Integer = -1; height: Integer = -1);
    { the raw form, for an option this façade has not named yet }
    procedure configure_raw(const opts: AnsiString);
    function cget(const option: AnsiString): AnsiString;
    procedure bind(const sequence, script: AnsiString);
    function winfo_width: Integer;
    function winfo_height: Integer;
    function winfo_children: AnsiString;   { space-separated Tcl paths }
    procedure destroy_;                    { `destroy` is a Pascal-ish trap }
  end;

  Frame = class(Widget)
  public
    constructor Create(master: Widget; highlightthickness: Integer = -1;
                       const background: AnsiString = ''; width: Integer = -1;
                       height: Integer = -1);
  end;

  Canvas = class(Widget)
  public
    constructor Create(master: Widget; highlightthickness: Integer = -1;
                       const background: AnsiString = ''; width: Integer = -1;
                       height: Integer = -1);
    function create_window(x, y: Integer; const window: AnsiString;
                           const anchor: AnsiString): Integer;
    function create_text(x, y: Integer; const text: AnsiString;
                         const anchor: AnsiString = ''; const fill: AnsiString = '';
                         const font: AnsiString = ''): Integer;
    function create_line(x1, y1, x2, y2: Integer;
                         const fill: AnsiString = ''): Integer;
    function create_rectangle(x1, y1, x2, y2: Integer;
                              const outline: AnsiString = '';
                              const fill: AnsiString = ''): Integer;
    procedure itemconfigure(item: Integer; const opts: AnsiString);
    procedure delete_all;
    function bbox(item: Integer): AnsiString;
    procedure yview(const args: AnsiString);
    procedure yview_scroll(n: Integer; const what: AnsiString);
    procedure xview(const args: AnsiString);
    procedure set_scrollregion(x1, y1, x2, y2: Integer);
  end;

  Scrollbar = class(Widget)
  public
    constructor Create(master: Widget; const orient: AnsiString = '';
                       const command: AnsiString = '');
    procedure set_(const first, last: AnsiString);
  end;

  { Named exactly as Python names it. The trailing-underscore spelling was a
    symmetry habit, and it cost the mission its whole point: an application
    writes `tk.Label(...)` and must not have to write anything else. }
  Label = class(Widget)
  public
    constructor Create(master: Widget; const text: AnsiString = '';
                       const anchor: AnsiString = ''; const font: AnsiString = '');
    procedure set_text(const value: AnsiString);
  end;

  Entry = class(Widget)
  public
    constructor Create(master: Widget; const textvariable: AnsiString = '';
                       width: Integer = -1);
    function get: AnsiString;
    procedure insert(index: Integer; const value: AnsiString);
  end;

  Checkbutton = class(Widget)
  public
    constructor Create(master: Widget; const text: AnsiString = '';
                       const variable: AnsiString = '';
                       const onvalue: AnsiString = '';
                       const offvalue: AnsiString = '');
  end;

  { tkinter's variable objects. A Tcl variable by name, which is how the real
    thing works too. }
  StringVar = class
  public
    name: AnsiString;
    constructor Create;
    function get: AnsiString;
    procedure set_(const value: AnsiString);
  end;

  BooleanVar = class
  public
    name: AnsiString;
    constructor Create;
    function get: Boolean;
    procedure set_(value: Boolean);
  end;

  { The root window as Python spells it: `root = tk.Tk()`. Tcl's root is a
    process-wide singleton, so every construction hands back the same '.' path;
    the class exists so the application's own spelling compiles. }
  Tk = class(Widget)
  public
    constructor Create;
  end;

{ The older function spelling, kept for the example and any caller that used it. }
function Tk_: Widget;
procedure mainloop;

implementation

var
  gTkWidgetSeq: Integer;
  gTkVarSeq: Integer;
  gTkStarted: Boolean;

function TkiIntStr(n: Integer): AnsiString; forward;
function TkiStrInt(const s: AnsiString): Integer; forward;

function TkiNextPath(master: Widget): AnsiString;
var base: AnsiString;
begin
  gTkWidgetSeq := gTkWidgetSeq + 1;
  if master = nil then base := '' else base := master.path;
  { the root window's path IS '.', so a child of it must not become '..w1' }
  if base = '.' then base := '';
  TkiNextPath := base + '.w' + TkiIntStr(gTkWidgetSeq);
end;

function TkiIntStr(n: Integer): AnsiString;
var neg: Boolean; r: AnsiString; v: Integer;
begin
  if n = 0 then
  begin
    TkiIntStr := '0';
    exit;
  end;
  neg := n < 0;
  if neg then v := -n else v := n;
  r := '';
  while v > 0 do
  begin
    r := Chr(Ord('0') + (v mod 10)) + r;
    v := v div 10;
  end;
  if neg then r := '-' + r;
  TkiIntStr := r;
end;

procedure TkiEnsureStarted;
begin
  if not gTkStarted then
  begin
    TkInit;
    gTkStarted := True;
  end;
end;

{ Append ` -name value` only when the caller supplied the option. The sentinel
  for "not given" is '' for strings and -1 for the integer options Tk defaults
  itself. }
function TkiOptStr(const name, value: AnsiString): AnsiString;
begin
  if value = '' then TkiOptStr := '' else TkiOptStr := ' -' + name + ' ' + value;
end;

function TkiOptInt(const name: AnsiString; value: Integer): AnsiString;
begin
  if value < 0 then TkiOptInt := ''
  else TkiOptInt := ' -' + name + ' ' + TkiIntStr(value);
end;

{ ---- Widget -------------------------------------------------------------- }

constructor Widget.Create;
begin
  path := '';
  kind := '';
end;

procedure Widget.pack(const side: AnsiString; const fill: AnsiString;
                     expand: Integer; padx: Integer; pady: Integer);
var opts: AnsiString;
begin
  opts := TkiOptStr('side', side) + TkiOptStr('fill', fill) +
          TkiOptInt('expand', expand) + TkiOptInt('padx', padx) +
          TkiOptInt('pady', pady);
  TkEval('pack ' + path + opts);
end;

procedure Widget.grid(row: Integer; column: Integer; const sticky: AnsiString);
begin
  TkEval('grid ' + path + TkiOptInt('row', row) + TkiOptInt('column', column) +
         TkiOptStr('sticky', sticky));
end;

procedure Widget.grid_columnconfigure(index: Integer; weight: Integer);
begin
  TkEval('grid columnconfigure ' + path + ' ' + TkiIntStr(index) +
         TkiOptInt('weight', weight));
end;

procedure Widget.grid_rowconfigure(index: Integer; weight: Integer);
begin
  TkEval('grid rowconfigure ' + path + ' ' + TkiIntStr(index) +
         TkiOptInt('weight', weight));
end;

procedure Widget.configure_raw(const opts: AnsiString);
begin
  TkEval(path + ' configure ' + opts);
end;

procedure Widget.configure(const state, scrollregion, yscrollcommand,
                           xscrollcommand, text, background: AnsiString;
                           width, height: Integer);
var o: AnsiString;
begin
  o := TkiOptStr('state', state) + TkiOptStr('scrollregion', scrollregion)
     + TkiOptStr('yscrollcommand', yscrollcommand)
     + TkiOptStr('xscrollcommand', xscrollcommand)
     + TkiOptStr('text', text) + TkiOptStr('background', background)
     + TkiOptInt('width', width) + TkiOptInt('height', height);
  if o <> '' then TkEval(path + ' configure' + o);
end;

function Widget.cget(const option: AnsiString): AnsiString;
begin
  cget := TkEval(path + ' cget -' + option);
end;

procedure Widget.bind(const sequence, script: AnsiString);
begin
  TkEval('bind ' + path + ' ' + sequence + ' {' + script + '}');
end;

function Widget.winfo_width: Integer;
begin
  winfo_width := TkiStrInt(TkEval('winfo width ' + path));
end;

function Widget.winfo_height: Integer;
begin
  winfo_height := TkiStrInt(TkEval('winfo height ' + path));
end;

function Widget.winfo_children: AnsiString;
begin
  winfo_children := TkEval('winfo children ' + path);
end;

procedure Widget.destroy_;
begin
  TkEval('destroy ' + path);
end;

function TkiStrInt(const s: AnsiString): Integer;
var i, r: Integer; neg: Boolean;
begin
  r := 0;
  neg := False;
  i := 1;
  while (i <= Length(s)) and ((s[i] = ' ') or (s[i] = #9)) do i := i + 1;
  if (i <= Length(s)) and (s[i] = '-') then
  begin
    neg := True;
    i := i + 1;
  end;
  while (i <= Length(s)) and (s[i] >= '0') and (s[i] <= '9') do
  begin
    r := r * 10 + (Ord(s[i]) - Ord('0'));
    i := i + 1;
  end;
  if neg then r := -r;
  TkiStrInt := r;
end;

{ ---- Frame --------------------------------------------------------------- }

constructor Frame.Create(master: Widget; highlightthickness: Integer;
                        const background: AnsiString; width: Integer;
                        height: Integer);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'frame';
  TkEval('frame ' + path + TkiOptInt('highlightthickness', highlightthickness) +
         TkiOptStr('background', background) + TkiOptInt('width', width) +
         TkiOptInt('height', height));
end;

{ ---- Canvas -------------------------------------------------------------- }

constructor Canvas.Create(master: Widget; highlightthickness: Integer;
                         const background: AnsiString; width: Integer;
                         height: Integer);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'canvas';
  TkEval('canvas ' + path + TkiOptInt('highlightthickness', highlightthickness) +
         TkiOptStr('background', background) + TkiOptInt('width', width) +
         TkiOptInt('height', height));
end;

function Canvas.create_window(x, y: Integer; const window: AnsiString;
                              const anchor: AnsiString): Integer;
begin
  create_window := TkiStrInt(TkEval(path + ' create window ' + TkiIntStr(x) +
                   ' ' + TkiIntStr(y) + TkiOptStr('window', window) +
                   TkiOptStr('anchor', anchor)));
end;

function Canvas.create_text(x, y: Integer; const text, anchor, fill,
                            font: AnsiString): Integer;
begin
  create_text := TkiStrInt(TkEval(path + ' create text ' + TkiIntStr(x) + ' ' +
                 TkiIntStr(y) + ' -text {' + text + '}' +
                 TkiOptStr('anchor', anchor) + TkiOptStr('fill', fill) +
                 TkiOptStr('font', font)));
end;

function Canvas.create_line(x1, y1, x2, y2: Integer;
                            const fill: AnsiString): Integer;
begin
  create_line := TkiStrInt(TkEval(path + ' create line ' + TkiIntStr(x1) + ' ' +
                 TkiIntStr(y1) + ' ' + TkiIntStr(x2) + ' ' + TkiIntStr(y2) +
                 TkiOptStr('fill', fill)));
end;

function Canvas.create_rectangle(x1, y1, x2, y2: Integer;
                                 const outline, fill: AnsiString): Integer;
begin
  create_rectangle := TkiStrInt(TkEval(path + ' create rectangle ' +
                      TkiIntStr(x1) + ' ' + TkiIntStr(y1) + ' ' +
                      TkiIntStr(x2) + ' ' + TkiIntStr(y2) +
                      TkiOptStr('outline', outline) + TkiOptStr('fill', fill)));
end;

procedure Canvas.itemconfigure(item: Integer; const opts: AnsiString);
begin
  TkEval(path + ' itemconfigure ' + TkiIntStr(item) + ' ' + opts);
end;

procedure Canvas.delete_all;
begin
  TkEval(path + ' delete all');
end;

function Canvas.bbox(item: Integer): AnsiString;
begin
  bbox := TkEval(path + ' bbox ' + TkiIntStr(item));
end;

procedure Canvas.yview(const args: AnsiString);
begin
  TkEval(path + ' yview ' + args);
end;

procedure Canvas.yview_scroll(n: Integer; const what: AnsiString);
begin
  TkEval(path + ' yview scroll ' + TkiIntStr(n) + ' ' + what);
end;

procedure Canvas.xview(const args: AnsiString);
begin
  TkEval(path + ' xview ' + args);
end;

procedure Canvas.set_scrollregion(x1, y1, x2, y2: Integer);
begin
  TkEval(path + ' configure -scrollregion {' + TkiIntStr(x1) + ' ' +
         TkiIntStr(y1) + ' ' + TkiIntStr(x2) + ' ' + TkiIntStr(y2) + '}');
end;

{ ---- Scrollbar ----------------------------------------------------------- }

constructor Scrollbar.Create(master: Widget; const orient: AnsiString;
                            const command: AnsiString);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'scrollbar';
  TkEval('scrollbar ' + path + TkiOptStr('orient', orient) +
         TkiOptStr('command', command));
end;

procedure Scrollbar.set_(const first, last: AnsiString);
begin
  TkEval(path + ' set ' + first + ' ' + last);
end;

{ ---- Label / Entry / Checkbutton ---------------------------------------- }

constructor Label.Create(master: Widget; const text, anchor, font: AnsiString);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'label';
  TkEval('label ' + path + ' -text {' + text + '}' + TkiOptStr('anchor', anchor) +
         TkiOptStr('font', font));
end;

procedure Label.set_text(const value: AnsiString);
begin
  TkEval(path + ' configure -text {' + value + '}');
end;

constructor Entry.Create(master: Widget; const textvariable: AnsiString;
                        width: Integer);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'entry';
  TkEval('entry ' + path + TkiOptStr('textvariable', textvariable) +
         TkiOptInt('width', width));
end;

function Entry.get: AnsiString;
begin
  get := TkEval(path + ' get');
end;

procedure Entry.insert(index: Integer; const value: AnsiString);
begin
  TkEval(path + ' insert ' + TkiIntStr(index) + ' {' + value + '}');
end;

constructor Checkbutton.Create(master: Widget; const text, variable,
                              onvalue, offvalue: AnsiString);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'checkbutton';
  TkEval('checkbutton ' + path + ' -text {' + text + '}' +
         TkiOptStr('variable', variable) + TkiOptStr('onvalue', onvalue) +
         TkiOptStr('offvalue', offvalue));
end;

{ ---- variables ----------------------------------------------------------- }

function TkiNextVar: AnsiString;
begin
  gTkVarSeq := gTkVarSeq + 1;
  TkiNextVar := 'pyvar' + TkiIntStr(gTkVarSeq);
end;

constructor StringVar.Create;
begin
  TkiEnsureStarted;
  name := TkiNextVar;
  TkEval('set ' + name + ' {}');
end;

function StringVar.get: AnsiString;
begin
  get := TkEval('set ' + name);
end;

procedure StringVar.set_(const value: AnsiString);
begin
  TkEval('set ' + name + ' {' + value + '}');
end;

constructor BooleanVar.Create;
begin
  TkiEnsureStarted;
  name := TkiNextVar;
  TkEval('set ' + name + ' 0');
end;

function BooleanVar.get: Boolean;
begin
  get := TkEval('set ' + name) = '1';
end;

procedure BooleanVar.set_(value: Boolean);
begin
  if value then TkEval('set ' + name + ' 1')
  else TkEval('set ' + name + ' 0');
end;

{ ---- root --------------------------------------------------------------- }

constructor Tk.Create;
begin
  TkiEnsureStarted;
  path := '.';
  kind := 'toplevel';
end;

function Tk_: Widget;
var w: Widget;
begin
  TkiEnsureStarted;
  w := Widget.Create;
  w.path := '.';
  w.kind := 'toplevel';
  Tk_ := w;
end;

procedure mainloop;
begin
  TkiEnsureStarted;
  TkMainLoop;
end;

begin
  gTkWidgetSeq := 0;
  gTkVarSeq := 0;
  gTkStarted := False;
end.
