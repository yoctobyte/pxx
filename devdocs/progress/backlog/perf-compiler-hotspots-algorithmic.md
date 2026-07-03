# Compiler self-compile hotspots — algorithmic wins (hash lookups, alloc, string append)

- **Type:** perf (compiler source — algorithms, NOT codegen)
- **Track:** A
- **Status:** backlog
- **Opened:** 2026-07-03 (pin-time optimization campaign)
- **Sibling:** [[feature-optimization-levels]] (codegen quality) — this ticket
  is the OTHER axis: make the compiler's own algorithms cheaper. Both shrink
  pin time; this one pays off even before any -O work because it also speeds
  the FPC-built binary.

## Data (2026-07-03, v162, `--proc-map` + perf)

Self-compile = 10.4s (self-built) / 5.1s (FPC-built same source). Perf on the
self-compile, symbolicated via the new `--proc-map` flag:

Full profile (4405 sample lines, per-proc cumulative — NOT the top-14
truncation of the first pass, which undersold everything):

| family | cum% |
|---|---|
| name lookup: FindProc 16.2 + ProcNameMatches 9.3 + StrEqual 8.2 + FindSym 7.4 + IsBlockVisible 1.6 + MatchProcCall 1.8 + CaseEqual 1.1 + ProcArityMatches 0.6 | **~46%** |
| string churn: PXXStrConcat 6.7 + PXXStrFromLit 2.4 + AppendChar 2.3 + AppendString 0.6 | ~12% |
| allocator: PXXAlloc 8.2 + PXXRealloc 0.4 | ~9% |
| IRVerify | 7.3% (keep — it catches lowering bugs) |
| IREmitMachineCode | 7.5% (real emission work) |

**Nearly half the self-compile is linear name scanning.** Item 1 alone
should take 10.4s to roughly 6s.

## Scope (each independently landable, gate = make test + byte-identical self-host)

1. **FindProc/FindSym/FindUMeth hash index.** Open-addressed hash over the
   name (case-folded per the proc's case rule) -> first candidate index;
   collisions fall back to today's scan from that point. CAUTION: FindProc
   returns the FIRST registered match (overload semantics depend on
   registration order) — the hash must preserve that (bucket stores
   first-by-order, or chain in insertion order).
2. **PXXAlloc**: size-class the free list (or at least make the zero loop
   8-byte-word based — it already is — and cap the first-fit walk with a
   segregated small-bin array). Measure before/after; the compiler's alloc
   pattern is many small same-size blocks.
3. **AppendChar/Concat**: geometric growth already exists for AnsiString;
   audit the compiler's hot builders (GetTokenStr* / name interning) for
   char-at-a-time loops that could be block moves.
4. Re-profile after each; stop when FindProc family < 2%.

## Non-goals

Codegen quality (that's [[feature-optimization-levels]]); changing IRVerify
coverage; anything that risks byte-identity gates beyond the one intentional
new binary per landing.

## Tooling (landed with this ticket's filing)

`--proc-map` flag: prints `PROC hexvaddr name` per routine to stderr —
symbolicates perf on pxx binaries (no .symtab). x86-64 static layout.
Recipe:
```
./compiler/pascal26 --proc-map compiler/compiler.pas /tmp/x 2>map.txt
perf record ./x ...; perf report --stdio   # then join offsets against map.txt
```

## Acceptance

Self-compile wall time measurably down (target: 10.4s -> ~6s from this ticket alone, dominated by item 1); `make benchmark` numbers recorded in the log; full make test green;
self-host byte-identical per landing.

## Progress — item 1 LANDED (2026-07-03): FindProc + FindSym hash indexes

Self-compile: **10.4s -> 5.9s** (pxx-built); FPC-built same source
5.1s -> **2.4s**. The lookup family vanished from the profile entirely.

- FindProc: FNV-1a buckets on the folded name, FIFO chains (= registration
  order) so first-match/overload-order semantics hold; converted FindProc,
  FindProcInUnit, HasNonOverloadProc, HasExactCaseSensitiveProc and all
  MatchProcCall/-InUnit phase loops. Procs are append-only — no unlink.
- FindSym: NEWEST-FIRST chains (walk = the linear `downto` innermost-scope
  order); scope exits go through SymRollbackTo, which pops the removed range
  off the bucket heads (descending idx = each is its bucket's current head,
  O(1) per pop).

LANDMINES hit (both cost a debugging round):
1. **Insert at the visibility point, not at name-assignment.** The Alloc*
   functions assign .Name ~80 lines before Inc(SymCount); the linear scans
   were bounded by SymCount, so a lookup made mid-registration must not see
   the in-flight slot. Insert now sits next to Inc(SymCount).
2. **`SymCount  := savedSC` with TWO spaces** (parser.inc ParseSubroutine,
   the main per-routine scope exit!) dodged every `SymCount :=` grep. A
   truncation that bypasses SymRollbackTo leaves dead indices chained ->
   chain cycles -> the self-compile spins in FindSym. Sweep rule: hunt
   assignment sites with `\s*:=` regexes, never fixed spacing.

Post-land profile (self-compile): PXXAlloc 14.7, IREmitMachineCode 14.4,
IRVerify 14.1, PXXStrConcat 13.2, AppendChar 4.5, PXXStrFromLit 4.4 —
items 2 (allocator) and 3 (string builders) are now the ticket's remainder.
