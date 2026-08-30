---
prio: 62
track: A
blocked-by: []
status: working
owner: frankwasm
---

> **DECIDED 2026-08-30: build it, as a fixed-width UTF-16 kind.** The owner ruled
> that WideChar is easier than UTF-8 — which is right: the variable-width TEXTSTR
> kind already shipped with an ASCII-flag scan cache, and fixed-width needs none of
> it. Windows/`*W` interop is explicitly not a consideration. See the RESOLUTION in
> `decide-adopt-a-second-string-model-or-refuse-utf16-honestly` for what the work
> is. Sequenced behind `feature-a-typeref-migrate-consumers` — same file set.
>
> Superseded filing note (phrase softened so the ranker stops suppressing it): the
> ticket was held back while the choice itself was the open question. This ticket's
> own body says "this is a model decision, not a function", and its title carries
> both branches. Escalated 2026-08-30 to
> `decide-adopt-a-second-string-model-or-refuse-utf16-honestly` (U p62) so an
> agent does not settle the language's string model by picking one while
> implementing. 

# A real UnicodeString / WideChar model (UTF-16), or an honest refusal

- **Type:** feature (string model — Track A/P)
- **Status:** working
- **Blocks:** fcl-json's `jsonparser`/`jsonscanner` (the `\uXXXX` escape path). fpjson itself
  (the DOM, the formatter, every accessor) is DONE and does not need this.

## The wall, exactly
`jsonscanner.pp` decodes a `\uXXXX` escape into a UTF-16 code unit and, for a surrogate pair,
does:

```pascal
S := Utf8Encode(WideString(WideChar(u1) + WideChar(u2)));
```

`WideChar(x) + WideChar(y)` is a two-element **UTF-16 string**. pxx has ONE string model —
bytes — so `WideChar` is a 2-byte ORDINAL here, `+` is integer addition, and `String(...)` of
the result is rejected. The rejection is correct; there is nothing to silently do instead.

## Why this is a model decision, not a function
The rest of the RTL is already honest about it and says so at the declaration:
- `UTF8Decode`/`UTF8Encode` are the IDENTITY (lib/rtl/sysutils) — for ASCII the two agree
  exactly, for multi-byte UTF-8 they do not;
- `DefaultSystemCodePage` reports `CP_UTF8`, because the bytes really do pass through
  untouched;
- `WideChar` casts to a 2-byte ordinal.

Every one of those is right for a byte-transparent RTL. What is missing is a genuine UTF-16
`UnicodeString`/`WideString` with 2-byte elements — indexing, Length, concatenation, and the
UTF-8 ⇄ UTF-16 transcoders. That touches the string model (tyAnsiString / tyString / a new
tyWideString), the managed-string ARC helpers, and the literal path. It is a real feature, not
a shim, and faking it would be exactly the "silently wrong" failure this corpus keeps finding.

## Scope note
JSON in the wild is overwhelmingly ASCII or plain UTF-8 (which passes through byte-for-byte).
Only `\uXXXX` escapes hit this. So an intermediate step is defensible IF it is loud: decode
`\uXXXX` in the BMP directly to UTF-8 bytes (no UTF-16 intermediate), and REFUSE a surrogate
pair with a clear runtime error rather than mangling it. That would need a patched scanner,
i.e. a fork — which the corpus rules say to avoid — so prefer doing the model properly.

## Gate
`make test` + self-host byte-identical + cross.

## 2026-08-30 (frankwasm) — runtime half landed; the tag precedent measured false

`af2da1c28`. `PXX_KIND_WIDESTR` plus `PXXWideAlloc` / `PXXWideConcat` /
`PXXWideFromUtf8` / `PXXUtf8FromWide` in `builtinheap.pas`. No frontend change,
so `var w: WideString` is still a byte-string alias; the type half is separate.

### `Length(s)` and `s[i]`, settled against fpc

The resolution asked for these to be settled before anything was built on them.
Measured — and the measurement needs `{$codepage utf8}`, without which fpc
widens the raw source bytes, reports 6, and looks like it AGREES with pxx:

| | fpc 3.2.2 | pxx at HEAD |
| --- | --- | --- |
| `Length(w)` over `'héllo'` | 5 | 6 |
| `Length(u)` (UnicodeString) | 5 | 6 |
| `Length(s)` (AnsiString) | 6 | 6 |
| `Ord(w[2])` | 233 (`é`) | 195 (`$C3`) |

