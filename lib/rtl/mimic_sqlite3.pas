{ SPDX-License-Identifier: Zlib }
unit mimic_sqlite3;
{$MODE PXX}   { our dialect; the FPC-parity strict-* flags do not judge this file }
{ Python's `sqlite3` — the DB-API surface, over the system libsqlite3.

  `import sqlite3` RESOLVES here through the NilPy import resolver's `mimic_`
  fallback, so no file in the tree carries the stdlib's name and `--no-shims`
  can turn the substitution into an error. See devdocs/dev/python-compat-tiers.md.

  WHY A SHIM AND NOT A HEADER IMPORT. The linking was never the gap: a NilPy
  `import` already maps onto the same unit resolver a Pascal `uses` uses, and a
  C header in /usr/include links identically. What no header can supply is the
  DB-API — CPython's `sqlite3` is a WRAPPER module, and `connect` / `execute` /
  `fetchone` exist nowhere in sqlite3.h, which exports `sqlite3_open` and
  `sqlite3_prepare_v2`. So the C calls are the easy half and are all below;
  the half that had to be designed is the row.

  THE SUBSET, and it is the lekkerzeilen surface measured ticket-side rather
  than the module index: `connect(database, uri=)`, `Error`, and on the
  connection `execute` / `executemany` / `executescript` / `commit` /
  `rollback` / `close` / `total_changes`. A cursor iterates, unpacks, and
  answers `fetchone` / `fetchall`.

  NOT HERE: `row_factory`, `detect_types`, the context-manager protocol,
  `cursor()` as an explicit object, `description`, `lastrowid`, `rowcount`,
  named (`:name`) parameters, `isolation_level` as an argument, the exception
  SUBCLASSES (OperationalError, IntegrityError, ...). Every one of those is a
  real part of the module and none of them is asked for by the corpus this was
  built against — see the note on API surface versus corpus surface in
  devdocs/progress/backlog-nilpy/feature-n-the-sqlite3-module-db-api-over-the-c-library.md.

  ---------------------------------------------------------------------------
  THREE THINGS THAT ARE NOT OBVIOUS AND COST TIME IF REDISCOVERED
  ---------------------------------------------------------------------------

  1. `uses sysutils, pylib` — THE ORDER IS LOAD-BEARING AND IT IS THE REVERSE
     OF EVERY OTHER mimic UNIT. pylib and sysutils each declare a class NAMED
     `Exception`, siblings under `ExceptionBase`, not one class with two hats
     (pylib.pas says so in its own header). A bare `Exception` resolves to
     whichever unit comes LAST, and pylib's `PyUserObjStr` renders an
     exception's `str()` from its message only for `o is Exception` with
     PYLIB's Exception. Measured 2026-09-10: with `uses pylib, sysutils`,
     `"%s" % exc` on a caught `sqlite3.Error` printed
     `<__main__.Error object at 0x...>` while a builtin ValueError and a NilPy
     `class MyErr(Exception)` both printed their message — three spellings of
     one concept, one of them in the wrong tree. lekkerzeilen/app.py:878 is
     exactly that line. mimic_urllib_error.pas dodges the same hazard by
     descending from `OSError`, a name only pylib declares; that is not open
     here, because CPython's `sqlite3.Error` descends from `Exception` and
     app.py catches `(sqlite3.Error, OSError)` as two DIFFERENT things.
     A qualified base (`class(pylib.Exception)`) is NOT accepted by this
     dialect — `base type not found: pylib` — so the uses order is the whole
     mechanism. pylib and sysutils overlap on seven interface names
     (copy, endswith, exception, indexof, replace, split, startswith); nothing
     in here calls any of the other six.

  2. `total_changes` is a PROPERTY, not a parameterless function. In Pascal a
     parameterless function IS its own call, so the two spellings look
     interchangeable — they are not, from NilPy. Measured: a `function
     total_changes: Integer` read as `db.total_changes` yields
     `<bound method at 0x...>`, because NilPy attribute access on a class
     hands back a bound method exactly as `obj.method` does in Python, and it
     cannot know this one was meant as an attribute. `property ... read Get`
     is the spelling that arrives as a value. gauges.py:188 and :193 read it.

  3. AN OMITTED `Variant` PARAMETER ARRIVES AS NONE, NOT AS ITS DEFAULT.
     `parameters: Variant = 0` is None when the caller wrote `execute(sql)`,
     so the guard here is the POSITIVE `pyvar_is_objtag` — "is this an object
     I can index" — and never `not pyvar_is_inttag`. lib/rtl/mimic_threading.pas
     records the same thing from the other side, where the negative form
     raised TypeError on a spawned thread several frames from its declaration.

  ---------------------------------------------------------------------------
  TRANSACTIONS — WHAT THIS REPRODUCES AND WHAT IT DOES NOT
  ---------------------------------------------------------------------------

  CPython's legacy default (`isolation_level=""`) does NOT run in autocommit:
  it opens an implicit transaction before the first data-modifying statement
  and holds it until `commit()`. That is observable — `close()` without a
  `commit()` LOSES the writes — so it is reproduced rather than flattened to
  autocommit, which would silently make an unfaithful program work here and
  fail under CPython.

  The discriminator is `sqlite3_stmt_readonly`, not a scan of the SQL text: it
  answers from the prepared statement's own opcodes, so `INSERT`, `UPDATE`,
  `DELETE`, `REPLACE`, a `CREATE TABLE` and a write through a trigger all come
  out right without this unit knowing any SQL. BEGIN/COMMIT/ROLLBACK themselves
  report READ-ONLY by that function (they do not modify the database directly),
  which is what keeps the flag from tripping over its own transaction control.

  `executescript` commits any pending transaction first, as CPython's does.

  ---------------------------------------------------------------------------
  STATEMENT LIFETIME
  ---------------------------------------------------------------------------

  A Cursor finalizes its statement the moment the walk ends — the common shape
  by far, since every corpus site either drains the cursor or takes one row
  from a query that has one. A cursor ABANDONED half-drained keeps its
  statement until the connection closes, and `close` uses `sqlite3_close_v2`,
  which accepts exactly that and reaps the handle when the last statement goes.
  This is a bounded leak and not a wrong answer; it is written down rather than
  fixed because fixing it needs the connection to own a live cursor list, and
  nothing in the corpus abandons a cursor.
}

