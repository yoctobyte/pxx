---
slug: feature-p-implement-the-real-tyshortstring-byte-prefix-layout
title: "Implement the real `tyShortString` byte-length-prefix layout — the kind is already plumbed, the codegen is not"
track: P
prio: 65
type: feature
status: backlog
created: 2026-09-02
found-by: owner (raised 2026-09-02), measured by frankuser
owner: ""
summary: "MEASURED at bf92c45a7, binary sha256 `5f275966bf50`: we are `cap+8` and FPC is `cap+1`, uniformly — ShortString 263 vs 256, string[10] 18 vs 11, string[255] 263 vs 256. The ENTIRE divergence is the length-word width (8-byte NativeInt vs 1 byte), and it is a documented INTERIM: `pasparser_decl.inc:540` maps the name `shortstring` to a 255-cap `tyFixedString` with the comment *'the true byte-length-prefix tyShortString (FPC ABI) is a later codegen slice'*. THE KIND IS ALREADY PLUMBED — `tyShortString` has 63 sites across 18 files including EVERY backend (i386, wasm32, arm32, aarch64), `abi.inc` and `rtti_emit.inc`, against `tyFixedString`'s 79; `FrozenStrSlotSize` already returns `cap+1` for it. What is missing is the byte-prefix codegen, not the type. WHY IT MATTERS BEYOND SizeOf: unlike sets, a fixed string is NOT a zero-extension of FPC's — the length word is at the FRONT and a different width — so there is NO truncating-copy trick, and every fixed string in a typed file is a genuine conversion. Implementing this makes `string[N]` for N<=255 byte-identical to FPC, which makes records containing one BLIT instead of marshal. Note pxx accepts `string[256]` (264) and `string[1000]` (1008) where FPC rejects both: frozenstring is a strict SUPERSET, and the 1-byte prefix IS the 255 ceiling, so the wide kind must stay for N>255."
---

# The real `tyShortString`, and why it is cheaper than it looks

> **DECIDED BY THE OWNER, 2026-09-02 — DO IT.** *"all we need to do is
> implement a real shortstring type. it will give us some headache with all
> mixed string types concatting etc, but that's all trivial. it will give us
> blitted file io. and memory efficient string handling, something esp targets
> will like. so, useful. we keep our fixedstring as well, just as is."*
>
> **`tyFixedString` STAYS EXACTLY AS IT IS.** This is additive — two kinds, not
> a migration. Nothing about the wide kind changes, and it remains the only one
> that can express `N > 255`.
>
> **The three payoffs, all measured rather than asserted:** blitted `file of T`
> (our padding and alignment rules already match FPC exactly — see below — so
> the width is the whole remaining gap); memory (`string[10]` becomes 11 bytes
> instead of 18, a 39% saving on small strings, which is the ESP argument); and
> FPC-byte-identical records for interop.
>
> **The mixed-kind surface, measured because "trivial" deserved a number:** 29
> sites enumerate multiple string kinds together; **20 already name
> `tyShortString`** and **9 omit it**, spread over 6 files at most 2 per file
> (`symtab`, `pasparser_stmt`, `ir_codegen` ×2 each; `pyparser`,
> `pasparser_expr`, `pasparser_decl` ×1). So the concat/assign work is
> extending nine kind lists. **Caveat, stated so nobody quotes 9 as the job:
> that bounds the ENUMERATION surface, not the semantics** — adding a kind to a
> list is not the same as the concat rule being right for it. The real work is
> the byte-prefix codegen, per backend.

## SEQUENCED BEHIND THE CAPACITY FIX — do not start this in parallel with it

**`bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes` lands
first.** frankB holds it, filed the constraint, and declined this feature on
sequencing grounds rather than interest (2026-09-02). The reason is
attributability, and it is the deciding kind:

