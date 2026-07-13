{ SPDX-License-Identifier: Zlib }
unit variants;
{ The FPC `Variants` surface, over pxx's own Variant.

  A pxx Variant is a 16-byte tagged value: an 8-byte TAG (the VT_* constants in
  defs.inc) followed by an 8-byte payload interpreted per tag. That is our model, not
  FPC's TVarData, and it is deliberately a closed scalar set -- so this unit exposes the
  parts of Variants that are meaningful over it, and does not pretend to the rest.

  Tag values (VT_*, from the compiler):
    0 empty   1 int   2 int64   3 double   4 boolean   5 char   6 string

  Note 0 = EMPTY, matching FPC's varEmpty, which is what `VarType(v) = 0` tests. FPC
  additionally distinguishes varNull (1) from varEmpty; pxx has no separate NULL tag, so
  VarIsNull and VarIsEmpty are the same question here and both answer "is it unassigned".
  Code that needs a real three-way empty/null/value distinction wants a ticket, not a
  silent approximation -- say so rather than guessing.

  Exists because fcl-json's fpjson.pp does `uses variants`. }

interface

type
  TVarType = Word;

{ FPC's Null / Unassigned variant values.

  READ THE UNIT HEADER: pxx has ONE "no value" tag (VT_EMPTY), where FPC distinguishes
  varEmpty (never assigned) from varNull (assigned, but null). So these two return the SAME
  thing here, and `VarIsNull(Unassigned)` is True where FPC says False.

  That is a real approximation and it is stated rather than hidden. It is the right one for
  the callers that exist -- fpjson uses Null purely as "the JSON null value", never to
  distinguish it from unassigned -- but code that genuinely needs the three-way
  empty/null/value distinction wants a compiler change (a VT_NULL tag), not a library
  workaround. Say so rather than quietly returning the wrong answer.

  These are VARIABLES, not functions, because a function cannot return a Variant in this
  compiler yet (bug-variant-function-return -- a Variant result segfaults). FPC declares them
  as functions; as read-only values the difference is invisible to callers, which is the
  whole surface anyone uses. They are initialised empty and nothing writes them. }
var
  Null: Variant;
  Unassigned: Variant;

{ The tag of V (VT_EMPTY..VT_STRING above). }
function VarType(const V: Variant): TVarType;

{ True when V holds no value. pxx has one "no value" tag, so these agree -- see the note
  above. }
function VarIsEmpty(const V: Variant): Boolean;
function VarIsNull(const V: Variant): Boolean;

{ True when V holds a number (integer kinds or a double). }
function VarIsNumeric(const V: Variant): Boolean;

{ True when V holds a string. }
function VarIsStr(const V: Variant): Boolean;

implementation

type
  PTagWord = ^Int64;

function VarType(const V: Variant): TVarType;
begin
  { the tag is the first machine word of the slot }
  Result := TVarType(PTagWord(@V)^);
end;

function VarIsEmpty(const V: Variant): Boolean;
begin
  Result := VarType(V) = 0;
end;

function VarIsNull(const V: Variant): Boolean;
begin
  Result := VarType(V) = 0;
end;

function VarIsNumeric(const V: Variant): Boolean;
var t: TVarType;
begin
  t := VarType(V);
  Result := (t = 1) or (t = 2) or (t = 3);
end;

function VarIsStr(const V: Variant): Boolean;
begin
  Result := VarType(V) = 6;
end;

end.