interface

uses sysutils, strings, pylib;

const
  SQLITE_OK    = 0;
  SQLITE_ROW   = 100;
  SQLITE_DONE  = 101;

  SQLITE_OPEN_READONLY  = $00000001;
  SQLITE_OPEN_READWRITE = $00000002;
  SQLITE_OPEN_CREATE    = $00000004;
  SQLITE_OPEN_URI       = $00000040;

  SQLITE_INTEGER = 1;
  SQLITE_FLOAT   = 2;
  SQLITE_TEXT    = 3;
  SQLITE_BLOB    = 4;
  SQLITE_NULL    = 5;

  { MIRRORS compiler/defs.inc's variant tags, the way pylib.pas mirrors
    VT_OBJ_FIRST/VT_OBJ_LAST for the same reason: a lib/rtl unit cannot include
    a compiler header. Only two of pylib's four `pyvar_is_<x>tag` predicates are
    EXPORTED -- objtag and inttag are in its interface, the string and float
    ones are implementation-only -- and a lib/rtl unit naming an unexported one
    still compiles inside a NilPy program while failing the pinned-lib/rtl
    canary, which builds each root unit as an ordinary Pascal unit. Measured
    2026-09-10: `undefined variable` from that canary, after the whole test
    suite had passed. `pyvartag` is exported, so the tag comparison is both the
    public spelling and the one that says what it means beside the sqlite
    column-type table above. }
  VT_DOUBLE = 3;
  VT_STRING = 6;