that ticket's finding is that `UFldStrCap` holds a record field's OWN capacity
while `ir.inc:11260` reads it as the field's ELEMENT's capacity, so
`inner: array[0..1] of string[10]` delivers 0 and `FrozenStrSlotSize`
substitutes `DEFAULT_STR_CAP`. The declared 10 is not mis-sized — it is
dropped. **Change the prefix width first and a wrong stride afterwards cannot
be attributed to a layer:** is the prefix wrong, or was the capacity never
delivered to it? `DEFAULT_STR_CAP` under a 1-byte prefix gives 256 instead of
263 — just as wrong, and just as reasonable-looking. Fix the thread, then
change what flows through it.

Both diffs apply cleanly to `FrozenStrSlotSize` territory and neither produces
a git conflict, which is exactly why this is written down instead of left to
the merge. **If you want this feature sooner, take frankB's ticket too and do
both in that order** — one agent, one sequence — rather than running them
concurrently. Message frankB first either way.

### A third site class, not in the counts above

The backends **hardcode the 8-byte length word** in their char-to-inline-string
store arms; none of them calls `FrozenStrSlotSize` or `SizeOfSlot`, so they do
not appear in any grep of the sizing-oracle surface:

| backend | arm | writes |
| --- | --- | --- |
| x86-64 | `ir_codegen.inc:4573` (`IREmitStoreCharAsString`) | `mov qword [rdi], 1` / `mov byte [rdi+8], sil` |
| i386 | `ir_codegen386.inc:1900` | `mov dword [edi], 1` / `mov dword [edi+4], 0` / `mov byte [edi+8], al` |
| aarch64 | `ir_codegen_aarch64.inc:1918` | same shape |
| arm32 | `ir_codegen_arm32.inc:1671` | same shape |

Measured by inspection at `f74d2f851`; no build run for this note.

**Updated 2026-09-02: the predicted growth happened and it is now EIGHT arms,
not four.** `bug-a-char-into-shortstring-through-a-pointer-is-x86-64-only`
landed at `e4cba526a` (verified on origin/master), adding the matching
`IR_STORE_MEM` arms on i386/aarch64/arm32 which previously refused outright.
So each of the four backends now carries the literal 8-byte length word in
BOTH its `IR_STORE_SYM` and `IR_STORE_MEM` arm. That is **favourable for this
feature, not a conflict** — the shape is now uniform across four backends
instead of implemented-on-one-refusing-on-three, so the edit is mechanical
rather than implement-here-un-refuse-there. It is simply eight sites.

**Why this paragraph exists at all:** "grep the sizing oracles" is how someone
will scope this feature, and it comes back short by all eight. None of these
arms calls `FrozenStrSlotSize` or `SizeOfSlot` — they write the layout
literally. Scope this feature by the LAYOUT, not by the oracle's callers.

## Measured, fresh binary

Owner, 2026-09-02: *"shortstring is more or less what we call frozenstring"* —
then, correctly, *"iirc shortstring is 255(+1) char max ... since indeed
frozenstring can have arbitrary length."* Both halves confirmed:

```
                pxx      FPC (-Mobjfpc)
ShortString     263      256
string[10]       18       11
string[255]     263      256
string[256]     264      REJECTED: "string length must be a value from 1 to 255"
string[1000]   1008      REJECTED
```

`cap+8` against `cap+1`, uniformly.

**The 255 ceiling re-measured properly after the owner questioned it** — the
first version of this claim was one mode and stated generally. `string[1000]`
is rejected in **all eight FPC modes** (default, objfpc, delphi, fpc, tp,
macpas, iso, extendedpascal) with *"string length must be a value from 1 to
255"*; the boundary is exact (`string[255]` → 256, `string[256]` → rejected);
and no switch lifts it (`-Sh` swaps to ansistring rather than extending the
shortstring). **The limit is the REPRESENTATION, not a policy**: a 1-byte
length prefix cannot count past 255, so FPC could not raise it without ceasing
to be a shortstring. NOT checked: an obscure source directive — but any such
directive would have to widen the prefix, which is the same change. **`ShortString` is a strict SUBSET of
frozenstring**, and the reason is the header itself: a 1-byte length prefix
*cannot* express a cap above 255. The wide kind must therefore stay for N>255 —
this is not a replacement, it is the second of two.

