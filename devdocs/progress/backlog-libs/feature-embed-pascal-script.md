---
prio: 45  # auto
track: B
type: feature
status: backlog
summary: "ATTEMPTED 2026-09-01, wall MAPPED rather than guessed at, and TWO OF THE THREE ARE NOW DOWN. uPSUtils compiles CLEAN on the pinned stable, first try, no flags beyond -Mobjfpc. uPSCompiler hit three walls: (1) missing PByteArray -- FIXED, a System-level FPC type, now in lib/rtl/sysutils.pas; (2) a value cast to a string alias dropped a following INDEX -- FIXED 2026-09-02 (9339d6661), so `tbtwidestring(p^.twidestring)[1]`, the shape that file uses 13 times, compiles and runs; (3) STILL OPEN and it is the only one left: `SetLength(tbtstring(p^.tstring), n)` (line 2753) answers `SetLength expects a string variable in IR codegen` -- a DIFFERENT arm from (2), the lowering wants an IR_LEA and a cast is not one. uPSRuntime has not been reached: it stops earlier on a `{$IF}` comparison. NOT vendored -- probed against a clone outside the repo, which is the reversible half of the ticket's own two options."
---

# RemObjects Pascal Script — compile under pxx (embeddable scripting)

- **Type:** feature / investigation (real-world compat target + feature)
- **Track:** P (Pascal frontend) — rung of [[feature-pascal-corpus-expansion]]
- **Status:** backlog
- **Owner:** opus-p
  compiler. Compiler gaps it surfaces → Track A tickets.)
- **Opened:** 2026-06-26
- **Upstream:** `github.com/remobjects/pascalscript` — pure Object Pascal,
  compiles into the exe (no external runtime files). Bytecode interpreter for an
  Object-Pascal subset. Delphi **and** FPC supported upstream.
- **License:** custom zlib-style + **mandatory attribution** (a visible
  "made using RemObjects Pascal Script" + where-to-find line in aboutbox/docs).
  Commercial OK, redistribution OK, **no copyleft** — clean to vendor. Keep the
  attribution line if we ship it.