type
  { CPython's `sqlite3.Error`, the root of the module's exception tree. The
    subclasses (OperationalError, IntegrityError, DatabaseError, ...) are NOT
    declared: the corpus catches the root, and a subclass nobody raises would
    be a name that looks like a promise. }
  Error = class(Exception) end;

  { What `execute` answers. CPython calls it a Cursor and the corpus never
    names the type — it iterates the result, unpacks its rows, or asks it for
    one row. All three go through the ITERATOR PROTOCOL: `__iter__` once, then
    `__next__` per step, terminating on StopIteration, dispatched by pylib
    through the RTTI. A Pascal class satisfies that protocol exactly as a NilPy
    one does; measured 2026-09-10, `for a, b in rows`, `list(rows)` and
    `dict(rows)` all work off a mimic-unit class. }
  Cursor = class
  public
    FStmt: Pointer;
    FDb: Pointer;
    FNCols: Integer;
    { A row is STEPPED and waiting. `execute` steps once before handing the
      cursor back — it has to, or an INSERT would never run — so the first
      __next__ must consume that step rather than take another. }
    FPending: Boolean;
    FDone: Boolean;
    constructor Create(db, stmt: Pointer; pending: Boolean);
    function __iter__: Variant;
    function __next__: Variant;
    function fetchone: Variant;
    function fetchall: Variant;
    function StepOne: Boolean;
    function RowNow: Variant;
    procedure FinishStmt;
  end;

  Connection = class
  public
    FDb: Pointer;
    FInTx: Boolean;
    FClosed: Boolean;
    { The parameter is named `database` because CPython names it that and a
      NilPy keyword argument binds by the PASCAL parameter's NAME. `uri` is
      the only other one the corpus passes, and it passes it by keyword. }
    constructor Create(database: AnsiString; uri: Boolean = False);
    function execute(sql: AnsiString; parameters: Variant = 0): Cursor;
    function executemany(sql: AnsiString; parameters: Variant = 0): Cursor;
    function executescript(sql_script: AnsiString): Cursor;
    procedure commit;
    procedure rollback;
    procedure close;
    function GetTotalChanges: Integer;
    procedure Exec(const sql: AnsiString);
    procedure Fail(const what: AnsiString);
    function Prepare(const sql: AnsiString; var tail: PChar): Pointer;
    procedure BeginIfWrites(stmt: Pointer);
    property total_changes: Integer read GetTotalChanges;
  end;

function connect(database: AnsiString; uri: Boolean = False): Connection;
function complete_statement(statement: AnsiString): Boolean;
function sqlite_version: AnsiString;

implementation

{ ------------------------------------------------------------------ the C API }
{ Only what is used. Every one of these is in libsqlite3.so.0's dynsym and in
  /usr/include/sqlite3.h; the binding shape (`cdecl; external '<soname>';`) is
  the same one lib/rtl uses for libc. }

function sqlite3_libversion: PChar; cdecl; external 'libsqlite3.so.0';
function sqlite3_open_v2(filename: PChar; var db: Pointer; flags: Integer;
                         vfs: PChar): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_close_v2(db: Pointer): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_errmsg(db: Pointer): PChar; cdecl; external 'libsqlite3.so.0';
function sqlite3_exec(db: Pointer; sql: PChar; cb: Pointer; arg: Pointer;
                      var errmsg: PChar): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_free(p: Pointer): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_prepare_v2(db: Pointer; sql: PChar; nByte: Integer;
                            var stmt: Pointer; var tail: PChar): Integer;
                            cdecl; external 'libsqlite3.so.0';
