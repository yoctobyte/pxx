unit tk;
{ Thin Tcl/Tk embed — the whole GUI is command strings via TkEval, exactly the
  model CPython's tkinter uses (a shim over Tcl_Eval). Links the system Tcl/Tk
  8.6 shared libraries directly by soname; needs no -dev headers and no change
  to the compiler's C-import registry — the `external` clauses name the
  versioned soname, which becomes a DT_NEEDED.

  Minimal by construction: Tk does all widget/layout/event work; this unit is
  just the interpreter bootstrap plus a string in / string out `TkEval`. Build a
  tkinter-shaped surface on top of `TkEval` if you want familiar Python idioms —
  the wrapper stays thin because every "widget" is one Tcl command.

  Track B (library). Used by the NilPy IDE demo (Track E). }
interface

uses strings;   { StrPas: NUL-terminated PChar -> AnsiString (copies to the NUL) }

{ Create the Tcl interpreter and initialise Tcl + Tk. True on success. }
function TkInit: Boolean;

{ Run a Tcl/Tk command string; return the interpreter's result string. }
function TkEval(const cmd: AnsiString): AnsiString;

{ Enter the Tk event loop; returns when the last window is destroyed. }
procedure TkMainLoop;

{ --- tkinter-shaped convenience surface ---

  Each of these is ONE TkEval with the arguments interpolated. That is the whole
  design: it is a name -> command mapping so familiar Python snippets read
  naturally, NOT a widget layer. There is no widget object, no state, and nothing
  that can drift out of sync with Tk — if a helper is missing, TkEval does the
  same job with one more line, which is the escape hatch that keeps this thin.

  Widget paths are Tk's own ('.b', '.f.entry'); they are strings, not handles,
  because that is what Tk uses and hiding it would mean inventing a registry.

  Values are interpolated in {braces}, which is Tcl's literal-quoting form — a
  caption containing a space or a bracket therefore stays one argument instead of
  being re-parsed as Tcl. A caption containing an unbalanced brace still breaks,
  which is a genuine limit of this thin approach rather than something the
  wrapper should start escaping. }

{ Window title of the root window. }
procedure TkTitle(const title: AnsiString);

{ Widget constructors. `path` is a Tk widget path like '.name'; `opts` is passed
  through verbatim, so anything Tk accepts works ('-width 20 -fg red'). }
procedure TkLabel(const path, text: AnsiString);
procedure TkButton(const path, text, command: AnsiString);
procedure TkEntry(const path, opts: AnsiString);
procedure TkText(const path, opts: AnsiString);
procedure TkFrame(const path, opts: AnsiString);

{ Geometry. }
procedure TkPack(const path, opts: AnsiString);
procedure TkGrid(const path, opts: AnsiString);

{ Read/replace the text of an entry or text widget. TkGetText covers both
  (`entry get` vs `text get 1.0 end`) by looking at the widget class, so callers
  do not have to branch. }
function  TkGetText(const path: AnsiString): AnsiString;
procedure TkSetText(const path, value: AnsiString);

{ Bind an event sequence ('<Return>', '<Button-1>') to a Tcl script. }
procedure TkBind(const path, sequence, script: AnsiString);

{ Destroy a widget (or '.' for the whole application). }
procedure TkDestroy(const path: AnsiString);

{ Run `script` after `ms` milliseconds — the idiom a headless smoke uses to
  close itself, and the only timer Tk needs. }
procedure TkAfter(ms: Integer; const script: AnsiString);

{ --- ttk themed widgets ---

  Same shape, `ttk::` command prefix. Worth having for one reason: the default Tk
  widget set looks like 1994, and ttk closes most of that gap for the cost of a
  prefix. Mixing ttk and classic widgets in one window is allowed but looks
  inconsistent — pick one per window. }
procedure TkThemeUse(const themeName: AnsiString);
function  TkThemeNames: AnsiString;
procedure TtkLabel(const path, text: AnsiString);
procedure TtkButton(const path, text, command: AnsiString);
procedure TtkEntry(const path, opts: AnsiString);
procedure TtkFrame(const path, opts: AnsiString);

implementation

type
  PTclInterp = Pointer;

function Tcl_CreateInterp: PTclInterp; cdecl; external 'libtcl8.6.so.0';
function Tcl_Init(interp: PTclInterp): Integer; cdecl; external 'libtcl8.6.so.0';
function Tcl_Eval(interp: PTclInterp; script: PAnsiChar): Integer; cdecl; external 'libtcl8.6.so.0';
function Tcl_GetStringResult(interp: PTclInterp): PAnsiChar; cdecl; external 'libtcl8.6.so.0';
procedure Tcl_FindExecutable(argv0: PAnsiChar); cdecl; external 'libtcl8.6.so.0';
function Tk_Init(interp: PTclInterp): Integer; cdecl; external 'libtk8.6.so.0';
procedure Tk_MainLoop; cdecl; external 'libtk8.6.so.0';

const
  TCL_OK = 0;

var
  gInterp: PTclInterp = nil;

function TkInit: Boolean;
begin
  { Tk_Init needs the interpreter to know where the tk script library lives;
    Tcl_FindExecutable primes the internal path search. A non-nil dummy is fine. }
  Tcl_FindExecutable('pxx-tk');
  gInterp := Tcl_CreateInterp;
  Result := (gInterp <> nil)
        and (Tcl_Init(gInterp) = TCL_OK)
        and (Tk_Init(gInterp) = TCL_OK);
end;

function TkEval(const cmd: AnsiString): AnsiString;
begin
  if gInterp = nil then begin
    Result := '';
    Exit;
  end;
  Tcl_Eval(gInterp, PAnsiChar(cmd));
  { StrPas copies up to the NUL — a plain AnsiString(ptr) cast wraps the pointer
    with a garbage length and over-reads Tcl's internal heap. }
  Result := StrPas(PChar(Tcl_GetStringResult(gInterp)));
end;

procedure TkMainLoop;
begin
  Tk_MainLoop;
end;

{ ===== tkinter-shaped convenience surface ===== }

function IntStrTk(v: Integer): AnsiString;
var n: Integer; neg: Boolean; r: AnsiString;
begin
  if v = 0 then begin IntStrTk := '0'; Exit; end;
  neg := v < 0; n := v; if neg then n := -n;
  r := '';
  while n > 0 do begin r := Chr(Ord('0') + (n mod 10)) + r; n := n div 10; end;
  if neg then r := '-' + r;
  IntStrTk := r;
end;

procedure TkTitle(const title: AnsiString);
begin
  TkEval('wm title . {' + title + '}');
end;

procedure TkLabel(const path, text: AnsiString);
begin
  TkEval('label ' + path + ' -text {' + text + '}');
end;

procedure TkButton(const path, text, command: AnsiString);
begin
  TkEval('button ' + path + ' -text {' + text + '} -command {' + command + '}');
end;

procedure TkEntry(const path, opts: AnsiString);
begin
  TkEval('entry ' + path + ' ' + opts);
end;

procedure TkText(const path, opts: AnsiString);
begin
  TkEval('text ' + path + ' ' + opts);
end;

procedure TkFrame(const path, opts: AnsiString);
begin
  TkEval('frame ' + path + ' ' + opts);
end;

procedure TkPack(const path, opts: AnsiString);
begin
  TkEval('pack ' + path + ' ' + opts);
end;

procedure TkGrid(const path, opts: AnsiString);
begin
  TkEval('grid ' + path + ' ' + opts);
end;

{ `winfo class` tells us whether this is an Entry-like or Text-like widget, so
  one call covers both instead of making the caller remember which get form
  applies. Anything else falls back to `cget -text`, which covers labels and
  buttons. }
function TkGetText(const path: AnsiString): AnsiString;
var cls: AnsiString;
begin
  cls := TkEval('winfo class ' + path);
  if (cls = 'Entry') or (cls = 'TEntry') then
    TkGetText := TkEval(path + ' get')
  else if cls = 'Text' then
    TkGetText := TkEval(path + ' get 1.0 end-1c')
  else
    TkGetText := TkEval(path + ' cget -text');
end;

procedure TkSetText(const path, value: AnsiString);
var cls: AnsiString;
begin
  cls := TkEval('winfo class ' + path);
  if (cls = 'Entry') or (cls = 'TEntry') then
  begin
    TkEval(path + ' delete 0 end');
    TkEval(path + ' insert 0 {' + value + '}');
  end
  else if cls = 'Text' then
  begin
    TkEval(path + ' delete 1.0 end');
    TkEval(path + ' insert 1.0 {' + value + '}');
  end
  else
    TkEval(path + ' configure -text {' + value + '}');
end;

procedure TkBind(const path, sequence, script: AnsiString);
begin
  TkEval('bind ' + path + ' ' + sequence + ' {' + script + '}');
end;

procedure TkDestroy(const path: AnsiString);
begin
  TkEval('destroy ' + path);
end;

procedure TkAfter(ms: Integer; const script: AnsiString);
begin
  TkEval('after ' + IntStrTk(ms) + ' {' + script + '}');
end;

{ ===== ttk ===== }

procedure TkThemeUse(const themeName: AnsiString);
begin
  TkEval('ttk::style theme use ' + themeName);
end;

function TkThemeNames: AnsiString;
begin
  TkThemeNames := TkEval('ttk::style theme names');
end;

procedure TtkLabel(const path, text: AnsiString);
begin
  TkEval('ttk::label ' + path + ' -text {' + text + '}');
end;

procedure TtkButton(const path, text, command: AnsiString);
begin
  TkEval('ttk::button ' + path + ' -text {' + text + '} -command {' + command + '}');
end;

procedure TtkEntry(const path, opts: AnsiString);
begin
  TkEval('ttk::entry ' + path + ' ' + opts);
end;

procedure TtkFrame(const path, opts: AnsiString);
begin
  TkEval('ttk::frame ' + path + ' ' + opts);
end;

end.
