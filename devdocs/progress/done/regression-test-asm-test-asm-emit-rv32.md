---
prio: 70
track: A
status: done
owner: frankA
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 9 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-asm#src:test/test_asm_emit_rv32.pas red at 108ac182bed6 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host seven). Untriaged.
- **Found:** 2026-08-30T05:56:04Z
- **Test source:** test/test_asm_emit_rv32.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-asm#src:test/test_asm_emit_rv32.pas'` at 108ac182bed6cd40244fd24108d6664d6cf1b2f0

## Range
> **The named sha `108ac182bed6` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `108ac182bed6`, last good `c951ec710b33`, 2 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:43: error: undefined variable (AIntToStr)
pascal26:44: error: expected comma or close parenthesis
(tail)
pascal26:43: error: undefined variable (AIntToStr)
  in: compiler/rv32enc.inc
  near:  what   displacement   AIntToStr >>>  v  
pascal26:44: error: expected comma or close parenthesis
  in: compiler/rv32enc.inc
  near: v    is outside the encodable range   AIntToStr >>>  lo  

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

## 2026-08-30 (coordinator) — RETRACKED P → A, on the error's own text

The auto-file guessed **P** from the test path, and the banner in this ticket says
plainly that the guess is what the ranker reads. The guess is wrong, and the
failing line says so without needing a repro:

```
pascal26:43: error: undefined variable (AIntToStr)
  in: compiler/rv32enc.inc
```

`AIntToStr` is defined in `compiler/util.inc`, pulled in at `compiler/compiler.pas:64`
— *"shared helpers owned by no frontend/backend"*. So this is **an include-order
fault in the compiler's own build, in a reduced configuration**: `rv32enc.inc`
calls a helper that is not in the stream yet. Nothing about it is the Pascal
frontend. Lane **A**, S-flavoured (riscv32 encoder); related to
`feature-a-build-a-reduced-compiler-by-selecting-frontends-and-targets`, which
already names this test.

**Why the retrack matters more than the fix here.** At `track: P` and `prio: 70`
this sat near the head of a queue whose agents own `pasparser_*.inc` and would
have opened it, found `compiler/rv32enc.inc`, and handed it back — while the lane
that owns the file never saw it. **A guessed track does not read as a guess in
`ready` output; it reads as a priced decision.** Retracked on the error text, not
on a hunch; if the guess was right after all, the evidence to overturn this is one
grep.

**Not re-verified at HEAD by me.** Track T reports it STILL-RED on every native
report from 06:57Z to 08:45Z, so it is standing rather than flaky, but the
attributing sha `108ac182bed6` is itself a `tstate-ticket(...)` commit — a
docs-only change that cannot have caused this. **A tstate red attributes to the
sha it swept, not the one that caused it.** Whoever takes this bisects; do not
start from that sha.

## 2026-08-30 (frankA, Track A) — RESOLVED: the harness's mock environment, not the compiler's build

**Reproduced at HEAD** (`4413c141a`, self-hosted binary `aa78a7faf63a`, `converged
after 1 round(s)`):

```
./compiler/pascal26 -Fucompiler test/test_asm_emit_rv32.pas /tmp/.../rv32emit
pascal26:43: error: undefined variable (AIntToStr)
  in: compiler/rv32enc.inc
```

**It is not an include-order fault in the compiler**, which is what the error text
suggests and what the coordinator's read proposed. `make compiler/pascal26`
converges at this sha: `util.inc` is pulled in at `compiler.pas:64` and
`rv32enc.inc` at `:81`, so in the real build `AIntToStr` is in scope 17 includes
before its call site. The compiler was never broken.

The failing program is **`test/test_asm_emit_rv32.pas`**, a standalone oracle
harness that mocks the byte sink (`EmitB`/`EmitI32`/`Patch32`/`Error`) and then
`{$include}`s the real shipped `compiler/rv32enc.inc` to assert its bytes against
`llvm-mc`. Its mock environment is hand-rolled, so **every helper an included
compiler file grows must be mocked by hand too** — and `2f81d8008` gave
`rv32enc.inc` a `RISCVRelCheck` whose `Error()` text formats the offset with
`AIntToStr`. The bisect is exactly right; the bad commit is a good fix that
outgrew a mock.

**Fix:** an `AIntToStr` mock next to the `AppendChar` mock already in that file
(`Result := IntToStr(n)`; the harness `uses SysUtils`, and exact over the Integer
range). Including `util.inc` for real is not available to the harness — that file
opens on `AppendChar`, which lives in `lexer.inc`, so it drags the lexer behind
it, which is why `AppendChar` is mocked by hand there in the first place.

The harness is green and the guard is on a live path, not dead code — `EmitBType`
calls `RISCVRelCheck` unconditionally, and the run reaches `PASS: jal forward` /
`PASS: beq backward` before `ALL RISC-V ASM EMIT TESTS PASSED`.

### Sibling sweep (root-cause-over-microfix): rv32enc.inc is the only exposure

The class here is *a harness-included compiler file calls a shared helper the
mock environment lacks*, and this file has now met it three times —
`AsmRv32ProcessInlineLine`, `InlineAsmLineHoleN` (both 2026-08-21, both recorded
in its own comments), and now `AIntToStr`. So the sweep is over the whole class,
not over riscv32:

- **Population:** the 7 compiler `.inc` files any harness `{$include}`s —
  `rv32enc.inc`, `asmtext_rv32.inc`, `x64enc.inc`, `asmtext.inc`,
  `asmtext_386.inc`, `asmtext_a64.inc`, `asmtext_arm32.inc`.
- **Sought:** all 4 of `util.inc`'s exports — `AIntToStr`, `RealTypeKind`,
  `TargetIsEspClass`, `SoftFloatMissing`.
- **Result:** 4 hits, all of them `rv32enc.inc:43-47`. Not a vacuous zero — the
  grep demonstrably finds this helper where it is called.

So no sibling harness is broken today, and no other harness needs a speculative
mock. `xtensaenc.inc`'s `XtensaRelCheck` — the template `RISCVRelCheck` was
mirrored from — uses `AIntToStr` the same way and is fine for the dull reason
that **no harness includes it**: `test_asmcore_xtensa.pas` links `lib/asmcore`
rather than `{$include}`ing the compiler's encoder.

**What is left standing, deliberately.** The five `test_asm_emit_*.pas` harnesses
duplicate their mock preludes (4 of the 5 carry their own copy of `AsmTextTrim`),
so the *concept* "the compiler's shared helpers, mocked for an encoder harness"
is served by five hand-rolled copies — the shape
`devdocs/dev/normalise-dont-special-case.md` warns about. It is not folded into a
shared prelude here: this is a live red at prio 70, the refactor puts five
currently-green harnesses at risk to close one ticket, and the rot is no longer
*silent* — `chore-a-sweep-the-unwired-tests-into-the-suite` wired all five into
`make test-asm`, which is why this surfaced the day the encoder changed instead
of years later. Filed as [[idea-a-fold-the-asm-emit-harness-mock-preludes-into-one]].

**Gate:** `make compiler/pascal26` (converged, 1 round) + the repro compiles and
prints `ALL RISC-V ASM EMIT TESTS PASSED`.
- 2026-08-30 — resolved, commit PENDING-COMMIT.