function sqlite3_step(stmt: Pointer): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_reset(stmt: Pointer): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_clear_bindings(stmt: Pointer): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_finalize(stmt: Pointer): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_stmt_readonly(stmt: Pointer): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_complete(sql: PChar): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_total_changes(db: Pointer): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_column_count(stmt: Pointer): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_column_type(stmt: Pointer; i: Integer): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_column_int64(stmt: Pointer; i: Integer): Int64; cdecl; external 'libsqlite3.so.0';
function sqlite3_column_double(stmt: Pointer; i: Integer): Double; cdecl; external 'libsqlite3.so.0';
function sqlite3_column_text(stmt: Pointer; i: Integer): PChar; cdecl; external 'libsqlite3.so.0';
function sqlite3_column_blob(stmt: Pointer; i: Integer): Pointer; cdecl; external 'libsqlite3.so.0';
function sqlite3_column_bytes(stmt: Pointer; i: Integer): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_bind_int64(stmt: Pointer; i: Integer; v: Int64): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_bind_double(stmt: Pointer; i: Integer; v: Double): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_bind_null(stmt: Pointer; i: Integer): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_bind_text(stmt: Pointer; i: Integer; v: PChar; n: Integer;
                           dtor: Pointer): Integer; cdecl; external 'libsqlite3.so.0';
function sqlite3_bind_blob(stmt: Pointer; i: Integer; v: Pointer; n: Integer;
                           dtor: Pointer): Integer; cdecl; external 'libsqlite3.so.0';

{ SQLITE_TRANSIENT — "the string is not stable, copy it now". Everything bound
  here comes out of a Variant that the caller may drop the moment execute
  returns, so TRANSIENT is the only correct choice and SQLITE_STATIC is a
  use-after-free waiting for a long-running statement. }
function TransientDtor: Pointer;
begin
  Result := Pointer(-1);
end;

function sqlite_version: AnsiString;
begin
  Result := StrPas(sqlite3_libversion);
end;

function complete_statement(statement: AnsiString): Boolean;
var cs: AnsiString;
begin
  cs := statement + #0;
  Result := sqlite3_complete(@cs[1]) <> 0;
end;

{ ------------------------------------------------------------------- Cursor }

constructor Cursor.Create(db, stmt: Pointer; pending: Boolean);
begin
  FDb := db;
  FStmt := stmt;
  FNCols := sqlite3_column_count(stmt);
  FPending := pending;
  FDone := not pending;
end;

procedure Cursor.FinishStmt;
var s: Pointer;
begin
  if FStmt = nil then Exit;
  s := FStmt;
  FStmt := nil;             { cleared FIRST — a raise below must not double-finalize }
  sqlite3_finalize(s);
end;

{ True when a row is available NOW, in RowNow. False at the end of the walk,
  which also finalizes: the common shape drains, and holding the statement
  past the last row is what would make an ordinary loop leak. }
function Cursor.StepOne: Boolean;
var rc: Integer; msg: AnsiString;
begin
  Result := False;
  if FPending then
  begin
    FPending := False;
    Result := True;
    Exit;
  end;
  if FDone or (FStmt = nil) then Exit;
  rc := sqlite3_step(FStmt);
  if rc = SQLITE_ROW then
  begin
    Result := True;
    Exit;
  end;
  FDone := True;
  if rc <> SQLITE_DONE then
  begin
    msg := StrPas(sqlite3_errmsg(FDb));
    FinishStmt;
    raise Error.Create(msg);
  end;
  FinishStmt;
end;

{ The current row as a LIST of variants, one per column, each carrying the
  column's own sqlite type. NilPy has no tuple type — a list IS the tuple here,
  and indexing, slicing and unpacking are identical, which is what lets
  `name, kind, stride, verts, indices = row` and `row[1:]` both work. }
