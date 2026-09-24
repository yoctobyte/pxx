---
slug: feature-a-non-float-str-on-the-bare-esp-profile
track: A
tags: [S]
type: feature
prio: 30
status: done
owner: frankb-8e
created: 2026-09-24
found-by: frank (frankb-8e, while pricing the uses-builtin cascade)
blocked-by: []
summary: "DONE 2026-09-24 -- BUILT, BOOTED ON BOTH CHIPS, UART BYTES EQUAL TO THE x86-64 ORACLE. `Str` now works on the bare ESP profile for every NON-FLOAT type on all four ESP targets; the float arm stays refused with its own diagnostic, deliberately. The five non-float formatters moved to compiler/builtin/strfmt.pas, which `builtin` uses and the bare profile pulls directly via a new needsStrFmt flag -- A SHARED UNIT, NOT THE INCLUDE THIS TICKET PRESCRIBED, because compiler/builtin/*.inc is not a Makefile dependency (COMPILER_INC globs builtin/*.pas) so an include there would have been a silent stale-build source. Regression row test/test_esp_bare_str.pas in test-esp-bare asserts TEXT and not compilation; positive control is the PINNED pre-split compiler refusing the exact test file on both chips while HEAD accepts it. Containment: `code=` identical in every row and a program that never calls Str is BYTE-IDENTICAL; the cost is +40 bytes of data, FIXED per program rather than per arm. INERT FOR $(PXX_STABLE) CONSUMERS UNTIL THE NEXT PIN -- the pinned compiler resolves its own builtin snapshot, so Track B/E is not broken by the split, but neither does it get the fix. ONE PREMISE OF THIS TICKET WAS CORRECTED BY MEASUREMENT: the pull site says `builtin` uses frozen-string concat the ESP backends cannot lower, which read straight says these five could not work either -- they do, and that comment is now scoped in place with the still-unmeasured part (whether `uses builtin` as a WHOLE compiles on bare) named. ORIGINAL MECHANISM:  `Str` -- the Pascal statement, no `uses` clause involved -- lowers through TextStrArg (pasparser_stmt.inc:4106), which resolves a formatter by FindProc; the bare ESP profile links no `builtin`, so every arm fails and the statement is refused for EVERY type, integer included, on all four ESP targets. THIS IS NOT A BARE FEATURE REQUEST AND MUST NOT BE READ AS ONE -- IT IS THE BARE PROFILE'S ONLY DEBUGGING INSTRUMENT BEING UNABLE TO REPORT A VALUE. espassert.pas exists solely so a bare assertion can be heard at all, and hand-rolls a UART writer to do it -- and then it can only speak in CONSTANTS. `Assert(n > 99, 'count too low')` compiles and boots; the same assertion carrying the value that failed does not, because the `Str(n, s)` that would render it is refused. A test vehicle whose assertions cannot say WHAT failed taxes every future bare investigation, which is a cost paid by whoever debugs the profile rather than by anyone shipping on it. PRIO 30, AND THE TENSION IS RECORDED BECAUSE A READER WILL CHECK THE NUMBER AGAINST THE RULING: the owner ruled 2026-09-23 that IDF is the assumed profile and bare is a test vehicle -- `the bare-bones compilation merely serves as test and has so many drawbacks that it serves niche cases` -- so bare work is not to be ranked as if it were the shipping target. It was filed at p40 on the consumer argument alone, which would have topped Track S; 30 puts it below the broader and partly-landed p35 on the same profile and above the p20 cascade it slices from. The parent ticket [[feature-bare-esp-supports-uses-builtin]] set its own ranking test as `nobody has yet named a program that wants builtin on a bare boot`; this names one, it is in-tree, and meeting that test is what moves it off p20 -- it is NOT an argument that bare has become a shipping target. SCOPE IS THE NON-FLOAT ARMS ONLY AND THE BOUNDARY IS MEASURED, not aesthetic: the five routines are pure AnsiString + integer arithmetic with no float, Variant, syscall or filesystem in their closure, and bare already carries AnsiString (3,768 B code=). The float arm stays refused because StrFloat needs PxxSciDigits17 and therefore softfloat, which the bare path deliberately skips so a float-free MCU program does not pay ~54-64 KB of flash -- priced at +89,116 B against +23,724 B for the integer arm. SHAPE IS PRESCRIBED BY PRECEDENT, NOT INVENTED: espassert.pas is the same pattern (on-demand token scan, target-gated, never ambient) and its own header states the rule for this exact moment -- `the shared-code alternative is an include both units pull, and that is the right shape ONLY once something else needs it; one caller is not a second path`. A second caller now exists, so the five bodies move to an include that `builtin.pas` and a new bare-only unit both pull, rather than being copied. Copying would mint the twin-spelling defect this tree keeps paying for. WHAT WOULD RETIRE IT: a bare fixture whose assertion message CONTAINS a formatted integer, booting on esp32c3 and esp32s3 under Espressif qemu and matching its x86-64 oracle byte-for-byte -- the same three-line oracle shape test-esp-bare already uses for Assert, because on this profile `ok:` from the compiler is not a result."
---

