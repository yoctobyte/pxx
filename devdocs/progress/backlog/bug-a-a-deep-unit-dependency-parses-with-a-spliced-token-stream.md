---
track: A
prio: 70
type: bug
blocked-by: []
summary: "Two units before a third with a deep transitive chain makes the parser hit EOF of a transitively-loaded unit still expecting `implementation`, with lookahead showing ANOTHER unit's generated tokens. Deterministic, -O-independent, and it is what makes test/lib_synapse.pas red. Platonic repro is 4 lines."
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
[[bug-t-a-skipped-lib-test-job-reports-green-and-manufactures-a-false-last-good]]
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
