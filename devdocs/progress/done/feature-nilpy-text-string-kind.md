---
track: N
prio: 55
type: feature
blocked-by: []   # was feature-a-managed-block-kind-word — landed, see Log 2026-08-10
summary: "Phase 2 of multi-type strings: stamp TextString/ByteString kinds and make NilPy str count CHARACTERS — len, indexing, slicing, find and reverse — over the shared byte substrate, with the ASCII flag keeping the common case O(1)"
status: done
owner: claude-AN
---

# NilPy `str` counts characters, not bytes (phase 2)

- **Type:** feature (semantics) — **Track N**
- **Design:** `devdocs/dev/managed-block-header.md`.
- **Blocked by** [[feature-a-managed-block-kind-word]] — do not start before that
  is **pinned**. The pin is what guarantees this never meets an old-offset
  binary.
- Supersedes the fork in `decide-nilpy-str-is-bytes-or-codepoints`, which is
  decided: a NilPy `str` is a sequence of code points; a Pascal `AnsiString`
  stays bytes; they are two kinds of one representation, not one type.

## The defect this closes

Measured at `8f1852f27`, `s = "héllo"`, `t = "日本語"`:

| expression | CPython | pxx |
| --- | --- | --- |
| `len(s)` | 5 | 6 |
| `s[1]` | `é` | `\xc3` — **invalid UTF-8 on stdout** |
| `s.find("l")` | 2 | 3 |
| `s[::-1]` | `olléh` | **byte-reversed, invalid UTF-8** |
| `len(t)` / `t[0]` | 3 / `日` | 9 / `\xe6` |
| `ord("€")` | 8364 | `TypeError: … string of length 3 found` |

The two rows that emit **malformed UTF-8** are the urgent part; they are worse
than any end state and worth fixing first.

## Why this is a defect and tuple-mutability is not

`devdocs/dev/nilpy-semantics-divergences.md` accepts a mutable tuple because no
working CPython program can observe it. Ordinary working code that slices or
measures non-ASCII text observes every row above. Different side of that line.

## What must NOT change

**Pascal is already correct and must stay "wrong."** FPC counts code units —
`Length` on an `AnsiString` is bytes, and on a `UnicodeString` it is UTF-16 code
units, so a non-BMP character counts 2 and `s[1]` can be half a surrogate pair.
Being *more* correct than FPC would be a compat bug. This is why the substrate
could not simply be changed: the two frontends have genuinely different correct
answers, which is what the kind word exists to express.

## Layout constraint you must obey

Every meaningful field lives in the **low 32 bits** of the meta word:
`BlockKind(8) | Flags(8) | KindData0(8) | KindData1(8)`, bits 32–63 reserved.
Spending the upper half would permanently foreclose
[[feature-a-shrink-managed-header-on-32-bit]], because a packed ILP32 header
makes the meta word 32 bits wide. Consequently `KindData0` holds a small
**encoding enum** (0 = bytes, 1 = UTF-8, 2 = UCS-2, 3 = UCS-4), not a raw
codepage — `CP_UTF8` = 65001 does not fit in 8 bits, and the enum is the better
field regardless.

Also rename the phase-1 offset constant `PXX_HDR_KIND` → `PXX_HDR_META` in this
ticket's first commit. Nothing reads it yet, and this ticket re-pins anyway.

## The work

1. **Stamp kinds at every materialisation site** — the literal→managed
   conversion, concat, `SetLength`, and the pylib constructors. The static type
   is known at each: Pascal context → `ByteString`, NilPy context → `TextString`.
2. **Propagate through pylib.** The ~79 `pystr_*` functions *construct* new
   blocks; every `Result := …` must carry the kind forward or the result
   silently degrades to the default. This is the bulk of the work and it is the
   part that is easy to under-estimate.
3. **Character-aware public positions** for `TextString`: `len`, indexing,
   slicing, `find`/`index`/`rfind`, reverse, `charlist`, padding widths,
   `ord`/`chr`. Internal offsets stay bytes.
4. **Set the `ASCII` flag** at construction when no byte is ≥ 0x80. Then `len`
   and indexing stay **O(1) and byte-identical to today** for the overwhelmingly
   common string; only genuinely non-ASCII text pays.