# Non-float `Str` on the bare ESP profile

Measured 2026-09-24 at `c4d759f5c5`, `compiler/pascal26` = `bb681c88af9f`.

## The pair that states the whole ticket

Bare `esp32c3`, same assertion, one difference:

```pascal
Assert(n > 99, 'count too low');            { ok: 22,512 B code, boots, prints }
Assert(n > 99, 'count too low: ' + s);      { needs Str(n, s) -> REFUSED }
```

```
pascal26:5: error: Str: StrInt not loaded
  near: Str ( n , s ) >>> ; Assert (
```

`espassert.pas` exists *only* so that a bare assertion can be heard — its header
records that the first draft reused `builtin`'s body, compiled on both chips and
**printed nothing**, so it hand-rolls a write to the UART0 TX FIFO at
`$60000000`. That work was done so assertions could speak. They can speak only
in string literals.

**This is the program the parent ticket asked for.** Its ranking test is
*"Nobody has yet named a program that wants `uses builtin;` on a bare boot.
Rank it against that"* — and the program is the RTL's own assertion path.

## The ruling this is ranked against, and why 30 rather than 40

The owner ruled **2026-09-23** that IDF is the assumed profile and bare is a
test vehicle: *"the bare-bones compilation merely serves as test and has so many
drawbacks that it serves niche cases."* **Bare work is therefore not to be
ranked as if bare were the shipping target**, and this ticket was filed at p40
on the consumer argument alone, which would have put it above everything left on
Track S. That was wrong and the number is now 30.

**What survives the ruling is not a feature argument, it is an instrument one.**
Nothing here asks bare to do more; it asks the profile's *only* debugging
instrument to be able to say what failed. `espassert.pas` was built, and a UART
write hand-rolled inside it, precisely so a bare assertion could be heard — the
gap is that it can be heard saying only constants. A test vehicle whose
assertions cannot report a value taxes every future investigation **of the test
vehicle**, which is a cost borne by whoever debugs bare, not by anyone shipping
on it.

30 places it below
[[feature-a-one-guard-excludes-both-the-unimplementable-and-the-merely-adjacent]]
(p35 — broader, same profile, already partly landed) and above the p20 cascade
it slices from. **If you are re-ranking this, argue against the instrument
framing, not against the consumer count** — the consumer count is what moved it
off p20 and it is not a claim that bare has been promoted.

## Refused for every type, not just floats

All four ESP targets, `--esp-profile=bare`, identical:

| statement | bare | why |
| --- | --- | --- |
| `Str(n, s)`, `n: Integer` | `Str: StrInt not loaded` | `pasparser_stmt.inc:4152` |
| `Str(d, s)`, `d: Double` | `Str: StrFloat not loaded` | `pasparser_stmt.inc:4136` |
| `WriteLn(d)` | **warns and compiles** | no console; the statement has no result |

