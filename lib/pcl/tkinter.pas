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

{ pylib on purpose. A façade's job is to accept what the APPLICATION writes, and
  real Python passes Python shapes: `create_window((0, 0), window=<widget>)` hands
  over a TUPLE and a widget OBJECT, not two ints and a Tcl path. Reading those
  needs the variant/TPyList runtime. Ruled in deliberately (Track U,
  decide-pcl-may-use-pylib): PCL is ours, and a façade that cannot take the
  argument the app already writes would push the edit into the app — exactly what
  the compile-as-is mission forbids. Pascal-only PCL users who never touch this
  unit never link it. }
uses tk, pylib, pyeval;

{ Tk's option WORDS, which tkinter exposes as module constants and applications
  write as `tk.BOTH` / `tk.LEFT`. They are the literal Tcl strings.

  Names that collide with a Pascal builtin are left out rather than renamed:
  a const called CHAR (the type) or INSERT (the procedure) ends the const
  block, and every constant declared after it silently disappears — which is
  how `tk.CENTER` came back as an undefined variable while `tk.WORD` resolved.
  Add such a name only with a spelling the frontend maps. }
const
  BOTH = 'both';
  X_ = 'x';
  Y_ = 'y';
  LEFT = 'left';
  RIGHT = 'right';
  TOP = 'top';
  BOTTOM = 'bottom';
  HORIZONTAL = 'horizontal';
  VERTICAL = 'vertical';
  WORD = 'word';
  { `END` is what an application writes (`text.delete("1.0", tk.END)`); Pascal
    reserves the word, so the constant is END_ and the frontend maps the
    qualified spelling onto it — the trailing-underscore convention the
    reserved METHOD names already use (set_, destroy_). }
  END_ = 'end';
  NW = 'nw';
  NE = 'ne';
  SW = 'sw';
  SE = 'se';
  CENTER = 'center';
  DISABLED = 'disabled';
  NORMAL = 'normal';