function Cursor.RowNow: Variant;
var l: TPyList; i, ct, n: Integer; b: TPyBytes; p: Pointer;
begin
  l := TPyList.Create;
  for i := 0 to FNCols - 1 do
  begin
    ct := sqlite3_column_type(FStmt, i);
    if ct = SQLITE_INTEGER then
      l.append(pyvar_of_int(sqlite3_column_int64(FStmt, i)))
    else if ct = SQLITE_FLOAT then
      l.append(pyvar_id(sqlite3_column_double(FStmt, i)))
    else if ct = SQLITE_TEXT then
      l.append(pyvar_id(StrPas(sqlite3_column_text(FStmt, i))))
    else if ct = SQLITE_BLOB then
    begin
      { A BLOB is Python `bytes`, and it is NOT a string: it may hold a zero
        byte anywhere, so StrPas would truncate it at the first one and answer
        a shorter blob with no error at all. The length comes from
        sqlite3_column_bytes and the bytes are copied, because sqlite owns
        that buffer only until the next step. }
      n := sqlite3_column_bytes(FStmt, i);
      b := TPyBytes.Create(n);
      if n > 0 then
      begin
        p := sqlite3_column_blob(FStmt, i);
        if p <> nil then Move(p^, b.FData^, n);
      end;
      l.append(TObject(b));
    end
    else
      l.append(pynone);
  end;
  Result := TObject(l);
end;

function Cursor.__iter__: Variant;
begin
  Result := Self;
end;

function Cursor.__next__: Variant;
begin
  if not StepOne then raise StopIteration.Create('sqlite3 cursor exhausted');
  Result := RowNow;
end;

{ CPython answers None — not an empty tuple — when there is no row, and the
  corpus tests exactly that: `... .fetchone() is not None` and `if row else`. }
function Cursor.fetchone: Variant;
begin
  if not StepOne then
  begin
    Result := pynone;
    Exit;
  end;
  Result := RowNow;
end;

function Cursor.fetchall: Variant;
var l: TPyList;
begin
  l := TPyList.Create;
  while StepOne do l.append(RowNow);
  Result := TObject(l);
end;

{ --------------------------------------------------------------- Connection }

{ The message is sqlite's OWN, and `what` is only the fallback for the case
  where there is no handle to ask. Concatenating the two was tried first and
  produced `unable to open database file: unable to open database file` --
  sqlite already words these the way CPython prints them, so anything added
  here is a divergence in the one string a program is most likely to log. }
procedure Connection.Fail(const what: AnsiString);
var m: AnsiString;
begin
  m := '';
  if FDb <> nil then m := StrPas(sqlite3_errmsg(FDb));
  if m = '' then m := what;
  raise Error.Create(m);
end;

constructor Connection.Create(database: AnsiString; uri: Boolean = False);
var cs: AnsiString; flags, rc: Integer; h: Pointer;
begin
  FDb := nil;
  FInTx := False;
  FClosed := False;
  cs := database + #0;
  flags := SQLITE_OPEN_READWRITE or SQLITE_OPEN_CREATE;
  { `uri=True` is what lets `file:x?mode=ro` mean read-only. Without the flag
    sqlite treats the whole URI as a FILENAME and cheerfully CREATES a file
    called `file:x?mode=ro` — a wrong answer with no error, which is the shape
    lekkerzeilen/world.py:512 comments on in its own source. }
  if uri then flags := flags or SQLITE_OPEN_URI;
  h := nil;
  rc := sqlite3_open_v2(@cs[1], h, flags, nil);
  FDb := h;
  if rc <> SQLITE_OK then
  begin
    { sqlite3_open_v2 hands back a handle even on failure, precisely so the
      error can be read off it; it must still be closed. }
    Fail('unable to open database file');
  end;
end;

procedure Connection.Exec(const sql: AnsiString);
var cs, m: AnsiString; err: PChar; rc: Integer;
begin
  cs := sql + #0;
  err := nil;
  rc := sqlite3_exec(FDb, @cs[1], nil, nil, err);
  if rc <> SQLITE_OK then
  begin
    m := '';
    if err <> nil then
    begin
      m := StrPas(err);
      sqlite3_free(Pointer(err));
    end;
    if m = '' then m := StrPas(sqlite3_errmsg(FDb));
    raise Error.Create(m);
  end;