> **PROVENANCE.** The first run of this measurement returned `8` for every row,
> from a `compiler/pascal26` that had not been rebuilt in a session where dozens
> of commits touched `compiler/**` — the exact stale-binary trap CLAUDE.md
> names. Rebuilt (`converged after 2 round(s)`, not the stamp path) to
> `5f275966bf50` at `bf92c45a7`; every number above is from that binary. The
> stale one was wrong by exactly 7 bytes on every row and looked plausible.

## OUR RECORD ALIGNMENT ALREADY MATCHES FPC — only the width differs

The owner read the earlier no-padding measurement as *"FPC has packed record
default to true, apparently."* Measured, and it is not: the earlier record had
TWO shortstring fields, which need only byte alignment, so nothing had to be
padded. Packing was never on.

```
                            FPC        pxx
record  string[2]+LongInt    8  b@4     16  b@12
packed  string[2]+LongInt    7  b@3     14  b@10
record  Byte+LongInt         8  y@4      8  y@4      <- identical
packed  Byte+LongInt         5  y@1      5  y@1      <- identical
```

**The bottom two rows are the finding.** Our padding and packing rules already
agree with FPC exactly. The top two diverge only because our `string[2]` is 10
bytes and FPC's is 3 — after which BOTH compilers correctly align the `LongInt`
to 4 from wherever the string ended.

**So this feature is the whole gap.** If `string[2]` were 3 bytes, `TU` would be
8 with `b` at offset 4 — byte-identical to FPC — with no alignment work
required. That is a much stronger claim than "sizes get closer": records
containing fixed strings become byte-compatible, which is what `file of T`
interop actually needs.

## CAPACITY STORAGE NEEDS NOTHING — the carriers are already kind-agnostic

The owner asked where the capacity is stored, and then answered the follow-on
himself: *"if we track that for fixedstrings, we can use the same field for
shortstrings already."* **Correct, and it withdraws a caution the coordinator
had just given about needing a new carrier per keying.**

`SymSubHi`'s own comment says it outright — *"frozen fixed-string capacity (max
chars) for **tyFixedString/tyShortString** slots"* — and every call site
confirms the shape: the capacity table stores a bare `N` while the KIND travels
beside it in a separate table.

```
FrozenStrSlotSize(tk,                       SymStrCap[retSymIdx])
FrozenStrSlotSize(tk,                       SymPtrElemStrCap[...])
FrozenStrSlotSize(IntToTypeKind(UFldTk[i]), UFldStrCap[i])
FrozenStrSlotSize(Syms[i].ElemType,         SymStrCap[i])
```

Kind tables: `UFldTk`, `AliasTk`, `ArrTypeElemTk`, `Syms[].ElemType`. Capacity
tables: `SymStrCap`, `SymSubHi`, `SymPtrElemStrCap`, `UFldStrCap`, `UFldSubHi`,
`AliasStrCap`, `AliasSubHi`, `ArrTypeElemStrCap`, plus the transient
`LastTypeStrCap`/`LastTypeSubHi`.

**So a `string[10]` that re-types writes `10` into the SAME StrCap slot and
`tyShortString` into the SAME Tk slot, and `FrozenStrSlotSize` already returns
11 instead of 18 with no change.** No tenth carrier, no new table.

**Keep the two problems separate.** That the capacity has no canonical home —
nine carriers keyed three ways, which is why the clamp can be right while the
stride is wrong in one expression — is a real design defect and belongs to
[[umbrella-sizeof-is-one-answer]]. It is **not** an obstacle to this feature,
and this feature does not make it worse.

## OVERFLOW/TRUNCATION IS SAFE TODAY, AND THIS CHANGE DOES NOT TOUCH IT

