# The phase-4 shortstring flip, measured on all seven targets before the flag goes

**Measured 2026-09-03 by frankb-78 (Track A).** Compiler
`sha256 80ecb94023ebb96f83bd7133984b9903db9eb2588d91f645dc6192eea8615274`,
which is pin v402's binary; tree `a1f3a173f`, and **no commit has touched
`compiler/` or `lib/` since the pin** (`git log 9edd70d02..origin/master --
compiler/ lib/` is empty), so every number here is the pinned compiler's.

## Why this could be measured at all

**Building with `-dPXX_SHORTSTRING` today IS the flip.** The phase-4 change
re-types `string[N]` to `tyShortString` unconditionally in
`pasparser_decl.inc`, and that is exactly what the flag already does. So the
post-flip state is reachable *now*, one `-d` away, and the two modes can be
compared row by row.

**That window closes when the flag is deleted, not when the re-type lands.**
The flag's deletion is not the last mechanical step of the flip — it is the
moment the *before* stops existing. Everything below is unrepeatable after it.

## Population, stated

71 files: every `test/[a-z]*.pas` that declares `string[N]` or `shortstring`.
**The Makefile builds 13 of them with the flag** — 58 have never been run in the
mode the flip makes the default. Pascal only: the re-type is in the Pascal
parser, so the C, NilPy, Rust and Zig frontends are out of this population by
construction, and so are `examples/` and `lib/`.

## The matrix

`.` = both modes identical · `OUT` = same rc, different bytes · `RC` =
different exit code · `b-` = the OFF mode does not compile for that target
(**checked: every one of these also fails to compile in the ON mode, so no row
changes buildability**) · `~` = measured NOISE, see below.

The FPC column is FPC 3.2.2 on x86-64, and it is the column that decides:
`=OFF` the oracle matches today (**the flip regresses this row**), `=ON` the
oracle matches the flip (**the flip fixes this row**), `=BOTH`/`!BOTH` the two
modes agree, `n/a` FPC cannot build it. FPC built and ran **55 of 71**.

```
test                                             x86_ i386 aarc arm3 risc xten wasm  FPC
test_array_and_scalar_overload_binding           .    .    .    .    .    b-   b-    =BOTH
test_array_of_const_cross_unit_overload          .    .    .    .    .    .    .     !BOTH
test_char_array_field_is_a_string                .    .    .    .    .    b-   b-    =BOTH
test_char_into_shortstring_via_pointer           RC   .    .    .    .    .    .     =OFF
test_char_string_equality_both_directions        OUT  .    .    .    .    .    .     =OFF
test_clone_entry_with_a_hidden_result            b-   b-   b-   b-   b-   b-   b-    n/a
test_frozen_string_concat_operand                RC   RC   RC   RC   RC   RC   .     =OFF
test_indexing_a_string_value                     .    .    .    .    .    b-   b-    =BOTH
test_indexing_length_for_new_inc_positive        .    .    .    .    .    .    b-    =BOTH
test_loadfile_shortstring                        .    b-   b-   b-   b-   b-   .     n/a
test_out_parameter_of_a_managed_type_is_cleared  .    .    .    .    .    b-   b-    =BOTH
test_result_by_function_name_converts            .    .    .    .    .    b-   b-    =BOTH
test_rtti_reg                                    .    ~    .    .    .    .    .     n/a
test_shortstring_byte_prefix                     OUT  OUT  OUT  OUT  OUT  OUT  OUT   =ON
test_sizeof_array_field                          OUT  OUT  OUT  OUT  OUT  OUT  OUT   =ON
test_sizeof_stringn_matches_storage              .    .    .    .    .    .    .     !BOTH
test_string_n_array_field_stride                 OUT  OUT  OUT  OUT  OUT  OUT  OUT   =OFF
test_variant_widechar_store                      .    .    .    .    .    .    .     !BOTH

rows where the flip changes NOTHING on any target and FPC agrees: 53 of 71
```

## What the flip FIXES — and this is the case for doing it

Two rows, on **all seven targets**, and the oracle is on the flip's side:

- `test_shortstring_byte_prefix` — today `layout 5 0 0 0 0 0` / `prefix 8`;
  post-flip `layout 5 104 101 108 108 111` / `prefix 1`, **byte for byte what
  FPC 3.2.2 prints.**
- `test_sizeof_array_field` — `rec.S shortstring` is 16 today, 8 post-flip.
  **FPC says 8.**

