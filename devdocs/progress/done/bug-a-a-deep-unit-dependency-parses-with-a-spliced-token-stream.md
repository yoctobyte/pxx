---
track: A
prio: 70
type: bug
blocked-by: []
summary: "Two units before a third with a deep transitive chain makes the parser hit EOF of a transitively-loaded unit still expecting `implementation`, with lookahead showing ANOTHER unit's generated tokens. Deterministic, -O-independent, and it is what makes test/lib_synapse.pas red. Platonic repro is 4 lines."
status: done
owner: frankA
---

# A deep unit dependency parses with a spliced token stream

Filed 2026-08-28 by frankB (Track B) while triaging
`regression-lib-test-lib-synapse`. **Not a Track B defect** — the library
sources involved are correct and compile standalone; this is unit-graph /
lexer-stack machinery, which is Track A's. Filed rather than worked around, per
the platonic-code rule.

## Repro — four lines, deterministic

Needs `external/synapse` (`tools/install_externals.sh`, pinned
`b3224c3d133a`).

```pascal
program z;
uses synacode, synaip, blcksock;
begin
end.
```

```
stable_linux_amd64/default/pinned --mimic-fpc \
  -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix z.pas z

pascal26:634: error: expected implementation section
  in: stable_linux_amd64/default/../../lib/rtl/sockets.pas
  near: n  end  end  >>>  procedure FlushGroup$126591
```

## The tell is in `near:`, and it is not a missing `implementation`

`sockets.pas` **has** an implementation section. Line 634 is at/near its end,
and the three tokens before the cursor (`n  end  end`) are that file's last
tokens. **The token AFTER the cursor is `procedure FlushGroup$126591`** — a
generated name with a numeric suffix, which appears nowhere in any source file.

So the parser ran off the end of one unit and kept reading into a *different*
unit's token stream. The diagnostic names the file it was in when it gave up,
not the file that is wrong. **Treat the reported line as the symptom's
location, never the defect's** — nothing is wrong with `sockets.pas` or with
`dns_cache.pas`.

## What varies, measured

Same shape reported against two different files depending on the uses list, which
is itself evidence the position is incidental:

| uses clause | result |
| --- | --- |
| `synacode, synautil, blcksock` | FAIL — `dns_cache.pas:270` (file is 269 lines: **past EOF**) |
| `synacode, synaip, blcksock` | FAIL — `sockets.pas:634` |
| `synacode, synautil, synaip, blcksock` | FAIL — `sockets.pas:634` |
| `synautil, synacode, blcksock` | FAIL |
| `blcksock, synacode, synautil` | **OK** |
| `synacode, blcksock, synautil` | **OK** |
| `sysutils, synacode, blcksock` | **OK** |
| `synacode, synaip` / `synautil, blcksock` / `synaip, blcksock` — any pair | **OK** |
| `synacode, dns_wire_core, blcksock`, `typinfo, dns_wire_core, blcksock` | **OK** |

Reading of that table:

- **Two units must precede `blcksock`**, and `blcksock` must be **last**.
  Moving it first or middle cures it.
- It is not "any two units". Two of *our* units in front (`dns_wire_core`,
  `typinfo`) do not trigger it, and **prepending `sysutils` cures it** — which
  suggests what matters is the state of the unit table / file stack when
  `blcksock`'s deep transitive chain (`blcksock` -> `synsock` -> our `sockets` /
  `dns` -> `dns_cache`) is entered, not the identity of the units.
- Deterministic: three consecutive runs, identical line. Not load- or
  hash-order-dependent.
- **`-O`-independent**: `-O0` reproduces identically.
- `--mimic-fpc` is required only because without it `synsock.pas` cannot resolve
  `libc` at all (a separate, unrelated resolution gap) — it is not part of this
  defect.

## This is NOT a regression from the range it was filed against