end;

function Connection.Prepare(const sql: AnsiString; var tail: PChar): Pointer;
var cs: AnsiString; stmt: Pointer; rc: Integer;
begin
  if FClosed then raise Error.Create('Cannot operate on a closed database.');
  cs := sql + #0;
  stmt := nil;
  tail := nil;
  rc := sqlite3_prepare_v2(FDb, @cs[1], -1, stmt, tail);
  if rc <> SQLITE_OK then Fail('prepare failed');
  if stmt = nil then raise Error.Create('no statement in ' + sql);
  Result := stmt;
end;

{ The implicit transaction CPython's legacy isolation_level opens before the
  first WRITE. Asked of the prepared statement rather than of the SQL text —
  see the header. }
procedure Connection.BeginIfWrites(stmt: Pointer);
begin
  if FInTx then Exit;
  if sqlite3_stmt_readonly(stmt) <> 0 then Exit;
  Exec('BEGIN');
  FInTx := True;
end;

{ Bind one variant into parameter `pos` (1-based, as sqlite counts them). }
procedure BindOne(stmt: Pointer; pos: Integer; const v: Variant);
var tag: Int64; s: AnsiString; o: TObject; b: TPyBytes; d: Double; i: Int64;
    empty: Byte; p: Pointer;
begin
  { A NON-NULL address for a ZERO-length value, and it is not a formality.
    sqlite3_bind_blob and _bind_text document that a NULL data pointer makes
    the call equivalent to sqlite3_bind_null REGARDLESS of the length, so
    `b""` and `""` bound through a nil pointer land in the database as SQL
    NULL. Measured 2026-09-10: an empty blob came back as None and `len()` on
    it raised TypeError three statements later, with nothing about the failure
    naming the bind. TRANSIENT copies immediately, so a stack byte is a
    perfectly good source for zero bytes. }
  empty := 0;
  tag := pyvartag(v);
  if tag = 0 then
  begin
    sqlite3_bind_null(stmt, pos);
    Exit;
  end;
  if tag = VT_STRING then
  begin
    s := v;
    { -1 would make sqlite call strlen, which is wrong for a Python str
      holding a NUL. The byte count is known here, so pass it. }
    if Length(s) = 0 then sqlite3_bind_text(stmt, pos, PChar(@empty), 0, TransientDtor)
    else sqlite3_bind_text(stmt, pos, @s[1], Length(s), TransientDtor);
    Exit;
  end;
  if tag = VT_DOUBLE then
  begin
    d := v;
    sqlite3_bind_double(stmt, pos, d);
    Exit;
  end;
  if pyvar_is_objtag(v) then
  begin
    o := TObject(pyvarobj(v));
    if o is TPyBytes then
    begin
      b := TPyBytes(o);
      p := b.FData;
      if (p = nil) or (b.count = 0) then p := @empty;
      sqlite3_bind_blob(stmt, pos, p, b.count, TransientDtor);
      Exit;
    end;
    { A list, a dict, a user object: sqlite has no column type for it and
      CPython raises InterfaceError. One class here, so it is Error. }
    raise Error.Create('Error binding parameter ' + IntToStr(pos - 1)
                       + ' - probably unsupported type.');
  end;
  { Everything left is integer-shaped — VT_INT, VT_INT64, VT_BOOL, VT_CHAR.
    Python's bool IS an int to sqlite (True stores as 1), which is CPython's
    own behaviour and not a rounding of ours. }
  i := v;
  sqlite3_bind_int64(stmt, pos, i);
end;

{ True when `parameters` actually carries a sequence. THE GUARD IS POSITIVE:
  an omitted `Variant = 0` parameter arrives as NONE, not as an int-tagged 0,
  so `not pyvar_is_inttag` would call this a sequence and pylen_v would raise
  TypeError from inside the shim. }