## What the flip BREAKS — four rows, oracle on today's side

| row | targets | today (= FPC) | post-flip |
| --- | --- | --- | --- |
| `test_frozen_string_concat_operand` | **6 of 7** (all but wasm32) | `a..h`, `OK`, rc 0 | **SIGSEGV at step `d`** (rc 139; 203 on aarch64) |
| `test_string_n_array_field_stride` | **all 7** | `stride 1 / fits 1 / guard 1` | `stride 0 / fits 0 / guard 0` |
| `test_char_into_shortstring_via_pointer` | **x86-64 only** | `a/b/c/d`, rc 0 | `a FAIL` then **SIGSEGV** |
| `test_char_string_equality_both_directions` | **x86-64 only** | `1char eq TRUE TRUE` | `1char eq TRUE FALSE` |

**I have not diagnosed these and do not claim they share a cause.** Three
symptoms in one subsystem on one day is the shape that reads like one root
cause and is three.

## The direction I got wrong, on the record

I told franka-29 to expect the seven-target matrix to be *worse* than the
native four, because x86-64 is where a width defect is least likely to show.
**It is not worse, and two of the four are x86-64-ONLY** —
`test_char_into_shortstring_via_pointer` and
`test_char_string_equality_both_directions` are correct in both modes on i386,
aarch64, arm32, riscv32, xtensa and wasm32, and their i386 post-flip output is
byte-identical to the native pre-flip one. The cross sweep found **no new
defect** the native sweep had not already found. The floor claim was right —
four was a floor and the count did not go down — but the *reason* I gave for
expecting more was wrong for this change: the flip is a front-end re-type, not
a width or ABI change, so it does not have the native-only-blindness shape.

## THREE OF THE "FINDINGS" WERE THE INSTRUMENT

Before normalisation this sweep reported **16 more differing rows than exist**,
and every one of them looked exactly like a real flip difference: same test,
same target, a real byte difference, reproducible.

1. **12 rows on wasm32** — wasmtime prints ``failed to run main module `<path>` ``
   on a trap, and the two modes are two different *files*. Every trapping
   wasm32 row came back OUTPUT-DIFFERS with identical exit codes, differing
   only in the filename it was asked to run.
2. **3 more rows on wasm32** — the trap backtrace prints wasm code offsets
   (`0x10fb8 - <unknown>!<wasm function 145>`). Same trap, same functions;
   the offsets moved because the code changed size. Normalised only *inside*
   backtrace lines, so a program that legitimately prints hex is untouched.
3. **`test_rtti_reg` on i386** — dumps raw RTTI containing a **stack address**.
   Running the *same* binary twice changes 3 bytes of 47557. ASLR alone
   manufactured a per-target finding.

**The control that caught the third is the one to keep: run the OFF binary
twice and compare it with ITSELF.** All 33 differing rows were re-measured that
way; 32 STABLE, that one NOISE. A differential sweep with no self-comparison
cannot tell "this change did something" from "this program is not
deterministic", and both produce the same tidy table.

## Reproducing

`tools/flip-shortstring/` — `sweep.sh <out.tsv> <artifactdir> <target>` for
each of the seven, `oracle_fpc.sh` for the FPC column, `noise.sh` for the
self-comparison control, `matrix.py` to join them. **That directory dies with
the flag**: the commit that deletes `PXX_SHORTSTRING` should delete it in the
same diff, because after that there is no "off" mode and every script there
measures one thing twice. xtensa needs `--platform=posix
--xtensa-soft-mulhigh`, so its rows are not bit-identical to hardware for
multiplies; wasm32 emits `.wasm` and runs under wasmtime.

## The flip's own boundary, measured at both ends

`SizeOf` of a `string[N]` variable, x86-64:

| declaration | pxx today | pxx post-flip | FPC 3.2.2 |
| --- | --- | --- | --- |
| `string[20]` | 32 | **21** | **21** |
| `string[255]` | 264 | **256** | **256** |
| `string[256]` | 264 | 264 | *rejected* |

The flip lands exactly on FPC at both ends of the 1..255 range, and
**`string[256]` is unchanged in both modes** — which is the row that matters
for the RTL, because `lib/rtl/typinfo.pas:42` declares `TRttiStr =
string[256]` and its comment says the 256 is a kind selector rather than a
length. FPC rejects that declaration outright, so it is a pxx extension and
the re-type must keep its 1..255 bound or the RTL changes shape underneath the
compiler that builds itself.