type
  { Tk's own error, which an application catches around clipboard and widget
    calls that can fail (`except tk.TclError:`). One class, like the rest of
    the NilPy exception surface. }
  TclError = class(Exception)
  end;

  Widget = class
  public
    path: AnsiString;         { the Tcl path name, e.g. `.w4.w9` }
    kind: AnsiString;         { `frame`, `canvas`, ... — for diagnostics }
    constructor Create;

    { geometry managers }
    { `expand=True` is what applications write, so it is a Variant: a bool, a
      number, or absent. }
    procedure pack(const side: AnsiString = ''; const fill: AnsiString = '';
                   const expand: Variant = 0; const padx: Variant = 0;
                   const pady: Variant = 0);
    { padx/pady are VARIANT: tkinter takes either a number or a (left, right)
      pair, and applications write both. See TkiOptPad. }
    procedure grid(row: Integer = -1; column: Integer = -1;
                   const sticky: AnsiString = '';
                   columnspan: Integer = -1; rowspan: Integer = -1;
                   const padx: Variant = 0; const pady: Variant = 0;
                   ipadx: Integer = -1; ipady: Integer = -1);
    procedure grid_columnconfigure(index: Integer = 0; weight: Integer = -1;
                                   minsize: Integer = -1; pad: Integer = -1);
    procedure grid_rowconfigure(index: Integer = 0; weight: Integer = -1;
                                minsize: Integer = -1; pad: Integer = -1);

    { common configuration. Two spellings on purpose: Python writes
      `w.configure(state="disabled")`, i.e. OPTIONS BY NAME, and NilPy binds
      keyword arguments by name over any subset — so the options an application
      actually sets are declared here as optional parameters. The raw-string form
      stays for anything not yet named (and is what the named form builds).
      An option this façade does not know is a compile error at the call site,
      which is the point: silently dropping a widget option would show up as a
      layout that is subtly wrong rather than as a diagnostic. }
    { yscrollcommand / xscrollcommand are VARIANT because Python passes a
      CALLABLE — `canvas.configure(yscrollcommand=self.scrollbar.set)` is the
      one spelling every scrollable widget uses. See TkiOptScrollCmd. }
    procedure configure(const state: AnsiString = ''; const scrollregion: AnsiString = '';
                        const yscrollcommand: Variant = 0;
                        const xscrollcommand: Variant = 0;
                        const text: AnsiString = ''; const background: AnsiString = '';
                        width: Integer = -1; height: Integer = -1);
    { the raw form, for an option this façade has not named yet }
    procedure configure_raw(const opts: AnsiString);
    function cget(const option: AnsiString): AnsiString;
    procedure bind(const sequence, script: AnsiString);
    { the Python spelling: a CALLABLE handler. `self._on_wheel` arrives as a
      bound-method variant and is invoked with an Event; `add="+"` appends to
      the existing binding instead of replacing it, exactly as tkinter's does. }
    procedure bind(const sequence: AnsiString; const callback: Variant;
                   const add: AnsiString = ''); overload;
    { the toplevel window this widget lives in, and its title bar — an editor
      shows the open document's name there }
    function winfo_toplevel: Widget;
    procedure title(const text: AnsiString);
    function winfo_width: Integer;
    function winfo_height: Integer;
    { Python hands back a LIST OF WIDGETS, and applications call methods on the
      elements (`for w in frame.winfo_children(): w.destroy()`). Returning the
      raw Tcl string made those elements strings. }
    function winfo_children: TPyList;
    { the widget that has keyboard focus, or nil — applications compare it to
      themselves (`if self.focus_get() == self`) }
    function focus_get: Widget;
    { the raw Tcl answer, for a caller that wants the paths }
    function winfo_children_paths: AnsiString;
    procedure destroy_;                    { `destroy` is a Pascal-ish trap }
    { process pending events without entering the main loop — what a test (and
      plenty of real code) uses to make geometry and bindings take effect }
    procedure update;
    procedure update_idletasks;
  end;

  Frame = class(Widget)
  public
    constructor Create(master: Widget; highlightthickness: Integer = -1;
                       const background: AnsiString = ''; width: Integer = -1;
                       height: Integer = -1);
  end;

  { ttk's PanedWindow — songformatter's editor is a horizontal split. Written
    `ttk.PanedWindow(...)`, and `ttk` resolves onto this unit, so the ttk
    widgets live here beside the classic ones and use the `ttk::` command
    prefix (see lib/pcl/tk.pas's note on why ttk is worth the prefix). }
  PanedWindow = class(Widget)
  public
    constructor Create(master: Widget; const orient: AnsiString = '';
                       width: Integer = -1; height: Integer = -1);
    { `paned.add(child, weight=1)` — a pane, optionally with a resize weight }
    procedure add(child: Widget; weight: Integer = -1);
  end;

  { A menu, and the popup an application posts on right-click. }
  Menu = class(Widget)
  public
    constructor Create(master: Widget; tearoff: Integer = -1);
    { `label` is what the application writes as a keyword, so that IS the
      parameter name — keyword arguments bind by name. }
    procedure add_command(const label: AnsiString; const command: Variant);
    procedure add_separator;
    { `post(x_root, y_root)` places the popup at a SCREEN coordinate }
    procedure post(x, y: Integer);
  end;

  { A multi-line text widget. The subset is what an editor needs: put text in,
    take it out, clear it, and set the options songformatter sets. }
  Text = class(Widget)
  public
    constructor Create(master: Widget; const wrap: AnsiString = '';
                       width: Integer = -1; height: Integer = -1;
                       const background: AnsiString = '');
    { Tk indices are strings ("1.0", "end"); an application writes them
      verbatim, so they stay strings here rather than being modelled. }
    procedure insert(const index_: AnsiString; const chars: AnsiString);
    procedure delete(const first_: AnsiString; const last_: AnsiString = '');
    function get(const first_: AnsiString; const last_: AnsiString = ''): AnsiString;
    procedure tag_add(const tagName, first_, last_: AnsiString);
    procedure event_generate(const sequence: AnsiString);
  end;

  Canvas = class(Widget)
  public
    constructor Create(master: Widget; highlightthickness: Integer = -1;
                       const background: AnsiString = ''; width: Integer = -1;
                       height: Integer = -1);
    function create_window(x, y: Integer; const window: AnsiString;
                           const anchor: AnsiString): Integer;
    { the Python spellings: a tuple coordinate and/or a widget as the window.
      `create_window((0, 0), window=self.content, anchor="nw")` is what tkinter
      applications actually write. }
    function create_window(const pos: Variant; window: Widget;
                           const anchor: AnsiString = ''): Integer; overload;
    function create_window(x, y: Integer; window: Widget;
                           const anchor: AnsiString = ''): Integer; overload;
    function create_text(x, y: Integer; const text: AnsiString;
                         const anchor: AnsiString = ''; const fill: AnsiString = '';
                         const font: AnsiString = ''): Integer;
    function create_line(x1, y1, x2, y2: Integer;
                         const fill: AnsiString = ''): Integer;
    function create_rectangle(x1, y1, x2, y2: Integer;
                              const outline: AnsiString = '';
                              const fill: AnsiString = ''): Integer;
    { the raw form, mirroring configure_raw: an option this façade has not
      named yet. Kept under a DIFFERENT name — a same-name overload made the
      keyword form ambiguous, and NilPy binds keyword arguments against the
      statically chosen overload. }
    procedure itemconfigure_raw(const item: Variant; const opts: AnsiString);
    { the Python spelling: options BY NAME, like Widget.configure }
    procedure itemconfigure(const item: Variant; width: Integer = -1;
                            height: Integer = -1; const state: AnsiString = '';
                            const fill: AnsiString = '';
                            const text: AnsiString = '');
    procedure delete_all;
    { An item is named by its ID or by a TAG — `canvas.bbox("all")` is the
      commonest call in the whole widget, so an Integer parameter refused the
      normal spelling. Variant takes both (see TkiItemSpec). }
    function bbox(const item: Variant): AnsiString;
    procedure yview(const args: AnsiString);
    procedure yview_scroll(n: Integer; const what: AnsiString);
    procedure xview(const args: AnsiString);
    procedure set_scrollregion(x1, y1, x2, y2: Integer);
  end;

  Scrollbar = class(Widget)
  public
    { `command=` takes the scrolled widget's own yview/xview METHOD in Python
      (`tk.Scrollbar(self, orient="vertical", command=self.canvas.yview)`), so
      it is a Variant. See TkiOptScrollCmd for how that is wired. }
    constructor Create(master: Widget; const orient: AnsiString = '';
                       const command: Variant = 0);
    procedure set_(const first, last: AnsiString);
  end;

  { Named exactly as Python names it. The trailing-underscore spelling was a
    symmetry habit, and it cost the mission its whole point: an application
    writes `tk.Label(...)` and must not have to write anything else. }
  Label = class(Widget)
  public
    { `font=` is a Tk font SPEC: a name, or the (family, size, style) tuple
      applications write — `font=("TkDefaultFont", 10, "bold")`. Variant takes
      both; see TkiOptFont. }
    constructor Create(master: Widget; const text: AnsiString = '';
                       const anchor: AnsiString = ''; const font: Variant = 0);
    procedure set_text(const value: AnsiString);
  end;

  Entry = class(Widget)
  public
    { `textvariable=` takes the VARIABLE OBJECT, like Checkbutton's `variable=` }
    constructor Create(master: Widget; const textvariable: Variant = 0;
                       width: Integer = -1);
    function get: AnsiString;
    procedure insert(index: Integer; const value: AnsiString);
  end;

  Checkbutton = class(Widget)
  public
    { `variable=` takes the VARIABLE OBJECT in Python, and on/offvalue are
      whatever type the variable holds — booleans for a BooleanVar. Variants
      accept all of it; TkiVarName reads a variable object's Tcl name. }
    constructor Create(master: Widget; const text: AnsiString = '';
                       const variable: Variant = 0;
                       const onvalue: Variant = 0;
                       const offvalue: Variant = 0;
                       const anchor: AnsiString = '';
                       const command: Variant = 0);
  end;

  { The event object a bound handler receives. Tk substitutes the % codes into
    the callback script and the dispatcher fills these in; the names are
    tkinter's, because handlers read them (`event.delta`, `event.width`). A
    field Tk did not substitute stays -1 / '' rather than guessing. }
  Event = class
  public
    x: Integer;
    y: Integer;
    delta: Integer;
    num: Integer;
    width: Integer;
    height: Integer;
    keysym: AnsiString;
    widget: AnsiString;
    constructor Create;
  end;

  { tkinter's variable objects. A Tcl variable by name, which is how the real
    thing works too. }
  StringVar = class
  public
    name: AnsiString;
    { `StringVar(value="x")` — tkinter's initial value, by keyword }
    constructor Create(const value: AnsiString = '');
    function get: AnsiString;
    procedure set_(const value: AnsiString);
    { the Python spelling of a variable trace: `var.trace_add("write", cb)` }
    procedure trace_add(const mode: AnsiString; const callback: Variant);
  end;

  BooleanVar = class
  public
    name: AnsiString;
    { `BooleanVar(value=True)`. Variant so an omitted value stays distinct from
      False, which the Tcl variable must not start as when nothing was asked. }
    constructor Create(const value: Variant = 0);
    function get: Boolean;
    procedure set_(value: Boolean);
    { the Python spelling of a variable trace: `var.trace_add("write", cb)` }
    procedure trace_add(const mode: AnsiString; const callback: Variant);
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
{ A MULTI-WORD value must be braced: Tcl splits on spaces, so
  `-scrollregion 0 0 500 1026` reached Tk as the option value `0` plus three
  stray arguments — the canvas kept a one-element scrollregion and nothing
  said so. Values without a space are left bare, which keeps every existing
  command string byte-identical. }
var i: Integer; hasSpace: Boolean;
begin
  if value = '' then begin TkiOptStr := ''; Exit; end;
  hasSpace := False;
  for i := 1 to Length(value) do
    if value[i] = ' ' then hasSpace := True;
  if hasSpace then TkiOptStr := ' -' + name + ' {' + value + '}'
  else TkiOptStr := ' -' + name + ' ' + value;
end;

function TkiOptInt(const name: AnsiString; value: Integer): AnsiString;
begin
  if value < 0 then TkiOptInt := ''
  else TkiOptInt := ' -' + name + ' ' + TkiIntStr(value);
end;

{ A SCROLL-WIRING option: `-yscrollcommand`, `-xscrollcommand`, and a
  scrollbar's `-command`. Python hands each of them a BOUND METHOD of the other
  widget (`self.scrollbar.set`, `self.canvas.yview`), and CPython's tkinter does
  not call back into Python for these at all — it wires Tcl straight to the
  other widget's own subcommand, which is why scrolling stays smooth. Same here:
  the receiver gives the widget PATH and the option decides the subcommand, so
  Tk drives both ends itself.

  The receiver's METHOD NAME is not recoverable from a bound-method value, and
  the option name determines it anyway — a scrollbar's command is the scrolled
  widget's yview/xview, a widget's yscrollcommand is the scrollbar's set. A
  callable that is NOT a widget method (a plain def, a lambda) needs the
  callback registry to receive Tcl's own arguments, which the dispatcher cannot
  do yet: it is refused loudly rather than wired to something wrong
  (feature-lib-tkinter-callable-options-with-args). A STRING still passes
  through verbatim, which is the raw Tcl form this unit has always taken. }
function TkiOptScrollCmd(const name: AnsiString; const v: Variant;
                         const subcmd: AnsiString): AnsiString;
var o: TObject;
begin
  Result := '';
  case pyvartag(v) of
    0: Exit;                                  { omitted }
    6: begin                                  { a raw Tcl script }
         if pystr_of(v) = '' then Exit;
         Result := ' -' + name + ' {' + pystr_of(v) + '}';
       end;
    8: begin                                  { a bound method: {code, receiver} }
         o := TObject(pybound_recv(v));
         if (o <> nil) and (o is Widget) then
           Result := ' -' + name + ' {' + Widget(o).path + ' ' + subcmd + '}'
         else
         begin
           WriteLn('tkinter: -', name,
                   ' needs a widget method or a Tcl script (a plain callable ',
                   'cannot receive Tk''s scroll arguments yet)');
           Halt(1);
         end;
       end;
  else
    WriteLn('tkinter: -', name, ' takes a widget method or a Tcl script');
    Halt(1);
  end;
end;

{ A canvas ITEM SPEC: the integer id create_* handed back, or a TAG name —
  `canvas.bbox("all")`, `canvas.itemconfigure("chords", state="hidden")`. Tk
  takes either in the same position, so the façade must too. }
function TkiItemSpec(const item: Variant): AnsiString;
begin
  if pyvartag(item) = 6 then Result := pystr_of(item)
  else Result := TkiIntStr(Integer(pyvar_to_int(item)));
end;

{ ---- Widget -------------------------------------------------------------- }

constructor Widget.Create;
begin
  path := '';
  kind := '';
end;

procedure Widget.pack(const side: AnsiString; const fill: AnsiString;
                     const expand, padx, pady: Variant);
var opts: AnsiString;
begin
  opts := TkiOptStr('side', side) + TkiOptStr('fill', fill) +
          TkiOptVar('expand', expand) + TkiOptPad('padx', padx) +
          TkiOptPad('pady', pady);
  TkEval('pack ' + path + opts);
end;

function TkiOptPad(const name: AnsiString; const p: Variant): AnsiString;
{ A padding option: absent (None), a NUMBER, or a (left, right) PAIR — Tk spells
  the pair `-padx {8 6}`. The pair is what a tkinter application writes when the
  two sides differ, and it arrives here as a TPyList. }
var l: TPyList; i: Integer; body: AnsiString;
begin
  Result := '';
  case pyvartag(p) of
    0: Exit;                                   { None / omitted }
    7:
      begin
        l := TPyList(pyvarobj(p));
        if (l = nil) or (l.count = 0) then Exit;
        body := '';
        for i := 0 to l.count - 1 do
        begin
          if i > 0 then body := body + ' ';
          body := body + TkiIntStr(pyvar_to_int(l.at(i)));
        end;
        Result := ' -' + name + ' {' + body + '}';
      end;
  else
    Result := ' -' + name + ' ' + TkiIntStr(pyvar_to_int(p));
  end;
end;

procedure Widget.grid(row: Integer; column: Integer; const sticky: AnsiString;
                      columnspan, rowspan: Integer;
                      const padx, pady: Variant; ipadx, ipady: Integer);
begin
  TkEval('grid ' + path + TkiOptInt('row', row) + TkiOptInt('column', column) +
         TkiOptStr('sticky', sticky) +
         TkiOptInt('columnspan', columnspan) + TkiOptInt('rowspan', rowspan) +
         TkiOptPad('padx', padx) + TkiOptPad('pady', pady) +
         TkiOptInt('ipadx', ipadx) + TkiOptInt('ipady', ipady));
end;

procedure Widget.grid_columnconfigure(index, weight, minsize, pad: Integer);
begin
  TkEval('grid columnconfigure ' + path + ' ' + TkiIntStr(index) +
         TkiOptInt('weight', weight) + TkiOptInt('minsize', minsize) +
         TkiOptInt('pad', pad));
end;

procedure Widget.grid_rowconfigure(index, weight, minsize, pad: Integer);
begin
  TkEval('grid rowconfigure ' + path + ' ' + TkiIntStr(index) +
         TkiOptInt('weight', weight) + TkiOptInt('minsize', minsize) +
         TkiOptInt('pad', pad));
end;

procedure Widget.configure_raw(const opts: AnsiString);
begin
  TkEval(path + ' configure ' + opts);
end;

procedure Widget.configure(const state, scrollregion: AnsiString;
                           const yscrollcommand, xscrollcommand: Variant;
                           const text, background: AnsiString;
                           width, height: Integer);
var o: AnsiString;
begin
  o := TkiOptStr('state', state) + TkiOptStr('scrollregion', scrollregion)
     + TkiOptScrollCmd('yscrollcommand', yscrollcommand, 'set')
     + TkiOptScrollCmd('xscrollcommand', xscrollcommand, 'set')
     + TkiOptStr('text', text) + TkiOptStr('background', background)
     + TkiOptInt('width', width) + TkiOptInt('height', height);
  if o <> '' then TkEval(path + ' configure' + o);
end;

function Widget.cget(const option: AnsiString): AnsiString;
begin
  cget := TkEval(path + ' cget -' + option);
end;

{ ===== callbacks =====

  One Tcl command, `pxxcb`, dispatches every Python callable the application
  registered. The script Tk evaluates carries the registry index and the %
  substitutions the binding asked for:  `{pxxcb 3 %x %y %D %b %w %h %K %W}`.
  A `-command` option has no event, so it registers `{pxxcb 3}` and the handler
  is called with no argument. }
const
  TKI_MAX_CALLBACKS = 512;

type
  TTkiFn0 = function: Int64;
  TTkiFn1 = function(const a0: Variant): Int64;

var
  gTkCb: array[0..TKI_MAX_CALLBACKS - 1] of Variant;
  gTkCbCount: Integer;
  gTkCbReady: Boolean;

procedure TkiCallValue(const cb: Variant; const arg: Variant; withArg: Boolean);
{ Every Python callable shape a façade meets: a BOUND METHOD (tag 8, {code,
  receiver}), a pyeval CLOSURE, a lifted bound-fn, and a plain compiled def
  (its code ADDRESS). The dispatch itself lives in pyeval as pycall_value —
  two of those four kinds are pyeval's own objects, and every library that
  takes a callable needs the same four-way test (atexit does too). }
begin
  pycall_value(cb, arg, withArg);
end;

function TkiCbArgInt(argc: Integer; argv: PPAnsiChar; i: Integer): Integer;
{ A % substitution Tk could not fill arrives as '??'. Report it as -1 rather
  than as a number the handler would believe. }
var s: AnsiString;
begin
  s := TkCmdArg(argc, argv, i);
  if (s = '') or (s = '??') then TkiCbArgInt := -1
  else TkiCbArgInt := TkiStrInt(s);
end;

function TkiCbDispatch(clientData: Pointer; interp: Pointer;
                       argc: Integer; argv: PPAnsiChar): Integer; cdecl;
var idx: Integer; ev: Event; evv: Variant;
begin
  TkiCbDispatch := 0;                       { TCL_OK }
  idx := TkiStrInt(TkCmdArg(argc, argv, 1));
  if (idx < 0) or (idx >= gTkCbCount) then Exit;
  if argc <= 2 then
  begin
    { a `-command` callback: no event argument }
    TkiCallValue(gTkCb[idx], pynone, False);
    Exit;
  end;
  ev := Event.Create;
  ev.x := TkiCbArgInt(argc, argv, 2);
  ev.y := TkiCbArgInt(argc, argv, 3);
  ev.delta := TkiCbArgInt(argc, argv, 4);
  ev.num := TkiCbArgInt(argc, argv, 5);
  ev.width := TkiCbArgInt(argc, argv, 6);
  ev.height := TkiCbArgInt(argc, argv, 7);
  ev.keysym := TkCmdArg(argc, argv, 8);
  ev.widget := TkCmdArg(argc, argv, 9);
  PPyVarRec(@evv)^.VType := 7;              { VT_OBJECT }
  PPyVarRec(@evv)^.Payload := Int64(NativeInt(Pointer(ev)));
  PXXObjRetain(Pointer(ev));
  TkiCallValue(gTkCb[idx], evv, True);
end;

function TkiRegisterCallback(const cb: Variant): Integer;
{ Store the callable and return its index. The registry holds the value for the
  process's lifetime — a widget's binding outlives every local that built it,
  and a Tk application's callbacks are few and permanent. }
begin
  if not gTkCbReady then
  begin
    TkRegisterCommand('pxxcb', @TkiCbDispatch);
    gTkCbReady := True;
  end;
  if gTkCbCount >= TKI_MAX_CALLBACKS then
  begin
    TkiRegisterCallback := -1;
    Exit;
  end;
  gTkCb[gTkCbCount] := cb;
  TkiRegisterCallback := gTkCbCount;
  gTkCbCount := gTkCbCount + 1;
end;

{ The script Tk runs for a BOUND event: index plus the substitutions the event
  object exposes. }
function TkiCbScript(idx: Integer): AnsiString;
begin
  TkiCbScript := 'pxxcb ' + TkiIntStr(idx) +
                 ' %x %y %D %b %w %h %K %W';
end;

constructor Event.Create;
begin
  x := -1; y := -1; delta := -1; num := -1; width := -1; height := -1;
  keysym := ''; widget := '';
end;

procedure Widget.bind(const sequence: AnsiString; const callback: Variant;
                      const add: AnsiString);
var idx: Integer; op: AnsiString;
begin
  idx := TkiRegisterCallback(callback);
  if idx < 0 then Exit;
  if add = '' then op := '' else op := '+';
  TkEval('bind ' + path + ' ' + sequence + ' {' + op + TkiCbScript(idx) + '}');
end;

function Widget.winfo_toplevel: Widget;
var w: Widget;
begin
  w := Widget.Create;
  w.path := TkEval('winfo toplevel ' + path);
  w.kind := 'toplevel';
  winfo_toplevel := w;
end;

procedure Widget.title(const text: AnsiString);
begin
  TkEval('wm title ' + path + ' {' + text + '}');
end;

procedure Widget.update;
begin
  TkEval('update');
end;

procedure Widget.update_idletasks;
begin
  TkEval('update idletasks');
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

function Widget.focus_get: Widget;
var p: AnsiString;
begin
  Result := nil;
  p := TkEval('focus');
  if p = '' then Exit;
  Result := Widget.Create;
  Result.path := p;
  Result.kind := 'widget';
end;

function Widget.winfo_children_paths: AnsiString;
begin
  winfo_children_paths := TkEval('winfo children ' + path);
end;

function Widget.winfo_children: TPyList;
var raw, cur: AnsiString; i: Integer; w: Widget; v: Variant;
begin
  Result := TPyList.Create;
  raw := TkEval('winfo children ' + path);
  cur := '';
  for i := 1 to Length(raw) + 1 do
  begin
    if (i > Length(raw)) or (raw[i] = ' ') then
    begin
      if cur <> '' then
      begin
        w := Widget.Create;
        w.path := cur;
        w.kind := 'widget';
        PPyVarRec(@v)^.VType := 7;
        PPyVarRec(@v)^.Payload := Int64(NativeInt(Pointer(w)));
        PXXObjRetain(Pointer(w));
        Result.append(v);
      end;
      cur := '';
    end
    else
      cur := cur + raw[i];
  end;
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

{ ---- PanedWindow (ttk) ---------------------------------------------------- }

constructor PanedWindow.Create(master: Widget; const orient: AnsiString;
                               width: Integer; height: Integer);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'panedwindow';
  TkEval('ttk::panedwindow ' + path + TkiOptStr('orient', orient) +
         TkiOptInt('width', width) + TkiOptInt('height', height));
end;

procedure PanedWindow.add(child: Widget; weight: Integer);
begin
  if child = nil then Exit;
  TkEval(path + ' add ' + child.path + TkiOptInt('weight', weight));
end;

{ ---- Menu ---------------------------------------------------------------- }

constructor Menu.Create(master: Widget; tearoff: Integer);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'menu';
  TkEval('menu ' + path + TkiOptInt('tearoff', tearoff));
end;

procedure Menu.add_command(const label: AnsiString; const command: Variant);
var cbIdx: Integer;
begin
  { `command=` is a CALLABLE in Python — routed through the same callback
    registry every other command option uses. }
  cbIdx := TkiRegisterCallback(command);
  if cbIdx < 0 then
    TkEval(path + ' add command' + TkiOptStr('label', label))
  else
    TkEval(path + ' add command' + TkiOptStr('label', label) +
           ' -command {' + TkiCbScript(cbIdx) + '}');
end;

procedure Menu.add_separator;
begin
  TkEval(path + ' add separator');
end;

procedure Menu.post(x, y: Integer);
begin
  TkEval(path + ' post ' + TkiIntStr(x) + ' ' + TkiIntStr(y));
end;

{ ---- Text ---------------------------------------------------------------- }

constructor Text.Create(master: Widget; const wrap: AnsiString;
                        width: Integer; height: Integer;
                        const background: AnsiString);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'text';
  TkEval('text ' + path + TkiOptStr('wrap', wrap) + TkiOptInt('width', width) +
         TkiOptInt('height', height) + TkiOptStr('background', background));
end;

procedure Text.insert(const index_: AnsiString; const chars: AnsiString);
begin
  TkEval(path + ' insert ' + index_ + ' {' + chars + '}');
end;

procedure Text.delete(const first_: AnsiString; const last_: AnsiString);
begin
  if last_ = '' then TkEval(path + ' delete ' + first_)
  else TkEval(path + ' delete ' + first_ + ' ' + last_);
end;

function Text.get(const first_: AnsiString; const last_: AnsiString): AnsiString;
begin
  if last_ = '' then get := TkEval(path + ' get ' + first_)
  else get := TkEval(path + ' get ' + first_ + ' ' + last_);
end;

procedure Text.tag_add(const tagName, first_, last_: AnsiString);
begin
  TkEval(path + ' tag add ' + tagName + ' ' + first_ + ' ' + last_);
end;

procedure Text.event_generate(const sequence: AnsiString);
begin
  TkEval('event generate ' + path + ' ' + sequence);
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

function Canvas.create_window(const pos: Variant; window: Widget;
                              const anchor: AnsiString): Integer;
{ `pos` is a 2-sequence (Python tuple or list — both are a TPyList here). }
var px, py: Integer;
begin
  px := pyvar_to_int(pyvar_getitem(pos, 0));
  py := pyvar_to_int(pyvar_getitem(pos, 1));
  create_window := create_window(px, py, window, anchor);
end;

function Canvas.create_window(x, y: Integer; window: Widget;
                              const anchor: AnsiString): Integer;
begin
  if window = nil then
    create_window := create_window(x, y, '', anchor)
  else
    create_window := create_window(x, y, window.path, anchor);
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

procedure Canvas.itemconfigure(const item: Variant; width, height: Integer;
                               const state, fill, text: AnsiString);
begin
  itemconfigure_raw(item, TkiOptInt('width', width) + TkiOptInt('height', height) +
                TkiOptStr('state', state) + TkiOptStr('fill', fill) +
                TkiOptStr('text', text));
end;

procedure Canvas.itemconfigure_raw(const item: Variant; const opts: AnsiString);
begin
  TkEval(path + ' itemconfigure ' + TkiItemSpec(item) + ' ' + opts);
end;

procedure Canvas.delete_all;
begin
  TkEval(path + ' delete all');
end;

function Canvas.bbox(const item: Variant): AnsiString;
begin
  bbox := TkEval(path + ' bbox ' + TkiItemSpec(item));
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
                            const command: Variant);
var sub: AnsiString;
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'scrollbar';
  { a vertical scrollbar drives the widget's yview, a horizontal one its xview }
  if orient = 'horizontal' then sub := 'xview' else sub := 'yview';
  TkEval('scrollbar ' + path + TkiOptStr('orient', orient) +
         TkiOptScrollCmd('command', command, sub));
end;

procedure Scrollbar.set_(const first, last: AnsiString);
begin
  TkEval(path + ' set ' + first + ' ' + last);
end;

{ ---- Label / Entry / Checkbutton ---------------------------------------- }

function TkiOptFont(const f: Variant): AnsiString;
{ A font option: absent, a NAME, or the (family, size, style) tuple. Tk spells
  the tuple as a braced list, `-font {TkDefaultFont 10 bold}`. }
var l: TPyList; i: Integer; body: AnsiString; el: Variant;
begin
  Result := '';
  case pyvartag(f) of
    0: Exit;
    7:
      begin
        l := TPyList(pyvarobj(f));
        if (l = nil) or (l.count = 0) then Exit;
        body := '';
        for i := 0 to l.count - 1 do
        begin
          if i > 0 then body := body + ' ';
          el := l.at(i);
          if (pyvartag(el) = 5) or (pyvartag(el) = 6) then body := body + VariantToStr(el)
          else body := body + TkiIntStr(pyvar_to_int(el));
        end;
        Result := ' -font {' + body + '}';
      end;
    5, 6: Result := ' -font {' + VariantToStr(f) + '}';
  end;
end;

constructor Label.Create(master: Widget; const text, anchor: AnsiString;
                        const font: Variant);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'label';
  TkEval('label ' + path + ' -text {' + text + '}' + TkiOptStr('anchor', anchor) +
         TkiOptFont(font));
end;

procedure Label.set_text(const value: AnsiString);
begin
  TkEval(path + ' configure -text {' + value + '}');
end;

constructor Entry.Create(master: Widget; const textvariable: Variant;
                        width: Integer);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'entry';
  TkEval('entry ' + path + TkiOptStr('textvariable', TkiVarName(textvariable)) +
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

function TkiVarName(const v: Variant): AnsiString;
{ The Tcl name behind a variable OBJECT (StringVar / BooleanVar), or the string
  itself when a caller passed the name directly. Absent yields ''. }
var o: TObject;
begin
  Result := '';
  case pyvartag(v) of
    0: Exit;
    7:
      begin
        o := TObject(pyvarobj(v));
        if o is StringVar then Result := StringVar(o).name
        else if o is BooleanVar then Result := BooleanVar(o).name;
      end;
    5, 6: Result := VariantToStr(v);
  end;
end;

function TkiOptVar(const name: AnsiString; const v: Variant): AnsiString;
{ An option whose value may be a number, a bool, a string or None. }
begin
  Result := '';
  case pyvartag(v) of
    0: Exit;
    4: if bool(v) then Result := ' -' + name + ' 1' else Result := ' -' + name + ' 0';
    5, 6: Result := ' -' + name + ' {' + VariantToStr(v) + '}';
  else
    Result := ' -' + name + ' ' + TkiIntStr(pyvar_to_int(v));
  end;
end;

constructor Checkbutton.Create(master: Widget; const text: AnsiString;
                              const variable, onvalue, offvalue: Variant;
                              const anchor: AnsiString;
                              const command: Variant);
var vn: AnsiString; idx: Integer;
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'checkbutton';
  vn := TkiVarName(variable);
  TkEval('checkbutton ' + path + ' -text {' + text + '}' +
         TkiOptStr('variable', vn) + TkiOptVar('onvalue', onvalue) +
         TkiOptVar('offvalue', offvalue) + TkiOptStr('anchor', anchor));
  if pyvartag(command) <> 0 then
  begin
    idx := TkiRegisterCallback(command);
    if idx >= 0 then
      TkEval(path + ' configure -command {pxxcb ' + TkiIntStr(idx) + '}');
  end;
end;

{ ---- variables ----------------------------------------------------------- }

function TkiNextVar: AnsiString;
begin
  gTkVarSeq := gTkVarSeq + 1;
  TkiNextVar := 'pyvar' + TkiIntStr(gTkVarSeq);
end;

constructor StringVar.Create(const value: AnsiString);
begin
  TkiEnsureStarted;
  name := TkiNextVar;
  TkEval('set ' + name + ' {' + value + '}');
end;

function StringVar.get: AnsiString;
begin
  get := TkEval('set ' + name);
end;

procedure StringVar.set_(const value: AnsiString);
begin
  TkEval('set ' + name + ' {' + value + '}');
end;

procedure StringVar.trace_add(const mode: AnsiString; const callback: Variant);
{ same Tcl trace as BooleanVar's — see the note there. An Entry's textvariable
  is a StringVar, so this is the spelling an editable field actually uses. }
var idx: Integer; op: AnsiString;
begin
  idx := TkiRegisterCallback(callback);
  if idx < 0 then Exit;
  if mode = '' then op := 'write' else op := mode;
  TkEval('trace add variable ' + name + ' ' + op + ' {pxxcb ' + TkiIntStr(idx) + '}');
end;

constructor BooleanVar.Create(const value: Variant);
var v: AnsiString;
begin
  TkiEnsureStarted;
  name := TkiNextVar;
  if bool(value) then v := '1' else v := '0';
  TkEval('set ' + name + ' ' + v);
end;

procedure BooleanVar.trace_add(const mode: AnsiString; const callback: Variant);
{ Tcl's variable trace: `trace add variable <name> write {pxxcb N}`. The
  callback runs with the three Tcl trace arguments appended, which the
  dispatcher ignores — tkinter's own trace_add hands its callback the same
  three and most handlers ignore them too. }
var idx: Integer; op: AnsiString;
begin
  idx := TkiRegisterCallback(callback);
  if idx < 0 then Exit;
  if mode = '' then op := 'write' else op := mode;
  TkEval('trace add variable ' + name + ' ' + op + ' {pxxcb ' + TkiIntStr(idx) + '}');
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