function HasParams(const parameters: Variant): Boolean;
begin
  Result := pyvar_is_objtag(parameters);
end;

procedure BindRow(stmt: Pointer; const row: Variant);
var n, k: Integer;
begin
  if not HasParams(row) then Exit;
  n := pylen_v(row);
  for k := 0 to n - 1 do
    BindOne(stmt, k + 1, pyvar_getitem(row, k));
end;

function Connection.execute(sql: AnsiString; parameters: Variant = 0): Cursor;
var stmt: Pointer; tail: PChar; rc: Integer; msg: AnsiString;
begin
  stmt := Prepare(sql, tail);
  BindRow(stmt, parameters);
  BeginIfWrites(stmt);
  { STEP ONCE HERE. An INSERT must run at execute() time — CPython's does, and
    a cursor nobody iterates is exactly how every write in the corpus is
    spelled. The row that step may produce is handed to the Cursor as PENDING
    so the first __next__ consumes it instead of skipping it. }
  rc := sqlite3_step(stmt);
  if (rc <> SQLITE_ROW) and (rc <> SQLITE_DONE) then
  begin
    msg := StrPas(sqlite3_errmsg(FDb));
    sqlite3_finalize(stmt);
    raise Error.Create(msg);
  end;
  Result := Cursor.Create(FDb, stmt, rc = SQLITE_ROW);
  if rc = SQLITE_DONE then Result.FinishStmt;
end;

function Connection.executemany(sql: AnsiString; parameters: Variant = 0): Cursor;
var stmt: Pointer; tail: PChar; rc, i, n: Integer; msg: AnsiString;
begin
  stmt := Prepare(sql, tail);
  BeginIfWrites(stmt);
  n := 0;
  if HasParams(parameters) then n := pylen_v(parameters);
  for i := 0 to n - 1 do
  begin
    sqlite3_reset(stmt);
    sqlite3_clear_bindings(stmt);
    BindRow(stmt, pyvar_getitem(parameters, i));
    rc := sqlite3_step(stmt);
    { CPython refuses a row-PRODUCING statement in executemany outright. A
      SELECT here is a program bug, not a shape to guess at, so it is refused
      rather than silently discarded. }
    if rc = SQLITE_ROW then
    begin
      sqlite3_finalize(stmt);
      raise Error.Create('executemany() can only execute DML statements.');
    end;
    if rc <> SQLITE_DONE then
    begin
      msg := StrPas(sqlite3_errmsg(FDb));
      sqlite3_finalize(stmt);
      raise Error.Create(msg);
    end;
  end;
  sqlite3_finalize(stmt);
  { An empty, already-finished cursor: executemany answers a cursor in CPython
    too, and nothing iterates it. }
  Result := Cursor.Create(FDb, nil, False);
end;

function Connection.executescript(sql_script: AnsiString): Cursor;
begin
  { CPython commits any pending transaction before running the script. }
  commit;
  Exec(sql_script);
  Result := Cursor.Create(FDb, nil, False);
end;

procedure Connection.commit;
begin
  if not FInTx then Exit;
  FInTx := False;
  Exec('COMMIT');
end;

procedure Connection.rollback;
begin
  if not FInTx then Exit;
  FInTx := False;
  Exec('ROLLBACK');
end;

{ CPython does NOT commit on close — uncommitted work is lost, and a program
  that relies on close-to-save is broken there too. So this does not commit
  either; see the header. }
procedure Connection.close;
var h: Pointer;
begin
  if FClosed then Exit;
  FClosed := True;
  FInTx := False;
  h := FDb;
  FDb := nil;
  if h <> nil then sqlite3_close_v2(h);
end;

function Connection.GetTotalChanges: Integer;
begin
  if FDb = nil then Result := 0
  else Result := sqlite3_total_changes(FDb);
end;

function connect(database: AnsiString; uri: Boolean = False): Connection;
begin
  Result := Connection.Create(database, uri);
end;

end.