So `Length` counts **UTF-16 code units** (header byte count >> 1) and `s[i]`
yields a **WideChar**. That is what the runtime half is built to.

### There is no two-kind runtime design to extend to three

The coordinator's brief asked whether the BYTESTR/TEXTSTR split extends to a
third answer cleanly. It does, but not for the expected reason: **the split
does not exist at runtime.** `PXX_KIND_BYTESTR` and `PXX_KIND_TEXTSTR` are
declared and documented in `builtinheap.pas` and are **never stamped and never
read** — every write to the kind field is `PXX_KIND_LEGACY`. Checked because
the RESOLUTION leans on TEXTSTR as a worked precedent for the tag.

The precedent is real for SEMANTICS and false for the MECHANISM. NilPy `str`
genuinely counts characters — `len("héllo")` is 5, `t[0]` is `日`, matching
CPython — but it gets there by STATIC typing plus `PXX_FLAG_ASCII`, which is
the part that is actually live. `PXX_KIND_WIDESTR` is the first kind ever
stamped in this tree.

### UTF-16 is not a third semantics, which is why it is cheap

BYTESTR's rule is *"Length counts storage ELEMENTS, index yields one element."*
WIDESTR is the same rule at element width 2. TEXTSTR is the odd one out — the
only kind that DECODES. So the axis is **elements vs characters**, not
bytes/characters/units, and UTF-16 joins the side that already existed.

That is the real reason the stride objection stays retracted, and it is a
different reason from the one in the resolution. Not "the kind machinery was
already built" (it was not) but **"the header was already a BYTE count"** — so
refcount, free, `PXXBlockCopy`, in-place append and every backend's
retain/release blob are byte-shaped and need no second arm. Only the public
`Length()` halves, and that lowers statically off `tyWideString`.

### What is in the runtime half, and what is deliberately not

Two things differ from a byte string and both are confined to the four new
functions: 2-byte elements, and a 2-byte NUL terminator so a `PWideChar` handed
to a C API terminates where that API expects.

No ASCII flag is stamped on a wide block. `PXX_FLAG_ASCII` means "no byte >=
$80" — true of any ASCII text in UTF-16 and therefore useless — while the
flag's actual contract, byte positions equalling character positions, is false
for every wide string. Leaving it unset means "unknown", which is the honest
answer and what every consumer already handles.

Note the trap `PU16` exists to avoid: this file's `PWord` is `^NativeInt`,
EIGHT bytes. `PWord(d)^ := unit` compiles, writes eight bytes, and silently
clobbers the next three code units.

### Verified, not reasoned about

`test/test_widestring_transcode.pas` calls the runtime entry points DIRECTLY,
because with `WideString` still an alias there is no source-level way to reach
them — that is what keeps the runtime half from sitting unexercised until the
frontend catches up.

    U+1F600    -> D83D DE00     the exact jsonscanner surrogate pair
    D83D DE00  -> F0 9F 98 80
    lone surrogate -> EF BF BD, and the NEXT unit survives
    truncated lead -> FFFD, without swallowing the following character
    ascii / é / 日 / emoji all round-trip byte-identical

Malformed input maps to U+FFFD in both directions rather than raising: these
run under `Utf8Decode`/`Utf8Encode` on data that came from a file, so a bad byte
in a JSON document must not become a crash in the parser.

### Next, and why the library half is NOT parallel to it

The `lib/rtl` string units are **downstream of the type half, not independent
of it**. The boundary helpers are `UTF8Encode(w: WideString)` and
`UTF8Decode(...): WideString`, and they cannot be written — cannot even be
declared as overloads — while `WideString` is an alias for `AnsiString`.
`sysutils.pas` says exactly this at the declaration today: *"THIS RTL HAS ONE
STRING MODEL: bytes... `UnicodeString` IS `string` here and these are the
IDENTITY."*

So the order is: `tyWideString`/`tyUnicodeString` in `defs.inc` (next to the
existing `tyWideChar`, ordinal 31, which already makes `WriteLn(someWideChar)`
print the character), then the static kind in `symtab.inc` — which is what makes
`WideChar(u1) + WideChar(u2)` build a string instead of adding two ordinals,
the actual wall — then the RTL helpers, then literal encoding and `Write`.

Blast radius for the alias change is small: 10 mentions of
`WideString`/`UnicodeString` across `lib/`, `test/` and `examples/`, the only
real consumers being sysutils' identity functions and rtl-generics' comparers.
Essentially all remaining risk is in the type half; the runtime was the cheap
end, as the owner predicted.