`regression-lib-test-lib-synapse` names bad `c52fc389fd97`, last good
`aca7f699288e`, 9 commits. Measured, all four `lib/` commits in that range are
mine and **all are innocent**:

- v388 (`e8b72f8afeb6`) and v389 (`325b4479070a`) fail **identically**, so the
  pin did not carry it in (this was the coordinator's hypothesis 1 — falsified
  in one command, no bisect).
- Building the *true* last-good state — `aca7f699288e`'s own `lib/` and `test/`,
  compiled by v388, the pin actually in force then — **also fails**.

The bug predates the range. See
[[bug-t-a-skipped-job-is-passlike-so-it-becomes-a-false-last-good]]
for why it looked like one.

## Gate

Track A: `make compiler/pascal26` (self-host fixedpoint) + the 4-line repro
above compiling. Worth adding the minimal `uses` triple as a regression test
once fixed — it needs `external/synapse`, so guard it the way `lib_synapse` is
guarded, but see the sibling ticket first: that guard is what hid this.

---

## CORRECTION to the `near:` evidence — measured by frank-coordinator, 2026-08-28

**Do not chase "`FlushGroup$126591` is a generated name that appears in no source
file."** That premise is false, and so is the negative result offered against it.
Four measurements, all one grep each:

1. **`FlushGroup` is a real routine** — `lib/rtl/sockets.pas:448`,
   `procedure FlushGroup(var arr: array of Integer; var cnt: Integer);`, a
   **nested** routine inside an enclosing one. It is not absent from the sources;
   only the `$126591` is appended.

2. **There IS a Pascal-side minter of the `Name$<number>` shape**, at
   `compiler/pasparser_decl.inc:6409`:
   ```pascal
   mangled := nestedName;
   AppendChar(mangled, '$');
   mangled := mangled + MangleSuffix(nestedStart);
   mOff := NestStrOff(mangled); mLen := Length(mangled);
   Tokens[nameTokIdx].SOffset := mOff;
   Tokens[nameTokIdx].SLen := mLen;
   ```
   A `+ '$' +` grep misses it because it uses `AppendChar`. Its own comment: *"Mangle
   the routine to a unique name so the lift descriptor and forward-completion
   can't collide with another routine (the in-place forward decl and the stashed
   definition share this single rewritten name token)."*

3. **`MangleSuffix(n: Integer)` renders an integer as decimal**
   (`pasparser_decl.inc:5979`) and is called with `nestedStart` — **a token
   index.** So `FlushGroup$126591` is the ordinary, expected mangled name of a
   real nested routine, and `126591` is its starting token index in the combined
   stream. Nothing about it is anomalous.

4. **Both reported lines are exactly EOF+1**:

   | file | length | reported |
   | --- | --- | --- |
   | `lib/rtl/sockets.pas` | 633 | **634** |
   | `lib/rtl/dns_cache.pas` | 269 | **270** |

### What this does to the ticket

**The `near:` context is NOT evidence of reading another unit's token stream** —
it is a correctly-mangled local nested routine, and the "generated name in no
source file" reading should be struck. **The real evidence of splicing is item 4:
the parser runs a unit to exhaustion and reports the line after the last one**,
i.e. an unexpected-EOF position, in a *different* file from the one whose tokens
are in view.

**The machinery to suspect is the one in item 2**, and it is the tighter lead:
that mangler **mutates the token array in place** (`Tokens[nameTokIdx].SOffset`,
`.SLen`) and is exercised by `sockets.pas`, which has nested routines, while the
failure is *attributed* to `dns_cache.pas`, which is a different file in the same
`uses` chain. In-place token rewriting plus a wrong file attribution at EOF is a
much narrower hypothesis than "the parser wandered into another unit."

**Credit where the reasoning was right:** frankA (standing down, two greps, offered
with its uncertainty attached) predicted that if the number were not a
specialization alias it would be *"a token index or source offset rather than a
counter."* **It is a token index.** The prediction was right and the negative
result was wrong — the greps missed `AppendChar`. Recorded because the prediction
is the reusable half.