- **Relation:** sibling of [[feature-synapse-compile-check]] (same "compile a real
  third-party Object Pascal codebase, file the gaps" loop). Likely consumer of
  [[feature-mimic-fpc]] / `{$mode delphi}` + [[feature-mode-delphi-remaining]].
  Gentler cousin of [[feature-embed-dwscript-rtti]] (the RTTI stress test).

## Why this is a good test case (the actual motivation)

Two wins at once:
1. **Compiler conformance.** A self-contained, FPC-clean, mid-size Object Pascal
   codebase (lexer + compiler + bytecode runtime + import glue). Compiling it on
   the pinned stable is a heavyweight real-world test that exercises the dialect
   far past our own RTL — like Synapse, but a different shape (interpreter, not
   networking). Lowest-friction of the Pascal scripting engines, so it goes first.
2. **A feature for free.** Once it builds, frank2 apps gain an embedded
   Object-Pascal scripting engine. We are *not* rolling our own — purely reusing.

## Approach

- Vendor the `Source/` units (or point `pxx -Fu` at a clone) under `{$mode delphi}`
  + `--mimic-fpc`.
- Start with the core: lexer/parser/compiler (`uPSCompiler`, `uPSUtils`) +
  runtime (`uPSRuntime`), the minimal set to compile+run a `writeln('hi')` script.
- Defer the optional importers (DB, classes, Lazarus) until the core runs.
- Each compile failure that is a genuine dialect/codegen gap → a Track A ticket
  with the exact `pascal26:` error; library-surface gaps → RTL work here.
- A smoke test (`test/lib_pascalscript`?) that compiles a tiny script string and
  asserts its output, wired into `make lib-test`.

## Done when

`$(PXX_STABLE)` builds the Pascal Script core, and a frank2 host program runs a
small script end-to-end (compile → execute → observe output) under a smoke.
Stretch: host↔script binding of a hand-registered function.

## License compliance (we honour it)

If we ship a demo or test app built on Pascal Script, we **follow the license and
give the attribution** — a visible "made using RemObjects Pascal Script" line (and
where to find it) in the app's aboutbox / docs / README, and we keep the upstream
notice in any vendored source. Fair trade for a free engine; bake the credit line
into the demo from the start, not as an afterthought.

## Log

### First probe 2026-06-28 (v83, --mimic-fpc)

Clone at `external/pascalscript/` (remobjects/pascalscript, shallow). Core units probed
with temporary lowercase copies (see [[bug-c-header-case-sensitivity-lookup]] — compiler
lowercases unit name for file lookup; uPS* units have mixed-case filenames → not found
without workaround).

| unit | state |
|------|-------|
| `uPSUtils` | **[[bug-consteval-named-type-cast]]** — `IPointer(expr)` in const expr fails ConstEval (same bug as Synapse `TSocket(NOT(0))`) |
| `uPSPreProcessor` | same — `IPointer` cast |
| `uPSCompiler` | same — `IPointer` cast |
| `uPSRuntime` | **[[bug-mimic-fpc-version-defines-missing]]** — `{$IF DEFINED(FPC) and (FPC_VERSION >= 3)}` fails; `FPC_VERSION` not defined as integer under `--mimic-fpc` |

**3 Track A bugs gate the core** (1 shared with Synapse, 1 new, 1 infrastructure):
1. [[bug-c-header-case-sensitivity-lookup]] — unit name lowercasing blocks all `uPS*` units on Linux
2. [[bug-consteval-named-type-cast]] — `IPointer(expr)` in const, blocks uPSUtils/uPSPreProcessor/uPSCompiler
3. [[bug-mimic-fpc-version-defines-missing]] — `FPC_VERSION` integer missing, blocks uPSRuntime

When Track A fixes these, re-probe for the next wall.

## Open questions

- How much of Pascal Script leans on Delphi-only RTTI vs manual registration
  (manual `RegisterMethod`/`AddFunction` is the plain path — start there, avoid
  RTTI until [[feature-embed-dwscript-rtti]] tackles auto-bind).
- Which `{$mode delphi}` / mimic-fpc corners it hits first (per-unit mode reset,
  interface delegation, variants).

## Probe log 2026-07-12 (opus-p)

Clone at github.com/remobjects/pascalscript, probe
`--mimic-fpc -Fu<clone>/Source -Fulib/rtl -Fulib/rtl/platform/posix`,
target unit uPSUtils. Walls burned this session:
1. const array-of-RECORD with named-field element inits
   (`(name: 'AND'; c: CSTII_and)` keyword table) — LANDED (parser,
   test_const_array_of_record).
2. `SysUtils.CurrToStr` / Currency — LANDED (sysutils shim: Currency=Double).
3. `Pos(tbtstring(' '), s)` — string-typed ALIAS casts were pointer
   reinterprets (arg matched nothing) — LANDED: value no-op passthrough.

**Current wall:** `CheckReserved(FLastUpToken, CurrTokenId)` — a managed
(tyAnsiString) field passed to a `Const S: ShortString` param: the const
frozen-string param is by-ref for ABI, the managed→frozen conversion
produces a non-lvalue, and the by-ref argument check rejects it. Needs the
const-frozen-string param path to materialize a conversion temp (mirror the
const-record temp rule) — parser/ir slice, file/pick up next session.

## Probe log 2026-07-12 (later, opus-p)

**uPSUtils compiles** (walls 4-8): FPC variable typecast as var arg
(Cardinal(len)), Dec(Byte(p^),32) cast-deref/type-keyword targets,
TObject(x).Free statement, FreeAndNil, managed→ShortString param conversion.

**uPSCompiler wall:** `IUnknown_Guid: TGuid = (D1:0; ...; D4:($C0,...))` — pxx
has NO builtin **TGuid** record (it's a System type; interfaces reference it).
The array-valued-field record const shape itself now works (LANDED,
test_record_const_array_field — TGuid's D4 array field). What's missing is
the builtin TGuid type + interface-GUID semantics. `-dPS_NOINTERFACES` skips
the GUID consts and reaches the next wall (uPSCompiler:1963, a `Decl.Params`
shape). Pascal Script core (uPSCompiler+uPSRuntime) is a multi-wall haul
past this — needs builtin TGuid, ole2/Variant surface (uPSRuntime uses ole2),
and more. Parked; uPSUtils is the concrete milestone reached.

Update: **builtin TGuid landed** (RegisterBuiltinTGuid — System record,
SizeOf 16); uPSCompiler advances past the GUID consts to uPSCompiler:1963,
a `{$IFDEF CPU64}...Result := False` block (CPU64 IS defined; the wall is
the surrounding record-field expression `Decl.Params[i].Mode` shape after
include expansion — needs isolation). Full Pascal Script core remains a
multi-wall haul (ole2/Variant for uPSRuntime, InvokeCall.inc assembly). The
generally-useful spinoffs all landed: array-field record consts, builtin
TGuid, variable typecasts as var args, cast-deref Dec targets,
TObject(x).Free, managed→ShortString param conversion, FreeAndNil.

- 2026-07-19 (backlog sweep note) Note: external/pascalscript clone is gone from library_candidates (only synapse remains) — a resume must re-fetch upstream first. uPSUtils-compiles milestone stands (pin v209 c718f279).


---

## 2026-09-01 (frankH) — attempted; the wall is three bricks and two of them are one cause

Probed against a `--depth 1` clone **outside the repo** with `-Fups/Source`,
which is the reversible half of this ticket's own two options. Nothing was
vendored, so there is no licence obligation incurred and nothing to revert.

**The good news first, because it changes what this ticket is worth:
`uPSUtils` compiles CLEAN on `$(PXX_STABLE)`, first try**, with no flags beyond
`-Mobjfpc` and no source edits. That is a 40KB unit of real third-party Object
Pascal, and it says the dialect surface is closer than "vendor it and see"
suggests.

### The three walls in `uPSCompiler.pas`, in the order the target hits them

**1. `unknown type: PByteArray` (line 3085) — FIXED.** FPC and Delphi declare
`TByteArray` / `PByteArray` in SYSTEM, so real code reaches them with no uses
clause. pxx has no System unit, so — exactly as the `HModule` note in that file
already records — implicitly-reached System types live in `lib/rtl/sysutils.pas`.
Added there.

The interesting part is a **name collision that is deliberate and was checked
rather than reasoned about**: `lib/rtl/hashing.pas` already declares
`TByteArray = array of Byte`, a DYNAMIC array — a different type wearing the
same name. FPC has the same situation and resolves it the same way (a unit's own
declaration shadows System's). Verified by compiling a program that uses BOTH in
one file and by re-running every existing `TByteArray` consumer in the tree
(`lib_base64`, `lib_png`, `lib_zlib`, `raytracer`) — `lib_png`'s output is
byte-identical to the same test built against the unmodified `sysutils`, which
is the control that matters, since its last line reads `bad chunk crc` and would
otherwise look like a regression I had caused.

**2. `expected comma or close parenthesis` (line 1930) — FILED.**
`tbtwidestring(p^.twidestring)[1]` as a call argument. 13 occurrences of the
shape in that one file.

**3. `SetLength expects a string variable in IR codegen` (line 2753) — SAME
BUG.** `SetLength(tbtstring(vari^.tstring), n)`. Confirmed same cause with a
control: drop the cast and it works — `SetLength(p^.s, 4)` compiles,
`SetLength(tbtstring(p^.s), 8)` does not.

Both are [[bug-p-a-cast-to-a-string-alias-silently-drops-a-following-index]]: a
value cast to a non-pointer type is not transparent to the postfix tail. **Its
worst face is not either of these** — in plain assignment position the index is
silently DROPPED and FPC disagrees with no diagnostic, which is why that ticket
is 60 and its two already-closed siblings were 45. Root cause is
[[refactor-p-one-lvalue-path-for-statements-and-expressions]], which now has
four instances.

### Not reached

`uPSRuntime` stops earlier and for an unrelated reason —
`conditional directive: comparison requires integer operands` — which has not
been characterised. **Probing was bounded deliberately**: past wall 3 I would be
editing the vendored source to keep going, and a wall map built on a source
nobody else has is worth less than three walls anybody can reproduce.

### What this ticket needs next

The dialect gap is smaller than the ticket assumed and it is concentrated:
**land the cast-transparency refactor and re-probe.** That is one change, it
clears two of three walls here, and it closes four tickets elsewhere. Vendoring
and the smoke test are downstream of that, not of a long tail of small gaps.


---

## 2026-09-02 (frankH) — wall 2 is down; wall 3 is a different arm and is the only one left

[[bug-p-a-cast-to-a-string-alias-silently-drops-a-following-index]] is fixed
(`9339d6661`). Verified on the exact shape this file uses rather than on the
ticket's abstraction of it:

```pascal
type tbtwidestring = WideString;
     PRec = ^TRec; TRec = record twidestring: tbtwidestring; end;
c := tbtwidestring(p^.twidestring)[1];      { was: expected ')' before '[' }
TakeW(tbtwidestring(p^.twidestring)[2]);    { was: expected comma or close paren }
```

Both compile and run and answer what fpc 3.2.2 answers. The pinned compiler
refuses both. That is `uPSCompiler.pas:1930` and the 13 occurrences of the shape
in that one file.

**Wall 3 is NOT the same bug and must not be assumed to have gone with it.**
`SetLength(tbtstring(p^.tstring), 8)` still answers *"SetLength expects a string
variable in IR codegen"* — measured today, after the fix. It is a different arm:
the `specialId = 101` lowering requires an `IR_LEA` target and a cast node is
not one, so this is the SetLength lvalue path rather than the postfix tail. The
minimal repro is the three lines above with the string field. Whoever takes it
should file or fix it in Track A/P and link it here; that is the residual
question this note is naming an owner for.

**Still not vendored, still no clone in the tree** — the numbers above come from
minimal repros of the shapes the 2026-09-01 attempt recorded, not from a fresh
build of the upstream file. Re-running the real attempt is the next step and it
needs the clone back.