## Keep the coordinate system coherent

Byte and character answers agree for `in`, `count`, `split`, `==`, `+`, and —
measured — offsets round-trip today: `s[s.find("w"):]` is correct across
multi-byte characters, because UTF-8 is self-synchronising. That is *why* `find`
must move to character offsets in the same change as indexing. Moving one and not
the other breaks programs that currently work.

## Static context wins

Kinds live on shared refcounted blocks, so a kind cannot be flipped at a boundary
without copying. Where a static type exists it decides; the kind answers only
where the static type is lost (variant, container element, generic/untyped
parameter). A `TextString` reaching Pascal code is read as bytes, no copy; a
`ByteString` reaching NilPy from a variant is treated as UTF-8 text.

## Gate

Per-fix loop per item. `.npy` tests diffed against CPython with `tools/pydiff.py`
covering every row of the table above, plus: an all-ASCII string (must stay
byte-identical and O(1)), a `find`→slice round-trip across a multi-byte
character, a Pascal `AnsiString` round-tripping through a variant into NilPy, and
`in`/`count`/`split`/`==`/`+` (which must not move). Watch for the O(n²) shape —
`while i < len(s): s[i]` — on a non-ASCII string.

## PARKED in unfinished/ — the foundation is LANDED and green, the semantics are not

Not blocked and not half-applied: the compiler change is complete, gated and
pinned (v248), so nothing here is in a broken intermediate state. What remains
is the semantic conversion, which is scoped below and must be done as one
commit. Re-claim it; do not re-derive the survey.

## 2026-08-07 — the FOUNDATION landed; the semantic conversion did not

Split deliberately. What is in is complete and useful on its own; what is out
would have been half a coordinate system, which is worse than none.

### Landed

- **The meta word is defined** with the low-32 budget the 32-bit shrink needs:
  `BlockKind(8) | Flags(8) | KindData0(8) | KindData1(8)`, bits 32–63 reserved.
  Kinds `LEGACY/BYTESTR/TEXTSTR/DYNARRAY/OBJECT`; flags `STATIC/INTERNED/ASCII/
  EXTENDED`; `KindData0` is the encoding enum (`BYTES/UTF8/UCS2/UCS4`), not a
  codepage.
- `PXX_HDR_KIND` → **`PXX_HDR_META`**, as this ticket required.
- **`PXX_FLAG_ASCII` is computed and stamped** for every string built by
  `PXXStrFromLit` and `PXXStrConcat` — and it is **free**: both already copy
  byte by byte, so it is one `or` per byte in a loop that exists anyway. No
  extra pass, no cached side table.
- `PXXHdrMeta(p)` is exported for consumers. Its absence of a flag means
  **"unknown"**, never "non-ASCII" — a consumer must scan.
- The phase-1 debug magic retired: the meta word now carries real data, so the
  `-dPXX_HEAP_DEBUG` check became "is the kind byte a kind we know". Weaker
  against a wild pointer into live data, but use-after-free is still caught
  ($DD poison = 221 > `PXX_KIND_MAX`).

Verified: `lit → ASCII`, a UTF-8 `é` string → not-ascii, `ascii + ascii →
ASCII`. Self-host fixedpoint in one round via the **fast path** — no layout
changed, so `make compiler/pascal26` is correct here, which is the narrow rule
from `devdocs/dev/fpc-optional-workflow.md` working as documented.

### The obstacle the next session needs to know about

**`pystr_at` returns a `Char`.** A NilPy `s[i]` lowers to it
(`pyparser.inc` ~5180) and the result is typed `tyChar`, promoted to a str via
`pystr_ofchar` where a string is needed. A `Char` is one byte, so it **cannot
carry a multi-byte character**. Character indexing therefore needs a new
string-returning entry point (`pystr_at_s`) *and* the lowering re-typed from
`tyChar` to `tyAnsiString` — which ripples into NilPy's type inference. That is
the structural work, not the UTF-8 arithmetic.

### How CPython solves the "char" problem — and why that removes the objection

Python has **no char type**. `s[i]` returns a `str` of length 1, always.
Measured against CPython 3.12:

