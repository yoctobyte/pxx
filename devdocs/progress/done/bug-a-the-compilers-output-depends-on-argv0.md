---
prio: 70
track: A
status: done
owner: frank1-ACP
---

# The compiler's output depends on how the compiler was invoked (argv[0])

- **Type:** bug (Track A — reproducibility / emitted string pool)
- **Found:** 2026-08-20 while triaging [[regression-test-core-compiler-4]]
- **Symptom it was reported as:** the `--threadsafe` self-host job in `make test`
  compares two compilers built from the same source and they differ by 32 data
  bytes. Filed as a threadsafe determinism bug. `--threadsafe` has nothing to do
  with it.

## What actually happens

One binary, one source, two invocations, four different outputs:

```
./compiler/pascal26            compiler/compiler.pas  ->  data=227072B
compiler/pascal26              compiler/compiler.pas  ->  data=227064B
/home/neo/frank1/compiler/...  compiler/compiler.pas  ->  data=227136B
/tmp/.../aaa (a copy)          compiler/compiler.pas  ->  data=227040B
```

The emitted binary carries the path the compiler was invoked as. `strings` on
the two outputs:

```
out-rel:  ./compiler/builtin/builtin.pas   ./compiler/../lib/asmcore/asmcore_x64.pas
out-abs:    compiler/builtin/builtin.pas     lib/asmcore/asmcore_x64.pas
```

## Root cause

`ParseUsesUnit` keys "have I already compiled this translation unit?" on the
resolved file path, and interns that key with **`InternStr`**
(`compiler/parser.inc`, `pyFileIdx := InternStr(path)`; the C side does the same
at `cparser.inc`'s `CCheckPascalUnitCollision`).

`InternStr` is not a hash. It hands back a stable index *and appends the text to
`Data[]`* — the emitted string pool. So a key the compiler only ever compares
against itself was being written into every binary we produce. And the key text
begins with `ExeDir`, which is `GetFilePath(ParamStr(0))`, so the emitted bytes
follow the compiler's own invocation path.

This is `normalise-dont-special-case`'s neighbour: one mechanism (the emitted
string table) was serving two concepts (a runtime string constant, a
compile-time identity key) that only look alike.

## Why it surfaced as a --threadsafe bug, and only there

Both self-host chains in `make test` compare generation N against N+1. The plain
chain runs *both* generations from `$(TESTTMP)` under names of equal length
(`pascal26-self`, `pascal26-next`), so the interned paths matched **by
coincidence** and the job was green. The threadsafe chain starts from
`./compiler/pascal26` and continues from `$(TESTTMP)/pascal26-threadsafe-self` —
two different `ExeDir`s, so the strings differ and `cmp` fails.

The gate was never proving what it appeared to prove: it proved the compiler
reproduces itself *when invoked twice by the same path*.

## Fix

A compile-time key table with no `Data[]` side:

- `KeyStrs` / `KeyCount` (`defs.inc`), `MAX_KEYS = 1024`
- `InternKey` (`emit.inc`), next to `InternStr` and with the rule written down:
  never `InternStr` anything derived from a resolved file path
- `CompiledUnitFile` now indexes `KeyStrs`; its two readers
  (`parser.inc` dedup, `cparser.inc` collision refusal) follow

## Verified

- five spellings of the compiler path (relative, bare, absolute, a copy under a
  short name, a copy under a long one) now emit **one identical binary**,
  md5 `771a082e43d4ee1acc27400ae422a55d`
- the reported job by hand: `ts-self` and `ts-next` byte-identical, both
  `data=226912B`
- `make compiler/pascal26` converges; `tools/gate.sh quick` GREEN
- the behaviour the interning existed for is intact: `test_nilpy_module_identity`
  (`body-ran` once), `test_nilpy_dotted_package_import`,
  `test_nilpy_quoted_import`, `c_pasunit`, `c_pasunit_twice`,
  `c_pasunit_collide_fail` (the refusal still names both files),
  `c_pasunit_case_fail`

## Left open deliberately

Every emitted binary still carries ~80 other `InternStr` keys that no runtime
reads — unit names, import aliases, py stdlib alias rows. They are stable text,
so they cost bytes rather than reproducibility, and sweeping them is a separate
cleanup. `CMarkTokModule` (`parser.inc:103`) interns a C module *path* and is
the one member of that set that could reproduce this bug for C compiles whose
`lib/crtl` resolves through `ExeDir`; unproven, not fixed here.

## Log
- 2026-08-20 — resolved, commit 3b0a886e9.
