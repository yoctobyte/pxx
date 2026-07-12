---
prio: 45  # auto
---

# RemObjects Pascal Script — compile under pxx (embeddable scripting)

- **Type:** feature / investigation (real-world compat target + feature)
- **Track:** P (Pascal frontend) — rung of [[feature-pascal-corpus-expansion]]
- **Status:** working
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