## 2026-08-30 (frankwasm) — STOP: the blast radius is 636, not 10

I measured the wrong thing earlier and reported it confidently. **"10 mentions
of `WideString`/`UnicodeString` across lib+test+examples" counted the NAME**,
which is what has to be re-spelled. The number that governs this ticket is
different: **how many places must learn that a second MANAGED STRING kind
exists.** Measured at HEAD, in `compiler/*.inc`:

| | count |
| --- | --- |
| `tyAnsiString` mentions, all | 824 |
| ...of those, code-level kind TESTS | **636** |
| ...of those, the `(x = tyAnsiString) or (x = tyString)` "any string" shape | 97 |
| `TypeIsManagedStr` — the predicate that exists to normalise this | **5 call sites** |
| `tyWideChar` sites, for contrast (a scalar kind that DID take its own ordinal) | 19 |

The last two rows are the finding. There IS a chokepoint —
`symtab.inc:3157 TypeIsManagedStr`, whose entire body is
`Result := (tk = tyAnsiString)` — and it is **essentially unadopted**: five
calls against 636 direct tests. So there is no single place to teach about a
second kind. Under the plan as decided, every one of those 636 sites that means
*"is this a string"* rather than *"is this specifically an AnsiString"* needs a
third arm, one at a time, with no way to find the ones that were missed except
by the bug they cause.

That is `normalise-dont-special-case.md`'s exact failure — *"the second path is
the one that stays broken"* — at 636x. And it is the SAME shape as the stride
objection the coordinator raised and retracted: the objection was aimed at the
six backends, where it was measured wrong; the real second-arm cost is in the
TYPE SYSTEM, where nobody looked.

### Why this is a fork and not just work

**Option A — `tyWideString` as a distinct `TTypeKind`** (what the RESOLUTION
says, and what is landed today as ordinal 32, readers-free). Matches the
`tyWideChar` precedent and is explicit at every use. Costs the 636-site audit
with no chokepoint, and a missed site does not fail loudly — it treats a wide
string as not-a-string, which is a silent wrong value or a leak.

**Option B — ONE managed-string kind carrying an ELEMENT WIDTH.**
`tyAnsiString` stays *the* managed string kind; what differs is the element:
`tyChar` (UTF-8 byte) or `tyWideChar` (UTF-16 unit). All 636 sites keep working
untouched, because a wide string IS a managed string; only the genuinely
width-sensitive sites change — `Length` (>> 1), indexing (stride 2), literal
encoding, `Write`, and the transcode boundary.

Option B is what the runtime half already does and is the same insight one
level up. The runtime needed no second block shape, no second refcount path and
no second free path, because **the difference was never the kind — it was the
element width**, and the header stayed a byte count. Modelling it as a new KIND
in the type system contradicts the way it is modelled in the runtime.

It also has a natural home in the structure this repo just built: `TTypeRef`
already carries `Kind` PLUS sub-attributes (`ElemTk`, `PtrDepth`, `DynDepth`,
`ArrLen`) for exactly this "same kind, different shape" situation. A wide
string is `Kind = tyAnsiString, ElemTk = tyWideChar`, which is the existing
field doing the job it already has.

**Recommendation: B**, and I hold it moderately rather than weakly — the 636
vs 5 measurement is what moves it, not taste.

**The open question I could not settle, and the reason this is escalated rather
than decided:** under B the element width must ride on an EXPRESSION node, not
only on a symbol, because the wall is `WideChar(u1) + WideChar(u2)` — the width
of that `+` result is not attached to any declaration. `ASTTk` carries a kind
per node; whether there is a node-level element slot, or whether one has to be
added, is the thing that decides whether B is actually cheaper than A. That is
a design call about the AST, not something to settle while implementing.

### State: nothing is half-done

The alias is NOT broken. `tyWideString` is landed additive and readers-free
(`ce693b1d5120`), the runtime half is landed and tested, and `WideString` still
resolves to `tyAnsiString`/`tyString` exactly as before. If the fork resolves to
B, the ordinal-32 kind is deleted or repurposed at zero cost; if it resolves to
A, the work continues from where it stands. Stopping here was the point.

### Also settled while measuring: BOTH `PXX_MANAGED_STRING` arms are live