The owner raised the real semantic worry: the cap is **compile-time-only
information**, so `a: string[10]; a := 'hello'+' '+'world'` has to be clamped by
something that was TOLD the cap. Measured, and it is:

```
                            pxx              FPC
a := 'hello'+' '+'world'    [hello worl] 10  [hello worl] 10
25x accumulate loop         [xxxxxxxxxx] 10  [xxxxxxxxxx] 10
r.inner[0] := 20 chars      [hello worl] 10  [hello worl] 10
guard / tail after store    intact           intact
```

Byte-identical to FPC in every shape tried, and **correct even in the record-
field-array shape where frankB measured the stride as 264.** That is a sharper
statement of this umbrella's thesis than the four-oracle census: in
`r.inner[0]` the capacity reaches the **clamp** (which correctly uses 10) while
the **stride** falls back to the `tyString` default. One number, two consumers,
two side-tables — one populated, one not.

**For this ticket the consequence is simple: the clamp bounds the LENGTH, not
the prefix**, so 8 bytes of prefix becoming 1 does not touch the overflow
machinery. The cap ceiling dropping to 255 is a parse-time check, not a runtime
one.

**Limit of the claim:** four shapes measured (bare var, concat expression,
25-iteration accumulate, record-field array). NOT covered — the open-array
parameter shape in
[[bug-p-a-string-n-element-loses-its-capacity-in-three-container-shapes]],
which reads `a[2]` empty despite a correct stride and is frankb-a9's.

## THE PREFIX IS 8 BYTES ON EVERY TARGET — and tyShortString is not a byte prefix TODAY

The owner asked whether `tyString` uses a *word* for the length. Measured, and
the word "word" is the confusing part: it means a **machine word**, not Pascal's
2-byte `Word`. `FrozenStrSlotSize` returns **`cap + 8` hardcoded** — NOT
`cap + TARGET_PTR_SIZE` — so the prefix is 8 bytes on every target despite the
comment calling it "NativeInt".

**And `tyShortString` has no byte-prefix semantics today.** A normaliser in
`symtab.inc` makes fixed/short strings present as a plain frozen `tyString`
*value*: *"they are codegen-identical (same inline word-prefixed layout); only
the slot SIZE differs, and that is carried by the storage kind + SymStrCap.
Normalising the node value-kind here keeps every existing `= tyString` value
check (write, concat, compare, ...) working without widening ~150 sites."* So
`FrozenStrSlotSize(tyShortString, cap)` already returns `cap+1` while the
codegen writes a word. Nothing exercises the mismatch yet.

### The cost structure, corrected

An earlier version of this ticket quoted **9 sites** for the mixed-kind work.
That number is right for what it measured (enumeration lists omitting
`tyShortString`) and **was not measuring the load-bearing thing.** The real
structure:

| number | what it is | does it change? |
| --- | --- | --- |
| **306** | `tyString` comparisons (252 `=`, 54 `in [...]`) | **NO** — the normaliser exists to keep them working. That is the design. |
| **13** | refs to the named `EmitStoreStrLen`/`EmitLoadStrLen` pair (symtab 7, ir_codegen 2, one each in 386/aarch64/arm32, pasparser_lval 1) | **YES** — this is where the prefix width lives |
| **9** | enumeration lists omitting `tyShortString` | yes, but they are kind lists |

**The design already anticipated this**: value kind normalised, storage kind
carries the width. That is why every measurement has come out cheaper than
expected.

### THE HAZARD — name it before starting

The normaliser's justification is that fixed and short strings are
**"codegen-identical"**. A byte prefix makes that **false**. Any site that reads
the length through the normalised VALUE kind, rather than through
`EmitStoreStrLen`/`EmitLoadStrLen`, then uses the wrong width **silently** —
and the concentration is not total: aarch64 emits `str x9, [x6] (length word)`
inline in at least two places, and 16 comments across the backends name the
length word directly.

