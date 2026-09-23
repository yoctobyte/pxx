---
slug: feature-a-non-float-str-on-the-bare-esp-profile
track: A
tags: [S]
type: feature
prio: 40
status: open
owner: ""
created: 2026-09-24
found-by: frank (frankb-8e, while pricing the uses-builtin cascade)
blocked-by: []
summary: "MECHANISM: `Str` -- the Pascal statement, no `uses` clause involved -- lowers through TextStrArg (pasparser_stmt.inc:4106), which resolves a formatter by FindProc; the bare ESP profile links no `builtin`, so every arm fails and the statement is refused for EVERY type, integer included, on all four ESP targets. THE NAMED CONSUMER IS THE RTL'S OWN ASSERT, WHICH IS WHY THIS IS p40 AND NOT p20: espassert.pas exists solely so a bare assertion can speak, and hand-rolls a UART writer to do it -- and then it can only speak in CONSTANTS. `Assert(n > 99, 'count too low')` compiles and boots; the same assertion carrying the value that failed does not, because the `Str(n, s)` that would produce the text is refused. An assertion that cannot report the number it tripped on is the weakest useful form of the feature this profile already paid for. The parent ticket [[feature-bare-esp-supports-uses-builtin]] set its own ranking test as `nobody has yet named a program that wants builtin on a bare boot`; this names one, and it is in-tree. SCOPE IS THE NON-FLOAT ARMS ONLY AND THE BOUNDARY IS MEASURED, not aesthetic: the five routines are pure AnsiString + integer arithmetic with no float, Variant, syscall or filesystem in their closure, and bare already carries AnsiString (3,768 B code=). The float arm stays refused because StrFloat needs PxxSciDigits17 and therefore softfloat, which the bare path deliberately skips so a float-free MCU program does not pay ~54-64 KB of flash -- priced at +89,116 B against +23,724 B for the integer arm. SHAPE IS PRESCRIBED BY PRECEDENT, NOT INVENTED: espassert.pas is the same pattern (on-demand token scan, target-gated, never ambient) and its own header states the rule for this exact moment -- `the shared-code alternative is an include both units pull, and that is the right shape ONLY once something else needs it; one caller is not a second path`. A second caller now exists, so the five bodies move to an include that `builtin.pas` and a new bare-only unit both pull, rather than being copied. Copying would mint the twin-spelling defect this tree keeps paying for. WHAT WOULD RETIRE IT: a bare fixture whose assertion message CONTAINS a formatted integer, booting on esp32c3 and esp32s3 under Espressif qemu and matching its x86-64 oracle byte-for-byte -- the same three-line oracle shape test-esp-bare already uses for Assert, because on this profile `ok:` from the compiler is not a result."
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

# Umbrella

[[meta-a-pxx-produces-linkable-code]]
