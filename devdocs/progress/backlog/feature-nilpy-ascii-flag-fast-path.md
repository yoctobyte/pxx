---
track: N
prio: 25
type: feature
blocked-by: []
summary: "Make pystr_isascii O(1) by reading PXX_FLAG_ASCII — but first MEASURE whether every string reaching it carries a header, because a false positive there is a silent wrong answer on exactly the non-ASCII strings the character surface exists for"
status: backlog
---

# The ASCII flag as an O(1) answer for `pystr_isascii`

- **Type:** feature (optimisation) — **Track N** (pylib) with a Track A
  measurement question about header coverage
- Follows [[feature-nilpy-text-string-kind]], which landed the character
  surface deliberately WITHOUT this.

## What is already there

Phase 1 (pinned v248) added the managed-block meta word and `PXX_FLAG_ASCII =
$0400`. `PXXStrFromLit` and `PXXStrConcat` stamp it for free — one `or` per byte
in a copy loop that already touches every byte — and `PXXHdrMeta(p)` reads it.
Its contract is stated in `builtinheap.pas`: **absence means UNKNOWN, never
non-ASCII**, so a consumer that does not find the flag must scan.

## What is missing

`pystr_isascii` scans, O(n), and it is now the gate in front of every
character-coordinate helper (`PyStrCharLen`, `PyStrByteOfChar`,
`PyStrCharOfByte`). The visible cost today: a **stepped** slice over a
non-ASCII string is O(n*k), because each of the k offset conversions walks the
string. Plain ASCII is unaffected in the sense that it is correct and takes the
byte path — but it still pays the O(n) scan to discover that.

## Why it was NOT done in the same change

Reading `PXXHdrMeta(p)` reads the word BEFORE the handle. For a block that never
carried a header — a static literal emitted straight into the data section, a
string that reached pylib from a Pascal caller, a frozen string — that read
returns whatever precedes it. A garbage value with bit `$0400` set is a **false
ASCII claim**, and a false ASCII claim makes every character helper take the
byte path and answer confidently wrong on precisely the strings this whole
surface exists for. Silent, and only on non-ASCII input, which is the hardest
combination to notice.

So this is a MEASUREMENT before it is an optimisation.

## The measurement to make first

1. Which string-producing paths actually stamp a header? `PXXStrFromLit` and
   `PXXStrConcat` do. Enumerate the rest — `SetLength` results, `Copy` results,
   frozen strings, `pystr_*` results, strings crossing from Pascal.
2. Is there a reliable way to tell a headered block from an unheadered one at
   the read site? `PXXHdrBase`'s `PXX_HEAP_DEBUG` path asks "is the kind byte a
   kind we know", and its own comment calls that weaker than the magic it
   replaced. If that is the only test available, the answer to this ticket may
   be "stamp universally first", not "read opportunistically".
3. Only then wire the flag into `pystr_isascii`, keeping the scan as the
   fallback for an unstamped block.

A `-dPXX_HEAP_DEBUG` run over `test_nilpy_str_counts_characters.npy` plus the
uforth corpus is the cheap version of steps 1–2.

## Gate

`make compiler/pascal26` + `test_nilpy_str_counts_characters.npy` still
byte-identical to its `.expected` + `tools/gate.sh quick`. A pin, since it edits
`compiler/builtin/**`. The uforth corpus is the performance oracle: it already
has a recorded CPython-identical output and a recorded runtime.