The `WriteLn` row is there as the control, and the asymmetry with it is
**correct** — see the parent ticket. `WriteLn` has no result, so dropping it
loses nothing observable; `Str` yields a value the program ships or compares, so
a warn-and-drop would be a silent wrong answer. Do not "normalise" these.

## Scope: the five non-float arms, and why the boundary is there

`TextStrArg` (`pasparser_stmt.inc:4106`) resolves one formatter per type via
`FindProc`. Five of its arms are bare-safe and one is not:

| arm | routine | `builtin.pas` | closure |
| --- | --- | --- | --- |
| string | `StrStrW` | `:1810` | AnsiString concat, `Length` |
| Char | `StrChar` | `:1798` | as above |
| Boolean | `StrBool` | `:1820` | calls `StrStrW` |
| signed ordinal | `StrInt` | `:1826` | `div`/`mod`, `Chr`, `Ord` |
| unsigned ordinal | `StrQWord` | `:1589` | as above |
| **float** | `StrFloat` | `:1978` | **`PxxSciDigits17` -> softfloat** |

The five carry **no float, no Variant, no syscall, no filesystem**, and bare
already links AnsiString (`code=3,768 B` for a concat program). The float arm is
excluded for a measured reason and not for tidiness: `PullSoftFloatBeforeBuiltinHeap`
(`frontend_prologue.inc`) skips bare deliberately so a float-free MCU program
does not pay ~54-64 KB of flash. Marginal `code=` on esp32c3 over an AnsiString
baseline: **integer +23,724 B, float +89,116 B.**

So the principle this establishes is narrower and better-founded than the parent
ticket's draft: **bare gets `Str` for everything except floats.**

## Shape — prescribed by `espassert.pas`, including the part about copying

`espassert.pas` is the precedent for giving bare one thing out of `builtin`
without the rest: an on-demand unit, pulled by a token scan, target-gated, never
ambient. The wiring is three lines plus a pull:

- `needsEspAssert` — declared `pasparser_prog.inc:1095`, cleared `:1191`, set by
  the token scan at `:1442`, pulled at `:2227`.
- **Note the second list.** `:2302` says *"THE ONE FLAG THE TWO LISTS DO NOT
  SHARE IS needsEspAssert"*, and `:2329` is the other list. A new flag must be
  considered against both, or it will work and then not work depending on which
  list decides.

**Do NOT copy the five bodies.** `espassert.pas`'s header already ruled on this
case, for itself, in advance:

> The shared-code alternative is an include both units pull, and that is the
> right shape ONLY once something else needs it — one caller is not a second
> path.

