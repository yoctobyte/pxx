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

end.
