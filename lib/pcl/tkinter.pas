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
    reserved METHOD name `destroy_` also uses. }
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
    calls that can fail (`except tk.TclError:`). Descends from pylib's
    PyException — the PYTHON root, which this unit reaches through `uses pylib`
    — not from sysutils' Pascal `Exception`, which this unit does not import at
    all and which only resolved here while `uses` was transitive and the two
    roots shared a name. decide-pylib-exception-vs-sysutils-exception option 5. }
  TclError = class(PyException)
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
    procedure configure(const state: AnsiString = ''; const scrollregion: Variant = 0;
                        const yscrollcommand: Variant = 0;
                        const xscrollcommand: Variant = 0;
                        const text: AnsiString = ''; const background: AnsiString = '';
                        width: Integer = -1; height: Integer = -1;
                        { a MENU option, declared here rather than as a Menu
                          overload: NilPy binds keyword arguments against the
                          statically chosen overload, so a same-named one is
                          not reachable by keyword (see configure_raw's note).
                          `m.configure(postcommand=fn)` runs fn just before the
                          menu posts — how an application greys entries out at
                          the last moment. }
                        const postcommand: Variant = 0);
    { `w.config(...)` — tkinter's own short spelling of configure, and what a
      real application writes about as often as the long one. }
    procedure config(const state: AnsiString = ''; const scrollregion: Variant = 0;
                     const yscrollcommand: Variant = 0;
                     const xscrollcommand: Variant = 0;
                     const text: AnsiString = ''; const background: AnsiString = '';
                     width: Integer = -1; height: Integer = -1;
                     { `root.config(menu=menubar)` — how a window's menu bar is
                       attached, and the only option here that takes a WIDGET. }
                     menu: Widget = nil;
                     const postcommand: Variant = 0);
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
    { `root.protocol("WM_DELETE_WINDOW", on_close)` — the window-manager hook an
      application uses to save its session before the window closes. }
    procedure protocol(const name: AnsiString; const callback: Variant);
    function winfo_width: Integer;
    function winfo_height: Integer;
    { Python hands back a LIST OF WIDGETS, and applications call methods on the
      elements (`for w in frame.winfo_children(): w.destroy()`). Returning the
      raw Tcl string made those elements strings. }
    function winfo_children: TPyList;
    { tkinter keeps a `children` dict on every widget, keyed by the child's
      name, and an application clears it after destroying the children to drop
      the stale references (`pane.children.clear()`). Built on demand from Tk's
      own answer: clearing the returned dict drops OUR references, which is all
      the application is after — Tk's bookkeeping went with destroy(). }
    function GetChildren: TPyDict;
    property children: TPyDict read GetChildren;
    { the widget that has keyboard focus, or nil — applications compare it to
      themselves (`if self.focus_get() == self`) }
    function focus_get: Widget;
    { `w.focus_set()` — give this widget the keyboard focus; `focus_force` takes
      it even when the window manager has not given the toplevel focus yet, and
      `focus()` is tkinter's short spelling of the same thing. An editor calls
      these every time it opens or switches a document. }
    procedure focus_set;
    procedure focus_force;
    procedure focus;
    { the raw Tcl answer, for a caller that wants the paths }
    function winfo_children_paths: AnsiString;
    { Tk's timer queue. `after(ms, cb)` and `after_idle(cb)` return the Tcl id
      the application stores to cancel with — a debounce (`self._preview_job =
      cv.after(120, redraw)`) re-arms on every keystroke, so the id round trip
      has to work or the registry fills up. The callback slot is ONE-SHOT: it is
      handed back when the timer fires or is cancelled. }
    function after(ms: Integer; const callback: Variant): AnsiString;
    function after_idle(const callback: Variant): AnsiString;
    procedure after_cancel(const id: Variant);
    { the window-stacking and icon-state calls a secondary window needs to be
      brought back up (`analysis_window.deiconify(); analysis_window.lift()`) }
    procedure lift;
    procedure lower;                      { Python's name; PXX parses it contextually }
    procedure deiconify;
    procedure iconify;
    { the X selection, as tkinter exposes it on every widget }
    function clipboard_get: AnsiString;
    procedure clipboard_clear;
    procedure clipboard_append(const text: AnsiString);
    { NOT `destroy`: Pascal is case-insensitive, so that name is every
      `destructor Destroy` in the RTL and PCL at once, and a dynamically-typed
      `widget.destroy()` then has too many candidate classes to dispatch. The
      frontend maps Python's spelling onto this one (pyparser.inc). }
    procedure destroy_;
    { process pending events without entering the main loop — what a test (and
      plenty of real code) uses to make geometry and bindings take effect }
    procedure update;
    procedure update_idletasks;
    { tkinter puts mainloop/quit on EVERY widget, and `root.mainloop()` is how
      an application spells its event loop. Without the method the call fell
      through closed-world dispatch to a nil code pointer — a SIGSEGV the
      instant the loop was entered, with no diagnostic. }
    procedure mainloop;
    procedure quit;
  end;

  Frame = class(Widget)
  public
    { `padding` is ttk's, and an application writes it as a tuple:
      `ttk.Frame(root, padding=(8, 6))`. }
    constructor Create(master: Widget; highlightthickness: Integer = -1;
                       const background: AnsiString = ''; width: Integer = -1;
                       height: Integer = -1; const padding: Variant = 0);
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
    { `paned.sashpos(0, 300)` places the divider; the one-argument form reads
      it. An editor sets this to give the source pane its share on startup. }
    function sashpos(index: Integer): Integer; overload;
    procedure sashpos(index, newpos: Integer); overload;
  end;

  { ttk's Notebook — a tab strip. songformatter's whole multi-document UI is
    this widget: one tab per open song, plus a Settings tab.

    A tab is identified by the CHILD WIDGET in Python (`nb.select(doc)`), and
    Tcl identifies it by the child's PATH, so the two are the same thing once
    `.path` is read. `tabs()` gives those paths back as a Python list of
    strings, and `nametowidget` turns one into the widget again — which is why
    this unit keeps a path -> Widget registry. }
  Notebook = class(Widget)
  public
    constructor Create(master: Widget; width: Integer = -1; height: Integer = -1);
    { `nb.add(child, text="Documents")` }
    procedure add(child: Widget; const text: AnsiString = '');
    { `nb.select()` reads the current tab's path; `nb.select(child)` switches;
      `nb.select(2)` switches by INDEX (what a session restore hands back).
      All three are FUNCTIONS returning the path: a receiver whose class is
      only known at run time dispatches by name, and overloads that disagree on
      whether they return anything cannot be given one type — the call then
      failed with "annotate the type / too dynamic". Tk's own `select` answers
      with the path in every form, so this is also what tkinter does. }
    function select: AnsiString; overload;
    function select(child: Widget): AnsiString; overload;
    function select(index: Integer): AnsiString; overload;
    { `nb.tab(child, text=...)` renames a tab — how a title follows its
      document. The read form is not modelled. }
    procedure tab(child: Widget; const text: AnsiString);
    { every tab's path, in order }
    function tabs: TPyList;
    { `nb.index("current")` — the selected tab's position, or the count for
      "end". Any other index expression is passed to Tcl as written. }
    function index(const which: AnsiString): Integer;
    procedure forget(child: Widget);
    { The widget a path names — the inverse of what tabs() yields. VARIANT, not
      Widget: the caller gets back whatever class was added (songformatter's
      tabs hold FormatText editors and it calls their own methods), and only a
      dynamic value can carry that. Typed `Widget` the result answered to the
      base class alone. }
    function nametowidget(const path: AnsiString): Variant;
  end;

  { A menu, and the popup an application posts on right-click. }
  Menu = class(Widget)
  public
    constructor Create(master: Widget; tearoff: Integer = -1);
    { `label` is what the application writes as a keyword, so that IS the
      parameter name — keyword arguments bind by name. }
    procedure add_command(const label: AnsiString; const command: Variant = 0;
                          const accelerator: AnsiString = '';
                          const state: AnsiString = '');
    procedure add_separator;
    { `menubar.add_cascade(label="File", menu=file_menu)` — a submenu. }
    procedure add_cascade(const label: AnsiString; menu: Widget = nil);
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
    procedure insert(const index: AnsiString; const chars: AnsiString);
    procedure delete(const first: AnsiString; const last: AnsiString = '');
    function get(const first: AnsiString; const last: AnsiString = ''): AnsiString;
    procedure tag_add(const tagName, first, last: AnsiString);
    { Style a tag: the options a rendered document needs. A tag is applied to a
      RANGE by tag_add, so text inserted between two `index` reads can be given
      a font, a colour, margins or spacing. }
    procedure tag_configure(const tagName: AnsiString;
                            const font: AnsiString = '';
                            const foreground: AnsiString = '';
                            const background: AnsiString = '';
                            const justify: AnsiString = '';
                            const underline: Variant = 0;
                            spacing1: Integer = -1; spacing3: Integer = -1;
                            lmargin1: Integer = -1; lmargin2: Integer = -1);
    { Tk's own index arithmetic, resolved to a concrete `line.char` — the
      caller records where a run STARTED before inserting it. }
    function index(const idx: AnsiString): AnsiString;
    procedure event_generate(const sequence: AnsiString);
    { scroll an index into view, and move a MARK (`insert` is the caret) —
      what "paste, then put the caret at the top" is made of }
    procedure see(const idx: AnsiString);
    procedure mark_set(const markName, idx: AnsiString);
    { The other half of the scrollbar wiring. A scrolled Text is written
      `sb.config(command=text.yview)` + `text.configure(yscrollcommand=sb.set)`,
      and Canvas has carried these since it was written — Text never did, so the
      canonical scrolled-TEXT pair raised `'Text' object has no attribute
      'yview'` at the moment Tk first drove the scrollbar. It reached the user as
      `'Scrollbar' object has no attribute 'set'`, which points at the healthy
      half of the pair. Found porting tkhtmlview. }
    procedure yview(const args: AnsiString);
    procedure yview_scroll(n: Integer; const what: AnsiString);
    procedure xview(const args: AnsiString);
  end;

  { An image Tk can draw on a canvas. THE SUBSET: `PhotoImage(data=<base64
    PNG>)`, which is how an application hands Tk an in-memory image without a
    temporary file — and `file=` for one on disk. Tk owns the pixels; keeping
    the object alive is the caller's job, as in tkinter. }
  PhotoImage = class
  public
    name: AnsiString;         { the Tcl image name }
    constructor Create(const data: Variant; const file: AnsiString = '');
    function width: Integer;
    function height: Integer;
  end;

  Canvas = class(Widget)
  public
    constructor Create(master: Widget; highlightthickness: Integer = -1;
                       const background: AnsiString = ''; width: Integer = -1;
                       height: Integer = -1;
                       { a canvas driving a scrollbar reports its position the
                         same way a Text widget does — `yscrollcommand=yscroll.set` }
                       const yscrollcommand: Variant = 0;
                       const xscrollcommand: Variant = 0;
                       const scrollregion: AnsiString = '';
                       const cursor: AnsiString = '';
                       borderwidth: Integer = -1);
    function create_window(x, y: Integer; const window: AnsiString;
                           const anchor: AnsiString): Integer;
    { the Python spellings: a tuple coordinate and/or a widget as the window.
      `create_window((0, 0), window=self.content, anchor="nw")` is what tkinter
      applications actually write. }
    function create_window(const pos: Variant; window: Widget;
                           const anchor: AnsiString = ''): Integer; overload;
    function create_window(x, y: Integer; window: Widget;
                           const anchor: AnsiString = ''): Integer; overload;
    { font is a Variant: apps pass either a name or the (family, size, style)
      tuple _map_font-style helpers build. An AnsiString parameter took the
      tuple's object word as a string pointer and SEGFAULTED. }
    function create_text(x, y: Double; const text: AnsiString;
                         const anchor: AnsiString = ''; const fill: AnsiString = '';
                         const font: Variant = 0): Integer;
    function create_line(x1, y1, x2, y2: Double;
                         const fill: AnsiString = '';
                         width: Double = -1): Integer;
    function create_rectangle(x1, y1, x2, y2: Double;
                              const outline: AnsiString = '';
                              const fill: AnsiString = '';
                              width: Double = -1): Integer;
    function create_oval(x1, y1, x2, y2: Double;
                         const outline: AnsiString = '';
                         const fill: AnsiString = '';
                         width: Double = -1): Integer;
    function create_image(x, y: Double; image: PhotoImage;
                          const anchor: AnsiString = ''): Integer;
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
    { tkinter's own spelling: `canvas.delete("all")` / `canvas.delete(item_id)`.
      Only delete_all existed, so the standard call fell through to a dynamic
      attribute that was None and jumped to address 0 — songformatter's preview
      redraw starts with exactly this line. Variant so an item ID works too
      (same reason as bbox below). }
    procedure delete(const item: Variant);
    { An item is named by its ID or by a TAG — `canvas.bbox("all")` is the
      commonest call in the whole widget, so an Integer parameter refused the
      normal spelling. Variant takes both (see TkiItemSpec). }
    { Python gets a 4-TUPLE of integers (x0, y0, x1, y1), or None when the tag
      matches nothing — `bbox[1]` is a coordinate, and applications index it.
      Returned as the raw Tcl string, indexing gave a CHARACTER and comparing it
      to a number raised "comparison of a string with a number" (songformatter's
      scrollregion fit). `bbox_str` keeps the raw form for a caller that wants
      it. }
    function bbox(const item: Variant): Variant;
    function bbox_str(const item: Variant): AnsiString;
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
    { the orientation it was built with, so a LATER `sb.config(command=...)`
      still knows whether the scrolled widget's yview or xview is meant —
      the callable itself carries only {code, receiver}, not the method name }
    fOrient: AnsiString;
    constructor Create(master: Widget; const orient: AnsiString = '';
                       const command: Variant = 0);
    procedure set(const first, last: AnsiString);
    { `yscroll.config(command=cv.yview)` — the other half of the scrollbar
      wiring, written after both widgets exist. }
    procedure config(const command: Variant); overload;
    procedure configure(const command: Variant); overload;
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
                       const anchor: AnsiString = ''; const font: Variant = 0;
                       { `textvariable=` follows a StringVar — a caption that
                         updates when the variable does, which is how a status
                         line is written. }
                       const textvariable: Variant = 0;
                       const foreground: AnsiString = '';
                       const background: AnsiString = '';
                       const padding: Variant = 0);
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

  { A push button — `ttk.Button(panel, text="New", command=fn)`. Every toolbar
    in songformatter is these. `textvariable=` follows a StringVar, which is
    how a caption that changes (a BPM readout) is written. }
  Button = class(Widget)
  public
    constructor Create(master: Widget; const text: AnsiString = '';
                       const command: Variant = 0;
                       const textvariable: Variant = 0;
                       const state: AnsiString = '';
                       width: Integer = -1);
    procedure invoke;
  end;

  { `ttk.Separator(panel, orient="vertical")` — a divider line. }
  Separator = class(Widget)
  public
    constructor Create(master: Widget; const orient: AnsiString = '');
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
    procedure set(const value: AnsiString);
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
    procedure set(value: Boolean);
    { the Python spelling of a variable trace: `var.trace_add("write", cb)` }
    procedure trace_add(const mode: AnsiString; const callback: Variant);
  end;

  { `tk.Toplevel(root)` — a second window: a help viewer, a dialog, an analysis
    panel. Tcl's `toplevel`, so it takes the same window operations as the root
    (title, geometry) and the same widget operations as any other container. }
  Toplevel = class(Widget)
  public
    constructor Create(master: Widget = nil; const background: AnsiString = '');
    procedure geometry(const spec: AnsiString);
    { `transient(parent)` / `grab_set()` are what a modal dialog writes. }
    procedure transient(parent: Widget);
    procedure grab_set;
    procedure grab_release;
  end;

  { The root window as Python spells it: `root = tk.Tk()`. Tcl's root is a
    process-wide singleton, so every construction hands back the same '.' path;
    the class exists so the application's own spelling compiles. }
  Tk = class(Widget)
  public
    constructor Create;
  end;

{ The Text class under a name that does NOT collide with the RTL's `Text`
  record, so another unit can declare a field of this type at all. }
type
  TkTextWidget = Text;

{ A Text widget built from ANOTHER unit. `Text` is also the RTL's file record,
  and an unqualified lookup outside this unit finds that one — so a sibling unit
  (lib/pcl/tkhtmlview) cannot write `Text.Create(...)` at all. Inside this unit
  the name resolves to the class, so the construction lives here.
  See [[decide-class-namespace-scoping]] / [[bug-pascal-uses-is-transitive]]:
  this is a workaround for the flat namespace, and it goes away when that does. }
function NewText(master: Widget; const wrap: AnsiString = '';
                 width: Integer = -1; height: Integer = -1;
                 const background: AnsiString = ''): Text;

{ The older function spelling, kept for the example and any caller that used it. }
function Tk_: Widget;
procedure mainloop;

{ ---- tkinter.messagebox / tkinter.filedialog / tkinter.simpledialog ----

  Python writes `from tkinter import messagebox` and then
  `messagebox.showwarning(title, text)`. NilPy resolves the qualified member in
  the unit the `from` named, so these live in `tkinter` itself under their
  Python names rather than in submodule units of their own.

  All of them are the real Tcl dialogs (`tk_messageBox`, `tk_getOpenFile`,
  `tk_getSaveFile`), not stubs — the same commands CPython's tkinter sends. }
procedure showinfo(const title, message: AnsiString);
procedure showwarning(const title, message: AnsiString);
procedure showerror(const title, message: AnsiString);
function askyesno(const title, message: AnsiString): Boolean;
function askokcancel(const title, message: AnsiString): Boolean;
{ `askyesnocancel` answers three ways, so it returns a VARIANT: True, False or
  None — exactly what CPython returns, and what a caller testing `is None`
  needs. }
function askyesnocancel(const title, message: AnsiString): Variant;

{ filedialog. `filetypes` is a Python list of (label, pattern) pairs; the
  Variant form takes that list as written. An empty result means the user
  cancelled, which is CPython's '' too. }
function askopenfilename(const title: AnsiString = '';
                         const filetypes: Variant = 0;
                         const initialdir: AnsiString = '';
                         const initialfile: AnsiString = '';
                         const defaultextension: AnsiString = ''): AnsiString;
function asksaveasfilename(const title: AnsiString = '';
                           const filetypes: Variant = 0;
                           const initialdir: AnsiString = '';
                           const initialfile: AnsiString = '';
                           const defaultextension: AnsiString = ''): AnsiString;
function askdirectory(const title: AnsiString = '';
                      const initialdir: AnsiString = ''): AnsiString;

implementation

var
  gTkWidgetSeq: Integer;
  gTkVarSeq: Integer;
  gTkStarted: Boolean;

function TkiIntStr(n: Integer): AnsiString; forward;
function TkiNumStr(d: Double): AnsiString; forward;
function TkiOptNum(const name: AnsiString; d: Double): AnsiString; forward;
function TkiStrInt(const s: AnsiString): Integer; forward;
function TkiOptFont(const f: Variant): AnsiString; forward;

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

{ Canvas coordinates and line widths are REAL in Python — reportlab points
  scaled by a zoom factor land on x.5 constantly, and rounding them to whole
  pixels made the on-screen preview drift from the PDF. Tcl takes a decimal
  string happily, so two decimals are printed by hand rather than pulling
  sysutils into this unit. }
function TkiNumStr(d: Double): AnsiString;
var whole: Integer; frac: Integer; neg: Boolean; v: Double;
begin
  neg := d < 0;
  if neg then v := -d else v := d;
  whole := Trunc(v);
  frac := Trunc((v - whole) * 100 + 0.5);
  if frac >= 100 then
  begin
    Inc(whole);
    frac := frac - 100;
  end;
  TkiNumStr := TkiIntStr(whole);
  if frac > 0 then
  begin
    if frac < 10 then TkiNumStr := TkiNumStr + '.0' + TkiIntStr(frac)
    else
    begin
      while (frac mod 10) = 0 do frac := frac div 10;
      TkiNumStr := TkiNumStr + '.' + TkiIntStr(frac);
    end;
  end;
  if neg then TkiNumStr := '-' + TkiNumStr;
end;

{ Sentinel for an omitted numeric option is a NEGATIVE value: Tk's -width is
  never negative, and 0 is meaningful (a hairline / hidden outline). }
function TkiOptNum(const name: AnsiString; d: Double): AnsiString;
begin
  if d < 0 then TkiOptNum := ''
  else TkiOptNum := ' -' + name + ' ' + TkiNumStr(d);
end;

procedure TkiEnsureCbCommand; forward;

procedure TkiEnsureStarted;
begin
  if not gTkStarted then
  begin
    TkInit;
    gTkStarted := True;
    { the callback command must exist from the moment the interpreter does: a
      binding created later names `pxxcb`, and any event that reaches Tcl before
      the command is defined raises "invalid command name" in the background }
    TkiEnsureCbCommand;
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
function TkiRegisterRawCallback(const cb: Variant): Integer; forward;

function TkiIsCallable(const v: Variant): Boolean;
{ The same four-way test pycall_value makes, as a QUESTION rather than a call:
  a bound method and a plain def both arrive as a {code, receiver} pair (the def
  with a nil receiver), and a lambda's closure and a lifted bound-fn are pyeval
  objects. Asked here so an option can tell "callable" from "a number someone
  passed by mistake" before wiring it to Tk. }
var p: Pointer;
begin
  TkiIsCallable := False;
  if pycallback_is(v) then begin TkiIsCallable := True; Exit; end;
  p := Pointer(NativeInt(PPyVarRec(@v)^.Payload));
  if p = nil then Exit;
  case pyvartag(v) of
    8: TkiIsCallable := True;               { {code, receiver} pair }
    7: TkiIsCallable := pyclosure_is(p) or pyboundfn_is(p);
    { A plain compiled def arrives as tag 2 — its code ADDRESS boxed as an
      integer, which is exactly what pycall_value falls through to ("the value
      IS its code address"). MEASURED, not assumed: pylib's comment says a def
      reaches pycallback_is as a pair with a nil receiver, and in this position
      it does not — tag 2, pycallback_is False.

      Which means a def and a plain integer are the SAME representation here, so
      `yscrollcommand=5` cannot be told apart from a callable and would jump to
      address 5. The façade cannot diagnose that; only the representation can
      fix it, and CPython raises TypeError precisely because it keeps the two
      distinct. Left as-is rather than papered over with a range check, which
      would reject valid low code addresses and still accept high integers.

      RESOLVED since VT_CALLABLE (12) landed: a callable in a variant slot is
      now stamped off its SOURCE IR NODE rather than its type kind, so a code
      address and an integer no longer wear one tag and `yscrollcommand=5` IS
      refused. Tag 2 stays accepted only because a callable BOXED IN A POSITION
      the stamping does not reach can still arrive as one; it is the residue,
      not the representation. }
    2: TkiIsCallable := True;
    { VT_CALLABLE — a plain compiled code address with a tag of its own. The
      façade never saw it before the tag existed, so a bound method of a NILPY
      class in a scroll option (`self.scrolled.configure(
      yscrollcommand=self.on_scroll)`) stopped being recognised the moment the
      pin carried the new tag in: it fell past every arm of TkiOptScrollCmd's
      case, TkiIsCallable answered False for a value that is a callable by
      construction, and configure() Halt(1)'d with "takes a callable or a Tcl
      script" on a program that worked one pin earlier.

      Kept as its own arm rather than folded into 2: they mean different things
      (12 is "the compiler proved this is code", 2 is "we could not tell"), and
      the day the residue closes, 2 goes and this stays. }
    12: TkiIsCallable := True;
  end;
end;

function TkiOptRawCallback(const name: AnsiString; const v: Variant): AnsiString;
{ Wire an option to a RAW slot: Tk appends its own arguments to the command
  prefix, so the script is just `pxxcb <idx>` with no % substitutions. }
var idx: Integer;
begin
  idx := TkiRegisterRawCallback(v);
  if idx < 0 then
  begin
    WriteLn('tkinter: -', name, ': the callback registry is full');
    Halt(1);
  end;
  TkiOptRawCallback := ' -' + name + ' {pxxcb ' + TkiIntStr(idx) + '}';
end;

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
         { A WIDGET method stays wired Tcl-to-Tcl. That is not an optimisation,
           it is what CPython's tkinter does: `yscrollcommand=sb.set` never
           calls back into Python, it hands Tk the other widget's subcommand.
           Keeping that path means the common case has no Python in the loop. }
         if (o <> nil) and (o is Widget) then
           Result := ' -' + name + ' {' + Widget(o).path + ' ' + subcmd + '}'
         else
           Result := TkiOptRawCallback(name, v);
       end;
  else
    { Any other callable — a plain def, a lambda, a closure, a bound method of a
      non-widget object — now goes through the raw dispatcher and receives Tk's
      own arguments. This used to Halt(1). }
    if TkiIsCallable(v) then
      Result := TkiOptRawCallback(name, v)
    else
    begin
      WriteLn('tkinter: -', name, ' takes a callable or a Tcl script');
      Halt(1);
    end;
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

procedure Widget.config(const state: AnsiString; const scrollregion: Variant;
                        const yscrollcommand, xscrollcommand: Variant;
                        const text, background: AnsiString;
                        width, height: Integer; menu: Widget;
                        const postcommand: Variant);
begin
  configure(state, scrollregion, yscrollcommand, xscrollcommand,
            text, background, width, height, postcommand);
  { the menu bar is `wm`-level on the root and an ordinary option elsewhere;
    Tcl takes the same spelling for both }
  if menu <> nil then TkEval(path + ' configure -menu ' + menu.path);
end;

procedure Widget.protocol(const name: AnsiString; const callback: Variant);
var idx: Integer;
begin
  idx := TkiRegisterCallback(callback);
  if idx >= 0 then
    TkEval('wm protocol ' + path + ' ' + name + ' {' + TkiCbScript(idx) + '}');
end;

procedure Widget.configure_raw(const opts: AnsiString);
begin
  TkEval(path + ' configure ' + opts);
end;

procedure Widget.configure(const state: AnsiString; const scrollregion: Variant;
                           const yscrollcommand, xscrollcommand: Variant;
                           const text, background: AnsiString;
                           width, height: Integer;
                           const postcommand: Variant);
var o: AnsiString; cbIdx: Integer;
begin
  { only when the caller actually passed one: registering the DEFAULT (0) burnt
    a registry slot on every plain `configure(state=...)` and put a
    `-postcommand` naming an uncallable value on the widget }
  cbIdx := -1;
  if pyvartag(postcommand) <> 0 then cbIdx := TkiRegisterCallback(postcommand);
  if cbIdx >= 0 then
    TkEval(path + ' configure -postcommand {' + TkiCbScript(cbIdx) + '}');
  o := TkiOptStr('state', state) + TkiOptRegion('scrollregion', scrollregion)
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
  TKI_MAX_CALLBACKS = 4096;

type
  TTkiFn0 = function: Int64;
  TTkiFn1 = function(const a0: Variant): Int64;

var
  gTkCb: array[0..TKI_MAX_CALLBACKS - 1] of Variant;
  { A ONE-SHOT slot (an `after` timer) is handed back when it fires or is
    cancelled. Without that a 300ms re-arming timer walked the registry to its
    end in minutes and every later binding silently failed to register. }
  gTkCbOnce: array[0..TKI_MAX_CALLBACKS - 1] of Boolean;
  { the Tcl `after` id a one-shot slot is armed under, so after_cancel can find
    the slot again; '' when the slot is not a timer }
  gTkCbAfterId: array[0..TKI_MAX_CALLBACKS - 1] of AnsiString;
  { RAW slot: Tk calls this option with arguments of its OWN, and the handler
    wants them as they came rather than as an Event. `-yscrollcommand` is called
    with `first last`, a scrollbar's `-command` with `moveto <frac>` or
    `scroll <n> units|pages`, `-validatecommand` and a variable trace with their
    own sets. They arrive as strings, which is what Tcl has — a handler wanting
    numbers converts, exactly as under CPython's tkinter. }
  gTkCbRaw: array[0..TKI_MAX_CALLBACKS - 1] of Boolean;
  gTkCbFree: array[0..TKI_MAX_CALLBACKS - 1] of Integer;
  gTkCbFreeCount: Integer;
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

procedure TkiReleaseCb(idx: Integer); forward;

procedure TkiCallRaw(const cb: Variant; argc: Integer; argv: PPAnsiChar);
{ Call a RAW slot with the arguments Tk appended, as strings.

  pyvar_callv0..3 (pyeval) are the bridges, and they cover all four callable
  shapes — bound method, closure, lifted bound-fn, plain compiled def — which is
  why the façade does not have to know which one it holds. Arity 0..3 is what
  they cover, and it is also what NilPy's own dynamic call sites are lowered to.

  Above three arguments we say so and DO NOT call. `-validatecommand` is the
  real case: Tk offers eight substitutions (%d %i %P %s %S %v %V %W), so a
  handler wanting all of them is beyond the bridges. Calling with the first
  three instead would be a silent truncation, which is worse than a refusal —
  the handler would run and quietly see the wrong arguments. }
var a0, a1, a2, r: Variant; n: Integer;
begin
  n := argc - 2;
  if n < 0 then n := 0;
  if n > 0 then a0 := TkCmdArg(argc, argv, 2);
  if n > 1 then a1 := TkCmdArg(argc, argv, 3);
  if n > 2 then a2 := TkCmdArg(argc, argv, 4);
  case n of
    0: r := pyvar_callv0(cb);
    1: r := pyvar_callv1(cb, a0);
    2: r := pyvar_callv2(cb, a0, a1);
    3: r := pyvar_callv3(cb, a0, a1, a2);
  else
    WriteLn('tkinter: this callback option passes ', n,
            ' arguments; at most 3 are supported, so the handler was NOT run ',
            '(feature-lib-tkinter-callable-options-with-args)');
    r := pynone;
  end;
end;

function TkiCbDispatch(clientData: Pointer; interp: Pointer;
                       argc: Integer; argv: PPAnsiChar): Integer; cdecl;
var idx: Integer; ev: Event; evv: Variant;
begin
  TkiCbDispatch := 0;                       { TCL_OK }
  idx := TkiStrInt(TkCmdArg(argc, argv, 1));
  if (idx < 0) or (idx >= gTkCbCount) then Exit;
  if gTkCbRaw[idx] then
  begin
    { Tk appended its own arguments to the registered command prefix. Hand them
      over as they came instead of forcing them through Event, whose fields are
      the % substitutions of a BINDING and mean nothing here. }
    TkiCallRaw(gTkCb[idx], argc, argv);
    TkiReleaseCb(idx);
    Exit;
  end;
  if argc <= 2 then
  begin
    { a `-command` callback (or a fired `after` timer): no event argument.
      The slot is released AFTER the call — clearing it first drops the last
      reference to the callable that is about to run. }
    TkiCallValue(gTkCb[idx], pynone, False);
    TkiReleaseCb(idx);
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
  TkiReleaseCb(idx);
end;

procedure TkiEnsureCbCommand;
begin
  if gTkCbReady then Exit;
  TkRegisterCommand('pxxcb', @TkiCbDispatch);
  gTkCbReady := True;
  { CPython's tkinter reports a callback error by printing the traceback to
    stderr; Tk's default handler pops a modal dialog instead, which in a
    compiled app is both wrong and unreadable. Match CPython. }
  TkEval('proc bgerror {m} { puts stderr "Exception in Tk callback: $m"; ' +
         'puts stderr $::errorInfo }');
end;

function TkiRegisterCallbackEx(const cb: Variant; once: Boolean): Integer;
{ Store the callable and return its index. A PERMANENT slot holds the value for
  the process's lifetime — a widget's binding outlives every local that built
  it. A ONE-SHOT slot (an `after` timer) returns to the free list once it has
  fired or been cancelled.
  TkiEnsureStarted first: registering `pxxcb` needs a live interpreter, and
  TkRegisterCommand is a silent no-op without one — which would leave every
  binding pointing at a command Tcl does not have. }
begin
  TkiEnsureStarted;
  if gTkCbFreeCount > 0 then
  begin
    gTkCbFreeCount := gTkCbFreeCount - 1;
    TkiRegisterCallbackEx := gTkCbFree[gTkCbFreeCount];
  end
  else
  begin
    if gTkCbCount >= TKI_MAX_CALLBACKS then
    begin
      TkiRegisterCallbackEx := -1;
      Exit;
    end;
    TkiRegisterCallbackEx := gTkCbCount;
    gTkCbCount := gTkCbCount + 1;
  end;
  gTkCb[TkiRegisterCallbackEx] := cb;
  gTkCbOnce[TkiRegisterCallbackEx] := once;
  gTkCbAfterId[TkiRegisterCallbackEx] := '';
  gTkCbRaw[TkiRegisterCallbackEx] := False;
end;

function TkiRegisterCallback(const cb: Variant): Integer;
begin
  TkiRegisterCallback := TkiRegisterCallbackEx(cb, False);
end;

function TkiRegisterRawCallback(const cb: Variant): Integer;
{ A permanent slot whose handler receives Tcl's own arguments. Separate from
  TkiRegisterCallback because the difference is in how the slot is DISPATCHED,
  not in how it is stored — see gTkCbRaw. }
begin
  TkiRegisterRawCallback := TkiRegisterCallbackEx(cb, False);
  if TkiRegisterRawCallback >= 0 then
    gTkCbRaw[TkiRegisterRawCallback] := True;
end;

procedure TkiReleaseCb(idx: Integer);
{ Hand a one-shot slot back. Permanent slots are left alone. }
begin
  if (idx < 0) or (idx >= gTkCbCount) then Exit;
  if not gTkCbOnce[idx] then Exit;
  gTkCbOnce[idx] := False;
  gTkCbAfterId[idx] := '';
  gTkCb[idx] := pynone;
  if gTkCbFreeCount < TKI_MAX_CALLBACKS then
  begin
    gTkCbFree[gTkCbFreeCount] := idx;
    gTkCbFreeCount := gTkCbFreeCount + 1;
  end;
end;

{ The script Tk runs for a BOUND event: index plus the substitutions the event
  object exposes. }
function TkiCbScript(idx: Integer): AnsiString;
begin
  TkiCbScript := 'pxxcb ' + TkiIntStr(idx) +
                 ' %x %y %D %b %w %h %K %W';
end;

procedure Widget.mainloop;
begin
  TkiEnsureStarted;
  TkMainLoop;
end;

procedure Widget.quit;
{ Tcl's `destroy .` ends Tk_MainLoop — there is no separate quit primitive
  bound here, and tkinter's quit also just leaves the loop. }
begin
  TkEval('destroy .');
end;

{ ---- timers -------------------------------------------------------------

  Tk's `after` queue. The slot is one-shot, and the Tcl id it was armed under is
  recorded so after_cancel can hand the slot back — an editor debounces its
  redraw by cancelling and re-arming on every keystroke. }

function Widget.after(ms: Integer; const callback: Variant): AnsiString;
var idx: Integer;
begin
  after := '';
  if pyvartag(callback) = 0 then Exit;
  idx := TkiRegisterCallbackEx(callback, True);
  if idx < 0 then Exit;
  after := TkEval('after ' + TkiIntStr(ms) + ' {pxxcb ' + TkiIntStr(idx) + '}');
  gTkCbAfterId[idx] := after;
end;

function Widget.after_idle(const callback: Variant): AnsiString;
var idx: Integer;
begin
  after_idle := '';
  if pyvartag(callback) = 0 then Exit;
  idx := TkiRegisterCallbackEx(callback, True);
  if idx < 0 then Exit;
  after_idle := TkEval('after idle {pxxcb ' + TkiIntStr(idx) + '}');
  gTkCbAfterId[idx] := after_idle;
end;

procedure Widget.after_cancel(const id: Variant);
var s: AnsiString; i: Integer;
begin
  if pyvartag(id) = 0 then Exit;
  s := pystr_of(id);
  if s = '' then Exit;
  TkEval('after cancel ' + s);
  for i := 0 to gTkCbCount - 1 do
    if gTkCbAfterId[i] = s then
    begin
      TkiReleaseCb(i);
      Exit;
    end;
end;

{ ---- stacking, icon state, selection ------------------------------------- }

procedure Widget.lift;
begin
  TkEval('raise ' + path);
end;

procedure Widget.lower;
begin
  TkEval('lower ' + path);
end;

procedure Widget.deiconify;
begin
  TkEval('wm deiconify ' + path);
end;

procedure Widget.iconify;
begin
  TkEval('wm iconify ' + path);
end;

function Widget.clipboard_get: AnsiString;
{ Tk raises when the selection is empty or holds a type we did not ask for;
  Python's clipboard_get raises TclError there and callers guard it. We have no
  Tcl error channel here, so an empty answer stands in for both. }
begin
  clipboard_get := TkEval('clipboard get');
end;

procedure Widget.clipboard_clear;
begin
  TkEval('clipboard clear -displayof ' + path);
end;

procedure Widget.clipboard_append(const text: AnsiString);
begin
  TkEval('clipboard append -displayof ' + path + ' -- {' + text + '}');
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

procedure Widget.focus_set;
begin
  TkEval('focus ' + path);
end;

procedure Widget.focus_force;
begin
  TkEval('focus -force ' + path);
end;

procedure Widget.focus;
begin
  focus_set;
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

function Widget.GetChildren: TPyDict;
var kids: TPyList; i: Integer; d: TPyDict; k: AnsiString; v: Variant;
begin
  d := TPyDict.Create;
  kids := winfo_children;
  for i := 0 to kids.count - 1 do
  begin
    v := kids.at(i);
    k := pystr_of(v);
    d.store(k, v);
  end;
  GetChildren := d;
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
                        height: Integer; const padding: Variant);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'frame';
  { `padding` is a ttk option and the classic `frame` rejects it, so a frame
    that asks for one IS a ttk::frame — which is what the application wrote
    (`ttk.Frame(root, padding=(8, 6))`). Without padding the classic widget is
    kept, so every frame that already worked is byte-identical. }
  if pyvartag(padding) <> 0 then
    TkEval('ttk::frame ' + path + TkiOptPadding(padding) +
           TkiOptInt('width', width) + TkiOptInt('height', height))
  else
    TkEval('frame ' + path + TkiOptInt('highlightthickness', highlightthickness) +
           TkiOptStr('background', background) + TkiOptInt('width', width) +
           TkiOptInt('height', height));
end;

{ ---- PhotoImage ---------------------------------------------------------- }

constructor PhotoImage.Create(const data: Variant; const file: AnsiString);
var payload: AnsiString;
begin
  TkiEnsureStarted;
  Inc(gTkWidgetSeq);
  name := 'pxximg' + TkiIntStr(gTkWidgetSeq);
  if file <> '' then
    TkEval('image create photo ' + name + ' -file {' + file + '}')
  else
  begin
    payload := pystr_of(data);
    if payload = '' then
      TkEval('image create photo ' + name)
    else
      TkEval('image create photo ' + name + ' -data {' + payload + '}');
  end;
end;

function PhotoImage.width: Integer;
begin
  width := TkiStrInt(TkEval('image width ' + name));
end;

function PhotoImage.height: Integer;
begin
  height := TkiStrInt(TkEval('image height ' + name));
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

function PanedWindow.sashpos(index: Integer): Integer;
begin
  sashpos := TkiStrInt(TkEval(path + ' sashpos ' + TkiIntStr(index)));
end;

procedure PanedWindow.sashpos(index, newpos: Integer);
begin
  TkEval(path + ' sashpos ' + TkiIntStr(index) + ' ' + TkiIntStr(newpos));
end;

constructor Menu.Create(master: Widget; tearoff: Integer);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'menu';
  TkEval('menu ' + path + TkiOptInt('tearoff', tearoff));
end;

procedure Menu.add_command(const label: AnsiString; const command: Variant;
                           const accelerator, state: AnsiString);
var cbIdx: Integer;
begin
  { `command=` is a CALLABLE in Python — routed through the same callback
    registry every other command option uses. }
  cbIdx := TkiRegisterCallback(command);
  if cbIdx < 0 then
    TkEval(path + ' add command' + TkiOptStr('label', label) +
           TkiOptStr('accelerator', accelerator) + TkiOptStr('state', state))
  else
    TkEval(path + ' add command' + TkiOptStr('label', label) +
           TkiOptStr('accelerator', accelerator) + TkiOptStr('state', state) +
           ' -command {' + TkiCbScript(cbIdx) + '}');
end;

procedure Menu.add_cascade(const label: AnsiString; menu: Widget);
var o: AnsiString;
begin
  o := '';
  if menu <> nil then o := ' -menu ' + menu.path;
  TkEval(path + ' add cascade -label {' + label + '}' + o);
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

procedure Text.insert(const index: AnsiString; const chars: AnsiString);
begin
  TkEval(path + ' insert ' + index + ' {' + chars + '}');
end;

procedure Text.delete(const first: AnsiString; const last: AnsiString);
begin
  if last = '' then TkEval(path + ' delete ' + first)
  else TkEval(path + ' delete ' + first + ' ' + last);
end;

function Text.get(const first: AnsiString; const last: AnsiString): AnsiString;
begin
  if last = '' then get := TkEval(path + ' get ' + first)
  else get := TkEval(path + ' get ' + first + ' ' + last);
end;

procedure Text.tag_add(const tagName, first, last: AnsiString);
begin
  TkEval(path + ' tag add ' + tagName + ' ' + first + ' ' + last);
end;

procedure Text.tag_configure(const tagName: AnsiString;
                             const font, foreground, background,
                             justify: AnsiString;
                             const underline: Variant;
                             spacing1, spacing3, lmargin1, lmargin2: Integer);
var o: AnsiString;
begin
  o := TkiOptStr('font', font) + TkiOptStr('foreground', foreground)
     + TkiOptStr('background', background) + TkiOptStr('justify', justify)
     + TkiOptInt('spacing1', spacing1) + TkiOptInt('spacing3', spacing3)
     + TkiOptInt('lmargin1', lmargin1) + TkiOptInt('lmargin2', lmargin2);
  if pyvartag(underline) <> 0 then
  begin
    if pyvar_to_bool(underline) then o := o + ' -underline 1'
    else o := o + ' -underline 0';
  end;
  TkEval(path + ' tag configure ' + tagName + o);
end;

function Text.index(const idx: AnsiString): AnsiString;
begin
  index := TkEval(path + ' index ' + idx);
end;

procedure Text.see(const idx: AnsiString);
begin
  TkEval(path + ' see ' + idx);
end;

procedure Text.mark_set(const markName, idx: AnsiString);
begin
  TkEval(path + ' mark set ' + markName + ' ' + idx);
end;

procedure Text.event_generate(const sequence: AnsiString);
begin
  TkEval('event generate ' + path + ' ' + sequence);
end;

procedure Text.yview(const args: AnsiString);
begin
  TkEval(path + ' yview ' + args);
end;

procedure Text.yview_scroll(n: Integer; const what: AnsiString);
begin
  TkEval(path + ' yview scroll ' + TkiIntStr(n) + ' ' + what);
end;

procedure Text.xview(const args: AnsiString);
begin
  TkEval(path + ' xview ' + args);
end;

{ ---- Canvas -------------------------------------------------------------- }

constructor Canvas.Create(master: Widget; highlightthickness: Integer;
                         const background: AnsiString; width: Integer;
                         height: Integer;
                         const yscrollcommand, xscrollcommand: Variant;
                         const scrollregion, cursor: AnsiString;
                         borderwidth: Integer);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'canvas';
  TkEval('canvas ' + path + TkiOptInt('highlightthickness', highlightthickness) +
         TkiOptStr('background', background) + TkiOptInt('width', width) +
         TkiOptInt('height', height) +
         TkiOptScrollCmd('yscrollcommand', yscrollcommand, 'set') +
         TkiOptScrollCmd('xscrollcommand', xscrollcommand, 'set') +
         TkiOptStr('scrollregion', scrollregion) +
         TkiOptStr('cursor', cursor) +
         TkiOptInt('borderwidth', borderwidth));
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

function Canvas.create_text(x, y: Double; const text, anchor, fill: AnsiString;
                            const font: Variant): Integer;
begin
  create_text := TkiStrInt(TkEval(path + ' create text ' + TkiNumStr(x) + ' ' +
                 TkiNumStr(y) + ' -text {' + text + '}' +
                 TkiOptStr('anchor', anchor) + TkiOptStr('fill', fill) +
                 TkiOptFont(font)));
end;

function Canvas.create_line(x1, y1, x2, y2: Double;
                            const fill: AnsiString; width: Double): Integer;
begin
  create_line := TkiStrInt(TkEval(path + ' create line ' + TkiNumStr(x1) + ' ' +
                 TkiNumStr(y1) + ' ' + TkiNumStr(x2) + ' ' + TkiNumStr(y2) +
                 TkiOptStr('fill', fill) + TkiOptNum('width', width)));
end;

function Canvas.create_rectangle(x1, y1, x2, y2: Double;
                                 const outline, fill: AnsiString;
                                 width: Double): Integer;
begin
  create_rectangle := TkiStrInt(TkEval(path + ' create rectangle ' +
                      TkiNumStr(x1) + ' ' + TkiNumStr(y1) + ' ' +
                      TkiNumStr(x2) + ' ' + TkiNumStr(y2) +
                      TkiOptStr('outline', outline) + TkiOptStr('fill', fill) +
                      TkiOptNum('width', width)));
end;

function Canvas.create_oval(x1, y1, x2, y2: Double;
                            const outline, fill: AnsiString;
                            width: Double): Integer;
begin
  create_oval := TkiStrInt(TkEval(path + ' create oval ' +
                 TkiNumStr(x1) + ' ' + TkiNumStr(y1) + ' ' +
                 TkiNumStr(x2) + ' ' + TkiNumStr(y2) +
                 TkiOptStr('outline', outline) + TkiOptStr('fill', fill) +
                 TkiOptNum('width', width)));
end;

{ An image item takes the PhotoImage's Tk NAME, not a path — the photo must
  outlive the item or Tk draws nothing (CPython has the same rule; the app
  keeps its own reference for exactly this reason). }
function Canvas.create_image(x, y: Double; image: PhotoImage;
                             const anchor: AnsiString): Integer;
var nm: AnsiString;
begin
  nm := '';
  if image <> nil then nm := image.name;
  create_image := TkiStrInt(TkEval(path + ' create image ' + TkiNumStr(x) +
                  ' ' + TkiNumStr(y) + TkiOptStr('image', nm) +
                  TkiOptStr('anchor', anchor)));
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

procedure Canvas.delete(const item: Variant);
{ a TAG (`"all"`, a 1-char tag) or a numeric item ID — never coerce a string
  through pyvar_to_int, which raises "expected a number, got str" }
var t: Int64;
begin
  t := pyvartag(item);
  if (t = 5) or (t = 6) then TkEval(path + ' delete ' + pystr_of(item))
  else TkEval(path + ' delete ' + TkiIntStr(Integer(pyvar_to_int(item))));
end;

procedure Canvas.delete_all;
begin
  TkEval(path + ' delete all');
end;

function Canvas.bbox_str(const item: Variant): AnsiString;
begin
  bbox_str := TkEval(path + ' bbox ' + TkiItemSpec(item));
end;

function Canvas.bbox(const item: Variant): Variant;
var raw, one: AnsiString; i: Integer; l: TPyList;
begin
  raw := TkEval(path + ' bbox ' + TkiItemSpec(item));
  if raw = '' then
  begin
    bbox := pynone;          { Tk answers empty when nothing matches }
    exit;
  end;
  l := TPyList.Create;
  one := '';
  for i := 1 to Length(raw) + 1 do
  begin
    if (i > Length(raw)) or (raw[i] = ' ') then
    begin
      if one <> '' then l.append(TkiStrInt(one));
      one := '';
    end
    else one := one + raw[i];
  end;
  bbox := l;
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
  fOrient := orient;
  TkEval('scrollbar ' + path + TkiOptStr('orient', orient) +
         TkiOptScrollCmd('command', command, sub));
end;

procedure Scrollbar.config(const command: Variant);
var sub: AnsiString;
begin
  if fOrient = 'horizontal' then sub := 'xview' else sub := 'yview';
  TkEval(path + ' configure' + TkiOptScrollCmd('command', command, sub));
end;

procedure Scrollbar.configure(const command: Variant);
begin
  config(command);
end;

procedure Scrollbar.set(const first, last: AnsiString);
begin
  TkEval(path + ' set ' + first + ' ' + last);
end;

{ ---- Label / Entry / Checkbutton ---------------------------------------- }

{ ttk's `-padding`: one number, or the (left, top[, right, bottom]) tuple an
  application writes. Tcl takes both spellings as a list. }
{ `scrollregion=` takes the Tcl string "x0 y0 x1 y1" — and an application
  writes the 4-TUPLE tkinter accepts (`cv.configure(scrollregion=(0, 0, w,
  h))`). Declared AnsiString, the tuple arrived as a list handle reinterpreted
  as text and the widget command was built from garbage. }
function TkiOptRegion(const name: AnsiString; const v: Variant): AnsiString;
var i, n: Integer; r: AnsiString;
begin
  r := '';
  case pyvartag(v) of
    0: ;                                    { omitted }
    7:
      begin
        n := pylen_v(v);
        for i := 0 to n - 1 do
          r := r + ' ' + pystr_of(pyvar_getitem(v, i));
        if r <> '' then r := ' -' + name + ' {' + Copy(r, 2, Length(r) - 1) + '}';
      end;
  else
    begin
      r := pystr_of(v);
      if r <> '' then r := ' -' + name + ' {' + r + '}' else r := '';
    end;
  end;
  TkiOptRegion := r;
end;

function TkiOptPadding(const p: Variant): AnsiString;
var i, n: Integer; r: AnsiString;
begin
  r := '';
  case pyvartag(p) of
    0: ;                                   { omitted }
    7:
      begin
        n := pylen_v(p);
        for i := 0 to n - 1 do
          r := r + ' ' + pystr_of(pyvar_getitem(p, i));
        if r <> '' then r := ' -padding {' + Copy(r, 2, Length(r) - 1) + '}';
      end;
  else
    r := ' -padding ' + pystr_of(p);       { a bare number }
  end;
  TkiOptPadding := r;
end;

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
                        const font: Variant; const textvariable: Variant;
                        const foreground, background: AnsiString;
                        const padding: Variant);
var vn: AnsiString;
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'label';
  vn := TkiVarName(textvariable);
  { ttk options (padding) and a ttk look go with ttk::label; the classic label
    is kept otherwise so existing callers emit the same command as before }
  if pyvartag(padding) <> 0 then
    TkEval('ttk::label ' + path + ' -text {' + text + '}' +
           TkiOptStr('anchor', anchor) + TkiOptFont(font) +
           TkiOptStr('textvariable', vn) + TkiOptStr('foreground', foreground) +
           TkiOptStr('background', background) + TkiOptPadding(padding))
  else
    TkEval('label ' + path + ' -text {' + text + '}' + TkiOptStr('anchor', anchor) +
           TkiOptFont(font) + TkiOptStr('textvariable', vn) +
           TkiOptStr('foreground', foreground) +
           TkiOptStr('background', background));
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

constructor Button.Create(master: Widget; const text: AnsiString;
                         const command, textvariable: Variant;
                         const state: AnsiString; width: Integer);
var idx: Integer; vn: AnsiString;
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'button';
  vn := TkiVarName(textvariable);
  TkEval('ttk::button ' + path + TkiOptStr('text', text) +
         TkiOptStr('textvariable', vn) + TkiOptStr('state', state) +
         TkiOptInt('width', width));
  if pyvartag(command) <> 0 then
  begin
    idx := TkiRegisterCallback(command);
    if idx >= 0 then
      TkEval(path + ' configure -command {' + TkiCbScript(idx) + '}');
  end;
end;

procedure Button.invoke;
begin
  TkEval(path + ' invoke');
end;

constructor Separator.Create(master: Widget; const orient: AnsiString);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'separator';
  TkEval('ttk::separator ' + path + TkiOptStr('orient', orient));
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

procedure StringVar.set(const value: AnsiString);
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

procedure BooleanVar.set(value: Boolean);
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

constructor Toplevel.Create(master: Widget; const background: AnsiString);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'toplevel';
  TkEval('toplevel ' + path + TkiOptStr('background', background));
end;

procedure Toplevel.geometry(const spec: AnsiString);
begin
  TkEval(path + ' geometry ' + spec);
end;

procedure Toplevel.transient(parent: Widget);
begin
  if parent <> nil then TkEval('wm transient ' + path + ' ' + parent.path);
end;

procedure Toplevel.grab_set;
begin
  TkEval('grab set ' + path);
end;

procedure Toplevel.grab_release;
begin
  TkEval('grab release ' + path);
end;

{ ---- Notebook ----------------------------------------------------------- }

{ Every widget this unit builds, by Tcl path. Tk hands an application back a
  PATH (a notebook tab, a bind's %W) and the application expects the WIDGET, so
  the mapping has to live somewhere; Tcl's own widget commands cannot rebuild a
  Pascal object. }
const TKI_MAX_REG = 4096;
var
  gTkRegPath: array[0..TKI_MAX_REG - 1] of AnsiString;
  gTkRegW: array[0..TKI_MAX_REG - 1] of Widget;
  gTkRegCount: Integer;

procedure TkiRegisterWidget(w: Widget);
begin
  if (w = nil) or (gTkRegCount >= TKI_MAX_REG) then Exit;
  gTkRegPath[gTkRegCount] := w.path;
  gTkRegW[gTkRegCount] := w;
  Inc(gTkRegCount);
end;

function TkiWidgetByPath(const p: AnsiString): Widget;
var i: Integer;
begin
  TkiWidgetByPath := nil;
  for i := gTkRegCount - 1 downto 0 do
    if gTkRegPath[i] = p then
    begin
      TkiWidgetByPath := gTkRegW[i];
      Exit;
    end;
end;

constructor Notebook.Create(master: Widget; width, height: Integer);
begin
  TkiEnsureStarted;
  path := TkiNextPath(master);
  kind := 'notebook';
  TkEval('ttk::notebook ' + path + TkiOptInt('width', width) +
         TkiOptInt('height', height));
  TkiRegisterWidget(Self);
end;

procedure Notebook.add(child: Widget; const text: AnsiString);
begin
  if child = nil then exit;
  TkiRegisterWidget(child);
  TkEval(path + ' add ' + child.path + TkiOptStr('text', text));
end;

function Notebook.select: AnsiString;
begin
  select := TkEval(path + ' select');
end;

function Notebook.select(child: Widget): AnsiString;
begin
  select := '';
  if child <> nil then select := TkEval(path + ' select ' + child.path);
end;

function Notebook.select(index: Integer): AnsiString;
begin
  select := TkEval(path + ' select ' + TkiIntStr(index));
end;

procedure Notebook.tab(child: Widget; const text: AnsiString);
begin
  if child <> nil then
    TkEval(path + ' tab ' + child.path + TkiOptStr('text', text));
end;

function Notebook.tabs: TPyList;
var raw, one: AnsiString; i: Integer; l: TPyList;
begin
  { Tcl returns a space-separated list of paths; no path contains a space, so
    splitting on the space is exact here. }
  l := TPyList.Create;
  raw := TkEval(path + ' tabs');
  one := '';
  for i := 1 to Length(raw) do
  begin
    if raw[i] = ' ' then
    begin
      if one <> '' then l.append(one);
      one := '';
    end
    else one := one + raw[i];
  end;
  if one <> '' then l.append(one);
  tabs := l;
end;

function Notebook.index(const which: AnsiString): Integer;
begin
  index := TkiStrInt(TkEval(path + ' index ' + which));
end;

procedure Notebook.forget(child: Widget);
begin
  if child <> nil then TkEval(path + ' forget ' + child.path);
end;

function Notebook.nametowidget(const path: AnsiString): Variant;
var w: Widget;
begin
  w := TkiWidgetByPath(path);
  if w = nil then nametowidget := pynone
  else nametowidget := w;      { boxes as VT_OBJECT — its real class comes with it }
end;

procedure mainloop;
begin
  TkiEnsureStarted;
  TkMainLoop;
end;

function NewText(master: Widget; const wrap: AnsiString;
                 width, height: Integer;
                 const background: AnsiString): Text;
begin
  NewText := Text.Create(master, wrap, width, height, background);
end;

{ ---- dialogs ---- }

function TkiMsgBox(const title, message, icon, boxType: AnsiString): AnsiString;
begin
  TkiEnsureStarted;
  TkiMsgBox := TkEval('tk_messageBox -title {' + title + '} -message {' +
               message + '} -icon ' + icon + ' -type ' + boxType);
end;

procedure showinfo(const title, message: AnsiString);
begin
  TkiMsgBox(title, message, 'info', 'ok');
end;

procedure showwarning(const title, message: AnsiString);
begin
  TkiMsgBox(title, message, 'warning', 'ok');
end;

procedure showerror(const title, message: AnsiString);
begin
  TkiMsgBox(title, message, 'error', 'ok');
end;

function askyesno(const title, message: AnsiString): Boolean;
begin
  askyesno := TkiMsgBox(title, message, 'question', 'yesno') = 'yes';
end;

function askokcancel(const title, message: AnsiString): Boolean;
begin
  askokcancel := TkiMsgBox(title, message, 'question', 'okcancel') = 'ok';
end;

function askyesnocancel(const title, message: AnsiString): Variant;
var r: AnsiString;
begin
  r := TkiMsgBox(title, message, 'question', 'yesnocancel');
  if r = 'yes' then askyesnocancel := True
  else if r = 'no' then askyesnocancel := False
  else askyesnocancel := pynone;    { cancelled — CPython returns None }
end;

{ `[("PNG images", "*.png"), ("All files", "*.*")]` -> Tcl's
  `{{PNG images} {*.png}} {{All files} {*.*}}`. Anything that is not a
  two-element pair is skipped rather than mangled. }
function TkiFileTypes(const filetypes: Variant): AnsiString;
var n, i: Integer; pair: Variant; r: AnsiString;
begin
  r := '';
  if pyvartag(filetypes) <> 7 then
  begin
    TkiFileTypes := '';
    exit;
  end;
  n := pylen_v(filetypes);
  for i := 0 to n - 1 do
  begin
    pair := pyvar_getitem(filetypes, i);
    if pyvartag(pair) <> 7 then continue;
    if pylen_v(pair) < 2 then continue;
    r := r + ' {{' + pystr_of(pyvar_getitem(pair, 0)) + '} {' +
         pystr_of(pyvar_getitem(pair, 1)) + '}}';
  end;
  if r <> '' then r := ' -filetypes {' + r + ' }';
  TkiFileTypes := r;
end;

function TkiFileDialog(const cmd, title: AnsiString; const filetypes: Variant;
                       const initialdir, initialfile, defaultextension: AnsiString): AnsiString;
begin
  TkiEnsureStarted;
  TkiFileDialog := TkEval(cmd + TkiOptStr('title', title) +
                   TkiFileTypes(filetypes) +
                   TkiOptStr('initialdir', initialdir) +
                   TkiOptStr('initialfile', initialfile) +
                   TkiOptStr('defaultextension', defaultextension));
end;

function askopenfilename(const title: AnsiString; const filetypes: Variant;
                         const initialdir, initialfile,
                         defaultextension: AnsiString): AnsiString;
begin
  askopenfilename := TkiFileDialog('tk_getOpenFile', title, filetypes,
                                   initialdir, initialfile, defaultextension);
end;

function asksaveasfilename(const title: AnsiString; const filetypes: Variant;
                           const initialdir, initialfile,
                           defaultextension: AnsiString): AnsiString;
begin
  asksaveasfilename := TkiFileDialog('tk_getSaveFile', title, filetypes,
                                     initialdir, initialfile, defaultextension);
end;

function askdirectory(const title, initialdir: AnsiString): AnsiString;
begin
  TkiEnsureStarted;
  askdirectory := TkEval('tk_chooseDirectory' + TkiOptStr('title', title) +
                  TkiOptStr('initialdir', initialdir));
end;

begin
  gTkWidgetSeq := 0;
  gTkVarSeq := 0;
  gTkRegCount := 0;
  gTkStarted := False;
end.