**Still unverified and NOT to be repeated as fact:** whether the in-place rewrite
is what desynchronises the file attribution. That is the next measurement, not a
finding. The ordering table above (only the triple, only with `blcksock` last,
cured by moving it or by prepending `sysutils`) remains the strongest constraint
on any explanation.

---

## BEFORE YOU START: the per-fix loop cannot see a broken bootstrap seed

Added by frank-coordinator 2026-08-28, after frankwasm hit it in `compiler/**`.

**`make compiler/pascal26` compiles with pxx, which accepts a call to a routine
defined LATER in the same include. FPC does not — and FPC is what bootstraps this
compiler.** So an edit that adds a call above its definition **breaks the
bootstrap seed while every commit stays green on the documented loop.**

Measured, not theorised: frankwasm's branch was red for **days** across several
commits (`WasmEmitCall` used at 912, defined at 1030), all green on
`make compiler/pascal26`, and it was caught only by `tools/gate.sh:219`'s FPC seed
canary, which lives in the **gate** and not in the loop.

**This ticket is a `compiler/**` edit.** If your fix adds a call above its
definition — likely here, since the suspect machinery is a token rewriter with
helpers — **run `tools/gate.sh quick` before you push**, and if it goes red on the
seed, fix it with forwards and **verify by building `compiler.pas` with `fpc`
directly**, not by inference.

---

## Measured 2026-08-29 (frankA) — the failing unit is **synsock**, and the mechanism is `PreScanPass`

Not fixed. Diagnosis banked and parked, with the position moved a long way and
one hypothesis left standing that I could not close.

### Everything the diagnostic told us about *where* is wrong, including the correction

The correction above was right that `FlushGroup$126591` is an ordinary mangled
nested routine and not evidence of splicing (this run mints `$128258` — a token
index, as predicted). But its replacement conclusion, *"the parser runs a unit to
exhaustion and reports the line after the last one, in a different file from the
one whose tokens are in view"*, is also not what happens.

`PXXDBG=a.srcmap:*` settles it in one run — **the token→file map is correct and
the attribution is right**:

```
tok=129561 srcline=634 lexing=FALSE tokcount=145285 -> lib/rtl/sockets.pas
[28] start=125429  unit sockets      [29] start=129615  unit netdb
```

Token 129561 really is inside `sockets`'s range. Nothing is misattributed. The
file is named correctly and is still not the file with the defect, because **the
unit being PARSED is `synsock`** — whose own tokens are [119862, 124005):

```
UDBG FAIL unit=synsock TokPos=129562 tokcount=145285
```

`synsock`'s interface parse ran ~5,500 tokens past the end of its own block,
through `syncobjs`, `palsync`, `palfutex`, `termio` and into `sockets`, and
stopped at the first `tkEOF` it met. So `sockets.pas:634` is where it *ran out of
stream*, and neither `sockets.pas` nor `dns_cache.pas` was ever the subject.

**Do not chase the reported file, and do not chase the mangled name.** Both are
now measured dead ends, and this is the second correction on that point.

### Why it runs off the end

`ParseSubroutine` decides header-only vs parse-a-body at `pasparser_proc.inc:1543`:

```pascal
if (CurTok.Kind = tkForward) or InInterface or PreScanPass then   { header only }
```

With `PreScanPass` **True** during a unit's interface, every routine header is
treated as a definition and the parser hunts for a body that is not there,
swallowing the rest of the stream. `ParseUnit` sets `PreScanPass := False` on
entry for exactly this reason, and says so:

> *"A used unit parses in its own normal (single-pass) mode: its interface is
> already forward-visible, so the enclosing program's pre-scan must not leak in
> and make ParseSubroutine skip the unit's bodies."*

Measured at the first routine header of `synsock`'s interface, failing vs passing
order, everything else identical:

| | `InInterface` | `PreScanPass` |
| --- | --- | --- |
| passing order | 1 | **0** |
| failing order | 1 | **1** |

The two runs are token-for-token identical for 18 interface declarations and
diverge at the first `function` header (`ssfpc.inc:332`), which is exactly the
first construct whose parse consults `PreScanPass`. The const/type sections
before it do not, which is why the failure looks like it starts late.

### Where the flag flips, and the part I could not close

Bracketing each interface-loop declaration narrows it to one call:

```
UDBG type-in  synsock line=90 ps=0
UDBG type-out synsock ps=1
```

`ParseTypeSection` over `ssfpc.inc:90` — `TSocket = longint; TAddrFamily =
integer; TMemory = pointer;`, three plain aliases — **enters with the flag clear
and returns with it set.**

**And nothing on that path writes it.** All **19** `PreScanPass := ` sites in the
tree live in `ParseUnit` or `ParseProgram` (`pasparser_proc.inc`,
`pasparser_prog.inc` — no other file has one; verified with a full grep, not a
truncated one). Probes on `ParseUnit`'s entry *and* its restore show **neither
fires inside that window** — no nested unit is parsed, and none exits early
leaving the flag raised, which was my first hypothesis and is disproved.

So the value changes with no assignment executing. The leading hypothesis is
therefore a **stray write clobbering the global** — which would also explain the
two properties nothing else does: the failure is deterministic, and it depends on
the *uses ordering*, i.e. on how many tokens precede the unit. `-O`-independence
(recorded above) does not argue against it.

**This is a hypothesis, not a finding, and it must not be repeated as one.** The
next measurement is a canary: place a known-valued global adjacent to
`PreScanPass` and see whether it is corrupted in the same window; if it is, hunt
the writer (an array bound, most likely in the token machinery, since the trigger
scales with stream size). If it is not, the flag has a writer I have not found
and the grep needs widening beyond `PreScanPass := `.

### Confirmed as still true from the ticket above

- Deterministic, ordering-dependent, and the minimal pair is three units with
  only the order changed: `synacode, synaip, blcksock` FAILS,
  `synacode, blcksock, synaip` PASSES.
- The `--mimic-fpc` flag is incidental.

### Two unrelated things measured on the way

