---
slug: feature-p-implement-the-real-tyshortstring-byte-prefix-layout
title: "Implement the real `tyShortString` byte-length-prefix layout — the kind is already plumbed, the codegen is not"
track: P
prio: 45
type: feature
status: backlog
created: 2026-09-02
found-by: owner (raised 2026-09-02), measured by frankuser
owner: ""
summary: "MEASURED at bf92c45a7, binary sha256 `5f275966bf50`: we are `cap+8` and FPC is `cap+1`, uniformly — ShortString 263 vs 256, string[10] 18 vs 11, string[255] 263 vs 256. The ENTIRE divergence is the length-word width (8-byte NativeInt vs 1 byte), and it is a documented INTERIM: `pasparser_decl.inc:540` maps the name `shortstring` to a 255-cap `tyFixedString` with the comment *'the true byte-length-prefix tyShortString (FPC ABI) is a later codegen slice'*. THE KIND IS ALREADY PLUMBED — `tyShortString` has 63 sites across 18 files including EVERY backend (i386, wasm32, arm32, aarch64), `abi.inc` and `rtti_emit.inc`, against `tyFixedString`'s 79; `FrozenStrSlotSize` already returns `cap+1` for it. What is missing is the byte-prefix codegen, not the type. WHY IT MATTERS BEYOND SizeOf: unlike sets, a fixed string is NOT a zero-extension of FPC's — the length word is at the FRONT and a different width — so there is NO truncating-copy trick, and every fixed string in a typed file is a genuine conversion. Implementing this makes `string[N]` for N<=255 byte-identical to FPC, which makes records containing one BLIT instead of marshal. Note pxx accepts `string[256]` (264) and `string[1000]` (1008) where FPC rejects both: frozenstring is a strict SUPERSET, and the 1-byte prefix IS the 255 ceiling, so the wide kind must stay for N>255."
---

# The real `tyShortString`, and why it is cheaper than it looks

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