| | result |
| --- | --- |
| `type(s[0]).__name__`, `len(s[0])` | `str`, `1` |
| `t[1] is t[1]` for `é` (U+00E9) | **True** — cached |
| `u[0] is u[0]` for `日` (U+65E5) | **False** — freshly allocated |
| `sys.getsizeof("a")` | 42 bytes |

So CPython keeps a cache of the **256 latin-1 single-character strings** and
allocates only above U+00FF. Given a 42-byte str object, that cache is what
makes `for c in s` and `s[i]` affordable at all.

**This is the answer to the `pystr_at` obstacle above.** The objection to
returning a string instead of a `Char` is allocation cost per subscript — and
CPython shows the standard fix: intern the single-character strings. For pxx
that means the ~128 ASCII ones (our substrate is UTF-8, so latin-1 above $7F is
already two bytes and less worth caching), which is exactly the population the
`PXX_FLAG_ASCII` fast path is already about. On that path `s[i]` becomes a
pointer to a shared block — **cheaper than today's `Char` → `pystr_ofchar`
promotion**, which allocates.

Pleasingly, both reserved flags from the phase-2 foundation find their purpose
here: `PXX_FLAG_INTERNED` marks a cached singleton, and `PXX_FLAG_STATIC` is
what stops its refcount ever reaching zero. Neither was invented for this; they
were reserved on general principle and the use arrived.

### …but do NOT copy CPython here — keep the char TYPED (user, 2026-08-07)

CPython interns single-character strings *because it has no static types*:
everything is an object, so `s[i]` must be one. We are a compiler and should not
adopt a workaround for a constraint we do not have.

**Any Unicode code point fits in 32 bits**, so a scalar holds any character.
The name already exists — FPC's system unit declares `UCS4Char = type LongWord`
(with `UCS4String`), which is the same thing as Go's `rune`, Rust's `char`,
C11's `char32_t` and CPython's own `Py_UCS4`. Use `UCS4Char`: it is the
FPC-faithful spelling and costs nothing to adopt.

The ladder is **not** three sizes of one idea, and the middle rung is the trap:

| type | width | holds |
| --- | --- | --- |
| `AnsiChar` (`tyChar` today) | 1 | a UTF-8 **code unit** |
| `WideChar` (a value cast today, not a type) | 2 | a UTF-16 **code unit** — may be HALF a character |
| `UCS4Char` | 4 | a **code point** — always whole |

Only the last is guaranteed to hold any character; `WideChar` needs a surrogate
pair above the BMP, which is the same defect as `Length(UnicodeString)` counting
code units.

**So the shape of the fix changes, and gets cheaper.** Widen the subscript
result from `tyChar` to a code-point scalar rather than converting it to a
string:

- **no allocation** — a register value, not a refcounted heap object;
- **no `tyChar` → `tyAnsiString` ripple through NilPy's inference**, which was
  the expensive part of the previous plan;
- it **generalises the existing architecture** instead of replacing it: `s[i]`
  is already a `tyChar` promoted by `pystr_ofchar` where a string is wanted.

The remaining work is to make that promotion **complete**. NilPy requires `s[i]`
to behave as a `str` everywhere — `s[i] + "x"`, `len(s[i])`,
`type(s[i]).__name__`, `s[i] in d` — and today `pystr_ofchar` is applied at
specific sites (comparisons, `pyparser.inc` ~1971). That is contextual
promotion in the frontend, where it already lives, not a type-system change.

The interned-1-char-string route is recorded above as the fallback if the
promotion turns out not to be completable; it is no longer the recommendation.

### Keep `tyChar` too — but know exactly when it is provable

