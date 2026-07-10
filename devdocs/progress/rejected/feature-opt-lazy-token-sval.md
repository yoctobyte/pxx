---
prio: 55
---

# Lazy / conditional CurTok.SVal materialization — cut per-token string allocation

- **Type:** feature (compiler perf — allocation churn) — **Track O** (file-ownership Track A; shared `lexer.inc`)
- **Status:** working
- **Opened:** 2026-07-10 (pin-time optimization campaign, profiling session)
- **Umbrella:** [[feature-optimization-levels]] — the "allocate less" lever the
  prior [[perf-compiler-hotspots-algorithmic]] ticket flagged (string churn is
  codegen-/count-bound, not free-list-bound).

## The cost

FPC-symboled profile of the self-compile (build `fpc -g -o... compiler.pas`,
`perf record`, post the label-clear fixes 984df81f/50549a81) is dominated by
managed-string + heap churn, ~30% aggregate:

```
NewAnsiString 8.5%  ansistr_concat 6.9%  ansistr_setlength 6.7%
SysGetMem_Fixed 4.5%  SysFreeMem_Fixed 3.7%  AppendChar 3.4%
ansistr_decr_ref 2.8%  Move 2.4%  ... (SetCodePage/StringCodePage ~3% is
FPC-RTL-only overhead the pxx binary lacks)
```

`Next` (lexer.inc) materialises a fresh AnsiString into `CurTok.SVal` for
**every** token the parser consumes (one `NewAnsiString` + heap alloc + later
free each). Token-string materialisation was already made O(n) instead of
O(n^2) per token in 0058a31e (SetLength+fill vs per-char AppendChar), but the
per-token ALLOCATION remains.

## The idea

Roughly half of Pascal tokens are operators / punctuation / keywords whose
meaning is fully in `CurTok.Kind` (tkBegin, tkPlus, tkSemicolon, …) — their
`SVal` is never read. Populate `SVal` only for the text-bearing kinds
(tkIdent, tkString, tkChar, and the number kinds if any code reads their text);
leave it empty (no alloc) otherwise. That removes a large fraction of the
NewAnsiString/SysGetMem/SysFreeMem traffic at the top of the profile.

## Why it is NOT a quick fix (the audit)

`CurTok.SVal` is read ~292× in parser.inc alone plus every other frontend that
shares the lexer. Skipping materialisation for a kind that some path DOES read =
silent miscompile. It must be gated on a proven-complete set of "SVal-bearing"
kinds:
- Known reads today are guarded by `Kind = tkIdent` (e.g. the soft-keyword
  `CaseEqual(CurTok.SVal, 'as')` at parser.inc ~1281) or occur in
  identifier/string/char-literal contexts — but this must be VERIFIED
  exhaustively across parser.inc, cparser, the Nil-Python/Rust/Zig parsers, and
  the asm frontends, not assumed.
- Determine the exact kind set empirically: instrument `Next` to record, per
  token Kind, whether SVal is subsequently read before the next `Next`; run the
  full test corpus + self-compile; the union is the must-materialise set.

## Gate

Self-host byte-identical at every opt level (the emitted compiler must not
change), full `make test`, `make test-opt`, and cross-target output-equality on
supported programs (i386/aarch64/arm32; riscv32 is a partial target — errors on
unsupported nodes, exclude). Land only with T up (async matrix) OR after running
the full cross-bootstrap locally, because it touches the shared `Next` on the
hot path of every frontend.

## Expected win

Upper bound is the NewAnsiString + matching getmem/freemem share attributable to
non-text tokens — plausibly 5-10% of self-compile if ~half of tokens stop
allocating. Measure before believing it (measured-not-speculative; several
optimization candidates this campaign were rejected at 0-fire / OoO-hidden).

## Related
- [[project_per_body_full_array_clear_waste]] — the label-clear wins from the
  same profiling session (1.30x, safe/output-neutral); this one is the riskier,
  behaviour-changing follow-up.
- [[feature-optimization-levels]], [[perf-compiler-hotspots-algorithmic]].

## RESOLUTION 2026-07-11: REJECTED — measured 0 win on the shipping (frozen) binary

Prototyped in full (gated pool storage in `LexAll`/`LexAppend` to a proven
SVal-bearing kind set + keep-everything inside inline `asm..end` regions +
monotone SOffset preserved for the decl-order gate). Result on the default
frozen-string self-host binary:

- baseline `pascal26` self-compile: **3.406 s ± 0.038** (hyperfine, 8 runs)
- patched stage1 self-compile: **3.455 s ± 0.049** — i.e. **no win, ~1% noise**

Root cause of the non-transfer: the motivating profile was of the **FPC-built**
binary, whose RTL uses heap-allocated AnsiStrings (NewAnsiString/getmem/freemem
per token). The self-host/pinned binary is built with **frozen inline strings**
(PXX_MANAGED_STRING is never defined by default — `-u` only strips it for the
explicit frozen bootstrap), so `CurTok.SVal` materialisation is a length store +
short memcpy, no allocator traffic at all. The 30% alloc-churn share simply does
not exist in the shipping binary. Managed-build timing could not be taken: the
checked-in `pascal26-managed` seed is stale (errors "too many array constant
elements" on HEAD source even unpatched — ordinary backward-compat reseed
situation, not a regression).

### Salvage: the SVal-read audit (useful for any future retry)

Exhaustive audit of all ~292 `CurTok.SVal` reads in parser.inc: keyword-kind
SVal is LOAD-BEARING at these semantic sites, so any lazy scheme must keep text
for this exact kind set:

- **Type keywords** `tkInteger_T/tkLongWord_T/tkChar_T/tkBoolean_T/tkString_T`
  (+Real/Single/Double/Extended): several type names collapse per kind
  (byte/integer → tkInteger_T; longword/cardinal → tkLongWord_T) and the parser
  disambiguates on source text — casts (parser.inc ~4834/4844, 9832, 7212
  const-eval `ConstIntCastWidth`), `SizeOf` (~5132), `var x: Byte` (~11373),
  generic specialization args (~1023, ~1272).
- **`tkRead/tkwrite/tkReadln/tkwriteln/tkArgCount/tkArgStr/tkSys*`**: admitted
  as member/decl names by `IsMemberNameTok`/`IsDeclNameTok` — method/param
  names spelled `Read`/`Write`/`ParamStr` etc. read SVal (~9863, 9888, 13097,
  13124, 13830, 14794, 14832, 12841).
- **Inline `asm..end`**: operand parser reads SVal of keyword tokens
  (and/or/div/dec mnemonics; `byte` → tkInteger_T size keyword) — asmenc.inc
  documented landmine.
- **`program <keyword-name>`** (~17639): DbgProgName may read keyword SVal
  (-g debug name only).
- Everything else (structural keywords) is kind-only — droppable in principle.
- Landmine for any retry: token `SOffset` is a **monotone source-order key**
  (SymDeclTok decl-order gate) — skipped tokens must still get
  `SOffset := TokCharLen`, never 0.

Structural-keyword pool text is ~droppable, but the payoff only exists in
FPC-hosted/managed builds, which are bootstrap/debug vehicles, not the perf
path. Not worth the frontend-shared risk. Rejected per the campaign's
measured-not-speculative rule.