A second caller is exactly what this ticket adds. So the five bodies move into
an include that `builtin.pas` and the new bare unit both pull. Copying them
would mint five twin spellings, which is the defect class this tree pays for
repeatedly (`LINE_BUF_SIZE`/`PXXLineBuf`, `EspArena`'s two spellings).

**The spans are not contiguous** — `StrQWord` is at `:1589` and the other four
are at `:1798`–`:1850`, with a `CPURISCV32`/`CPUXTENSA` guard between them whose
own comment warns that a declaration whose body compiles out is a known bug
class. Two spans, and the extraction must not move a body across that guard.

## The containment control, which is not optional

`builtin.pas` is linked into every program on every target, and it is part of the
pin. The extraction must be a **no-op** everywhere else, and that is cheap to
assert the way frankS asserted it for the `builtinheap` half of
[[feature-a-one-guard-excludes-both-the-unimplementable-and-the-merely-adjacent]]:
compile a program exercising `Str` of a string, Char, Boolean, signed and
unsigned ordinal on x86-64 **before and after**, and `cmp` the binaries. Expect
byte-identical.

That control is not vacuous here: the same change must move a bare fixture from
`compiler error` to `ok`, so it demonstrably reaches output.

## Verification — the harness exists and both qemus are installed

`test-esp-bare`'s Assert rows (`Makefile:36612`) are the template, and the
three-line oracle shape there is deliberate: the compile stands alone so `make`
aborts on it, the run tolerates only its own expected rc, and `test -s` proves
the oracle has bytes before either chip boots — *"a comparison whose inputs were
never proven to exist cannot fail."*

- `tools/esp_run_bare.sh --chip esp32c3|esp32s3`, output diffed against the
  x86-64 build of the same source.
- Verified present on this box 2026-09-24:
  `~/.espressif/tools/qemu-{riscv32,xtensa}/esp_develop_9.2.2_20250817/`.

**The fixture must assert the TEXT, not compilation.** `espassert.pas`'s own
lesson is the one that applies: a draft compiled on both chips and printed
nothing, and *"only the serial bytes can tell a working Assert from a silent
one."* A row that only builds would pass over a `Str` that returns `''`.

Positive control to write beside it: a formatted value whose correct output
differs from the empty string **and** from the failure value. `Str(0, s)` is a
poor choice — `'0'` is one character and a blank result is zero characters, but a
padded-width row can collide. Use a negative number and `Low(Int64)`, which
`StrInt`'s body calls out as the case that once produced just `"-"`.

## Relationship to the two adjacent tickets

- [[feature-bare-esp-supports-uses-builtin]] (p20) is the **whole cascade** —
  making `uses builtin` compile, Variants included, open-ended by its own
  description. This is a bounded slice that does not need it, and it does not
  retire it. Its ranking test is met **for this slice only**.
- [[feature-a-one-guard-excludes-both-the-unimplementable-and-the-merely-adjacent]]
  (p35, frankS) is the **sibling in the other unit**: `builtinheap` is a unit
  bare DOES link, whose regions are excluded positionally. This ticket is about
  `builtin`, which bare does not link at all, so the mechanisms are different
  and neither fix delivers the other. They do collide on one point and it is
  worth reading before starting: that ticket's "one exclusion that is NOT
  positional" is the same float/softfloat boundary drawn here, and it reaches
  the same answer independently — a guard keyed on whether the program uses
  floats at all.

## RESOLVED 2026-09-24 (frank, frankb-8e) — built, booted on both chips, UART bytes equal to the x86-64 oracle

`Str` now works on the bare ESP profile for every non-float type, on all four ESP
targets. The float arm stays refused, deliberately, with its own diagnostic.

Compiler `af40370a8a91d298`, `make compiler/pascal26` -> `converged after 1
round(s)`; `tools/gate.sh quick` -> `gate: GREEN (exit 0)`, self-host fixedpoint
PASS.

### What was built, and where it DIVERGES from what this ticket prescribed

The ticket said: extract the five bodies into an **include** that `builtin.pas`
and a new bare-only unit both pull. **I built a shared UNIT instead**, and the
reason is not preference:

- `compiler/builtin/*.inc` does not exist as a category, and the Makefile's
  `COMPILER_INC` globs `compiler/builtin/*.pas` — **a new `.inc` there would not
  have been a build dependency**, so editing it would not have triggered a
  rebuild. An include that is not a dependency is a silent stale-build source.
- Two unit identities over one body is a second path by another name. One unit,
  `strfmt`, is one home.

So `compiler/builtin/strfmt.pas` holds the five; `builtin.pas` `uses strfmt` for
its own `StrFloat`, which calls `StrInt`. The ticket's *anti-copying* rule was
the right instinct and is honoured — there is exactly one body of each.

### The wiring

- `needsStrFmt` in `pasparser_prog.inc`: declared beside `needsEspAssert`,
  cleared beside it, set by extending the **existing** `str`/`val` token scan
  rather than adding a neighbour to it, and pulled at `:2369` **before**
  `builtin`, which uses it.
- `str` only, never `val` — `Val`'s body is still in `builtin`, so pulling
  `strfmt` for a Val-only program would cost a unit and resolve nothing.
- Pulled for `needsBuiltin` **as well as** for the bare flag, so the formatters
  are a direct program-level unit on every target rather than reached
  transitively. Whether a used unit's interface re-exports to `FindProc` is
  measurable and is measured, but making it structural costs nothing and removes
  the question.
- **The second list was checked, not assumed** — the ticket warned about it.
  `needsStrFmt` is added to the `needHeapUnit` condition (`strfmt` builds
  AnsiStrings, and the invariant there is "an ambient unit that is Pascal over
  managed strings needs builtinheap's bodies, full stop"). It is NOT added to the
  x86-64 emission list, for the same reason `needsEspAssert` is not: it can only
  be set under `EspBareBoot`, i.e. xtensa/riscv32, so it can never decide an
  x86-64 emission. It reaches that list transitively via `needHeapUnit` anyway.

### Verification — output equality, not compilation

The ticket said the fixture must assert the TEXT, because espassert's first
draft compiled on both chips and printed nothing. `test/test_esp_bare_str.pas`
is a runtime row in `test-esp-bare`, booted under Espressif qemu on esp32c3 and
esp32s3, UART bytes diffed against the x86-64 oracle. **Both chips: byte-for-byte
equal, 107 bytes.**

```
int=-4095
low=-9223372036854775808
qw=18446744073709551615
chr=z
bool=[   FALSE]
wid=[    42]
strw=[   hi]
```

Values chosen so a correct answer differs from the failure value `''` **and from
every other row**: `Low(Int64)` is the case `StrInt`'s body records as having
once produced just `"-"`, and a QWord >= 2^63 through the *signed* formatter
prints a minus sign, which is the only thing `StrQWord` exists for.

**POSITIVE CONTROL, run against a real pre-fix compiler rather than asserted:**
the pinned binary `4d148c23cc723afe` — which is this tree's own compiler from
before the split — refuses the exact test file on both chips with
`pascal26:51: error: Str: StrInt not loaded`, while HEAD accepts it. The
asymmetry is the control.

**BOUNDARY CONTROL:** `Str(d, s)` for `d: Double` on bare still answers
`Str: StrFloat not loaded`, and still compiles on x86-64. The float arm was never
in scope and is not silently enabled.

### Containment — measured three ways, and one of them is byte-exact

| program | pre-split (pinned) | post-split (HEAD) |
| --- | --- | --- |
| never calls `Str` | `code=19093B data=4384B` | **byte-identical binary** |
| one `Str` arm | `code=21546B data=6896B` | `code=21546B data=6936B` |
| eight `Str` arms | `code=24368B data=6936B` | `code=24368B data=6976B` |

**`code=` is identical in every row; a program that never calls `Str` is
byte-identical.** The cost is **+40 bytes of `data`, FIXED** — the same for one
arm as for eight, so it is one additional unit descriptor and not duplicated
literals. That distinction is the reason the one-arm row is in the table: a
per-arm cost and a per-unit cost are indistinguishable from the eight-arm row
alone.

`gate.sh quick`'s `pinned builds live lib/rtl` passes, and the pinned compiler
resolves its OWN snapshot at `stable_linux_amd64/default/builtin/` rather than
the live tree — verified with `--where`. **So Track B/E are not exposed:**
`$(PXX_STABLE)` consumers keep working against the split tree. The corollary is
the usual one — **this fix is INERT for `$(PXX_STABLE)` consumers until the next
pin**, and a bare program wanting `Str` must be built with `compiler/pascal26`
until then.

### One measured correction to this ticket's own premise

The ticket scoped the five arms as bare-safe by reading their closures. The pull
site's comment says `builtin` uses *"frozen-string concat, which the ESP backends
cannot lower"* — which, read straight, says the five could not work either. **It
is not true of these five, and that was measured before the split, not after:**
`' ' + r`, `'-' + digits`, `Chr(...) + digits`, the indexed store `r[1] := c` and
the QWord digit loop all compile and boot on both chips. That comment is now
scoped in place, with what is still unmeasured named explicitly — nobody has
established that `uses builtin` as a whole compiles on bare, and Variant and Val
were not part of this.

### Docs

`docs/targets/esp32.md`'s bullet said `Str` was unavailable for any type. **I
wrote that bullet earlier the same day and it is now false** — rewritten, with
both snippets compiled on bare esp32c3 and the documented float refusal
reproduced verbatim, per Track D's rule that snippets are verified by compiling
them.

# Umbrella

[[meta-a-pxx-produces-linkable-code]]

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
