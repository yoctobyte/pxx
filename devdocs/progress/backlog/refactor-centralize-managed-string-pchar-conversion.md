---
summary: "Populate pointer-element-type metadata consistently (additive, fallback-preserving) — kill the recurring silent PChar/WideChar-conversion class at its source. SLICE 1 LANDED 2026-08-21 (decl-side population + the AN_VIRTUAL_CALL/AN_INTF_CALL reader gap); slices 2-3 (node-side storage, WideChar) remain"
type: refactor
prio: 45

---

# Populate pointer-element metadata consistently — the low-risk fix for the conversion class

- **Type:** refactor / data-completeness (Track A — `parser.inc` registration + node
  creation, `ir.inc` predicates). **Additive and fallback-preserving — NOT a big-bang
  rewrite.**
- **Status:** backlog — slice 1 done (2026-08-21), slices 2-3 open
- **Opened:** 2026-07-17, from a user observation ("we keep special-casing AnsiString,
  keep finding issues"). **Re-scoped 2026-07-18** after the user correctly pointed out the
  sane, low-risk shape: *just store the pointer type; C already does it.*

## The observation, and the corrected diagnosis

The recurring PChar/WideChar→string bugs are **one root**, and it is NOT "shape
enumeration is inherently wrong" — it is **"the element-type metadata is not populated in
every creation path."**

- The reader predicates (`IsNodePChar`, `NodeIsWideCharVal`) key on stored data — e.g.
  `ProcRetPtrElemTk[procIdx]` (a proc's return pointer-element type). That field already
  exists.
- The bugs were **registration paths that forgot to set it**: the external-directive path
  and the `$proctype` signature path each re-implemented registration and dropped the
  return-element fields, so the predicate read `tyUnknown` and skipped the conversion →
  silent garbage / segfault.

C proves the pattern is fine: `cparser.inc` has the *same* shape-walk
(`CNodePtrElemRec`), but at node creation (`cparser.inc:374`) it **computes once and
STORES** the element type on the node (`ASTSOffset` side-channel), so downstream reads are
a clean lookup. Mirror that.

## Instances (all the SAME pattern; the point-fixes are slices of this)

- [[bug-pascal-ansistring-cast-of-cdecl-call-result]] — external decl dropped
  `ProcRetPtrElemTk` (FIXED, `33f0d555`).
- [[bug-pascal-ansistring-cast-of-fnptr-call-result]] — `$proctype` sig dropped it +
  `IsNodePChar` missed `AN_CALL_IND` (FIXED, `9118a760`).
- [[bug-pascal-widechar-var-to-string-segfault]] / [[bug-pascal-widechar-var-to-string-other-contexts]]
  — `NodeIsWideCharVal` cast-only, missed the tyUInt16 var shape (assign + concat FIXED,
  `19fbf64a`/`6ea2e6ff`; arg residual open).
- The copy-pasted conversion block → one `WrapPCharToString` builder (`7e4bebc0`).
- **Not-yet-fixed dropped-field sites:** `parser.inc` `18447`/`19128`/`19649` — method-decl
  registrations that set `BodyAddr` + params but never `ProcRetPtrElemTk`. Harmless when a
  method has a body (the impl re-registers via the normal path), but a decl-only PChar
  method (abstract/interface/virtual-via-base) would mis-lower `AnsiString(ref.Method())`.

## Status after the reachable-instance audit (2026-07-18)

**The reachable instances are all FIXED** (the 5 point-fixes above were the slices).
Verified: instance-method AND class-method PChar-result casts (`AnsiString(o.GetP())`,
`AnsiString(TObj.GetPC())`) work — a method **with a body** resolves to the impl's
procIdx, which the normal registration path populates. So the 3 method-decl sites
(`18447`/`19128`/`19649`) are **defensive-only and NOT reachable by a normal call** — no
failing test is constructible. Deliberately **not** patched: adding metadata there would
be self-host-identical with no test, and would set a shared field from a possibly-stale
`LastTypePointerElemTk` that cannot be verified — which violates the "added data must be
correct" rule. Leave them until a real reachable case appears.

Net: **do-with-a-test-when-needed.** This ticket is now forward insurance + documentation
of the pattern, not a list of open bugs. The bleeding is closed.

## The plan — additive, fallback-preserving, incremental (LOW RISK)

The whole reason this is safe: **add a stored fast-path, keep the old shape-walk as a
fallback.** A reader that consults stored metadata first and falls back to the existing
enumeration can only ever *add* recognitions (fix a missed shape) — never remove one. It
is impossible to regress by construction.

1. **Finish the proc side (first slice, do now).** Set `ProcRetPtrElemTk` (+ the other
   return-element fields) at the 3 method-decl registration sites so *every* proc
   registration records it — matching the external/`$proctype` fixes already landed.
   Purely additive; self-host byte-identical unless it fixes a real case.
2. **Node side (later).** Store the pointer-element type on pointer-typed nodes at
   creation (C's store-on-node pattern); have `IsNodePChar` read the stored value first,
   fall back to the shape-walk if unset. Populate creation sites incrementally.
3. **Fold WideChar in.** Same treatment (WideChar==tyUInt16 has no marker; the safe
   contexts are already handled — see [[project_string_conversion_shape_blindspot_pattern]]).

Each step: self-host byte-identical + a targeted regression + a fuzz pass. No step is a
sweep of all 688 `tyString` branches — that count is just the *evidence* of the sprawl,
not a to-do list.

## Why not just keep point-fixing?

You can, and it's safe — each new shape found by fuzzing gets a one-line populate. This
ticket is the *systematic* version: audit the creation sites once so future shapes are
covered as the data is populated, instead of waiting for a fuzzer to draw blood on each.
Do it at the pace that suits; the bleeding is already stopped.

## Acceptance

- Every proc-registration path sets `ProcRetPtrElemTk` (grep audit); a decl-only PChar
  method cast works.
- `IsNodePChar` prefers stored metadata with the shape-walk as fallback (additive).
- The known instances stay fixed; a fuzz pass finds no new PChar/WideChar-conversion
  divergence.
- Gate: `make test` + self-host byte-identical per slice.

## Explicitly NOT

- **Not** a big-bang rewrite of the conversion sites or the 688 `tyString` branches.
- **Not** removing the shape-enumeration walks — they stay as the fallback.
- **Not** reworking the managed-string runtime/ABI — this is about *where the compiler
  records/reads the pointer element type*, nothing about how strings are represented.

## Slice 1 landed 2026-08-21 — and the audit's "not reachable" was wrong

The 2026-07-18 audit closed this ticket's first slice as *"defensive-only and NOT
reachable by a normal call — no failing test is constructible"*, on the reasoning
that a method with a BODY re-registers through the normal path. That reasoning is
right and the conclusion did not follow: it covers every method **that has an
implementation**, and the two shapes whose call resolves to the DECL and never to
an implementation — an **abstract** method reached through the base class, and an
**interface** method reached through the interface — have none to fall back on.

Constructed in one try, and it is a silent wrong VALUE, not a crash:

```pascal
TBase = class function GetP: PChar; virtual; abstract; end;
IGet  = interface function GetP: PChar; end;
...
s := AnsiString(b.GetP);    { FPC: 'abcde'   pxx: '' }
s := AnsiString(g.GetP);    { FPC: 'abcde'   pxx: '' }
```

**Both halves were needed, which is the part worth recording.** Populating the
metadata at the three decl sites changed nothing on its own, because the READER
was shape-blind in the same way the ticket describes:

1. `pasparser_decl.inc` — the record-method, interface-method and class-method
   decl registrations now capture `LastTypePointerElem*` right after the return
   type is parsed (same place `mRetRecId` is captured) and store
   `ProcRetPtrElemTk/Rec`. This is the "finish the proc side" slice, verbatim.
2. `ir.inc` — `IsNodePChar` enumerated `AN_CALL` and `AN_CALL_IND` only. All FOUR
   call node kinds carry a `Procs[]` index in `IVal` (`AN_VIRTUAL_CALL` keeps the
   slot in `ASTRight`, `AN_INTF_CALL` the IMT slot in `ASTSOffset`), so the
   virtual and interface shapes now read the same way.

**A second bug fell out of the same enumeration**, and it is NOT interface- or
PChar-specific: `IRPointerStride`'s call arm read the element KIND and never the
element's RECORD id, so for `function P: PRec` the tail computed
`RecSize(REC_NONE)` = the pointer size. `P2 - P0` over a 24-byte record answered
**6 instead of 2**, and `P0 + 2` landed inside element 0 — on plain functions as
much as virtual ones, on `pinned` and on HEAD. Every other arm of that function
sets the (kind, rec) pair together; this one set half. Fixed here rather than
filed, because it is the same dropped-field pattern in the same predicate family
and the test was already written.

`test/test_pchar_result_decl_only_method.pas`: **9 / 9**, identical to FPC 3.2.2
on the same source, natively and under qemu on aarch64 / arm32 / i386 / riscv32.
`pinned` scores **1 / 9**. Gate: `make compiler/pascal26` (fixedpoint) +
`tools/gate.sh quick` GREEN.

**Still open, unchanged**: slice 2 (store the pointer-element type on pointer
NODES at creation, C's pattern, shape-walk as fallback) and slice 3 (fold
WideChar in). The ticket stays open for those; this closes slice 1 and the
reader-enumeration gap it depended on.

## Slice 2's first real instalment, 2026-08-21 — found by a 84-shape differential

The ticket's own acceptance line asks for "a fuzz pass finds no new
PChar/WideChar-conversion divergence". Ran the equivalent, deliberately as a
CROSS PRODUCT rather than a list: 12 PChar SOURCES (plain function, called
function, record field, array element, local var, pointer arithmetic, proc-typed
value, class method, instance method, virtual, abstract-through-base,
interface-through-interface) × 7 CONTEXTS (`AnsiString()` cast, assign, concat,
`WriteLn`, a `const s: AnsiString` argument, `Length`, `=`), each a program of
its own, each diffed against fpc 3.2.2. **18 of the 84 diverged.** All 18 are
now identical to FPC, from two fixes.

**1. `+` had no PChar conversion at all — and was wrong in two unrelated ways.**
Which one you got depended on the OTHER operand, which is why it never looked
like one bug:

| expression | pxx before | FPC |
| --- | --- | --- |
| `'xy' + p` | `xy?` — one garbage byte | `xyabcde` |
| `'x' + p` | `` (empty) | `xabcde` |
| `p + 'tail'` | `?tail` | `abcdetail` |
| `c + p`, `p + c` (char VAR) | `` (empty) | `Qabcde` / `abcdeQ` |
| `p + 1` | `bcde` | `bcde` ✓ |

With a multi-char literal the node typed as a string concat and the concat
codegen read the POINTER as string data. With a ONE-char literal — `tyChar`, an
ordinal — the `ordinal + pointer` arm claimed the expression first and it became
pointer arithmetic: the pointer moved 120 bytes and the result was ''. Same
expression shape, two different silent wrong answers, no diagnostic in either.

Fixed by normalising the OPERAND in `pasparser_expr.inc`, immediately next to
the WideChar wrap that was already doing exactly this — not by adding a third
arm to the typing chain below it. Downstream then sees two string operands and
needs to know nothing about PChar. The rule matches FPC and was measured, not
assumed: a char/string operand means concat, an integer operand stays pointer
arithmetic. Excluded in C mode, where `p + 'x'` genuinely IS arithmetic.

**2. An array-of-PChar ELEMENT was an unrecognised SHAPE.** `IsNodePChar`
enumerated cast / ident / field / call / binop and had no `AN_INDEX` arm, so
`arr[0]` was wrong in EVERY context at once — cast, assign, concat and `=`
produced '', `Length` answered 0, `WriteLn` printed the pointer as a decimal
number, and `Show(arr[0])` was refused outright with *"argument types:
(Pointer)"*. That spread is the tell: one broken context is a context bug, seven
broken contexts is an unrecognised shape.

Note what was NOT wrong: `AllocArray` and `AllocDynArray` both already record
the element pointee in `Syms[].PtrElemTk`. **The metadata was there and only the
reader was missing** — the mirror image of slice 1, where the reader was right
and the metadata was missing, and together they are the argument for this
ticket's whole framing.

`test/test_pchar_concat_and_array_element.pas`, 18 lines, byte-identical to fpc
3.2.2 on the same source. `pinned` does not compile it (the `const AnsiString`
argument is refused). Gate: `make compiler/pascal26` fixedpoint +
`tools/gate.sh quick` GREEN.

**Still open**: the node-side storage that is slice 2 proper (this instalment
extended the reader instead), slice 3 (WideChar), and `pp[i]` where `pp: PPChar`
— an element of a POINTER to pointers, which the new arm deliberately does not
cover because `IsArray` is false there and no differential row exercised it.

## Log
- 2026-08-21 — slice 1 landed. Note for whoever reads the 2026-07-18 audit next:
  "no failing test is constructible" was a claim about a search that stopped at
  methods with bodies. When a ticket says a case is unreachable, the cheap check
  is to try to reach it.
