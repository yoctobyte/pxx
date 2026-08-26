{ FPC routine directives that pxx can honestly ignore, in the three positions
  that carry one: a routine with a body, a class method (declaration AND
  implementation header), and an interface method signature.

  Found by marching the real FPC compiler sources through pxx: `constexp.pas`
  stopped dead on `procedure internalerror(i:longint); noreturn;` — a directive
  that changes nothing pxx emits, refused as a syntax error, with the whole
  unit behind it.

  The set is drawn on purpose and the line is "would ignoring it make pxx
  compile something other than what was written?" These six say no —
  `noreturn`/`noinline` are hints about code pxx already decides for itself,
  `nostackframe` asks for an optimisation not making which is merely bigger,
  `far`/`near` are 16-bit memory models, and `local` is unit-scoped visibility
  in a whole-program compiler that has no separate unit output. `varargs`,
  `public`, `export`, `alias`, `weakexternal`, `compilerproc` and
  `hardfloat`/`softfloat` say yes, and stay refused.

  test_calling_convention_directives_everywhere is the same shape for the
  calling-convention spellings; both ask ONE predicate, because five separate
  directive loops each grew their own copy of the set and drifted.

  NOT oracled against FPC, and that is a finding rather than a gap: FPC 3.2.2's
  own answer is uneven, and it is uneven in a way that would make an oracle
  assert FPC's accidents rather than this rule.

  | directive | FPC on a routine | FPC on a method |
  | --- | --- | --- |
  | `noreturn`     | ok | ok |
  | `near`         | ok | ok |
  | `local`        | ok | ok |
  | `far`          | ok | *rejected* |
  | `nostackframe` | *"declared with call option NOSTACKFRAME but without ASSEMBLER"* | same |
  | `noinline`     | *syntax error* — the directive is 3.3.1, not 3.2.2 | same |

  pxx accepts all six everywhere. Accepting a form FPC rejects is not a defect
  (CLAUDE.md): none of the six changes what is emitted, so there is nothing for
  a stricter rule to protect. }
program test_inert_routine_directives;

type
  TC = class
    procedure MNoreturn;     noreturn;
    procedure MNostackframe; nostackframe;
    procedure MNoinline;     noinline;
    procedure MFar;          far;
    procedure MNear;         near;
    procedure MLocal;        local;
  end;

  IProbe = interface
    procedure INoreturn;     noreturn;
    procedure INostackframe; nostackframe;
    procedure INoinline;     noinline;
    procedure IFar;          far;
    procedure INear;         near;
    procedure ILocal;        local;
  end;

procedure RNoreturn(a: Integer);     noreturn;     begin end;
procedure RNostackframe(a: Integer); nostackframe; begin end;
procedure RNoinline(a: Integer);     noinline;     begin end;
procedure RFar(a: Integer);          far;          begin end;
procedure RNear(a: Integer);         near;         begin end;
procedure RLocal(a: Integer);        local;        begin end;

{ forward declaration + separate body: the pre-scan loop and the
  implementation-header loop are two different lists, and a directive that
  parses in one and not the other is how this class of bug shows up }
function Twice(a: Integer): Integer; noinline; forward;
function Twice(a: Integer): Integer; noinline;
begin Twice := a * 2; end;

procedure TC.MNoreturn;     noreturn;     begin writeln('m noreturn');     end;
procedure TC.MNostackframe; nostackframe; begin writeln('m nostackframe'); end;
procedure TC.MNoinline;     noinline;     begin writeln('m noinline');     end;
procedure TC.MFar;          far;          begin writeln('m far');          end;
procedure TC.MNear;         near;         begin writeln('m near');         end;
procedure TC.MLocal;        local;        begin writeln('m local');        end;

var
  c: TC;
  i: IProbe;
begin
  RNoreturn(1); RNostackframe(1); RNoinline(1); RFar(1); RNear(1); RLocal(1);
  writeln('routines ok');

  c := TC.Create;
  c.MNoreturn; c.MNostackframe; c.MNoinline; c.MFar; c.MNear; c.MLocal;

  i := nil;
  if i = nil then writeln('interface ok');

  writeln(Twice(21));
end.