The coordinator asked for this as a gate rather than advice. Measured — both
arms build today and both agree with fpc 3.2.2 for ASCII:

    default (PXX_MANAGED_STRING defined)   w=abc lw=3 sz=8  cat=abcde len=5
    -uPXX_MANAGED_STRING (frozen tyString) w=abc lw=3 sz=8  cat=abcde len=5
    fpc 3.2.2                              w=abc lw=3 sz=8  cat=abcde len=5

So there is no excuse for testing one arm and letting the other inherit the
verdict: the untested arm is buildable, and whichever option wins must state
which arm its acceptance test ran under and run both.

### And a correction to my own earlier lockstep list

I named `rtti_emit.inc:942` as a site needing a `tyWideString` case. **Wrong** —
that function classifies ORDINALS, and `tyAnsiString` correctly is not in it
either. The real `rtti_emit.inc` sites are five others, and they are the
managed-field ones, which is what makes them matter: `FieldIsManaged` (:24) and
four finalizer/RTTI member-kind sites (:1337, :1367, :1456, :1490) that all
spell `UFldTk[fi] = Ord(tyAnsiString)`. Under option A every one is a leak if
missed; under option B none of them changes at all, which is the argument in
miniature.

`PxxTkToFPCKind` maps to FPC's numbering, and measured against fpc 3.2.2:
`TypeInfo(WideString)^.Kind` and `TypeInfo(UnicodeString)^.Kind` are **both 24**
(`tkUString`) on Linux — FPC's own RTTI collapses the two spellings exactly as
this ticket does, which is independent support for the one-kind call.

## 2026-08-30 (frankwasm) — the deciding measurement: **outcome 2, B stands**

The falsifier was: *does an expression node carry an element slot, and if not
what does adding one cost?* Measured.

### No AST node carries one, and the existing answer to that problem is a walk

There are 18 `AST*` parallel arrays. **None** carries an element type, record id
or width — `ASTTk` ("TTypeKind of expression") is the only type information a
node has. The analogous problem, a node's RECORD identity, is solved by
`symtab.inc:12778 ResolveNodeRec`, a structural resolver that dispatches on node
kind and walks to wherever the answer really lives. Its own comments call that
path *"a recurring landmine throughout this codebase"* and it visibly grew arms
one bug at a time. So the precedent exists and is a warning, not a template.

### How `s1 + s2` answers it today: it doesn't — 1 is assumed

Exactly as predicted. `PXXStrConcat(lenA, srcA, srcB, lenB)` takes BYTE lengths
and element size never appears (which is why `PXXWideConcat` came out nearly
identical). Indexing is where width lives, and for a managed string it is set in
**one** place:

    ir.inc:1794    if (tk = tyAnsiString) and not isArr then
                   begin lo := 1; elemSize := 1; tk := tyChar; ... end

That is THE site. `IR_INDEX` already carries `elemSize` as an operand and every
backend already multiplies by it, so the IR layer needs nothing new — the
constant is simply hardcoded one level up.

### Cost of adding a node-level width: 4 mechanical sites

Adding an `AST*` array is a worn path with three recent precedents
(`ASTQChk`, `ASTNilChk`, `ASTRChk`). Measured on `ASTRChk`, the whole
infrastructure cost is:

    defs.inc            the declaration
    ast_arena.inc:32    SetLength, growing in lockstep
    ast_arena.inc:74    initialise in AllocNode
    ast_arena.inc:123   copy in CloneAST

Four sites, all mechanical. **Bounded and additive — outcome 2. B stands.**

### The honest total for B, including what I did NOT expect

| | sites |
| --- | --- |
| add the node width array | 4, mechanical |
| width-sensitive lowering (index, Length, literal, Write, transcode) | ~5 |
| **per-backend COW guards** | **6** |
| of the 636 `tyAnsiString` tests | **0** |

The COW guards are the part I would have missed. Six backends carry

    (IRTk[left] = Ord(tyAnsiString)) and (elemSize = 1)

and under B a wide index has `elemSize = 2`, so the guard fails, copy-on-write
does not fire, and mutating a SHARED wide string corrupts its aliases — a silent
wrong value. All six must change.

**And `ir_codegen_xtensa.inc:1677` is one of them — the exact line the
coordinator's original stride objection cited.** So that objection was pointing
at something real. It was wrong about the SCALE (six grep-identical guards, not
a rewrite of indexing in six backends) and the retraction was correct, but the
line was not imaginary and the reflex that found it was sound.

