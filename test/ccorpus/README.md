# Built-in C corpus for `tools/c_corpus_probe.sh`

Whole C **programs**, not cases. `tools/gcc_diff_probe.sh` already covers the
"does this call agree with the oracle" question over hundreds of small cases;
this directory answers a different one:

> **I changed something C-wide. Do substantial programs still build, run, and
> produce gcc-identical output — in two minutes, without the full suite?**

That gap is structural, not incidental. A Track C agent making a C-wide change
(the token stream, the preprocessor, the member parser) cannot run
`make test-zlib` / `test-lua` / `test-quickjs` — the no-full-suite hook refuses
them, correctly — so its evidence is whatever small tests it wrote plus a push
and a hope that Track T catches the rest. These programs are the middle rung.

**Every file here must be buildable by an unmodified `gcc -std=c99` with no
flags beyond `-lm`, and must print deterministic output.** The oracle is gcc; a
program gcc cannot build proves nothing, and the probe reports that as a SKIP
rather than swallowing it.

**Self-contained on purpose** — no third-party source is vendored (`gate.sh`
asserts no vendor tree is tracked). Real single-file libraries (stb, cJSON,
miniz) are picked up from `$PXX_C_CORPUS_DIR` when the operator has fetched
them, exactly as `test-lua` picks up `$(LUA_SRC)` and skips with the path when
it is absent.

Add a program by dropping a `.c` file here. The probe finds it; nothing lists
them by name.