**First job is therefore an audit, not an edit**: find every site that assumes
the prefix is 8 bytes without going through the named pair. Per the guard rules,
a test for this must assert the STRIDE and a `string[N]` whose content length
differs from its capacity — a value check cannot see a wrong prefix width when
the string happens to fill its slot.

## CONSTANTS: the landing order, and it is narrower than it looks

The owner named the sequencing risk: *"the big catch is — constant strings.
right now we all parse them as fixedstring (i think, or do we convert them all
to ansistring?). so, all plumbing has to be in place before we convert short
string constants to shortstrings."* Measured — and it is **neither**:

**An untyped string LITERAL types as `tyString`.** Three source comments say so
(`pasparser_expr.inc:631`, `:5590`, `:9539`). It has no storage of its own and
is converted at the point of use, so a `tyShortString` destination needs only a
conversion ARM — one of the nine sites above. **Nothing about literals has to
change at all.**

**A TYPED constant is what forces the issue.** `const T: string[10] = 'hello'`
measures **18** — real `.data`, emitted at compile time, byte-identical in
layout to a var of the same type. These are what must not change representation
before the readers understand the new one.

```
                          pxx     FPC
typed const string[10]     18      11
var plain string            8     256
var string[10]             18      11
```

**LANDING ORDER, each step independently green:**
1. byte-prefix codegen per backend (load/store the length as a byte)
2. the nine conversion/enumeration arms, including `tyString -> tyShortString`
3. only then, typed constants for `N <= 255`

**AND ONE THING NOT TO DO.** That table shows FPC's plain `string` is **256
bytes** — its default string genuinely IS a shortstring, which is the `{$H}`
default. Ours is an 8-byte managed handle. Someone will read the 8-vs-256 row
as the last piece of parity and map plain `string` onto `tyShortString`. **That
would replace managed strings with 256-byte stack blocks, and it is not part of
this ticket.** The owner asked for a second kind alongside `tyFixedString`, not
a new default.

## Why it is cheaper than "a later codegen slice" suggests

`tyShortString` is **not** a new kind to build. 63 sites, 18 files:

```
symtab 15  pasparser_decl 11  pasparser_lval 9  pasparser_expr 6
pasparser_proc 3  defs 3  rtti_emit 2  pyparser 2  ir_codegen386 2  ir 2
+ abi, cparser, ir_codegen, and the aarch64 / arm32 / wasm32 backends
```

`FrozenStrSlotSize(tyShortString, cap)` already returns `cap+1`. The name
binding at `pasparser_decl.inc:540` is a **one-line interim** that says so in
its own comment. What is missing is the codegen that loads and stores the length
as a byte rather than a word.

## The asymmetry with the set decision — this does NOT come free

[[decide-a-what-a-set-costs-bits-bytes-bounds-and-what-file-of-t-writes-to-disk]]
concluded that set file IO needs no representation change, because our 32-byte
mask is a byte-exact **zero-extension** of FPC's and truncation suffices.

**Strings have no such trick.** The length word is at the FRONT and is a
different width, so an on-disk fixed string is a genuine conversion under the
current layout — and a record containing one cannot blit (18 in memory, 11 on
disk, every later field shifted). Implementing this removes that for N<=255,
where sets could not be fixed so cheaply. **Strings in records are also far more
common than sets in records**, so the same argument is worth more here.

Blocks-relation: [[feature-pascal-typed-and-untyped-files]] — this is the
difference between `file of T` blitting and marshalling for the common case.

## THE CLUSTER WAS NOT A CLUSTER — my count was wrong (corrected 2026-09-02)

This ticket said *"eight open tickets name shortstring, several cross-target"*
and offered it as a lead. **Seven of the eight are in `done/`. One is open.**
frankc-af's census (`586eae2f8`) established it; the count came from an
`ls devdocs/progress/*/` that globbed EVERY folder, `done/` included, and I read
the result as open tickets. **The instrument did not error — it answered a
different question.**