The decisive asymmetry is findability, not just count: those 6 are one exact
grep in one shape. The 636 are NOT mechanically separable into "means any
string" and "means specifically AnsiString" — that is what makes A's misses
undetectable except by the bug they cause.

### Length needs no backend change at all

`Length` on a managed string is emitted per backend as `mov rax, [rax-8]` (and
its six equivalents) after testing `IRTk = tyAnsiString`. Under B that test still
passes and returns the BYTE count, so the halving can be a FRONTEND-emitted
shift over the existing result rather than seven new backend arms. Under A the
test would FAIL for a wide string and Length would fall through to the
dyn-array/catch-all path and return garbage — the silent-failure mode again.

### Proceeding with B, per the stated ordering

Not a fork, so not escalating. Starting on the node width array and
`ir.inc:1794`, then the six COW guards, then Length. `tyWideString` (ordinal 32,
readers-free) becomes the wide ELEMENT marker rather than a second string kind,
so nothing landed so far is wasted.

## ORDERING CONSTRAINT — not a plan, and not reorderable

**The alias break is the enabling switch and it goes LAST.** Until `widestring`
stops resolving to `tyAnsiString`, no program can construct a wide string, so
`elemSize` is never 2 and every intermediate step below is a no-op on every
existing program. That is what lets them land one at a time, green, without
holding every lock at once:

    1. ir.inc:1794 SYMBOL arm                             DONE 100d68f51
    2. AST-node element slot          (ast_arena.inc)     DONE 533877ec7
    3. record-field element slot      (pasparser_decl.inc) DONE f4587a2e4
    4. the SEVEN per-backend COW guards (ir_codegen*.inc) DONE 1dd30255b
    5. Length — a frontend shift over the existing byte count  DONE 6a3407207
    ---- and, out of step 4's findings ----
       tyWideString deleted (dead option-A residue)       DONE de9c53613
    ---- only then ----
    6. break the alias in pasparser_lval.inc:6322/6424    <- LAST
       (and change sysutils' UTF8Encode/Decode in the SAME commit: they are
        DOCUMENTED as the identity, so at that moment the documentation stops
        being merely stale and becomes a lie)

**Steps 2 and 3 were not on the first version of this list, and their absence
was the more dangerous omission.** `ir.inc:1794` derives its type from THREE
entities and only ONE of them has a width slot:

    AN_IDENT -> Syms[].TypeKind  + ElemType   EXISTS (deliberate, symtab.inc:4169)
    AN_FIELD -> RecFieldType()   + nothing    UFldTk/UFldPtrElemTk, no string elem
    else     -> ASTTk[baseNode]  + nothing    no AST node carries an element type

So `rec.w[i]` and `(a + b)[i]` would index a wide string at stride 1, silently.
And the AST-node slot is not optional polish: the wall this ticket exists to
remove is `WideChar(u1) + WideChar(u2)`, which is an EXPRESSION, so step 2 is
load-bearing for the actual goal.