1. **`PXX_HOME` is not honoured.** `--where` advertises it as tier 2, overriding
   the exe-dir defaults, but pointing it at a copied RTL changed nothing — the
   `in:` path still named `compiler/../lib/rtl`, and *removing* `sockets.pas`
   from the `PXX_HOME` tree did not even produce "unit not found". This blocked
   the obvious experiment (edit a copy of the RTL rather than Track B's files)
   and is worth its own ticket.
2. **The interface loop's terminator is case-sensitive.**
   `pasparser_proc.inc:4763` ends the interface on
   `(CurTok.SVal = 'implementation') or (CurTok.SVal = 'Implementation')` — two
   hand-listed spellings in a case-insensitive language, where every neighbouring
   test uses `CaseEqual`. `IMPLEMENTATION` would run a unit off its own end with
   this exact symptom. Not this bug (ssfpc.inc spells it lowercase), and not
   fixed here to keep this session's change set at zero.

### State

**No compiler change was made.** Every probe was reverted; the tree is clean at
HEAD and the repro still reproduces (binary `0750a098d055`). `external/synapse`
installed from `tools/install_externals.sh`; the pin `b3224c3d133a` resolves.

---

## FIXED 2026-08-29 (frankA) — an out-of-bounds write into the global after the array

Resumed from the park above. The banked diagnosis was right as far as it went and
its leading hypothesis was correct: **a stray write clobbering `PreScanPass`.**

### The write

`VisibilityAllows` (`symtab.inc`) memoizes unit visibility in

```pascal
VisCacheVis : array[0..MAX_UNITS] of Boolean;   { MAX_UNITS = 256 }
```

It range-checks two of its three indices and missed the third:

```pascal
  if (curUnit + 1 > MAX_UNITS) or (declUnit + 1 > MAX_UNITS) then ...   { guarded }
  ...
  v := UsesEdgeTo[i];
  VisCacheVis[v + 1] := True;                                           { NOT guarded }
```

Instrumented, the failing repro writes at **[257], [258], [259]** of an array
ending at [256]. The three globals declared immediately after it, in order:

| index | global | effect |
| --- | --- | --- |
| 257 | `WarnIgnoredDirectives` | spurious diagnostics |
| **258** | **`PreScanPass`** | **this bug** |
| 259 | `GenericMethodBuffered` | corrupts generic method buffering |

A `True` in `PreScanPass` mid-parse makes `ParseSubroutine` treat every interface
routine header as a definition, so the unit runs off its own end hunting a body
and dies at the next `tkEOF` with `expected implementation section`, naming a
file it was never parsing. Everything the two earlier framings chased —
`sockets.pas`, `dns_cache.pas`, the mangled name, the token map — was downstream
of one out-of-bounds boolean.

### Why it depended on `uses` ORDER, which is the part worth keeping

These indices are **`Strs[]` indices**, not unit ordinals — the function's own
header says so (*"Strs[] indices offset by 1"*). The array is sized by
`MAX_UNITS`, a unit **count**. Two domains conflated in one subscript.

`CompiledUnitCount` really is capped at 256 (`pasparser_proc.inc:3393`), so the
comment claiming this made the range check unreachable was *reasoning about the
wrong quantity*. A unit whose NAME interns past string slot 255 overflows, and
how many strings are interned before a given unit's name is decided by the order
its `uses` clause was walked. That is the whole ordering table in the ticket
above: not "two units before blcksock", but "this ordering pushes a unit name
past slot 255".

It also explains why it looked like a token-stream problem and was not, and why
it was `-O`-independent and perfectly deterministic.

### The fix

Range-check the edge target, and correct the comment whose premise was false.
Skipping an out-of-range target loses nothing: the answer read at the end is
`VisCacheVis[declUnit + 1]` and `declUnit` is already checked, so a query ABOUT a
unit past the cache takes the direct-scan early-out that already exists.

**Deliberately not done here:** separating the two domains (sizing the cache by
the string table, or keying it on a real unit ordinal) is the change that removes
the class rather than this instance. It is a bigger, riskier edit to a function
called from *every* symbol lookup, and it wants its own ticket rather than
riding along with a memory-corruption fix that needs to land now. Filed as
[[refactor-a-viscachevis-is-indexed-by-a-string-id-and-sized-by-a-unit-count]].

### Verification

| | baseline | fixed |
| --- | --- | --- |
| ticket's 4-line repro (`synacode, synaip, blcksock`) | `sockets.pas:634` | compiles |
| `test/lib_synapse.pas` | `dns_cache.pas:270` | compiles, output matches expected exactly |
| `test/lib_synapse_transitive_unit.pas` | red | `ok` |
| passing order (`synacode, blcksock, synaip`) | compiles | compiles |

Both reported positions from the variance table are one defect and both are gone.
`lib_synapse` is the regression test and is already wired and guarded on
`external/synapse`; no new test is added, because reproducing this synthetically
needs ~260 units purely to push a name past the string slot.

Gate: `make compiler/pascal26` fixedpoint `da54007a8f92`, `gate.sh quick`,
`tools/forwardlint.py` clean **for this change** — it reports one pre-existing
FAIL in `compiler/rparser.inc:1293` (`RExprRecId` used at 1293, declared at 1507)
which is Track R's file at HEAD, not from this work, and is a live bootstrap-seed
break for everyone. Reported to the coordinator, not touched.

## Log
- 2026-08-29 — resolved, commit PENDING-COMMIT.
