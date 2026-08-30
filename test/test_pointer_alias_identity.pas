{ A pointer type ALIAS must be the type it aliases — same element, same
  assignability — in every spelling and across a unit boundary.

  RegisterGeneralAlias recorded `AliasElemTk := tk`, conflating "what kind is
  T?" with "what does T point AT?". Invisible for non-pointer aliases (nothing
  reads the element), but it made EVERY general pointer alias record a
  tyPointer element regardless of target: `= Pointer`, `= PChar` and `= PRec`
  all collapsed to the same value, which is correct only for the single
  spelling `^Pointer` and correct there by coincidence.

  THREE symptoms, one cause. Each arm was verified ON ITS OWN against the pinned
  v393 binary (1d69760deabe2865), because two of them are compile-time errors
  and a single run stops at the first — do not read one failing run as evidence
  about more than its first error:

    - deref:    `p^.field` through an alias of a pointer-to-record
                -> "a pointer has no members"           (v393: compile error)
    - pchar:    `c[i]` through an alias of PChar
                -> printed 378951523 instead of `pxx`   (v393: SILENT garbage,
                   the worst of the three and the one nobody had noticed)
    - overload: a `Pointer` alias rejects a class instance that plain `Pointer`
                accepts -> "no overload of ... matches these arguments"

  The overload arm is POSITION-DEPENDENT on v393 and that is not a curiosity —
  it is why this ticket read as two separate bugs. Measured on v393: an alias
  formal at parameter index 0 is ACCEPTED, at index 1 or 2 REJECTED, and the
  cross-unit case accepted regardless. That is the signature of the stale-symbol
  read fixed by
  bug-p-a-parameters-pointer-element-type-is-lost-between-registration-and-overload-matching:
  the matcher was reading a RECYCLED symbol slot whose value happened to be the
  untyped sentinel on some paths. Fixing that read did not introduce this defect,
  it made a garbage channel deterministic — so a wrong answer that had been
  shape-dependent became consistent, and Synapse (alias formal, cross-unit) went
  from accidentally passing to reliably failing. One cause, two eras.

  So the positional arm below is load-bearing: a fix verified only with the
  alias at index 0 would have been tested exclusively on the one shape that was
  green on the broken binary.

  THE CONTROL IS THE POINT. `PtrToPtr = ^Pointer` genuinely has a tyPointer
  element and must NOT move; it is the one spelling the broken code got right,
  so a fix that propagates carelessly turns it into the untyped sentinel and
  this test catches that. Every value is distinctive (74xx/31xx) rather than
  0/1: two arms agreeing on a boring number is not evidence they bound the
  right formal.

  bug-p-a-pointer-type-alias-rejects-a-class-instance-that-plain-pointer-accepts }
program test_pointer_alias_identity;
uses uptralias;

type
  TRec = record a: Integer; b: Integer; end;
  PRec = ^TRec;
  LocalP    = Pointer;     { same-unit alias of untyped Pointer }
  LocalP2   = LocalP;      { alias of an alias }
  LocalPR   = PRec;        { alias of a pointer to record }
  LocalPC   = PChar;       { alias of a pointer to char }
  PtrToPtr  = ^Pointer;    { NOT an alias — a real pointer-to-pointer (control) }
  TThing = class
    procedure Go;
  end;

var
  r: TRec;
  raw: Pointer;
  pp: PtrToPtr;
  lp: LocalPR;
  lc: LocalPC;
  t: TThing;
  same1, same2, atpos: Integer;

{ same-unit overload arm, alias at parameter index 0 — the shape that PASSED on
  the broken binary. Kept precisely because it passed: it is the control that
  says the fix did not break the one path that already worked. }
function LocalTakes(p: LocalP): Integer;
begin if p = nil then LocalTakes := 0 else LocalTakes := 3101; end;

{ ...and the same call with the alias at index 1 and 2, which v393 REJECTED.
  These are the arms that actually fail on the broken binary. }
function LocalTakesAt1(x: Pointer; p: LocalP): Integer;
begin if p = nil then LocalTakesAt1 := 0 else LocalTakesAt1 := 3111; end;

function LocalTakesAt2(x, y: Pointer; p: LocalP): Integer;
begin if p = nil then LocalTakesAt2 := 0 else LocalTakesAt2 := 3122; end;

function LocalTakes2(p: LocalP2): Integer;
begin if p = nil then LocalTakes2 := 0 else LocalTakes2 := 3102; end;

procedure TThing.Go;
begin
  { `self` is a class instance reaching a Pointer-alias formal — the exact
    shape of Synapse's SslCtxSetDefaultPasswdCbUserdata(FCtx, self) call }
  same1 := LocalTakes(self);
  same2 := LocalTakes2(self);
  atpos := LocalTakesAt1(nil, self) + LocalTakesAt2(nil, nil, self);
end;

begin
  r.a := 4177; r.b := 9931;
  t := TThing.Create;
  t.Go;

  { 1. same-unit overload, alias and alias-of-alias }
  writeln('same ', same1, ' ', same2);

  { positional arm: 3111 + 3122 = 6233. On v393 these two were the rejected
    shapes while `same` above was accepted. }
  writeln('atpos ', atpos);

  { 2. cross-unit overload: alias, alias-of-alias, and the plain control }
  writeln('cross ', TakesAlias(t), ' ', TakesAlias2(t), ' ', TakesPlain(t));

  { 3. deref through a pointer alias, same-unit and cross-unit }
  lp := @r;
  writeln('deref ', lp^.a, ' ', lp^.b, ' ', SumVia(@r));

  { 4. alias of PChar still indexes as chars, not as pointers }
  lc := 'pxx';
  writeln('pchar ', lc[0], lc[1], lc[2]);

  { 5. CONTROL — ^Pointer must still be a pointer to a pointer. If the fix
       over-propagated and gave it the untyped element, `pp^` stops being a
       Pointer and this arm changes. }
  raw := @r;
  pp := @raw;
  if pp^ = @r then writeln('ctrl ok') else writeln('ctrl BAD');

  t.Free;
end.