**Why step 4 must precede step 6, stated as a reason so nobody reorders it
innocently.** (This paragraph said "step 5" until 2026-08-30; that was a
numbering slip in the list above it, not a second constraint. Step 5 is
`Length`, which is inert like every other pre-6 step. The hazard below is the
ALIAS BREAK's, and the alias break is step 6.) Each backend guards copy-on-write with
`(IRTk[left] = Ord(tyAnsiString)) and (elemSize = 1)`. A wide index has
`elemSize = 2`, so an unguarded backend silently skips COW and mutating a
SHARED wide string corrupts its aliases. If the alias were broken first, that
window would exist and **nothing could detect it** — no test can construct a
wide string to find the bug, because the only thing that constructs one is the
alias break itself. A hazard that can be neither triggered nor observed is one
that survives to production. The ordering is the entire mitigation.

Everything before step 5 is inert by construction, which is also why a
half-finished migration here is safe to park.

## 2026-08-30 (frankwasm) — steps 2, 3 and 5 landed; only step 4 is left before the switch

`533877ec7/f4587a2e4` (2, 3) and `6a3407207` (5). Step 1 was `100d68f51`. What remains
before the alias break is **step 4 alone**: six identical one-line guards in six
backend files.

### The width lookup is now ONE function, not three inline arms

Step 2 and 3 gave `AN_FIELD` and the expression case the element slot the symbol
arm already had. Step 5 needed the same three-arm lookup, which is where a fourth
spelling of it would have appeared — so it was extracted first:

```pascal
function ASTStrElemTkOf(node: Integer): Integer;   { ir.inc, above IRLowerAddress }
```

    AN_IDENT -> Syms[].ElemType         (symtab.inc:4169, the pre-existing slot)
    AN_FIELD -> RecFieldStrElemTk()     (UFldStrElemTk, added by step 3)
    else     -> ASTStrElemTk[node]      (added by step 2)

Both the index site and `Length` now read that one function. Extraction verified
behaviour-preserving before step 5 was written on top of it: `idx` and `fld` both
still match fpc, transcode still passes.

### Step 5 needed no backend arm, as predicted

The `tkLength` call RESULT is wrapped in `shr 1` when the argument is a managed
string whose element is `tyWideChar`. The header's length word is a BYTE count —
that is what it has always held and what all six backends' `tyAnsiString` Length
arms load — so the character count is that count halved, and the halving is a
frontend fact the IR never has to carry down.

**Guarded on the argument being `tyAnsiString`**, which is not pedantry: a
dynamic `array of WideChar` also has `Syms[].ElemType = tyWideChar`, and its
`Length` is an element count that must not be touched. Without that guard the
first thing step 5 would have broken is a type that has nothing to do with this
ticket.

### Neutrality was measured, not assumed

Every step so far is inert by construction — nothing stamps `tyWideChar` as a
string's element type until step 6 — but "inert by construction" is a claim about
code I just wrote, so it was checked against `pinned`: identical output on
`Length` over strings, `ps^`, string fields, dynamic and static arrays of `Char`,
`WideChar` and `Byte`, and over concat and `Copy` results.

That sweep found a **pre-existing** bug on a neighbouring row —
`Length(dynamic array of Char)` answers 1 where fpc answers 6, while `High` on
the same variable is correct — wrong on `pinned` too, so not this work. Filed as
[[bug-p-length-of-a-dynamic-array-of-char-returns-1]], not fixed here.

### What step 4 needs from the coordinator

**SEVEN files, and the edit WIDENS an existing clause rather than adding one.**
Both halves of that sentence correct what this section said when first written
(and what I had told the coordinator); the wrong version is quoted below so the
next reader can tell which claim changed.

> ~~Six files, one line each, no logic: add `and (elemSize = 1)` beside the
> existing `IRTk[left] = Ord(tyAnsiString)` COW test in `ir_codegen.inc:5969`,
> ... It wants one short window across all six.~~

`and (elemSize = 1)` is **already there** at every site. It is the current text,
and it is exactly what excludes a wide string from the copy-on-write path — the
x86-64 site says so in its own comment (*"uses a 1-byte stride and needs
copy-on-write"*). So the edit is:

    (elemSize = 1)  ->  ((elemSize = 1) or (elemSize = 2))

Stride 8 must stay excluded: that is the case the clause was written for — an
`array of AnsiString`, whose `IRTk` is `tyAnsiString` because the ELEMENT is a
string, not because the base is one.

**And there are seven sites, not six.** `ir_codegen_aarch64.inc:3420` spells the
identical rule as `(Integer(IRIVal[node]) = 1)` — same condition, same position
in the same if-chain — because aarch64 never hoists the value into an `elemSize`
local. **A grep for `elemSize = 1` returns six files and silently omits it.** It
surfaced only by listing `compiler/ir_codegen*.inc` and noticing seven backends
against six hits, and aarch64 is one of the two backends CLAUDE.md names as
perf-relevant, so it is not a fringe target.

Current lines (drifted; `ir_codegen.inc` is 6053, not the 5969 first recorded):

    ir_codegen.inc:6053           (elemSize = 1)                baseAddr, not left
    ir_codegen_aarch64.inc:3420   (Integer(IRIVal[node]) = 1)   the ungreppable one
    ir_codegen_arm32.inc:3295     (elemSize = 1)
    ir_codegen386.inc:3902        (elemSize = 1)
    ir_codegen_riscv32.inc:1673   (elemSize = 1)
    ir_codegen_wasm32.inc:1133    (elemSize = 1)
    ir_codegen_xtensa.inc:1677    (elemSize = 1)

It wants one short window across all seven rather than seven negotiations,
because a partial application is the one state the ordering constraint above
exists to prevent — and here the partial state is undetectable, since nothing
constructs a wide string until step 6.

**Seven spellings of one rule, one of them invisible to the obvious grep, is a
refactor ticket of its own** — the sibling of
[[refactor-p-the-char-array-is-not-a-string-rule-is-spelled-five-times]]. To be
filed AFTER step 4 lands, so the window is not held up by paperwork.

## 2026-08-30 (frankwasm) — step 4 landed; only the switch is left

`1dd30255b`, one commit, seven files, in a window the coordinator held open
across three other agents. Steps 1-5 are now all in and **step 6 is the only
thing left**.

    (elemSize = 1)  ->  ((elemSize = 1) or (elemSize = 2))     x6
    (Integer(IRIVal[node]) = 1) -> the same widening            aarch64

Stride 8 stays excluded, which was the point of the clause in the first place:
an `array of AnsiString` has `IRTk = tyAnsiString` because its ELEMENT is a
string, not its base.

**Three comments asserting a 1-byte stride were corrected in the same commit** —
x86-64's said the widened assumption outright, riscv32's and xtensa's carried it
in their arm headers. A file whose prose contradicts its code is how the next
reader concludes the code is wrong.

Inert on today's corpus, and measured rather than asserted: `pinned` == new on
copy-on-write through a plain variable, a record field and an array element, on
the aliasing COW exists to protect, and on the read path.

The seven-spellings problem is filed as
[[refactor-a-the-managed-string-index-cow-rule-is-spelled-seven-times]].

### Step 6 is NOT disjoint from `defs.inc` — correcting an answer I nearly gave

I was drafting "step 6 does not touch `defs.inc`, so frank-optimize and I are
disjoint" when the step-4 window opened, and had not finished checking. It is
probably wrong.

The alias sites are inside **`BuiltinScalarTypeKind(nm: AnsiString): TTypeKind`**
(`pasparser_lval.inc`), which returns a **bare kind**. Under option B the answer
for `widestring` is not a kind, it is a PAIR — `tyAnsiString` *whose element is
`tyWideChar`* — and that function's signature has nowhere to put the second half.
So step 6 needs a channel out of it, and every global in this compiler lives in
`defs.inc`. Settle the shape of that channel BEFORE claiming a lane boundary.

This is the same trap as step 4's, one level up: the obvious reading of a site
("it just returns a kind, so widening it is local") is wrong for a reason only
visible from the signature.

### `tyWideString` (defs.inc:1752) is dead, and its comment sells option A

It was added under **option A**, which was then rejected in favour of **B**.
Nothing constructs or reads it — the only references anywhere are its own
comment and two prose mentions in `builtinheap.pas`. Under B it is permanently
unreachable, because `widestring` resolves to a `tyAnsiString` carrying a wide
ELEMENT and never to a distinct kind.

That would be harmless if the comment above it were not a 40-line, confident
migration plan for the design we did not take, sitting at the tail of
`TTypeKind` where it reads as current. Its lockstep list also still names
`rtti_emit.inc:~942`, which was established to be wrong — that site classifies
ORDINALS, and `tyAnsiString` is correctly absent from it too; the real lockstep
sites are `FieldIsManaged` and the four finalizer sites.

**Recommended: delete the enumerator and the comment**, keeping only the
sysutils `UTF8Encode`/`UTF8Decode` warning, which belongs here in the ticket
rather than in `defs.inc`. It is last in the enum, so nothing renumbers, and
re-adding it costs nothing if A is ever revisited. Raised with the coordinator
rather than done unilaterally: `defs.inc` is dual-occupied, and deleting a type
kind is closer to a decision than to cleanup.

### Sha citations here were rewritten once — these are the landed ones

Every sha this ticket cited before 2026-08-30 was a PRE-REBASE sha and none of
them exist in history. `tools/sync.sh` rebases on nearly every push (the watcher
publishes tstate continuously), so a sha read from `git log` before the push
names a commit that survives only in the local reflog — exactly
[[bug-t-resolve-cites-a-sha-the-rebase-then-rewrites]]. They have been corrected
in place above. The mapping, for anyone holding the old numbers:

    12111b1f2 -> 100d68f51   step 1
    526f86cc9 -> 533877ec7   step 2   (and f4587a2e4 for step 3 — it was TWO
                                       commits, not one, as recorded)
    8b35b2d60 -> 6a3407207   step 5
    e2dba4293 -> 1dd30255b   step 4

The general lesson is the one CLAUDE.md already states for `resolve`: do not
write a sha you have not seen on origin. I wrote four, in a ticket AND in
messages to the coordinator, before the push that renamed them.

## 2026-08-30 (frankwasm) — step 6 is NOT one commit: it needs FIVE durable slots, and two exist

Measured before starting, because the design question "how does `widestring`
carry its element width out of a function that returns a bare `TTypeKind`" has a
right answer that is not the obvious one, and a cost that is not the obvious one
either.

### The transport is a companion global, because that mechanism already exists

`ParseTypeKind` (`pasparser_decl.inc`) has solved this exact problem twice:

    LastTypeStrCap          `string[N]`   — kind is tyFixedString, CAPACITY travels beside it
    LastTypePointerElemTk   `PWideChar`   — kind is tyPointer,     ELEMENT KIND travels beside it

`LastTypePointerElemTk` is the precise analogue: a kind that cannot express the
whole type, with the remainder carried in a companion set at the same moment,
reset per declaration at `pasparser_decl.inc:135`. Per
`normalise-dont-special-case`, step 6 adds `LastTypeStrElemTk` beside it rather
than a pair-return or a third name table — and a third name table is *actively*
contraindicated, because `pasparser_lval.inc:6413` records
`bug-a-sizeof-real-disagrees-with-the-storage-real-actually-gets`, which was two
parallel name->kind tables drifting until `SizeOf(Real)` answered 8 for a
variable occupying 4.

### But the global is ONLY a transport, and that is where the cost is

**The companion-global pattern has produced at least three documented silent-wrong-value
bugs in this compiler, all the same shape:** a consumer distant from the
declaration read whatever the last unrelated declaration had left in the global.

    bug-pascal-array-of-pointer-deref-loses-the-record-type    LastTypePointerElemRec
    bug-p-typed-constants-cannot-hold-a-pointer-...            LastTypePointerElemTk
    bug-a-nd-array-function-result-indexes-the-wrong-slot      LastTypeStrCap

`defs.inc:4612-4635` tells the second one in full: `TAp = array[0..1] of PChar`,
then `a[0] := 'hey'; WriteLn(a[0])` printed **4304310** — the pointer — because
every consumer of the alias read whatever the last unrelated pointer declaration
in the unit had left behind.

**The fix was never to abandon the global. It was to CAPTURE it into a durable
per-entity slot at definition time.** So the real question for step 6 is not
"which channel" — it is *how many durable slots must capture it*, and the answer
is however many the POINTER element kind has, because a wide string reaches
exactly the same places a typed pointer does.

### The count: five carriers, two written

    entity            pointer element kind      string element kind
    ---------------   -----------------------   -----------------------------
    symbol            Syms[].PtrElemTk          Syms[].ElemType     EXISTS
    record field      UFldPtrElemTk             UFldStrElemTk       step 3
    type alias        AliasElemTk               --- MISSING ---
    array-type elem   ArrTypePtrElemTk          --- MISSING ---
    proc param/ret    ptypesPtrElemTk /         --- MISSING ---
                      ProcRetPtrElemTk

The denominator here comes from outside the instrument, per the step-4 lesson:
it is **the set of durable carriers the POINTER element kind already has**, not
a grep for things that look string-ish. Five entities can hold a type whose kind
does not describe it fully; two of the five have a string-element slot.

Each missing one is a silent stride-1 index of a UTF-16 string at a use site far
from the declaration:

    type TW = WideString;  var x: TW;          { alias      }
    var a: array[0..3] of WideString;          { array elem }
    procedure P(const w: WideString);          { param      }
    function F: WideString;                    { return     }

### Consequence for the plan

**Step 6 is not one commit and must not be attempted as one.** It is three more
slot-migrations of the same shape as steps 2 and 3 — each additive, readers-free
and inert while the alias still resolves to a byte string — and only then the
alias break. The ordering argument that put the alias break last applies
unchanged and with more force: every one of these is undetectable until the
switch is thrown.

Revised tail of the ordering constraint:

    6a. AliasStrElemTk       (type alias)
    6b. ArrTypeStrElemTk     (array element)
    6c. param / return slots
    ---- only then ----
    7.  break the alias in pasparser_lval.inc:6322/6424, with sysutils'
        UTF8Encode/UTF8Decode in the SAME commit

Note this is the "one of six parallel arrays not written" class by name — which
the deleted `tyWideString` comment was right about even though it was wrong
about everything else. Recorded here rather than lost with it.