## The self-host fixedpoint is not at risk from the SOURCE side

`compiler/compiler.pas` and its includes contain **no `string[N]`
declaration** — every one of the 24 files that mention `string[N]` or
`shortstring` mentions it in a comment, and `lib/rtl/typinfo.pas`'s
`string[256]` is outside the re-typed range.

**Established by building, not by grepping:**

```
./compiler/pascal26 -dPXX_SHORTSTRING compiler/compiler.pas <out>
  -> sha256 80ecb94023eb...  identical to the pinned compiler
```

A grep would have told you the same thing and would have been an argument
about comment syntax. This is the compiler compiled in post-flip mode coming
out byte-identical.

**What that does NOT establish:** a compiler with the re-type baked into
`pasparser_decl.inc` is a different binary that behaves differently for every
program it compiles. Its fixedpoint is `make compiler/pascal26` on the flip
commit, and it is franka-29's gate, not this measurement.


---

# AFTER THE FOUR FIXES — 2026-09-04, the same measurement re-run

All four defects above are closed (`b97167982`, `157b02b90`, `15b9abdcf`,
`8b6c2280d`). The identical sweep, on the same seven targets and both modes,
now reports **exactly two differing rows per target, and they are the two the
flip is supposed to change** — `test_shortstring_byte_prefix` and
`test_sizeof_array_field`, both `=ON`, meaning FPC 3.2.2 agrees with the
flip's answer and not with today's.

**Zero RC-DIFFERS on any target.** Before the fixes there were six, including a
SIGSEGV on six of seven.

```
test                                             x86_ i386 aarc arm3 risc xten wasm  FPC
test_array_and_scalar_overload_binding           .    .    .    .    .    b-   b-    =BOTH
test_array_of_const_cross_unit_overload          .    .    .    .    .    .    .     !BOTH
test_char_array_field_is_a_string                .    .    .    .    .    b-   b-    =BOTH
test_clone_entry_with_a_hidden_result            b-   b-   b-   b-   b-   b-   b-    n/a
test_indexing_a_string_value                     .    .    .    .    .    b-   b-    =BOTH
test_indexing_length_for_new_inc_positive        .    .    .    .    .    .    b-    =BOTH
test_loadfile_shortstring                        .    b-   b-   b-   b-   b-   .     n/a
test_out_parameter_of_a_managed_type_is_cleared  .    .    .    .    .    b-   b-    =BOTH
test_result_by_function_name_converts            .    .    .    .    .    b-   b-    =BOTH
test_rtti_reg                                    .    ~    .    .    .    .    .     n/a
test_shortstring_byte_prefix                     OUT  OUT  OUT  OUT  OUT  OUT  OUT   =ON
test_sizeof_array_field                          OUT  OUT  OUT  OUT  OUT  OUT  OUT   =ON
test_sizeof_stringn_matches_storage              .    .    .    .    .    .    .     !BOTH
test_variant_widechar_store                      .    .    .    .    .    .    .     !BOTH

rows where the flip changes NOTHING on any target and FPC agrees: 58 of 72
x86_64   BUILD-OFF-FAIL=1  OUTPUT-DIFFERS=2  SAME=69
i386     BUILD-OFF-FAIL=2  NOISE=1  OUTPUT-DIFFERS=2  SAME=67
aarch64  BUILD-OFF-FAIL=2  OUTPUT-DIFFERS=2  SAME=68
arm32    BUILD-OFF-FAIL=2  OUTPUT-DIFFERS=2  SAME=68
riscv32  BUILD-OFF-FAIL=2  OUTPUT-DIFFERS=2  SAME=68
xtensa   BUILD-OFF-FAIL=7  OUTPUT-DIFFERS=2  SAME=63
wasm32   BUILD-OFF-FAIL=7  OUTPUT-DIFFERS=2  SAME=63
```

The population is 72 rather than 71 because
`test_frozen_string_char_compare_shapes` was added with the fourth fix.

`~` is still the one measured-NOISE row (i386 `test_rtti_reg` prints a stack
address; the same binary differs from itself under ASLR). `b-` rows still fail
to compile in the OFF mode and were re-checked: none of them builds in the ON
mode either, so nothing changes buildability.

**The flip is now measurable as a pure improvement on this corpus:** two rows
move toward FPC, nothing moves away, and nothing that ran stops running.