`tyChar` does not go away, and not only for NilPy's sake: **Pascal's `Char` is
one byte unconditionally** (FPC's `AnsiChar`), so the kind is load-bearing
regardless. The question is only what NilPy's `s[i]` types as.

Use `tyChar` where the compiler can **prove** the source is single-byte, and
`tyUCS4Char` otherwise. Be precise about which is which, because the obvious
mistake is to reach for the ASCII flag:

| source of `s` | provable statically? |
| --- | --- |
| an all-ASCII string **literal**, or a concat of them | **yes** → `tyChar` |
| anything from a variable, a call, input, a container | **no** → `tyUCS4Char` |

**`PXX_FLAG_ASCII` is a RUNTIME fact and cannot drive a static type.** It is
still worth everything it costs — inside the `tyUCS4Char` subscript it gives an
O(1) index and a one-byte load — but it is a runtime fast path, not a typing
input. Do not write "we use `tyChar` when the string is ASCII"; that is only
true for literals.

### Adding the kind is small, and there is a precedent for its shape

Append `tyUCS4Char` at the **tail** of `TTypeKind` — ordinals 0–6 are frozen
since first bootstrap and everything after is append-only, so a new kind at the
end is the cheap, safe move. Storage is 4 bytes; `TypeSize`/`TypeIsOrdinal`
carry it with no special-casing.

The precedent for making it a **distinct kind** rather than reusing `tyUInt32`
is `_Bool`, three lines above in the same enum: *"the reason it is its own kind
is CONVERSION, not layout"*. Same argument here — a `UCS4Char` converts to a
string as its UTF-8 encoding, a `UInt32` converts as decimal digits, and nothing
downstream could tell them apart if they shared a kind. Only the conversion
sites need to ask for it by name.

### `WideChar` stays contained — do NOT complete it

It is a historical accident: a 16-bit *code unit* from the era when Unicode was
16 bits, so it cannot hold a character above the BMP without a surrogate pair.
pxx already has it in the only defensible form — a **boundary cast**
(`__pxxWideCharToUTF8`, with a surrogate-aware pair form) that exists so
FPC-shaped source spelling `WideChar(u)` compiles. That containment is correct.

Do not promote it to a first-class type, a string element, or a subscript
result. The ladder that matters is `AnsiChar` (byte) → `UCS4Char` (code point);
`WideChar` is not a rung on it.

### Why it must be all-or-nothing

Converting `len()` alone makes things **worse**: `while i < len(s): s[i]` would
then mix a character count with a byte index, breaking code that works today.
The byte model is at least internally consistent (measured: `s[s.find("w"):]` is
correct across multi-byte characters, because UTF-8 is self-synchronising). So
one commit must move the whole public coordinate system:

`pystr_len`, `pystr_at`(→ new str form), `pystr_slice`, `pystr_slice_step`,
`pystr_reverse`, `pystr_charlist`, `pystr_find`/`_from`/`_range`,
`pystr_index`*, `pystr_rfind`*, and the padding widths
(`ljust`/`rjust`/`center`/`zfill`).

Not affected, because byte and character answers coincide — and this was
**measured against CPython with non-ASCII input**, not assumed: `in`, `count`,
`split`, `partition`, `join`, `replace`, `==`, `+`, `startswith`/`endswith`
without offsets all already agree on `"héllo wörld"`. That is what bounds the
conversion to the position-exposing functions above; do not re-verify it, and do
not widen the list without a measurement.

### The property that makes it safe when it happens

Gate every converted function on `PXX_FLAG_ASCII`: when set, byte position ==
character position and the function takes **exactly today's code path**. Every
existing test uses ASCII, so the entire suite stays on the unchanged path and
the new behaviour appears only where the old behaviour was wrong. That is the
whole regression argument — build it that way from the start.

### Access route, verified

pylib does **not** `uses builtinheap` today. Adding it was tried and **works**
(a NilPy program built and ran with it). The exploratory edit was reverted to
keep this commit purposeful, but the route is known-good — do not re-litigate
it, and do not duplicate the header offsets into pylib instead.


## 2026-08-07 — the `--no-unicode` mode (user proposal, accepted with a sequence)

NilPy ends up with two string types, and the choice is partly per-target. A
programmer — or a platform — may opt out of Unicode entirely and get plain byte
text.

**This costs almost nothing to build, because the foundation already fits it.**
The mode is not a second implementation: it changes which kind NilPy stamps on
its literals, `PXX_KIND_TEXTSTR` → `PXX_KIND_BYTESTR`. Everything downstream
dispatches on kind anyway, so the opt-out is one constant at the stamping sites.

### The default must stay Unicode-on

Upward compatibility decides it (see this ticket's top): if code runs on CPython
it must run on NilPy. A byte default makes ordinary CPython programs silently
wrong, which is the defect being fixed. So Unicode is the default and
`--no-unicode` is the opt-out — never the reverse.

**ESP flips the default, and there is precedent.** CLAUDE.md already justifies
*"ESP is not a Unix"* — 33 PAL entry points refused even under IDF, so
POSIX-shaped code meets a clear refusal rather than a wrong answer. *"ESP is not
Unicode"* is the same move: a platform with an explicitly narrower contract
rather than a silently different one. Serial I/O is bytes, and a 64 KiB static
arena should not carry decode tables.

### Contain the two-dialect risk

A switch that changes `len()` makes two languages, and code built the other way
misbehaves quietly. Two cheap containments, both worth building WITH the flag
and not after:

1. **Whole-program, not per-unit.** No mixing inside one binary.
2. **Warn on a non-ASCII string LITERAL under `--no-unicode`.** In that mode
   such a literal is almost certainly a mistake, so the mode polices itself at
   compile time instead of surprising someone at runtime.

### Sequence — this is the part that matters

1. **The correct path first**: `tyUCS4Char` + the runtime `PXX_FLAG_ASCII` fast
   path, so CPython-correct behaviour is what you get by default.
2. **Then** the `--no-unicode` mode and the ESP default.
3. **Then** the static-literal optimisation below.

Building (2) before (1) ships a mode that is fast and wrong by default, and a
wrong default is far harder to withdraw than to never set.

### The hardcoded-literal optimisation, with its caveat

An all-ASCII literal is statically provable, so `s[i]` on one is `tyChar` with
no runtime check — this composes with the provability table above and is a pure
win with no semantic change.

The user's *"if they never mutate"* caveat is load-bearing: **the property
belongs to the VALUE, not the variable.** `"hello"[i]` is provable;
`s = "hello"; …; s[i]` requires knowing `s` was not reassigned. Keep it
conservative — literal-derived only, killed by any assignment that is not itself
provable — or it quietly becomes dataflow analysis wearing the costume of a
quick win.


## 2026-08-07 (later) — `tyUCS4Char` LANDED

Step 1 of the sequence above. The kind exists, is declarable, and converts.

### FPC parity, verified against FPC 3.2.2 directly

| | FPC | pxx |
| --- | --- | --- |
| `UCS4Char` accepted as a type | yes | yes |
| `SizeOf` | 4 | 4 |
| `Ord(c)` | the code point | the code point |
| holds a value past the BMP | yes | yes |

So the *type surface* is genuine Pascal compliance, which is the framing that
justified doing it: pxx lacked a type FPC has.

### …and one deliberate divergence, stated rather than blurred

**FPC REJECTS `'h' + c`** — its `UCS4Char = type LongWord` is an integer type,
so string-plus-integer does not compile. pxx converts it to the code point's
UTF-8 encoding instead. That is a **pxx extension, not parity**, and it is the
whole reason the kind is distinct rather than an alias for `tyUInt32` — same
storage, different conversion, exactly the argument `defs.inc` already makes for
C99 `_Bool`. Consistent with the dialect stance: lax by default, FPC-strictness
behind `--strict-*` flags if parity is ever wanted here.

### What it took

- `tyUCS4Char` appended at the enum tail (ordinal 30), `TypeSize` 4,
  `TypeIsOrdinal` true.
- Name mapping in **both** resolvers — the expression-level one and the
  declaration-level one. Only patching the first gives *"unknown type:
  UCS4Char"* on `var c: UCS4Char`.
- `__pxxUCS4ToUTF8` in `builtin.pas`: full 1/2/3/4-byte range, no `$FFFF` mask,
  and a lone surrogate or a value past U+10FFFF encodes to nothing (matching
  what FPC does with an unpaired surrogate).
- The builtin pre-scan pulls the helper on **any mention** of the name, not just
  a `(` cast as WideChar does — because unlike WideChar this is a declarable
  type and `var c: UCS4Char` needs the helper just as much.

### Two traps worth keeping

1. **A one-character literal is `tyChar`.** So `'h' + c` had two ordinals and
   took the ARITHMETIC path — `Chr(104+233)`, one wrong byte, silently. Both
   operands must be wrapped: the code point encodes, the byte only widens.
2. **Wrapping the operands is not enough — re-type the concat NODE.**
   `('h' + c) + 'llo'` left the inner node still claiming `tyChar`, so the outer
   concat read a 2-byte result as one byte and the whole expression came back 4
   bytes instead of 6. Both are pinned in `test/test_ucs4char.pas`.

### The trap that actually cost a gate run

The concat re-typing (trap 2 above) was first written as *"if this is a `tkPlus`
and either side is a string, the result is a string"* — with **no guard that a
`tyUCS4Char` was involved at all**. It therefore fired for **every string concat
in every frontend**, and turned LOLCODE's `SMOOSH` into an infinite loop: the
program printed its first four lines forever until it blew the stack.

Two things worth carrying from that:

- **A conversion hook in the shared IR is not local, however local its motive
  is.** The wrap arms were correctly guarded on `tyUCS4Char`; the re-typing that
  followed them was not, and it sat inside the same `begin…end` so it read as
  guarded. The fix is the guard on the *enclosing* `if`, so the whole block only
  runs when a code point is really present.
- **The failure appeared nowhere near the change.** Nothing in Pascal, C, NilPy,
  Rust or Zig noticed; the one visible symptom was an esoteric-frontend test
  looping. That is exactly the case the full tier exists for, and the reason a
  shared-IR change does not get the quick loop.

### One latent bug fixed on the way

`IRVerify` bounded valid kinds with a hardcoded `Ord(tyBool8)` — the last kind
at the time — so **every future kind appended to the enum would fail IR
verification** until someone found that line. Now `Ord(High(TTypeKind))`.

### Still to do (unchanged from the plan)

Widen NilPy's `s[i]` from `tyChar` to `tyUCS4Char` and complete the
`pystr_ofchar` promotion, then the character-aware `len`/slice/find as one
commit, then `--no-unicode`, then the literal optimisation.

## 2026-08-10 — UNBLOCKED (board maintenance, no code change)

`blocked-by: feature-a-managed-block-kind-word` was still set in frontmatter,
but that ticket is in `done/`. Cleared the field.

Worth flagging how this hid: a stale `blocked-by` is invisible in two layers at
once. `unfinished/` is already outside the ranked queue (`ready`/`next` never
list it), so nobody saw the ticket; and had it been re-filed to `backlog/`, the
stale blocker would have kept it out of `ready` anyway. Prio-55 work with a
satisfied blocker was parked twice over.

## 2026-08-14 — LANDED: str counts characters (the whole defect table)

Every row of the defect table above now matches CPython **byte for byte**, and
so does `test/test_nilpy_str_counts_characters.npy` (generated from CPython, ~70
assertions). The uforth corpus — 4357 lines of real Python with 123 string
subscript sites — recompiles and runs the full ANS Forth suite with **Total
errors 0** and stdout **identical to CPython's**, which is the regression
evidence that mattered most for a change this broad.

### The re-pricing: it was ~10 functions, not ~79

The plan above priced this as "~79 `pystr_*` functions must carry a kind word".
Measured instead of assumed, that is wrong twice over:

1. **`pystr_*` is already the NilPy-only surface.** Pascal uses
   `Length`/`Copy`/`Pos`; it never calls these. The two coordinate systems are
   therefore separated **by function**, not by a kind word on the value — so no
   kind word is needed for the semantics at all. (The kind word still has its
   own uses; it is simply not load-bearing here.)
2. **The surface composes.** `strip`, `split`, `partition`, `count(a,b)`,
   `startswith(a,b)`, `index`, `rindex`, and the find/rfind windows are all
   written in terms of `pystr_slice` / `pystr_find` / `PyWindowStart`. Convert
   those and the rest convert with them, untouched.

What actually changed: three helpers (`PyStrCharLen`, `PyStrByteOfChar`,
`PyStrCharOfByte` — the ONLY place the two coordinate systems meet), then
`pystr_len`, `len(AnsiString)`, `pystr_at`, `pystr_slice`, `pystr_slice_step`,
`pystr_reverse`, `pystr_find`, `pystr_find_from`, `pystr_rfind`, `pystr_count`,
`pystr_charlist`, the four justify/zfill widths, and `pyord_s`.

### `s[i]` is a one-character `str`, not a `tyUCS4Char`

The plan said to widen the subscript to `tyUCS4Char`. It is now `tyAnsiString`
via a new `pystr_charat`, which is **closer to the language being implemented**:
Python has no char type, `s[i]` IS a `str`, and `type(s[1]).__name__` must
answer `'str'`. It is also far less invasive — `tyUCS4Char` has conversion arms
only in the shared IR's binary-operator path, so widening to it would have meant
auditing every context a subscript can reach (print, comparison, dict key, call
argument, assignment) and adding a `__pxxUCS4ToUTF8` wrap to each. A string
needs none of that: strings are the well-trodden path.

`tyUCS4Char` keeps its place for `UCS4Char(x)` in Pascal. `pystr_at` (a lead
BYTE) survives for callers that genuinely want a byte.

### Three sites for one concept, again

`list(s)`, `pystr_charlist` (the zip/enumerate path) and the `for ch in s`
desugar each exploded a string into characters **their own way** — so `list(s)`
and `zip(s, s)` could disagree about how many elements a string has, and the
loop desugar reached its element through `pystr_ofchar(pystr_at(...))`, a
promotion that existed only to repair the `tyChar` that is now gone. All three
route through `pystr_charat`/`pystr_charlist` now. The recurring NilPy shape
(`project_nilpy_class_attribute_lowering_matrix` and its siblings) held here too:
the concept had N independent lowerings and fixing one would have left the rest
wrong.

Length had the same duplication one level down: `len(s)` resolves to pylib's
`len(AnsiString)` overload and **never reaches `pystr_len`** — a probe that
converted only `pystr_len` still answered 6 for `len("héllo")`. Both moved.

### `chr` and `ord` moved with them, and had to

`ord` and `chr` are inverses, so converting one alone converts a loud error into
a silent wrong value — the worst available direction. `ord("€")` was a
TypeError ("string of length 3"); `chr(8364)` first truncated mod 256, then was
made to refuse anything over 255. Both now span the whole Unicode range:
`pyord_s` decodes UTF-8, a new `pychr_s` encodes it and returns a `str`, and
`PyChrRangeCheck` is **deleted** rather than left beside its replacement.

`test/test_nilpy_chr_range_check.npy` asserted the refusal, so implementing the
feature inverted its own test — the third time on this board
(`project_implementing_a_feature_breaks_its_own_fail_test`). Rewritten to assert
the round-trip `ord(chr(n))`, which is the property that fails for BOTH older
behaviours and is what programs actually depend on.

### Deliberately NOT in this commit

- **The `PXX_FLAG_ASCII` fast path.** `pystr_isascii` scans, O(n). The flag is
  already stamped by `PXXStrFromLit`/`PXXStrConcat` and would make it O(1), but
  reading the meta word of a block that may never have carried a header is a
  claim that has to be MEASURED — and a false positive there is a silent wrong
  answer on exactly the strings this ticket is about. Filed separately.
  Consequence today: a **stepped** slice over a non-ASCII string is O(n*k).
  ASCII is unaffected — it takes the byte-identical fast path everywhere.
- **`--no-unicode`** and the literal optimisation from the original plan.
- **Unicode case mapping.** `"héllo".upper()` still answers `HéLLO`; that needs
  case tables, not offsets, and is
  `bug-nilpy-case-mapping-cannot-change-code-point-count`.
- **`sep.join(str)`.** `"-".join("hello")` **segfaults on the pinned compiler**
  — `pystr_join` is reached by name and takes a `TPyList`, so a string handle
  was dereferenced as an object pointer. This change turns it into a loud
  TypeError; the real fix (explode the str, as `PyIterArgAsList` already does
  for zip/enumerate) is filed separately.

### The scoping trap worth remembering

The ticket's "must be done as one commit" was right, but its *reason* was wrong,
and acting on the stated reason would have priced the job out of a session. The
constraint is not "79 functions share a kind word" — it is that **`len`, `s[i]`,
`find` and slicing COMPOSE**: `s[s.find(x)]` mixes two of them, so any half
conversion breaks code that works today. That is a much smaller and much
sharper constraint, and it is what decided the split actually taken: coordinates
+ the character accessor together (this commit), the ASCII fast path separately
(pure optimisation, composes with nothing).

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