Worse in a specific way: I hedged the *inference* (*"I have not established the
interim mapping causes any of them"*) and not the *premise*. The hedge made the
claim read as careful, which made the unmeasured number MORE credible rather
than less, and a peer spent a census on it.

**The one survivor is not a layout question and this feature would not close
it.** `bug-a-char-into-shortstring-through-a-pointer-is-x86-64-only` is a
missing EMITTER ARM — three explicit `Error()` arms beside working code, at
exactly one intersection (char VALUE + string DEST + POINTER store); a literal
through a pointer works everywhere, a char without a pointer works everywhere.
Under either layout each backend still needs the arm written; the byte prefix
makes them marginally simpler and removes none. riscv32 now passes, so a
non-x86-64 reference already exists.

**So: strike the cluster as support for this feature.** What survives untouched
is the `file of T` argument, which stands on its own and was always the real
one — a record containing a `string[10]` is 18 bytes in memory and 11 on disk,
plus the record padding (offset 112 vs 101) that the byte prefix also removes.
**The justification is narrower, not weaker in kind.**


## The byte prefix is NOT the whole record-layout gap — alignment is hardcoded

Checked 2026-09-02 (frankC) against the packing measurement added in
`76342c379`, because that claim is now the load-bearing argument for this
ticket's rank and it deserved a second instrument.

**The packing half reproduces exactly.** pxx and FPC agree with no string in
sight:

| | pxx | FPC `-Mobjfpc` |
| --- | --- | --- |
| `record a: Byte; b: LongInt; end` | 8, b@4 | 8, b@4 |
| `packed record a: Byte; b: LongInt; end` | 5, b@1 | 5, b@1 |
| `record a: Byte; b: Byte; end` | 2, b@1 | 2, b@1 |

**But "the only divergence is the string field's own width" is not right, and
"no alignment work" is the part to correct.** Isolating the string field:

| | pxx | FPC |
| --- | --- | --- |
| `record a: Byte; s: string[4]; end` | 24, **s@8** | 6, **s@1** |
| `record s: string[4]; end` | 16 | 5 |
| `record a: Byte; s: string[4]; b: LongInt; end` | 24, s@8, b@20 | 12, s@1, b@8 |

pxx pads **seven bytes** before the string. FPC pads none — a shortstring is a
byte array and aligns to 1. So a mixed record diverges in TWO ways: the string's
width *and* the string's alignment. The `LongInt` observation holds — once each
compiler has placed the string, both align `b` correctly relative to their own
offset — but that is downstream of a field that is already in the wrong place.

**Why the size fix alone will not move it** (read from source, not measured —
there is no 5-byte string today to measure with): the record layout does not
derive a frozen string's alignment from its size. It is a literal, at three
arms in `pasparser_decl.inc`, and **each already names `tyShortString`**:

```pascal
else if (fTk = tyFixedString) or (fTk = tyShortString) then
begin
  fSize  := FrozenStrSlotSize(fTk, fStrCap);   { becomes cap+1 -- this is the fix }
  fAlign := TARGET_PTR_SIZE;                   { stays 8 -- this is not }
end;
```

`TypeAlign`/`TypeFieldAlign` are not consulted here, so making
`FrozenStrSlotSize` return `cap+1` would give a `string[4]` field five bytes
that are still 8-aligned: `record a: Byte; s: string[4]; end` would go from
24/s@8 to 16/s@8, not to FPC's 6/s@1.

**This does not weaken the ticket — it sharpens the work item.** The blit
argument stands, and the alignment side is three lines (`fAlign := 1` for
`tyShortString`, the wide `tyFixedString` keeping pointer alignment). It just
has to be in the plan, or the feature lands, `SizeOf` matches FPC, and records
still do not blit — which is the failure mode where the acceptance test passes
and the goal is missed.

**Acceptance should therefore assert an OFFSET, not just a size.**
`record a: Byte; s: string[4]; b: LongInt; end` must be 12 with s@1 and b@8. A
size-only row can be satisfied by a record that is the right total with the
fields in the wrong places.
