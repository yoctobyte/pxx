FPC     ?= fpc
# No -Fu needed for lib/asmcore: compiler.pas carries its own
# {$UNITPATH ../lib/asmcore} (FPC-only directive, source-relative, silently
# ignored by PXX self-host -- which finds lib/asmcore via its own
# ParseUsesUnit search chain instead, see compiler/parser.inc). Parameter-
# less compile from sources alone, no out-of-band flags to keep in sync.
FPCFLAGS = -O2 -Tlinux -Px86_64
HYPERFINE ?= hyperfine
BENCH_RUNS ?= 3
BENCH_HELLO_RUNS ?= 3
BENCH_BATCH ?= 3
BENCH_RUNTIME_RUNS ?= 3

COMPILER     := compiler/pascal26
COMPILER_MANAGED := compiler/pascal26-managed
COMPILER_SRC := compiler/compiler.pas
COMPILER_INC := $(wildcard compiler/*.inc) $(wildcard compiler/builtin/*.pas) $(wildcard lib/rtl/*.pas) $(wildcard lib/asmcore/*.pas)
FPC_COMPILER := /tmp/pascal26-fpc
BUILD_COMPILER := /tmp/pascal26-build
VERIFY_COMPILER := /tmp/pascal26-verify
BUILD_COMPILER_MANAGED  := /tmp/pascal26-managed-build
VERIFY_COMPILER_MANAGED := /tmp/pascal26-managed-verify

STABLE_ROOT := stable_linux_amd64
STABLE_DEFAULT_DIR := $(STABLE_ROOT)/default
STABLE_MANAGED_DIR := $(STABLE_ROOT)/managed
# Pinned compiler for the library/demo track (Claude B). Points at the `pinned`
# pointer, which track A advances DELIBERATELY with `make pin` -- distinct from
# `latest`, which `make stabilize` moves on every checkpoint. So A can record new
# stables without yanking B's ground; B only moves when A blesses a version.
# Override to pin a specific version ad hoc, e.g.
#   make lib-test PXX_STABLE=stable_linux_amd64/default/v9
PXX_STABLE ?= $(STABLE_DEFAULT_DIR)/pinned
PXXFLAGS   :=
FROZEN_PXXFLAGS := -uPXX_MANAGED_STRING

.PHONY: fuzz-csmith
.PHONY: test-c-conformance-i386 test-c-conformance-aarch64 test-c-conformance-arm32 test-c-conformance-riscv32 test-c-conformance-cross
.PHONY: all bootstrap bootstrap-check fpc-check test-fpc seed-from-stable test test-quick test-smoke test-opt stabilize-fast stabilize-record test-core test-threads test-asm test-asm-emit test-debug-g test-nilpy qemu-env-check test-lua test-cjson test-c-conformance test-c test-zlib test-chess-perft test-i386 test-aarch64 test-arm32 test-riscv32 test-emit-obj test-sqlite-threads stabilize check-stable selfcheck revert benchmark benchmark-compiler-runtime benchmark-opt-levels benchmark-check clean distclean symbols \
        bootstrap-managed bootstrap-frozen test-managed test-frozen stabilize-managed stabilize-frozen check-stable-managed revert-managed test-nilpy-managed test-nilpy-frozen \
        pxx-stable-check pin lib-test library-suite library-suite-green library-suite-discovery gui-test demos c-interop-devtest tls-openssl-devtest tls13-handshake-devtest \
        progress-check cross-bootstrap cross-bootstrap-aarch64 cross-bootstrap-arm32 cross-bootstrap-i386 test-esp-bare test-esp-softfloat

all: $(COMPILER)

# Regenerate SYMBOLS.md — concise routine index (universal-ctags). Navigation
# aid for humans and agents; re-run after code changes.
symbols:
	python3 tools/gen_symbols.py

bootstrap-check:
	@which $(FPC) > /dev/null 2>&1 || \
	  (echo "fpc not found. Install: sudo apt install fpc"; exit 1)

bootstrap: bootstrap-check
	$(FPC) $(FPCFLAGS) -o$(FPC_COMPILER) $(COMPILER_SRC)
	$(FPC_COMPILER) $(PXXFLAGS) $(COMPILER_SRC) $(BUILD_COMPILER)
	$(BUILD_COMPILER) $(PXXFLAGS) $(COMPILER_SRC) $(VERIFY_COMPILER)
	cmp $(BUILD_COMPILER) $(VERIFY_COMPILER)
	mv $(BUILD_COMPILER) $(COMPILER)

bootstrap-frozen: PXXFLAGS := $(FROZEN_PXXFLAGS)
bootstrap-frozen: bootstrap

bootstrap-managed: bootstrap-check
	$(FPC) $(FPCFLAGS) -o$(FPC_COMPILER) $(COMPILER_SRC)
	$(FPC_COMPILER) -dPXX_MANAGED_STRING $(COMPILER_SRC) $(BUILD_COMPILER_MANAGED)
	$(BUILD_COMPILER_MANAGED) -dPXX_MANAGED_STRING $(COMPILER_SRC) $(VERIFY_COMPILER_MANAGED)
	cmp $(BUILD_COMPILER_MANAGED) $(VERIFY_COMPILER_MANAGED)
	mv $(BUILD_COMPILER_MANAGED) $(COMPILER_MANAGED)

$(COMPILER): $(COMPILER_SRC) $(COMPILER_INC)
	@test -x $(COMPILER) || \
	  (echo "self-hosted compiler seed missing. Run: make bootstrap"; exit 1)
	./$(COMPILER) $(PXXFLAGS) $(COMPILER_SRC) $(BUILD_COMPILER)
	$(BUILD_COMPILER) $(PXXFLAGS) $(COMPILER_SRC) $(VERIFY_COMPILER)
	cmp $(BUILD_COMPILER) $(VERIFY_COMPILER)
	mv $(BUILD_COMPILER) $(COMPILER)

$(COMPILER_MANAGED): $(COMPILER_SRC) $(COMPILER_INC)
	@test -x $(COMPILER_MANAGED) || \
	  (echo "self-hosted managed compiler seed missing. Run: make bootstrap-managed"; exit 1)
	./$(COMPILER_MANAGED) -dPXX_MANAGED_STRING $(COMPILER_SRC) $(BUILD_COMPILER_MANAGED)
	$(BUILD_COMPILER_MANAGED) -dPXX_MANAGED_STRING $(COMPILER_SRC) $(VERIFY_COMPILER_MANAGED)
	cmp $(BUILD_COMPILER_MANAGED) $(VERIFY_COMPILER_MANAGED)
	mv $(BUILD_COMPILER_MANAGED) $(COMPILER_MANAGED)

fpc-check: bootstrap-check $(COMPILER)
	$(FPC) $(FPCFLAGS) -o$(FPC_COMPILER) $(COMPILER_SRC)
	$(FPC_COMPILER) $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-from-fpc
	cmp $(COMPILER) /tmp/pascal26-from-fpc

benchmark-check: bootstrap-check
	@which $(HYPERFINE) > /dev/null 2>&1 || \
	  (echo "hyperfine not found. Install: sudo apt install hyperfine"; exit 1)

benchmark: $(COMPILER) benchmark-check
	rm -rf /tmp/frankonpiler-bench-fpc-units /tmp/frankonpiler-bench-hello-fpc-units
	mkdir -p /tmp/frankonpiler-bench-fpc-units /tmp/frankonpiler-bench-hello-fpc-units
	$(HYPERFINE) --warmup 3 --runs $(BENCH_RUNS) \
	  --export-markdown /tmp/frankonpiler-compiler-bench.md \
	  --command-name 'FPC' '$(FPC) $(FPCFLAGS) -FU/tmp/frankonpiler-bench-fpc-units -o/tmp/pascal26-bench-fpc $(COMPILER_SRC) >/dev/null' \
	  --command-name 'self-hosted pascal26' './$(COMPILER) $(COMPILER_SRC) /tmp/pascal26-bench-self >/dev/null'
	$(HYPERFINE) --warmup 1 --runs $(BENCH_HELLO_RUNS) \
	  --export-markdown /tmp/frankonpiler-hello-bench.md \
	  --command-name 'FPC: $(BENCH_BATCH) x hello' 'for i in $$(seq 1 $(BENCH_BATCH)); do $(FPC) $(FPCFLAGS) -FU/tmp/frankonpiler-bench-hello-fpc-units -o/tmp/hello-bench-fpc test/hello.pas >/dev/null; done' \
	  --command-name 'self-hosted pascal26 managed: $(BENCH_BATCH) x hello' 'for i in $$(seq 1 $(BENCH_BATCH)); do ./$(COMPILER) test/hello.pas /tmp/hello-bench-self-managed >/dev/null; done' \
	  --command-name 'self-hosted pascal26 frozen: $(BENCH_BATCH) x hello' 'for i in $$(seq 1 $(BENCH_BATCH)); do ./$(COMPILER) -uPXX_MANAGED_STRING test/hello.pas /tmp/hello-bench-self-frozen >/dev/null; done'
	stat -c '%n %s bytes' /tmp/pascal26-bench-fpc /tmp/pascal26-bench-self /tmp/hello-bench-fpc /tmp/hello-bench-self-managed /tmp/hello-bench-self-frozen
	test "$$(/tmp/hello-bench-fpc)" = "Hello, World!"
	test "$$(/tmp/hello-bench-self-managed)" = "Hello, World!"
	test "$$(/tmp/hello-bench-self-frozen)" = "Hello, World!"
	/tmp/pascal26-bench-self test/hello.pas /tmp/bench-compiler-hello-managed >/dev/null
	/tmp/pascal26-bench-self -uPXX_MANAGED_STRING test/hello.pas /tmp/bench-compiler-hello-frozen >/dev/null
	stat -c '%n %s bytes' /tmp/bench-compiler-hello-managed /tmp/bench-compiler-hello-frozen
	test "$$(/tmp/bench-compiler-hello-managed)" = "Hello, World!"
	test "$$(/tmp/bench-compiler-hello-frozen)" = "Hello, World!"

benchmark-compiler-runtime: $(COMPILER) benchmark-check
	rm -rf /tmp/frankonpiler-bench-runtime-fpc-units
	mkdir -p /tmp/frankonpiler-bench-runtime-fpc-units
	$(FPC) $(FPCFLAGS) -FU/tmp/frankonpiler-bench-runtime-fpc-units -o/tmp/pascal26-runtime-fpc $(COMPILER_SRC) >/dev/null
	/tmp/pascal26-runtime-fpc $(COMPILER_SRC) /tmp/pascal26-runtime-fpc-output >/dev/null
	./$(COMPILER) $(COMPILER_SRC) /tmp/pascal26-runtime-self-output >/dev/null
	cmp /tmp/pascal26-runtime-fpc-output /tmp/pascal26-runtime-self-output
	$(HYPERFINE) --warmup 3 --runs $(BENCH_RUNTIME_RUNS) \
	  --export-markdown /tmp/frankonpiler-compiler-runtime-bench.md \
	  --command-name 'FPC-built pascal26 compiles compiler' '/tmp/pascal26-runtime-fpc $(COMPILER_SRC) /tmp/pascal26-runtime-fpc-output >/dev/null' \
	  --command-name 'self-hosted pascal26 compiles compiler' './$(COMPILER) $(COMPILER_SRC) /tmp/pascal26-runtime-self-output >/dev/null'
	$(HYPERFINE) --warmup 1 --runs $(BENCH_HELLO_RUNS) \
	  --export-markdown /tmp/frankonpiler-compiler-runtime-hello-bench.md \
	  --command-name 'FPC-built pascal26: $(BENCH_BATCH) x hello' 'for i in $$(seq 1 $(BENCH_BATCH)); do /tmp/pascal26-runtime-fpc test/hello.pas /tmp/hello-runtime-fpc >/dev/null; done' \
	  --command-name 'self-hosted pascal26: $(BENCH_BATCH) x hello' 'for i in $$(seq 1 $(BENCH_BATCH)); do ./$(COMPILER) test/hello.pas /tmp/hello-runtime-self >/dev/null; done'
	stat -c '%n %s bytes' /tmp/pascal26-runtime-fpc /tmp/pascal26-runtime-fpc-output /tmp/pascal26-runtime-self-output /tmp/hello-runtime-fpc /tmp/hello-runtime-self
	test "$$(/tmp/hello-runtime-fpc)" = "Hello, World!"
	test "$$(/tmp/hello-runtime-self)" = "Hello, World!"

# benchmark-opt-levels: build the compiler at each -O tier with the current
# self-hosted binary, prove every tier emits identical (correct) -O0 output,
# report each tier binary's size, then hyperfine each tier self-compiling the
# compiler (the standard heavy workload). -O2/-O3 currently ALIAS -O1 — all
# landed -O1 passes gate OptLevel>=1 and no -O2/-O3-only pass exists yet — so
# their rows track -O1 until the higher tiers gain distinct passes; they stay
# in the table so the tiers remain visible as work lands.
benchmark-opt-levels: $(COMPILER) benchmark-check
	@echo "=== building the compiler at each -O tier ==="
	./$(COMPILER) -O0 $(COMPILER_SRC) /tmp/pxx-opt-O0
	./$(COMPILER) -O1 $(COMPILER_SRC) /tmp/pxx-opt-O1
	./$(COMPILER) -O2 $(COMPILER_SRC) /tmp/pxx-opt-O2
	./$(COMPILER) -O3 $(COMPILER_SRC) /tmp/pxx-opt-O3
	@echo "=== correctness: every tier binary emits identical output (default -O0 emission) ==="
	/tmp/pxx-opt-O0 $(COMPILER_SRC) /tmp/pxx-opt-out-O0 >/dev/null
	/tmp/pxx-opt-O1 $(COMPILER_SRC) /tmp/pxx-opt-out-O1 >/dev/null
	/tmp/pxx-opt-O2 $(COMPILER_SRC) /tmp/pxx-opt-out-O2 >/dev/null
	/tmp/pxx-opt-O3 $(COMPILER_SRC) /tmp/pxx-opt-out-O3 >/dev/null
	cmp /tmp/pxx-opt-out-O0 /tmp/pxx-opt-out-O1
	cmp /tmp/pxx-opt-out-O0 /tmp/pxx-opt-out-O2
	cmp /tmp/pxx-opt-out-O0 /tmp/pxx-opt-out-O3
	@echo "=== compiler binary size per tier (smaller = tighter codegen) ==="
	@stat -c '%n  %s bytes' /tmp/pxx-opt-O0 /tmp/pxx-opt-O1 /tmp/pxx-opt-O2 /tmp/pxx-opt-O3
	@echo "=== self-compile time per tier ==="
	$(HYPERFINE) --warmup 2 --runs $(BENCH_RUNTIME_RUNS) \
	  --export-markdown /tmp/frankonpiler-opt-levels-bench.md \
	  --command-name 'O0-built compiles compiler' '/tmp/pxx-opt-O0 $(COMPILER_SRC) /tmp/pxx-opt-sc0 >/dev/null' \
	  --command-name 'O1-built compiles compiler' '/tmp/pxx-opt-O1 $(COMPILER_SRC) /tmp/pxx-opt-sc1 >/dev/null' \
	  --command-name 'O2-built compiles compiler' '/tmp/pxx-opt-O2 $(COMPILER_SRC) /tmp/pxx-opt-sc2 >/dev/null' \
	  --command-name 'O3-built compiles compiler' '/tmp/pxx-opt-O3 $(COMPILER_SRC) /tmp/pxx-opt-sc3 >/dev/null'

test-nilpy: $(COMPILER)
	./$(COMPILER) test/test_nil_python_core.npy /tmp/test_nil_python_core26
	test "$$(/tmp/test_nil_python_core26)" = "$$(printf '0\n1\n1\n2\n3\n5\n10')"
	./$(COMPILER) test/test_nilpy_import_sqlite.npy /tmp/test_nilpy_import_sqlite26
	test "$$(/tmp/test_nilpy_import_sqlite26)" = "3045001"
	rm -f /tmp/test_nilpy_sqlite_crud.db
	./$(COMPILER) test/test_nilpy_sqlite_crud.npy /tmp/test_nilpy_sqlite_crud26
	test "$$(/tmp/test_nilpy_sqlite_crud26)" = "$$(printf '1 alice\n2 bob')"
	./$(COMPILER) test/test_nilpy_variant.npy /tmp/test_nilpy_variant26
	test "$$(/tmp/test_nilpy_variant26)" = "$$(printf '5\n3.14\n1')"
	./$(COMPILER) test/test_nilpy_control.npy /tmp/test_nilpy_control26
	test "$$(/tmp/test_nilpy_control26)" = "$$(printf '10\n20\n30\n6\n15\n6\n3')"
	./$(COMPILER) test/test_nilpy_local_variant.npy /tmp/test_nilpy_local_variant26
	test "$$(/tmp/test_nilpy_local_variant26)" = "$$(printf '5\n3.14\n1\n7')"
	./$(COMPILER) test/test_nilpy_numeric_widen.npy /tmp/test_nilpy_numeric_widen26
	test "$$(/tmp/test_nilpy_numeric_widen26)" = "$$(printf '3.14')"
	./$(COMPILER) test/test_nilpy_convert.npy /tmp/test_nilpy_convert26
	test "$$(/tmp/test_nilpy_convert26)" = "$$(printf '3\n42')"
	./$(COMPILER) test/test_nilpy_bool.npy /tmp/test_nilpy_bool26
	test "$$(/tmp/test_nilpy_bool26)" = "$$(printf 'True\nTrue\nTrue\nFalse\nTrue\nTrue')"
	./$(COMPILER) test/test_nilpy_str_float.npy /tmp/test_nilpy_str_float26
	test "$$(/tmp/test_nilpy_str_float26)" = "$$(printf '3.14\n2.5\n-1.25\npi=3.14159\n3\n2')"
	! ./$(COMPILER) test/test_nilpy_slash_fail.npy /tmp/test_nilpy_slash_fail26 > /tmp/test_nilpy_slash_fail.log 2>&1
	grep -q "unsupported operator /; use // for integer division" /tmp/test_nilpy_slash_fail.log
	./$(COMPILER) test/test_nilpy_string_variant.npy /tmp/test_nilpy_string_variant26
	test "$$(/tmp/test_nilpy_string_variant26)" = "$$(printf '5\napple\nTrue\nFalse\nFalse\nTrue\nTrue\nTrue\nFalse\nFalse\nTrue\nTrue\nFalse\nTrue\nFalse\nFalse\nhello world\nhello potato\ngreen world')"
	! ./$(COMPILER) test/test_nilpy_missing_param_annotation_fail.npy /tmp/test_nilpy_missing_param_annotation_fail26 > /tmp/test_nilpy_missing_param_annotation_fail.log 2>&1
	grep -q "unexpected token" /tmp/test_nilpy_missing_param_annotation_fail.log
	! ./$(COMPILER) test/test_nilpy_missing_result_annotation_fail.npy /tmp/test_nilpy_missing_result_annotation_fail26 > /tmp/test_nilpy_missing_result_annotation_fail.log 2>&1
	grep -q "unexpected token" /tmp/test_nilpy_missing_result_annotation_fail.log
	! ./$(COMPILER) test/test_nilpy_range_step_fail.npy /tmp/test_nilpy_range_step_fail26 > /tmp/test_nilpy_range_step_fail.log 2>&1
	grep -q "range step other than 1 is not supported in v1" /tmp/test_nilpy_range_step_fail.log
	! ./$(COMPILER) test/test_nilpy_five_params_fail.npy /tmp/test_nilpy_five_params_fail26 > /tmp/test_nilpy_five_params_fail.log 2>&1
	grep -q "more than four parameters are not supported in v1" /tmp/test_nilpy_five_params_fail.log
	! ./$(COMPILER) test/test_nilpy_inconsistent_dedent_fail.npy /tmp/test_nilpy_inconsistent_dedent_fail26 > /tmp/test_nilpy_inconsistent_dedent_fail.log 2>&1
	grep -q "inconsistent dedent" /tmp/test_nilpy_inconsistent_dedent_fail.log
	! ./$(COMPILER) test/test_nilpy_mixed_indent_fail.npy /tmp/test_nilpy_mixed_indent_fail26 > /tmp/test_nilpy_mixed_indent_fail.log 2>&1
	grep -q "mixing tabs and spaces for indentation" /tmp/test_nilpy_mixed_indent_fail.log
	./$(COMPILER) test/test_nilpy_str_param.npy /tmp/test_nilpy_str_param26
	test "$$(/tmp/test_nilpy_str_param26)" = "$$(printf '2\na\ncd\nok!')"
	./$(COMPILER) examples/shell/shell0.npy /tmp/test_nilpy_shell026
	/tmp/test_nilpy_shell026 | grep -q "hello portable userland"

test-managed: COMPILER := $(COMPILER_MANAGED)
test-managed: PXXFLAGS := -dPXX_MANAGED_STRING
test-managed: test

test-frozen: PXXFLAGS := $(FROZEN_PXXFLAGS)
test-frozen: test-core

test-nilpy-managed: COMPILER := $(COMPILER_MANAGED)
test-nilpy-managed: PXXFLAGS := -dPXX_MANAGED_STRING
test-nilpy-managed: test-nilpy

test-nilpy-frozen: PXXFLAGS := $(FROZEN_PXXFLAGS)
test-nilpy-frozen: test-nilpy

# Daily gate. Self-hosts off the EXISTING compiler/pascal26 (the $(COMPILER)
# rule rebuilds it from itself, no FPC). FPC is NOT required here -- the
# FPC-dependent checks (compliance + host-side asm-emit oracle) live in
# `make test-fpc` (release/CI postcheck), and a cold checkout seeds the binary
# with `make seed-from-stable` (also no FPC). Only a pure-source distro build
# with no committed binary needs `make bootstrap`.
test: test-core test-threads test-asm test-debug-g lib-fpc-clean

# FPC-dependent postcheck, NOT part of the daily gate. Two checks that shell out
# to FPC: (1) fpc-check -- FPC can still compile us and yields the same
# self-hosted binary (compliance); (2) test-asm-emit -- host-built byte oracle
# for the per-target assemblers (built with FPC). Was a transitive dep of
# `test`/`stabilize`, forcing FPC for every pin; now explicit so the daily loop
# (and `apt remove fpc`) is unaffected. Run by the release workflow / CI.
test-fpc: fpc-check test-asm-emit

# Cold-start seed WITHOUT FPC: copy the committed pinned stable binary into the
# working slot so `make test` / `make stabilize` can self-host. Use this on a
# fresh checkout instead of `make bootstrap` (which rebuilds gen0 from FPC and is
# only needed for a pure-source build that ships no binary).
seed-from-stable:
	@test -x $(PXX_STABLE) || \
	  (echo "No pinned stable at $(PXX_STABLE). Run: make bootstrap (needs FPC) once."; exit 1)
	cp $(PXX_STABLE) $(COMPILER)
	@echo "seeded $(COMPILER) from $(PXX_STABLE) (no FPC). Run 'make test' to self-host."

# DWARF Tier 1 (-g) smoke: a -g build must keep identical runtime output, emit a
# .debug_line table for the source, and let gdb resolve+hit a line breakpoint
# with file:line in the backtrace (x86-64). -g is opt-in, so the byte-identical
# self-host path is unaffected (covered by fpc-check/bootstrap).
test-debug-g: $(COMPILER)
	./tools/dwarf_smoke.sh ./$(COMPILER)

# Invariant for --mimic-fpc: under whole-compile mimic, lib/ units lex with FPC
# defined, so any {$ifdef FPC} in a library unit would silently change meaning
# (feature-mimic-fpc drawback 3). Keep lib/ FPC-clean — fail if any appears.
lib-fpc-clean:
	@if grep -rnoE '\{\$$if(n?def)?[ ]+FPC[ ]*\}|defined\(FPC\)' lib/ ; then \
	  echo "lib-fpc-clean: FAIL — lib/ must not use {\$$ifdef FPC} (breaks --mimic-fpc)"; exit 1; \
	else echo "lib-fpc-clean: OK"; fi

# Host-side byte tests for the per-target text assemblers (EmitAsm386 / Rv32 /
# A64 / Arm32). Each test {$include}s the SAME per-platform file the compiler
# ships and asserts emitted bytes against llvm-mc oracle values; it Halt(1)s on
# any mismatch. Built/run out of /tmp to keep test/ clean.
test-asm-emit:
	@for t in x64 386 rv32 a64 arm32; do \
	  $(FPC) -FU/tmp -FE/tmp test/test_asm_emit_$$t.pas >/tmp/asmemit_$$t.log 2>&1 || \
	    { echo "asm-emit $$t: BUILD FAIL"; cat /tmp/asmemit_$$t.log; exit 1; }; \
	  /tmp/test_asm_emit_$$t >/dev/null || \
	    { echo "asm-emit $$t: FAIL"; /tmp/test_asm_emit_$$t; exit 1; }; \
	  echo "asm-emit $$t: OK"; \
	done

# Libc-free threading (meta-multithreading M1/M2). x86-64 only: spawns real OS
# threads via the __pxxclone trampoline (clone(2)) and joins them with futex
# (raw + the palthread PAL); M2 adds the atomic intrinsics (lost-update test) and
# the futex mutex (mutual-exclusion test). tids stay out of stdout so output is
# deterministic.
test-threads: $(COMPILER)
	./$(COMPILER) --threadsafe test/test_thread_clone.pas /tmp/test_thread_clone26
	test "$$(/tmp/test_thread_clone26)" = "$$(printf 'thread 0 -> 1000\nthread 1 -> 1001\nthread 2 -> 1002\nthread 3 -> 1003\ntotal ok 4 / 4\nTHREADS OK')"
	./$(COMPILER) --threadsafe test/test_palthread.pas /tmp/test_palthread26
	test "$$(/tmp/test_palthread26)" = "$$(printf 'thread 0 -> 1000\nthread 1 -> 1001\nthread 2 -> 1002\nthread 3 -> 1003\ntotal ok 4 / 4\nPALTHREAD OK')"
	./$(COMPILER) --threadsafe test/test_atomic_counter.pas /tmp/test_atomic_counter26
	test "$$(/tmp/test_atomic_counter26)" = "$$(printf 'xchg old=10 now=99\ncas hit old=99 now=7\ncas miss old=7 now=7\nadd old=7 now=12\ncounter=800000 expected=800000\nATOMIC OK')"
	./$(COMPILER) --threadsafe test/test_mutex.pas /tmp/test_mutex26
	test "$$(/tmp/test_mutex26)" = "$$(printf 'counter=400000 expected=400000\nMUTEX OK')"
	./$(COMPILER) --threadsafe test/test_tthread.pas /tmp/test_tthread26
	test "$$(/tmp/test_tthread26)" = "$$(printf 'counter=400000 expected=400000\nTTHREAD OK')"
	./$(COMPILER) --threadsafe test/test_event.pas /tmp/test_event26
	test "$$(/tmp/test_event26)" = "$$(printf 'passed=4 expected=4\nEVENT OK')"
	./$(COMPILER) --threadsafe test/test_thread_heap.pas /tmp/test_thread_heap26
	test "$$(/tmp/test_thread_heap26)" = "$$(printf 'errors=0\nHEAP OK')"
	# heap contract: every allocation family safe under concurrent churn (strings, dynarrays, classes, raw+realloc)
	./$(COMPILER) --threadsafe test/test_thread_heap_mixed.pas /tmp/test_thread_heap_mixed26
	test "$$(/tmp/test_thread_heap_mixed26)" = "$$(printf 'errors=0\nHEAP MIXED OK')"
	# heap contract: thread creation without --threadsafe is a clear compile error, not a heisencrash
	! ./$(COMPILER) test/test_thread_clone.pas /tmp/test_thread_clone_guard26 > /tmp/test_thread_clone_guard.log 2>&1
	grep -q "requires --threadsafe" /tmp/test_thread_clone_guard.log
	# heap contract: --threadsafe on a target without the locked runtime is rejected
	# (x86-64/i386/aarch64 got the locked runtime; riscv32 has no threading PAL, so it is the guard probe)
	! ./$(COMPILER) --target=riscv32 --threadsafe test/hello.pas /tmp/test_threadsafe_riscv32_guard26 > /tmp/test_threadsafe_riscv32_guard.log 2>&1
	grep -q "only" /tmp/test_threadsafe_riscv32_guard.log
	./$(COMPILER) --threadsafe test/test_critsec_once.pas /tmp/test_critsec_once26
	test "$$(/tmp/test_critsec_once26)" = "$$(printf 'critsec=400000 expected=400000\ninit ran=1 expected=1\nCRITSEC_ONCE OK')"
	# __pxxmulhi_u64: unsigned 64x64->128 high half (x86-64 mul / aarch64 umulh)
	./$(COMPILER) test/test_mulhi.pas /tmp/test_mulhi26
	test "$$(/tmp/test_mulhi26 | tail -1)" = "MULHI OK"
	# whole-array assign to a var param (copy sized from the open-array
	# placeholder -> 1000-element overrun) + N-D whole-array assign
	./$(COMPILER) test/test_array_var_param_assign.pas /tmp/test_avpa26
	test "$$(/tmp/test_avpa26 | tail -1)" = "ARRAY VAR PARAM ASSIGN OK"
	# 64-bit named constants (were declared tyInteger -> truncated on 32-bit
	# targets). Only meaningful cross; x86-64 passed even when broken.
	./$(COMPILER) test/test_const64.pas /tmp/test_const64_26
	test "$$(/tmp/test_const64_26 | tail -1)" = "CONST64 OK"
	# M2 final slice: 64-bit atomics + TConditionVariable
	./$(COMPILER) --threadsafe test/test_atomic64.pas /tmp/test_atomic64_26
	test "$$(/tmp/test_atomic64_26 | tail -1)" = "ATOMIC64 OK"
	./$(COMPILER) --threadsafe test/test_condvar.pas /tmp/test_condvar26
	test "$$(/tmp/test_condvar26 | tail -1)" = "CONDVAR OK"
	./$(COMPILER) --threadsafe test/test_tthread_terminate.pas /tmp/test_tthread_terminate26
	test "$$(/tmp/test_tthread_terminate26)" = "$$(printf 'terminated=TRUE\nfinished=TRUE\nreturnvalue=42\nTERMINATE OK')"
	# TThread Synchronize/Queue/CheckSynchronize main-thread marshalling + auto-join virtual destructor
	./$(COMPILER) --threadsafe test/test_tthread_sync.pas /tmp/test_tthread_sync26
	test "$$(/tmp/test_tthread_sync26)" = "$$(printf 'sync=200 expected=200\nonmain=200 expected=200\nqueue=200 expected=200\nautojoin OK\nTTHREAD SYNC OK')"
	# M3 final slice: FreeOnTerminate + OnTerminate + CurrentThread + Suspend/Resume
	./$(COMPILER) --threadsafe test/test_tthread_final.pas /tmp/test_tthread_final26
	test "$$(/tmp/test_tthread_final26)" = "$$(printf 'main current OK\ncurrentthread=1 ontermmain=1\nfreeonterminate=1\nsuspend=2 suspended=FALSE\nlatestart=1\nTTHREAD FINAL OK')"
	# statement-atomic threaded writeln: every concurrent output line is whole (--threadsafe I/O lock)
	./$(COMPILER) --threadsafe test/test_thread_writeln_interleave.pas /tmp/test_thread_writeln_interleave26
	/tmp/test_thread_writeln_interleave26 > /tmp/twi26.out
	test "$$(wc -l < /tmp/twi26.out)" = "401"
	test "$$(grep -cvE '^(A{60}|B{60}|done)$$' /tmp/twi26.out)" = "0"

# MVP .asm -> exe frontend (feature-asm-mvp-frontend). A flat mov/add/ret .asm
# encoded through lib/asmcore -> ET_EXEC; exit code carries the computed result.
# Gives Track B a run-it-and-check path for lib/asmcore. x86-64.
test-asm: $(COMPILER)
	./$(COMPILER) test/test_asm_mvp.asm /tmp/test_asm_mvp26
	/tmp/test_asm_mvp26; test "$$?" = "42"
	./$(COMPILER) test/test_asmcore_x64.pas /tmp/test_asmcore_x64_26
	/tmp/test_asmcore_x64_26 | tail -1 | grep -q "all asmcore_x64 checks passed"
	./$(COMPILER) test/test_asmcore_aarch64.pas /tmp/test_asmcore_aarch64_26
	/tmp/test_asmcore_aarch64_26 | tail -1 | grep -q "all asmcore_aarch64 checks passed"
	./$(COMPILER) test/test_asmcore_i386.pas /tmp/test_asmcore_i386_26
	/tmp/test_asmcore_i386_26 | tail -1 | grep -q "all asmcore_i386 checks passed"
	./$(COMPILER) test/test_asmcore_arm32.pas /tmp/test_asmcore_arm32_26
	/tmp/test_asmcore_arm32_26 | tail -1 | grep -q "all asmcore_arm32 checks passed"
	./$(COMPILER) test/test_asmcore_riscv32.pas /tmp/test_asmcore_riscv32_26
	/tmp/test_asmcore_riscv32_26 | tail -1 | grep -q "all asmcore_riscv32 checks passed"
	./$(COMPILER) test/test_asmcore_xtensa.pas /tmp/test_asmcore_xtensa_26
	/tmp/test_asmcore_xtensa_26 | tail -1 | grep -q "all asmcore_xtensa checks passed"
	./$(COMPILER) test/test_asm_loop.asm /tmp/test_asm_loop26
	/tmp/test_asm_loop26; test "$$?" = "45"
	./$(COMPILER) test/test_asm_hello.asm /tmp/test_asm_hello26
	test "$$(/tmp/test_asm_hello26)" = "Hello, asm world!"
	./$(COMPILER) test/test_asm_entry_global.asm /tmp/test_asm_entry_global26
	/tmp/test_asm_entry_global26; test "$$?" = "42"
	./$(COMPILER) test/test_asm_extern.asm /tmp/test_asm_extern26
	test "$$(/tmp/test_asm_extern26)" = "Hello from extern printf!"
	./$(COMPILER) test/test_asm_obj.asm /tmp/test_asm_obj26.o
	readelf -h /tmp/test_asm_obj26.o | grep -q 'REL (Relocatable file)'
	readelf -h /tmp/test_asm_obj26.o | grep -q 'X86-64'
	readelf -s /tmp/test_asm_obj26.o | grep -q 'GLOBAL DEFAULT    1 asm_obj_add'
	readelf -s /tmp/test_asm_obj26.o | grep -q 'GLOBAL DEFAULT    1 asm_obj_start'
	readelf -s /tmp/test_asm_obj26.o | grep -q 'UND puts'
	readelf -r /tmp/test_asm_obj26.o | grep -q 'R_X86_64_PLT32'
	readelf -r /tmp/test_asm_obj26.o | grep -q 'puts - 4'
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -nostartfiles -e asm_obj_start /tmp/test_asm_obj26.o -o /tmp/test_asm_obj26_exe 2>/dev/null && \
	  test "$$(/tmp/test_asm_obj26_exe)" = "asm object file test" && echo "test-asm: .o links+runs via ld/gcc ok" || { echo "test-asm: .o link/run FAILED"; exit 1; }; \
	  printf 'extern int asm_obj_add(int,int);\nint main(){ return asm_obj_add(19,23) == 42 ? 0 : 1; }\n' > /tmp/test_asm_obj26_caller.c; \
	  gcc -c /tmp/test_asm_obj26_caller.c -o /tmp/test_asm_obj26_caller.o && \
	  gcc /tmp/test_asm_obj26_caller.o /tmp/test_asm_obj26.o -o /tmp/test_asm_obj26_caller_exe 2>/dev/null && \
	  /tmp/test_asm_obj26_caller_exe && echo "test-asm: .o exported symbol callable from C ok"; \
	else echo "test-asm: gcc not installed; .o link check skipped"; fi
	./$(COMPILER) test/test_asm_so.asm /tmp/test_asm_so26.so
	readelf -h /tmp/test_asm_so26.so | grep -q 'DYN (Shared object file)'
	readelf -h /tmp/test_asm_so26.so | grep -q 'X86-64'
	readelf -d /tmp/test_asm_so26.so | grep -q 'NEEDED.*libc.so.6'
	@if command -v gcc >/dev/null 2>&1; then \
	  printf '#include <stdio.h>\n#include <dlfcn.h>\nint main(int c,char**v){void*h=dlopen(v[1],RTLD_NOW);if(!h){fprintf(stderr,"dlopen: %%s\\n",dlerror());return 1;}int(*a)(int,int)=dlsym(h,"so_add");void(*g)(void)=dlsym(h,"so_greet");if(!a||!g){fprintf(stderr,"dlsym: %%s\\n",dlerror());return 1;}if(a(19,23)!=42){fprintf(stderr,"so_add wrong\\n");return 1;}g();return 0;}\n' > /tmp/test_asm_so26_dlopen.c; \
	  gcc /tmp/test_asm_so26_dlopen.c -o /tmp/test_asm_so26_dlopen -ldl 2>/dev/null && \
	  test "$$(/tmp/test_asm_so26_dlopen /tmp/test_asm_so26.so)" = "hello from shared lib" && \
	  echo "test-asm: .so dlopen/dlsym round-trip (incl. extern-call GOT) ok" || { echo "test-asm: .so dlopen round-trip FAILED"; exit 1; }; \
	else echo "test-asm: gcc not installed; .so dlopen check skipped"; fi
	./$(COMPILER) -S test/hello.pas /tmp/test_asm_dis_hello26
	test -f /tmp/test_asm_dis_hello26.s
	grep -q "^    call " /tmp/test_asm_dis_hello26.s
	grep -q "^    ret$$" /tmp/test_asm_dis_hello26.s
	! grep -q "^    db " /tmp/test_asm_dis_hello26.s
	./$(COMPILER) -S compiler/compiler.pas /tmp/test_asm_dis_self26
	test -f /tmp/test_asm_dis_self26.s
	! grep -q "^    db " /tmp/test_asm_dis_self26.s

test-core: $(COMPILER)
	# nested variant part + tagged discriminant + const case labels (TVarSin, bug-pascal-nested-variant-record-tagged)
	./$(COMPILER) test/test_nested_variant_record.pas /tmp/test_nested_variant_record26
	test "$$(/tmp/test_nested_variant_record26)" = "$$(printf '28\n2\n8080\nTRUE\n7')"
	# cast-deref (PChar(s)^) as by-ref method arg (bug-cast-deref-as-varparam-arg)
	./$(COMPILER) test/test_cast_deref_varparam.pas /tmp/test_cast_deref_varparam26
	test "$$(/tmp/test_cast_deref_varparam26)" = "$$(printf 'abc 3')"
	# on-handler binder must not poison the next routine's params (stale SymBlockId)
	./$(COMPILER) -Fulib/rtl -Fulib/rtl/platform/posix test/test_on_handler_next_proc_params.pas /tmp/test_on_handler_npp26
	test "$$(/tmp/test_on_handler_npp26)" = "$$(printf 'purging\nTRUE 7')"
	# TObject params: full 64-bit value + plain-routine match (bug-tobject-param-truncated-32bit)
	./$(COMPILER) test/test_tobject_param_b243.pas /tmp/test_tobject_param_b24326
	test "$$(/tmp/test_tobject_param_b24326)" = "$$(printf 'm-ident=TRUE\nm-cast=77\np-ident=TRUE\np-cast=77')"
	# `class var` section ends at a visibility marker; bare class var in a (static) method
	./$(COMPILER) test/test_class_var_section_b244.pas /tmp/test_class_var_section_b24426
	test "$$(/tmp/test_class_var_section_b24426)" = "$$(printf 'hits=12\nviaobj=12\ntotal=19')"
	# string-literal default parameter values (bug-pascal-string-default-param)
	./$(COMPILER) test/test_string_default_param_b245.pas /tmp/test_string_default_param_b24526
	test "$$(/tmp/test_string_default_param_b24526)" = "$$(printf 'a=1 msg=default len=7 taillen=0\na=2 msg=abc len=3 taillen=0\na=3 msg=abc len=3 taillen=2\nhi bob 3 len=2\nyo ann 3 len=2\nhey cid 9 len=3')"
	# method defaults must not shift onto the previous slot (bug-pascal-method-default-param-self-shift)
	./$(COMPILER) test/test_method_default_param_b246.pas /tmp/test_method_default_param_b24626
	test "$$(/tmp/test_method_default_param_b24626)" = "$$(printf 'a=1 b=2\na=9 b=2\na=9 b=8\nx=1 msg=hi n=3 len=2\nx=2 msg=yo n=3 len=2\nx=3 msg=hey n=7 len=3')"
	# `overload` is a real token: class-body directive loop must consume it (bug-pascal-class-body-overload-directive)
	./$(COMPILER) test/test_class_overload_directive_b247.pas /tmp/test_class_overload_directive_b24726
	test "$$(/tmp/test_class_overload_directive_b24726)" = "$$(printf 'name=<none>\nbase ping\ntag=base\nderived ping\ntag=derived')"
	# method + ctor overloads resolve by ARGUMENT TYPE, not first-name-match (bug-pascal-method-overload-ignores-arg-types)
	./$(COMPILER) test/test_method_overload_types_b248.pas /tmp/test_method_overload_types_b24826
	test "$$(/tmp/test_method_overload_types_b24826)" = "$$(printf 'ctor=none\nint 1\nstr xy\nstr x\ntwice-int=42\ntwice-str=abab\nctor=str:zed\nctor=int\nsub-ctor=str:sub\nstr hi\nint 7')"
	# constref + untyped `out` in an interface method + cdecl directive + RTL IInterface/HResult
	./$(COMPILER) -Fulib/rtl -Fulib/rtl/platform/posix test/test_interface_constref_cdecl_b249.pas /tmp/test_interface_constref_cdecl_b24926
	test "$$(/tmp/test_interface_constref_cdecl_b24926)" = "$$(printf 'ping\naddref=-1\nrelease=-1\nqi=-1\nn=7 s=hi')"
	# advanced records: methods in a record; Self is the RECORD, BY REFERENCE
	./$(COMPILER) test/test_advanced_records_b268.pas /tmp/test_advanced_records_b26826
	test "$$(/tmp/test_advanced_records_b26826)" = "$$(printf 'sum=7\nhalf=3\noffset=4,5\nadd=14,25\nunchanged=4,5 10,20\nctor=3,4 sum=7\nctor-via-fn=5,10\nop-plus=11,22\nop-eq=TRUE\nop-neq=FALSE\nprop-read=7\nprop-write=70\nprop-method=78\ndef=140 141')"
	# RTL types.pas: TPoint/TRect are ADVANCED RECORDS -- record methods reached
	# through a UNIT, with overloads, by-ref Self, record results, props over fields
	./$(COMPILER) -Fulib/rtl test/test_types_point_methods_b269.pas /tmp/test_types_point_methods_b26926
	test "$$(/tmp/test_types_point_methods_b26926)" = "$$(printf 'p=3,4\nq=3,4\noff=13,24\noffp=16,28\nzero=FALSE\nzero0=TRUE\nadd=14,26\nsub=10,20\nrect=20x10 w=20 h=10\nempty=FALSE\nin=TRUE out=FALSE\nsize=7x9\nsizew=11')"
	# TObject.ClassType / InheritsFrom, incl. the fpcunit chain E.ClassType.InheritsFrom(C)
	./$(COMPILER) test/test_classtype_inheritsfrom_b274.pas /tmp/test_classtype_inheritsfrom_b27426
	test "$$(/tmp/test_classtype_inheritsfrom_b27426)" = "$$(printf 'classtype name: TLeaf\nchain leaf<-mid: TRUE\nchain leaf<-base: TRUE\nchain leaf<-other: FALSE\nchain leaf<-leaf: TRUE\ninst leaf<-base: TRUE\nvar name: TLeaf\nvar leaf<-mid: TRUE\nvar leaf<-other: FALSE\nlit mid<-base: TRUE\nlit base<-leaf: FALSE\nchain name: TLeaf')"
	# bare PARENLESS call of a proc-var / method-pointer as a statement (`AMethod;`),
	# and the other half: a bare proc-var stays a VALUE in every other position
	./$(COMPILER) test/test_bare_procvar_call_b273.pas /tmp/test_bare_procvar_call_b27326
	test "$$(/tmp/test_bare_procvar_call_b27326)" = "$$(printf 'assigned: TRUE\nsame: TRUE\ncalls so far: 0\nplain\nplain\nplain\nparam assigned: TRUE\nplain\nfunc via parens: 7\nmeth assigned: TRUE\nmeth n=5\nmeth n=5\ntotal calls: 8')"
	# FreeAndNil must RUN THE DESTRUCTOR (it silently skipped it: Free through an untyped
	# reference does not dispatch Destroy)
	./$(COMPILER) -Fulib/rtl -Fulib/rtl/platform/posix test/test_freeandnil_destructor_b300.pas /tmp/test_freeandnil_destructor_b30026
	test "$$(/tmp/test_freeandnil_destructor_b30026)" = "$$(printf 'freeing parent:\n  TParent.Destroy\n  TChild.Destroy\nparent nil : TRUE\ndestructors: 1 (1 = the child, via TParent.Destroy)\nfreeing child:\n  TChild.Destroy\nchild nil  : TRUE\ndestructors: 2 (2)')"
	# a CLASS PROPERTY through the class name: TD.Compressed := True
	./$(COMPILER) test/test_class_property_b299.pas /tmp/test_class_property_b29926
	test "$$(/tmp/test_class_property_b29926)" = "$$(printf 'default : FALSE 0\nafter   : TRUE 7\nagain   : FALSE 7')"
	# an `array of const` LITERAL to an OVERLOADED constructor (fcl-json TJSONArray.Create)
	./$(COMPILER) -Fulib/rtl -Fulib/rtl/platform/posix test/test_ctor_arrayofconst_overload_b298.pas /tmp/test_ctor_arrayofconst_overload_b29826
	test "$$(/tmp/test_ctor_arrayofconst_overload_b29826)" = "$$(printf 'noarg n=-1\narr n=3')"
	# a PARENTHESISED expression keeps its class id: (b as T)[i] / (b as T).ClassName
	./$(COMPILER) test/test_paren_expr_class_b297.pas /tmp/test_paren_expr_class_b29726
	test "$$(/tmp/test_paren_expr_class_b29726)" = "$$(printf 'direct index   : 20\nas-cast index  : 20\nas-cast chained: TB\nas-cast member : TArr\nas-cast inherit: TRUE')"
	# a class-reference OP chained after a value: d.Self_.ClassName / .InheritsFrom
	./$(COMPILER) test/test_classref_op_chained_b296.pas /tmp/test_classref_op_chained_b29626
	test "$$(/tmp/test_classref_op_chained_b29626)" = "$$(printf 'TD\nTRUE')"
	# `for F in <property>` -- a container EXPRESSION with GetEnumerator, not a bare variable
	./$(COMPILER) test/test_forin_property_b295.pas /tmp/test_forin_property_b29526
	test "$$(/tmp/test_forin_property_b29526)" = "$$(printf '1 2 3 \n1 2 3 \n7 8 9 ')"
	# the property `index` specifier (several properties sharing one accessor)
	./$(COMPILER) test/test_property_index_b293.pas /tmp/test_property_index_b29326
	test "$$(/tmp/test_property_index_b29326)" = "$$(printf '  [set idx=0 -> TRUE]\n  [set idx=2 -> TRUE]\nStrict   =   [get idx=0]\nTRUE\nUseUTF8  =   [get idx=1]\nFALSE\nComments =   [get idx=2]\nTRUE')"
	# frozen inline strings (string[N]) on the cross backends: store, Length, and passing
	# one to a MANAGED string parameter (aarch64/arm32/i386 all missed TypeIsFrozenString)
	./$(COMPILER) test/test_frozen_string_cross_b305.pas /tmp/test_frozen_string_cross_b30526
	test "$$(/tmp/test_frozen_string_cross_b30526)" = "$$(printf 'len=5\nf=hello\nassigned=hello len=5\nbyvalue=5\nfirst=h\nderef=hello\nderef-arg=5\nre-len=2 re=hi re-arg=2')"
	# an overloaded method's BODY must not clobber a DIFFERENT overload's table entry
	# (fpjson: ten Insert(Index,...) bodies clobbered the one-arg Insert; verified vs FPC)
	./$(COMPILER) test/test_method_overload_arity_rebind_b315.pas /tmp/test_method_overload_b31526
	test "$$(/tmp/test_method_overload_b31526)" = "oneintstr(x)bool(T)dbl"
	# untyped string constants must be SCOPED: a routine's const must not leak into the
	# next routine and beat ITS const of the same name (verified against FPC)
	./$(COMPILER) test/test_string_const_scoping_b314.pas /tmp/test_string_const_scoping_b31426
	test "$$(/tmp/test_string_const_scoping_b31426)" = "$$(printf 'A=A-local\nB=B-local\nUsesOuter=outer-G\nShadowsOuter=inner-G\nOuterAgain=outer-G\nCombine=unit-level/outer-G')"
	# a VARIABLE in scope beats an untyped string CONSTANT of the same name: the const
	# table is not scoped, so a `const S` in one method silently replaced a later
	# method's `var S : TClass` with the constant's TEXT (verified against FPC)
	./$(COMPILER) test/test_local_var_beats_string_const_b313.pas /tmp/test_local_var_const_b31326
	test "$$(/tmp/test_local_var_const_b31326)" = "$$(printf 'from the const\n[from the var] / from the var\n[arg]|arg\n[global]')"
	# a source type ALIAS must beat the built-in type NAME of the same name (the chain ran
	# before the alias table, so a builtin silently won -- fatal for the compiler's own PWord)
	./$(COMPILER) test/test_typename_alias_wins_b304.pas /tmp/test_typename_alias_wins_b30426
	test "$$(/tmp/test_typename_alias_wins_b30426)" = "$$(printf 'TDateTime=8 (8, as Int64)\nCurrency =4 (4)\nValReal  =4 (4)\nComp     =4 (4)\nWideChar =1 (1)\nSizeInt  =2 (2)')"
	# built-in POINTER type names (PInteger/PByte/PDouble) in a type position AND a cast --
	# and a SOURCE declaration of the same name must still WIN (the compiler's own PWord)
	./$(COMPILER) test/test_builtin_pointer_types_b303.pas /tmp/test_builtin_pointer_types_b30326
	test "$$(/tmp/test_builtin_pointer_types_b30326)" = "$$(printf 'source PWord is ^NativeInt : TRUE\ncast via source PWord      : TRUE\nsource PInteger is ^Int64  : -5\nPByte      : 200\nPCardinal  : 4000000000\nPDouble    : 2.5\ndone')"
	# `^string` — a pointer to a MANAGED string: reading p^ segfaulted (@s gave the HANDLE,
	# not the variable's address)
	./$(COMPILER) test/test_deref_managed_string_b302.pas /tmp/test_deref_managed_string_b30226
	test "$$(/tmp/test_deref_managed_string_b30226)" = "$$(printf 'read      : orig\nafter write: changed\nvia proc  : via proc\ncopied    : via proc len=8\nlen via ^ : 8')"
	# `x in [constants]` is a BOOLEAN (it carried no type: printed 1/0, and `and` went bitwise)
	./$(COMPILER) test/test_in_is_boolean_b301.pas /tmp/test_in_is_boolean_b30126
	test "$$(/tmp/test_in_is_boolean_b30126)" = "$$(printf 'const enum : TRUE\nconst char : TRUE\nruntime    : TRUE\nvia bool   : TRUE\ncombined   : TRUE')"
	# a set constructor with a RUNTIME element, used with `in`
	./$(COMPILER) test/test_runtime_set_member_b294.pas /tmp/test_runtime_set_member_b29426
	test "$$(/tmp/test_runtime_set_member_b29426)" = "$$(printf '1: a\n2: b\n3: quote\n4: c\n5: d\nconst set: TRUE FALSE')"
	# VIRTUAL CLASS METHODS dispatch on the RUNTIME class (fpjson JSONType)
	./$(COMPILER) test/test_virtual_class_method_b290.pas /tmp/test_virtual_class_method_b29026
	test "$$(/tmp/test_virtual_class_method_b29026)" = "$$(printf 'base inst : 0 base\nmid  inst : 1 mid\nleaf inst : 2 mid  (Name inherited from TMid)\nnamed     : 0 1 2')"
	# a method's RETURN-TYPE class id must be recorded at its DECLARATION
	./$(COMPILER) test/test_decl_order_ret_recid_b291.pas /tmp/test_decl_order_ret_recid_b29126
	test "$$(/tmp/test_decl_order_ret_recid_b29126)" = "$$(printf '#1 #2 #3 ')"
	# CONSTANT initializers run BEFORE any unit initialization section
	./$(COMPILER) -Futest test/test_const_before_unit_init_b292.pas /tmp/test_const_before_unit_init_b29226
	test "$$(/tmp/test_const_before_unit_init_b29226)" = "$$(printf 'captured by init: [, ]\nunit const      : [, ]')"
	# a SELECTOR after an indexed-property read: obj.Items[i].Method, incl. as a call ARG
	./$(COMPILER) test/test_selector_after_property_b289.pas /tmp/test_selector_after_property_b28926
	test "$$(/tmp/test_selector_after_property_b28926)" = "$$(printf 'took 100\ntook 200\ntook 300\ntook 400\nchained: 200')"
	# TypeInfo(TEnum) + TypInfo enum reflection (GetEnumName / GetEnumValue)
	./$(COMPILER) -Fulib/rtl -Fulib/rtl/platform/posix test/test_typeinfo_enum_b288.pas /tmp/test_typeinfo_enum_b28826
	test "$$(/tmp/test_typeinfo_enum_b28826)" = "$$(printf 'count: 3\n  0 = Red\n  1 = Green\n  2 = Blue\nvalue of Green: 1\nvalue of green (ci): 1\nvalue of nope: -1\nout of range: []\n--- a second enum type:\njtUnknown jtNumber jtString jtBoolean jtNull jtArray jtObject ')"
	# a value cast to an ordinal type NAMED BY AN IDENTIFIER: WideChar(x) / QWord(x)
	./$(COMPILER) test/test_ident_ordinal_cast_b286.pas /tmp/test_ident_ordinal_cast_b28626
	test "$$(/tmp/test_ident_ordinal_cast_b28626)" = "$$(printf 'Byte(300)     = 44 (44)\nWord(300)     = 300 (300)\nWideChar(65)  = 65 (65)\nWideChar(300) = 300 (300)\nCardinal(...) = 4294967295 (4294967295)\nQWord(-1)     = 18446744073709551615\nNativeInt(5)  = 5 (5)')"
	# an `array of const` LITERAL passed to a METHOD (fpjson TJSONData.DoError)
	./$(COMPILER) -Fulib/rtl -Fulib/rtl/platform/posix test/test_arrayofconst_to_method_b287.pas /tmp/test_arrayofconst_to_method_b28726
	test "$$(/tmp/test_arrayofconst_to_method_b28726)" = "$$(printf 'direct: answer = 42\n  n=2 -> class: answer = 42')"
	# an initialised array of CLASS REFERENCES (elements are class names) -- const AND var
	./$(COMPILER) test/test_classref_array_const_b285.pas /tmp/test_classref_array_const_b28526
	test "$$(/tmp/test_classref_array_const_b28526)" = "$$(printf 'TBase TMid TLeaf \nTLeaf TBase TMid \nleaf<-base: TRUE\nbase<-leaf: FALSE')"
	# SET-typed default parameters (fpjson FormatJSON(Options: TFormatOptions = DefaultFormat))
	./$(COMPILER) test/test_set_default_param_b282.pas /tmp/test_set_default_param_b28226
	test "$$(/tmp/test_set_default_param_b28226)" = "$$(printf 'P1: (empty)\nP2: (empty)\nP3: AC\nP4: B\nP5 n=1 : C\nP3: B\nP5 n=2 : AB')"
	# property REDECLARATION `property Items;default;` (fpjson TJSONArray)
	./$(COMPILER) test/test_property_redecl_b283.pas /tmp/test_property_redecl_b28326
	test "$$(/tmp/test_property_redecl_b28326)" = "$$(printf 'base explicit: 7\nchild explicit: 9\nchild default: 11\nchild default read of 3: 9')"
	# array indexed by an ordinal TYPE: array[Boolean] / array[TEnum] / array[Char]
	./$(COMPILER) test/test_array_index_type_b284.pas /tmp/test_array_index_type_b28426
	test "$$(/tmp/test_array_index_type_b28426)" = "$$(printf 'sep[false]=[, ] sep[true]=[,]\nred green blue \ncounts[Green]=7\nflags[True]=42\ntab[A]=9\nok')"
	# unary `not` on an ARRAY ELEMENT / FIELD / DEREF must be BITWISE, not boolean
	./$(COMPILER) test/test_bitwise_not_lvalue_b280.pas /tmp/test_bitwise_not_lvalue_b28026
	test "$$(/tmp/test_bitwise_not_lvalue_b28026)" = "$$(printf 'byte elem : 5 (5)\nint elem  : 5 (5)\nint64 elem: 5 (5)\nrec byte  : 5 (5)\nrec int   : 5 (5)\nderef     : 5 (5)\nplain var : 5 (5)\nnot elem  : -3\nnot var   : -3\nbool elem : TRUE (TRUE)\nbool elem2: FALSE (FALSE)')"
	# constant SET EXPRESSIONS: one set const defined from another (+ - *)
	./$(COMPILER) test/test_set_const_expr_b281.pas /tmp/test_set_const_expr_b28126
	test "$$(/tmp/test_set_const_expr_b28126)" = "$$(printf 'S1: abc\nSA: bc\nSB: ac\nSC: ac\nSD: abc\nSE: acd\nSF: bc\nSG: bcd')"
	# managed-string store through an ADDRESS (class field / record field / array elem):
	# a frozen LITERAL is not a handle, and riscv32's IR_STORE_MEM stored the raw word
	./$(COMPILER) test/test_managed_store_via_addr_b279.pas /tmp/test_managed_store_via_addr_b27926
	test "$$(/tmp/test_managed_store_via_addr_b27926)" = "$$(printf 'field-lit=[field-lit]\nmethod-lit=[in-method-lit]\nmethod-cat=[cat:x]\nfield-var=[via-var]\nfield-self-cat=[via-var!]\nrec-lit=[rec-lit]\nrec-cat=[rec:via-var]\narr-lit=[arr-lit]\narr-cat=[arr:via-var]\narr-copy=[arr-lit]\nchar-lit=[z]')"
	# a callable METHOD POINTER built by hand from a TMethod record: the cast is a
	# reinterpret of the same {Code,Data} words (fpcunit's RunBare)
	./$(COMPILER) test/test_method_ptr_cast_b277.pas /tmp/test_method_ptr_cast_b27726
	test "$$(/tmp/test_method_ptr_cast_b27726)" = "$$(printf 'found Hello: TRUE\nhello n=7\nhello n=100\ntwice: 14\ntwice b: 200')"
	# TYPED metaclasses: any constructor name + class methods through `class of T`
	./$(COMPILER) test/test_typed_metaclass_b278.pas /tmp/test_typed_metaclass_b27826
	test "$$(/tmp/test_typed_metaclass_b27826)" = "$$(printf '1: base:x | tag of TBase\n2: derived:y | tag of TDerived\n3: TDerived')"
	# `E is <class-reference VALUE>` -- a TClass field/var, not a class name
	./$(COMPILER) test/test_is_classref_b276.pas /tmp/test_is_classref_b27626
	test "$$(/tmp/test_is_classref_b27626)" = "$$(printf 'leaf is mid (field): TRUE\nleaf is other (field): FALSE\nleaf is base (var): TRUE\nleaf is other (var): FALSE\nleaf is EMid (name): TRUE\nleaf is EOther (name): FALSE')"
	# `Self` in a CLASS method is the METACLASS, and the RUNTIME class: TDerived.M must
	# see Self=TDerived inside TBase.M, and a bare sibling call must propagate it
	./$(COMPILER) test/test_metaclass_self_b275.pas /tmp/test_metaclass_self_b27526
	test "$$(/tmp/test_metaclass_self_b27526)" = "$$(printf 'named: TBase TDerived TOther\nsuite: suite of TBase | suite of TDerived\ntagged: >> TDerived\nvia instance: TDerived\nvia instance suite: suite of TDerived\nvia classref: TOther\ninherits: TRUE FALSE')"
	# bare call to a sibling CLASS (static) method from inside a class method
	# (fpcunit's TAssert.FailEquals calling Fail) -- incl. overloads
	./$(COMPILER) test/test_class_method_bare_call_b272.pas /tmp/test_class_method_bare_call_b27226
	test "$$(/tmp/test_class_method_bare_call_b27226)" = "$$(printf 'helper: from class method\ntwice: 42\nover int: 7\nover str: seven\nv=42\nhelper: from instance method')"
	# TObject.ClassName / TClass.ClassName -- every class carries an RTTI header now,
	# so it answers for classes that publish nothing (fpcunit's GetN(C: TClass))
	./$(COMPILER) test/test_classname_b271.pas /tmp/test_classname_b27126
	test "$$(/tmp/test_classname_b27126)" = "$$(printf 'inst: TBase TDerived TPub\nparens: TBase\nclassref: TBase TDerived TPub\nnil: <NIL>\nvar: TDerived\nvar2: TBase\ndynamic: TDerived')"
	# System stack-frame intrinsics: get_frame / get_pc_addr / get_caller_stackinfo
	# (fpcunit's CallerAddr walks the saved-fp chain with them)
	./$(COMPILER) test/test_stack_frame_intrinsics_b270.pas /tmp/test_stack_frame_intrinsics_b27026
	test "$$(/tmp/test_stack_frame_intrinsics_b27026)" = "$$(printf 'frame nonnil: TRUE\npc nonnil: TRUE\nempty parens: TRUE\nwalk: TRUE\nper-site distinct: TRUE\nascending: TRUE')"
	# System type names that never existed (TDateTime was a 4-byte INT, not a Double)
	./$(COMPILER) test/test_system_type_names_b267.pas /tmp/test_system_type_names_b26726
	test "$$(/tmp/test_system_type_names_b26726)" = "$$(printf 'WideChar=2\nComp=8\nTDateTime=8\nCurrency=8\nSizeInt=8 SizeUInt=8\nPWideChar=8\nbools=4 2 1\ndt=1.75\nstr=hi hi')"
	# an UNKNOWN type name is an ERROR (it used to become a silent 4-byte Integer).
	# Positive half: forward `^` refs, named dyn-array types, AnsiChar/Int16 widths.
	./$(COMPILER) test/test_unknown_type_rejected_b266.pas /tmp/test_unknown_type_rejected_b26626
	test "$$(/tmp/test_unknown_type_rejected_b26626)" = "$$(printf 'fwd-ptr=1 2\nnamed-dynarray=3 7\nansichar=x size=1\nint16=30000 size=2')"
	# Negative half: a typo'd type name must FAIL to compile, not quietly become an Integer
	printf 'program t;\nvar x: Integr;\nbegin x := 1; end.\n' > /tmp/unknown_type_typo_b266.pas
	! ./$(COMPILER) /tmp/unknown_type_typo_b266.pas /tmp/unknown_type_typo_b26626 > /tmp/unknown_type_typo_b266.log 2>&1
	grep -q "unknown type: Integr" /tmp/unknown_type_typo_b266.log
	# `absolute` overlays SHARE storage (it was silently ignored -> independent variable)
	./$(COMPILER) test/test_absolute_overlay_b265.pas /tmp/test_absolute_overlay_b26526
	test "$$(/tmp/test_absolute_overlay_b26526)" = "$$(printf 'global=4 4\nglobal=9 9\nlocal=7 7\nlocal=11 11\nreinterp=4294967295')"
	# class sealed/abstract, method `final`, and System.Assert (a user's own Assert wins)
	./$(COMPILER) test/test_assert_sealed_final_b264.pas /tmp/test_assert_sealed_final_b26426
	test "$$(/tmp/test_assert_sealed_final_b26426)" = "$$(printf 'B\nS\nasserts-passed')"
	# a FAILING assert reports and halts with 227 (FPC's assertion runtime error)
	printf 'program a; begin Assert(1=2, "boom"); end.\n' | tr '"' "'" > /tmp/assert_fail_b264.pas
	./$(COMPILER) /tmp/assert_fail_b264.pas /tmp/assert_fail_b26426
	! /tmp/assert_fail_b26426 > /tmp/assert_fail_b264.out 2>&1; test "$$?" = "0"
	test "$$(cat /tmp/assert_fail_b264.out)" = "Assertion failed: boom"
	# `const` / `class const` sections inside a class body; qualified TFoo.K access
	./$(COMPILER) test/test_class_const_b263.pas /tmp/test_class_const_b26326
	test "$$(/tmp/test_class_const_b26326)" = "$$(printf 'rec-x=8 rec-name=rec\nn=19\ngreeting=hi\nqualified=16 3')"
	# `strict private` / `strict protected`; a published section after them still reflects
	./$(COMPILER) -Fulib/rtl -Fulib/rtl/platform/posix test/test_strict_visibility_b262.pas /tmp/test_strict_visibility_b26226
	test "$$(/tmp/test_strict_visibility_b26226)" = "$$(printf 'x=2\npublished-count=1\npublished=TestVisible\nbump-hidden=TRUE')"
	# Int8/Int16/Int32 and TClass are real type names (they silently became 4-byte Integers)
	./$(COMPILER) test/test_int_sized_names_b261.pas /tmp/test_int_sized_names_b26126
	test "$$(/tmp/test_int_sized_names_b26126)" = "$$(printf 'Int8=1\nInt16=2\nInt32=4\nInt64=8\nTClass=8\nTObject=8\nint16-val=30000\nint8-val=-128\nclassref-nonnil=TRUE')"
	# System.LineEnding with no `uses`; a source's own LineEnding still wins
	./$(COMPILER) test/test_lineending_b260.pas /tmp/test_lineending_b26026
	test "$$(/tmp/test_lineending_b26026)" = "$$(printf 'const-concat-len=3\nis-lf=TRUE\nexpr-len=2\nle-len=1')"
	# TFPList — FPC's plain pointer list, the name its sources actually write
	./$(COMPILER) -Fulib/rtl -Fulib/rtl/platform/posix test/test_tfplist_b259.pas /tmp/test_tfplist_b25926
	test "$$(/tmp/test_tfplist_b25926)" = "$$(printf 'count=3\nidx-b=1\nitem0=10\nafter-delete=2 item0=20\nafter-remove=1 item0=20\nis-tlist=TRUE\nafter-clear=0')"
	# published-method RTTI: discover by name, bind, and RUN (feature-rtti-method-reflection)
	./$(COMPILER) -Fulib/rtl -Fulib/rtl/platform/posix test/test_rtti_method_reflection_b254.pas /tmp/test_rtti_method_reflection_b25426
	test "$$(/tmp/test_rtti_method_reflection_b25426)" = "$$(printf 'class=TMyCase\ncount=3\nmethod=TestAlpha\nmethod=TestBeta\nmethod=TestInherited\nfind-helper=FALSE\nfind-missing=FALSE\nfind-lowercase=TRUE\nlog=AB\nhelper-assigned=FALSE\ncls-name=TMyCase\ncls-count=3\ncls-method=TestAlpha addr=TRUE\ncls-method=TestBeta addr=TRUE\ncls-method=TestInherited addr=TRUE')"
	# `packed array` is legal on a FIELD/var, not just `packed record`
	./$(COMPILER) test/test_packed_array_field_b258.pas /tmp/test_packed_array_field_b25826
	test "$$(/tmp/test_packed_array_field_b25826)" = "$$(printf 'sum=22\nelems=7 9')"
	# TObject.GetInterface: GUID lookup over the class interface table (feature-tobject-getinterface-guid-table)
	./$(COMPILER) test/test_getinterface_guid_b257.pas /tmp/test_getinterface_guid_b25726
	test "$$(/tmp/test_getinterface_guid_b25726)" = "$$(printf 'qualified=TRUE\ncall=42\nmiss=FALSE\nbare=TRUE\ncall2=42')"
	# FPC spelling: TObject.MethodAddress/MethodName with NO uses; a user method shadows
	./$(COMPILER) test/test_tobject_methodaddress_b256.pas /tmp/test_tobject_methodaddress_b25626
	test "$$(/tmp/test_tobject_methodaddress_b25626)" = "$$(printf 'found-alpha=TRUE\nname-of-it=TestAlpha\ncase-insensitive=TRUE\nfound-inherited=TRUE\nfound-private=FALSE\nfound-missing=FALSE\nname-of-nil=[]\nran TestAlpha\nshadowed=zzz\nshadow-nil=TRUE')"
	# High/Low of ordinal types in const expressions (bug-pascal-high-low-in-const-expr)
	./$(COMPILER) test/test_high_low_const_expr.pas /tmp/test_high_low_const_expr26
	test "$$(/tmp/test_high_low_const_expr26)" = "$$(printf '256\n256\n255 -32768 2\n2147483646\n7\n1')"
	# {$I} -Fi search + hard error on miss (bug-pascal-include-search-silent-miss)
	./$(COMPILER) -Fitest/incdir_fi test/test_include_fi_search.pas /tmp/test_include_fi26
	test "$$(/tmp/test_include_fi26)" = "fi-ok"
	! ./$(COMPILER) test/test_include_miss_fails.pas /tmp/test_include_miss26 2>/dev/null
	# with TFoo.Create: single evaluation + with-scoped property/method/Free
	./$(COMPILER) test/test_with_class_create.pas /tmp/test_with_class_create26
	test "$$(/tmp/test_with_class_create26)" = "$$(printf '21\n42\ncreates=1')"
	# open-array args from record fields + indirect-call writeback + High(rec.fieldarr)
	./$(COMPILER) test/test_open_array_field_args.pas /tmp/test_open_array_field26
	test "$$(/tmp/test_open_array_field26)" = "$$(printf '15 3\nhb=3 hd=15\ndirect: 42\nhb=3 hd=15\nindirect: 74\nhb=3 hd=15\nwith: 106')"
	# {$SCOPEDENUMS}: scoped members + TEnum.member access (bug-pascal-scopedenums-ignored)
	./$(COMPILER) test/test_scopedenums.pas /tmp/test_scopedenums26
	test "$$(/tmp/test_scopedenums26)" = "$$(printf '0\n2\n1\ncase-ok')"
	# virtual/indirect calls: managed-string arg materialization + string->Pointer skip
	./$(COMPILER) --mimic-fpc test/test_virtual_call_string_args.pas /tmp/test_virtual_call_string26
	test "$$(/tmp/test_virtual_call_string26)" = "$$(printf 'v-len=6 d1=112\nv-len=2 d1=120\ni-len=5 d1=97')"
	# generic record/array/procvar templates (feature-pascal-generic-nonclass-templates)
	./$(COMPILER) test/test_generic_nonclass.pas /tmp/test_generic_nonclass26
	test "$$(/tmp/test_generic_nonclass26)" = "$$(printf '7\n20\n42')"
	# named operators :=/Explicit/Inc/Dec on records (feature-pascal-class-management-operators slice 1)
	./$(COMPILER) test/test_named_operators.pas /tmp/test_named_operators26
	test "$$(/tmp/test_named_operators26)" = "ok"
	# operator enumerator drives for-in (feature-pascal-class-management-operators slice 2)
	./$(COMPILER) test/test_operator_enumerator.pas /tmp/test_operator_enum26
	test "$$(/tmp/test_operator_enum26)" = "$$(printf '10\n20\n30')"
	# const array-of-record named-field initializers + string-alias cast passthrough
	./$(COMPILER) --mimic-fpc test/test_const_array_of_record.pas /tmp/test_const_arr_rec26
	test "$$(/tmp/test_const_arr_rec26)" = "$$(printf 'AND=1\nOR=2\nXOR=3\n2')"
	# managed arg -> const ShortString param conversion temp
	./$(COMPILER) --mimic-fpc test/test_shortstring_param_conv.pas /tmp/test_ssparam26
	test "$$(/tmp/test_ssparam26)" = "TRUE"
	# writeln of ShortString params (bug-pascal-writeln-shortstring-param)
	./$(COMPILER) --mimic-fpc test/test_writeln_shortstring_param.pas /tmp/test_wsp26
	test "$$(/tmp/test_wsp26)" = "$$(printf 'got=HELLO len=5\nm=WORLD')"
	# FPC variable typecast var args + type-keyword Dec targets
	./$(COMPILER) --mimic-fpc test/test_varcast_and_dec.pas /tmp/test_vcd26
	test "$$(/tmp/test_vcd26)" = "$$(printf '42\n65')"
	# TObject(expr).Free statement
	./$(COMPILER) --mimic-fpc test/test_tobject_cast_free.pas /tmp/test_tocf26
	test "$$(/tmp/test_tocf26)" = "ok"
	# array-valued field in a typed record constant (TGuid D4 shape)
	./$(COMPILER) --mimic-fpc test/test_record_const_array_field.pas /tmp/test_rcaf26
	test "$$(/tmp/test_rcaf26)" = "$$(printf '132096 192 70')"
	# builtin TGuid (System type) resolves without a uses
	./$(COMPILER) --mimic-fpc test/test_builtin_tguid.pas /tmp/test_tguid26
	test "$$(/tmp/test_tguid26)" = "$$(printf '132096 192 70 16')"
	# builtin TObject class: var o: TObject; o := TObject.Create
	./$(COMPILER) --mimic-fpc test/test_builtin_tobject.pas /tmp/test_tobj26
	test "$$(/tmp/test_tobj26)" = "$$(printf 'FALSE\n42\nFALSE')"
	./$(COMPILER) test/test_bare_property.pas /tmp/test_bare_property26
	test "$$(/tmp/test_bare_property26)" = "$$(printf 'num=21\nnum2=25\ndbl=50\nflagzero=TRUE\nflagset=TRUE')"
	./$(COMPILER) test/test_ansistring.pas /tmp/test_ansistring26
	test "$$(/tmp/test_ansistring26)" = "$$(printf '0\nInitially empty ok\nHello\n5\nHello\nAssignment equal ok\nhello\nHello\nCOW index write ok\nLocalString\n11\nLocal equal ok\nX\nChar assign ok\nHello World!\nHello\nHello World!\n0\nClear empty ok')"
	./$(COMPILER) test/test_string_ordering.pas /tmp/test_string_ordering26
	test "$$(/tmp/test_string_ordering26)" = "$$(printf '101001\n10\n011010\n101\n110')"
	./$(COMPILER) test/test_set_of_char_const.pas /tmp/test_set_of_char_const26
	test "$$(/tmp/test_set_of_char_const26)" = "$$(printf '65\n1\n0\n1\n0\n120')"
	./$(COMPILER) test/test_indexed_property.pas /tmp/test_indexed_property26
	test "$$(/tmp/test_indexed_property26)" = "$$(printf '99\n7\n42\n10\n30\n55\n88')"
	./$(COMPILER) test/test_many_properties.pas /tmp/test_many_properties26
	test "$$(/tmp/test_many_properties26)" = "$$(printf '11\nTRUE\n99')"
	./$(COMPILER) test/test_overload_record_identity.pas /tmp/test_overload_record_identity26
	test "$$(/tmp/test_overload_record_identity26)" = "$$(printf '11.0\n37.0\nvec2\nthing')"
	./$(COMPILER) test/test_unicodestring_alias.pas /tmp/test_unicodestring_alias26
	test "$$(/tmp/test_unicodestring_alias26)" = "$$(printf 'abc\nhello\n5\ne\neq\nhello!\n2')"
	./$(COMPILER) test/test_missing_diagnostics_fail.pas /tmp/test_missing_diagnostics26
	test "$$(/tmp/test_missing_diagnostics26)" = "$$(printf 'textfile=text\nTRUE')"
	! ./$(COMPILER) test/test_default_textfile_fail.pas /tmp/test_dtf26 > /tmp/test_dtf.log 2>&1
	grep -q "Default: file types are not allowed" /tmp/test_dtf.log
	! ./$(COMPILER) test/test_file_type_fail.pas /tmp/test_ftf26 > /tmp/test_ftf.log 2>&1
	grep -q "file types are not supported" /tmp/test_ftf.log
	! ./$(COMPILER) test/test_default_filefield_fail.pas /tmp/test_dff26 > /tmp/test_dff.log 2>&1
	grep -q "record type contains a file field" /tmp/test_dff.log
	! ./$(COMPILER) test/test_forin_string_char_fail.pas /tmp/test_fsc26 > /tmp/test_fsc.log 2>&1
	grep -q "loop variable must be of type Char" /tmp/test_fsc.log
	! ./$(COMPILER) test/test_record_self_field_fail.pas /tmp/test_rsf26 > /tmp/test_rsf.log 2>&1
	grep -q "record field cannot be of the enclosing record type" /tmp/test_rsf.log
	! ./$(COMPILER) test/test_record_class_var_fail.pas /tmp/test_rcv26 > /tmp/test_rcv.log 2>&1
	grep -q "class var is not allowed in a record type" /tmp/test_rcv.log
	! ./$(COMPILER) test/test_enum_pointer_compare_fail.pas /tmp/test_epc26 > /tmp/test_epc.log 2>&1
	grep -q "cannot compare an enum with a pointer" /tmp/test_epc.log
	! ./$(COMPILER) test/test_forin_enum_holes_fail.pas /tmp/test_feh26 > /tmp/test_feh.log 2>&1
	grep -q "non-contiguous values" /tmp/test_feh.log
	./$(COMPILER) test/test_delphi_generics.pas /tmp/test_delphi_generics26
	test "$$(/tmp/test_delphi_generics26)" = "$$(printf '42\nhi')"
	./$(COMPILER) test/test_inline_array_field_const_bound.pas /tmp/test_inline_array_field_const_bound26
	test "$$(/tmp/test_inline_array_field_const_bound26)" = "$$(printf '0\n70\n6\n103')"
	./$(COMPILER) test/test_symslot_stale_ndims.pas /tmp/test_symslot_stale_ndims26
	test "$$(/tmp/test_symslot_stale_ndims26)" = "136"
	! ./$(COMPILER) test/test_array_member_fail.pas /tmp/test_amf26 > /tmp/test_amf.log 2>&1
	grep -q "an array variable has no members" /tmp/test_amf.log
	! ./$(COMPILER) test/test_overload_record_identity_fail.pas /tmp/test_overload_record_identity_fail26 > /tmp/test_overload_record_identity_fail.log 2>&1
	grep -q "no overload of Dot matches" /tmp/test_overload_record_identity_fail.log
	./$(COMPILER) test/test_virtual_managed_arg.pas /tmp/test_virtual_managed_arg26
	test "$$(/tmp/test_virtual_managed_arg26)" = "$$(printf '2\ncherry\napple')"
	./$(COMPILER) test/test_stream_methods.pas /tmp/test_stream_methods26
	test "$$(/tmp/test_stream_methods26)" = "$$(printf '65 66 67\n3 3')"
	./$(COMPILER) test/test_r_directive.pas /tmp/test_r_directive26
	test "$$(/tmp/test_r_directive26)" = "42"
	./$(COMPILER) -Itest test/test_cond_comment_skip.pas /tmp/test_cond_comment_skip26
	test "$$(/tmp/test_cond_comment_skip26)" = "42"
	./$(COMPILER) test/test_const_string_concat.pas /tmp/test_const_string_concat26
	test "$$(/tmp/test_const_string_concat26)" = "$$(printf 'AB\n2\nABC\n3\nfoobar\nx-y\n65 66')"
	./$(COMPILER) test/test_const_string_index.pas /tmp/test_const_string_index26
	test "$$(/tmp/test_const_string_index26)" = "$$(printf '58\n58\nX:\n:\n[:]\nab\n30 30')"
	./$(COMPILER) test/test_typed_string_const.pas /tmp/test_typed_string_const26
	test "$$(/tmp/test_typed_string_const26)" = "$$(printf 'ABCDEF\nfoobar\nABC\nB\nABCDEF\n6\nlocal!')"
	./$(COMPILER) test/test_byval_record_temp.pas /tmp/test_byval_record_temp26
	test "$$(/tmp/test_byval_record_temp26)" = "$$(printf '11 22 33\n15 15 15\n8 9 10')"
	./$(COMPILER) test/test_int_arg_to_float_param.pas /tmp/test_int_arg_to_float_param26
	test "$$(/tmp/test_int_arg_to_float_param26)" = "$$(printf '80.0\n50.0\n1.0 2.0 3.0\n2.500 2.500 2.500')"
	./$(COMPILER) test/test_record_temp_byval_arg.pas /tmp/test_record_temp_byval_arg26
	test "$$(/tmp/test_record_temp_byval_arg26)" = "$$(printf '18\n46')"
	./$(COMPILER) test/test_ctor_string_literal_arg.pas /tmp/test_ctor_string_literal_arg26
	test "$$(/tmp/test_ctor_string_literal_arg26)" = "$$(printf 'field:hello\nc1\nafter1\nc2\nafter2\nc3\nc4\nafter3\nmsg:hello\nafter4')"
	./$(COMPILER) test/test_single_in_aggregate.pas /tmp/test_single_in_aggregate26
	test "$$(/tmp/test_single_in_aggregate26)" = "$$(printf '1.5 2.5 3.5\n9.500 8.250 7.125\n2.0 4.0 6.0\n10.0')"
	./$(COMPILER) test/test_dynarray_field.pas /tmp/test_dynarray_field26
	test "$$(/tmp/test_dynarray_field26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_dynarray_torture.pas /tmp/test_dynarray_torture26
	test "$$(/tmp/test_dynarray_torture26 | tail -1)" = "total ok 27 / 27"
	# --threadsafe I/O statement lock: reentrant (write-arg writes), single-thread output unchanged
	./$(COMPILER) --threadsafe test/test_threadsafe_io_lock.pas /tmp/test_threadsafe_io_lock26
	test "$$(/tmp/test_threadsafe_io_lock26)" = "$$(printf 'outer inner 21\n42\nline1 10\nline2 20\nline3 30\ndone')"
	# Move/FillChar with no uses (builtin home, FPC System parity; overlap-safe Move pinned)
	./$(COMPILER) test/test_move_fillchar_nouses.pas /tmp/test_move_fillchar_nouses26
	test "$$(/tmp/test_move_fillchar_nouses26 | tail -1)" = "total ok 4 / 4"
	# literal/char concat in a loop must not eat stack (managed typing; frozen carve documented)
	./$(COMPILER) test/test_concat_loop_stack.pas /tmp/test_concat_loop_stack26
	test "$$(/tmp/test_concat_loop_stack26)" = "$$(printf 'pI\nab0z\nbad=0')"
	# anonymous inline record types (var x: record ... end) incl nested/packed/variant/managed-field
	./$(COMPILER) test/test_anonymous_record.pas /tmp/test_anonymous_record26
	test "$$(/tmp/test_anonymous_record26 | tail -1)" = "total ok 8 / 8"
	# all 13 former hard-keyword intrinsics are soft keywords: declarable as identifiers, intrinsics/statements unaffected when unshadowed
	./$(COMPILER) test/test_soft_keyword_length.pas /tmp/test_soft_keyword_length26
	test "$$(/tmp/test_soft_keyword_length26 | tail -1)" = "total ok 19 / 19"
	# signal runtime: SetSignalHandler hooks fire + program survives; nil-revert dies killed-by-SIGTERM (143)
	./$(COMPILER) test/test_signal_handlers.pas /tmp/test_signal_handlers26
	test "$$(/tmp/test_signal_handlers26; echo "exit=$$?")" = "$$(printf 'usr1=2 int=1 term=1\nreverted\nexit=143')"
	# rust frontend else-if self-host miscompile regression (bug-selfhost-multifn-ifelse-miscompile):
	# 3-fn program, one if/else-if/else-return chain + call; classify(1)=20 -> exit 20. Also under --strict-ir (0 IR_UNSUPPORTED).
	./$(COMPILER) test/test_rust_else_if.rs /tmp/test_rust_else_if26
	/tmp/test_rust_else_if26; test "$$?" = "20"
	./$(COMPILER) --strict-ir test/test_rust_else_if.rs /tmp/test_rust_else_if_si26
	/tmp/test_rust_else_if_si26; test "$$?" = "20"
	# Rust frontend ports-back pass: println!/print! (format splitter), [T; N]
	# arrays (repeat/list literals, indexing, .len()), borrowed slices &a[lo..hi]
	# (s[i] rw, s.len()), for-in ranges (../..=) -- existing IR only.
	./$(COMPILER) test/test_rust_advanced.rs /tmp/test_rust_advanced26
	test "$$(/tmp/test_rust_advanced26)" = "$$(printf 'total 610\na3 9 s0 1 s1 4 slen 2\np 3 4\ncircle 75')"
	# Rust chess-corpus milestone (feature-rust-corpus-chess): C-style port of the
	# nextlevel engine's movegen core -- slices through fns, bitless mailbox, full
	# legality filtering. Perft exact through depth 3 (no EP/castle before ply 4).
	./$(COMPILER) test/test_rust_chess_perft.rs /tmp/test_rust_chess_perft26
	test "$$(/tmp/test_rust_chess_perft26)" = "$$(printf 'perft1 20\nperft2 400\nperft3 8902')"
	# Rust tuple structs — two field-bearing structs, smaller first
	# (bug-uclass-field-window-stale-base fixed: second struct's field window re-bases)
	./$(COMPILER) test/test_rust_tuple_struct.rs /tmp/test_rust_tuple26
	test "$$(/tmp/test_rust_tuple26)" = "$$(printf 'a 300 b 44 s 7')"
	# Rust associated fns + Self (Type::fn / Self::fn call paths, mixed with methods)
	./$(COMPILER) test/test_rust_assoc_fns.rs /tmp/test_rust_assoc26
	test "$$(/tmp/test_rust_assoc26)" = "$$(printf 'v 42 comb 75')"
	# Ada frontend skeleton (feature-esoteric-ada): for-range accumulate, if/elsif/else,
	# while, bare loop + exit-when, Put_Line -- all lowering onto existing shared IR.
	./$(COMPILER) test/test_ada_skeleton.adb /tmp/test_ada_skeleton26
	test "$$(/tmp/test_ada_skeleton26)" = "$$(printf 'sum correct\nwhile iter\nwhile iter\nwhile iter\nexit-when correct\nseven correct')"
	# Zig frontend skeleton (feature-zig-frontend, esoteric probe): fns/calls/recursion,
	# var/const inference, if/else-if, while + continue-expr, range for (exclusive hi),
	# break/continue, integer / lowered as trunc div, std.debug.print {} placeholders.
	./$(COMPILER) test/test_zig_skeleton.zig /tmp/test_zig_skeleton26
	test "$$(/tmp/test_zig_skeleton26)" = "$$(printf 'add gives 5\nscratch 50\nfor-sum 10\nevens 5\nodd-sum 25\nclassify ok\nfib(10) is 55\npair 2 and 4')"
	# Zig frontend sub-ticket 2 (zig-structs-and-pointers): struct decl/literal/fields,
	# *T pointers (&x, p.*, pointer params), [N]T fixed arrays + .len -- existing IR only.
	./$(COMPILER) test/test_zig_structs.zig /tmp/test_zig_structs26
	test "$$(/tmp/test_zig_structs26)" = "$$(printf 'dist2 25\nq 10 4\nsquares sum 30 len 5\nv 42\nsum 31')"
	# Zig frontend theoretic-completion pass: switch (if-chain), defer/errdefer
	# (reverse replay at exits), optionals ?T (null/if-capture/orelse/.?), error
	# unions !T (global-slot errno convention: return error.X/try/catch/catch |e|),
	# minimal slices (a[lo..hi], s[i] rw, s.len) -- all parse-time desugar, no new IR.
	./$(COMPILER) test/test_zig_advanced.zig /tmp/test_zig_advanced26
	test "$$(/tmp/test_zig_advanced26)" = "$$(printf 'c0 100 c1 200 c2 200 c9 300\nok 3 bad -1\nt1 7 t2 -2\nunderflow caught 2\nalways\nr1 10\nalways\ncleanup\nr2 -1\nnone\nsome 42\norelse 42 unwrap 42\norelse2 7\nslices 60999\ngen 9 7 100\nend\nmain done')"
	# LOLCODE frontend skeleton (feature-esoteric-lolcode, esoteric probe): HAI/KTHXBYE,
	# I HAS A/ITZ, VISIBLE, R assign, prefix ops (SUM OF..), BOTH SAEM/DIFFRINT + O RLY?,
	# IM IN YR loop + GTFO, SMOOSH string concat -- all on existing shared IR.
	./$(COMPILER) test/test_lolcode_skeleton.lol /tmp/test_lolcode_skeleton26
	test "$$(/tmp/test_lolcode_skeleton26)" = "$$(printf 'HAI WORLD\ny is 42\nsaem correct\nacc is 15\nsmoosh works')"
	# Whitespace frontend skeleton (feature-esoteric-whitespace, esoteric probe):
	# tokenless char-level frontend, stack-machine instructions folded into AST
	# expression trees at compile time (push/dup/discard, add/sub/mul/div/mod,
	# out-char/out-number). Prints Hi\n40\n2\n36.
	./$(COMPILER) test/test_ws_skeleton.ws /tmp/test_ws_skeleton26
	test "$$(/tmp/test_ws_skeleton26)" = "$$(printf 'Hi\n40\n2\n36')"
	# Erlang frontend skeleton (esoteric probe on feature-erlang-frontend-scoping):
	# multi-clause pattern dispatch (literals + variable binds + when guards),
	# recursion, single-assignment, io:format ~p placeholders.
	./$(COMPILER) test/test_erlang_skeleton.erl /tmp/test_erlang_skeleton26
	test "$$(/tmp/test_erlang_skeleton26)" = "$$(printf 'fact(5) is 120\nfib(10) is 55\nclassify: 1 2 3 4\ndiv gives 5 rem 1')"
	# Algol 60 frontend skeleton (feature-esoteric-algol, esoteric probe -- the
	# kinship test: Pascal's direct ancestor): declarations, :=, if/then/else,
	# while, for..step..until (incl. negative step), begin/end, out* I/O.
	./$(COMPILER) test/test_algol_skeleton.alg /tmp/test_algol_skeleton26
	test "$$(/tmp/test_algol_skeleton26)" = "$$(printf '55\n30\n 1.0500000000000000E+001\nkinship holds\n40')"
	# Fortran frontend skeleton (feature-esoteric-fortran, esoteric probe): implicit
	# first-letter typing (I-N int / else REAL->double), DO with step (incl. negative),
	# IF/ELSE, PRINT * with correct double formatting (ARG decimals sentinel -1).
	./$(COMPILER) test/test_fortran_skeleton.f90 /tmp/test_fortran_skeleton26
	test "$$(/tmp/test_fortran_skeleton26)" = "$$(printf 'sum is55\ndownsum is30\ny is 1.0500000000000000E+001\nsum correct\nreal correct')"
	# BASIC GOTO/GOSUB (bug-basic-goto-gosub-halts-program): real jumps via shared
	# AN_LABEL/AN_GOTO; nested GOSUB over the Int64 shift-register return stack;
	# LET-less assignment off-by-one. Previously GOTO/GOSUB silently HALTED (exit 0).
	./$(COMPILER) test/test_basic_goto_gosub.bas /tmp/test_basic_goto_gosub26
	test "$$(/tmp/test_basic_goto_gosub26)" = "$$(printf 'A\nB\nlooped 3\nsub1\nsub2\nsub1 back\nafter gosub\nsub2\ndone')"
	# the frontend's own comprehensive file: GOTO/GOSUB loop section + FOR/WHILE +
	# cross-language imports; used to print 1 line of ~21 and exit 0 (silently wrong)
	./$(COMPILER) test/test_basic_comprehensive.bas /tmp/test_basic_comprehensive26
	test "$$(/tmp/test_basic_comprehensive26 | wc -l)" = "21"
	# TObject virtual Destroy/Create override: FPC's universal `destructor Destroy; override;` compiles on a root class + dispatches; inherited Destroy/Create = root no-op
	./$(COMPILER) test/test_tobject_destroy_override.pas /tmp/test_tobject_destroy_override26
	test "$$(/tmp/test_tobject_destroy_override26)" = "$$(printf 'F\nc\nD\nA\nOK')"
	# override of a non-existent, non-Destroy/Create method still errors (guard)
	! ./$(COMPILER) test/test_override_bogus_rejected.pas /tmp/test_override_bogus26 > /tmp/test_override_bogus.log 2>&1
	grep -q "no virtual method found in parent chain" /tmp/test_override_bogus.log
	# a var section before a constructor/destructor method impl must not eat the ctor/dtor token as a var name
	./$(COMPILER) test/test_var_before_method_impl.pas /tmp/test_var_before_method_impl26
	test "$$(/tmp/test_var_before_method_impl26)" = "ctor=1 dtor=1"
	# FPC-compat: hint directives (deprecated/platform/...) ignored, SizeOf in const/default-param position
	./$(COMPILER) test/test_hint_sizeof.pas /tmp/test_hint_sizeof26
	test "$$(/tmp/test_hint_sizeof26)" = "total ok 8 / 8"
	# FPC-compat: default parameter values on class/interface methods + constructors (fgl's TFPSList.Create shape)
	./$(COMPILER) test/test_default_params_methods.pas /tmp/test_default_params_methods26
	test "$$(/tmp/test_default_params_methods26 | tail -1)" = "total ok 12 / 12"
	# FPC-compat: class function/procedure members in a generic class (fgl's ItemIsManaged shape)
	./$(COMPILER) test/test_generic_class_methods.pas /tmp/test_generic_class_methods26
	test "$$(/tmp/test_generic_class_methods26 | tail -1)" = "total ok 5 / 5"
	# forward class decl + full decl adding a base keeps fields on the stub's entry (metaclass-before-decl idiom)
	./$(COMPILER) test/test_forward_class_base.pas /tmp/test_forward_class_base26
	test "$$(/tmp/test_forward_class_base26 | tail -1)" = "total ok 6 / 6"
	# property through a class typecast (TButton(Sender).Caption shape) — was a silent offset-0 (VMT ptr) read
	./$(COMPILER) test/test_cast_property.pas /tmp/test_cast_property26
	test "$$(/tmp/test_cast_property26 | tail -1)" = "total ok 15 / 15"
	# multi-param generics <TKey, TData> + constrained type params (fgl TFPGMap/TFPGObjectList shapes)
	./$(COMPILER) test/test_generic_multiparam.pas /tmp/test_generic_multiparam26
	test "$$(/tmp/test_generic_multiparam26 | tail -1)" = "total ok 4 / 4"
	# parser gaps: impl-side `static;`/`reintroduce;` on a class function + PChar(expr)[i] indexing
	./$(COMPILER) test/test_impl_static_and_pchar_index.pas /tmp/test_impl_static_and_pchar_index26
	test "$$(/tmp/test_impl_static_and_pchar_index26 | tail -1)" = "total ok 5 / 5"
	# FPC-compat batch: System.-qualifier, Assigned, resourcestring, method directives, unqualified indexed properties
	./$(COMPILER) test/test_fpc_compat_batch.pas /tmp/test_fpc_compat_batch26
	test "$$(/tmp/test_fpc_compat_batch26 | tail -1)" = "total ok 11 / 11"
	# FPC-compat batch 2: method overloads, method pointers, setter-prop writes, nested class types, CreateFmt, mem builtins
	./$(COMPILER) -Fulib/rtl test/test_fpc_compat_batch2.pas /tmp/test_fpc_compat_batch226
	test "$$(/tmp/test_fpc_compat_batch226 | tail -1)" = "total ok 13 / 13"
	# flagship FPC-compat: compile+run REAL FPC 3.2.2 fgl.pp (skipped when fpcsrc absent)
	@if [ -d /usr/share/fpcsrc/3.2.2/rtl/objpas ]; then \
	  ./$(COMPILER) --mimic-fpc -Fu/usr/share/fpcsrc/3.2.2/rtl/objpas test/test_fgl_use.pas /tmp/test_fgl_use26 >/dev/null && \
	  test "$$(/tmp/test_fgl_use26 | tail -1)" = "map count=3 m[5]=50 m[2]=20" && echo "fgl(real FPC source): OK"; \
	else echo "fgl(real FPC source): SKIP (no fpcsrc)"; fi
	# implicit (sloppy) locals: --auto-locals infers int/string/for-counter/for-in from first assignment; default OFF still errors
	./$(COMPILER) --auto-locals test/test_auto_locals.pas /tmp/test_auto_locals26
	test "$$(/tmp/test_auto_locals26 2>/dev/null)" = "total ok 4 / 4"
	! ./$(COMPILER) test/test_auto_locals.pas /tmp/test_auto_locals_neg26 > /tmp/test_auto_locals_neg.log 2>&1
	grep -q "undefined variable" /tmp/test_auto_locals_neg.log
	# integer div/mod by zero = clean Runtime error 200 + exit 200 (not a raw SIGFPE core dump)
	./$(COMPILER) test/test_div_zero_re200.pas /tmp/test_div_zero_re20026
	test "$$(/tmp/test_div_zero_re20026 || echo "exit=$$?")" = "$$(printf '14 2 -14\nbefore\nRuntime error 200 (division by zero)\nexit=200')"
	test "$$(/tmp/test_div_zero_re20026 mod || echo "exit=$$?")" = "$$(printf '14 2 -14\nbefore\nRuntime error 200 (division by zero)\nexit=200')"
	# dynamic-array Insert/Delete intrinsics (FPC clamp semantics, fresh-temp refcount balance)
	./$(COMPILER) test/test_dynarray_insert_delete.pas /tmp/test_dynarray_insert_delete26
	test "$$(/tmp/test_dynarray_insert_delete26 | tail -1)" = "total ok 35 / 35"
	# frozen-string Result is per-call (reentrant) on direct/virtual/indirect calls
	./$(COMPILER) test/test_frozen_string_reentrant.pas /tmp/test_frozen_string_reentrant26
	test "$$(/tmp/test_frozen_string_reentrant26 | tail -1)" = "total ok 4 / 4"
	# inline AnsiString SetLength grow must double the LENGTH, not a reused oversized block's capacity (else OOM)
	./$(COMPILER) test/test_setlength_grow_capacity.pas /tmp/test_setlength_grow_capacity26
	test "$$(/tmp/test_setlength_grow_capacity26)" = "$$(printf 'len=101\nfirst=a\nlast=b\nSETLENGTH_CAP_OK')"
	# dynarray a+b is rejected at compile time (not a silent segfault)
	! ./$(COMPILER) test/test_dynarray_concat_rejected.pas /tmp/test_dynarray_concat_rejected26 > /tmp/test_dynarray_concat_rejected.log 2>&1
	grep -q "not supported for dynamic arrays" /tmp/test_dynarray_concat_rejected.log
	./$(COMPILER) test/test_method_implicit_field.pas /tmp/test_method_implicit_field26
	test "$$(/tmp/test_method_implicit_field26)" = "$$(printf '3\n2\n42\n0\n-1')"
	./$(COMPILER) test/test_method_read_write_unqualified.pas /tmp/test_method_rw_unqual26
	test "$$(/tmp/test_method_rw_unqual26)" = "$$(printf 'data=42\nr=43')"
	# inside a method, the class's own method shadows a same-name plain proc (sysutils.Move vs TGame.Move)
	./$(COMPILER) test/test_method_shadows_unit_proc.pas /tmp/test_method_shadows_unit_proc26
	test "$$(/tmp/test_method_shadows_unit_proc26)" = "$$(printf 'tick=50\npos=5\nsteps=3\nplainHits=0\nb0=7 b1=8\nplainHits2=2')"
	./$(COMPILER) test/test_forin_implicit_field.pas /tmp/test_forin_implicit_field26
	test "$$(/tmp/test_forin_implicit_field26)" = "$$(printf '10\n42\n3\n121')"
	./$(COMPILER) test/test_dynarray_global_after_method.pas /tmp/test_dynarray_global_after_method26
	test "$$(/tmp/test_dynarray_global_after_method26)" = "$$(printf '7\n121')"
	./$(COMPILER) test/test_forin_member_access.pas /tmp/test_forin_member_access26
	test "$$(/tmp/test_forin_member_access26)" = "$$(printf '42\n2\n42')"
	./$(COMPILER) test/test_object_ref_array_identity.pas /tmp/test_object_ref_array_identity26
	test "$$(/tmp/test_object_ref_array_identity26)" = "B"
	./$(COMPILER) test/test_call_result_member.pas /tmp/test_call_result_member26
	test "$$(/tmp/test_call_result_member26)" = "$$(printf 'rec\n7\nhello\n42\ntag:hello\nhello/tag:hello')"
	./$(COMPILER) test/test_collections.pas /tmp/test_collections26
	test "$$(/tmp/test_collections26)" = "$$(printf '100\n0\n81\n9801\n7\n328276\n0\n3\nalpha\ngamma\nBETA')"
	./$(COMPILER) test/test_generic_class_in_program.pas /tmp/test_generic_class_in_program26
	test "$$(/tmp/test_generic_class_in_program26)" = "$$(printf '7\nhi')"
	./$(COMPILER) test/test_nested_proc_sibling_call.pas /tmp/test_nested_proc_sibling_call26
	test "$$(/tmp/test_nested_proc_sibling_call26)" = "$$(printf 'a\nb-before\na7\nb-after\na7\na42\n3\n2\n1\n0\n15\n10005\n10')"
	./$(COMPILER) test/test_managed_var_param.pas /tmp/test_managed_var_param26
	test "$$(/tmp/test_managed_var_param26)" = "$$(printf '1\n1\n1\n1\n1\n6')"
	./$(COMPILER) test/test_managed_setlength_var.pas /tmp/test_managed_setlength_var26
	test "$$(/tmp/test_managed_setlength_var26)" = "$$(printf '1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_managed_setlength_growth.pas /tmp/test_managed_setlength_growth26
	test "$$(/tmp/test_managed_setlength_growth26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_cross_setlen_varparam.pas /tmp/test_setlen_varparam26
	test "$$(/tmp/test_setlen_varparam26)" = "$$(printf 'grow len=5\n11\n22\n33\n0\n0\nshrink len=2\n11\n22\ns len=2\nhello\nworld')"
	./$(COMPILER) test/test_managed_exception_cleanup.pas /tmp/test_managed_exception_cleanup26
	ulimit -v 800000; test "$$(/tmp/test_managed_exception_cleanup26)" = "1"
	./$(COMPILER) test/test_default_keyword.pas /tmp/test_default_keyword26
	test "$$(/tmp/test_default_keyword26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_op_record_result.pas /tmp/test_op_record_result26
	test "$$(/tmp/test_op_record_result26)" = "$$(printf '4 6\n4 6\n5 8\n4 6\n4 6\n4 6\n5 8\n110 220 330\n110 220 330')"
	./$(COMPILER) test/test_const_record_temp.pas /tmp/test_const_record_temp26
	test "$$(/tmp/test_const_record_temp26)" = "$$(printf '77\n42\n420\n42\n101')"
	./$(COMPILER) test/test_const_record_temp_managed.pas /tmp/test_const_record_temp_managed26
	test "$$(/tmp/test_const_record_temp_managed26)" = "$$(printf '7\n42\n42')"
	./$(COMPILER) test/test_set_runtime.pas /tmp/test_set_runtime26
	test "$$(/tmp/test_set_runtime26)" = "$$(printf 'TRUE TRUE FALSE\nTRUE\nFALSE TRUE\nFALSE TRUE TRUE FALSE\nTRUE TRUE TRUE FALSE\nTRUE FALSE TRUE')"
	./$(COMPILER) test/test_dynarray_copy.pas /tmp/test_dynarray_copy26
	test "$$(/tmp/test_dynarray_copy26)" = "$$(printf '3\n30\n40\n50\n2\n50\n60\n2\n30 60\n3\n1 10 100\n2 20 200\n3 30 300\n6 60')"
	./$(COMPILER) test/test_val_builtin.pas /tmp/test_val_builtin26
	test "$$(/tmp/test_val_builtin26)" = "$$(printf '5 0\n55 0\n0 2\n-42 0\n88 0\n0 1\n1000000000000 0\n0')"
	./$(COMPILER) test/test_managed_record_temp_init.pas /tmp/test_managed_record_temp_init26
	test "$$(/tmp/test_managed_record_temp_init26)" = "$$(printf '5! = 120\n5! = 120\n6! = 720')"
	./$(COMPILER) test/hello.pas /tmp/hello26
	test "$$(/tmp/hello26)" = "Hello, World!"
	./$(COMPILER) test/hello.c /tmp/hello_c26
	test "$$(/tmp/hello_c26)" = "Hello, World!"
	# 17..32-parameter C function definitions + calls (MAX_PROC_PARAMS=32; gcc oracle)
	# a global pointer initialised to &multidim_array[i][j][k]: only ONE subscript was
	# consumed, so the whole initializer was silently SKIPPED and the pointer stayed null
	./$(COMPILER) test/cglobal_addr_multidim_elem_b312.c /tmp/cglobal_addr_multidim_b31226
	test "$$(/tmp/cglobal_addr_multidim_b31226)" = "$$(printf '3d=77 off=200 want=200\n2d=66 off=17 want=17\n1d=55 off=5 want=5\n0 =44 off=0 want=0\nstored=11 22')"
	# a multidim LOCAL array of STRUCTS: the walker got nDims=1, so only the first
	# element was initialised and the rest stayed zero (silently)
	./$(COMPILER) test/cmultidim_struct_array_init_b311.c /tmp/cmultidim_struct_array_b31126
	test "$$(/tmp/cmultidim_struct_array_b31126)" = "$$(printf '2d=1 4 6\n3d=1 6 8\n2f=1 4 5 8\n1d=1 6')"
	# a multidim LOCAL array of POINTERS must honour its brace initializer (it was
	# silently SKIPPED -- every element read back nil; 1-D and multidim-int were fine)
	./$(COMPILER) test/cmultidim_ptr_array_init_b309.c /tmp/cmultidim_ptr_array_b30926
	test "$$(/tmp/cmultidim_ptr_array_b30926)" = "$$(printf 'braced=1 1\nflat=1 1\n3d=1 1\nderef3d=5\n1d=1\nints=1 6\nglobal2d=1 1\nglobal3d=1 1')"
	# a discarded expression statement must still be EVALUATED: a non-call root was an
	# IR orphan, so `f() ^ 3;` / `(void)(f()+1);` / `x = ((f()^K), 0);` never called f()
	./$(COMPILER) test/cdiscarded_expr_side_effects_b308.c /tmp/cdiscarded_expr_b30826
	test "$$(/tmp/cdiscarded_expr_b30826)" = "$$(printf 'bare-call=1\nbinop=1\ncast=1\nternary=1\ntwo-calls=2\nunary=1\ncomma-assign=1 g=0\ncomma-chain=2 x=9\ncomma-in-if=1')"
	# a struct-valued comma expression passed BY VALUE (segfaulted: a comma is not an
	# lvalue, so the record-by-value copy could not take its address); plus the left
	# operand's side effects, which must still run
	./$(COMPILER) test/ccomma_struct_arg_b307.c /tmp/ccomma_struct_arg_b30726
	test "$$(/tmp/ccomma_struct_arg_b30726)" = "$$(printf 'plain=10\ncomma=10\ncomma-big=10\nnested-comma=10\nside=2\nassign-comma=2 7 side=0\nassign-comma-big=10 side=1')"
	# anonymous bit-fields (`T : width` padding, `T : 0` alignment) -- the aggregate used
	# to be REJECTED and fell back to opaque: sizeof 0, every field garbage, silently
	./$(COMPILER) test/canon_bitfield_b310.c /tmp/canon_bitfield_b31026
	test "$$(/tmp/canon_bitfield_b31026)" = "$$(printf 'A size=4 a=5 b=6\nB size=16 x=11 y=22\nC size=4 a=5 b=6\nD size=8 a=5 b=6\nU size=8 f0=18446744073709551612\nA written a=7 b=1\nD written a=2 b=7')"
	# signed bitfields must sign-extend on read (they came back zero-extended on EVERY
	# backend; the C corpora all use unsigned bitfields, so csmith found it, not them)
	./$(COMPILER) test/csigned_bitfield_b306.c /tmp/csigned_bitfield_b30626
	test "$$(/tmp/csigned_bitfield_b30626)" = "$$(printf 'A.a=-5\nB.a=-3 B.b=-9 B.c=7\nC.a=-1\nD.a=140 D.b=560 D.c=423 D.d=-5\nlocal A.a=-2\nlocal B.a=3 B.b=-16 B.c=15\nmin5=-16\nmax5=15\nzero=0\nu4=15\nfull8=-7\nfull8max=127\nfull16=-300')"
	./$(COMPILER) test/cparams_17_32_b150.c /tmp/cparams_17_32_26
	test "$$(/tmp/cparams_17_32_26)" = "$$(printf 's=153\nt=528')"
	./$(COMPILER) test/cexpr_b.c /tmp/cexpr_b26
	/tmp/cexpr_b26; test "$$?" = "89"
	./$(COMPILER) test/cstmt_c.c /tmp/cstmt_c26
	/tmp/cstmt_c26; test "$$?" = "82"
	./$(COMPILER) test/cmulti_d.c /tmp/cmulti_d26
	/tmp/cmulti_d26; test "$$?" = "104"
	./$(COMPILER) test/cptr_b2.c /tmp/cptr_b226
	/tmp/cptr_b226; test "$$?" = "122"
	./$(COMPILER) test/cstruct_b3.c /tmp/cstruct_b326
	/tmp/cstruct_b326; test "$$?" = "62"
	./$(COMPILER) test/ccast_b4.c /tmp/ccast_b426
	/tmp/ccast_b426; test "$$?" = "102"
	# cast expression as a call argument (vararg + plain) — bug-c-cast-as-call-arg-parse-error
	./$(COMPILER) test/ccast_call_arg.c /tmp/ccast_call_arg26
	test "$$(/tmp/ccast_call_arg26)" = "v=20 s=22"
	./$(COMPILER) test/cloop_b5.c /tmp/cloop_b526
	/tmp/cloop_b526; test "$$?" = "28"
	./$(COMPILER) test/cfnptr_b6.c /tmp/cfnptr_b626
	/tmp/cfnptr_b626; test "$$?" = "91"
	./$(COMPILER) test/cfnptr_call_via_ptr_cast_b236.c /tmp/cfnptr_call_via_ptr_cast_b23626
	/tmp/cfnptr_call_via_ptr_cast_b23626; test "$$?" = "42"
	./$(COMPILER) test/ctypedef_struct_b7.c /tmp/ctypedef_struct_b726
	/tmp/ctypedef_struct_b726; test "$$?" = "51"
	./$(COMPILER) test/cstruct_fwd_interleave_b8.c /tmp/cstruct_fwd_interleave_b826
	/tmp/cstruct_fwd_interleave_b826; test "$$?" = "42"
	./$(COMPILER) test/cternary_b9.c /tmp/cternary_b926
	/tmp/cternary_b926; test "$$?" = "37"
	./$(COMPILER) test/cint_suffix_b10.c /tmp/cint_suffix_b1026
	/tmp/cint_suffix_b1026; test "$$?" = "42"
	./$(COMPILER) test/cbitnot_b11.c /tmp/cbitnot_b1126
	/tmp/cbitnot_b1126; test "$$?" = "6"
	./$(COMPILER) test/cparen_name_b12.c /tmp/cparen_name_b1226
	/tmp/cparen_name_b1226; test "$$?" = "30"
	./$(COMPILER) test/cswitch_b13.c /tmp/cswitch_b1326
	/tmp/cswitch_b1326; test "$$?" = "3"
	./$(COMPILER) test/cbuiltin_expect_b14.c /tmp/cbuiltin_expect_b1426
	/tmp/cbuiltin_expect_b1426; test "$$?" = "5"
	./$(COMPILER) test/cfnptr_deref_call_b15.c /tmp/cfnptr_deref_call_b1526
	/tmp/cfnptr_deref_call_b1526; test "$$?" = "42"
	./$(COMPILER) test/caddr_array_field_b16.c /tmp/caddr_array_field_b1626
	/tmp/caddr_array_field_b1626; test "$$?" = "42"
	./$(COMPILER) test/cpp_if_chain_b17.c /tmp/cpp_if_chain_b1726
	/tmp/cpp_if_chain_b1726; test "$$?" = "42"
	./$(COMPILER) test/cstr_concat_b18.c /tmp/cstr_concat_b1826
	/tmp/cstr_concat_b1826; test "$$?" = "42"
	./$(COMPILER) test/cstr_to_ptr_b19.c /tmp/cstr_to_ptr_b1926
	/tmp/cstr_to_ptr_b1926; test "$$?" = "42"
	./$(COMPILER) test/csizeof_constexpr_b20.c /tmp/csizeof_constexpr_b2026
	/tmp/csizeof_constexpr_b2026; test "$$?" = "42"
	./$(COMPILER) test/caddr_func_b21.c /tmp/caddr_func_b2126
	/tmp/caddr_func_b2126; test "$$?" = "42"
	./$(COMPILER) test/ccomma_expr_b22.c /tmp/ccomma_expr_b2226
	/tmp/ccomma_expr_b2226; test "$$?" = "42"
	./$(COMPILER) test/cstruct_array_stride_b23.c /tmp/cstruct_array_stride_b2326
	/tmp/cstruct_array_stride_b2326; test "$$?" = "42"
	./$(COMPILER) test/cfield_ptr_arith_b24.c /tmp/cfield_ptr_arith_b2426
	/tmp/cfield_ptr_arith_b2426; test "$$?" = "42"
	./$(COMPILER) test/cmacro_nested_self_b25.c /tmp/cmacro_nested_self_b2526
	/tmp/cmacro_nested_self_b2526; test "$$?" = "42"
	./$(COMPILER) test/cmacro_multiline_b26.c /tmp/cmacro_multiline_b2626
	/tmp/cmacro_multiline_b2626; test "$$?" = "42"
	./$(COMPILER) test/cincdec_value_b27.c /tmp/cincdec_value_b2726
	/tmp/cincdec_value_b2726; test "$$?" = "42"
	./$(COMPILER) test/cglobal_array_init_b28.c /tmp/cglobal_array_init_b2826
	/tmp/cglobal_array_init_b2826; test "$$?" = "42"
	./$(COMPILER) test/cglobal_char_array_str_init_b128.c /tmp/cglobal_char_array_str_init_b12826
	/tmp/cglobal_char_array_str_init_b12826; test "$$?" = "0"
	./$(COMPILER) test/cinline_struct_ptr_field_b129.c /tmp/cinline_struct_ptr_field_b12926
	/tmp/cinline_struct_ptr_field_b12926; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/src test/crtl_string_leaf_b130.c /tmp/crtl_string_leaf_b13026
	/tmp/crtl_string_leaf_b13026; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/include/sys -Ilib/crtl/src test/crtl_lfs64_aliases_b234.c /tmp/crtl_lfs64_aliases_b23426
	/tmp/crtl_lfs64_aliases_b23426; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/include/sys -Ilib/crtl/src test/crtl_stat_errno_enoent_b235.c /tmp/crtl_stat_errno_enoent_b23526
	/tmp/crtl_stat_errno_enoent_b23526; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/include/sys -Ilib/crtl/src test/crtl_posix_io_leaf_b238.c /tmp/crtl_posix_io_leaf_b23826
	/tmp/crtl_posix_io_leaf_b23826; test "$$?" = "42"
	./$(COMPILER) -DGUARD=42 -DON -DOFFME -UOFFME test/cdefine_flag_b239.c /tmp/cdefine_flag_b23926
	/tmp/cdefine_flag_b23926; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cmath_sqrt_correctly_rounded_b240.c /tmp/cmath_sqrt_b24026
	/tmp/cmath_sqrt_b24026; test "$$?" = "42"
	./$(COMPILER) test/cfnptr_deref_call_b241.c /tmp/cfnptr_deref_call_b24126
	/tmp/cfnptr_deref_call_b24126; test "$$?" = "42"
	./$(COMPILER) test/c_lua_tvalue_int_b131.c /tmp/c_lua_tvalue_int_b13126
	/tmp/c_lua_tvalue_int_b13126; test "$$?" = "42"
	./$(COMPILER) test/c_lua_opcode_decode_b132.c /tmp/c_lua_opcode_decode_b13226
	/tmp/c_lua_opcode_decode_b13226; test "$$?" = "42"
	./$(COMPILER) test/cglobal_array_elem_addr_b133.c /tmp/cglobal_array_elem_addr_b13326
	/tmp/cglobal_array_elem_addr_b13326; test "$$?" = "42"
	./$(COMPILER) test/cstruct_layout_stress_b134.c /tmp/cstruct_layout_stress_b13426
	/tmp/cstruct_layout_stress_b13426; test "$$?" = "42"
	./$(COMPILER) test/csizeof_paren_index_b29.c /tmp/csizeof_paren_index_b2926
	/tmp/csizeof_paren_index_b2926; test "$$?" = "42"
	./$(COMPILER) test/cmulti_decl_ptr_b30.c /tmp/cmulti_decl_ptr_b3026
	/tmp/cmulti_decl_ptr_b3026; test "$$?" = "42"
	./$(COMPILER) test/ccall_field_b31.c /tmp/ccall_field_b3126
	/tmp/ccall_field_b3126; test "$$?" = "42"
	./$(COMPILER) test/cmacro_paste_b32.c /tmp/cmacro_paste_b3226
	/tmp/cmacro_paste_b3226; test "$$?" = "42"
	./$(COMPILER) test/cgoto_label_b33.c /tmp/cgoto_label_b3326
	/tmp/cgoto_label_b3326; test "$$?" = "42"
	./$(COMPILER) test/cfloat_literal_b34.c /tmp/cfloat_literal_b3426
	/tmp/cfloat_literal_b3426; test "$$?" = "42"
	./$(COMPILER) test/cconst_divmod_b35.c /tmp/cconst_divmod_b3526
	/tmp/cconst_divmod_b3526; test "$$?" = "42"
	./$(COMPILER) test/ccomma_cond_b36.c /tmp/ccomma_cond_b3626
	/tmp/ccomma_cond_b3626; test "$$?" = "42"
	./$(COMPILER) test/carray_param_b37.c /tmp/carray_param_b3726
	/tmp/carray_param_b3726; test "$$?" = "42"
	./$(COMPILER) test/cmacro_obj_alias_b38.c /tmp/cmacro_obj_alias_b3826
	/tmp/cmacro_obj_alias_b3826; test "$$?" = "42"
	./$(COMPILER) test/cconst_cast_b39.c /tmp/cconst_cast_b3926
	/tmp/cconst_cast_b3926; test "$$?" = "42"
	./$(COMPILER) test/cmacro_stringize_b40.c /tmp/cmacro_stringize_b4026
	/tmp/cmacro_stringize_b4026; test "$$?" = "42"
	./$(COMPILER) test/cagg_init_local_b41.c /tmp/cagg_init_local_b4126
	/tmp/cagg_init_local_b4126; test "$$?" = "42"
	./$(COMPILER) test/cptr_diff_b42.c /tmp/cptr_diff_b4226
	/tmp/cptr_diff_b4226; test "$$?" = "42"
	./$(COMPILER) test/cassign_value_b43.c /tmp/cassign_value_b4326
	/tmp/cassign_value_b4326; test "$$?" = "42"
	./$(COMPILER) test/cnested_union_b44.c /tmp/cnested_union_b4426
	/tmp/cnested_union_b4426; test "$$?" = "42"
	./$(COMPILER) test/canon_agg_global_b45.c /tmp/canon_agg_global_b4526
	/tmp/canon_agg_global_b4526; test "$$?" = "42"
	./$(COMPILER) test/cunion_global_init_b46.c /tmp/cunion_global_init_b4626
	/tmp/cunion_global_init_b4626; test "$$?" = "42"
	./$(COMPILER) test/cglobal_scalar_init_b47.c /tmp/cglobal_scalar_init_b4726
	/tmp/cglobal_scalar_init_b4726; test "$$?" = "42"
	./$(COMPILER) test/cstruct_global_init_b48.c /tmp/cstruct_global_init_b4826
	/tmp/cstruct_global_init_b4826; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include test/cvarargs_int_b49.c /tmp/cvarargs_int_b4926
	/tmp/cvarargs_int_b4926; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include test/crecord_byval_param_b50.c /tmp/crecord_byval_param_b5026
	/tmp/crecord_byval_param_b5026; test "$$?" = "42"
	./$(COMPILER) test/cstatic_ptr_array_b51.c /tmp/cstatic_ptr_array_b5126
	/tmp/cstatic_ptr_array_b5126; test "$$?" = "42"
	./$(COMPILER) test/cfield_ptr_array_b52.c /tmp/cfield_ptr_array_b5226
	/tmp/cfield_ptr_array_b5226; test "$$?" = "42"
	./$(COMPILER) test/cunion_ptr_chain_b53.c /tmp/cunion_ptr_chain_b5326
	/tmp/cunion_ptr_chain_b5326; test "$$?" = "42"
	./$(COMPILER) test/cptrptr_clear_chain_b54.c /tmp/cptrptr_clear_chain_b5426
	/tmp/cptrptr_clear_chain_b5426; test "$$?" = "42"
	./$(COMPILER) test/coffsetof_array_field_b55.c /tmp/coffsetof_array_field_b5526
	/tmp/coffsetof_array_field_b5526; test "$$?" = "42"
	./$(COMPILER) test/cfnptr_four_args_b56.c /tmp/cfnptr_four_args_b5626
	/tmp/cfnptr_four_args_b5626; test "$$?" = "42"
	./$(COMPILER) test/cunion_field_offsets_b57.c /tmp/cunion_field_offsets_b5726
	/tmp/cunion_field_offsets_b5726; test "$$?" = "42"
	./$(COMPILER) test/cfield_ptr_null_store_b58.c /tmp/cfield_ptr_null_store_b5826
	/tmp/cfield_ptr_null_store_b5826; test "$$?" = "42"
	./$(COMPILER) test/cfixed_seven_args_b59.c /tmp/cfixed_seven_args_b5926
	/tmp/cfixed_seven_args_b5926; test "$$?" = "42"
	./$(COMPILER) test/cfn_ret_ptrptr_b60.c /tmp/cfn_ret_ptrptr_b6026
	/tmp/cfn_ret_ptrptr_b6026; test "$$?" = "42"
	./$(COMPILER) test/cptr_array_decay_stride_b61.c /tmp/cptr_array_decay_stride_b6126
	/tmp/cptr_array_decay_stride_b6126; test "$$?" = "42"
	./$(COMPILER) test/cfield_2d_row_decay_b62.c /tmp/cfield_2d_row_decay_b6226
	/tmp/cfield_2d_row_decay_b6226; test "$$?" = "42"
	./$(COMPILER) test/ctypedef_shadow_local_b151.c /tmp/ctypedef_shadow_local_b15126
	/tmp/ctypedef_shadow_local_b15126; test "$$?" = "42"
	./$(COMPILER) test/cinit_struct_designator_b152.c /tmp/cinit_struct_designator_b15226
	/tmp/cinit_struct_designator_b15226; test "$$?" = "42"
	./$(COMPILER) test/cinit_array_designator_b153.c /tmp/cinit_array_designator_b15326
	/tmp/cinit_array_designator_b15326; test "$$?" = "42"
	./$(COMPILER) test/csizeof_no_parens_b154.c /tmp/csizeof_no_parens_b15426
	/tmp/csizeof_no_parens_b15426; test "$$?" = "42"
	./$(COMPILER) test/cblock_scope_func_decl_b155.c /tmp/cblock_scope_func_decl_b15526
	/tmp/cblock_scope_func_decl_b15526; test "$$?" = "42"
	./$(COMPILER) test/cpragma_push_pop_macro_b156.c /tmp/cpragma_push_pop_macro_b15626
	/tmp/cpragma_push_pop_macro_b15626; test "$$?" = "42"
	./$(COMPILER) test/cvariadic_macro_b157.c /tmp/cvariadic_macro_b15726
	/tmp/cvariadic_macro_b15726; test "$$?" = "42"
	./$(COMPILER) test/cenum_typed_decl_b158.c /tmp/cenum_typed_decl_b15826
	/tmp/cenum_typed_decl_b15826; test "$$?" = "42"
	./$(COMPILER) test/cstatic_init_cast_intdouble_b159.c /tmp/cstatic_init_cast_intdouble_b15926
	/tmp/cstatic_init_cast_intdouble_b15926; test "$$?" = "42"
	./$(COMPILER) test/csizeof_expr_result_b160.c /tmp/csizeof_expr_result_b16026
	/tmp/csizeof_expr_result_b16026; test "$$?" = "42"
	./$(COMPILER) test/cglobal_fnptr_addressof_b161.c /tmp/cglobal_fnptr_addressof_b16126
	/tmp/cglobal_fnptr_addressof_b16126; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/ccrtl_hand_declared_proto_b162.c /tmp/ccrtl_hand_declared_proto_b16226
	/tmp/ccrtl_hand_declared_proto_b16226; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cstr_literal_binop_b163.c /tmp/cstr_literal_binop_b16326
	/tmp/cstr_literal_binop_b16326; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cconst_logical_ternary_b164.c /tmp/cconst_logical_ternary_b16426
	/tmp/cconst_logical_ternary_b16426; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/canon_struct_union_members_b165.c /tmp/canon_struct_union_members_b16526
	/tmp/canon_struct_union_members_b16526; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cfnptr_typedef_global_b166.c /tmp/cfnptr_typedef_global_b16626
	/tmp/cfnptr_typedef_global_b16626; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cfnptr_call_result_b167.c /tmp/cfnptr_call_result_b16726
	/tmp/cfnptr_call_result_b16726; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cstruct_fnptr_field_addressof_b168.c /tmp/cstruct_fnptr_field_addressof_b16826
	/tmp/cstruct_fnptr_field_addressof_b16826; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cfnptr_string_arg_b169.c /tmp/cfnptr_string_arg_b16926
	/tmp/cfnptr_string_arg_b16926; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cfnptr_variadic_call_b170.c /tmp/cfnptr_variadic_call_b17026
	/tmp/cfnptr_variadic_call_b17026; test "$$?" = "42"
	./$(COMPILER) test/cparen_fnname_call_b171.c /tmp/cparen_fnname_call_b17126
	/tmp/cparen_fnname_call_b17126; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src -Itest/creinc_b172 test/creinc_proto_reinclude_b172.c /tmp/creinc_proto_reinclude_b17226
	/tmp/creinc_proto_reinclude_b17226; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/creturn_strlit_b173.c /tmp/creturn_strlit_b17326
	/tmp/creturn_strlit_b17326; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cstrlit_index_b174.c /tmp/cstrlit_index_b17426
	/tmp/cstrlit_index_b17426; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cptrdiff_addr_elem_b175.c /tmp/cptrdiff_addr_elem_b17526
	/tmp/cptrdiff_addr_elem_b17526; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cfloat_conv_b176.c /tmp/cfloat_conv_b17626
	/tmp/cfloat_conv_b17626; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/csizeof_deref_field_b177.c /tmp/csizeof_deref_field_b17726
	/tmp/csizeof_deref_field_b17726; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cbuiltin_va_copy_b178.c /tmp/cbuiltin_va_copy_b17826
	/tmp/cbuiltin_va_copy_b17826; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/csizeof_unparen_field_b179.c /tmp/csizeof_unparen_field_b17926
	/tmp/csizeof_unparen_field_b17926; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cglobal_multi_declarator_b180.c /tmp/cglobal_multi_declarator_b18026
	/tmp/cglobal_multi_declarator_b18026; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cstrtok_b181.c /tmp/cstrtok_b18126
	/tmp/cstrtok_b18126; test "$$?" = "42"
	./$(COMPILER) test/cpaste_rescan_call_b182.c /tmp/cpaste_rescan_call_b18226
	/tmp/cpaste_rescan_call_b18226; test "$$?" = "42"
	./$(COMPILER) test/cpaste_empty_arg_b183.c /tmp/cpaste_empty_arg_b18326
	/tmp/cpaste_empty_arg_b18326; test "$$?" = "42"
	./$(COMPILER) test/ctcc_parse_batch_b184.c /tmp/ctcc_parse_batch_b18426
	/tmp/ctcc_parse_batch_b18426; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/ctcc_batch2_b185.c /tmp/ctcc_batch2_b18526
	/tmp/ctcc_batch2_b18526 > /dev/null; test "$$?" = "42"
	# QuickJS bring-up prerequisites (feature-c-corpus-quickjs): gcc bit-scan
	# builtins (cfront rename -> crtl helpers), C99 math additions, and
	# pthread_once + condvars (palsync bridge; --threadsafe pulls palpthread).
	./$(COMPILER) --threadsafe -Ilib/crtl/include -Ilib/crtl/src test/cquickjs_prereq.c /tmp/cquickjs_prereq26
	/tmp/cquickjs_prereq26; test "$$?" = "42"
	./$(COMPILER) test/cblock_scope_b186.c /tmp/cblock_scope_b18626
	/tmp/cblock_scope_b18626; test "$$?" = "42"
	./$(COMPILER) test/cptr_deref_stride_b187.c /tmp/cptr_deref_stride_b18726
	/tmp/cptr_deref_stride_b18726; test "$$?" = "42"
	./$(COMPILER) test/csizeof_string_noparen_b188.c /tmp/csizeof_string_noparen_b18826
	/tmp/csizeof_string_noparen_b18826; test "$$?" = "42"
	# b189-b192 (feature-c-corpus-tcc self-compile arc): {0} zero-fill,
	# &floatField as pointer arg, `int nb, *lv;` declarator, narrow-cast extend
	./$(COMPILER) test/czeroinit_partial_b189.c /tmp/czeroinit_partial_b18926
	/tmp/czeroinit_partial_b18926; test "$$?" = "42"
	./$(COMPILER) test/caddr_float_field_b190.c /tmp/caddr_float_field_b19026
	/tmp/caddr_float_field_b19026; test "$$?" = "42"
	./$(COMPILER) test/ccomma_star_declarator_b191.c /tmp/ccomma_star_declarator_b19126
	/tmp/ccomma_star_declarator_b19126; test "$$?" = "42"
	./$(COMPILER) test/cnarrow_cast_extend_b192.c /tmp/cnarrow_cast_extend_b19226
	/tmp/cnarrow_cast_extend_b19226; test "$$?" = "42"
	# b193-b194 (bug-c-init-brace-elision-nested): recursive global aggregate
	# init walker (elision/nested/anon-union/designators), sizeof(arr->field)
	./$(COMPILER) test/cinit_elision_nested_b193.c /tmp/cinit_elision_nested_b19326
	/tmp/cinit_elision_nested_b19326; test "$$?" = "42"
	./$(COMPILER) test/csizeof_arrow_array_field_b194.c /tmp/csizeof_arrow_array_field_b19426
	/tmp/csizeof_arrow_array_field_b19426; test "$$?" = "42"
	# b195 (bug-c-printf-without-stdio-include-varargs): implicit printf binds crtl
	./$(COMPILER) test/cimplicit_printf_varargs_b195.c /tmp/cimplicit_printf_varargs_b19526
	test "$$(/tmp/cimplicit_printf_varargs_b19526; test $$? = 42 && echo RC42)" = "$$(printf 'x=42 y=ok\nRC42')"
	# b196 (bug-crtl-strtod-precision-cjson-floats): exact strtod + %g round-trip
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/ccrtl_strtod_g_roundtrip_b196.c /tmp/ccrtl_strtod_g_roundtrip_b19626
	/tmp/ccrtl_strtod_g_roundtrip_b19626; test "$$?" = "42"
	# crtl arpa/inet.h IPv4 conversion (feature-game-library-candidate-suite / ENet surface)
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/gamelib/crtl_inet_smoke.c /tmp/crtl_inet_smoke26
	/tmp/crtl_inet_smoke26; test "$$?" = "42"
	# b197 (bug-c-float-single-return-zero): cdecl float(single) return ABI
	./$(COMPILER) test/cfloat_single_return_b197.c /tmp/cfloat_single_return_b19726
	/tmp/cfloat_single_return_b19726; test "$$?" = "42"
	# crtl single-precision <math.h> f-family (feature-game-library-candidate-suite / cglm surface)
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/gamelib/crtl_mathf_smoke.c /tmp/crtl_mathf_smoke26
	/tmp/crtl_mathf_smoke26; test "$$?" = "42"
	# b198 (bug-c-inline-fnptr-param-call): function-TYPE typedef call idiom
	./$(COMPILER) test/cfntype_typedef_call_b198.c /tmp/cfntype_typedef_call_b19826
	/tmp/cfntype_typedef_call_b19826; test "$$?" = "42"
	# b199 (bug-c-local-nested-aggregate-init): local recursive brace-elision walker
	./$(COMPILER) test/clocal_nested_aggregate_init_b199.c /tmp/clocal_nested_aggregate_init_b19926
	/tmp/clocal_nested_aggregate_init_b19926; test "$$?" = "42"
	# b200 (bug-c-expr-result-type-model / 00104): hex/octal constant unsigned type ladder
	./$(COMPILER) test/chex_constant_unsigned_type_b200.c /tmp/chex_constant_unsigned_type_b20026
	/tmp/chex_constant_unsigned_type_b20026; test "$$?" = "42"
	# b201 (bug-crtl-printf-g-double-roundtrip): va_arg(T*) pointee width (scanf float)
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cva_arg_pointer_pointee_b201.c /tmp/cva_arg_pointer_pointee_b20126
	/tmp/cva_arg_pointer_pointee_b20126; test "$$?" = "42"
	# b202 (bug-c-tag-redef-misfiles-field-selfref-segv): struct-tag redefinition no crash
	./$(COMPILER) test/ctag_redef_no_selfref_crash_b202.c /tmp/ctag_redef_no_selfref_crash_b20226
	/tmp/ctag_redef_no_selfref_crash_b20226; test "$$?" = "42"
	# crtl networking header surface (bug-c-crtl-missing-net-headers-enet / ENet)
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/gamelib/crtl_net_headers_smoke.c /tmp/crtl_net_headers_smoke26
	/tmp/crtl_net_headers_smoke26; test "$$?" = "42"
	# external crtl int returned negative, used inline in a signed compare
	# (bug-c-crtl-pulled-fn-inline-signed-compare): sign-extend the 32-bit result
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/ccrtl_external_int_signed_compare.c /tmp/ccrtl_external_int_signed_compare26
	/tmp/ccrtl_external_int_signed_compare26; test "$$?" = "42"
	# array typedef `typedef float vec4[4]` folds its dim into a decl
	# (bug-c-typedef-array-element-init): vec4 v -> float[4], vec4 arr[N] -> [N][4]
	./$(COMPILER) test/carray_typedef_element_init.c /tmp/carray_typedef_element_init26
	/tmp/carray_typedef_element_init26; test "$$?" = "42"
	# wide string literals L"..." decode UTF-8 -> wchar_t codepoints
	# (feature-c-wide-string-literals, c-testsuite 00220)
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cwide_string_literal.c /tmp/cwide_string_literal26
	/tmp/cwide_string_literal26; test "$$?" = "42"
	# b203 (bug-c-multidim-ordinal-global-init): multidim ordinal global array init
	./$(COMPILER) test/cmultidim_ordinal_global_b203.c /tmp/cmultidim_ordinal_global_b20326
	/tmp/cmultidim_ordinal_global_b20326; test "$$?" = "42"
	# b205 (bug-c-multidim-float-brace-init): multidim FLOAT/DOUBLE global brace init
	./$(COMPILER) test/cmultidim_float_global_b205.c /tmp/cmultidim_float_global_b20526
	/tmp/cmultidim_float_global_b20526; test "$$?" = "42"
	# b206 (bug-c-pointer-to-array-declarator): `char (*p)[4]` pointer-to-array + p[i][j]
	./$(COMPILER) test/cptr_to_array_declarator_b206.c /tmp/cptr_to_array_declarator_b20626
	/tmp/cptr_to_array_declarator_b20626; test "$$?" = "42"
	# b207 (bug-c-switch-nonblock-and-duffs-device): non-compound switch body + Duff's device
	./$(COMPILER) test/cswitch_noncompound_duff_b207.c /tmp/cswitch_noncompound_duff_b20726
	/tmp/cswitch_noncompound_duff_b20726; test "$$?" = "42"
	# stb_sprintf callback engine (feature-game-library-candidate-suite): integer
	# subset. Skips when the gitignored stb tree is absent (install_lib_candidates.sh stb).
	@if [ -f library_candidates/stb/stb_sprintf.h ]; then 	  ./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src -Ilibrary_candidates/stb test/gamelib/stb_sprintf_probe.c /tmp/stb_sprintf_probe26 >/dev/null && 	  /tmp/stb_sprintf_probe26; test "$$?" = "42" && echo "stb_sprintf_probe: OK"; 	else echo "stb_sprintf_probe: SKIP (no library_candidates/stb)"; fi
	./$(COMPILER) test/ctypedef_ptr_stride_b63.c /tmp/ctypedef_ptr_stride_b6326
	/tmp/ctypedef_ptr_stride_b6326; test "$$?" = "42"
	./$(COMPILER) test/cternary_ptr_null_b64.c /tmp/cternary_ptr_null_b6426
	/tmp/cternary_ptr_null_b6426; test "$$?" = "42"
	./$(COMPILER) test/cchar_ptr_arith_deref_b65.c /tmp/cchar_ptr_arith_deref_b6526
	/tmp/cchar_ptr_arith_deref_b6526; test "$$?" = "42"
	./$(COMPILER) test/cstruct_field_constexpr_array_b66.c /tmp/cstruct_field_constexpr_array_b6626
	/tmp/cstruct_field_constexpr_array_b6626; test "$$?" = "42"
	./$(COMPILER) test/cunion_ptr_field_expr_b67.c /tmp/cunion_ptr_field_expr_b6726
	/tmp/cunion_ptr_field_expr_b6726; test "$$?" = "42"
	./$(COMPILER) test/cglobal_uchar_array_init_b68.c /tmp/cglobal_uchar_array_init_b6826
	/tmp/cglobal_uchar_array_init_b6826; test "$$?" = "42"
	./$(COMPILER) test/cglobal_nested_struct_init_b69.c /tmp/cglobal_nested_struct_init_b6926
	/tmp/cglobal_nested_struct_init_b6926; test "$$?" = "42"
	./$(COMPILER) test/cuchar_struct_field_load_b70.c /tmp/cuchar_struct_field_load_b7026
	/tmp/cuchar_struct_field_load_b7026; test "$$?" = "42"
	./$(COMPILER) test/cternary_int_promotion_b71.c /tmp/cternary_int_promotion_b7126
	/tmp/cternary_int_promotion_b7126; test "$$?" = "42"
	./$(COMPILER) test/cglobal_reg_array_init_b72.c /tmp/cglobal_reg_array_init_b7226
	/tmp/cglobal_reg_array_init_b7226; test "$$?" = "42"
	./$(COMPILER) test/cglobal_strptr_array_decay_b73.c /tmp/cglobal_strptr_array_decay_b7326
	/tmp/cglobal_strptr_array_decay_b7326; test "$$?" = "42"
	./$(COMPILER) test/cvoid_cast_call_stmt_b74.c /tmp/cvoid_cast_call_stmt_b7426
	/tmp/cvoid_cast_call_stmt_b7426; test "$$?" = "42"
	./$(COMPILER) test/cglobal_scalar_strptr_b75.c /tmp/cglobal_scalar_strptr_b7526
	/tmp/cglobal_scalar_strptr_b7526; test "$$?" = "42"
	./$(COMPILER) test/cderef_arrow_field_b76.c /tmp/cderef_arrow_field_b7626
	/tmp/cderef_arrow_field_b7626; test "$$?" = "42"
	./$(COMPILER) test/cglobal_constexpr_array_init_b77.c /tmp/cglobal_constexpr_array_init_b7726
	/tmp/cglobal_constexpr_array_init_b7726; test "$$?" = "42"
	./$(COMPILER) test/cchar_escapes_b78.c /tmp/cchar_escapes_b7826
	/tmp/cchar_escapes_b7826; test "$$?" = "42"
	./$(COMPILER) test/csizeof_deref_ptr_b79.c /tmp/csizeof_deref_ptr_b7926
	/tmp/csizeof_deref_ptr_b7926; test "$$?" = "42"
	./$(COMPILER) test/cunsigned_arith_compare_b80.c /tmp/cunsigned_arith_compare_b8026
	/tmp/cunsigned_arith_compare_b8026; test "$$?" = "42"
	./$(COMPILER) test/cptrcast_deref_double_b81.c /tmp/cptrcast_deref_double_b8126
	/tmp/cptrcast_deref_double_b8126; test "$$?" = "42"
	./$(COMPILER) test/caggregate_double_return_b82.c /tmp/caggregate_double_return_b8226
	/tmp/caggregate_double_return_b8226; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cvararg_double_b83.c /tmp/cvararg_double_b8326
	/tmp/cvararg_double_b8326; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cderef_addr_local_store_b84.c /tmp/cderef_addr_local_store_b8426
	/tmp/cderef_addr_local_store_b8426; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cfloat_pascal_bridge_b85.c /tmp/cfloat_pascal_bridge_b8526
	/tmp/cfloat_pascal_bridge_b8526; test "$$?" = "42"
	./$(COMPILER) test/csizeof_string_literal_b86.c /tmp/csizeof_string_literal_b8626
	/tmp/csizeof_string_literal_b8626; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cfile_stdio_b87.c /tmp/cfile_stdio_b8726
	/tmp/cfile_stdio_b8726; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/csocket_loopback_b88.c /tmp/csocket_loopback_b8826
	/tmp/csocket_loopback_b8826; test "$$?" = "42"
	./$(COMPILER) test/ctypedef_alias_fnptr_field_b89.c /tmp/ctypedef_alias_fnptr_field_b8926
	/tmp/ctypedef_alias_fnptr_field_b8926; test "$$?" = "42"
	./$(COMPILER) test/cmain_argv_b90.c /tmp/cmain_argv_b9026
	/tmp/cmain_argv_b9026 ab xyz; test "$$?" = "42"
	./$(COMPILER) test/cglobal_float_init_b91.c /tmp/cglobal_float_init_b9126
	/tmp/cglobal_float_init_b9126; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include test/ctypedef_sys_ssize_b92.c /tmp/ctypedef_sys_ssize_b9226
	/tmp/ctypedef_sys_ssize_b9226; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cvararg_overflow_b93.c /tmp/cvararg_overflow_b9326
	out="$$(/tmp/cvararg_overflow_b9326)"; status="$$?"; test "$$out" = "$$(printf '1 2 3 4 5 6\n7 8')"; test "$$status" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cvararg_many_args_b135.c /tmp/cvararg_many_args_b13526
	out="$$(/tmp/cvararg_many_args_b13526)"; status="$$?"; test "$$out" = "$$(printf '300 78 110\n1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18')"; test "$$status" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cvariadic_struct_b208.c /tmp/cvariadic_struct_b20826
	/tmp/cvariadic_struct_b20826; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cgeneric_selection_b209.c /tmp/cgeneric_selection_b20926
	/tmp/cgeneric_selection_b20926; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/crange_designator_b210.c /tmp/crange_designator_b21026
	/tmp/crange_designator_b21026; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/carray_designated_init_b211.c /tmp/carray_designated_init_b21126
	/tmp/carray_designated_init_b21126; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cglobal_array_range_b212.c /tmp/cglobal_array_range_b21226
	/tmp/cglobal_array_range_b21226; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cnested_designator_b213.c /tmp/cnested_designator_b21326
	/tmp/cnested_designator_b21326; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cfnptr_typedef_array_b214.c /tmp/cfnptr_typedef_array_b21426
	/tmp/cfnptr_typedef_array_b21426; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cfnptr_range_table_b215.c /tmp/cfnptr_range_table_b21526
	/tmp/cfnptr_range_table_b21526; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/ccompound_literal_b216.c /tmp/ccompound_literal_b21626
	/tmp/ccompound_literal_b21626; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/ccompound_literal_postfix_b217.c /tmp/ccompound_literal_postfix_b21726
	/tmp/ccompound_literal_postfix_b21726; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/ccompound_literal_nested_b218.c /tmp/ccompound_literal_nested_b21826
	/tmp/ccompound_literal_nested_b21826; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/ccompound_literal_global_array_b219.c /tmp/ccompound_literal_global_array_b21926
	/tmp/ccompound_literal_global_array_b21926; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cformfeed_whitespace_b220.c /tmp/cformfeed_whitespace_b22026
	/tmp/cformfeed_whitespace_b22026; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/canon_member_designated_init_b221.c /tmp/canon_member_designated_init_b22126
	/tmp/canon_member_designated_init_b22126; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cstruct_identity_cast_b222.c /tmp/cstruct_identity_cast_b22226
	/tmp/cstruct_identity_cast_b22226; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cfnptr_range_array_len_b223.c /tmp/cfnptr_range_array_len_b22326
	/tmp/cfnptr_range_array_len_b22326; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cflex_array_member_sizeof_b224.c /tmp/cflex_array_member_sizeof_b22426
	/tmp/cflex_array_member_sizeof_b22426; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cglobal_compound_literal_init_b225.c /tmp/cglobal_compound_literal_init_b22526
	/tmp/cglobal_compound_literal_init_b22526; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/carray_compound_literal_b226.c /tmp/carray_compound_literal_b22626
	/tmp/carray_compound_literal_b22626; test "$$?" = "42"
	./$(COMPILER) test/cpreproc_macro_arg_string_paren_b227.c /tmp/cpreproc_macro_arg_string_paren_b22726
	/tmp/cpreproc_macro_arg_string_paren_b22726; test "$$?" = "42"
	./$(COMPILER) test/cpreproc_stdc_version_predefine_b228.c /tmp/cpreproc_stdc_version_predefine_b22826
	/tmp/cpreproc_stdc_version_predefine_b22826; test "$$?" = "42"
	./$(COMPILER) test/cpreproc_hex_octal_if_b237.c /tmp/cpreproc_hex_octal_if_b23726
	/tmp/cpreproc_hex_octal_if_b23726; test "$$?" = "42"
	./$(COMPILER) test/cpreproc_macro_comment_continuation_b229.c /tmp/cpreproc_macro_comment_continuation_b22926
	/tmp/cpreproc_macro_comment_continuation_b22926; test "$$?" = "42"
	./$(COMPILER) test/cfield_ptrcast_index_b230.c /tmp/cfield_ptrcast_index_b23026
	/tmp/cfield_ptrcast_index_b23026; test "$$?" = "42"
	./$(COMPILER) test/cstruct_field_case_sensitive_b231.c /tmp/cstruct_field_case_sensitive_b23126
	/tmp/cstruct_field_case_sensitive_b23126; test "$$?" = "42"
	./$(COMPILER) test/cfloat_nan_compare_b232.c /tmp/cfloat_nan_compare_b23226
	/tmp/cfloat_nan_compare_b23226; test "$$?" = "42"
	./$(COMPILER) test/cmath_domain_nan_b233.c /tmp/cmath_domain_nan_b23326
	/tmp/cmath_domain_nan_b23326; test "$$?" = "42"
	# _Generic must tell long from int (ILP32) and long long from long (LP64) —
	# same width, different C type (bug-c-generic-long-vs-int-ilp32). Also run as
	# a 32-bit binary, which is where long collapsed onto int.
	./$(COMPILER) test/cgeneric_long_rank_b250.c /tmp/cgeneric_long_rank_b25026
	/tmp/cgeneric_long_rank_b25026; test "$$?" = "42"
	./$(COMPILER) --target=i386 test/cgeneric_long_rank_b250.c /tmp/cgeneric_long_rank_b250_386
	/tmp/cgeneric_long_rank_b250_386; test "$$?" = "42"
	# a 64-bit value is a register PAIR on ILP32: `if (v)` must test BOTH halves
	# (bug-32bit-truthiness-high-half). The 32-bit run is the one that matters.
	./$(COMPILER) test/ctruthy_int64_b251.c /tmp/ctruthy_int64_b25126
	/tmp/ctruthy_int64_b25126; test "$$?" = "42"
	./$(COMPILER) --target=i386 test/ctruthy_int64_b251.c /tmp/ctruthy_int64_b251_386
	/tmp/ctruthy_int64_b251_386; test "$$?" = "42"
	# crtl printf must honour `ll`, not just count it (bug-crtl-printf-ll-ilp32)
	./$(COMPILER) test/cprintf_ll_b252.c /tmp/cprintf_ll_b25226
	/tmp/cprintf_ll_b25226; test "$$?" = "42"
	./$(COMPILER) --target=i386 test/cprintf_ll_b252.c /tmp/cprintf_ll_b252_386
	/tmp/cprintf_ll_b252_386; test "$$?" = "42"
	# unary minus applies the integer promotions: -(unsigned short) is a SIGNED int
	# (bug-c-unary-minus-no-integer-promotion)
	./$(COMPILER) test/cunary_minus_promote_b253.c /tmp/cunary_minus_promote_b25326
	/tmp/cunary_minus_promote_b25326; test "$$?" = "42"
	# sizeof(us + 0) is 4, not 2 — the symbol fast path must not swallow a whole
	# expression (bug-c-binary-op-no-integer-promotion-sizeof)
	./$(COMPILER) test/csizeof_promoted_expr_b255.c /tmp/csizeof_promoted_expr_b25526
	/tmp/csizeof_promoted_expr_b25526; test "$$?" = "42"
	./$(COMPILER) --target=i386 test/csizeof_promoted_expr_b255.c /tmp/csizeof_promoted_expr_b255_386
	/tmp/csizeof_promoted_expr_b255_386; test "$$?" = "42"
	./$(COMPILER) test/carrow_on_array_call_rhs_b136.c /tmp/carrow_on_array_call_rhs_b13626
	/tmp/carrow_on_array_call_rhs_b13626; test "$$?" = "42"
	./$(COMPILER) test/csigned_arith_shift_right_b137.c /tmp/csigned_arith_shift_right_b13726
	/tmp/csigned_arith_shift_right_b13726; test "$$?" = "42"
	./$(COMPILER) test/cunsigned_semantics_sweep_b138.c /tmp/cunsigned_semantics_sweep_b13826
	/tmp/cunsigned_semantics_sweep_b13826; test "$$?" = "42"
	./$(COMPILER) test/cstatic_local_init_once_b139.c /tmp/cstatic_local_init_once_b13926
	/tmp/cstatic_local_init_once_b13926; test "$$?" = "42"
	./$(COMPILER) test/cmath_round_trunc_b140.c /tmp/cmath_round_trunc_b14026
	/tmp/cmath_round_trunc_b14026; test "$$?" = "42"
	./$(COMPILER) test/cternary_struct_value_b141.c /tmp/cternary_struct_value_b14126
	/tmp/cternary_struct_value_b14126; test "$$?" = "42"
	./$(COMPILER) test/cfloat_literal_precise_b142.c /tmp/cfloat_literal_precise_b14226
	/tmp/cfloat_literal_precise_b14226; test "$$?" = "42"
	# bug-c-comment-terminator-greedy: stray tokens after a comment that ends at
	# its first `*/` must be rejected at top level (gcc parity), not silently skipped.
	! ./$(COMPILER) test/cstray_toplevel_reject_b193.c /tmp/cstray_toplevel_reject_b19326 > /tmp/cstray_toplevel_reject_b193.log 2>&1
	grep -q "stray token at top level" /tmp/cstray_toplevel_reject_b193.log
	# bug-c-anon-struct-nested-enum-global: inline `enum {...}` in type position
	# (struct member / typedef / global) is consumed and its enumerators registered.
	./$(COMPILER) test/cenum_in_struct_b194.c /tmp/cenum_in_struct_b19426
	/tmp/cenum_in_struct_b19426; test "$$?" = "42"
	# bug-c-sqlite-suite-runtime-segfault: address of a single/double lvalue is an
	# IR_LEA (pointer value); C float->int truncation must not corrupt it.
	./$(COMPILER) test/cfloat_lea_ptr_b195.c /tmp/cfloat_lea_ptr_b19526
	/tmp/cfloat_lea_ptr_b19526; test "$$?" = "142"
	# bug-c-double-ptr-deref-narrow-to-single: (float)*doubleptr / (double)*floatptr
	# must convert, not reinterpret the load width.
	./$(COMPILER) test/cfloat_cast_deref_b196.c /tmp/cfloat_cast_deref_b19626
	/tmp/cfloat_cast_deref_b19626; test "$$?" = "42"
	# bug-c-stb-sprintf-float-empty: file-scope float/double array initializers
	# must emit their element values (were skipped -> read as zero).
	./$(COMPILER) test/cfloat_global_array_init_b197.c /tmp/cfloat_global_array_init_b19726
	/tmp/cfloat_global_array_init_b19726; test "$$?" = "42"
	# bug-c-shift-result-type-battery-00200: shift result type = promoted LEFT
	# operand (C99 6.5.7p3); a wide/unsigned count must not change the signedness.
	./$(COMPILER) test/cshift_result_type_b198.c /tmp/cshift_result_type_b19826
	/tmp/cshift_result_type_b19826; test "$$?" = "42"
	# bug-c-sizeof-widening-cast-expr: sizeof of a general expr must use the
	# operand's own type size (long->8, char->1), not a flat 4.
	./$(COMPILER) test/csizeof_cast_expr_b199.c /tmp/csizeof_cast_expr_b19926
	/tmp/csizeof_cast_expr_b19926; test "$$?" = "42"
	./$(COMPILER) test/cnested_pointer_b94.c /tmp/cnested_pointer_b9426
	/tmp/cnested_pointer_b9426 ab xyz; test "$$?" = "42"
	./$(COMPILER) test/cfnptr_struct_member.c /tmp/cfnptr_struct_member26
	/tmp/cfnptr_struct_member26; test "$$?" = "42"
	./$(COMPILER) test/cfnptr_local_b95.c /tmp/cfnptr_local_b9526
	/tmp/cfnptr_local_b9526; test "$$?" = "42"
	./$(COMPILER) test/cstruct_bitfield_b96.c /tmp/cstruct_bitfield_b9626
	/tmp/cstruct_bitfield_b9626; test "$$?" = "42"
	./$(COMPILER) test/cfnptr_cast_call_b97.c /tmp/cfnptr_cast_call_b9726
	/tmp/cfnptr_cast_call_b9726; test "$$?" = "42"
	./$(COMPILER) test/cglobal_struct_array_fnptr_cast_b98.c /tmp/cglobal_struct_array_fnptr_cast_b9826
	/tmp/cglobal_struct_array_fnptr_cast_b9826; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include test/crtl_unistd_fsync_b99.c /tmp/crtl_unistd_fsync_b9926
	/tmp/crtl_unistd_fsync_b9926; test "$$?" = "42"
	./$(COMPILER) test/cpreproc_defined_directive_join_b100.c /tmp/cpreproc_defined_directive_join_b10026
	/tmp/cpreproc_defined_directive_join_b10026; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include test/crtl_unistd_getpid_b101.c /tmp/crtl_unistd_getpid_b10126
	/tmp/crtl_unistd_getpid_b10126; test "$$?" = "42"
	./$(COMPILER) test/cternary_middle_comma_b102.c /tmp/cternary_middle_comma_b10226
	/tmp/cternary_middle_comma_b10226; test "$$?" = "42"
	./$(COMPILER) test/cternary_pointer_array_index_b103.c /tmp/cternary_pointer_array_index_b10326
	/tmp/cternary_pointer_array_index_b10326; test "$$?" = "42"
	./$(COMPILER) test/coffsetof_constexpr_array_b104.c /tmp/coffsetof_constexpr_array_b10426
	/tmp/coffsetof_constexpr_array_b10426; test "$$?" = "42"
	./$(COMPILER) test/cfn_return_fnptr_b105.c /tmp/cfn_return_fnptr_b10526
	/tmp/cfn_return_fnptr_b10526; test "$$?" = "42"
	./$(COMPILER) test/cexternal_func_addr_b106.c /tmp/cexternal_func_addr_b10626
	/tmp/cexternal_func_addr_b10626; test "$$?" = "42"
	./$(COMPILER) test/clocal_static_const_2d_init_b107.c /tmp/clocal_static_const_2d_init_b10726
	/tmp/clocal_static_const_2d_init_b10726; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include test/cva_arg_local_fnptr_typedef_b108.c /tmp/cva_arg_local_fnptr_typedef_b10826
	/tmp/cva_arg_local_fnptr_typedef_b10826; test "$$?" = "42"
	./$(COMPILER) test/cglobal_fnptr_array_b109.c /tmp/cglobal_fnptr_array_b10926
	/tmp/cglobal_fnptr_array_b10926; test "$$?" = "42"
	./$(COMPILER) test/cpreproc_if_arith_b110.c /tmp/cpreproc_if_arith_b11026
	/tmp/cpreproc_if_arith_b11026; test "$$?" = "42"
	./$(COMPILER) test/cauto_pull_crtl_math_b111.c /tmp/cauto_pull_crtl_math_b11126
	/tmp/cauto_pull_crtl_math_b11126; test "$$?" = "42"
	./$(COMPILER) --system-libs=m test/csystem_libs_granular_math_b112.c /tmp/csystem_libs_granular_math_b11226
	/tmp/csystem_libs_granular_math_b11226; test "$$?" = "39"
	@if command -v readelf >/dev/null 2>&1; then \
	  readelf -d /tmp/csystem_libs_granular_math_b11226 | grep -q "Shared library: \\[libm.so.6\\]"; \
	  ! readelf -d /tmp/csystem_libs_granular_math_b11226 | grep -q "Shared library: \\[libc.so.6\\]"; \
	fi
	./$(COMPILER) --system-libs=c test/csystem_libs_granular_libc_b113.c /tmp/csystem_libs_granular_libc_b11326
	@if command -v readelf >/dev/null 2>&1; then \
	  readelf -d /tmp/csystem_libs_granular_libc_b11326 | grep -q "Shared library: \\[libc.so.6\\]"; \
	  ! readelf -d /tmp/csystem_libs_granular_libc_b11326 | grep -q "Shared library: \\[libm.so.6\\]"; \
	fi
	./$(COMPILER) test/clocal_record_fnptr_init_b114.c /tmp/clocal_record_fnptr_init_b11426
	/tmp/clocal_record_fnptr_init_b11426; test "$$?" = "42"
	./$(COMPILER) test/clocal_static_record_array_b115.c /tmp/clocal_static_record_array_b11526
	/tmp/clocal_static_record_array_b11526; test "$$?" = "42"
	./$(COMPILER) test/cptr_return_text_b116.c /tmp/cptr_return_text_b11626
	/tmp/cptr_return_text_b11626; test "$$?" = "42"
	./$(COMPILER) test/cternary_string_ptr_b118.c /tmp/cternary_string_ptr_b11826
	/tmp/cternary_string_ptr_b11826; test "$$?" = "42"
	./$(COMPILER) test/csizeof_array_field_b119.c /tmp/csizeof_array_field_b11926
	/tmp/csizeof_array_field_b11926; test "$$?" = "42"
	./$(COMPILER) test/carray_field_decay_nested_item_b120.c /tmp/carray_field_decay_nested_item_b12026
	/tmp/carray_field_decay_nested_item_b12026; test "$$?" = "42"
	./$(COMPILER) test/csizeof_ptr_field_index_b122.c /tmp/csizeof_ptr_field_index_b12226
	/tmp/csizeof_ptr_field_index_b12226; test "$$?" = "42"
	./$(COMPILER) test/cswitch_nested_case_block_b127.c /tmp/cswitch_nested_case_block_b12726
	/tmp/cswitch_nested_case_block_b12726; test "$$?" = "42"
	./$(COMPILER) test/cunsigned_int_arith_b121.c /tmp/cunsigned_int_arith_b12126
	/tmp/cunsigned_int_arith_b12126; test "$$?" = "42"
	./$(COMPILER) test/cunsigned_div_mod_b123.c /tmp/cunsigned_div_mod_b12326
	/tmp/cunsigned_div_mod_b12326; test "$$?" = "42"
	./$(COMPILER) test/cvararg_named_fp.c /tmp/cvararg_named_fp26
	/tmp/cvararg_named_fp26; test "$$?" = "42"
	# stack-spilled named params (7th+ GP / 9th+ FP) + overflow_arg_area anchor + capped va seeds (gcc-verified oracle)
	./$(COMPILER) test/cvararg_stack_spill.c /tmp/cvararg_stack_spill26
	test "$$(/tmp/cvararg_stack_spill26)" = "$$(printf '7060\n950.25\n7807800.75')"
	./$(COMPILER) -Ilib/crtl/include -Ilibrary_candidates/tiny-regex-c test/crtl_tiny_regex_match.c /tmp/crtl_tiny_regex_match26
	test "$$(/tmp/crtl_tiny_regex_match26)" = "tiny-regex: all cases pass"
	./$(COMPILER) -Itest/cinc/inc test/cinc/cinc_main.c /tmp/cinc_main26
	test "$$(/tmp/cinc_main26)" = "$$(printf 'local-ok\ninc-ok')"
	./$(COMPILER) test/test_declared_directive.pas /tmp/test_declared_directive26
	test "$$(/tmp/test_declared_directive26)" = "$$(printf '1\n2\n3\n4\n5')"
	./$(COMPILER) test/dotted/test_dotted_uses.pas /tmp/test_dotted_uses26
	test "$$(/tmp/test_dotted_uses26)" = "$$(printf '2\n42\n7')"
	./$(COMPILER) test/test_string_copy_intrinsic.pas /tmp/test_string_copy_intrinsic26
	test "$$(/tmp/test_string_copy_intrinsic26)" = "$$(printf 'Hello\nWorld\nWorld!\nWorld!\nHel\n0\nHello')"
	./$(COMPILER) test/test_forward_use.pas /tmp/test_forward_use26
	test "$$(/tmp/test_forward_use26)" = "$$(printf 'square(7) = 49\nGreeting  = hello\nsum 1..4  = 10\npoint     = 3,4')"
	./$(COMPILER) test/test_unit_impl_fwd.pas /tmp/test_unit_impl_fwd26
	test "$$(/tmp/test_unit_impl_fwd26)" = "110"
	./$(COMPILER) test/test_const_before_ctor.pas /tmp/test_const_before_ctor26
	test "$$(/tmp/test_const_before_ctor26)" = "$$(printf '12\n112')"
	./$(COMPILER) test/test_platform_defines.pas /tmp/test_platform_defines_posix26
	test "$$(/tmp/test_platform_defines_posix26)" = "$$(printf 'platform=posix\nfiles\nsockets\nthreads\ndynlib\nend')"
	./$(COMPILER) --platform=esp test/test_platform_defines.pas /tmp/test_platform_defines_esp26
	test "$$(/tmp/test_platform_defines_esp26)" = "$$(printf 'platform=esp\nend')"
	./$(COMPILER) -Itest/unitpath/posix test/test_unitpath.pas /tmp/test_unitpath_posix26
	test "$$(/tmp/test_unitpath_posix26)" = "posix"
	./$(COMPILER) -Futest/unitpath/esp test/test_unitpath.pas /tmp/test_unitpath_esp26
	test "$$(/tmp/test_unitpath_esp26)" = "esp"
	./$(COMPILER) test/test_asm.pas /tmp/test_asm26
	/tmp/test_asm26; test "$$?" = "42"
	./$(COMPILER) test/test_asm_func.pas /tmp/test_asm_func26
	test "$$(/tmp/test_asm_func26)" = "14"
	./$(COMPILER) test/test_asm_swap.pas /tmp/test_asm_swap26
	test "$$(/tmp/test_asm_swap26)" = "$$(printf '42\n-7\n-7\n42')"
	./$(COMPILER) test/test_asm_branch.pas /tmp/test_asm_branch26
	/tmp/test_asm_branch26; test "$$?" = "45"
	./$(COMPILER) test/test_asm_keywords.pas /tmp/test_asm_keywords26
	test "$$(/tmp/test_asm_keywords26)" = "4"
	./$(COMPILER) test/test_asm_global.pas /tmp/test_asm_global26
	test "$$(/tmp/test_asm_global26)" = "$$(printf '11 12 23\nTRUE')"
	./$(COMPILER) test/test_asm_memr.pas /tmp/test_asm_memr26
	test "$$(/tmp/test_asm_memr26)" = "$$(printf '0\n20\n30\n40\n999\n1\n110\n1')"
	./$(COMPILER) test/test_asm_sizekw.pas /tmp/test_asm_sizekw26
	test "$$(/tmp/test_asm_sizekw26)" = "$$(printf '6\n7\n232 3 0 0\n300')"
	# one source, per-target asm blocks behind {$$ifdef CPU...} guards (x64 leg; rv32/a64 legs in the cross suites)
	./$(COMPILER) test/test_asm_ifdef_multiarch.pas /tmp/test_asm_ifdef_ma26
	test "$$(/tmp/test_asm_ifdef_ma26)" = "42"
	! ./$(COMPILER) test/test_asm_att_reject.pas /tmp/test_asm_att_reject26 > /tmp/test_asm_att_reject.log 2>&1
	grep -q "asmMode att.*not supported" /tmp/test_asm_att_reject.log
	./$(COMPILER) test/test_coswitch.pas /tmp/test_coswitch26
	test "$$(/tmp/test_coswitch26)" = "$$(printf 'main: 1\ngen: 1\nmain: 2\ngen: 2\nmain: 3\ngen: 3\nmain: 4\ngen: 4\nmain: 5\ngen: 5\ndone')"
	./$(COMPILER) test/test_not.pas /tmp/test_not26
	test "$$(/tmp/test_not26)" = "$$(printf -- '-1\n-16\n-256\n4\nok')"
	./$(COMPILER) test/test_generator.pas /tmp/test_generator26
	test "$$(/tmp/test_generator26)" = "$$(printf '1 4 9 16 25 \n25\n0 1 1 2 3 5 8 13 \n1 2 3 ')"
	./$(COMPILER) test/test_generator_record.pas /tmp/test_generator_record26
	test "$$(/tmp/test_generator_record26)" = "$$(printf '1 10 1\n2 20 4\n3 30 9\n30')"
	./$(COMPILER) test/test_generator_yield_call.pas /tmp/test_generator_yield_call26
	test "$$(/tmp/test_generator_yield_call26)" = "$$(printf '1 2 10\n3 4 20\n5 6 30\n60')"
	./$(COMPILER) test/test_forin_set_member.pas /tmp/test_forin_set_member26
	test "$$(/tmp/test_forin_set_member26)" = "$$(printf 'spell=0\nspell=2\nspell=4\ndone')"
	./$(COMPILER) -Fulib/rtl/platform/posix test/test_textfile.pas /tmp/test_textfile26
	test "$$(/tmp/test_textfile26)" = "$$(printf 'line0: room=hall\nline1: count=42\nio=0')"
	./$(COMPILER) -Futest -Fulib/rtl/platform/posix test/test_textfile_in_unit.pas /tmp/test_textfile_in_unit26
	test "$$(/tmp/test_textfile_in_unit26)" = "hello from unit"
	./$(COMPILER) test/test_forin_native.pas /tmp/test_forin_native26
	test "$$(/tmp/test_forin_native26)" = "$$(printf 'static sum=150\ndyn sum=600\nchar=a\nchar=b\nchar=c\nday=0\nday=1\nday=2\nday=3\nday=4\nwd=0\nwd=2\nwd=4\ncs=a\ncs=m\ncs=x')"
	./$(COMPILER) test/test_forin_enumerator.pas /tmp/test_forin_enumerator26
	test "$$(/tmp/test_forin_enumerator26)" = "$$(printf 'x=11\nx=22\nx=33\nsum=66')"
	./$(COMPILER) test/test_forin_aggr_elems.pas /tmp/test_forin_aggr_elems26
	test "$$(/tmp/test_forin_aggr_elems26)" = "$$(printf 'rec=33\ncls=30\nstr=aabbcc')"
	./$(COMPILER) test/test_enum_cast.pas /tmp/test_enum_cast26
	test "$$(/tmp/test_enum_cast26)" = "$$(printf '1\n5\n3\n0\n3')"
	./$(COMPILER) test/test_cast_char_bool.pas /tmp/test_cast_char_bool26
	test "$$(/tmp/test_cast_char_bool26)" = "$$(printf 'A\ncharcmp\n67\nbtrue\nbfalse\nHIJ')"
	./$(COMPILER) test/test_cast_string.pas /tmp/test_cast_string26
	test "$$(/tmp/test_cast_string26)" = "$$(printf '[Q]\nA\neq\nhello\nhello\nXYZ')"
	./$(COMPILER) test/test_class_is_as.pas /tmp/test_class_is_as26
	test "$$(/tmp/test_class_is_as26)" = "$$(printf 'is TDog\nis TAnimal\nnot TCat\nnot TPuppy\nnil not\nv=42\ncast read=42\npuppy is TDog\npuppy is TAnimal\npuppy not TCat')"
	./$(COMPILER) test/test_class_cast_field.pas /tmp/test_class_cast_field26
	test "$$(/tmp/test_class_cast_field26)" = "$$(printf '166408768\n7\n42\n99\n555\n555\n2')"
	./$(COMPILER) test/test_inline_concat_arg.pas /tmp/test_inline_concat_arg26
	test "$$(/tmp/test_inline_concat_arg26)" = "$$(printf '[aabb] len=4\n[Line 1\nLine 2] len=13\n[xyz] len=3')"
	./$(COMPILER) test/test_array_of_string.pas /tmp/test_array_of_string26
	test "$$(/tmp/test_array_of_string26)" = "$$(printf 'Apple\nBanana\nCherry\nx|yy|2\nscalar')"
	./$(COMPILER) test/test_string_sized.pas /tmp/test_string_sized26
	test "$$(/tmp/test_string_sized26)" = "$$(printf 'Apple\nBanana\nCherry-and-then-some\n5\n6\n20\na-ok\nb-ok\nApple')"
	./$(COMPILER) test/test_shortstring.pas /tmp/test_shortstring26
	test "$$(/tmp/test_shortstring26)" = "$$(printf 'hello world\n11\nApple\nBanana\nCherry\narr0-ok\narr1-ok')"
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_str_val_managed.pas /tmp/test_str_val_managed26
	test "$$(/tmp/test_str_val_managed26)" = "$$(printf '[42]\n42 code=0\n3.5 code=0\n0 code=2')"
	./$(COMPILER) test/test_managed_string_flip.pas /tmp/test_managed_string_flip26
	test "$$(/tmp/test_managed_string_flip26)" = "$$(printf 'hello world long enough\nhello world long enough!\nhello world long enough!\nhello world long enough!\nhello world long enough!')"
	./$(COMPILER) test/test_interfaces.pas /tmp/test_interfaces26
	test "$$(/tmp/test_interfaces26)" = "$$(printf 'area=20\nscaled=60\narea2=42\ndirect=42')"
	./$(COMPILER) test/test_interfaces_is.pas /tmp/test_interfaces_is26
	test "$$(/tmp/test_interfaces_is26)" = "$$(printf 'a IFoo\na noBar\nc IFoo\nz no\nnil no\ncall=7\nsup IFoo\nz sup no')"
	./$(COMPILER) test/test_interfaces_as.pas /tmp/test_interfaces_as26
	test "$$(/tmp/test_interfaces_as26)" = "$$(printf 'a.F=7\nc.F=7\ndirect=7\ndone')"
	./$(COMPILER) test/test_interfaces_param.pas /tmp/test_interfaces_param26
	test "$$(/tmp/test_interfaces_param26)" = "$$(printf 'viaparam=7\nresult=7\nfg same\nfh diff\nfh ne\nf set\nnow nil')"
	./$(COMPILER) test/test_interfaces_inherit.pas /tmp/test_interfaces_inherit26
	test "$$(/tmp/test_interfaces_inherit26)" = "$$(printf 'bar.B=9\nbar.F=7\nfoo.F=7\nwiden=7\nwf=7\na is IFoo\na is IBar\nsup IFoo')"
	./$(COMPILER) test/test_interfaces_multi_secondary.pas /tmp/test_interfaces_multi_secondary26
	test "$$(/tmp/test_interfaces_multi_secondary26)" = "$$(printf 'direct\nTitle\nSome content\nSome content\nTitle\nSome content')"
	./$(COMPILER) test/test_interface_arc.pas /tmp/test_interface_arc26
	test "$$(/tmp/test_interface_arc26)" = "$$(printf 'hello\nhello\nhello\nfreed=3')"
	./$(COMPILER) test/test_interface_arc_exc.pas /tmp/test_interface_arc_exc26
	test "$$(/tmp/test_interface_arc_exc26)" = "$$(printf 'reassign created=2 freed=2\ncaught\nunwind freed=3')"
	./$(COMPILER) test/test_uint64_ops.pas /tmp/test_uint64_ops26
	test "$$(/tmp/test_uint64_ops26)" = "$$(printf '9600629759793949339\n0\n8846114313915602276\n4344256703880665856\n8\n1099511627776\nTRUE\nFALSE\n6')"
	./$(COMPILER) test/test_case_io.pas /tmp/test_case_io26
	test "$$(/tmp/test_case_io26)" = "$$(printf 'one\nab\ntwo\nthree\n42')"
	./$(COMPILER) test/test_case_io_casesensitive_intrinsics.pas /tmp/test_case_io_casesensitive_intrinsics26
	test "$$(printf '10 32\n' | /tmp/test_case_io_casesensitive_intrinsics26)" = "$$(printf 'AB\n42')"
	./$(COMPILER) test/test_uses_sysutils.pas /tmp/test_uses_sysutils26
	test "$$(/tmp/test_uses_sysutils26)" = "sysutils noop ok"
	./$(COMPILER) test/test_sysutils_datetime.pas /tmp/test_sysutils_datetime26
	test "$$(/tmp/test_sysutils_datetime26)" = "$$(printf '2026-7-2\n2000-2-29\n1900-2-28\n1899-12-30 0.0\n1899-12-29 -1.0\n1969-12-31\n1800-1-1\n2026-7-2 14:30:15.500\n1899-12-30 18:0:0.0')"
	./$(COMPILER) -Futest/case_units test/test_case_unit_lookup.pas /tmp/test_case_unit_lookup26
	/tmp/test_case_unit_lookup26; test "$$?" = "42"
	./$(COMPILER) test/test_float_str_val.pas /tmp/test_float_str_val26
	test "$$(/tmp/test_float_str_val26)" = "$$(printf '[3.14]\n[    3.1416]\n[-2.750]\n[1000.5]\n42.7500 code=0\n-1.5000 code=0\n100.00 code=0\n350.00 code=0\n0.1250 code=0\ncode=1\n[   42]\n-99 code=0')"
	./$(COMPILER) test/test_float_result_loop.pas /tmp/test_float_result_loop26
	test "$$(/tmp/test_float_result_loop26)" = "$$(printf '8.0000\n6.0000\n2.0000')"
	./$(COMPILER) test/test_single_first_class.pas /tmp/test_single_first_class26
	test "$$(/tmp/test_single_first_class26)" = "$$(printf '4.5000\n9.0000\n3.7500\n4.0000\n7.0000\n13.0000\n0.7500')"
	./$(COMPILER) test/test_int_to_float.pas /tmp/test_int_to_float26
	test "$$(/tmp/test_int_to_float26)" = "$$(printf '1.0000\n7.0000\n7.0000\n3.0000\n5.0000\n0.0000\n1.0000\n2.0000\n5.0000')"
	./$(COMPILER) test/test_math.pas /tmp/test_math26
	test "$$(/tmp/test_math26)" = "$$(printf '3.14159265\n1.41421356\n4.00000000\n1.50000000\n2.71828183\n1.00000000\n12.18249396\n0.69314718\n2.30258509\n1.00000000\n0.00000000\n0.84147098\n0.00000000\n1.00000000\n0.54030231\n0.78539816\n0.46364761\n1024.00000000\n1.41421356\n3.50000000\n1.00000000')"
	./$(COMPILER) examples/sudoku/sudoku.pas /tmp/test_sudoku26
	test "$$(/tmp/test_sudoku26)" = "$$(printf '534678912672195348198342567859761423426853791713924856961537284287419635345286179\n987654321246173985351928746128537694634892157795461832519286473472319568863745219\n812753649943682175675491283154237896369845721287169534521974368438526917796318452')"
	./$(COMPILER) test/test_stackless_gen.pas /tmp/test_stackless_gen26
	test "$$(/tmp/test_stackless_gen26)" = "$$(printf '1 4 9 16 25 \n25\n5 4 3 2 1 \n0 2 4 6 8 \n10 20 30 \n1 2 3 \n99 100 10 101 20 21 102 30 103 30 104 30 105 99 106 \n1 20 300 4 50 600 \n0:10:300 0:10:301 2:30:302 2:30:303 53:40:7 ')"
	./$(COMPILER) test/test_scheduler.pas /tmp/test_scheduler26
	test "$$(/tmp/test_scheduler26)" = "$$(printf 'c2:1\nc3:1\nonce 7\nc2:2\nc3:2\nc3:3\nall done')"
	./$(COMPILER) test/test_scheduler_exc.pas /tmp/test_scheduler_exc26
	test "$$(/tmp/test_scheduler_exc26)" = "$$(printf 'w1 try\nw2 try\nw1 caught\nw2 caught\ndone')"
	./$(COMPILER) test/test_costack.pas /tmp/test_costack26
	test "$$(/tmp/test_costack26)" = "$$(printf 'w1:55\nw2:210\nw3:465\nw1:55\nw2:210\nw3:465\nall done')"
	./$(COMPILER) test/test_async.pas /tmp/test_async26
	test "$$(/tmp/test_async26)" = "$$(printf 'a1:1\na2:1\na1:2\na2:2\ndone1=102\ndone2=202\nall done')"
	./$(COMPILER) test/test_async_sl.pas /tmp/test_async_sl26
	test "$$(/tmp/test_async_sl26)" = "$$(printf 'A0\nB0\nA1\nB1\nA2\ndone')"
	./$(COMPILER) test/test_reactor.pas /tmp/test_reactor26
	test "$$(/tmp/test_reactor26)" = "$$(printf 'reader: start\nreader: would-block, parking\nwriter: writing\nreader: got 2 bytes: hi\ndone')"
	./$(COMPILER) -Fulib/rtl/platform/posix test/test_asyncecho.pas /tmp/test_asyncecho26
	test "$$(/tmp/test_asyncecho26)" = "$$(printf 'client 1 ok\nclient 2 ok\ndone')"
	./$(COMPILER) test/test_timer.pas /tmp/test_timer26
	test "$$(/tmp/test_timer26)" = "$$(printf 'woke 50\nwoke 100\nwoke 150\ndone')"
	./$(COMPILER) test/test_channel.pas /tmp/test_channel26
	test "$$(/tmp/test_channel26)" = "$$(printf 'recv 1\nrecv 2\nrecv 3\nrecv 4\nrecv 5\nrecv 6\ndone')"
	./$(COMPILER) test/test_many_params.pas /tmp/test_many_params26
	test "$$(/tmp/test_many_params26)" = "$$(printf '1 2 3 4 5 6 7\n3 4 5 6 7 12 89\n8912\n7654326\n12100806\n7654321\n96\n196')"
	./$(COMPILER) test/test_procaddr.pas /tmp/test_procaddr26
	test "$$(/tmp/test_procaddr26)" = "1 2 3 4 5 "
	./$(COMPILER) test/test_proctype.pas /tmp/test_proctype26
	test "$$(/tmp/test_proctype26)" = "$$(printf 'hello 1\nadd 7\nmul 30\nexpr ok\nhello 7\ngreet 99')"
	./$(COMPILER) test/test_proc_const_record.pas /tmp/test_proc_const_record26
	test "$$(/tmp/test_proc_const_record26)" = "$$(printf '42\n42')"
	./$(COMPILER) test/test_indexed_proc_call.pas /tmp/test_indexed_proc_call26
	test "$$(/tmp/test_indexed_proc_call26)" = "$$(printf '42\n42\n20\n11\n42')"
	./$(COMPILER) test/test_methodptr.pas /tmp/test_methodptr26
	test "$$(/tmp/test_methodptr26)" = "$$(printf 'code set\ndata ok')"
	./$(COMPILER) test/test_methcall.pas /tmp/test_methcall26
	test "$$(/tmp/test_methcall26)" = "$$(printf 'show 42 base=100\nadd 105\nexpr ok\nping base=100')"
	./$(COMPILER) test/test_const_record_param.pas /tmp/test_const_record_param26
	test "$$(/tmp/test_const_record_param26)" = "111 222"
	./$(COMPILER) test/test_array_of_const.pas /tmp/test_array_of_const26
	test "$$(/tmp/test_array_of_const26)" = "$$(printf 'int 10\nint 20\nint 30\ncount 3\nstr hi\nint 7\nstr world\ncount 3')"
	./$(COMPILER) test/test_varrec_branch.pas /tmp/test_varrec_branch26
	test "$$(/tmp/test_varrec_branch26)" = "$$(printf 'none\na1\na2\na3\nb1\nb2\nc1\nd1\nd2\nd3\nd4\ne1\ne2\nnone')"
	./$(COMPILER) test/test_varrec_string.pas /tmp/test_varrec_string26
	test "$$(/tmp/test_varrec_string26)" = "$$(printf 'S=lit\nI=42\nS=hello\nS=world\nS=param\nS=tail')"
	./$(COMPILER) test/test_varrec_alloc_after.pas /tmp/test_varrec_alloc_after26
	test "$$(/tmp/test_varrec_alloc_after26)" = "$$(printf 'n=2: S 42\nn=4: 10 20 30 40\nn=3: 115 11 22')"
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_array_of_const_types.pas /tmp/test_aoc_types26
	test "$$(/tmp/test_aoc_types26)" = "$$(printf 'vt0: 42\nvt1: TRUE\nvt2: Q\nvt16: 5000000000\nvt3: 3.50\nvt11: hi')"
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_write_pchar.pas /tmp/test_write_pchar26
	test "$$(/tmp/test_write_pchar26)" = "$$(printf 'hello\nhello\nhello world')"
	./$(COMPILER) test/test_cross_static_open_array.pas /tmp/test_static_open26
	test "$$(/tmp/test_static_open26)" = "$$(printf 'len=4 high=3 sum=100 a0=10\nlen=2 high=1 sum=15 a0=7')"
	./$(COMPILER) test/test_conformance_1.pas /tmp/test_conformance_1_26
	test "$$(/tmp/test_conformance_1_26)" = "$$(printf 'shape 0 square area=9.00 tag=5000000004\nshape 1 circle area=12.00 tag=1000000000\nshape 2 generic area=0.00 tag=1000000007\ntotal area=21.00\npts len=3 high=2\n  pt p 0,0\n  pt p 2,1\n  pt p 4,4\n  i 42\n  q 9000000000\n  b TRUE\n  s mixed\nv int=1\ncaught: boom\ncaught=1\nconcat=abcdef len=6\nV...V.')"
	./$(COMPILER) test/test_conformance_2.pas /tmp/test_conformance_2_26
	test "$$(/tmp/test_conformance_2_26)" = "$$(printf 'q=7000000005 mix=111000000083\nfact20=2432902008176640000\neven10=TRUE odd7=TRUE\nsum9=45 big=97864\n  rec r A=1000000000 B=0 sum=1000000000\n  rec r A=2000000000 B=1 sum=2000000001\n  rec r A=3000000000 B=4 sum=3000000004\ncopy A=3000000000 B=99 orig B=4\nopensum=100\n  i 42\n  q 9000000000\n  b TRUE\n  s mixed\nconcat=abcdef len=6\nV.--V.\ncaught=11 gdiv=5 gzero=-1')"
	./$(COMPILER) test/test_cross_shortcircuit.pas /tmp/test_shortcircuit26
	test "$$(/tmp/test_shortcircuit26)" = "$$(printf 'and-false calls=0\nor-true\nor-true calls=0\nand-true\nand-true calls=1\nor-false\nor-false calls=2\nguard1 ok\nchain calls=2\nbits 2 7 8')"
	./$(COMPILER) test/test_many_local_names.pas /tmp/test_many_local_names26
	test "$$(/tmp/test_many_local_names26)" = "s=104"
	./$(COMPILER) test/test_cross_ptr_arith.pas /tmp/test_ptr_arith26
	test "$$(/tmp/test_ptr_arith26)" = "$$(printf 'deref=44\nparen=44\nplus1=55\nminus1=33\nplus0=44\nminus2=22\nvarneg=11\nfn+2=66\nfn-4=0\nsweep=308')"
	./$(COMPILER) test/test_cross_case_range.pas /tmp/test_case_range26
	test "$$(/tmp/test_case_range26)" = "$$(printf 'ints=8436\nchars=206\nbucket=LLLMMMMHHH')"
	./$(COMPILER) test/test_case_of_string.pas /tmp/test_case_of_string26
	test "$$(/tmp/test_case_of_string26)" = "$$(printf '1\n2\n3\n0\n0\n4\n0\n2\n1\n2')"
	./$(COMPILER) test/test_case_otherwise.pas /tmp/test_case_otherwise26
	test "$$(/tmp/test_case_otherwise26)" = "$$(printf 'one\nother 7\nstill-other')"
	./$(COMPILER) test/test_str_variable_width.pas /tmp/test_str_varwidth26
	test "$$(/tmp/test_str_varwidth26)" = "$$(printf '[    42]\nint-eq\n[      42]\n[    3.142]\nfloat-eq\n       42\n    3.142\n       42\n    3.142')"
	! ./$(COMPILER) --strict-case test/test_case_label_dup_error.pas /tmp/test_case_label_dup26 > /tmp/test_case_label_dup.log 2>&1
	./$(COMPILER) test/test_case_label_dup_error.pas /tmp/test_case_label_dup_lax26 > /dev/null 2>&1   # lax default: first-match, must COMPILE
	grep -q "duplicate or overlapping case label" /tmp/test_case_label_dup.log
	! ./$(COMPILER) --strict-case test/test_case_range_inverted_error.pas /tmp/test_case_range_inv26 > /tmp/test_case_range_inv.log 2>&1
	./$(COMPILER) test/test_case_range_inverted_error.pas /tmp/test_case_range_inv_lax26 > /dev/null 2>&1   # lax default: never-matching range, must COMPILE
	grep -q "case range: lower bound is greater than upper bound" /tmp/test_case_range_inv.log
	./$(COMPILER) test/test_cross_global_init.pas /tmp/test_global_init26
	test "$$(/tmp/test_global_init26)" = "$$(printf 'k=42 q=5000000000 flag=TRUE\ntabsum=150\nlutsum=6000000000')"
	./$(COMPILER) test/test_cross_typed_const.pas /tmp/test_typed_const26
	test "$$(/tmp/test_typed_const26)" = "$$(printf 'limit=100 big=9000000000\ntabsum=14\nlutsum=6000000000\ntab2=40')"
	./$(COMPILER) test/test_local_typed_const.pas /tmp/test_local_tc26
	test "$$(/tmp/test_local_tc26)" = "$$(printf '100\na\nb\nc\n42\n100')"
	./$(COMPILER) test/test_typed_const_record.pas /tmp/test_tc_record26
	test "$$(/tmp/test_tc_record26)" = "$$(printf '7\n10 Z 20\n300\n300')"
	./$(COMPILER) test/test_multidim_const_array.pas /tmp/test_md_const26
	test "$$(/tmp/test_md_const26)" = "$$(printf '1 2 3 4\n10 30 40 60\n1 4 5 8\n7 8 9 10\n7 8 9 10')"
	./$(COMPILER) test/test_const_set.pas /tmp/test_const_set26
	test "$$(/tmp/test_const_set26)" = "$$(printf 'digits=5\ngreen=out\nblue=in\nrange=4\nunion=ok\ninter=ok')"
	./$(COMPILER) test/test_func_name_result_read.pas /tmp/test_fnresult26
	test "$$(/tmp/test_fnresult26)" = "$$(printf '33\n0\nhi!\n120')"
	./$(COMPILER) test/test_func_name_paramless_result.pas /tmp/test_fnresult_pl26
	test "$$(/tmp/test_fnresult_pl26)" = "$$(printf '0 1\n8\n55')"
	./$(COMPILER) test/test_local_shadows_func.pas /tmp/test_local_shadows26
	test "$$(/tmp/test_local_shadows26)" = "$$(printf 'count=7 viaFunc=7\ntally=20')"
	./$(COMPILER) test/test_mode_delphi.pas /tmp/test_mode_delphi26
	test "$$(/tmp/test_mode_delphi26)" = "$$(printf 'p5=10\nGate=42 calls=3\nTally=105')"
	./$(COMPILER) test/test_mode_delphi_callarg.pas /tmp/test_mode_delphi_callarg26
	test "$$(/tmp/test_mode_delphi_callarg26)" = "$$(printf 'ApplyFn=42\nlog=20\nCallNul=14')"
	./$(COMPILER) test/test_mode_delphi_methptr.pas /tmp/test_mode_delphi_methptr26
	test "$$(/tmp/test_mode_delphi_methptr26)" = "$$(printf 'total=12\nkicked=1')"
	./$(COMPILER) test/test_mimic_fpc.pas /tmp/test_mimic_fpc_off26
	test "$$(/tmp/test_mimic_fpc_off26)" = "fpc=no"
	./$(COMPILER) --mimic-fpc test/test_mimic_fpc.pas /tmp/test_mimic_fpc_on26
	test "$$(/tmp/test_mimic_fpc_on26)" = "$$(printf 'fpc=yes\nver>=20400\nmajor>=3\nversion=3.2.2\nunix')"
	./$(COMPILER) test/test_mimic_directive.pas /tmp/test_mimic_directive26
	test "$$(/tmp/test_mimic_directive26)" = "$$(printf 'fpc 3.x\nversion=3.2.2')"
	./$(COMPILER) test/test_keyword_array_case.pas /tmp/test_keyword_array_case26
	test "$$(/tmp/test_keyword_array_case26)" = "$$(printf '36\n5')"
	./$(COMPILER) test/test_succ_pred_odd.pas /tmp/test_succ_pred_odd26
	test "$$(/tmp/test_succ_pred_odd26)" = "$$(printf '6 4\nb\ny\nodd7\neven8\n1')"
	./$(COMPILER) test/test_shr_width.pas /tmp/test_shr_width26
	test "$$(/tmp/test_shr_width26)" = "$$(printf '2147483644\n2147483644\n9223372036854775804\n1099511627776\n256\n-2147483648\n-16\n2147483648\n1099511627776\n4503599627370496')"
	./$(COMPILER) test/test_stderr_fd.pas /tmp/test_stderr_fd26
	test "$$(/tmp/test_stderr_fd26 2>/dev/null)" = "$$(printf 'out1\nout2')"
	test "$$(/tmp/test_stderr_fd26 2>&1 1>/dev/null)" = "$$(printf 'e1 n=42 i=  7 b=TRUE')"
	./$(COMPILER) test/test_concat_arg_bss.pas /tmp/test_concat_arg_bss26 > /tmp/test_concat_arg_bss.log
	test "$$(/tmp/test_concat_arg_bss26)" = "24"
	@if grep -qE 'bss=[0-9]{7,}B' /tmp/test_concat_arg_bss.log; then echo "concat-arg BSS bloat regressed:"; grep -oE 'bss=[0-9]+B' /tmp/test_concat_arg_bss.log; exit 1; else echo "concat-arg-bss: OK ($$(grep -oE 'bss=[0-9]+B' /tmp/test_concat_arg_bss.log))"; fi
	./$(COMPILER) test/test_const_open_array_managed.pas /tmp/test_const_open_array_managed26
	test "$$(/tmp/test_const_open_array_managed26)" = "$$(printf 'high=2 sel=1\n aa\n>bb\n cc\naabbcc')"
	./$(COMPILER) test/test_open_array_ctor_stmt.pas /tmp/test_open_array_ctor_stmt26
	test "$$(/tmp/test_open_array_ctor_stmt26)" = "$$(printf '3\n1 2 3 \n\nhi 5')"
	./$(COMPILER) test/test_open_array_no_leak.pas /tmp/test_open_array_no_leak26
	test "$$(/tmp/test_open_array_no_leak26)" = "ok 1000000"
	@if [ -x /usr/bin/time ]; then \
	  /usr/bin/time -v /tmp/test_open_array_no_leak26 2>/tmp/oanl.time >/dev/null; \
	  rss=$$(grep -oE 'Maximum resident set size .kbytes.: [0-9]+' /tmp/oanl.time | grep -oE '[0-9]+$$'); \
	  if [ -n "$$rss" ] && [ "$$rss" -gt 10000 ]; then echo "open-array temp leak regressed: RSS $${rss}KB (>10MB over 2M calls)"; exit 1; else echo "open-array-no-leak: OK (RSS $${rss}KB)"; fi; \
	else echo "/usr/bin/time absent; open-array RSS leak guard skipped"; fi
	./$(COMPILER) test/test_big_static_array_open_param.pas /tmp/test_big_static_array_open_param26
	test "$$(/tmp/test_big_static_array_open_param26)" = "$$(printf 'small const sum: 6\nsmall var: 0 1 2\nbig const sum (zeros): 0\nbig var writeback correct: TRUE\nbig const sum (filled): 267386880\nleak-loop total: 13369344000')"
	./$(COMPILER) --debug test/test_big_static_array_open_param.pas /tmp/test_big_static_array_open_param_dbg26 > /tmp/big_static_open_array.log 2>&1
	@if grep -qi "stack frame" /tmp/big_static_open_array.log; then echo "bug-const-open-array-param-stack-copies-caller-frame REGRESSED: oversized-stack-frame warning fired"; grep -i "stack frame" /tmp/big_static_open_array.log; exit 1; else echo "big-static-array-open-param: no oversized frame, OK"; fi
	@if [ -x /usr/bin/time ]; then \
	  /usr/bin/time -v /tmp/test_big_static_array_open_param26 2>/tmp/bsoa.time >/dev/null; \
	  rss=$$(grep -oE 'Maximum resident set size .kbytes.: [0-9]+' /tmp/bsoa.time | grep -oE '[0-9]+$$'); \
	  if [ -n "$$rss" ] && [ "$$rss" -gt 50000 ]; then echo "big-array open-array temp leak regressed: RSS $${rss}KB (>50MB over 51 calls of a 2MB array)"; exit 1; else echo "big-static-array-open-param-no-leak: OK (RSS $${rss}KB)"; fi; \
	else echo "/usr/bin/time absent; big-array open-array RSS leak guard skipped"; fi
	./$(COMPILER) test/test_abs_sqr.pas /tmp/test_abs_sqr26
	test "$$(/tmp/test_abs_sqr26)" = "$$(printf '5 7\n49\n3.50\n6.25\n43')"
	./$(COMPILER) test/test_upcase_pos.pas /tmp/test_upcase_pos26
	test "$$(/tmp/test_upcase_pos26)" = "$$(printf 'AZ5\n3\n0\n1\nHI3')"
	./$(COMPILER) test/test_keyword_case.pas /tmp/test_keyword_case26
	test "$$(/tmp/test_keyword_case26)" = "$$(printf '9\n22')"
	./$(COMPILER) test/test_builtin_name_params.pas /tmp/test_builtin_name_params26
	test "$$(/tmp/test_builtin_name_params26)" = "$$(printf '1\n41\n7\nB\n67')"
	./$(COMPILER) test/test_var_open_array.pas /tmp/test_var_open_array26
	test "$$(/tmp/test_var_open_array26)" = "$$(printf '6\n0 10 20 30 ')"
	./$(COMPILER) test/test_var_open_array_field.pas /tmp/test_var_open_array_field26
	test "$$(/tmp/test_var_open_array_field26)" = "$$(printf '256\n1284')"
	./$(COMPILER) test/test_static_array_length.pas /tmp/test_static_array_length26
	test "$$(/tmp/test_static_array_length26)" = "$$(printf '3\n2\n64\n60')"
	./$(COMPILER) test/test_narrowing_typecast_rvalue.pas /tmp/test_narrowing_typecast_rvalue26
	test "$$(/tmp/test_narrowing_typecast_rvalue26)" = "$$(printf '44\ncmp-ok\n44\n44\n4464\n4294967295\n4294967295\n-1\n-56\n5\n5')"
	./$(COMPILER) test/test_var_nd_array_string_init.pas /tmp/test_var_nd_array_string_init26
	test "$$(/tmp/test_var_nd_array_string_init26)" = "$$(printf '1 3 4 6\nJan Mar Apr Jun\nx yy zzz')"
	./$(COMPILER) test/test_sizeof_array_typename.pas /tmp/test_sizeof_array_typename26
	test "$$(/tmp/test_sizeof_array_typename26)" = "$$(printf '40\n12\n16\n60\n36\n12\n4\n40\n60\n8\n8\n4\n8\n12\n4\n10\n1\n12\n5\n4\n12\n4\n120\n60\n4\n36\n12')"
	./$(COMPILER) test/test_byvalue_record_managed_copy.pas /tmp/test_byvalue_record_managed_copy26
	test "$$(/tmp/test_byvalue_record_managed_copy26)" = "$$(printf '1,2\n1,2,3\n1,orig\n5,view\n5,view\n111,viavar\n2,orig2\nshared?')"
	./$(COMPILER) test/test_untyped_params.pas /tmp/test_untyped_params26
	test "$$(/tmp/test_untyped_params26)" = "$$(printf '7 7 7 7 \n7 7 7 7 ')"
	./$(COMPILER) test/test_string_delete_insert.pas /tmp/test_string_delete_insert26
	test "$$(/tmp/test_string_delete_insert26)" = "$$(printf 'ho\nhellxo\nabc\nworld!\nabc')"
	./$(COMPILER) test/test_concat_intrinsic.pas /tmp/test_concat_intrinsic26
	test "$$(/tmp/test_concat_intrinsic26)" = "$$(printf 'abc\nx\nhello world')"
	./$(COMPILER) test/test_str_literal_concat_compare.pas /tmp/test_str_lit_concat_cmp26
	test "$$(/tmp/test_str_lit_concat_cmp26)" = "$$(printf 'eq1\nneq2\neq3\npqr\nhello world')"
	./$(COMPILER) test/test_user_type_shadows_builtin.pas /tmp/test_usershadow26
	test "$$(/tmp/test_usershadow26)" = "$$(printf 'show 7\ndbl=10')"
	./$(COMPILER) test/test_eof_stdin.pas /tmp/test_eof26
	test "$$(printf 'x\ny' | /tmp/test_eof26)" = "$$(printf '1: x\n2: y\ntotal 2')"
	test "$$(printf '' | /tmp/test_eof26)" = "total 0"
	./$(COMPILER) test/test_const_bitwise_shift.pas /tmp/test_const_bitshift26
	test "$$(/tmp/test_const_bitshift26)" = "$$(printf '65536\n128\n2\n8\n15\n511\n65536')"
	./$(COMPILER) test/test_const_precedence.pas /tmp/test_const_precedence26
	test "$$(/tmp/test_const_precedence26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_const_typecast.pas /tmp/test_const_typecast26
	test "$$(/tmp/test_const_typecast26)" = "$$(printf '4503599627370496\n4503599627370495\n300\n1\n65535\n-56\n4294967295\n-1\n1\n65535')"
	./$(COMPILER) test/test_const_array_of_string.pas /tmp/test_const_array_of_string26
	test "$$(/tmp/test_const_array_of_string26)" = "$$(printf 'aa bb cc dd \na b c d \nxx yy zz \nzzz bb')"
	./$(COMPILER) test/test_case_else_multistmt.pas /tmp/test_case_else_multistmt26
	test "$$(/tmp/test_case_else_multistmt26)" = "$$(printf '5 a\n1 b\n4 c')"
	./$(COMPILER) test/test_var_array_of_string.pas /tmp/test_var_array_of_string26
	test "$$(/tmp/test_var_array_of_string26)" = "$$(printf 'hello0 unset1 unset2 hello3\nhello0 open1 open2 hello3\nafter\nhello0 hello3\nloop total=330000 final=padding-value-to-exercise-realloc-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx')"
	./$(COMPILER) test/test_record_typecast.pas /tmp/test_record_typecast26
	test "$$(/tmp/test_record_typecast26)" = "$$(printf '77\n88\n77\n88\n165')"
	./$(COMPILER) test/test_funcname_field.pas /tmp/test_funcname_field26
	test "$$(/tmp/test_funcname_field26)" = "$$(printf 'a=1000000000 b=2000000000 n=7\na=3 b=6 n=9')"
	./$(COMPILER) test/test_cross_multidim.pas /tmp/test_multidim26
	test "$$(/tmp/test_multidim26)" = "$$(printf 'sum=138 m12=12 m12b=12\nm23=99\ngsum=12000000009 g32=3000000002')"
	./$(COMPILER) test/test_cross_named_array.pas /tmp/test_named_array26
	test "$$(/tmp/test_named_array26)" = "$$(printf 'vsum=30\ngsum=138 g23=23\nbsum=6000000000')"
	./$(COMPILER) test/test_cross_record_2darray.pas /tmp/test_record_2darray26
	test "$$(/tmp/test_record_2darray26)" = "$$(printf 'msum=138 m23=23 tag=7\nm11=99\ngsum=6000000006 g22=2000000002')"
	./$(COMPILER) test/test_cross_param_2darray.pas /tmp/test_param_2darray26
	test "$$(/tmp/test_param_2darray26)" = "$$(printf 'vsum=14\ngsum=30\nafter=1338 m23=123')"
	./$(COMPILER) test/test_cross_multidim3d.pas /tmp/test_multidim3d26
	test "$$(/tmp/test_multidim3d26)" = "$$(printf 'var3d=1476000000 c123=123000000\nparam3d=1476 n123=123\nfield3d=28 rc=7 tag=9')"
	./$(COMPILER) test/test_cross_const_alias.pas /tmp/test_const_alias26
	test "$$(/tmp/test_const_alias26)" = "$$(printf 'Hello, World! len=13\nalist=55 len=6\nrlist=46 len=4')"
	./$(COMPILER) test/test_dyn_comma.pas /tmp/test_dyn_comma26
	test "$$(/tmp/test_dyn_comma26)" = "$$(printf 'm=138 m12=12 brk=12\nalias=9 t11=2')"
	./$(COMPILER) test/test_set_subrange.pas /tmp/test_set_subrange26
	test "$$(/tmp/test_set_subrange26)" = "$$(printf 'union: 1 2 3 4 5 6 10 15 20\ninter: 3 4 15\ndiff: 1 2 10\n15in')"
	./$(COMPILER) test/test_cross_float_const.pas /tmp/test_float_const26
	test "$$(/tmp/test_float_const26)" = "$$(printf 'pi=3.14159 scale=2.00\ncoef=8.25\ntab=35.75 c2=0.25')"
	./$(COMPILER) test/test_asm_emit.pas /tmp/test_asm_emit26
	test "$$(/tmp/test_asm_emit26)" = "$$(printf 'S=\nS=ab\nS=abc\nS=a longer string here\nI=0\nI=123\nI=-7\n---\nS=ww\nI=1\nS=yy\nI=2\nS=zzz\nI=3')"
	./$(COMPILER) test/test_virtual_proc.pas /tmp/test_virtual_proc26
	test "$$(/tmp/test_virtual_proc26)" = "$$(printf 'B\nB')"
	./$(COMPILER) test/test_ir_virtual_call.pas /tmp/test_ir_virtual_call26
	test "$$(/tmp/test_ir_virtual_call26)" = "$$(printf '1\n2\n1\n2')"
	./$(COMPILER) test/test_metaclass_construct.pas /tmp/test_metaclass_construct26
	test "$$(/tmp/test_metaclass_construct26)" = "$$(printf '50\n70\n3')"
	./$(COMPILER) test/test_metaclass_getclass.pas /tmp/test_metaclass_getclass26
	test "$$(/tmp/test_metaclass_getclass26)" = "$$(printf '3 base TRUE\n40 der TRUE')"
	./$(COMPILER) test/test_inheritance_dispatch.pas /tmp/test_inheritance_dispatch26
	test "$$(/tmp/test_inheritance_dispatch26)" = "$$(printf '50\n507\n50\n507\n5\n12\n7\n99\n5\n88')"
	./$(COMPILER) test/test_inherited.pas /tmp/test_inherited26
	test "$$(/tmp/test_inherited26)" = "$$(printf '42\nbase\nchild\n85\ntouch\nchild touch')"
	./$(COMPILER) test/test_abstract_out.pas /tmp/test_abstract_out26
	test "$$(/tmp/test_abstract_out26)" = "$$(printf '16\n9\n16\n32\n18\n42\n99\n100\n7')"
	./$(COMPILER) --debug test/hello.pas /tmp/hello_debug26 > /tmp/hello_debug26.log
	grep -q "Loaded file length:" /tmp/hello_debug26.log
	test "$$(/tmp/hello_debug26)" = "Hello, World!"
	./$(COMPILER) --dump-ir test/hello.pas /tmp/hello_ir26 > /tmp/hello_ir26.log
	grep -q "IR count=" /tmp/hello_ir26.log
	grep -q "writeln" /tmp/hello_ir26.log
	test "$$(/tmp/hello_ir26)" = "Hello, World!"
	./$(COMPILER) --dump-ir test/test_ir_if.pas /tmp/test_ir_if26 > /tmp/test_ir_if26.log
	grep -q "label" /tmp/test_ir_if26.log
	grep -q "jump " /tmp/test_ir_if26.log
	grep -q "jump_if_false" /tmp/test_ir_if26.log
	grep -q "binop" /tmp/test_ir_if26.log
	test "$$(/tmp/test_ir_if26)" = "then"
	./$(COMPILER) --dump-ir test/test_ir_while.pas /tmp/test_ir_while26 > /tmp/test_ir_while26.log
	grep -q "label" /tmp/test_ir_while26.log
	grep -q "jump " /tmp/test_ir_while26.log
	grep -q "jump_if_false" /tmp/test_ir_while26.log
	grep -q "binop" /tmp/test_ir_while26.log
	test "$$(/tmp/test_ir_while26)" = "3"
	./$(COMPILER) --dump-ir test/test_ir_repeat.pas /tmp/test_ir_repeat26 > /tmp/test_ir_repeat26.log
	grep -q "label" /tmp/test_ir_repeat26.log
	grep -q "jump_if_false" /tmp/test_ir_repeat26.log
	grep -q "binop" /tmp/test_ir_repeat26.log
	test "$$(/tmp/test_ir_repeat26)" = "3"
	./$(COMPILER) --dump-ir test/test_ir_for.pas /tmp/test_ir_for26 > /tmp/test_ir_for26.log
	grep -q "label" /tmp/test_ir_for26.log
	grep -q "jump " /tmp/test_ir_for26.log
	grep -q "jump_if_false" /tmp/test_ir_for26.log
	grep -q "binop" /tmp/test_ir_for26.log
	grep -q "const_int" /tmp/test_ir_for26.log
	grep -q "store_sym" /tmp/test_ir_for26.log
	grep -q "load_sym" /tmp/test_ir_for26.log
	test "$$(/tmp/test_ir_for26)" = "$$(printf '15\n15')"
	./$(COMPILER) --dump-ir test/test_ir_loop_control.pas /tmp/test_ir_loop_control26 > /tmp/test_ir_loop_control26.log
	grep -q "label" /tmp/test_ir_loop_control26.log
	grep -q "jump " /tmp/test_ir_loop_control26.log
	grep -q "jump_if_false" /tmp/test_ir_loop_control26.log
	grep -q "binop" /tmp/test_ir_loop_control26.log
	test "$$(/tmp/test_ir_loop_control26)" = "$$(printf '10\n12\n15\n12\n6\n12')"
	./$(COMPILER) --dump-ir test/test_ir_case.pas /tmp/test_ir_case26 > /tmp/test_ir_case26.log
	grep -q "label" /tmp/test_ir_case26.log
	grep -q "jump " /tmp/test_ir_case26.log
	grep -q "jump_if_false" /tmp/test_ir_case26.log
	grep -q "binop" /tmp/test_ir_case26.log
	test "$$(/tmp/test_ir_case26)" = "$$(printf '12\n12\n3\n99\n99')"
	./$(COMPILER) test/test_ir_codegen.pas /tmp/test_ir_codegen26
	test "$$(/tmp/test_ir_codegen26)" = "$$(printf '15\nOK')"
	./$(COMPILER) test/test_fixed_array_copy.pas /tmp/test_fixed_array_copy26
	test "$$(/tmp/test_fixed_array_copy26)" = "$$(printf '1 4\n10 20 30\n5000000000 7000000000\nOK')"
	./$(COMPILER) test/test_ir_codegen_fail.pas /tmp/test_ir_codegen_fail26
	test "$$(/tmp/test_ir_codegen_fail26)" = "$$(printf '15\nFAIL')"
	./$(COMPILER) test/test_ir_unary.pas /tmp/test_ir_unary26
	test "$$(/tmp/test_ir_unary26)" = "$$(printf '%s\nOK' '-5')"
	./$(COMPILER) test/test_not_int64_expr.pas /tmp/test_not_int64_expr26
	test "$$(/tmp/test_not_int64_expr26)" = "$$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\nok-lw0\nok-lw1\nok-bool' '-6' '-6' '-5' '-3' '-7' '-11' '-11' '-6' '-1')"
	./$(COMPILER) test/test_virtual_keyword_result.pas /tmp/test_vkr26
	test "$$(/tmp/test_vkr26)" = "$$(printf '5\n6\n10\n10')"
	./$(COMPILER) test/test_ir_deref.pas /tmp/test_ir_deref26
	test "$$(/tmp/test_ir_deref26)" = "$$(printf '10\n20\n100\n200')"
	./$(COMPILER) test/test_ir_call.pas /tmp/test_ir_call26
	test "$$(/tmp/test_ir_call26)" = "$$(printf '30\n30\n42')"
	./$(COMPILER) test/test_ir_binops.pas /tmp/test_ir_binops26
	test "$$(/tmp/test_ir_binops26)" = "$$(printf -- '-3\n-2\n3\n2\n8\n14\n0\n1\n25')"
	./$(COMPILER) test/test_shl.pas /tmp/test_shl26
	test "$$(/tmp/test_shl26)" = "$$(printf '16\n12\n9')"
	./$(COMPILER) test/test_hex_char_code.pas /tmp/test_hex_char_code26
	test "$$(/tmp/test_hex_char_code26)" = "$$(printf '65\n65\n65\n65\n255\nlo\nhi\nex')"
	./$(COMPILER) test/test_op_overload.pas /tmp/test_op_overload_ir26
	test "$$(/tmp/test_op_overload_ir26)" = "$$(printf '1\n0\n1\n0\n1\n0\n10\n6')"
	./$(COMPILER) test/test_op_fpc_named_result.pas /tmp/test_op_fpc_named_result_ir26
	test "$$(/tmp/test_op_fpc_named_result_ir26)" = "$$(printf '5/6\n1/6\n3/2\n1/6\n1/6\n4/12')"
	./$(COMPILER) test/test_op_unit_scope.pas /tmp/test_op_unit_scope_ir26
	test "$$(/tmp/test_op_unit_scope_ir26)" = "$$(printf 'in:5/6\n5/6\n3/2\n1/6')"
	./$(COMPILER) test/test_overloading.pas /tmp/test_overloading_ir26
	test "$$(/tmp/test_overloading_ir26)" = "$$(printf 'Integer: 42\nChar: A\nTwo Integers: 10, 20\nAdd integers: 12\nChar addition: XY')"
	./$(COMPILER) test/test_float_write.pas /tmp/test_float_write_ir26
	test "$$(/tmp/test_float_write_ir26)" = "$$(printf '3.50\n4\n-2.750\n1.0\n0.00\n10.5\n 1.0000000000000000E+000\n-2.0000000000000000E+000\n 0.0000000000000000E+000\n 3.5000000000000000E+000\n 1.2345000000000002E+003')"
	./$(COMPILER) test/test_shared_object.pas /tmp/shared_object26
	test "$$(/tmp/shared_object26)" = "97"
	./$(COMPILER) test/test_c_import.pas /tmp/c_import26
	test "$$(/tmp/c_import26)" = "42"
	./$(COMPILER) test/test_c_widths.pas /tmp/c_widths26
	test "$$(/tmp/c_widths26)" = "5000000000"
	./$(COMPILER) test/test_c_typedef.pas /tmp/c_typedef26
	test "$$(/tmp/c_typedef26)" = "5000000000"
	./$(COMPILER) test/test_c_enum.pas /tmp/c_enum26
	test "$$(/tmp/c_enum26)" = "$$(printf '0 1 2\n0 1 2 4 5\n1000 1001')"
	./$(COMPILER) test/test_c_slicea.pas /tmp/c_slicea26
	test "$$(/tmp/c_slicea26)" = "16 32 6 60 21 275 1"
	./$(COMPILER) test/test_c_float.pas /tmp/c_float26
	test "$$(/tmp/c_float26)" = "$$(printf '1024.0\n16.0\n12.0')"
	cc -shared -fPIC -o /tmp/libspill.so test/spill_lib.c
	./$(COMPILER) test/test_c_argspill.pas /tmp/c_argspill26
	test "$$(LD_LIBRARY_PATH=/tmp /tmp/c_argspill26)" = "$$(printf '28\n55.0\n45')"
	cc -shared -fPIC -o /tmp/liblazycasing.so test/lazycasing_lib.c
	./$(COMPILER) test/test_c_lazycasing.pas /tmp/c_lazycasing26
	test "$$(LD_LIBRARY_PATH=/tmp /tmp/c_lazycasing26)" = "$$(printf '7\n30\n101')"
	rm -f /tmp/sqlite_crud26.db
	./$(COMPILER) test/test_sqlite_crud.pas /tmp/sqlite_crud26
	test "$$(/tmp/sqlite_crud26)" = "$$(printf 'open=0\nprepare=0\n1 alice\n2 bob\nfinalize=0\nclose=0')"
	rm -f /tmp/test_string_to_pchar_auto26.db
	./$(COMPILER) test/test_string_to_pchar_auto.pas /tmp/string_to_pchar_auto26
	test "$$(/tmp/string_to_pchar_auto26)" = "$$(printf 'open=0\nprepare=0\n1 alice\n2 bob\nfinalize=0\nclose=0')"
	./$(COMPILER) test/test_pchar_to_string.pas /tmp/test_pchar_to_string26
	test "$$(/tmp/test_pchar_to_string26)" = "$$(printf '3\n3\nabc\n3')"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cmath_sign_bits.c /tmp/cmath_sign_bits26
	/tmp/cmath_sign_bits26; test "$$?" = "42"
	./$(COMPILER) test/test_ptr_untyped_deref.pas /tmp/test_ptr_untyped_deref26
	test "$$(/tmp/test_ptr_untyped_deref26)" = "$$(printf 'move=TRUE\nfill=TRUE')"
	./$(COMPILER) -Fulib/rtl test/test_on_binderless.pas /tmp/test_on_binderless26
	test "$$(/tmp/test_on_binderless26)" = "hits=11"
	./$(COMPILER) -Fulib/rtl test/test_dynlib.pas /tmp/test_dynlib_stub26
	test "$$(/tmp/test_dynlib_stub26)" = "no loader"
	./$(COMPILER) -dPXX_DYNLIB_LIBC -Fulib/rtl test/test_dynlib.pas /tmp/test_dynlib_libc26
	test "$$(/tmp/test_dynlib_libc26)" = "$$(printf 'strlen: 5\nunloaded: TRUE')"
	./$(COMPILER) test/test_cdecl_indirect.pas /tmp/test_cdecl_indirect26
	test "$$(/tmp/test_cdecl_indirect26)" = "$$(printf '4.0\n1024.0\n12.0')"
	./$(COMPILER) test/test_auto_var.pas /tmp/test_auto_var26
	test "$$(/tmp/test_auto_var26)" = "$$(printf 'Global tests:\ng_int = 456\ng_str = hello global\ng_bool is False\ng_dbl = 3.14\nLocal tests:\nl_int = 123\nl_str = hello local\nl_bool is True\nl_rec = 10, 20\np_rec^ = 10, 20\nall auto variable tests done!')"
	./$(COMPILER) test/test_sqlite_crud_autotyped.pas /tmp/test_sqlite_crud_autotyped26
	test "$$(/tmp/test_sqlite_crud_autotyped26)" = "$$(printf 'open=0\nprepare=0\n1 alice\n2 bob\nfinalize=0\nclose=0')"
	! ./$(COMPILER) test/test_auto_var_fail.pas /tmp/test_auto_var_fail26 > /tmp/test_auto_var_fail.log 2>&1
	grep -q "use of auto variable before type is inferred" /tmp/test_auto_var_fail.log
	./$(COMPILER) test/test_lazy_var.pas /tmp/test_lazy_var26
	test "$$(/tmp/test_lazy_var26)" = "$$(printf 'Basic tests:\na = 123\nb = hello inline\nc = 3.14\nd is True\nScoping tests:\nouter x = 10\ninner x = 20\ninner y = 30\nouter x after block = 10\nMultiple declarations:\nx = 42, y = 24\nall lazy variable tests done!')"
	rm -f /tmp/test_sqlite_crud_lazy26.db
	./$(COMPILER) test/test_sqlite_crud_lazy.pas /tmp/test_sqlite_crud_lazy26
	test "$$(/tmp/test_sqlite_crud_lazy26)" = "$$(printf -- '--- File Database ---\nopen=0\nprepare=0\n1 alice alice\n2 bob bob\nfinalize=0\nclose=0\n--- In-Memory Database ---\nopen=0\nprepare=0\n1 alice alice\n2 bob bob\nfinalize=0\nclose=0')"
	! ./$(COMPILER) test/test_lazy_var_scope_fail.pas /tmp/test_lazy_var_scope_fail26 > /tmp/test_lazy_var_scope_fail.log 2>&1
	grep -q "undefined variable (a)" /tmp/test_lazy_var_scope_fail.log
	./$(COMPILER) test/test_c_define_const.pas /tmp/c_define_const26
	test "$$(/tmp/c_define_const26)" = "$$(printf '0\n100\n101\n101')"
	./$(COMPILER) test/test_c_struct_fields.pas /tmp/c_struct_fields26
	test "$$(/tmp/c_struct_fields26)" = "$$(printf '7\n9\n11\nh\ni\n3\n4')"
	./$(COMPILER) test/test_c_struct_many.pas /tmp/c_struct_many26
	test "$$(/tmp/c_struct_many26)" = "$$(printf '30\n4300')"
	./$(COMPILER) test/test_func_ptr_return.pas /tmp/func_ptr_return26
	test "$$(/tmp/func_ptr_return26)" = "$$(printf '7\n8\n9')"
	./$(COMPILER) test/test_c_struct_tags.pas /tmp/c_struct_tags26
	test "$$(/tmp/c_struct_tags26)" = "$$(printf '12\n10\n20')"
	./$(COMPILER) test/test_c_packed_aligned.pas /tmp/test_c_packed_aligned26
	test "$$(/tmp/test_c_packed_aligned26)" = "$$(printf 'X\n42\n8\n4\nP\n7\n5\n1\nA\n8\n16\n8\nT\n16\n16\n4')"
	./$(COMPILER) test/test_c_preprocess.pas /tmp/c_preprocess26
	test "$$(/tmp/c_preprocess26)" = "42"
	./$(COMPILER) --debug test/test_c_preprocess.pas /tmp/c_preprocess_debug26 > /tmp/c_preprocess_debug26.log
	grep -q "C preprocessor: expand function" /tmp/c_preprocess_debug26.log
	test "$$(/tmp/c_preprocess_debug26)" = "42"
	./$(COMPILER) test/test_c_macro_soup.pas /tmp/c_macro_soup26
	test "$$(/tmp/c_macro_soup26)" = "42"
	./$(COMPILER) test/bootstrap_features.pas /tmp/bootstrap_features26
	test "$$(/tmp/bootstrap_features26)" = "$$(printf '120\n98\ncase-ok\n0')"
	./$(COMPILER) test/paramcount_if.pas /tmp/paramcount_if26
	test "$$(/tmp/paramcount_if26 dummy)" = "argc-ok"
	./$(COMPILER) test/records.pas /tmp/records26
	test "$$(/tmp/records26)" = "$$(printf '42\n7\n11\n22')"
	./$(COMPILER) test/fileio.pas /tmp/fileio26
	test "$$(/tmp/fileio26 test/hello.pas | sed -n '1,3p')" = "$$(printf 'test/hello.pas\n14\n54')"
	./$(COMPILER) test/fileio.pas /tmp/fileio_ir26
	test "$$(/tmp/fileio_ir26 test/hello.pas | sed -n '1,3p')" = "$$(printf 'test/hello.pas\n14\n54')"
	./$(COMPILER) test/string_compare.pas /tmp/string_compare26
	test "$$(/tmp/string_compare26)" = "$$(printf '1\n1\n1')"
	./$(COMPILER) test/test_string_concat.pas /tmp/test_string_concat26
	test "$$(/tmp/test_string_concat26)" = "$$(printf 'Hello, World!\nHello there!\nHi World')"
	./$(COMPILER) test/record_string_field.pas /tmp/record_string_field26
	test "$$(/tmp/record_string_field26)" = "$$(printf '1\n4')"
	./$(COMPILER) test/test_class_str.pas /tmp/test_class_str26
	test "$$(/tmp/test_class_str26)" = "FStr: hello"
	./$(COMPILER) test/vars.pas /tmp/vars26
	test "$$(/tmp/vars26)" = "$$(printf 'Sum: 42\nCountdown:\n5\n4\n3\n2\n1\nSquares:\n1\n4\n9\n16\n25\nbig\nloop 0\nloop 1\nloop 2')"
	./$(COMPILER) test/arrays.pas /tmp/arrays26
	test "$$(/tmp/arrays26)" = "$$(printf 'Squares:\n0\n1\n4\n9\n16\n25\n36\n49\n64\n81\nH\ni\n!')"
	./$(COMPILER) test/strings.pas /tmp/strings26
	test "$$(/tmp/strings26)" = "$$(printf 'Hello, World!\nPascal26\n13\nPascal26\n8')"
	./$(COMPILER) test/test_heap.pas /tmp/test_heap26
	test "$$(/tmp/test_heap26)" = "$$(printf '1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_class.pas /tmp/test_class26
	test "$$(/tmp/test_class26)" = "$$(printf '1\n1\n1\n42\n100\n999\n888')"
	./$(COMPILER) test/test_tmyclass_name.pas /tmp/test_tmyclass_name26
	test "$$(/tmp/test_tmyclass_name26)" = "78"
	./$(COMPILER) test/test_setlength_dynarray_result.pas /tmp/test_setlength_dynarray_result26
	test "$$(/tmp/test_setlength_dynarray_result26)" = "$$(printf '42\n99\n2\n7\n3')"
	./$(COMPILER) test/test_class_methods.pas /tmp/test_class_methods26
	test "$$(/tmp/test_class_methods26)" = "3"
	./$(COMPILER) test/test_visibility.pas /tmp/test_visibility26
	test "$$(/tmp/test_visibility26)" = "$$(printf '7\n3\n42\n99\n123')"
	./$(COMPILER) test/test_ptr_alias.pas /tmp/test_ptr_alias26
	test "$$(/tmp/test_ptr_alias26)" = "$$(printf '777\n888\n12\n34\n20\n30\n99\n55')"
	./$(COMPILER) test/test_ptr_deref_field.pas /tmp/test_ptr_deref_field26
	test "$$(/tmp/test_ptr_deref_field26)" = "$$(printf '10\n20\n42\n99\n1234\n5\n9999\n100\n300\n777')"
	./$(COMPILER) test/test_ptr_deref_vararg.pas /tmp/test_ptr_deref_vararg26
	test "$$(/tmp/test_ptr_deref_vararg26)" = "$$(printf '5\n7\n7')"
	./$(COMPILER) test/test_pointer_deref_depth.pas /tmp/test_pointer_deref_depth26
	/tmp/test_pointer_deref_depth26; test "$$?" = "42"
	./$(COMPILER) test/test_ptr_cast.pas /tmp/test_ptr_cast26
	test "$$(/tmp/test_ptr_cast26)" = "$$(printf '12345\n99999\n77\n88\n42\n1111\n7\n99\n100\n200\nbuiltin_cast: int64 ok\n100')"
	./$(COMPILER) test/test_ptr_arithmetic.pas /tmp/test_ptr_arithmetic26
	test "$$(/tmp/test_ptr_arithmetic26)" = "$$(printf '30\n20\n40\n40\n77\n99\n20')"
	./$(COMPILER) test/test_pointers.pas /tmp/test_pointers26
	test "$$(/tmp/test_pointers26 | tail -1)" = "all pointer tests done!"
	./$(COMPILER) test/test_ref.pas /tmp/test_ref26
	test "$$(/tmp/test_ref26)" = "hello"
	./$(COMPILER) test/test_rtti_emit.pas /tmp/test_rtti_emit26
	test "$$(/tmp/test_rtti_emit26)" = "$$(printf '42\n3\nhello')"
	./$(COMPILER) --dump-rtti test/test_rtti_emit.pas /tmp/test_rtti_emit_dump26 > /tmp/test_rtti_emit_dump26.log
	grep -q "enum TAlign count=4 rttiOff=.* alNone alLeft alRight alClient" /tmp/test_rtti_emit_dump26.log
	grep -q "class TBase" /tmp/test_rtti_emit_dump26.log
	grep -q "class TChild" /tmp/test_rtti_emit_dump26.log
	grep -q "prop Id tk=1 getField@8 setField@8" /tmp/test_rtti_emit_dump26.log
	grep -q "meth Notify proc=" /tmp/test_rtti_emit_dump26.log
	grep -q "prop Caption tk=23" /tmp/test_rtti_emit_dump26.log
	grep -q "prop Owner tk=6" /tmp/test_rtti_emit_dump26.log
	grep -q "prop Align tk=1 enum=TAlign" /tmp/test_rtti_emit_dump26.log
	./$(COMPILER) test/test_rtti_reg.pas /tmp/test_rtti_reg26
	test "$$(/tmp/test_rtti_reg26)" = "$$(printf 'Count: 2\nClass 0: TBase\nClass 1: TChild')"
	./$(COMPILER) test/test_rtti.pas /tmp/test_rtti26
	/tmp/test_rtti26 > /tmp/test_rtti26.log
	grep -q "c.Caption: Antigravity" /tmp/test_rtti26.log
	grep -q "c.Align: 3" /tmp/test_rtti26.log
	grep -q "OnClick event thunk matches DummyHandler" /tmp/test_rtti26.log
	./$(COMPILER) test/test_classref.pas /tmp/test_classref26
	test "$$(/tmp/test_classref26)" = "$$(printf 'same: yes\nname=TFoo\nTag=99')"
	./$(COMPILER) test/test_class_of.pas /tmp/test_class_of26
	test "$$(/tmp/test_class_of26)" = "TChild"
	./$(COMPILER) test/test_initsec.pas /tmp/test_initsec26
	test "$$(/tmp/test_initsec26)" = "AB"
	./$(COMPILER) test/test_wildcard_lfm.pas /tmp/test_wildcard_lfm26
	test "$$(/tmp/test_wildcard_lfm26)" = "$$(printf 'Caption=Wildcard\nWidth=200')"
	./$(COMPILER) test/test_field_chain.pas /tmp/test_field_chain26
	test "$$(/tmp/test_field_chain26)" = "$$(printf 'deep=9\nbasevar=9\nfield=9')"
	./$(COMPILER) test/test_with.pas /tmp/test_with26
	test "$$(/tmp/test_with26 | tail -1)" = "all with tests completed!"
	./$(COMPILER) test/test_streaming.pas /tmp/test_streaming26
	test "$$(/tmp/test_streaming26)" = "$$(printf 'root.Name=Root1\nroot.Count=42\nroot.Title=Hi\nOnGo bound: yes\nchildCount=1\nkid.Name=Kid1\nkid.Value=7')"
	./$(COMPILER) test/test_streaming_enumset.pas /tmp/test_streaming_enumset26
	test "$$(/tmp/test_streaming_enumset26)" = "$$(printf 'Color=1\nColors=5\nCaption=Hello, long world!')"
	./$(COMPILER) test/test_resource.pas /tmp/test_resource26
	test "$$(/tmp/test_resource26)" = "$$(printf 'len=16\ndata=Hello, resource!\nmissing: ok')"
	./$(COMPILER) test/test_lfm.pas /tmp/test_lfm26
	test "$$(/tmp/test_lfm26)" = "$$(printf 'Caption=Hello LFM\nWidth=320\nAlign=2\nAnchors=10\nchildCount=1\nbtn.Name=Btn\nbtn.Caption=OK\nbtn.Tag=7')"
	./$(COMPILER) test/gui/repro_multiunit_rtti_segfault.pas /tmp/repro_multiunit_rtti26
	test "$$(/tmp/repro_multiunit_rtti26)" = "$$(printf 'propcount=2\nName found')"
	./$(COMPILER) test/test_char_to_string.pas /tmp/test_char_to_string26
	test "$$(/tmp/test_char_to_string26)" = "$$(printf 'x\ny\nab\nZZy\nyZZ\nyy\nA\nqqq\nz\ndone')"
	./$(COMPILER) test/test_comments.pas /tmp/test_comments26
	test "$$(/tmp/test_comments26)" = "$$(printf '3\ndone')"
	# flexcolumn directive: call args carry write-style :w:d modifiers
	./$(COMPILER) test/test_flexcolumn.pas /tmp/test_flexcolumn26
	test "$$(/tmp/test_flexcolumn26 | tail -1)" = "OK"
	# const small-record method arg: pre-body call uses the by-ref convention
	./$(COMPILER) test/test_const_record_method_prebody.pas /tmp/test_const_record_method_prebody26
	test "$$(/tmp/test_const_record_method_prebody26 | tail -1)" = "OK"
	./$(COMPILER) --target=i386 test/test_const_record_method_prebody.pas /tmp/test_i386_crmp
	test "$$(tools/run_target.sh i386 /tmp/test_i386_crmp | tail -1)" = "OK"
	# metaclass descendant enforcement: class-of assignment is descendant-checked
	./$(COMPILER) test/test_metaclass_descendant.pas /tmp/test_metaclass_descendant26
	test "$$(/tmp/test_metaclass_descendant26 | tail -1)" = "OK"
	! ./$(COMPILER) test/test_metaclass_descendant_error.pas /tmp/test_metaclass_descendant_error26 > /tmp/test_metaclass_descendant_error.log 2>&1
	grep -q "metaclass type mismatch: TOther is not TBase" /tmp/test_metaclass_descendant_error.log
	! ./$(COMPILER) test/test_metaclass_narrowing_error.pas /tmp/test_metaclass_narrowing_error26 > /tmp/test_metaclass_narrowing_error.log 2>&1
	grep -q "metaclass type mismatch: TBase is not TChild" /tmp/test_metaclass_narrowing_error.log
	# object: rooted object-reference type (any instance; cast to touch members)
	./$(COMPILER) test/test_object_reference.pas /tmp/test_object_reference26
	test "$$(/tmp/test_object_reference26 | tail -1)" = "OK"
	! ./$(COMPILER) test/test_object_reference_error.pas /tmp/test_object_reference_error26 > /tmp/test_object_reference_error.log 2>&1
	grep -q "member access on a bare object reference" /tmp/test_object_reference_error.log
	./$(COMPILER) test/test_case_insensitive.pas /tmp/test_case_insensitive26
	test "$$(/tmp/test_case_insensitive26)" = "42"
	./$(COMPILER) test/test_case_sensitive.pas /tmp/test_case_sensitive26
	test "$$(/tmp/test_case_sensitive26)" = "$$(printf '10\n20\nupper\nlower')"
	! ./$(COMPILER) test/test_case_sensitive_error.pas /tmp/test_case_sensitive_error26 > /tmp/test_case_sensitive_error.log 2>&1
	grep -q "undefined variable (VALUE)" /tmp/test_case_sensitive_error.log
	# FPC-parity nested {} comments by default (delphi mode / NESTEDCOMMENTS OFF stay flat)
	./$(COMPILER) test/test_nested_comments.pas /tmp/test_nested_comments26
	test "$$(/tmp/test_nested_comments26)" = "$$(printf '3\nNESTED COMMENTS OK')"
	# constructor arity is compile-checked (missing required arg used to desync the caller stack)
	! ./$(COMPILER) test/test_ctor_arity_error.pas /tmp/test_ctor_arity_error26 > /tmp/test_ctor_arity_error.log 2>&1
	grep -q "not enough arguments to constructor" /tmp/test_ctor_arity_error.log
	! ./$(COMPILER) test/test_decl_order_global_error.pas /tmp/test_decl_order_global_error26 > /tmp/test_decl_order_global_error.log 2>&1
	grep -q "declared later" /tmp/test_decl_order_global_error.log
	grep -q "(gLate)" /tmp/test_decl_order_global_error.log
	# {$DECLORDER OFF} opt-out: the lenient program compiles + runs
	./$(COMPILER) test/test_decl_order_lax.pas /tmp/test_decl_order_lax26
	test "$$(/tmp/test_decl_order_lax26)" = "42"
	# --lax-decl-order flag: the strict error case compiles cleanly under the opt-out
	./$(COMPILER) --lax-decl-order test/test_decl_order_global_error.pas /tmp/test_decl_order_global_lax26
	# Rio inline loop var: for var i := a to b (counted) + for var x in c (for-in)
	./$(COMPILER) test/test_for_var_inline.pas /tmp/test_for_var_inline26
	test "$$(/tmp/test_for_var_inline26)" = "$$(printf '10\n6\nx=0\nx=10\nx=20\nx=30\nc=a\nc=b\nc=c\nr=1,2\nr=3,4\nm=0\nm=2')"
	./$(COMPILER) test/test_case_sensitive_unit.pas /tmp/test_case_sensitive_unit26
	test "$$(/tmp/test_case_sensitive_unit26)" = "$$(printf 'unit\n7')"
	./$(COMPILER) test/test_qualified_units.pas /tmp/test_qualified_units26
	test "$$(/tmp/test_qualified_units26)" = "$$(printf '1074030207\n1074030207\n3\n7\n11\n22\n101\n201')"
	./$(COMPILER) test/test_uses_alias.pas /tmp/test_uses_alias26
	test "$$(/tmp/test_uses_alias26)" = "$$(printf '42\n7\n2')"
	./$(COMPILER) test/test_relpath_uses.pas /tmp/test_relpath_uses26
	test "$$(/tmp/test_relpath_uses26)" = "$$(printf '13\n15\n100')"
	./$(COMPILER) test/test_syncobjs.pas /tmp/test_syncobjs26
	test "$$(/tmp/test_syncobjs26)" = "$$(printf '1\n2\n3')"
	./$(COMPILER) test/test_getmem_proc.pas /tmp/test_getmem_proc26
	test "$$(/tmp/test_getmem_proc26)" = "$$(printf '1\n65\n66\n90\n1')"
	./$(COMPILER) test/test_freemem.pas /tmp/test_freemem26
	test "$$(/tmp/test_freemem26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_new_dispose.pas /tmp/test_new_dispose26
	test "$$(/tmp/test_new_dispose26)" = "$$(printf '1234\n16\n1')"
	./$(COMPILER) test/test_reallocmem.pas /tmp/test_reallocmem26
	test "$$(/tmp/test_reallocmem26)" = "$$(printf '1\n50\n1\n1\n1\n77')"
	./$(COMPILER) test/test_str_val.pas /tmp/test_str_val26
	test "$$(/tmp/test_str_val26)" = "$$(printf '42\n-7\n0\n[  1234]\n100\n0\n-25\n0\n2\n1\nabc\n3')"
	./$(COMPILER) test/test_intrinsic_name_var_no_collision.pas /tmp/test_intrinsic_name_var_no_collision26
	test "$$(/tmp/test_intrinsic_name_var_no_collision26)" = "$$(printf '1\n2\n3\n4\n5\n6\n7')"
	./$(COMPILER) test/test_assign_types.pas /tmp/test_assign_types26
	test "$$(/tmp/test_assign_types26)" = "$$(printf 'foobarbaz\nHi world!\nx\nQ\nhello\nY\n65')"
	./$(COMPILER) test/test_method_named_result.pas /tmp/test_method_named_result26
	test "$$(/tmp/test_method_named_result26)" = "$$(printf '120\nHi Bob')"
	./$(COMPILER) test/test_ptr_field_index.pas /tmp/test_ptr_field_index26
	test "$$(/tmp/test_ptr_field_index26)" = "$$(printf '10\n30\n50')"
	./$(COMPILER) test/test_record_multifield.pas /tmp/test_record_multifield26
	test "$$(/tmp/test_record_multifield26)" = "$$(printf '11 22\n0 1 2\n0 10 20')"
	./$(COMPILER) test/test_readln.pas /tmp/test_readln26
	test "$$(printf '100 200 300\n42\n10 20\nhello world\nQ\nSKIP\n-5\n' | /tmp/test_readln26)" = "$$(printf -- '100\n200\n300\n-5\n30\nhello world\nQ')"
	./$(COMPILER) test/test_record_copy.pas /tmp/test_record_copy26
	test "$$(/tmp/test_record_copy26)" = "$$(printf '1 2 3 4\n20 21 22 23')"
	./$(COMPILER) test/test_static_methods.pas /tmp/test_static_methods26
	test "$$(/tmp/test_static_methods26)" = "$$(printf '7\n11\n25')"
	./$(COMPILER) test/test_write_fmt.pas /tmp/test_write_fmt26
	test "$$(/tmp/test_write_fmt26)" = "$$(printf '    42\n    -7\n1000\n  0\n    hi\n   ab\n99\nx')"
	./$(COMPILER) test/test_math_unit.pas /tmp/test_math_unit26
	test "$$(/tmp/test_math_unit26)" = "$$(printf '42\n999\n10\n20\n256\n6\n144')"
	./$(COMPILER) test/test_generic_func.pas /tmp/test_generic_func26
	test "$$(/tmp/test_generic_func26)" = "$$(printf '7\n10\n3\n4\n5\n1\n10\n99\n42')"
	./$(COMPILER) test/test_overloading.pas /tmp/test_overloading26
	test "$$(/tmp/test_overloading26)" = "$$(printf 'Integer: 42\nChar: A\nTwo Integers: 10, 20\nAdd integers: 12\nChar addition: XY')"
	./$(COMPILER) test/test_op_overload.pas /tmp/test_op_overload26
	test "$$(/tmp/test_op_overload26)" = "$$(printf '1\n0\n1\n0\n1\n0\n10\n6')"
	./$(COMPILER) test/test_op_fpc_named_result.pas /tmp/test_op_fpc_named_result26
	test "$$(/tmp/test_op_fpc_named_result26)" = "$$(printf '5/6\n1/6\n3/2\n1/6\n1/6\n4/12')"
	./$(COMPILER) test/test_op_unit_scope.pas /tmp/test_op_unit_scope26
	test "$$(/tmp/test_op_unit_scope26)" = "$$(printf 'in:5/6\n5/6\n3/2\n1/6')"
	./$(COMPILER) test/test_loop_control.pas /tmp/test_loop_control26
	test "$$(/tmp/test_loop_control26)" = "$$(printf '8\n5\n8\n7\n3')"
	./$(COMPILER) test/test_goto.pas /tmp/test_goto26
	test "$$(/tmp/test_goto26)" = "$$(printf '15\nskipped\n3')"
	./$(COMPILER) test/test_math_parens.pas /tmp/test_math_parens26
	test "$$(/tmp/test_math_parens26)" = "14"
	./$(COMPILER) test/test_inline_register.pas /tmp/test_inline_register26
	test "$$(/tmp/test_inline_register26 | tail -1)" = "all inline/register tests completed!"
	./$(COMPILER) test/test_pascal_directives.pas /tmp/test_pascal_directives26
	test "$$(/tmp/test_pascal_directives26)" = "$$(printf '1\n0\n1\n1\n1\n0\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_comment_directive.pas /tmp/test_comment_directive26
	test "$$(/tmp/test_comment_directive26)" = "42"
	./$(COMPILER) -dCLI_FLAG test/test_pascal_directives.pas /tmp/test_pascal_directives_defined26
	test "$$(/tmp/test_pascal_directives_defined26)" = "$$(printf '1\n0\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_pascal_directive_messages.pas /tmp/test_pascal_directive_messages26 > /tmp/test_pascal_directive_messages.log
	grep -q "warning: warning text" /tmp/test_pascal_directive_messages.log
	grep -q "message: message text" /tmp/test_pascal_directive_messages.log
	./$(COMPILER) test/test_warn_self_result.pas /tmp/test_warn_self_result26
	test "$$(/tmp/test_warn_self_result26)" = "2"
	./$(COMPILER) --warn-self-result test/test_warn_self_result.pas /tmp/test_warn_self_result_warn26 > /tmp/test_warn_self_result.log
	grep -q "warning: bare own name 'Count' reads the result of parameterless function Count" /tmp/test_warn_self_result.log
	! ./$(COMPILER) --warn-self-result -Werror test/test_warn_self_result.pas /tmp/test_warn_self_result_werror26 > /tmp/test_warn_self_result_werror.log 2>&1
	grep -q "warning promoted by -Werror" /tmp/test_warn_self_result_werror.log
	# Oversized-stack-frame warning: 2MB local warns (default 1MB threshold), runs fine
	./$(COMPILER) test/test_warn_stack_frame.pas /tmp/test_warn_stack_frame26 > /tmp/test_warn_stack_frame.log
	grep -q "routine 'BigLocal' uses 2097152 bytes of stack frame" /tmp/test_warn_stack_frame.log
	! grep -q "routine 'SmallLocal'" /tmp/test_warn_stack_frame.log
	test "$$(/tmp/test_warn_stack_frame26)" = "$$(printf '1\n42')"
	# --max-stack-frame=0 disables the warning entirely
	./$(COMPILER) --max-stack-frame=0 test/test_warn_stack_frame.pas /tmp/test_warn_stack_frame_off26 > /tmp/test_warn_stack_frame_off.log
	! grep -q "stack frame" /tmp/test_warn_stack_frame_off.log
	# -Werror promotes the oversized-frame warning to a fatal error
	! ./$(COMPILER) -Werror test/test_warn_stack_frame.pas /tmp/test_warn_stack_frame_werr26 > /tmp/test_warn_stack_frame_werr.log 2>&1
	grep -q "uses 2097152 bytes of stack frame .* (warning promoted by -Werror)" /tmp/test_warn_stack_frame_werr.log
	! ./$(COMPILER) test/test_pascal_directive_error.pas /tmp/test_pascal_directive_error26 > /tmp/test_pascal_directive_error.log 2>&1
	grep -q "requested failure" /tmp/test_pascal_directive_error.log
	./$(COMPILER) test/test_pascal_conditional_include.pas /tmp/test_pascal_conditional_include26
	test "$$(/tmp/test_pascal_conditional_include26)" = "$$(printf '42\n7')"
	./$(COMPILER) test/test_directive_if_numeric.pas /tmp/test_directive_if_numeric26
	test "$$(/tmp/test_directive_if_numeric26)" = "$$(printf '1\n0\n1\n0\n0\n1\n0\n1\n1')"
	! ./$(COMPILER) test/test_directive_if_typemix.pas /tmp/test_directive_if_typemix26 > /tmp/test_directive_if_typemix.log 2>&1
	grep -q "boolean operands" /tmp/test_directive_if_typemix.log
	! ./$(COMPILER) test/test_directive_if_float.pas /tmp/test_directive_if_float26 > /tmp/test_directive_if_float.log 2>&1
	grep -q "float literals not supported" /tmp/test_directive_if_float.log
	./$(COMPILER) test/test_strict_overload.pas /tmp/test_strict_overload26
	test "$$(/tmp/test_strict_overload26)" = "$$(printf '5\n65')"
	! ./$(COMPILER) test/test_strict_overload_error.pas /tmp/test_strict_overload_error26 > /tmp/test_strict_overload_error.log 2>&1
	grep -q "overloaded routine requires overload directive" /tmp/test_strict_overload_error.log
	./$(COMPILER) --strict-overload test/test_overloading.pas /tmp/test_overloading_strict26
	test "$$(/tmp/test_overloading_strict26)" = "$$(printf 'Integer: 42\nChar: A\nTwo Integers: 10, 20\nAdd integers: 12\nChar addition: XY')"
	./$(COMPILER) test/test_sizeof.pas /tmp/test_sizeof26
	test "$$(/tmp/test_sizeof26)" = "$$(printf '1\n1\n2\n2\n4\n4\n4\n4\n8\n8\n8\n8\n8\n8\n8\n1\n1')"
	! ./$(COMPILER) test/test_sizeof_error.pas /tmp/test_sizeof_error26 > /tmp/test_sizeof_error.log 2>&1
	grep -q "SizeOf: unknown type" /tmp/test_sizeof_error.log
	./$(COMPILER) test/test_record_alignment.pas /tmp/test_record_alignment26
	test "$$(/tmp/test_record_alignment26)" = "$$(printf '8\n4\n5\n1\n6\n2\n5\n1\n12\n2\n8\n12\n1\n8')"
	./$(COMPILER) test/test_record_layout_stress.pas /tmp/test_record_layout_stress26
	test "$$(/tmp/test_record_layout_stress26)" = "$$(printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16\n17\n18\n19\n20\n21\n22\n23\n24\n25\n26\n27\n28\n29\n30\n31\n32\n33\n34\n35')"
	./$(COMPILER) test/test_pthread_header.pas /tmp/test_pthread_header26
	test "$$(/tmp/test_pthread_header26)" = "pthread loaded successfully"
	./$(COMPILER) test/test_c_crypt.pas /tmp/test_c_crypt26
	/tmp/test_c_crypt26 | grep -q "All crypt tests passed successfully!"
	./$(COMPILER) test/test_c_dlopen.pas /tmp/test_c_dlopen26
	/tmp/test_c_dlopen26 | grep -q "All dynamic loading and dlsym tests passed successfully!"
	./$(COMPILER) test/test_c_gtk.pas /tmp/test_c_gtk26
	test "$$(/tmp/test_c_gtk26)" = "my_gtk header parsed and imported successfully"
	./$(COMPILER) test/test_c_gtk_call.pas /tmp/test_c_gtk_call26
	xvfb-run -a /tmp/test_c_gtk_call26
	./$(COMPILER) test/test_c_gtk_types.pas /tmp/test_c_gtk_types26
	xvfb-run -a /tmp/test_c_gtk_types26
	./$(COMPILER) test/test_c_gtk_window.pas /tmp/test_c_gtk_window26
	xvfb-run -a /tmp/test_c_gtk_window26
	./$(COMPILER) test/test_c_header_case_sensitive_import.pas /tmp/test_c_header_case_sensitive_import26
	test "$$(/tmp/test_c_header_case_sensitive_import26)" = "77"
	./$(COMPILER) test/test_type_runtime.pas /tmp/test_type_runtime26
	test "$$(/tmp/test_type_runtime26)" = "$$(printf '1\n1\n1\n0\n1\n18446744065119617025\n18446744073709551615\n9223372036854775807\n1\n-1\n-1\n-1\n18446744073709551615\n-1\n0\n2\n7\n123456\n9\n20')"
	./$(COMPILER) test/test_float.pas /tmp/test_float26
	test "$$(/tmp/test_float26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_extended_is_double.pas /tmp/test_ext_dbl26
	test "$$(/tmp/test_ext_dbl26)" = "$$(printf 'eq-div\n16.0\n6.00')"
	./$(COMPILER) test/test_named_dynarray_field.pas /tmp/test_named_dynfield26
	test "$$(/tmp/test_named_dynfield26)" = "$$(printf 'nums len=3 sum=60\nnames len=2 abb\nrec len=4 v3=99')"
	./$(COMPILER) test/test_float_const_and_cast.pas /tmp/test_fconst_cast26
	test "$$(/tmp/test_fconst_cast26)" = "$$(printf '0.0010\n3.14159\n-2.50\n0.0010\n-7.25\n42\n6.28318\n2.50\n3.00\n7.00\n3.0000')"
	./$(COMPILER) test/test_dynarray_record_field.pas /tmp/test_dynrecfield26
	test "$$(/tmp/test_dynrecfield26)" = "$$(printf 'len=3 a0=10 a2=30 sum=60\nret len=4 first=1 last=4')"
	./$(COMPILER) test/test_nested_dynarray_field.pas /tmp/test_nesteddynfield26
	test "$$(/tmp/test_nesteddynfield26)" = "m00=0 m12=12 m22=22 sum=99"
	./$(COMPILER) test/test_dynarray.pas /tmp/test_dynarray26
	test "$$(/tmp/test_dynarray26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_dynarray_ansistring.pas /tmp/test_dynarray_ansistring26
	test "$$(/tmp/test_dynarray_ansistring26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) --threadsafe test/test_dynarray_ansistring.pas /tmp/test_dynarray_ansistring_threadsafe26
	test "$$(/tmp/test_dynarray_ansistring_threadsafe26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_dynarray_managed_record.pas /tmp/test_dynarray_managed_record26
	test "$$(/tmp/test_dynarray_managed_record26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) --threadsafe test/test_dynarray_managed_record.pas /tmp/test_dynarray_managed_record_threadsafe26
	test "$$(/tmp/test_dynarray_managed_record_threadsafe26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_dynarray_params.pas /tmp/test_dynarray_params26
	test "$$(/tmp/test_dynarray_params26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_dynarray_result.pas /tmp/test_dynarray_result26
	test "$$(/tmp/test_dynarray_result26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) -Fulib/rtl test/test_length_dynarray_call.pas /tmp/test_length_dynarray_call26
	test "$$(/tmp/test_length_dynarray_call26)" = "$$(printf '3\n3\n0\n0\n4\n0')"
	./$(COMPILER) test/test_local_shadows_method_assign.pas /tmp/test_local_shadows_method_assign26
	test "$$(/tmp/test_local_shadows_method_assign26)" = "$$(printf '10\n20\n30\n40\n-1')"
	./$(COMPILER) test/test_static_array_ansistring_field.pas /tmp/test_static_array_ansistring_field26
	test "$$(/tmp/test_static_array_ansistring_field26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_ansistring_record_char_read.pas /tmp/test_ansistring_record_char_read26
	test "$$(/tmp/test_ansistring_record_char_read26)" = "$$(printf '1\n1\n1')"
	./$(COMPILER) test/test_nested_dynarray.pas /tmp/test_nested_dynarray26
	test "$$(/tmp/test_nested_dynarray26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_nested_dynarray_alias.pas /tmp/test_nested_dynarray_alias26
	test "$$(/tmp/test_nested_dynarray_alias26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_dynarray_managed_field_reassign.pas /tmp/test_dynarray_managed_field_reassign26
	test "$$(/tmp/test_dynarray_managed_field_reassign26)" = "$$(printf '1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_fixed_array_of_dynarray.pas /tmp/test_fixed_array_of_dynarray26
	test "$$(/tmp/test_fixed_array_of_dynarray26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_nested_dynarray_managed.pas /tmp/test_nested_dynarray_managed26
	test "$$(/tmp/test_nested_dynarray_managed26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) --threadsafe test/test_nested_dynarray_managed.pas /tmp/test_nested_dynarray_managed_threadsafe26
	test "$$(/tmp/test_nested_dynarray_managed_threadsafe26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_setlength_managed_field.pas /tmp/test_setlength_managed_field26
	test "$$(/tmp/test_setlength_managed_field26)" = "$$(printf 'ABxxx\nAB\nA\nQzz')"
	./$(COMPILER) test/test_managed_record_assign.pas /tmp/test_managed_record_assign26
	test "$$(/tmp/test_managed_record_assign26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_managed_record_exit.pas /tmp/test_managed_record_exit26
	test "$$(/tmp/test_managed_record_exit26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\nOK')"
	./$(COMPILER) test/test_managed_record_funcname_return.pas /tmp/test_managed_record_funcname_return26
	test "$$(/tmp/test_managed_record_funcname_return26)" = "$$(printf '1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_managed_record_field_string_ops.pas /tmp/test_managed_record_field_string_ops26
	test "$$(/tmp/test_managed_record_field_string_ops26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_char_arg_ansistring.pas /tmp/test_char_arg_ansistring26
	test "$$(/tmp/test_char_arg_ansistring26)" = "$$(printf 'x\nyy\nz\n[q]')"
	./$(COMPILER) test/test_managed_result_move.pas /tmp/test_managed_result_move26
	test "$$(/tmp/test_managed_result_move26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_managed_arg_temp.pas /tmp/test_managed_arg_temp26
	test "$$(/tmp/test_managed_arg_temp26)" = "$$(printf 'literal\nab\nk\n<x>\n<m>\nkeep\n1\n1')"
	./$(COMPILER) test/test_nested_cow.pas /tmp/test_nested_cow26
	test "$$(/tmp/test_nested_cow26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_variant.pas /tmp/test_variant26
	test "$$(/tmp/test_variant26)" = "$$(printf '42\n-7\nQ\n3.14\n1\n100')"
	./$(COMPILER) test/test_variant_ops.pas /tmp/test_variant_ops26
	test "$$(/tmp/test_variant_ops26)" = "$$(printf '8\n2\n15\n7.5\n12.5\nTRUE\nFALSE\nFALSE\nTRUE\nTRUE\n11\nTRUE')"
	./$(COMPILER) test/test_variant_div.pas /tmp/test_variant_div26
	test "$$(/tmp/test_variant_div26)" = "$$(printf '3\n2\n3.4\n2.5')"
	./$(COMPILER) test/test_variant_string.pas /tmp/test_variant_string26
	test "$$(/tmp/test_variant_string26)" = "$$(printf 'hello\n42\nhello\nmanaged\nworld\nlocal\n7')"
	./$(COMPILER) test/test_variant_string_ops.pas /tmp/test_variant_string_ops26
	test "$$(/tmp/test_variant_string_ops26)" = "$$(printf 'TRUE\nFALSE\nFALSE\nTRUE\nTRUE\nTRUE\nFALSE\nFALSE\nTRUE\nTRUE\nTRUE\nTRUE\nTRUE\nFALSE\nTRUE\nTRUE\nFALSE\nhello world\nab\nsweet potato\ngreen tomato\nFALSE\nTRUE\nFALSE\nFALSE')"
	./$(COMPILER) test/test_float_intrinsics.pas /tmp/test_float_intrinsics26
	test "$$(/tmp/test_float_intrinsics26)" = "$$(printf '3\n-3\n4\n2\n4\n0.7500\n3.0')"
	./$(COMPILER) test/test_nil_python_core.npy /tmp/test_nil_python_core26
	test "$$(/tmp/test_nil_python_core26)" = "$$(printf '0\n1\n1\n2\n3\n5\n10')"
	./$(COMPILER) test/test_nilpy_variant.npy /tmp/test_nilpy_variant26
	test "$$(/tmp/test_nilpy_variant26)" = "$$(printf '5\n3.14\n1')"
	./$(COMPILER) test/test_nilpy_class.npy /tmp/test_nilpy_class26
	test "$$(/tmp/test_nilpy_class26)" = "25"
	./$(COMPILER) test/test_nilpy_widen_fix.npy /tmp/test_nilpy_widen_fix26
	test "$$(/tmp/test_nilpy_widen_fix26)" = "$$(printf '5.0\n3.14\n7.0\n2.5')"
	./$(COMPILER) test/test_nilpy_call_return_infer.npy /tmp/test_nilpy_call_return_infer26
	test "$$(/tmp/test_nilpy_call_return_infer26)" = "42"
	./$(COMPILER) test/test_nilpy_c_define_const.npy /tmp/test_nilpy_c_define_const26
	test "$$(/tmp/test_nilpy_c_define_const26)" = "$$(printf '0\n100\n101')"
	./$(COMPILER) test/test_nilpy_c_pointer.npy /tmp/test_nilpy_c_pointer26
	test "$$(/tmp/test_nilpy_c_pointer26)" = "1"
	./$(COMPILER) test/test_nilpy_convert.npy /tmp/test_nilpy_convert26
	test "$$(/tmp/test_nilpy_convert26)" = "$$(printf '3\n42')"
	./$(COMPILER) test/test_nilpy_bool.npy /tmp/test_nilpy_bool26
	test "$$(/tmp/test_nilpy_bool26)" = "$$(printf 'True\nTrue\nTrue\nFalse\nTrue\nTrue')"
	./$(COMPILER) test/test_nilpy_str_float.npy /tmp/test_nilpy_str_float26
	test "$$(/tmp/test_nilpy_str_float26)" = "$$(printf '3.14\n2.5\n-1.25\npi=3.14159\n3\n2')"
	./$(COMPILER) test/test_sets.pas /tmp/test_sets26
	test "$$(/tmp/test_sets26 | tail -1)" = "all set tests completed!"
	./$(COMPILER) test/test_set_shapes.pas /tmp/test_set_shapes26
	test "$$(/tmp/test_set_shapes26)" = "$$(printf '1\n1\n1')"
	./$(COMPILER) test/test_aggregate_results.pas /tmp/test_aggregate_results26
	test "$$(/tmp/test_aggregate_results26)" = "$$(printf '1\n1\n1\n1\n1\n1\n2\n5\n16\n20')"
	./$(COMPILER) test/test_float_literals.pas /tmp/test_float_literals26
	test "$$(/tmp/test_float_literals26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_float_write.pas /tmp/test_float_write26
	test "$$(/tmp/test_float_write26)" = "$$(printf '3.50\n4\n-2.750\n1.0\n0.00\n10.5\n 1.0000000000000000E+000\n-2.0000000000000000E+000\n 0.0000000000000000E+000\n 3.5000000000000000E+000\n 1.2345000000000002E+003')"
	./$(COMPILER) test/test_float_width.pas /tmp/test_float_width26
	test "$$(/tmp/test_float_width26)" = "$$(printf '[   3.142]\n[      1.50]\n[  -2.5]\n[   123.46]\n[  10.00]\n[3.1]\n[ 0.00]\n[1000]')"
	./$(COMPILER) test/test_exceptions.pas /tmp/test_exceptions26
	test "$$(/tmp/test_exceptions26)" = "$$(printf '1\n2\n4\n5')"
	./$(COMPILER) test/test_exception_unit.pas /tmp/test_exception_unit26
	test "$$(/tmp/test_exception_unit26)" = "6"
	./$(COMPILER) test/test_exception_control_error.pas /tmp/test_exception_control_flow26
	test "$$(/tmp/test_exception_control_flow26)" = "$$(printf '1\n2\n3\n4\n5\n6\n7')"
	./$(COMPILER) test/test_exception_finally.pas /tmp/test_exception_finally26
	test "$$(/tmp/test_exception_finally26)" = "$$(printf '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n12')"
	./$(COMPILER) test/test_exception_typed.pas /tmp/test_exception_typed26
	test "$$(/tmp/test_exception_typed26)" = "$$(printf '41\n42\n43\n44\n45')"
	./$(COMPILER) test/test_except_derived_caught_by_base.pas /tmp/test_except_derived_caught_by_base26
	test "$$(/tmp/test_except_derived_caught_by_base26)" = "$$(printf 'caught1:derived\ncaught2:grandchild\ncaught3:exact\ncaught4-specific:specific\ncaught5:sibling\ndone')"
	./$(COMPILER) test/test_empty_class_shorthand.pas /tmp/test_empty_class_shorthand26
	test "$$(/tmp/test_empty_class_shorthand26)" = "$$(printf 'EBase ok: base error\nEDerived ok: derived error')"
	! ./$(COMPILER) test/test_reraise_error.pas /tmp/test_reraise_error26 > /tmp/test_reraise_error.log 2>&1
	grep -q "raise without expression requires an exception handler" /tmp/test_reraise_error.log
	./$(COMPILER) test/test_exception_unit_unhandled.pas /tmp/test_exception_unit_unhandled26
	! /tmp/test_exception_unit_unhandled26 > /tmp/test_exception_unit_unhandled.out 2> /tmp/test_exception_unit_unhandled.log
	grep -q "Unhandled exception" /tmp/test_exception_unit_unhandled.log
	./$(COMPILER) test/test_exception_unhandled.pas /tmp/test_exception_unhandled26
	! /tmp/test_exception_unhandled26 > /tmp/test_exception_unhandled.out 2> /tmp/test_exception_unhandled.log
	grep -q "Unhandled exception" /tmp/test_exception_unhandled.log
	./$(COMPILER) --threadsafe test/test_multithreading.pas /tmp/test_multithreading26
	/tmp/test_multithreading26 | grep -q "multithreading test completed successfully"
	./$(COMPILER) --threadsafe test/test_threadsafe_layout_rtti.pas /tmp/test_threadsafe_layout_rtti26
	test "$$(/tmp/test_threadsafe_layout_rtti26)" = "threadsafe layout ok"
	test ! -s /tmp/test_exception_unhandled.out
	./$(COMPILER) --no-unhandled-handler test/test_exception_unhandled.pas /tmp/test_exception_silent26
	! /tmp/test_exception_silent26 > /tmp/test_exception_silent.out 2> /tmp/test_exception_silent.log
	test ! -s /tmp/test_exception_silent.log
	./$(COMPILER) -fno-unhandled-handler test/test_exception_unhandled.pas /tmp/test_exception_silent_alias26
	! /tmp/test_exception_silent_alias26 > /tmp/test_exception_silent_alias.out 2> /tmp/test_exception_silent_alias.log
	test ! -s /tmp/test_exception_silent_alias.log
	./$(COMPILER) $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-self
	/tmp/pascal26-self test/hello.pas /tmp/self-hello26
	test "$$(/tmp/self-hello26)" = "Hello, World!"
	/tmp/pascal26-self test/bootstrap_features.pas /tmp/self-bootstrap_features26
	test "$$(/tmp/self-bootstrap_features26)" = "$$(printf '120\n98\ncase-ok\n0')"
	/tmp/pascal26-self test/records.pas /tmp/self-records26
	test "$$(/tmp/self-records26)" = "$$(printf '42\n7\n11\n22')"
	/tmp/pascal26-self test/procs.pas /tmp/self-procs26
	test "$$(/tmp/self-procs26 | tail -9)" = "$$(printf '0\n1\n1\n2\n3\n5\n8\n13\n21')"
	/tmp/pascal26-self test/string_compare.pas /tmp/self-string_compare26
	test "$$(/tmp/self-string_compare26)" = "$$(printf '1\n1\n1')"
	/tmp/pascal26-self test/record_string_field.pas /tmp/self_record_string_field26
	test "$$(/tmp/self_record_string_field26)" = "$$(printf '1\n4')"
	/tmp/pascal26-self test/test_heap.pas /tmp/self-test_heap26
	test "$$(/tmp/self-test_heap26)" = "$$(printf '1\n1\n1\n1\n1\n1')"
	/tmp/pascal26-self --threadsafe test/test_multithreading.pas /tmp/self-test_multithreading26
	/tmp/self-test_multithreading26 | grep -q "multithreading test completed successfully"
	/tmp/pascal26-self test/test_math_unit.pas /tmp/self-test_math_unit26
	test "$$(/tmp/self-test_math_unit26)" = "$$(printf '42\n999\n10\n20\n256\n6\n144')"
	/tmp/pascal26-self test/fileio.pas /tmp/self-fileio26
	test "$$(/tmp/self-fileio26 test/hello.pas | sed -n '1,3p')" = "$$(printf 'test/hello.pas\n14\n54')"
	/tmp/pascal26-self $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-next
	/tmp/pascal26-next test/hello.pas /tmp/next-hello26
	test "$$(/tmp/next-hello26)" = "Hello, World!"
	/tmp/pascal26-next test/bootstrap_features.pas /tmp/next-bootstrap_features26
	test "$$(/tmp/next-bootstrap_features26)" = "$$(printf '120\n98\ncase-ok\n0')"
	/tmp/pascal26-next test/records.pas /tmp/next-records26
	test "$$(/tmp/next-records26)" = "$$(printf '42\n7\n11\n22')"
	/tmp/pascal26-next test/procs.pas /tmp/next-procs26
	test "$$(/tmp/next-procs26 | tail -9)" = "$$(printf '0\n1\n1\n2\n3\n5\n8\n13\n21')"
	/tmp/pascal26-next test/string_compare.pas /tmp/next-string_compare26
	test "$$(/tmp/next-string_compare26)" = "$$(printf '1\n1\n1')"
	/tmp/pascal26-next test/record_string_field.pas /tmp/next_record_string_field26
	test "$$(/tmp/next_record_string_field26)" = "$$(printf '1\n4')"
	/tmp/pascal26-next test/test_heap.pas /tmp/next-test_heap26
	test "$$(/tmp/next-test_heap26)" = "$$(printf '1\n1\n1\n1\n1\n1')"
	/tmp/pascal26-next --threadsafe test/test_multithreading.pas /tmp/next-test_multithreading26
	/tmp/next-test_multithreading26 | grep -q "multithreading test completed successfully"
	/tmp/pascal26-next test/test_math_unit.pas /tmp/next-test_math_unit26
	test "$$(/tmp/next-test_math_unit26)" = "$$(printf '42\n999\n10\n20\n256\n6\n144')"
	/tmp/pascal26-next test/fileio.pas /tmp/next-fileio26
	test "$$(/tmp/next-fileio26 test/hello.pas | sed -n '1,3p')" = "$$(printf 'test/hello.pas\n14\n54')"
	/tmp/pascal26-next $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-fixedpoint
	cmp /tmp/pascal26-next /tmp/pascal26-fixedpoint
	./$(COMPILER) $(PXXFLAGS) --threadsafe $(COMPILER_SRC) /tmp/pascal26-threadsafe-self
	/tmp/pascal26-threadsafe-self $(PXXFLAGS) --threadsafe $(COMPILER_SRC) /tmp/pascal26-threadsafe-next
	cmp /tmp/pascal26-threadsafe-self /tmp/pascal26-threadsafe-next
	@echo "=== progress board check (non-fatal) ==="
	@./tools/progress.sh check || echo "WARNING: progress board stale or invalid — run 'tools/progress.sh board-md' (non-fatal)"

# Validate the devdocs/progress board: stale BOARD.md, dangling Blocked-by slugs,
# dependency cycles, ownerless working/, commit-less done/. Fatal when run
# directly; only advisory inside 'make test' (above).
progress-check:
	@./tools/progress.sh check

# i386 cross-target slice (feature-target-i386). Grows with the backend;
# joins 'make test' when the op coverage is broad enough to matter.
test-i386: $(COMPILER)
	./$(COMPILER) --target=i386 test/hello.pas /tmp/test_i386_hello
	test "$$(tools/run_target.sh i386 /tmp/test_i386_hello)" = "Hello, World!"
	# inline expansion is target-independent (AST/IR level): -O2 output must match
	# -O0 on every cross target (feature-inline-routines).
	./$(COMPILER) --target=i386 test/test_inline_expand.pas /tmp/test_i386_inl_o0
	./$(COMPILER) --target=i386 -O2 test/test_inline_expand.pas /tmp/test_i386_inl_o2
	test "$$(tools/run_target.sh i386 /tmp/test_i386_inl_o0)" = "$$(tools/run_target.sh i386 /tmp/test_i386_inl_o2)"
	# net lib cross matrix: httpdemo builds on i386 (feature-net-lib-cross-target)
	./$(COMPILER) --target=i386 -Fulib/rtl/platform/posix examples/net/httpdemo.pas /tmp/test_i386_httpdemo
	# 32-bit atomic intrinsics on i386 (vs x86-64 golden)
	./$(COMPILER) --target=i386 test/test_atomic_i386.pas /tmp/test_i386_atomic
	./$(COMPILER) test/test_atomic_i386.pas /tmp/test_i386_atomic_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_atomic)" = "$$(/tmp/test_i386_atomic_x64)"
	# i386 --threadsafe: clone trampoline + softlock heap/ARC + TThread (feature-i386-threadsafe-locks)
	./$(COMPILER) --threadsafe --target=i386 test/test_palthread.pas /tmp/test_i386_palthread
	test "$$(tools/run_target.sh i386 /tmp/test_i386_palthread | tail -1)" = "PALTHREAD OK"
	./$(COMPILER) --threadsafe --target=i386 test/test_mutex.pas /tmp/test_i386_mutex
	test "$$(tools/run_target.sh i386 /tmp/test_i386_mutex | tail -1)" = "MUTEX OK"
	./$(COMPILER) --threadsafe --target=i386 test/test_atomic_counter.pas /tmp/test_i386_atomiccnt
	test "$$(tools/run_target.sh i386 /tmp/test_i386_atomiccnt | tail -1)" = "ATOMIC OK"
	./$(COMPILER) --threadsafe --target=i386 test/test_tthread.pas /tmp/test_i386_tthread
	test "$$(tools/run_target.sh i386 /tmp/test_i386_tthread | tail -1)" = "TTHREAD OK"
	./$(COMPILER) --threadsafe --target=i386 test/test_tthread_sync.pas /tmp/test_i386_tthread_sync
	test "$$(tools/run_target.sh i386 /tmp/test_i386_tthread_sync | tail -1)" = "TTHREAD SYNC OK"
	./$(COMPILER) --threadsafe --target=i386 test/test_threadsafe_i386_stress.pas /tmp/test_i386_tsstress
	test "$$(tools/run_target.sh i386 /tmp/test_i386_tsstress | tail -1)" = "HEAPSTRESS386 OK"
	./$(COMPILER) --target=i386 test/test_i386_arith.pas /tmp/test_i386_arith
	./$(COMPILER) test/test_i386_arith.pas /tmp/test_i386_arith_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_arith)" = "$$(/tmp/test_i386_arith_x64)"
	./$(COMPILER) --target=i386 test/test_i386_procs.pas /tmp/test_i386_procs
	./$(COMPILER) test/test_i386_procs.pas /tmp/test_i386_procs_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_procs)" = "$$(/tmp/test_i386_procs_x64)"
	./$(COMPILER) --target=i386 test/test_i386_loops.pas /tmp/test_i386_loops
	./$(COMPILER) test/test_i386_loops.pas /tmp/test_i386_loops_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_loops)" = "$$(/tmp/test_i386_loops_x64)"
	./$(COMPILER) --target=i386 test/test_i386_write.pas /tmp/test_i386_write
	./$(COMPILER) test/test_i386_write.pas /tmp/test_i386_write_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_write)" = "$$(/tmp/test_i386_write_x64)"
	./$(COMPILER) --target=i386 test/test_i386_varparam.pas /tmp/test_i386_varparam
	./$(COMPILER) test/test_i386_varparam.pas /tmp/test_i386_varparam_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_varparam)" = "$$(/tmp/test_i386_varparam_x64)"
	./$(COMPILER) --target=i386 test/test_i386_int64.pas /tmp/test_i386_int64
	./$(COMPILER) test/test_i386_int64.pas /tmp/test_i386_int64_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_int64)" = "$$(/tmp/test_i386_int64_x64)"
	./$(COMPILER) --target=i386 test/test_cross_syscall.pas /tmp/test_i386_syscall
	./$(COMPILER) test/test_cross_syscall.pas /tmp/test_i386_syscall_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_syscall)" = "$$(/tmp/test_i386_syscall_x64)"
	./$(COMPILER) --target=i386 test/test_cross_heap.pas /tmp/test_i386_heap
	./$(COMPILER) test/test_cross_heap.pas /tmp/test_i386_heap_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_heap)" = "$$(/tmp/test_i386_heap_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_cross_string.pas /tmp/test_i386_string
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_string.pas /tmp/test_i386_string_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_string)" = "$$(/tmp/test_i386_string_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_cross_record.pas /tmp/test_i386_record
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_record.pas /tmp/test_i386_record_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_record)" = "$$(/tmp/test_i386_record_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_cross_dynarray.pas /tmp/test_i386_dynarray
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_dynarray.pas /tmp/test_i386_dynarray_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_dynarray)" = "$$(/tmp/test_i386_dynarray_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_nested_dynarray_setlen.pas /tmp/test_i386_nestdynsetlen
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_nested_dynarray_setlen.pas /tmp/test_i386_nestdynsetlen_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_nestdynsetlen)" = "$$(/tmp/test_i386_nestdynsetlen_x64)"
	./$(COMPILER) --target=i386 test/test_cross_exception.pas /tmp/test_i386_exception
	./$(COMPILER) test/test_cross_exception.pas /tmp/test_i386_exception_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_exception)" = "$$(/tmp/test_i386_exception_x64)"
	./$(COMPILER) --target=i386 test/test_ctor_string_literal_arg.pas /tmp/test_i386_ctorstrlit
	test "$$(tools/run_target.sh i386 /tmp/test_i386_ctorstrlit)" = "$$(printf 'field:hello\nc1\nafter1\nc2\nafter2\nc3\nc4\nafter3\nmsg:hello\nafter4')"
	./$(COMPILER) --target=i386 test/test_cross_float.pas /tmp/test_i386_float
	./$(COMPILER) test/test_cross_float.pas /tmp/test_i386_float_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_float)" = "$$(/tmp/test_i386_float_x64)"
	./$(COMPILER) --target=i386 test/test_i386_float_params.pas /tmp/test_i386_float_params
	./$(COMPILER) test/test_i386_float_params.pas /tmp/test_i386_float_params_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_float_params)" = "$$(/tmp/test_i386_float_params_x64)"
	./$(COMPILER) --target=i386 test/test_i386_byvalue_set_param.pas /tmp/test_i386_byvalue_set_param
	./$(COMPILER) test/test_i386_byvalue_set_param.pas /tmp/test_i386_byvalue_set_param_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_byvalue_set_param)" = "$$(/tmp/test_i386_byvalue_set_param_x64)"
	./$(COMPILER) --target=i386 test/test_cross_float_return.pas /tmp/test_i386_fret
	./$(COMPILER) test/test_cross_float_return.pas /tmp/test_i386_fret_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_fret)" = "$$(/tmp/test_i386_fret_x64)"
	./$(COMPILER) --target=i386 test/test_cross_variant.pas /tmp/test_i386_variant
	./$(COMPILER) test/test_cross_variant.pas /tmp/test_i386_variant_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_variant)" = "$$(/tmp/test_i386_variant_x64)"
	./$(COMPILER) --target=i386 test/test_cross_variant_single.pas /tmp/test_i386_variant_single
	./$(COMPILER) test/test_cross_variant_single.pas /tmp/test_i386_variant_single_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_variant_single)" = "$$(/tmp/test_i386_variant_single_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_cross_byref_params.pas /tmp/test_i386_byref
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_byref_params.pas /tmp/test_i386_byref_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_byref)" = "$$(/tmp/test_i386_byref_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_cross_setlen_str.pas /tmp/test_i386_setlen_str
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_setlen_str.pas /tmp/test_i386_setlen_str_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_setlen_str)" = "$$(/tmp/test_i386_setlen_str_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_cross_setlen_varparam.pas /tmp/test_i386_setlen_vp
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_setlen_varparam.pas /tmp/test_i386_setlen_vp_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_setlen_vp)" = "$$(/tmp/test_i386_setlen_vp_x64)"
	./$(COMPILER) --target=i386 test/test_cross_in_operator.pas /tmp/test_i386_in
	./$(COMPILER) test/test_cross_in_operator.pas /tmp/test_i386_in_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_in)" = "$$(/tmp/test_i386_in_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_cross_loadfile.pas /tmp/test_i386_loadfile
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_loadfile.pas /tmp/test_i386_loadfile_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_loadfile)" = "$$(/tmp/test_i386_loadfile_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_cross_sysopen_family.pas /tmp/test_i386_sysopen_family
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_sysopen_family.pas /tmp/test_i386_sysopen_family_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_sysopen_family)" = "$$(/tmp/test_i386_sysopen_family_x64)"
	./$(COMPILER) --target=i386 test/test_arm32_arg_runtime.pas /tmp/test_i386_args
	./$(COMPILER) test/test_arm32_arg_runtime.pas /tmp/test_i386_args_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_args alpha beta)" = "$$(/tmp/test_i386_args_x64 alpha beta)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_cross_string_cow.pas /tmp/test_i386_string_cow
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_string_cow.pas /tmp/test_i386_string_cow_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_string_cow)" = "$$(/tmp/test_i386_string_cow_x64)"
	./$(COMPILER) -uPXX_MANAGED_STRING --target=i386 test/test_cross_frozen_strlen_deref.pas /tmp/test_i386_frozen_strlen
	./$(COMPILER) -uPXX_MANAGED_STRING test/test_cross_frozen_strlen_deref.pas /tmp/test_i386_frozen_strlen_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_frozen_strlen)" = "$$(/tmp/test_i386_frozen_strlen_x64)"
	./$(COMPILER) --target=i386 test/test_managed_strlen_deref.pas /tmp/test_i386_managed_strlen
	./$(COMPILER) test/test_managed_strlen_deref.pas /tmp/test_i386_managed_strlen_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_managed_strlen)" = "$$(/tmp/test_i386_managed_strlen_x64)"
	test "$$(/tmp/test_i386_managed_strlen_x64)" = "$$(printf '5\n5\n5\n2\n2\nOK')"
	./$(COMPILER) --target=i386 test/test_not_int64_expr.pas /tmp/test_i386_not64
	./$(COMPILER) test/test_not_int64_expr.pas /tmp/test_i386_not64_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_not64)" = "$$(/tmp/test_i386_not64_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_cross_record_array_store.pas /tmp/test_i386_rec_arr_store
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_record_array_store.pas /tmp/test_i386_rec_arr_store_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_rec_arr_store)" = "$$(/tmp/test_i386_rec_arr_store_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_array_of_const_types.pas /tmp/test_i386_aoc_types
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_array_of_const_types.pas /tmp/test_i386_aoc_types_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_aoc_types)" = "$$(/tmp/test_i386_aoc_types_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_cross_write_pchar.pas /tmp/test_i386_write_pchar
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_write_pchar.pas /tmp/test_i386_write_pchar_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_write_pchar)" = "$$(/tmp/test_i386_write_pchar_x64)"
	./$(COMPILER) --target=i386 test/test_cross_static_open_array.pas /tmp/test_i386_static_open
	./$(COMPILER) test/test_cross_static_open_array.pas /tmp/test_i386_static_open_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_static_open)" = "$$(/tmp/test_i386_static_open_x64)"
	./$(COMPILER) --target=i386 test/test_cross_many_params.pas /tmp/test_i386_many_params
	./$(COMPILER) test/test_cross_many_params.pas /tmp/test_i386_many_params_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_many_params)" = "$$(/tmp/test_i386_many_params_x64)"
	./$(COMPILER) --target=i386 test/test_conformance_2.pas /tmp/test_i386_conf2
	./$(COMPILER) test/test_conformance_2.pas /tmp/test_i386_conf2_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_conf2)" = "$$(/tmp/test_i386_conf2_x64)"
	./$(COMPILER) --target=i386 test/test_cross_shortcircuit.pas /tmp/test_i386_scx
	./$(COMPILER) test/test_cross_shortcircuit.pas /tmp/test_i386_scx_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_scx)" = "$$(/tmp/test_i386_scx_x64)"
	./$(COMPILER) --target=i386 test/test_cross_ptr_arith.pas /tmp/test_i386_pa
	./$(COMPILER) test/test_cross_ptr_arith.pas /tmp/test_i386_pa_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_pa)" = "$$(/tmp/test_i386_pa_x64)"
	./$(COMPILER) --target=i386 test/test_cross_case_range.pas /tmp/test_i386_cr
	./$(COMPILER) test/test_cross_case_range.pas /tmp/test_i386_cr_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_cr)" = "$$(/tmp/test_i386_cr_x64)"
	./$(COMPILER) --target=i386 test/test_cross_global_init.pas /tmp/test_i386_gi
	./$(COMPILER) test/test_cross_global_init.pas /tmp/test_i386_gi_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_gi)" = "$$(/tmp/test_i386_gi_x64)"
	./$(COMPILER) --target=i386 test/test_cross_typed_const.pas /tmp/test_i386_tc
	./$(COMPILER) test/test_cross_typed_const.pas /tmp/test_i386_tc_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_tc)" = "$$(/tmp/test_i386_tc_x64)"
	./$(COMPILER) --target=i386 test/test_cross_multidim.pas /tmp/test_i386_md
	./$(COMPILER) test/test_cross_multidim.pas /tmp/test_i386_md_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_md)" = "$$(/tmp/test_i386_md_x64)"
	./$(COMPILER) --target=i386 test/test_cross_named_array.pas /tmp/test_i386_na
	./$(COMPILER) test/test_cross_named_array.pas /tmp/test_i386_na_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_na)" = "$$(/tmp/test_i386_na_x64)"
	./$(COMPILER) --target=i386 test/test_cross_record_2darray.pas /tmp/test_i386_r2
	./$(COMPILER) test/test_cross_record_2darray.pas /tmp/test_i386_r2_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_r2)" = "$$(/tmp/test_i386_r2_x64)"
	./$(COMPILER) --target=i386 test/test_cross_param_2darray.pas /tmp/test_i386_pa2
	./$(COMPILER) test/test_cross_param_2darray.pas /tmp/test_i386_pa2_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_pa2)" = "$$(/tmp/test_i386_pa2_x64)"
	./$(COMPILER) --target=i386 test/test_cross_multidim3d.pas /tmp/test_i386_d3
	./$(COMPILER) test/test_cross_multidim3d.pas /tmp/test_i386_d3_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_d3)" = "$$(/tmp/test_i386_d3_x64)"
	./$(COMPILER) --target=i386 test/test_cross_const_alias.pas /tmp/test_i386_ca
	./$(COMPILER) test/test_cross_const_alias.pas /tmp/test_i386_ca_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_ca)" = "$$(/tmp/test_i386_ca_x64)"
	./$(COMPILER) --target=i386 test/test_cross_float_const.pas /tmp/test_i386_fc
	./$(COMPILER) test/test_cross_float_const.pas /tmp/test_i386_fc_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_fc)" = "$$(/tmp/test_i386_fc_x64)"
	./$(COMPILER) --target=i386 test/test_stackless_gen.pas /tmp/test_i386_slg
	./$(COMPILER) test/test_stackless_gen.pas /tmp/test_i386_slg_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_slg)" = "$$(/tmp/test_i386_slg_x64)"
	./$(COMPILER) --target=i386 test/test_async_sl.pas /tmp/test_i386_asl
	./$(COMPILER) test/test_async_sl.pas /tmp/test_i386_asl_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_asl)" = "$$(/tmp/test_i386_asl_x64)"
	./$(COMPILER) --target=i386 test/test_proctype.pas /tmp/test_i386_proctype
	./$(COMPILER) test/test_proctype.pas /tmp/test_i386_proctype_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_proctype)" = "$$(/tmp/test_i386_proctype_x64)"
	./$(COMPILER) --target=i386 test/test_scheduler.pas /tmp/test_i386_sched
	./$(COMPILER) test/test_scheduler.pas /tmp/test_i386_sched_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_sched)" = "$$(/tmp/test_i386_sched_x64)"
	./$(COMPILER) --target=i386 test/test_scheduler_exc.pas /tmp/test_i386_sexc
	./$(COMPILER) test/test_scheduler_exc.pas /tmp/test_i386_sexc_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_sexc)" = "$$(/tmp/test_i386_sexc_x64)"
	./$(COMPILER) --target=i386 test/test_channel.pas /tmp/test_i386_chan
	./$(COMPILER) test/test_channel.pas /tmp/test_i386_chan_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_chan)" = "$$(/tmp/test_i386_chan_x64)"
	./$(COMPILER) --target=i386 test/test_methodptr.pas /tmp/test_i386_mptr
	./$(COMPILER) test/test_methodptr.pas /tmp/test_i386_mptr_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_mptr)" = "$$(/tmp/test_i386_mptr_x64)"
	./$(COMPILER) --target=i386 test/test_methcall.pas /tmp/test_i386_mcall
	./$(COMPILER) test/test_methcall.pas /tmp/test_i386_mcall_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_mcall)" = "$$(/tmp/test_i386_mcall_x64)"
	./$(COMPILER) --target=i386 test/test_cross_sets.pas /tmp/test_i386_sets
	./$(COMPILER) test/test_cross_sets.pas /tmp/test_i386_sets_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_sets)" = "$$(/tmp/test_i386_sets_x64)"
	./$(COMPILER) --target=i386 test/test_classref.pas /tmp/test_i386_classref
	./$(COMPILER) test/test_classref.pas /tmp/test_i386_classref_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_classref)" = "$$(/tmp/test_i386_classref_x64)"
	./$(COMPILER) --target=i386 test/test_class_of.pas /tmp/test_i386_classof
	./$(COMPILER) test/test_class_of.pas /tmp/test_i386_classof_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_classof)" = "$$(/tmp/test_i386_classof_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_rtti.pas /tmp/test_i386_rtti
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_rtti.pas /tmp/test_i386_rtti_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_rtti | grep -vE 'pointer:|RTTI value:|InstanceSize:')" = "$$(/tmp/test_i386_rtti_x64 | grep -vE 'pointer:|RTTI value:|InstanceSize:')"
	./$(COMPILER) --target=i386 test/test_streaming.pas /tmp/test_i386_streaming
	./$(COMPILER) test/test_streaming.pas /tmp/test_i386_streaming_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_streaming)" = "$$(/tmp/test_i386_streaming_x64)"
	./$(COMPILER) --target=i386 test/test_streaming_enumset.pas /tmp/test_i386_streaming_enumset
	./$(COMPILER) test/test_streaming_enumset.pas /tmp/test_i386_streaming_enumset_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_streaming_enumset)" = "$$(/tmp/test_i386_streaming_enumset_x64)"
	./$(COMPILER) --target=i386 test/test_lfm.pas /tmp/test_i386_lfm
	./$(COMPILER) test/test_lfm.pas /tmp/test_i386_lfm_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_lfm)" = "$$(/tmp/test_i386_lfm_x64)"
	./$(COMPILER) --target=i386 test/test_interfaces.pas /tmp/test_i386_iface
	./$(COMPILER) test/test_interfaces.pas /tmp/test_i386_iface_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_iface)" = "$$(/tmp/test_i386_iface_x64)"
	./$(COMPILER) --target=i386 test/test_interface_arc.pas /tmp/test_i386_iarc
	./$(COMPILER) test/test_interface_arc.pas /tmp/test_i386_iarc_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_iarc)" = "$$(/tmp/test_i386_iarc_x64)"
	./$(COMPILER) --target=i386 test/test_uint64_ops.pas /tmp/test_i386_u64
	./$(COMPILER) test/test_uint64_ops.pas /tmp/test_i386_u64_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_u64)" = "$$(/tmp/test_i386_u64_x64)"
	./$(COMPILER) --target=i386 test/test_interfaces_is.pas /tmp/test_i386_iface_is
	./$(COMPILER) test/test_interfaces_is.pas /tmp/test_i386_iface_is_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_iface_is)" = "$$(/tmp/test_i386_iface_is_x64)"
	./$(COMPILER) --target=i386 test/test_interfaces_as.pas /tmp/test_i386_iface_as
	./$(COMPILER) test/test_interfaces_as.pas /tmp/test_i386_iface_as_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_iface_as)" = "$$(/tmp/test_i386_iface_as_x64)"
	./$(COMPILER) --target=i386 test/test_interfaces_param.pas /tmp/test_i386_iface_param
	./$(COMPILER) test/test_interfaces_param.pas /tmp/test_i386_iface_param_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_iface_param)" = "$$(/tmp/test_i386_iface_param_x64)"
	./$(COMPILER) --target=i386 test/test_interfaces_inherit.pas /tmp/test_i386_iface_inh
	./$(COMPILER) test/test_interfaces_inherit.pas /tmp/test_i386_iface_inh_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_iface_inh)" = "$$(/tmp/test_i386_iface_inh_x64)"
	./$(COMPILER) --target=i386 test/test_interfaces_multi_secondary.pas /tmp/test_i386_iface_multi
	./$(COMPILER) test/test_interfaces_multi_secondary.pas /tmp/test_i386_iface_multi_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_iface_multi)" = "$$(/tmp/test_i386_iface_multi_x64)"
	./$(COMPILER) --target=i386 test/test_cross_aggregate_return.pas /tmp/test_i386_aggret
	./$(COMPILER) test/test_cross_aggregate_return.pas /tmp/test_i386_aggret_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_aggret)" = "$$(/tmp/test_i386_aggret_x64)"
	# aggregate / frozen-string result via a VIRTUAL and an INDIRECT call
	# (feature-cross-virtual-indirect-hidden-dest)
	./$(COMPILER) --target=i386 test/test_cross_virtual_indirect_aggret.pas /tmp/test_i386_vindaggret
	./$(COMPILER) test/test_cross_virtual_indirect_aggret.pas /tmp/test_i386_vindaggret_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_vindaggret)" = "$$(/tmp/test_i386_vindaggret_x64)"
	./$(COMPILER) --target=i386 test/test_inheritance_dispatch.pas /tmp/test_i386_cls
	./$(COMPILER) test/test_inheritance_dispatch.pas /tmp/test_i386_cls_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_cls)" = "$$(/tmp/test_i386_cls_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_dynarray_field.pas /tmp/test_i386_dynfield
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_dynarray_field.pas /tmp/test_i386_dynfield_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_dynfield)" = "$$(/tmp/test_i386_dynfield_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_method_implicit_field.pas /tmp/test_i386_mif
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_method_implicit_field.pas /tmp/test_i386_mif_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_mif)" = "$$(/tmp/test_i386_mif_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_forin_implicit_field.pas /tmp/test_i386_fif
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_forin_implicit_field.pas /tmp/test_i386_fif_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_fif)" = "$$(/tmp/test_i386_fif_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_dynarray_global_after_method.pas /tmp/test_i386_dgam
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_dynarray_global_after_method.pas /tmp/test_i386_dgam_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_dgam)" = "$$(/tmp/test_i386_dgam_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_forin_member_access.pas /tmp/test_i386_fima
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_forin_member_access.pas /tmp/test_i386_fima_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_fima)" = "$$(/tmp/test_i386_fima_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_call_result_member.pas /tmp/test_i386_crm
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_call_result_member.pas /tmp/test_i386_crm_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_crm)" = "$$(/tmp/test_i386_crm_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_collections.pas /tmp/test_i386_collections
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_collections.pas /tmp/test_i386_collections_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_collections)" = "$$(/tmp/test_i386_collections_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_const_record_temp.pas /tmp/test_i386_constrectemp
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_const_record_temp.pas /tmp/test_i386_constrectemp_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_constrectemp)" = "$$(/tmp/test_i386_constrectemp_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_const_record_temp_managed.pas /tmp/test_i386_constrectemp_managed
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_const_record_temp_managed.pas /tmp/test_i386_constrectemp_managed_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_constrectemp_managed)" = "$$(/tmp/test_i386_constrectemp_managed_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_set_runtime.pas /tmp/test_i386_setrt
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_set_runtime.pas /tmp/test_i386_setrt_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_setrt)" = "$$(/tmp/test_i386_setrt_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_managed_record_temp_init.pas /tmp/test_i386_mrti
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_managed_record_temp_init.pas /tmp/test_i386_mrti_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_mrti)" = "$$(/tmp/test_i386_mrti_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=i386 test/test_dynarray_copy.pas /tmp/test_i386_dyncopy
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_dynarray_copy.pas /tmp/test_i386_dyncopy_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_dyncopy)" = "$$(/tmp/test_i386_dyncopy_x64)"
	./$(COMPILER) --target=i386 test/test_timer.pas /tmp/test_i386_timer
	test "$$(tools/run_target.sh i386 /tmp/test_i386_timer)" = "$$(printf 'woke 50\nwoke 100\nwoke 150\ndone')"
	./$(COMPILER) --target=i386 test/test_reactor.pas /tmp/test_i386_reactor
	test "$$(tools/run_target.sh i386 /tmp/test_i386_reactor)" = "$$(printf 'reader: start\nreader: would-block, parking\nwriter: writing\nreader: got 2 bytes: hi\ndone')"
	./$(COMPILER) --target=i386 -Fulib/rtl/platform/posix test/test_asyncecho.pas /tmp/test_i386_asyncecho
	test "$$(tools/run_target.sh i386 /tmp/test_i386_asyncecho)" = "$$(printf 'client 1 ok\nclient 2 ok\ndone')"
	./$(COMPILER) --target=i386 test/test_extern_c.pas /tmp/test_i386_extern
	./$(COMPILER) test/test_extern_c.pas /tmp/test_i386_extern_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_extern)" = "$$(/tmp/test_i386_extern_x64)"
	./$(COMPILER) --target=i386 test/test_extern_c_float.pas /tmp/test_i386_extern_float
	./$(COMPILER) test/test_extern_c_float.pas /tmp/test_i386_extern_float_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_extern_float)" = "$$(/tmp/test_i386_extern_float_x64)"
	./$(COMPILER) --target=i386 test/ccross_entry.c /tmp/test_i386_centry
	tools/run_target.sh i386 /tmp/test_i386_centry; test "$$?" = "42"
	./$(COMPILER) --target=i386 test/ccross_args.c /tmp/test_i386_cargs
	tools/run_target.sh i386 /tmp/test_i386_cargs; test "$$?" = "42"
	./$(COMPILER) --target=i386 test/ccross_double_to_int.c /tmp/test_i386_cd2i
	tools/run_target.sh i386 /tmp/test_i386_cd2i; test "$$?" = "42"
	./$(COMPILER) --target=i386 test/test_readln.pas /tmp/test_i386_readln
	./$(COMPILER) test/test_readln.pas /tmp/test_i386_readln_x64
	test "$$(printf '100 200 300\n42\n10 20\nhello world\nQ\nSKIP\n-5\n' | tools/run_target.sh i386 /tmp/test_i386_readln)" = "$$(printf '100 200 300\n42\n10 20\nhello world\nQ\nSKIP\n-5\n' | /tmp/test_i386_readln_x64)"
	./$(COMPILER) --target=i386 test/test_eof_stdin.pas /tmp/test_i386_eof
	./$(COMPILER) test/test_eof_stdin.pas /tmp/test_i386_eof_x64
	test "$$(printf 'alpha\nbeta\ngamma' | tools/run_target.sh i386 /tmp/test_i386_eof)" = "$$(printf 'alpha\nbeta\ngamma' | /tmp/test_i386_eof_x64)"
	./$(COMPILER) --target=i386 test/cunsigned_int_arith_b121.c /tmp/test_i386_cuarith
	tools/run_target.sh i386 /tmp/test_i386_cuarith; test "$$?" = "42"
	./$(COMPILER) --target=i386 test/cunsigned_semantics_sweep_b138.c /tmp/test_i386_cusweep
	tools/run_target.sh i386 /tmp/test_i386_cusweep; test "$$?" = "42"
	./$(COMPILER) --target=i386 test/cunsigned_div_mod_b123.c /tmp/test_i386_cudiv
	tools/run_target.sh i386 /tmp/test_i386_cudiv; test "$$?" = "42"
	# inline asm on i386: locals/params via [ebp±off] substitution, labels+jcc, mov/@glob global access
	./$(COMPILER) --target=i386 test/test_asm_386.pas /tmp/test_i386_asm
	test "$$(tools/run_target.sh i386 /tmp/test_i386_asm)" = "$$(printf '42\n55\n42')"
	# .asm source frontend on i386: labels/branches + global entry override, exit code = ebx
	./$(COMPILER) --target=i386 test/test_asm_386_sum.asm /tmp/test_i386_asmfront
	tools/run_target.sh i386 /tmp/test_i386_asmfront; test "$$?" = "55"
	@echo "i386 hello + arith + procs + loops + write + varparam + syscall + heap + string + record + dynarray + exception + float + float-params + variant + variant-single + byref-params + setlen-str + setlen-varparam + in-operator + loadfile + sysopen-family + args + string-cow + frozen-strlen-deref + rec-arr-store + aoc-types + many-params + conformance2 + shortcircuit + ptr-arith + case-range + global-init + typed-const + multidim + named-array + record-2darray + param-2darray + multidim3d + const-alias + float-const + stackless-generator + proctype + scheduler + scheduler-exc + classes + method-pointers + aggregate-return + metaclass-rtti + rtti-typinfo + streaming + streaming-enumset + lfm + interfaces + dynarray-field + nested-dynarray-setlen + method-implicit-field + forin-implicit-field + dynarray-global-after-method + forin-member-access + call-result-member + collections + timer + reactor + asyncecho + extern-c + extern-c-float + c-entry + c-args + c-double-to-int + readln + eof-stdin ok (output identical to x86-64)"

test-aarch64: $(COMPILER)
	./$(COMPILER) --target=aarch64 test/hello.pas /tmp/test_aarch64_hello
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_hello)" = "Hello, World!"
	# inline expansion (feature-inline-routines): -O2 == -O0 on this cross target.
	./$(COMPILER) --target=aarch64 test/test_inline_expand.pas /tmp/test_aarch64_inl_o0
	./$(COMPILER) --target=aarch64 -O2 test/test_inline_expand.pas /tmp/test_aarch64_inl_o2
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_inl_o0)" = "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_inl_o2)"
	./$(COMPILER) --target=aarch64 test/test_record_temp_byval_arg.pas /tmp/test_aarch64_rectemp
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_rectemp)" = "$$(printf '18\n46')"
	./$(COMPILER) --target=aarch64 test/test_ctor_string_literal_arg.pas /tmp/test_aarch64_ctorstrlit
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_ctorstrlit)" = "$$(printf 'field:hello\nc1\nafter1\nc2\nafter2\nc3\nc4\nafter3\nmsg:hello\nafter4')"
	./$(COMPILER) --target=aarch64 test/test_arm32_record_byval_wide.pas /tmp/test_aarch64_recwide
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_recwide)" = "$$(printf '1 2\n1 2\n111 222\n1 7 8 2\n1 2 3 4 7 8\n1 2 3 7 8\n1 2 3 4 5 7 8\n200 7\ndone')"
	./$(COMPILER) --target=aarch64 test/test_single_in_aggregate.pas /tmp/test_aarch64_singleagg
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_singleagg)" = "$$(printf '1.5 2.5 3.5\n9.500 8.250 7.125\n2.0 4.0 6.0\n10.0')"
	./$(COMPILER) --target=aarch64 test/test_i386_arith.pas /tmp/test_aarch64_arith
	./$(COMPILER) test/test_i386_arith.pas /tmp/test_aarch64_arith_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_arith)" = "$$(/tmp/test_aarch64_arith_x64)"
	./$(COMPILER) --target=aarch64 test/test_i386_procs.pas /tmp/test_aarch64_procs
	./$(COMPILER) test/test_i386_procs.pas /tmp/test_aarch64_procs_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_procs)" = "$$(/tmp/test_aarch64_procs_x64)"
	./$(COMPILER) --target=aarch64 test/test_i386_loops.pas /tmp/test_aarch64_loops
	./$(COMPILER) test/test_i386_loops.pas /tmp/test_aarch64_loops_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_loops)" = "$$(/tmp/test_aarch64_loops_x64)"
	./$(COMPILER) --target=aarch64 test/test_i386_write.pas /tmp/test_aarch64_write
	./$(COMPILER) test/test_i386_write.pas /tmp/test_aarch64_write_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_write)" = "$$(/tmp/test_aarch64_write_x64)"
	./$(COMPILER) --target=aarch64 test/test_i386_varparam.pas /tmp/test_aarch64_varparam
	./$(COMPILER) test/test_i386_varparam.pas /tmp/test_aarch64_varparam_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_varparam)" = "$$(/tmp/test_aarch64_varparam_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_syscall.pas /tmp/test_aarch64_syscall
	./$(COMPILER) test/test_cross_syscall.pas /tmp/test_aarch64_syscall_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_syscall)" = "$$(/tmp/test_aarch64_syscall_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_heap.pas /tmp/test_aarch64_heap
	./$(COMPILER) test/test_cross_heap.pas /tmp/test_aarch64_heap_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_heap)" = "$$(/tmp/test_aarch64_heap_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_cross_managed_a64.pas /tmp/test_aarch64_managed
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_managed_a64.pas /tmp/test_aarch64_managed_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_managed)" = "$$(/tmp/test_aarch64_managed_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_exception.pas /tmp/test_aarch64_exception
	./$(COMPILER) test/test_cross_exception.pas /tmp/test_aarch64_exception_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_exception)" = "$$(/tmp/test_aarch64_exception_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_float.pas /tmp/test_aarch64_float
	./$(COMPILER) test/test_cross_float.pas /tmp/test_aarch64_float_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_float)" = "$$(/tmp/test_aarch64_float_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_float_return.pas /tmp/test_aarch64_fret
	./$(COMPILER) test/test_cross_float_return.pas /tmp/test_aarch64_fret_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_fret)" = "$$(/tmp/test_aarch64_fret_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_variant.pas /tmp/test_aarch64_variant
	./$(COMPILER) test/test_cross_variant.pas /tmp/test_aarch64_variant_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_variant)" = "$$(/tmp/test_aarch64_variant_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_variant_single.pas /tmp/test_aarch64_variant_single
	./$(COMPILER) test/test_cross_variant_single.pas /tmp/test_aarch64_variant_single_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_variant_single)" = "$$(/tmp/test_aarch64_variant_single_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_cross_setlen_str.pas /tmp/test_aarch64_setlen_str
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_setlen_str.pas /tmp/test_aarch64_setlen_str_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_setlen_str)" = "$$(/tmp/test_aarch64_setlen_str_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_cross_setlen_varparam.pas /tmp/test_aarch64_setlen_vp
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_setlen_varparam.pas /tmp/test_aarch64_setlen_vp_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_setlen_vp)" = "$$(/tmp/test_aarch64_setlen_vp_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_cross_str_length_index.pas /tmp/test_aarch64_str_length_index
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_str_length_index.pas /tmp/test_aarch64_str_length_index_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_str_length_index)" = "$$(/tmp/test_aarch64_str_length_index_x64)"
	./$(COMPILER) --target=aarch64 test/test_managed_strlen_deref.pas /tmp/test_aarch64_managed_strlen
	./$(COMPILER) test/test_managed_strlen_deref.pas /tmp/test_aarch64_managed_strlen_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_managed_strlen)" = "$$(/tmp/test_aarch64_managed_strlen_x64)"
	./$(COMPILER) --target=aarch64 test/test_not_int64_expr.pas /tmp/test_aarch64_not64
	./$(COMPILER) test/test_not_int64_expr.pas /tmp/test_aarch64_not64_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_not64)" = "$$(/tmp/test_aarch64_not64_x64)"
	./$(COMPILER) -uPXX_MANAGED_STRING --target=aarch64 test/test_cross_frozen_strlen_deref.pas /tmp/test_aarch64_frozen_strlen
	./$(COMPILER) -uPXX_MANAGED_STRING test/test_cross_frozen_strlen_deref.pas /tmp/test_aarch64_frozen_strlen_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_frozen_strlen)" = "$$(/tmp/test_aarch64_frozen_strlen_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_cross_record_array_store.pas /tmp/test_aarch64_rec_arr_store
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_record_array_store.pas /tmp/test_aarch64_rec_arr_store_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_rec_arr_store)" = "$$(/tmp/test_aarch64_rec_arr_store_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_in_operator.pas /tmp/test_aarch64_in
	./$(COMPILER) test/test_cross_in_operator.pas /tmp/test_aarch64_in_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_in)" = "$$(/tmp/test_aarch64_in_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_cross_loadfile.pas /tmp/test_aarch64_loadfile
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_loadfile.pas /tmp/test_aarch64_loadfile_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_loadfile)" = "$$(/tmp/test_aarch64_loadfile_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_cross_sysopen_family.pas /tmp/test_aarch64_sysopen_family
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_sysopen_family.pas /tmp/test_aarch64_sysopen_family_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_sysopen_family)" = "$$(/tmp/test_aarch64_sysopen_family_x64)"
	./$(COMPILER) --target=aarch64 test/test_arm32_arg_runtime.pas /tmp/test_aarch64_args
	./$(COMPILER) test/test_arm32_arg_runtime.pas /tmp/test_aarch64_args_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_args alpha beta)" = "$$(/tmp/test_aarch64_args_x64 alpha beta)"
	./$(COMPILER) --target=aarch64 test/test_cross_open_array_params.pas /tmp/test_aarch64_open_array_params
	./$(COMPILER) test/test_cross_open_array_params.pas /tmp/test_aarch64_open_array_params_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_open_array_params)" = "$$(/tmp/test_aarch64_open_array_params_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_cross_string_cow.pas /tmp/test_aarch64_string_cow
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_string_cow.pas /tmp/test_aarch64_string_cow_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_string_cow)" = "$$(/tmp/test_aarch64_string_cow_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_huge_frame.pas /tmp/test_aarch64_huge_frame
	./$(COMPILER) test/test_cross_huge_frame.pas /tmp/test_aarch64_huge_frame_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_huge_frame)" = "$$(/tmp/test_aarch64_huge_frame_x64)"
	./$(COMPILER) --target=aarch64 test/test_varrec_alloc_after.pas /tmp/test_aarch64_varrec_alloc
	./$(COMPILER) test/test_varrec_alloc_after.pas /tmp/test_aarch64_varrec_alloc_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_varrec_alloc)" = "$$(/tmp/test_aarch64_varrec_alloc_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_array_of_const_types.pas /tmp/test_aarch64_aoc_types
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_array_of_const_types.pas /tmp/test_aarch64_aoc_types_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_aoc_types)" = "$$(/tmp/test_aarch64_aoc_types_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_cross_write_pchar.pas /tmp/test_aarch64_write_pchar
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_write_pchar.pas /tmp/test_aarch64_write_pchar_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_write_pchar)" = "$$(/tmp/test_aarch64_write_pchar_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_static_open_array.pas /tmp/test_aarch64_static_open
	./$(COMPILER) test/test_cross_static_open_array.pas /tmp/test_aarch64_static_open_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_static_open)" = "$$(/tmp/test_aarch64_static_open_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_many_params.pas /tmp/test_aarch64_many_params
	./$(COMPILER) test/test_cross_many_params.pas /tmp/test_aarch64_many_params_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_many_params)" = "$$(/tmp/test_aarch64_many_params_x64)"
	./$(COMPILER) --target=aarch64 test/test_conformance_2.pas /tmp/test_aarch64_conf2
	./$(COMPILER) test/test_conformance_2.pas /tmp/test_aarch64_conf2_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_conf2)" = "$$(/tmp/test_aarch64_conf2_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_shortcircuit.pas /tmp/test_aarch64_scx
	./$(COMPILER) test/test_cross_shortcircuit.pas /tmp/test_aarch64_scx_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_scx)" = "$$(/tmp/test_aarch64_scx_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_ptr_arith.pas /tmp/test_aarch64_pa
	./$(COMPILER) test/test_cross_ptr_arith.pas /tmp/test_aarch64_pa_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_pa)" = "$$(/tmp/test_aarch64_pa_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_case_range.pas /tmp/test_aarch64_cr
	./$(COMPILER) test/test_cross_case_range.pas /tmp/test_aarch64_cr_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_cr)" = "$$(/tmp/test_aarch64_cr_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_global_init.pas /tmp/test_aarch64_gi
	./$(COMPILER) test/test_cross_global_init.pas /tmp/test_aarch64_gi_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_gi)" = "$$(/tmp/test_aarch64_gi_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_typed_const.pas /tmp/test_aarch64_tc
	./$(COMPILER) test/test_cross_typed_const.pas /tmp/test_aarch64_tc_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_tc)" = "$$(/tmp/test_aarch64_tc_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_multidim.pas /tmp/test_aarch64_md
	./$(COMPILER) test/test_cross_multidim.pas /tmp/test_aarch64_md_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_md)" = "$$(/tmp/test_aarch64_md_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_named_array.pas /tmp/test_aarch64_na
	./$(COMPILER) test/test_cross_named_array.pas /tmp/test_aarch64_na_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_na)" = "$$(/tmp/test_aarch64_na_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_record_2darray.pas /tmp/test_aarch64_r2
	./$(COMPILER) test/test_cross_record_2darray.pas /tmp/test_aarch64_r2_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_r2)" = "$$(/tmp/test_aarch64_r2_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_param_2darray.pas /tmp/test_aarch64_pa2
	./$(COMPILER) test/test_cross_param_2darray.pas /tmp/test_aarch64_pa2_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_pa2)" = "$$(/tmp/test_aarch64_pa2_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_multidim3d.pas /tmp/test_aarch64_d3
	./$(COMPILER) test/test_cross_multidim3d.pas /tmp/test_aarch64_d3_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_d3)" = "$$(/tmp/test_aarch64_d3_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_const_alias.pas /tmp/test_aarch64_ca
	./$(COMPILER) test/test_cross_const_alias.pas /tmp/test_aarch64_ca_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_ca)" = "$$(/tmp/test_aarch64_ca_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_float_const.pas /tmp/test_aarch64_fc
	./$(COMPILER) test/test_cross_float_const.pas /tmp/test_aarch64_fc_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_fc)" = "$$(/tmp/test_aarch64_fc_x64)"
	./$(COMPILER) --target=aarch64 test/test_scheduler.pas /tmp/test_aarch64_sched
	./$(COMPILER) test/test_scheduler.pas /tmp/test_aarch64_sched_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_sched)" = "$$(/tmp/test_aarch64_sched_x64)"
	./$(COMPILER) --target=aarch64 test/test_scheduler_exc.pas /tmp/test_aarch64_sexc
	./$(COMPILER) test/test_scheduler_exc.pas /tmp/test_aarch64_sexc_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_sexc)" = "$$(/tmp/test_aarch64_sexc_x64)"
	./$(COMPILER) --target=aarch64 test/test_channel.pas /tmp/test_aarch64_chan
	./$(COMPILER) test/test_channel.pas /tmp/test_aarch64_chan_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_chan)" = "$$(/tmp/test_aarch64_chan_x64)"
	./$(COMPILER) --target=aarch64 test/test_async_sl.pas /tmp/test_aarch64_asl
	./$(COMPILER) test/test_async_sl.pas /tmp/test_aarch64_asl_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_asl)" = "$$(/tmp/test_aarch64_asl_x64)"
	./$(COMPILER) --target=aarch64 test/test_methodptr.pas /tmp/test_aarch64_mptr
	./$(COMPILER) test/test_methodptr.pas /tmp/test_aarch64_mptr_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_mptr)" = "$$(/tmp/test_aarch64_mptr_x64)"
	./$(COMPILER) --target=aarch64 test/test_methcall.pas /tmp/test_aarch64_mcall
	./$(COMPILER) test/test_methcall.pas /tmp/test_aarch64_mcall_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_mcall)" = "$$(/tmp/test_aarch64_mcall_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_sets.pas /tmp/test_aarch64_sets
	./$(COMPILER) test/test_cross_sets.pas /tmp/test_aarch64_sets_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_sets)" = "$$(/tmp/test_aarch64_sets_x64)"
	./$(COMPILER) --target=aarch64 test/test_classref.pas /tmp/test_aarch64_classref
	./$(COMPILER) test/test_classref.pas /tmp/test_aarch64_classref_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_classref)" = "$$(/tmp/test_aarch64_classref_x64)"
	./$(COMPILER) --target=aarch64 test/test_class_of.pas /tmp/test_aarch64_classof
	./$(COMPILER) test/test_class_of.pas /tmp/test_aarch64_classof_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_classof)" = "$$(/tmp/test_aarch64_classof_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_rtti.pas /tmp/test_aarch64_rtti
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_rtti.pas /tmp/test_aarch64_rtti_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_rtti | grep -vE 'pointer:|RTTI value:|InstanceSize:')" = "$$(/tmp/test_aarch64_rtti_x64 | grep -vE 'pointer:|RTTI value:|InstanceSize:')"
	./$(COMPILER) --target=aarch64 test/test_streaming.pas /tmp/test_aarch64_streaming
	./$(COMPILER) test/test_streaming.pas /tmp/test_aarch64_streaming_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_streaming)" = "$$(/tmp/test_aarch64_streaming_x64)"
	./$(COMPILER) --target=aarch64 test/test_streaming_enumset.pas /tmp/test_aarch64_streaming_enumset
	./$(COMPILER) test/test_streaming_enumset.pas /tmp/test_aarch64_streaming_enumset_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_streaming_enumset)" = "$$(/tmp/test_aarch64_streaming_enumset_x64)"
	./$(COMPILER) --target=aarch64 test/test_lfm.pas /tmp/test_aarch64_lfm
	./$(COMPILER) test/test_lfm.pas /tmp/test_aarch64_lfm_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_lfm)" = "$$(/tmp/test_aarch64_lfm_x64)"
	./$(COMPILER) --target=aarch64 test/test_interfaces.pas /tmp/test_aarch64_iface
	./$(COMPILER) test/test_interfaces.pas /tmp/test_aarch64_iface_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_iface)" = "$$(/tmp/test_aarch64_iface_x64)"
	./$(COMPILER) --target=aarch64 test/test_interface_arc.pas /tmp/test_aarch64_iarc
	./$(COMPILER) test/test_interface_arc.pas /tmp/test_aarch64_iarc_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_iarc)" = "$$(/tmp/test_aarch64_iarc_x64)"
	./$(COMPILER) --target=aarch64 test/test_uint64_ops.pas /tmp/test_aarch64_u64
	./$(COMPILER) test/test_uint64_ops.pas /tmp/test_aarch64_u64_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_u64)" = "$$(/tmp/test_aarch64_u64_x64)"
	./$(COMPILER) --target=aarch64 test/test_interfaces_is.pas /tmp/test_aarch64_iface_is
	./$(COMPILER) test/test_interfaces_is.pas /tmp/test_aarch64_iface_is_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_iface_is)" = "$$(/tmp/test_aarch64_iface_is_x64)"
	./$(COMPILER) --target=aarch64 test/test_interfaces_as.pas /tmp/test_aarch64_iface_as
	./$(COMPILER) test/test_interfaces_as.pas /tmp/test_aarch64_iface_as_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_iface_as)" = "$$(/tmp/test_aarch64_iface_as_x64)"
	./$(COMPILER) --target=aarch64 test/test_interfaces_param.pas /tmp/test_aarch64_iface_param
	./$(COMPILER) test/test_interfaces_param.pas /tmp/test_aarch64_iface_param_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_iface_param)" = "$$(/tmp/test_aarch64_iface_param_x64)"
	./$(COMPILER) --target=aarch64 test/test_interfaces_inherit.pas /tmp/test_aarch64_iface_inh
	./$(COMPILER) test/test_interfaces_inherit.pas /tmp/test_aarch64_iface_inh_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_iface_inh)" = "$$(/tmp/test_aarch64_iface_inh_x64)"
	./$(COMPILER) --target=aarch64 test/test_interfaces_multi_secondary.pas /tmp/test_aarch64_iface_multi
	./$(COMPILER) test/test_interfaces_multi_secondary.pas /tmp/test_aarch64_iface_multi_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_iface_multi)" = "$$(/tmp/test_aarch64_iface_multi_x64)"
	./$(COMPILER) --target=aarch64 test/test_cross_aggregate_return.pas /tmp/test_aarch64_aggret
	./$(COMPILER) test/test_cross_aggregate_return.pas /tmp/test_aarch64_aggret_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_aggret)" = "$$(/tmp/test_aarch64_aggret_x64)"
	# aggregate / frozen-string result via a VIRTUAL and an INDIRECT call
	# (feature-cross-virtual-indirect-hidden-dest)
	./$(COMPILER) --target=aarch64 test/test_cross_virtual_indirect_aggret.pas /tmp/test_aarch64_vindaggret
	./$(COMPILER) test/test_cross_virtual_indirect_aggret.pas /tmp/test_aarch64_vindaggret_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_vindaggret)" = "$$(/tmp/test_aarch64_vindaggret_x64)"
	./$(COMPILER) --target=aarch64 test/test_inheritance_dispatch.pas /tmp/test_aarch64_cls
	./$(COMPILER) test/test_inheritance_dispatch.pas /tmp/test_aarch64_cls_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_cls)" = "$$(/tmp/test_aarch64_cls_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_dynarray_field.pas /tmp/test_aarch64_dynfield
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_dynarray_field.pas /tmp/test_aarch64_dynfield_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_dynfield)" = "$$(/tmp/test_aarch64_dynfield_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_method_implicit_field.pas /tmp/test_aarch64_mif
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_method_implicit_field.pas /tmp/test_aarch64_mif_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_mif)" = "$$(/tmp/test_aarch64_mif_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_forin_implicit_field.pas /tmp/test_aarch64_fif
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_forin_implicit_field.pas /tmp/test_aarch64_fif_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_fif)" = "$$(/tmp/test_aarch64_fif_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_dynarray_global_after_method.pas /tmp/test_aarch64_dgam
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_dynarray_global_after_method.pas /tmp/test_aarch64_dgam_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_dgam)" = "$$(/tmp/test_aarch64_dgam_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_forin_member_access.pas /tmp/test_aarch64_fima
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_forin_member_access.pas /tmp/test_aarch64_fima_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_fima)" = "$$(/tmp/test_aarch64_fima_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_call_result_member.pas /tmp/test_aarch64_crm
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_call_result_member.pas /tmp/test_aarch64_crm_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_crm)" = "$$(/tmp/test_aarch64_crm_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_collections.pas /tmp/test_aarch64_collections
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_collections.pas /tmp/test_aarch64_collections_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_collections)" = "$$(/tmp/test_aarch64_collections_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_const_record_temp.pas /tmp/test_aarch64_constrectemp
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_const_record_temp.pas /tmp/test_aarch64_constrectemp_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_constrectemp)" = "$$(/tmp/test_aarch64_constrectemp_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_const_record_temp_managed.pas /tmp/test_aarch64_constrectemp_managed
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_const_record_temp_managed.pas /tmp/test_aarch64_constrectemp_managed_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_constrectemp_managed)" = "$$(/tmp/test_aarch64_constrectemp_managed_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_set_runtime.pas /tmp/test_aarch64_setrt
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_set_runtime.pas /tmp/test_aarch64_setrt_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_setrt)" = "$$(/tmp/test_aarch64_setrt_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_managed_record_temp_init.pas /tmp/test_aarch64_mrti
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_managed_record_temp_init.pas /tmp/test_aarch64_mrti_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_mrti)" = "$$(/tmp/test_aarch64_mrti_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_dynarray_copy.pas /tmp/test_aarch64_dyncopy
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_dynarray_copy.pas /tmp/test_aarch64_dyncopy_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_dyncopy)" = "$$(/tmp/test_aarch64_dyncopy_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=aarch64 test/test_nested_dynarray_setlen.pas /tmp/test_aarch64_nestdynsetlen
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_nested_dynarray_setlen.pas /tmp/test_aarch64_nestdynsetlen_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_nestdynsetlen)" = "$$(/tmp/test_aarch64_nestdynsetlen_x64)"
	./$(COMPILER) --target=aarch64 test/test_timer.pas /tmp/test_aarch64_timer
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_timer)" = "$$(printf 'woke 50\nwoke 100\nwoke 150\ndone')"
	./$(COMPILER) --target=aarch64 test/test_reactor.pas /tmp/test_aarch64_reactor
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_reactor)" = "$$(printf 'reader: start\nreader: would-block, parking\nwriter: writing\nreader: got 2 bytes: hi\ndone')"
	./$(COMPILER) --target=aarch64 -Fulib/rtl/platform/posix test/test_asyncecho.pas /tmp/test_aarch64_asyncecho
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_asyncecho)" = "$$(printf 'client 1 ok\nclient 2 ok\ndone')"
	./$(COMPILER) --target=aarch64 test/test_extern_c.pas /tmp/test_aarch64_extern
	./$(COMPILER) test/test_extern_c.pas /tmp/test_aarch64_extern_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_extern)" = "$$(/tmp/test_aarch64_extern_x64)"
	./$(COMPILER) --target=aarch64 test/test_extern_c_float.pas /tmp/test_aarch64_extern_float
	./$(COMPILER) test/test_extern_c_float.pas /tmp/test_aarch64_extern_float_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_extern_float)" = "$$(/tmp/test_aarch64_extern_float_x64)"
	./$(COMPILER) --target=aarch64 test/ccross_entry.c /tmp/test_aarch64_centry
	tools/run_target.sh aarch64 /tmp/test_aarch64_centry; test "$$?" = "42"
	./$(COMPILER) --target=aarch64 test/ccross_args.c /tmp/test_aarch64_cargs
	tools/run_target.sh aarch64 /tmp/test_aarch64_cargs; test "$$?" = "42"
	./$(COMPILER) --target=aarch64 test/ccross_double_to_int.c /tmp/test_aarch64_cd2i
	tools/run_target.sh aarch64 /tmp/test_aarch64_cd2i; test "$$?" = "42"
	./$(COMPILER) --target=aarch64 test/test_readln.pas /tmp/test_aarch64_readln
	./$(COMPILER) test/test_readln.pas /tmp/test_aarch64_readln_x64
	test "$$(printf '100 200 300\n42\n10 20\nhello world\nQ\nSKIP\n-5\n' | tools/run_target.sh aarch64 /tmp/test_aarch64_readln)" = "$$(printf '100 200 300\n42\n10 20\nhello world\nQ\nSKIP\n-5\n' | /tmp/test_aarch64_readln_x64)"
	./$(COMPILER) --target=aarch64 test/test_eof_stdin.pas /tmp/test_aarch64_eof
	./$(COMPILER) test/test_eof_stdin.pas /tmp/test_aarch64_eof_x64
	test "$$(printf 'alpha\nbeta\ngamma' | tools/run_target.sh aarch64 /tmp/test_aarch64_eof)" = "$$(printf 'alpha\nbeta\ngamma' | /tmp/test_aarch64_eof_x64)"
	./$(COMPILER) --target=aarch64 test/cunsigned_int_arith_b121.c /tmp/test_aarch64_cuarith
	tools/run_target.sh aarch64 /tmp/test_aarch64_cuarith; test "$$?" = "42"
	./$(COMPILER) --target=aarch64 test/cunsigned_semantics_sweep_b138.c /tmp/test_aarch64_cusweep
	tools/run_target.sh aarch64 /tmp/test_aarch64_cusweep; test "$$?" = "42"
	./$(COMPILER) --target=aarch64 test/cunsigned_div_mod_b123.c /tmp/test_aarch64_cudiv
	tools/run_target.sh aarch64 /tmp/test_aarch64_cudiv; test "$$?" = "42"
	# inline asm on aarch64: locals/params via [x29,off] substitution, labels+branches, ldr/@glob global access
	./$(COMPILER) --target=aarch64 test/test_asm_a64.pas /tmp/test_aarch64_asm
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_asm)" = "$$(printf '42\n55\n42')"
	# ifdef-guarded multi-arch asm source, aarch64 leg
	./$(COMPILER) --target=aarch64 test/test_asm_ifdef_multiarch.pas /tmp/test_aarch64_asmifdef
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_asmifdef)" = "42"
	# .asm source frontend on aarch64: labels/branches + global entry override, exit code = x0
	./$(COMPILER) --target=aarch64 test/test_asm_a64_sum.asm /tmp/test_aarch64_asmfront
	tools/run_target.sh aarch64 /tmp/test_aarch64_asmfront; test "$$?" = "55"
	@echo "aarch64 hello + arith + procs + loops + write + varparam + syscall + heap + string + record + dynarray + exception + float + variant + variant-single + setlen-str + setlen-varparam + str-length-index + in-operator + loadfile + sysopen-family + args + open-array-params + string-cow + frozen-strlen-deref + rec-arr-store + huge-frame + varrec-alloc + aoc-types + many-params + conformance2 + shortcircuit + ptr-arith + case-range + global-init + typed-const + multidim + named-array + record-2darray + param-2darray + multidim3d + const-alias + float-const + classes + method-pointers + aggregate-return + metaclass-rtti + rtti-typinfo + streaming + streaming-enumset + lfm + interfaces + dynarray-field + nested-dynarray-setlen + method-implicit-field + forin-implicit-field + dynarray-global-after-method + forin-member-access + call-result-member + collections + timer + reactor + asyncecho + extern-c + extern-c-float + c-entry + c-args + c-double-to-int + readln + eof-stdin ok (output identical to x86-64)"

test-riscv32: $(COMPILER)
	./$(COMPILER) --target=riscv32 test/ccross_entry.c /tmp/test_riscv32_centry
	tools/run_target.sh riscv32 /tmp/test_riscv32_centry; test "$$?" = "42"
	./$(COMPILER) --target=riscv32 test/ccross_args.c /tmp/test_riscv32_cargs
	tools/run_target.sh riscv32 /tmp/test_riscv32_cargs; test "$$?" = "42"
	./$(COMPILER) --target=riscv32 test/ccross_double_to_int.c /tmp/test_riscv32_cd2i
	tools/run_target.sh riscv32 /tmp/test_riscv32_cd2i; test "$$?" = "42"
	./$(COMPILER) --target=riscv32 test/cunsigned_int_arith_b121.c /tmp/test_riscv32_cuarith
	tools/run_target.sh riscv32 /tmp/test_riscv32_cuarith; test "$$?" = "42"
	./$(COMPILER) --target=riscv32 test/cunsigned_semantics_sweep_b138.c /tmp/test_riscv32_cusweep
	tools/run_target.sh riscv32 /tmp/test_riscv32_cusweep; test "$$?" = "42"
	./$(COMPILER) --target=riscv32 test/cunsigned_div_mod_b123.c /tmp/test_riscv32_cudiv
	tools/run_target.sh riscv32 /tmp/test_riscv32_cudiv; test "$$?" = "42"
	./$(COMPILER) --target=riscv32 test/hello.pas /tmp/test_riscv32_hello
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_hello)" = "Hello, World!"
	# inline expansion (feature-inline-routines): -O2 == -O0 on this cross target.
	./$(COMPILER) --target=riscv32 test/test_inline_expand.pas /tmp/test_riscv32_inl_o0
	./$(COMPILER) --target=riscv32 -O2 test/test_inline_expand.pas /tmp/test_riscv32_inl_o2
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_inl_o0)" = "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_inl_o2)"
	./$(COMPILER) --target=riscv32 test/test_stackless_gen.pas /tmp/test_riscv32_slg
	./$(COMPILER) test/test_stackless_gen.pas /tmp/test_riscv32_slg_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_slg)" = "$$(/tmp/test_riscv32_slg_x64)"
	./$(COMPILER) --target=riscv32 test/test_readln.pas /tmp/test_riscv32_readln
	./$(COMPILER) test/test_readln.pas /tmp/test_riscv32_readln_x64
	test "$$(printf '100 200 300\n42\n10 20\nhello world\nQ\nSKIP\n-5\n' | tools/run_target.sh riscv32 /tmp/test_riscv32_readln)" = "$$(printf '100 200 300\n42\n10 20\nhello world\nQ\nSKIP\n-5\n' | /tmp/test_riscv32_readln_x64)"
	./$(COMPILER) --target=riscv32 test/test_eof_stdin.pas /tmp/test_riscv32_eof
	./$(COMPILER) test/test_eof_stdin.pas /tmp/test_riscv32_eof_x64
	test "$$(printf 'alpha\nbeta\ngamma' | tools/run_target.sh riscv32 /tmp/test_riscv32_eof)" = "$$(printf 'alpha\nbeta\ngamma' | /tmp/test_riscv32_eof_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_exception.pas /tmp/test_riscv32_exc
	./$(COMPILER) test/test_cross_exception.pas /tmp/test_riscv32_exc_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_exc)" = "$$(/tmp/test_riscv32_exc_x64)"
	./$(COMPILER) --target=riscv32 test/test_arm32_arg_runtime.pas /tmp/test_riscv32_pargs
	./$(COMPILER) test/test_arm32_arg_runtime.pas /tmp/test_riscv32_pargs_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_pargs alpha beta)" = "$$(/tmp/test_riscv32_pargs_x64 alpha beta)"
	./$(COMPILER) --target=riscv32 test/test_cross_typed_const.pas /tmp/test_riscv32_tc
	./$(COMPILER) test/test_cross_typed_const.pas /tmp/test_riscv32_tc_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_tc)" = "$$(/tmp/test_riscv32_tc_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_global_init.pas /tmp/test_riscv32_gi
	./$(COMPILER) test/test_cross_global_init.pas /tmp/test_riscv32_gi_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_gi)" = "$$(/tmp/test_riscv32_gi_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_set_param.pas /tmp/test_riscv32_setp
	./$(COMPILER) test/test_cross_set_param.pas /tmp/test_riscv32_setp_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_setp)" = "$$(/tmp/test_riscv32_setp_x64)"
	# inline asm on riscv32: locals/params via s0-substitution, labels+branches, la/@glob global access
	./$(COMPILER) --target=riscv32 test/test_asm_rv32.pas /tmp/test_riscv32_asm
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_asm)" = "$$(printf '42\n55\n42')"
	# .asm source frontend on riscv32: labels/branches + global entry override, exit code = a0
	./$(COMPILER) --target=riscv32 test/test_asm_rv32_sum.asm /tmp/test_riscv32_asmfront
	tools/run_target.sh riscv32 /tmp/test_riscv32_asmfront; test "$$?" = "55"
	# ifdef-guarded multi-arch asm source, riscv32 leg
	./$(COMPILER) --target=riscv32 test/test_asm_ifdef_multiarch.pas /tmp/test_riscv32_asmifdef
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_asmifdef)" = "42"
	@echo "riscv32 c-entry + c-args + c-double-to-int + c-unsigned-arith + c-unsigned-div + hello + stackless-generator + readln + eof-stdin + exception + args + typed-const + global-init + set-param + inline-asm ok"

test-arm32: $(COMPILER)
	./$(COMPILER) --target=arm32 test/hello.pas /tmp/test_arm32_hello
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_hello)" = "Hello, World!"
	# inline expansion (feature-inline-routines): -O2 == -O0 on this cross target.
	./$(COMPILER) --target=arm32 test/test_inline_expand.pas /tmp/test_arm32_inl_o0
	./$(COMPILER) --target=arm32 -O2 test/test_inline_expand.pas /tmp/test_arm32_inl_o2
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_inl_o0)" = "$$(tools/run_target.sh arm32 /tmp/test_arm32_inl_o2)"
	./$(COMPILER) --target=arm32 test/test_record_temp_byval_arg.pas /tmp/test_arm32_rectemp
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_rectemp)" = "$$(printf '18\n46')"
	./$(COMPILER) --target=arm32 test/test_ctor_string_literal_arg.pas /tmp/test_arm32_ctorstrlit
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_ctorstrlit)" = "$$(printf 'field:hello\nc1\nafter1\nc2\nafter2\nc3\nc4\nafter3\nmsg:hello\nafter4')"
	./$(COMPILER) --target=arm32 test/test_arm32_virtual_wide.pas /tmp/test_arm32_virtwide
	./$(COMPILER) test/test_arm32_virtual_wide.pas /tmp/test_arm32_virtwide_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_virtwide)" = "$$(/tmp/test_arm32_virtwide_x64)"
	# net lib cross matrix: httpdemo builds on arm32 (feature-net-lib-cross-target)
	./$(COMPILER) --target=arm32 -Fulib/rtl/platform/posix examples/net/httpdemo.pas /tmp/test_arm32_httpdemo
	./$(COMPILER) --target=arm32 test/test_arm32_record_byval_wide.pas /tmp/test_arm32_recwide
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_recwide)" = "$$(printf '1 2\n1 2\n111 222\n1 7 8 2\n1 2 3 4 7 8\n1 2 3 7 8\n1 2 3 4 5 7 8\n200 7\ndone')"
	./$(COMPILER) --target=arm32 test/test_single_in_aggregate.pas /tmp/test_arm32_singleagg
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_singleagg)" = "$$(printf '1.5 2.5 3.5\n9.500 8.250 7.125\n2.0 4.0 6.0\n10.0')"
	./$(COMPILER) --target=arm32 test/test_i386_arith.pas /tmp/test_arm32_arith
	./$(COMPILER) test/test_i386_arith.pas /tmp/test_arm32_arith_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_arith)" = "$$(/tmp/test_arm32_arith_x64)"
	./$(COMPILER) --target=arm32 test/test_i386_procs.pas /tmp/test_arm32_procs
	./$(COMPILER) test/test_i386_procs.pas /tmp/test_arm32_procs_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_procs)" = "$$(/tmp/test_arm32_procs_x64)"
	./$(COMPILER) --target=arm32 test/test_i386_loops.pas /tmp/test_arm32_loops
	./$(COMPILER) test/test_i386_loops.pas /tmp/test_arm32_loops_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_loops)" = "$$(/tmp/test_arm32_loops_x64)"
	./$(COMPILER) --target=arm32 test/test_i386_write.pas /tmp/test_arm32_write
	./$(COMPILER) test/test_i386_write.pas /tmp/test_arm32_write_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_write)" = "$$(/tmp/test_arm32_write_x64)"
	./$(COMPILER) --target=arm32 test/test_i386_varparam.pas /tmp/test_arm32_varparam
	./$(COMPILER) test/test_i386_varparam.pas /tmp/test_arm32_varparam_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_varparam)" = "$$(/tmp/test_arm32_varparam_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_syscall.pas /tmp/test_arm32_syscall
	./$(COMPILER) test/test_cross_syscall.pas /tmp/test_arm32_syscall_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_syscall)" = "$$(/tmp/test_arm32_syscall_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_heap.pas /tmp/test_arm32_heap
	./$(COMPILER) test/test_cross_heap.pas /tmp/test_arm32_heap_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_heap)" = "$$(/tmp/test_arm32_heap_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_string.pas /tmp/test_arm32_string
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_string.pas /tmp/test_arm32_string_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_string)" = "$$(/tmp/test_arm32_string_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_record.pas /tmp/test_arm32_record
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_record.pas /tmp/test_arm32_record_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_record)" = "$$(/tmp/test_arm32_record_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_dynarray.pas /tmp/test_arm32_dynarray
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_dynarray.pas /tmp/test_arm32_dynarray_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_dynarray)" = "$$(/tmp/test_arm32_dynarray_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_nested_dynarray_setlen.pas /tmp/test_arm32_nestdynsetlen
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_nested_dynarray_setlen.pas /tmp/test_arm32_nestdynsetlen_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_nestdynsetlen)" = "$$(/tmp/test_arm32_nestdynsetlen_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_exception.pas /tmp/test_arm32_exception
	./$(COMPILER) test/test_cross_exception.pas /tmp/test_arm32_exception_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_exception)" = "$$(/tmp/test_arm32_exception_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_float.pas /tmp/test_arm32_float
	./$(COMPILER) test/test_cross_float.pas /tmp/test_arm32_float_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_float)" = "$$(/tmp/test_arm32_float_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_float_return.pas /tmp/test_arm32_fret
	./$(COMPILER) test/test_cross_float_return.pas /tmp/test_arm32_fret_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_fret)" = "$$(/tmp/test_arm32_fret_x64)"
	./$(COMPILER) --target=arm32 test/test_arm32_arg_runtime.pas /tmp/test_arm32_args
	./$(COMPILER) test/test_arm32_arg_runtime.pas /tmp/test_arm32_args_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_args alpha beta)" = "$$(/tmp/test_arm32_args_x64 alpha beta)"
	./$(COMPILER) --target=arm32 test/test_cross_variant.pas /tmp/test_arm32_variant
	./$(COMPILER) test/test_cross_variant.pas /tmp/test_arm32_variant_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_variant)" = "$$(/tmp/test_arm32_variant_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_variant_single.pas /tmp/test_arm32_variant_single
	./$(COMPILER) test/test_cross_variant_single.pas /tmp/test_arm32_variant_single_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_variant_single)" = "$$(/tmp/test_arm32_variant_single_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_strresult.pas /tmp/test_arm32_strresult
	./$(COMPILER) test/test_cross_strresult.pas /tmp/test_arm32_strresult_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_strresult)" = "$$(/tmp/test_arm32_strresult_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_setlen_str.pas /tmp/test_arm32_setlen_str
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_setlen_str.pas /tmp/test_arm32_setlen_str_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_setlen_str)" = "$$(/tmp/test_arm32_setlen_str_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_setlen_varparam.pas /tmp/test_arm32_setlen_vp
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_setlen_varparam.pas /tmp/test_arm32_setlen_vp_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_setlen_vp)" = "$$(/tmp/test_arm32_setlen_vp_x64)"
	./$(COMPILER) -uPXX_MANAGED_STRING --target=arm32 test/test_cross_frozen_strlen_deref.pas /tmp/test_arm32_frozen_strlen
	./$(COMPILER) -uPXX_MANAGED_STRING test/test_cross_frozen_strlen_deref.pas /tmp/test_arm32_frozen_strlen_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_frozen_strlen)" = "$$(/tmp/test_arm32_frozen_strlen_x64)"
	./$(COMPILER) --target=arm32 test/test_managed_strlen_deref.pas /tmp/test_arm32_managed_strlen
	./$(COMPILER) test/test_managed_strlen_deref.pas /tmp/test_arm32_managed_strlen_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_managed_strlen)" = "$$(/tmp/test_arm32_managed_strlen_x64)"
	./$(COMPILER) --target=arm32 test/test_not_int64_expr.pas /tmp/test_arm32_not64
	./$(COMPILER) test/test_not_int64_expr.pas /tmp/test_arm32_not64_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_not64)" = "$$(/tmp/test_arm32_not64_x64)"
	./$(COMPILER) --target=arm32 test/test_uint32_write.pas /tmp/test_arm32_u32w
	./$(COMPILER) test/test_uint32_write.pas /tmp/test_arm32_u32w_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_u32w)" = "$$(/tmp/test_arm32_u32w_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_record_array_store.pas /tmp/test_arm32_rec_arr_store
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_record_array_store.pas /tmp/test_arm32_rec_arr_store_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_rec_arr_store)" = "$$(/tmp/test_arm32_rec_arr_store_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_str_length_index.pas /tmp/test_arm32_str_li
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_str_length_index.pas /tmp/test_arm32_str_li_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_str_li)" = "$$(/tmp/test_arm32_str_li_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_in_operator.pas /tmp/test_arm32_in
	./$(COMPILER) test/test_cross_in_operator.pas /tmp/test_arm32_in_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_in)" = "$$(/tmp/test_arm32_in_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_managed_aggregate_locals.pas /tmp/test_arm32_mal
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_managed_aggregate_locals.pas /tmp/test_arm32_mal_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_mal)" = "$$(/tmp/test_arm32_mal_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_loadfile.pas /tmp/test_arm32_loadfile
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_loadfile.pas /tmp/test_arm32_loadfile_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_loadfile)" = "$$(/tmp/test_arm32_loadfile_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_sysopen_family.pas /tmp/test_arm32_sysopen_family
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_sysopen_family.pas /tmp/test_arm32_sysopen_family_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_sysopen_family)" = "$$(/tmp/test_arm32_sysopen_family_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_string_cow.pas /tmp/test_arm32_string_cow
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_string_cow.pas /tmp/test_arm32_string_cow_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_string_cow)" = "$$(/tmp/test_arm32_string_cow_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_var_string_param.pas /tmp/test_arm32_var_string_param
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_var_string_param.pas /tmp/test_arm32_var_string_param_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_var_string_param)" = "$$(/tmp/test_arm32_var_string_param_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_openarray_string.pas /tmp/test_arm32_openarray_string
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_openarray_string.pas /tmp/test_arm32_openarray_string_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_openarray_string)" = "$$(/tmp/test_arm32_openarray_string_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_stack_params.pas /tmp/test_arm32_stack_params
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_stack_params.pas /tmp/test_arm32_stack_params_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_stack_params)" = "$$(/tmp/test_arm32_stack_params_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_int64.pas /tmp/test_arm32_int64
	./$(COMPILER) test/test_cross_int64.pas /tmp/test_arm32_int64_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_int64)" = "$$(/tmp/test_arm32_int64_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_int64_byref.pas /tmp/test_arm32_int64_byref
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_int64_byref.pas /tmp/test_arm32_int64_byref_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_int64_byref)" = "$$(/tmp/test_arm32_int64_byref_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_array_of_const_types.pas /tmp/test_arm32_aoc_types
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_array_of_const_types.pas /tmp/test_arm32_aoc_types_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_aoc_types)" = "$$(/tmp/test_arm32_aoc_types_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_cross_write_pchar.pas /tmp/test_arm32_write_pchar
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_write_pchar.pas /tmp/test_arm32_write_pchar_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_write_pchar)" = "$$(/tmp/test_arm32_write_pchar_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_static_open_array.pas /tmp/test_arm32_static_open
	./$(COMPILER) test/test_cross_static_open_array.pas /tmp/test_arm32_static_open_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_static_open)" = "$$(/tmp/test_arm32_static_open_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_many_params.pas /tmp/test_arm32_many_params
	./$(COMPILER) test/test_cross_many_params.pas /tmp/test_arm32_many_params_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_many_params)" = "$$(/tmp/test_arm32_many_params_x64)"
	./$(COMPILER) --target=arm32 test/test_conformance_2.pas /tmp/test_arm32_conf2
	./$(COMPILER) test/test_conformance_2.pas /tmp/test_arm32_conf2_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_conf2)" = "$$(/tmp/test_arm32_conf2_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_shortcircuit.pas /tmp/test_arm32_scx
	./$(COMPILER) test/test_cross_shortcircuit.pas /tmp/test_arm32_scx_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_scx)" = "$$(/tmp/test_arm32_scx_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_ptr_arith.pas /tmp/test_arm32_pa
	./$(COMPILER) test/test_cross_ptr_arith.pas /tmp/test_arm32_pa_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_pa)" = "$$(/tmp/test_arm32_pa_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_case_range.pas /tmp/test_arm32_cr
	./$(COMPILER) test/test_cross_case_range.pas /tmp/test_arm32_cr_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_cr)" = "$$(/tmp/test_arm32_cr_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_global_init.pas /tmp/test_arm32_gi
	./$(COMPILER) test/test_cross_global_init.pas /tmp/test_arm32_gi_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_gi)" = "$$(/tmp/test_arm32_gi_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_typed_const.pas /tmp/test_arm32_tc
	./$(COMPILER) test/test_cross_typed_const.pas /tmp/test_arm32_tc_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_tc)" = "$$(/tmp/test_arm32_tc_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_multidim.pas /tmp/test_arm32_md
	./$(COMPILER) test/test_cross_multidim.pas /tmp/test_arm32_md_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_md)" = "$$(/tmp/test_arm32_md_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_named_array.pas /tmp/test_arm32_na
	./$(COMPILER) test/test_cross_named_array.pas /tmp/test_arm32_na_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_na)" = "$$(/tmp/test_arm32_na_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_record_2darray.pas /tmp/test_arm32_r2
	./$(COMPILER) test/test_cross_record_2darray.pas /tmp/test_arm32_r2_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_r2)" = "$$(/tmp/test_arm32_r2_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_param_2darray.pas /tmp/test_arm32_pa2
	./$(COMPILER) test/test_cross_param_2darray.pas /tmp/test_arm32_pa2_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_pa2)" = "$$(/tmp/test_arm32_pa2_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_multidim3d.pas /tmp/test_arm32_d3
	./$(COMPILER) test/test_cross_multidim3d.pas /tmp/test_arm32_d3_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_d3)" = "$$(/tmp/test_arm32_d3_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_const_alias.pas /tmp/test_arm32_ca
	./$(COMPILER) test/test_cross_const_alias.pas /tmp/test_arm32_ca_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_ca)" = "$$(/tmp/test_arm32_ca_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_float_const.pas /tmp/test_arm32_fc
	./$(COMPILER) test/test_cross_float_const.pas /tmp/test_arm32_fc_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_fc)" = "$$(/tmp/test_arm32_fc_x64)"
	./$(COMPILER) --target=arm32 test/test_scheduler.pas /tmp/test_arm32_sched
	./$(COMPILER) test/test_scheduler.pas /tmp/test_arm32_sched_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_sched)" = "$$(/tmp/test_arm32_sched_x64)"
	./$(COMPILER) --target=arm32 test/test_scheduler_exc.pas /tmp/test_arm32_sexc
	./$(COMPILER) test/test_scheduler_exc.pas /tmp/test_arm32_sexc_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_sexc)" = "$$(/tmp/test_arm32_sexc_x64)"
	./$(COMPILER) --target=arm32 test/test_async_sl.pas /tmp/test_arm32_asl
	./$(COMPILER) test/test_async_sl.pas /tmp/test_arm32_asl_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_asl)" = "$$(/tmp/test_arm32_asl_x64)"
	./$(COMPILER) --target=arm32 test/test_channel.pas /tmp/test_arm32_chan
	./$(COMPILER) test/test_channel.pas /tmp/test_arm32_chan_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_chan)" = "$$(/tmp/test_arm32_chan_x64)"
	./$(COMPILER) --target=arm32 test/test_methodptr.pas /tmp/test_arm32_mptr
	./$(COMPILER) test/test_methodptr.pas /tmp/test_arm32_mptr_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_mptr)" = "$$(/tmp/test_arm32_mptr_x64)"
	./$(COMPILER) --target=arm32 test/test_methcall.pas /tmp/test_arm32_mcall
	./$(COMPILER) test/test_methcall.pas /tmp/test_arm32_mcall_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_mcall)" = "$$(/tmp/test_arm32_mcall_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_sets.pas /tmp/test_arm32_sets
	./$(COMPILER) test/test_cross_sets.pas /tmp/test_arm32_sets_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_sets)" = "$$(/tmp/test_arm32_sets_x64)"
	./$(COMPILER) --target=arm32 test/test_classref.pas /tmp/test_arm32_classref
	./$(COMPILER) test/test_classref.pas /tmp/test_arm32_classref_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_classref)" = "$$(/tmp/test_arm32_classref_x64)"
	./$(COMPILER) --target=arm32 test/test_class_of.pas /tmp/test_arm32_classof
	./$(COMPILER) test/test_class_of.pas /tmp/test_arm32_classof_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_classof)" = "$$(/tmp/test_arm32_classof_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_rtti.pas /tmp/test_arm32_rtti
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_rtti.pas /tmp/test_arm32_rtti_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_rtti | grep -vE 'pointer:|RTTI value:|InstanceSize:')" = "$$(/tmp/test_arm32_rtti_x64 | grep -vE 'pointer:|RTTI value:|InstanceSize:')"
	./$(COMPILER) --target=arm32 test/test_streaming.pas /tmp/test_arm32_streaming
	./$(COMPILER) test/test_streaming.pas /tmp/test_arm32_streaming_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_streaming)" = "$$(/tmp/test_arm32_streaming_x64)"
	./$(COMPILER) --target=arm32 test/test_streaming_enumset.pas /tmp/test_arm32_streaming_enumset
	./$(COMPILER) test/test_streaming_enumset.pas /tmp/test_arm32_streaming_enumset_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_streaming_enumset)" = "$$(/tmp/test_arm32_streaming_enumset_x64)"
	./$(COMPILER) --target=arm32 test/test_lfm.pas /tmp/test_arm32_lfm
	./$(COMPILER) test/test_lfm.pas /tmp/test_arm32_lfm_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_lfm)" = "$$(/tmp/test_arm32_lfm_x64)"
	./$(COMPILER) --target=arm32 test/test_interfaces.pas /tmp/test_arm32_iface
	./$(COMPILER) test/test_interfaces.pas /tmp/test_arm32_iface_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_iface)" = "$$(/tmp/test_arm32_iface_x64)"
	./$(COMPILER) --target=arm32 test/test_interface_arc.pas /tmp/test_arm32_iarc
	./$(COMPILER) test/test_interface_arc.pas /tmp/test_arm32_iarc_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_iarc)" = "$$(/tmp/test_arm32_iarc_x64)"
	./$(COMPILER) --target=arm32 test/test_uint64_ops.pas /tmp/test_arm32_u64
	./$(COMPILER) test/test_uint64_ops.pas /tmp/test_arm32_u64_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_u64)" = "$$(/tmp/test_arm32_u64_x64)"
	./$(COMPILER) --target=arm32 test/test_interfaces_is.pas /tmp/test_arm32_iface_is
	./$(COMPILER) test/test_interfaces_is.pas /tmp/test_arm32_iface_is_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_iface_is)" = "$$(/tmp/test_arm32_iface_is_x64)"
	./$(COMPILER) --target=arm32 test/test_interfaces_as.pas /tmp/test_arm32_iface_as
	./$(COMPILER) test/test_interfaces_as.pas /tmp/test_arm32_iface_as_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_iface_as)" = "$$(/tmp/test_arm32_iface_as_x64)"
	./$(COMPILER) --target=arm32 test/test_interfaces_param.pas /tmp/test_arm32_iface_param
	./$(COMPILER) test/test_interfaces_param.pas /tmp/test_arm32_iface_param_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_iface_param)" = "$$(/tmp/test_arm32_iface_param_x64)"
	./$(COMPILER) --target=arm32 test/test_interfaces_inherit.pas /tmp/test_arm32_iface_inh
	./$(COMPILER) test/test_interfaces_inherit.pas /tmp/test_arm32_iface_inh_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_iface_inh)" = "$$(/tmp/test_arm32_iface_inh_x64)"
	./$(COMPILER) --target=arm32 test/test_interfaces_multi_secondary.pas /tmp/test_arm32_iface_multi
	./$(COMPILER) test/test_interfaces_multi_secondary.pas /tmp/test_arm32_iface_multi_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_iface_multi)" = "$$(/tmp/test_arm32_iface_multi_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_aggregate_return.pas /tmp/test_arm32_aggret
	./$(COMPILER) test/test_cross_aggregate_return.pas /tmp/test_arm32_aggret_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_aggret)" = "$$(/tmp/test_arm32_aggret_x64)"
	# aggregate / frozen-string result via a VIRTUAL and an INDIRECT call
	# (feature-cross-virtual-indirect-hidden-dest)
	./$(COMPILER) --target=arm32 test/test_cross_virtual_indirect_aggret.pas /tmp/test_arm32_vindaggret
	./$(COMPILER) test/test_cross_virtual_indirect_aggret.pas /tmp/test_arm32_vindaggret_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_vindaggret)" = "$$(/tmp/test_arm32_vindaggret_x64)"
	./$(COMPILER) --target=arm32 test/test_cross_aggregate_stackargs.pas /tmp/test_arm32_aggstk
	./$(COMPILER) test/test_cross_aggregate_stackargs.pas /tmp/test_arm32_aggstk_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_aggstk)" = "$$(/tmp/test_arm32_aggstk_x64)"
	./$(COMPILER) --target=arm32 test/test_inheritance_dispatch.pas /tmp/test_arm32_cls
	./$(COMPILER) test/test_inheritance_dispatch.pas /tmp/test_arm32_cls_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_cls)" = "$$(/tmp/test_arm32_cls_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_dynarray_field.pas /tmp/test_arm32_dynfield
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_dynarray_field.pas /tmp/test_arm32_dynfield_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_dynfield)" = "$$(/tmp/test_arm32_dynfield_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_method_implicit_field.pas /tmp/test_arm32_mif
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_method_implicit_field.pas /tmp/test_arm32_mif_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_mif)" = "$$(/tmp/test_arm32_mif_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_forin_implicit_field.pas /tmp/test_arm32_fif
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_forin_implicit_field.pas /tmp/test_arm32_fif_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_fif)" = "$$(/tmp/test_arm32_fif_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_dynarray_global_after_method.pas /tmp/test_arm32_dgam
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_dynarray_global_after_method.pas /tmp/test_arm32_dgam_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_dgam)" = "$$(/tmp/test_arm32_dgam_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_forin_member_access.pas /tmp/test_arm32_fima
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_forin_member_access.pas /tmp/test_arm32_fima_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_fima)" = "$$(/tmp/test_arm32_fima_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_call_result_member.pas /tmp/test_arm32_crm
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_call_result_member.pas /tmp/test_arm32_crm_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_crm)" = "$$(/tmp/test_arm32_crm_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_collections.pas /tmp/test_arm32_collections
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_collections.pas /tmp/test_arm32_collections_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_collections)" = "$$(/tmp/test_arm32_collections_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_const_record_temp.pas /tmp/test_arm32_constrectemp
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_const_record_temp.pas /tmp/test_arm32_constrectemp_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_constrectemp)" = "$$(/tmp/test_arm32_constrectemp_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_const_record_temp_managed.pas /tmp/test_arm32_constrectemp_managed
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_const_record_temp_managed.pas /tmp/test_arm32_constrectemp_managed_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_constrectemp_managed)" = "$$(/tmp/test_arm32_constrectemp_managed_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_set_runtime.pas /tmp/test_arm32_setrt
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_set_runtime.pas /tmp/test_arm32_setrt_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_setrt)" = "$$(/tmp/test_arm32_setrt_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_managed_record_temp_init.pas /tmp/test_arm32_mrti
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_managed_record_temp_init.pas /tmp/test_arm32_mrti_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_mrti)" = "$$(/tmp/test_arm32_mrti_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=arm32 test/test_dynarray_copy.pas /tmp/test_arm32_dyncopy
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_dynarray_copy.pas /tmp/test_arm32_dyncopy_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_dyncopy)" = "$$(/tmp/test_arm32_dyncopy_x64)"
	./$(COMPILER) --target=arm32 test/test_timer.pas /tmp/test_arm32_timer
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_timer)" = "$$(printf 'woke 50\nwoke 100\nwoke 150\ndone')"
	./$(COMPILER) --target=arm32 test/test_reactor.pas /tmp/test_arm32_reactor
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_reactor)" = "$$(printf 'reader: start\nreader: would-block, parking\nwriter: writing\nreader: got 2 bytes: hi\ndone')"
	./$(COMPILER) --target=arm32 -Fulib/rtl/platform/posix test/test_asyncecho.pas /tmp/test_arm32_asyncecho
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_asyncecho)" = "$$(printf 'client 1 ok\nclient 2 ok\ndone')"
	./$(COMPILER) --target=arm32 test/test_extern_c.pas /tmp/test_arm32_extern
	./$(COMPILER) test/test_extern_c.pas /tmp/test_arm32_extern_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_extern)" = "$$(/tmp/test_arm32_extern_x64)"
	./$(COMPILER) --target=arm32 test/test_extern_c_float.pas /tmp/test_arm32_extern_float
	./$(COMPILER) test/test_extern_c_float.pas /tmp/test_arm32_extern_float_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_extern_float)" = "$$(/tmp/test_arm32_extern_float_x64)"
	./$(COMPILER) --target=arm32 test/ccross_entry.c /tmp/test_arm32_centry
	tools/run_target.sh arm32 /tmp/test_arm32_centry; test "$$?" = "42"
	./$(COMPILER) --target=arm32 test/ccross_args.c /tmp/test_arm32_cargs
	tools/run_target.sh arm32 /tmp/test_arm32_cargs; test "$$?" = "42"
	./$(COMPILER) --target=arm32 test/ccross_double_to_int.c /tmp/test_arm32_cd2i
	tools/run_target.sh arm32 /tmp/test_arm32_cd2i; test "$$?" = "42"
	./$(COMPILER) --target=arm32 test/test_readln.pas /tmp/test_arm32_readln
	./$(COMPILER) test/test_readln.pas /tmp/test_arm32_readln_x64
	test "$$(printf '100 200 300\n42\n10 20\nhello world\nQ\nSKIP\n-5\n' | tools/run_target.sh arm32 /tmp/test_arm32_readln)" = "$$(printf '100 200 300\n42\n10 20\nhello world\nQ\nSKIP\n-5\n' | /tmp/test_arm32_readln_x64)"
	./$(COMPILER) --target=arm32 test/test_eof_stdin.pas /tmp/test_arm32_eof
	./$(COMPILER) test/test_eof_stdin.pas /tmp/test_arm32_eof_x64
	test "$$(printf 'alpha\nbeta\ngamma' | tools/run_target.sh arm32 /tmp/test_arm32_eof)" = "$$(printf 'alpha\nbeta\ngamma' | /tmp/test_arm32_eof_x64)"
	./$(COMPILER) --target=arm32 test/cunsigned_int_arith_b121.c /tmp/test_arm32_cuarith
	tools/run_target.sh arm32 /tmp/test_arm32_cuarith; test "$$?" = "42"
	./$(COMPILER) --target=arm32 test/cunsigned_semantics_sweep_b138.c /tmp/test_arm32_cusweep
	tools/run_target.sh arm32 /tmp/test_arm32_cusweep; test "$$?" = "42"
	./$(COMPILER) --target=arm32 test/cunsigned_div_mod_b123.c /tmp/test_arm32_cudiv
	tools/run_target.sh arm32 /tmp/test_arm32_cudiv; test "$$?" = "42"
	# inline asm on arm32: locals/params via [fp,off] substitution, labels+cond-suffixed branches, ldr/@glob global access
	./$(COMPILER) --target=arm32 test/test_asm_arm32.pas /tmp/test_arm32_asm
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_asm)" = "$$(printf '42\n55\n42')"
	# .asm source frontend on arm32: labels/branches + global entry override, exit code = r0
	./$(COMPILER) --target=arm32 test/test_asm_arm32_sum.asm /tmp/test_arm32_asmfront
	tools/run_target.sh arm32 /tmp/test_arm32_asmfront; test "$$?" = "55"
	@echo "arm32 hello + arith + procs + loops + write + varparam + syscall + heap + string + record + dynarray + exception + float + args + variant + variant-single + strresult + setlen-str + setlen-varparam + str-length-index + in-operator + managed-aggregate-locals + loadfile + sysopen-family + string-cow + frozen-strlen-deref + rec-arr-store + var-string-param + openarray-string + stack-params + aggregate-stackargs + int64 + int64-byref + aoc-types + many-params + conformance2 + shortcircuit + ptr-arith + case-range + global-init + typed-const + multidim + named-array + record-2darray + param-2darray + multidim3d + const-alias + float-const + classes + method-pointers + aggregate-return + metaclass-rtti + rtti-typinfo + streaming + streaming-enumset + lfm + interfaces + dynarray-field + nested-dynarray-setlen + method-implicit-field + forin-implicit-field + dynarray-global-after-method + forin-member-access + call-result-member + collections + timer + reactor + asyncecho + extern-c + extern-c-float + c-entry + c-args + c-double-to-int + readln + eof-stdin ok (output identical to x86-64)"

# ----- Cross self-host bootstrap gates (feature-cross-bootstrap-selfhost) -----
# Triple-stage proof: native cross-compiles compiler.pas -> <arch>; that binary,
# run under QEMU, compiles compiler.pas -> <arch> again; the two outputs must be
# byte-identical. Managed runtime (-dPXX_MANAGED_STRING) is required.
CROSS_BOOTSTRAP_FLAGS := -dPXX_MANAGED_STRING

cross-bootstrap-aarch64: $(COMPILER)
	./$(COMPILER) $(CROSS_BOOTSTRAP_FLAGS) --target=aarch64 compiler/compiler.pas /tmp/pc_aarch64
	tools/run_target.sh aarch64 /tmp/pc_aarch64 $(CROSS_BOOTSTRAP_FLAGS) --target=aarch64 compiler/compiler.pas /tmp/pc_aarch64_2
	cmp /tmp/pc_aarch64 /tmp/pc_aarch64_2
	@echo "aarch64 cross self-host: byte-identical self-fixedpoint OK"

cross-bootstrap-arm32: $(COMPILER)
	./$(COMPILER) $(CROSS_BOOTSTRAP_FLAGS) --target=arm32 compiler/compiler.pas /tmp/pc_arm32
	tools/run_target.sh arm32 /tmp/pc_arm32 $(CROSS_BOOTSTRAP_FLAGS) --target=arm32 compiler/compiler.pas /tmp/pc_arm32_2
	cmp /tmp/pc_arm32 /tmp/pc_arm32_2
	@echo "arm32 cross self-host: byte-identical self-fixedpoint OK"

cross-bootstrap-i386: $(COMPILER)
	./$(COMPILER) $(CROSS_BOOTSTRAP_FLAGS) --target=i386 compiler/compiler.pas /tmp/pc_i386
	tools/run_target.sh i386 /tmp/pc_i386 $(CROSS_BOOTSTRAP_FLAGS) --target=i386 compiler/compiler.pas /tmp/pc_i386_2
	cmp /tmp/pc_i386 /tmp/pc_i386_2
	@echo "i386 cross self-host: byte-identical self-fixedpoint OK"

cross-bootstrap: cross-bootstrap-aarch64 cross-bootstrap-arm32 cross-bootstrap-i386
	@echo "cross-bootstrap: i386 + aarch64 + arm32 all byte-identical self-fixedpoint"

# Float bit-determinism across targets (feature-real-cross-target-consistency).
# The mandelbrot escape-count checksum is integer-deterministic: strict IEEE-754
# Double (x86-64 SSE2, AArch64/ARM VFP) must produce the SAME checksum on every
# target — a mismatch localises a float-determinism bug (e.g. i386 x87 80-bit
# intermediates). Reference 3745966 (FPC-confirmed on x86-64).
test-float-determinism: $(COMPILER)
	./$(COMPILER) examples/mandelbrot/mandelbrot.pas /tmp/mb_x86_64
	test "$$(/tmp/mb_x86_64 | grep checksum=)" = "checksum=3745966"
	@for a in i386 aarch64 arm32; do \
	  ./$(COMPILER) --target=$$a examples/mandelbrot/mandelbrot.pas /tmp/mb_$$a >/dev/null || exit 1; \
	  c=$$(tools/run_target.sh $$a /tmp/mb_$$a | grep checksum=); \
	  test "$$c" = "checksum=3745966" || { echo "$$a float-determinism FAIL: $$c (want checksum=3745966)"; exit 1; }; \
	  echo "$$a float-determinism: OK (checksum=3745966)"; \
	done
	@echo "test-float-determinism: x86_64 + i386 + aarch64 + arm32 all checksum=3745966"

# Lua integration suite (feature-c-source-frontend smoke). DISTINCT from `make
# test`: the base gate carries no 3rd-party dependency. Compiles the lua 5.4
# core+stdlib (from library_candidates/lua/src — gitignored scratch, fetch it
# there) into a file-loading runner and checks each test/lua/*.lua against its committed
# .expected stdout. Skips gracefully when the lua tree is absent. Exercises the
# C frontend end-to-end on real portable C (OOP/metatables, closures, coroutines,
# string lib, the float value model) — coverage the micro-tests cannot reach
# (e.g. sizeof("self") breaking colon-method OOP was invisible to them).
LUA_SRC := library_candidates/lua/src
test-lua: $(COMPILER)
	@if [ ! -f "$(LUA_SRC)/lua.h" ]; then \
	  echo "test-lua: SKIP — no lua tree at $(LUA_SRC) (fetch lua 5.4 there to run)"; \
	  exit 0; \
	fi; \
	echo "compiling lua runner ..."; \
	wd="$$(mktemp -d)"; trap 'rm -rf "$$wd"' EXIT; \
	./$(COMPILER) -g -Ilib/crtl/include -Ilib/crtl/src -I$(LUA_SRC) test/lua/runner.c "$$wd/runner" || exit 1; \
	fail=0; for p in test/lua/*.lua; do \
	  exp="$${p%.lua}.expected"; \
	  "$$wd/runner" "$$p" 2>/dev/null > "$$wd/got.txt"; \
	  if diff -u "$$exp" "$$wd/got.txt" > "$$wd/diff.txt"; then \
	    echo "test-lua: PASS $$(basename $$p)"; \
	  else \
	    echo "test-lua: FAIL $$(basename $$p)"; \
	    head -12 "$$wd/diff.txt"; \
	    fail=1; \
	  fi; \
	done; \
	test "$$fail" = "0" || { echo "test-lua: FAILURES"; exit 1; }; \
	echo "test-lua: all lua programs match expected"

# Cross-target lua 5.4 (feature-c-cross-lua-sqlite). Builds the lua runner for a
# cross target and runs every script under qemu, comparing to the same .expected
# files as test-lua. NOT part of `make test` (3rd-party dep + qemu). aarch64 is
# green; the other targets await their variadic-ABI bring-up (they build-fail
# early, so are omitted here rather than reported as failures). Skips gracefully
# when the lua tree or qemu is absent.
LUA_CROSS_TARGETS ?= aarch64 arm32 i386 riscv32
test-lua-cross: $(COMPILER)
	@if [ ! -f "$(LUA_SRC)/lua.h" ]; then \
	  echo "test-lua-cross: SKIP — no lua tree at $(LUA_SRC)"; exit 0; \
	fi; \
	overall=0; \
	for T in $(LUA_CROSS_TARGETS); do \
	  if ! command -v qemu-$$T >/dev/null 2>&1 && ! command -v qemu-$${T%32} >/dev/null 2>&1; then \
	    echo "test-lua-cross: SKIP $$T (qemu-$$T not installed)"; continue; \
	  fi; \
	  echo "test-lua-cross: building lua for $$T ..."; \
	  if ! ./$(COMPILER) --target=$$T -g -Ilib/crtl/include -Ilib/crtl/src -I$(LUA_SRC) \
	       test/lua/runner.c /tmp/pxx_lua_$$T 2>/tmp/pxx_lua_$$T.err; then \
	    echo "test-lua-cross: FAIL $$T (build error)"; head -3 /tmp/pxx_lua_$$T.err; overall=1; continue; \
	  fi; \
	  fail=0; \
	  for p in test/lua/*.lua; do \
	    exp="$${p%.lua}.expected"; \
	    cp "$$p" /tmp/pxx_lua_input.lua; \
	    timeout 120 tools/run_target.sh $$T /tmp/pxx_lua_$$T 2>/dev/null > /tmp/pxx_lua_got.txt; \
	    if diff -u "$$exp" /tmp/pxx_lua_got.txt > /tmp/pxx_lua_diff.txt; then \
	      echo "test-lua-cross: PASS $$T $$(basename $$p)"; \
	    else \
	      echo "test-lua-cross: FAIL $$T $$(basename $$p)"; head -12 /tmp/pxx_lua_diff.txt; fail=1; \
	    fi; \
	  done; \
	  test "$$fail" = "0" || overall=1; \
	done; \
	test "$$overall" = "0" || { echo "test-lua-cross: FAILURES"; exit 1; }; \
	echo "test-lua-cross: all cross lua runs match expected"

# Multithreaded SQLite over the libc-free PXX pthread shim (lib/crtl pthread.h/.c
# bridged to the PAL via lib/rtl/palpthread.pas). Builds SQLITE_THREADSAFE=1 and
# runs test/csqlite_thread_test.c: N threads on one FULLMUTEX (serialized)
# connection + N per-thread connections, self-checking. Both threading-capable
# targets: x86-64 (native) + i386 (qemu). --threadsafe is x86-64/i386 only (the
# PAL atomics/clone are not ported to arm32/aarch64/riscv32 yet — M5). Skips when
# the gitignored sqlite amalgamation is absent, like test-cjson. NOT in `make
# test` (large 3rd-party build); run explicitly.
SQLITE_SRC ?= library_candidates/sqlite
test-sqlite-threads-%: $(COMPILER)
	tools/run_sqlite_thread_test.sh $* ./$(COMPILER) $(SQLITE_SRC)

test-sqlite-threads: test-sqlite-threads-x86_64 test-sqlite-threads-i386 test-sqlite-threads-aarch64 test-sqlite-threads-arm32
	@echo "test-sqlite-threads: all arches green (or skipped)"

# cJSON integration suite (feature-c-source-frontend smoke). DISTINCT from `make
# test`: the base gate carries no 3rd-party dependency. Amalgamates lib/crtl + the
# cJSON 1.7.18 core (from library_candidates/cjson/src — gitignored scratch, fetch
# it there) into a round-trip runner: parse each test/cjson/*.json and re-serialize
# with cJSON_PrintUnformatted, checking stdout against the committed *.expected
# (generated independently with stock json tooling). Skips gracefully when the
# cJSON tree is absent. Rung-1 C-frontend probe: heap (malloc/realloc/free),
# object/array structs, pointers, recursive parser, string handling — coverage the
# test/c*_b*.c micro-tests cannot reach. The float-output path additionally needs
# crtl sscanf; the committed fixtures stay integer/string/bool/null to keep that
# gap out of this rung.
CJSON_SRC := library_candidates/cjson/src
test-cjson: $(COMPILER)
	@if [ ! -f "$(CJSON_SRC)/cJSON.h" ]; then \
	  echo "test-cjson: SKIP — no cJSON tree at $(CJSON_SRC) (fetch cJSON 1.7.18 there to run)"; \
	  exit 0; \
	fi; \
	echo "compiling cJSON runner ..."; \
	wd="$$(mktemp -d)"; trap 'rm -rf "$$wd"' EXIT; \
	./$(COMPILER) -g -Ilib/crtl/include -Ilib/crtl/src -I$(CJSON_SRC) test/cjson/runner.c "$$wd/runner" || exit 1; \
	fail=0; for p in test/cjson/*.json; do \
	  exp="$${p%.json}.expected"; \
	  "$$wd/runner" "$$p" 2>/dev/null > "$$wd/got.txt"; \
	  if diff -u "$$exp" "$$wd/got.txt" > "$$wd/diff.txt"; then \
	    echo "test-cjson: PASS $$(basename $$p)"; \
	  else \
	    echo "test-cjson: FAIL $$(basename $$p)"; \
	    head -12 "$$wd/diff.txt"; \
	    fail=1; \
	  fi; \
	done; \
	test "$$fail" = "0" || { echo "test-cjson: FAILURES"; exit 1; }; \
	echo "test-cjson: all cJSON documents round-trip to expected"

# c-testsuite conformance battery (feature-c-corpus-expansion step 1).
# Auto-skips when the gitignored suite is absent (tools/install_lib_candidates.sh
# c-testsuite). Known-fails are EXPLICIT in test/c-conformance/pxx.skip, one
# ticket-referenced line per test; anything else failing = regression, exit 1.
# Differential fuzzing vs gcc on random csmith programs. NOT part of `make test` --
# it is open-ended by nature (run it for as long as you like). Needs the csmith
# generator (apt install csmith) and its headers
# (tools/install_lib_candidates.sh csmith). Exits non-zero only on a MISCOMPILE.
#   make fuzz-csmith                 # 100 programs
#   make fuzz-csmith FUZZ_ITERS=1000
FUZZ_ITERS ?= 100
fuzz-csmith: $(COMPILER)
	tools/csmith_fuzz.py --iters $(FUZZ_ITERS)

test-c-conformance: $(COMPILER)
	tools/run_c_conformance.sh ./$(COMPILER)

# C cross-conformance matrix (feature-c-cross-target-feature-coverage): the
# same 220-program battery compiled --target=<arch> and run under QEMU
# (tools/run_target.sh). Per-target backend gaps are EXPLICIT in
# test/c-conformance/pxx.skip.<arch> (one ticket-referenced line each), on top
# of the base pxx.skip; anything else failing = cross regression, exit 1.
test-c-conformance-i386: $(COMPILER)
	tools/run_c_conformance.sh ./$(COMPILER) library_candidates/c-testsuite/tests/single-exec --target i386
test-c-conformance-aarch64: $(COMPILER)
	tools/run_c_conformance.sh ./$(COMPILER) library_candidates/c-testsuite/tests/single-exec --target aarch64
test-c-conformance-arm32: $(COMPILER)
	tools/run_c_conformance.sh ./$(COMPILER) library_candidates/c-testsuite/tests/single-exec --target arm32
test-c-conformance-riscv32: $(COMPILER)
	tools/run_c_conformance.sh ./$(COMPILER) library_candidates/c-testsuite/tests/single-exec --target riscv32
test-c-conformance-cross: test-c-conformance-i386 test-c-conformance-aarch64 test-c-conformance-arm32 test-c-conformance-riscv32
	@echo "test-c-conformance-cross: all targets green"

# Track C gate bundle: the base gate (test-core self-host + C unit tests) PLUS
# the c-testsuite conformance battery. Run this before pushing a C-frontend
# change — `make test` alone does NOT run c-conformance, so a cparser/clexer
# change can pass test-core + self-host and still silently regress c-testsuite
# (e.g. the 00022 typedef-shadow regression, 2026-07-06).
test-c: test-core test-c-conformance
	@echo "test-c: base gate + c-conformance green"

# zlib v1.3.1 bring-up (feature-c-corpus-zlib, corpus step 2). Unity-builds
# crtl + the zlib TUs + zlib's own test/example.c and diffs stdout+exit against
# the SAME sources built with gcc (the oracle). Skips if the gitignored tree is
# absent (tools/install_lib_candidates.sh zlib). NOT in `make test` (3rd-party +
# needs gcc). Currently blocked — see the ticket's two compiler blockers.
ZLIB_SRC ?= library_candidates/zlib
test-zlib: $(COMPILER)
	@if [ ! -f "$(ZLIB_SRC)/zlib.h" ]; then \
	  echo "test-zlib: SKIP — no zlib tree at $(ZLIB_SRC) (tools/install_lib_candidates.sh zlib)"; \
	  exit 0; \
	fi; \
	command -v gcc >/dev/null 2>&1 || { echo "test-zlib: SKIP — gcc oracle not found"; exit 0; }; \
	echo "building gcc oracle ..."; \
	gcc -w -I$(ZLIB_SRC) -o /tmp/pxx_zlib_oracle \
	  $(ZLIB_SRC)/adler32.c $(ZLIB_SRC)/crc32.c $(ZLIB_SRC)/zutil.c \
	  $(ZLIB_SRC)/inftrees.c $(ZLIB_SRC)/inffast.c $(ZLIB_SRC)/inflate.c \
	  $(ZLIB_SRC)/infback.c $(ZLIB_SRC)/trees.c $(ZLIB_SRC)/deflate.c \
	  $(ZLIB_SRC)/compress.c $(ZLIB_SRC)/uncompr.c $(ZLIB_SRC)/gzlib.c \
	  $(ZLIB_SRC)/gzread.c $(ZLIB_SRC)/gzwrite.c $(ZLIB_SRC)/gzclose.c \
	  $(ZLIB_SRC)/test/example.c || exit 1; \
	( cd /tmp && ./pxx_zlib_oracle > /tmp/pxx_zlib_oracle.txt 2>&1 ); \
	echo "compiling pxx zlib runner ..."; \
	./$(COMPILER) -g -Ilib/crtl/include -Ilib/crtl/src -I$(ZLIB_SRC) -I$(ZLIB_SRC)/test \
	  test/zlib/runner.c /tmp/pxx_zlib_runner || exit 1; \
	( cd /tmp && ./pxx_zlib_runner > /tmp/pxx_zlib_got.txt 2>&1 ); \
	if diff -u /tmp/pxx_zlib_oracle.txt /tmp/pxx_zlib_got.txt; then \
	  echo "test-zlib: PASS — byte-identical to gcc oracle"; \
	else \
	  echo "test-zlib: FAIL — output differs from gcc oracle"; exit 1; \
	fi

# Chess perft corpus (feature-c-corpus-chess, corpus step after tcc). Unity-builds
# crtl + the VICE engine's perft translation units and runs legal-move perft over
# the canonical positions (startpos + Kiwipete + positions 3-6). The oracle is NOT
# gcc: the perft counts are compiler-independent known-answer values baked into the
# runner — a wrong count is a pxx miscompile (movegen / 64-bit bitboard mask /
# recursion / array-of-struct movelist), never the engine. Default depth 1..4 (a
# few seconds); PERFT_DEEP=5 for the heavy depth-5 sweep (~40s). Skips if the
# gitignored tree is absent (tools/install_lib_candidates.sh chess). NOT in
# `make test` (3rd-party).
CHESS_SRC ?= library_candidates/chess/Vice11/src
PERFT_DEEP ?=
test-chess-perft: $(COMPILER)
	@if [ ! -f "$(CHESS_SRC)/perft.c" ]; then \
	  echo "test-chess-perft: SKIP — no chess tree at $(CHESS_SRC) (tools/install_lib_candidates.sh chess)"; \
	  exit 0; \
	fi; \
	deep=""; [ -n "$(PERFT_DEEP)" ] && deep="-DPERFT_DEEP=$(PERFT_DEEP)"; \
	echo "compiling pxx chess perft runner ..."; \
	./$(COMPILER) $$deep -Ilib/crtl/include -Ilib/crtl/src -I$(CHESS_SRC) \
	  test/chess/perft_runner.c /tmp/pxx_chess_perft || exit 1; \
	/tmp/pxx_chess_perft > /tmp/pxx_chess_perft.txt 2>&1; rc=$$?; \
	cat /tmp/pxx_chess_perft.txt; \
	if [ "$$rc" = "42" ]; then \
	  echo "test-chess-perft: PASS — all canonical perft counts match"; \
	else \
	  echo "test-chess-perft: FAIL — perft mismatch (exit $$rc)"; exit 1; \
	fi

# Relocatable .o emission for the esp32-idf profile (feature-elf-rel-writer).
# Host-only checks via binutils readelf; if the ESP cross toolchains are
# installed (~/.espressif), also proves each .o links against a C shim.
test-emit-obj: $(COMPILER)
	./$(COMPILER) --target=riscv32 test/test_emit_obj.pas /tmp/test_emit_obj_rv.o
	readelf -h /tmp/test_emit_obj_rv.o | grep -q 'REL (Relocatable file)'
	readelf -h /tmp/test_emit_obj_rv.o | grep -q 'RISC-V'
	readelf -s /tmp/test_emit_obj_rv.o | grep -q 'FUNC    GLOBAL DEFAULT    1 app_main'
	readelf -s /tmp/test_emit_obj_rv.o | grep -q 'UND ext_notify'
	readelf -r /tmp/test_emit_obj_rv.o | grep -q 'R_RISCV_32'
	readelf -r /tmp/test_emit_obj_rv.o | grep -q 'ext_notify + 0'
	./$(COMPILER) --target=xtensa test/test_emit_obj.pas /tmp/test_emit_obj_xt.o
	readelf -h /tmp/test_emit_obj_xt.o | grep -q 'REL (Relocatable file)'
	readelf -h /tmp/test_emit_obj_xt.o | grep -q 'Xtensa'
	readelf -s /tmp/test_emit_obj_xt.o | grep -q 'FUNC    GLOBAL DEFAULT    1 app_main'
	readelf -s /tmp/test_emit_obj_xt.o | grep -q 'UND ext_notify'
	readelf -r /tmp/test_emit_obj_xt.o | grep -q 'R_XTENSA_32'
	readelf -r /tmp/test_emit_obj_xt.o | grep -q 'ext_notify + 0'
	./$(COMPILER) --target=xtensa --xtensa-abi=windowed test/test_emit_obj.pas /tmp/test_emit_obj_xt_windowed.o
	readelf -h /tmp/test_emit_obj_xt_windowed.o | grep -q 'REL (Relocatable file)'
	readelf -h /tmp/test_emit_obj_xt_windowed.o | grep -q 'Xtensa'
	readelf -s /tmp/test_emit_obj_xt_windowed.o | grep -q 'FUNC    GLOBAL DEFAULT    1 app_main'
	readelf -r /tmp/test_emit_obj_xt_windowed.o | grep -q 'R_XTENSA_32'
	@printf 'int captured;\nvoid ext_notify(int v) { captured = v; }\nextern void app_main(void);\nint main(void) { app_main(); return captured; }\n' > /tmp/test_emit_obj_shim.c
	@RV=$$(ls $$HOME/.espressif/tools/riscv32-esp-elf/*/riscv32-esp-elf/bin/riscv32-esp-elf-gcc 2>/dev/null | head -1); \
	if [ -n "$$RV" ]; then \
	  $$RV -nostartfiles -Wl,-e,main /tmp/test_emit_obj_shim.c /tmp/test_emit_obj_rv.o -o /tmp/test_emit_obj_rv.elf && echo "riscv32 .o links ok"; \
	else echo "riscv32-esp-elf-gcc not installed; link check skipped"; fi
	@XT=$$(ls $$HOME/.espressif/tools/xtensa-esp-elf/*/xtensa-esp-elf/bin/xtensa-esp32s3-elf-gcc 2>/dev/null | head -1); \
	if [ -n "$$XT" ]; then \
	  $$XT -nostartfiles -Wl,-e,main /tmp/test_emit_obj_shim.c /tmp/test_emit_obj_xt.o -o /tmp/test_emit_obj_xt.elf && echo "xtensa .o links ok"; \
	  $$XT -nostartfiles -Wl,-e,main /tmp/test_emit_obj_shim.c /tmp/test_emit_obj_xt_windowed.o -o /tmp/test_emit_obj_xt_windowed.elf && echo "xtensa windowed .o links ok"; \
	else echo "xtensa-esp32s3-elf-gcc not installed; link check skipped"; fi
	@echo "emit-obj ok (ET_REL sections/symbols/relocs sane on riscv32 + xtensa call0/windowed)"

# Bare-metal ESP32 boot (feature-esp32-bare-boot). Links a self-contained
# ET_EXEC at the SoC SRAM map (--esp-profile=bare), boots it directly under the
# Espressif qemu fork via `-kernel` (no ESP-IDF), and diffs the raw UART output
# against the x86-64 oracle run. Each chip is skipped when its Espressif qemu is
# absent (they are not part of the base toolchain). esp32c3=riscv32, esp32s3=xtensa.
test-esp-bare: $(COMPILER)
	@./$(COMPILER) test/test_esp_bare.pas /tmp/test_esp_bare_oracle >/dev/null && /tmp/test_esp_bare_oracle > /tmp/test_esp_bare.oracle
	@RV=$$(ls $$HOME/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1); \
	if [ -z "$$RV" ]; then echo "Espressif qemu-system-riscv32 not installed; esp32c3 bare-boot run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32c3 test/test_esp_bare.pas > /tmp/test_esp_bare.c3 2>/dev/null; \
	  if diff -u /tmp/test_esp_bare.oracle /tmp/test_esp_bare.c3; then echo "esp32c3 bare-boot ok (UART output == x86-64 oracle)"; \
	  else echo "esp32c3 bare-boot MISMATCH"; exit 1; fi; fi
	@XT=$$(ls $$HOME/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1); \
	if [ -z "$$XT" ]; then echo "Espressif qemu-system-xtensa not installed; esp32s3 bare-boot run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32s3 test/test_esp_bare.pas > /tmp/test_esp_bare.s3 2>/dev/null; \
	  if diff -u /tmp/test_esp_bare.oracle /tmp/test_esp_bare.s3; then echo "esp32s3 bare-boot ok (UART output == x86-64 oracle)"; \
	  else echo "esp32s3 bare-boot MISMATCH"; exit 1; fi; fi
	@./$(COMPILER) test/test_esp_bare_largeframe.pas /tmp/test_esp_bare_lf_oracle >/dev/null && /tmp/test_esp_bare_lf_oracle > /tmp/test_esp_bare_lf.oracle
	@XT=$$(ls $$HOME/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1); \
	if [ -z "$$XT" ]; then echo "Espressif qemu-system-xtensa not installed; esp32s3 large-frame run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32s3 test/test_esp_bare_largeframe.pas > /tmp/test_esp_bare_lf.s3 2>/dev/null; \
	  if diff -u /tmp/test_esp_bare_lf.oracle /tmp/test_esp_bare_lf.s3; then echo "esp32s3 call0 large-frame ok (>128B frame via ADDMI == x86-64 oracle)"; \
	  else echo "esp32s3 call0 large-frame MISMATCH"; exit 1; fi; fi
	@./$(COMPILER) test/test_esp_varparam.pas /tmp/test_esp_varparam_oracle >/dev/null && /tmp/test_esp_varparam_oracle > /tmp/test_esp_varparam.oracle
	@RV=$$(ls $$HOME/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1); \
	if [ -z "$$RV" ]; then echo "Espressif qemu-system-riscv32 not installed; esp32c3 var-param run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32c3 test/test_esp_varparam.pas > /tmp/test_esp_varparam.c3 2>/dev/null; \
	  if diff -u /tmp/test_esp_varparam.oracle /tmp/test_esp_varparam.c3; then echo "esp32c3 var->var forwarding ok (UART output == x86-64 oracle)"; \
	  else echo "esp32c3 var->var forwarding MISMATCH"; exit 1; fi; fi
	@XT=$$(ls $$HOME/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1); \
	if [ -z "$$XT" ]; then echo "Espressif qemu-system-xtensa not installed; esp32s3 var-param run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32s3 test/test_esp_varparam.pas > /tmp/test_esp_varparam.s3 2>/dev/null; \
	  if diff -u /tmp/test_esp_varparam.oracle /tmp/test_esp_varparam.s3; then echo "esp32s3 var->var forwarding ok (UART output == x86-64 oracle)"; \
	  else echo "esp32s3 var->var forwarding MISMATCH"; exit 1; fi; fi
	@./$(COMPILER) test/test_esp_record_result.pas /tmp/test_esp_record_result_oracle >/dev/null && /tmp/test_esp_record_result_oracle > /tmp/test_esp_record_result.oracle
	@RV=$$(ls $$HOME/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1); \
	if [ -z "$$RV" ]; then echo "Espressif qemu-system-riscv32 not installed; esp32c3 record-result run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32c3 test/test_esp_record_result.pas > /tmp/test_esp_record_result.c3 2>/dev/null; \
	  if diff -u /tmp/test_esp_record_result.oracle /tmp/test_esp_record_result.c3; then echo "esp32c3 record copy + by-value results ok (UART output == x86-64 oracle)"; \
	  else echo "esp32c3 record result MISMATCH"; exit 1; fi; fi
	@XT=$$(ls $$HOME/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1); \
	if [ -z "$$XT" ]; then echo "Espressif qemu-system-xtensa not installed; esp32s3 record-result run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32s3 test/test_esp_record_result.pas > /tmp/test_esp_record_result.s3 2>/dev/null; \
	  if diff -u /tmp/test_esp_record_result.oracle /tmp/test_esp_record_result.s3; then echo "esp32s3 (Call0) record copy + by-value results ok (UART output == x86-64 oracle)"; \
	  else echo "esp32s3 record result MISMATCH"; exit 1; fi; fi
	@./$(COMPILER) test/test_esp_exception.pas /tmp/test_esp_exception_oracle >/dev/null && /tmp/test_esp_exception_oracle > /tmp/test_esp_exception.oracle
	@RV=$$(ls $$HOME/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1); \
	if [ -z "$$RV" ]; then echo "Espressif qemu-system-riscv32 not installed; esp32c3 exception run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32c3 test/test_esp_exception.pas > /tmp/test_esp_exception.c3 2>/dev/null; \
	  if diff -u /tmp/test_esp_exception.oracle /tmp/test_esp_exception.c3; then echo "esp32c3 try/except/finally ok (UART output == x86-64 oracle)"; \
	  else echo "esp32c3 exception MISMATCH"; exit 1; fi; fi
	@XT=$$(ls $$HOME/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1); \
	if [ -z "$$XT" ]; then echo "Espressif qemu-system-xtensa not installed; esp32s3 exception run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32s3 test/test_esp_exception.pas > /tmp/test_esp_exception.s3 2>/dev/null; \
	  if diff -u /tmp/test_esp_exception.oracle /tmp/test_esp_exception.s3; then echo "esp32s3 (Call0) try/except/finally ok (UART output == x86-64 oracle)"; \
	  else echo "esp32s3 exception MISMATCH"; exit 1; fi; fi
	@./$(COMPILER) test/test_esp_class.pas /tmp/test_esp_class_oracle >/dev/null && /tmp/test_esp_class_oracle > /tmp/test_esp_class.oracle
	@RV=$$(ls $$HOME/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1); \
	if [ -z "$$RV" ]; then echo "Espressif qemu-system-riscv32 not installed; esp32c3 class run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32c3 test/test_esp_class.pas > /tmp/test_esp_class.c3 2>/dev/null; \
	  if diff -u /tmp/test_esp_class.oracle /tmp/test_esp_class.c3; then echo "esp32c3 class + virtual dispatch ok (UART output == x86-64 oracle)"; \
	  else echo "esp32c3 class MISMATCH"; exit 1; fi; fi
	@XT=$$(ls $$HOME/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1); \
	if [ -z "$$XT" ]; then echo "Espressif qemu-system-xtensa not installed; esp32s3 class run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32s3 test/test_esp_class.pas > /tmp/test_esp_class.s3 2>/dev/null; \
	  if diff -u /tmp/test_esp_class.oracle /tmp/test_esp_class.s3; then echo "esp32s3 class + virtual dispatch ok (UART output == x86-64 oracle)"; \
	  else echo "esp32s3 class MISMATCH"; exit 1; fi; fi
	@./$(COMPILER) test/test_esp_procvar.pas /tmp/test_esp_procvar_oracle >/dev/null && /tmp/test_esp_procvar_oracle > /tmp/test_esp_procvar.oracle
	@RV=$$(ls $$HOME/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1); \
	if [ -z "$$RV" ]; then echo "Espressif qemu-system-riscv32 not installed; esp32c3 procvar run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32c3 test/test_esp_procvar.pas > /tmp/test_esp_procvar.c3 2>/dev/null; \
	  if diff -u /tmp/test_esp_procvar.oracle /tmp/test_esp_procvar.c3; then echo "esp32c3 proc-var indirect call ok (UART output == x86-64 oracle)"; \
	  else echo "esp32c3 procvar MISMATCH"; exit 1; fi; fi
	@XT=$$(ls $$HOME/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1); \
	if [ -z "$$XT" ]; then echo "Espressif qemu-system-xtensa not installed; esp32s3 procvar run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32s3 test/test_esp_procvar.pas > /tmp/test_esp_procvar.s3 2>/dev/null; \
	  if diff -u /tmp/test_esp_procvar.oracle /tmp/test_esp_procvar.s3; then echo "esp32s3 (Call0) proc-var indirect call ok (UART output == x86-64 oracle)"; \
	  else echo "esp32s3 procvar MISMATCH"; exit 1; fi; fi
	@$(MAKE) --no-print-directory test-esp-softfloat

# Runtime 64-bit-integer gate for the ESP backends: the soft-float library is
# almost entirely Int64 math, so it doubles as the proof that runtime 64-bit
# arithmetic (add/sub/mul/div/mod/shifts/compares + Int64 params/returns) works
# on BOTH ESP backends. The same kernel source runs on the x86-64 oracle and on
# the riscv32 (esp32c3) + xtensa (esp32s3) QEMU targets; any output mismatch
# means a 64-bit op miscompiles. Each chip is skipped when its Espressif qemu is
# absent. (feature-esp-int64-arith)
test-esp-softfloat: $(COMPILER)
	@./$(COMPILER) test/test_esp_softfloat_probe.pas /tmp/test_esp_softfloat_oracle >/dev/null && /tmp/test_esp_softfloat_oracle > /tmp/test_esp_softfloat.oracle
	@RV=$$(ls $$HOME/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1); \
	if [ -z "$$RV" ]; then echo "Espressif qemu-system-riscv32 not installed; esp32c3 softfloat run skipped"; else \
	  ESP_RUN_TIMEOUT=12 tools/esp_run_bare.sh --chip esp32c3 test/test_esp_softfloat_probe.pas > /tmp/test_esp_softfloat.c3 2>/dev/null; \
	  if diff -u /tmp/test_esp_softfloat.oracle /tmp/test_esp_softfloat.c3; then echo "esp32c3 softfloat/int64 ok (UART output == x86-64 oracle)"; \
	  else echo "esp32c3 softfloat/int64 MISMATCH"; exit 1; fi; fi
	@XT=$$(ls $$HOME/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1); \
	if [ -z "$$XT" ]; then echo "Espressif qemu-system-xtensa not installed; esp32s3 softfloat run skipped"; else \
	  ESP_RUN_TIMEOUT=12 tools/esp_run_bare.sh --chip esp32s3 test/test_esp_softfloat_probe.pas > /tmp/test_esp_softfloat.s3 2>/dev/null; \
	  if diff -u /tmp/test_esp_softfloat.oracle /tmp/test_esp_softfloat.s3; then echo "esp32s3 softfloat/int64 ok (UART output == x86-64 oracle)"; \
	  else echo "esp32s3 softfloat/int64 MISMATCH"; exit 1; fi; fi

# Cross-target test environment sanity (chore-qemu-test-env). Manual target:
# joins 'make test' when the first cross backend exists. Validates the runner
# indirection on the native path, then proves each planned target arch
# actually EXECUTES under emulation via a minimal exit(42) probe ELF
# (an installed emulator can still be broken; --version proves nothing).
qemu-env-check: $(COMPILER)
	./$(COMPILER) test/hello.pas /tmp/qemu_env_hello
	test "$$(tools/run_target.sh x86_64 /tmp/qemu_env_hello)" = "Hello, World!"
	@echo "runner ok (native x86_64 path)"
	@fail=0; for a in i386 aarch64 arm32; do \
	  python3 tools/gen_arch_probe.py $$a /tmp/qemu_probe_$$a; \
	  chmod +x /tmp/qemu_probe_$$a; \
	  if tools/run_target.sh $$a /tmp/qemu_probe_$$a; then rc=0; else rc=$$?; fi; \
	  if [ "$$rc" = 42 ]; then \
	    echo "ok: $$a probe (exit 42 via runner)"; \
	  else \
	    echo "FAIL: $$a probe (exit $$rc, expected 42)"; fail=1; \
	  fi; \
	done; exit $$fail


# ---------------------------------------------------------------------------
# The TEST LADDER (chore-fast-pin-tiered-tests) — run the cheapest tier that
# covers what you touched; do NOT run the full suite every iteration:
#
#   make test-quick   (~3s)  inner loop. Curated regression-prone programs
#                            against the CURRENT binary — no self-host, no
#                            rebuild. Run after almost every edit.
#   make test-smoke  (~25s)  before a commit. = test-quick + the full 3-stage
#                            self-host byte-identity chain (catches self-host
#                            miscompiles a runtime pass can't). The iteration
#                            gate for compiler changes.
#   make test        (2m+)   before a pin / push of batched work. Full core +
#                            threads + asm + debug-g suite.
#   make stabilize / cross   releases, ABI/ELF/backend changes, all targets.
#
# New features append a case to test-quick (if runtime-observable) AND to their
# full-suite test.
# ---------------------------------------------------------------------------

# test-quick: fastest inner-loop gate — curated programs, current binary only.
test-quick: $(COMPILER)
	./$(COMPILER) test/test_dynarray_torture.pas /tmp/smoke_dyntorture26
	test "$$(/tmp/smoke_dyntorture26 | tail -1)" = "total ok 27 / 27"
	./$(COMPILER) test/test_dynarray_insert_delete.pas /tmp/smoke_dynid26
	test "$$(/tmp/smoke_dynid26 | tail -1)" = "total ok 35 / 35"
	./$(COMPILER) test/test_frozen_string_reentrant.pas /tmp/smoke_frozen26
	test "$$(/tmp/smoke_frozen26 | tail -1)" = "total ok 4 / 4"
	./$(COMPILER) test/test_ansistring.pas /tmp/smoke_ansistr26
	test "$$(/tmp/smoke_ansistr26)" = "$$(printf '0\nInitially empty ok\nHello\n5\nHello\nAssignment equal ok\nhello\nHello\nCOW index write ok\nLocalString\n11\nLocal equal ok\nX\nChar assign ok\nHello World!\nHello\nHello World!\n0\nClear empty ok')"
	./$(COMPILER) test/test_class_of.pas /tmp/smoke_classof26
	test "$$(/tmp/smoke_classof26)" = "TChild"
	./$(COMPILER) test/test_metaclass_construct.pas /tmp/smoke_metactor26
	test "$$(/tmp/smoke_metactor26)" = "$$(printf '50\n70\n3')"
	./$(COMPILER) test/test_cross_exception.pas /tmp/smoke_exc26
	test "$$(/tmp/smoke_exc26 | wc -l)" = "9"
	./$(COMPILER) test/test_record_temp_byval_arg.pas /tmp/smoke_recbyval26
	test "$$(/tmp/smoke_recbyval26)" = "$$(printf '18\n46')"
	./$(COMPILER) test/test_const_record_method_prebody.pas /tmp/smoke_crmp26
	test "$$(/tmp/smoke_crmp26 | tail -1)" = "OK"
	./$(COMPILER) --threadsafe test/test_mutex.pas /tmp/smoke_mutex26
	test "$$(/tmp/smoke_mutex26 | tail -1)" = "MUTEX OK"
	./$(COMPILER) --threadsafe test/test_tthread_sync.pas /tmp/smoke_tthread26
	test "$$(/tmp/smoke_tthread26 | tail -1)" = "TTHREAD SYNC OK"

# test-smoke: the pre-commit iteration gate = test-quick + the full self-host
# byte-identity chain (the artifacts stabilize-core pins). Catches self-host
# miscompiles that a runtime-only pass cannot (see
# bug-selfhost-multifn-ifelse-miscompile).
test-smoke: test-quick
	# self-host byte-identity chain (the artifacts stabilize-core pins)
	./$(COMPILER) $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-self
	/tmp/pascal26-self $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-next
	/tmp/pascal26-next test/bootstrap_features.pas /tmp/smoke_boot26
	test "$$(/tmp/smoke_boot26)" = "$$(printf '120\n98\ncase-ok\n0')"
	/tmp/pascal26-next $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-fixedpoint
	cmp /tmp/pascal26-next /tmp/pascal26-fixedpoint
	cp /tmp/pascal26-fixedpoint /tmp/pascal26-s5

# test-opt: the -O gate (feature-optimization-levels). Differential corpus —
# every program compiled at -O0 and -O1 must produce IDENTICAL runtime
# output — plus the -O1 self-compile fixedpoint. Run whenever an opt pass
# changes; -O0 stays covered by the ordinary byte-identity gates.
test-opt: $(COMPILER)
	for t in test_dynarray_torture test_dynarray_insert_delete \
	         test_frozen_string_reentrant test_ansistring bootstrap_features \
	         records procs test_cross_exception test_math_unit \
	         test_metaclass_construct test_const_record_method_prebody \
	         test_inline_expand test_conformance_1 test_conformance_2 \
	         test_class_is_as test_const_set test_cast_string \
	         test_call_result_member strings test_char_to_string \
	         test_cross_ptr_arith test_anonymous_record \
	         test_exc_resident_param; do \
	  ./$(COMPILER) test/$$t.pas /tmp/opt0_$$t >/dev/null && \
	  ./$(COMPILER) -O1 test/$$t.pas /tmp/opt1_$$t >/dev/null && \
	  ./$(COMPILER) -O2 test/$$t.pas /tmp/opt2_$$t >/dev/null && \
	  ./$(COMPILER) -O3 test/$$t.pas /tmp/opt3_$$t >/dev/null && \
	  /tmp/opt0_$$t > /tmp/opt0_$$t.out && /tmp/opt1_$$t > /tmp/opt1_$$t.out && \
	  /tmp/opt2_$$t > /tmp/opt2_$$t.out && /tmp/opt3_$$t > /tmp/opt3_$$t.out && \
	  cmp -s /tmp/opt0_$$t.out /tmp/opt1_$$t.out || { echo "OPT DIFF O1: $$t"; exit 1; }; \
	  cmp -s /tmp/opt0_$$t.out /tmp/opt2_$$t.out || { echo "OPT DIFF O2: $$t"; exit 1; }; \
	  cmp -s /tmp/opt0_$$t.out /tmp/opt3_$$t.out || { echo "OPT DIFF O3: $$t"; exit 1; }; \
	done
	./$(COMPILER) --threadsafe test/test_atomic64.pas /tmp/opt0_atomic64 >/dev/null
	./$(COMPILER) -O1 --threadsafe test/test_atomic64.pas /tmp/opt1_atomic64 >/dev/null
	/tmp/opt0_atomic64 > /tmp/opt0_a64.out; /tmp/opt1_atomic64 > /tmp/opt1_a64.out
	cmp /tmp/opt0_a64.out /tmp/opt1_a64.out
	# -O1 self-compile fixedpoint: an -O1-built compiler rebuilding itself at
	# -O1 must reach byte-identity too
	./$(COMPILER) -O1 $(COMPILER_SRC) /tmp/pascal26-o1a
	/tmp/pascal26-o1a -O1 $(COMPILER_SRC) /tmp/pascal26-o1b
	/tmp/pascal26-o1b -O1 $(COMPILER_SRC) /tmp/pascal26-o1c
	cmp /tmp/pascal26-o1b /tmp/pascal26-o1c
	# -O2 self-compile fixedpoint (register calling convention, feature-callconv-
	# register-args): an -O2-built compiler rebuilding itself at -O2 reaches
	# byte-identity too. Gates the r14/r15 param-residency codegen.
	./$(COMPILER) -O2 $(COMPILER_SRC) /tmp/pascal26-o2a
	/tmp/pascal26-o2a -O2 $(COMPILER_SRC) /tmp/pascal26-o2b
	/tmp/pascal26-o2b -O2 $(COMPILER_SRC) /tmp/pascal26-o2c
	cmp /tmp/pascal26-o2b /tmp/pascal26-o2c
	# -O2 now carries the W1 mirror / leaf-index fold / last-arg collapse
	# (promoted 2026-07-11 after a 564-program -O0-vs differential). -O3 keeps
	# the register-lifetime passes (r8-r13 scratch, loop/float residency); an
	# -O3-built compiler rebuilding itself at -O3 must reach byte-identity too.
	./$(COMPILER) -O3 $(COMPILER_SRC) /tmp/pascal26-o3a
	/tmp/pascal26-o3a -O3 $(COMPILER_SRC) /tmp/pascal26-o3b
	/tmp/pascal26-o3b -O3 $(COMPILER_SRC) /tmp/pascal26-o3c
	cmp /tmp/pascal26-o3b /tmp/pascal26-o3c
	@echo "test-opt OK (differential corpus + -O1/-O2 fixedpoint)"

# stabilize-fast: everyday iteration pin — test-smoke instead of the full
# suite, and the already-proven fixedpoint binary is recorded directly (the
# full target's s4/s5 re-derivations only re-prove what cmp(next,fixedpoint)
# established). Policy: fine for iteration; run full `stabilize` before
# pushing a batch / milestone pins / releases.
stabilize-fast: test-smoke
	$(MAKE) stabilize-record

stabilize: test
	@echo "=== stabilize: 4-iteration fixedpoint check ==="
	/tmp/pascal26-fixedpoint $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-s4
	cmp /tmp/pascal26-next /tmp/pascal26-s4
	/tmp/pascal26-s4 $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-s5
	cmp /tmp/pascal26-next /tmp/pascal26-s5
	$(MAKE) stabilize-record

stabilize-record:
	@echo "=== recording stable binary ==="
	@mkdir -p $(STABLE_DEFAULT_DIR)
	@# Fixed-name overwrite (no per-version vN files): `latest` is a symlink to the
	@# single, in-place-overwritten `stable_latest` binary. VERSION stays a
	@# monotonic counter for reporting/provenance; history.log carries date + sha +
	@# source commit per checkpoint. See
	@# devdocs/progress/.../chore-stable-binary-single-file-no-version-churn.md.
	@NV=$$(( $$(cat $(STABLE_DEFAULT_DIR)/VERSION 2>/dev/null || echo 0) + 1 )); \
	 echo $$NV > $(STABLE_DEFAULT_DIR)/VERSION; \
	 cp /tmp/pascal26-s5 $(STABLE_DEFAULT_DIR)/stable_latest; \
	 ln -sfn stable_latest $(STABLE_DEFAULT_DIR)/latest; \
	 SHA=$$(sha256sum $(STABLE_DEFAULT_DIR)/latest | awk '{print $$1}'); \
	 echo "$$SHA  latest" > $(STABLE_DEFAULT_DIR)/last.sha256; \
	 printf '%s  v%s  %s  %s  %s\n' \
	   "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$NV" "$$SHA" \
	   "$$(git log -1 --format='%H')" \
	   "$$(git log -1 --format='%s')" \
	   >> $(STABLE_DEFAULT_DIR)/history.log; \
	 echo "STABLE v$$NV OK: $$SHA  (-> stable_latest, fixed-name overwrite)"

stabilize-managed: COMPILER := $(COMPILER_MANAGED)
stabilize-managed: PXXFLAGS := -dPXX_MANAGED_STRING
stabilize-managed: test-managed
	@echo "=== stabilize-managed: 4-iteration fixedpoint check ==="
	/tmp/pascal26-fixedpoint $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-s4
	cmp /tmp/pascal26-next /tmp/pascal26-s4
	/tmp/pascal26-s4 $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-s5
	cmp /tmp/pascal26-next /tmp/pascal26-s5
	@echo "=== recording stable managed binary ==="
	@mkdir -p $(STABLE_MANAGED_DIR)
	@NV=$$(( $$(cat $(STABLE_MANAGED_DIR)/VERSION 2>/dev/null || echo 0) + 1 )); \
	 echo $$NV > $(STABLE_MANAGED_DIR)/VERSION; \
	 cp /tmp/pascal26-s5 $(STABLE_MANAGED_DIR)/v$$NV; \
	 ln -sfn v$$NV $(STABLE_MANAGED_DIR)/latest; \
	 SHA=$$(sha256sum $(STABLE_MANAGED_DIR)/latest | awk '{print $$1}'); \
	 echo "$$SHA  latest" > $(STABLE_MANAGED_DIR)/last.sha256; \
	 printf '%s  v%s  %s  %s  %s\n' \
	   "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$NV" "$$SHA" \
	   "$$(git log -1 --format='%H')" \
	   "$$(git log -1 --format='%s')" \
	   >> $(STABLE_MANAGED_DIR)/history.log; \
	 echo "STABLE MANAGED v$$NV OK: $$SHA"

stabilize-frozen: PXXFLAGS := $(FROZEN_PXXFLAGS)
stabilize-frozen: stabilize

check-stable:
	@test -e $(STABLE_DEFAULT_DIR)/latest || \
	  (echo "No stable binary. Run: make stabilize"; exit 1)
	@(cd $(STABLE_DEFAULT_DIR) && sha256sum -c last.sha256) && \
	  echo "Stable v$$(cat $(STABLE_DEFAULT_DIR)/VERSION) OK: $$(cat $(STABLE_DEFAULT_DIR)/last.sha256)" || \
	  (echo "MISMATCH: stable binary does not match last.sha256"; exit 1)

# Light CI self-check -- NO fpc, NO qemu, seconds not minutes. Seeds from the
# committed native stable binary instead of rebuilding it from FPC, self-hosts
# the current source to a fixedpoint, and runs a compiled hello to prove the
# binary executes. The pinned seed usually lags HEAD by one codegen generation,
# so convergence is checked as g2 == g3 (a single g1 == g2 would false-fail
# right after any codegen change). The full release-grade gate -- FPC bootstrap,
# full determinism, and cross-target byte-identity -- stays in `make test` +
# `make cross-bootstrap`, run by the release workflow.
selfcheck: check-stable
	@test -x $(PXX_STABLE) || (echo "No executable stable at $(PXX_STABLE)"; exit 1)
	@echo "=== selfcheck: self-host from committed stable $(PXX_STABLE) ==="
	$(PXX_STABLE) $(COMPILER_SRC) /tmp/pxx-sc-g1
	/tmp/pxx-sc-g1 $(COMPILER_SRC) /tmp/pxx-sc-g2
	/tmp/pxx-sc-g2 $(COMPILER_SRC) /tmp/pxx-sc-g3
	cmp /tmp/pxx-sc-g2 /tmp/pxx-sc-g3
	@echo "self-host fixedpoint OK (g2 == g3)"
	/tmp/pxx-sc-g1 test/hello.pas /tmp/pxx-sc-hello
	test "$$(/tmp/pxx-sc-hello)" = "Hello, World!"
	@echo "=== selfcheck OK ==="

check-stable-managed:
	@test -e $(STABLE_MANAGED_DIR)/latest || \
	  (echo "No stable managed binary. Run: make stabilize-managed"; exit 1)
	@(cd $(STABLE_MANAGED_DIR) && sha256sum -c last.sha256) && \
	  echo "Stable managed v$$(cat $(STABLE_MANAGED_DIR)/VERSION) OK: $$(cat $(STABLE_MANAGED_DIR)/last.sha256)" || \
	  (echo "MISMATCH: stable managed binary does not match last.sha256"; exit 1)

revert:
	@V=$$(cat $(STABLE_DEFAULT_DIR)/VERSION); \
	 TV=$${VERSION:-$$((V-1))}; \
	 test "$$TV" -ge 1 2>/dev/null || (echo "Usage: make revert VERSION=N"; exit 1); \
	 test "$$TV" -le "$$V" || (echo "v$$TV does not exist (current is v$$V)"; exit 1); \
	 test -f $(STABLE_DEFAULT_DIR)/v$$TV || \
	   (echo "Binary $(STABLE_DEFAULT_DIR)/v$$TV missing — may need to rebuild from that commit"; exit 1); \
	 cp $(STABLE_DEFAULT_DIR)/v$$TV $(COMPILER); \
	 echo "Reverted $(COMPILER) to stable v$$TV (was v$$V)"; \
	 echo "Run 'make test' to verify, or 'make stabilize' to record as new stable."

revert-managed:
	@V=$$(cat $(STABLE_MANAGED_DIR)/VERSION); \
	 TV=$${VERSION:-$$((V-1))}; \
	 test "$$TV" -ge 1 2>/dev/null || (echo "Usage: make revert-managed VERSION=N"; exit 1); \
	 test "$$TV" -le "$$V" || (echo "v$$TV does not exist (current is v$$V)"; exit 1); \
	 test -f $(STABLE_MANAGED_DIR)/v$$TV || \
	   (echo "Binary $(STABLE_MANAGED_DIR)/v$$TV missing — may need to rebuild from that commit"; exit 1); \
	 cp $(STABLE_MANAGED_DIR)/v$$TV $(COMPILER_MANAGED); \
	 echo "Reverted $(COMPILER_MANAGED) to stable managed v$$TV (was v$$V)"; \
	 echo "Run 'make test-managed' to verify, or 'make stabilize-managed' to record as new stable."

clean:
	rm -f compiler/*.o compiler/*.ppu
	rm -f $(COMPILER_MANAGED)
	rm -f $(BUILD_COMPILER_MANAGED) $(VERIFY_COMPILER_MANAGED)

distclean: clean
	rm -f $(COMPILER)

# ============================================================================
# Library / demo track (Claude B). These build against the PINNED stable
# compiler ($(PXX_STABLE)), NOT the in-flux compiler/pascal26, so library and
# demo-app work is decoupled from compiler churn. NEITHER target is the
# authoritative gate -- that stays `make test` + self-host fixedpoint. They are
# discovery/smoke harnesses: when they surface missing or bugged library or
# language support, file a ticket (devdocs/progress/backlog) rather than treating
# the red as a hard CI failure. See devdocs/dev/parallel-tracks.md.
# ============================================================================

# Guard + report which stable the library track is pinned to.
pxx-stable-check:
	@test -x $(PXX_STABLE) || \
	  (echo "No pinned stable at $(PXX_STABLE). Run: make stabilize && make pin"; exit 1)
	@PV=$$(readlink $(STABLE_DEFAULT_DIR)/pinned 2>/dev/null || echo '?'); \
	 LV=$$(readlink $(STABLE_DEFAULT_DIR)/latest 2>/dev/null || echo '?'); \
	 echo "lib track pinned to: $(PXX_STABLE) -> $$PV   (newest checkpoint: latest -> $$LV)"; \
	 if [ -d $(STABLE_DEFAULT_DIR)/builtin ]; then \
	   echo "frozen builtin RTL: $(STABLE_DEFAULT_DIR)/builtin/ ($$(ls $(STABLE_DEFAULT_DIR)/builtin/*.pas 2>/dev/null | wc -l) src) -- isolates track A's compiler/builtin/ edits"; \
	 else \
	   echo "WARNING: no frozen builtin RTL ($(STABLE_DEFAULT_DIR)/builtin/ missing); pinned binary reads LIVE compiler/builtin/. Run 'make pin' to freeze."; \
	 fi; \
	 if [ "$$PV" != "$$LV" ] && [ "$$PXX_STABLE" = "$(STABLE_DEFAULT_DIR)/pinned" ]; then \
	   echo "note: a newer stable ($$LV) exists than the pinned one ($$PV)."; \
	   echo "      track A can bless it for B with 'make pin'."; \
	 fi

# Advance the stable that track B builds against (PXX_STABLE -> pinned). Blesses
# the current `latest` checkpoint by copying it onto the single `stable_pinned`
# binary (the `pinned` symlink points there permanently). This is the deliberate
# 'hand B a new compiler' step, separate from `make stabilize` (which only
# overwrites `stable_latest`). Records the move in pin.log for audit.
# (No per-version vN files / VERSION=N selection -- mid-dev we only keep the
# latest; old stables live in git history, see STABLES.md.)
pin:
	@test -e $(STABLE_DEFAULT_DIR)/stable_latest || \
	  (echo "No stable yet. Run: make stabilize"; exit 1)
	@NV=$$(cat $(STABLE_DEFAULT_DIR)/VERSION 2>/dev/null || echo '?'); \
	 OLDSHA=$$(test -e $(STABLE_DEFAULT_DIR)/pinned && sha256sum $(STABLE_DEFAULT_DIR)/pinned | awk '{print substr($$1,1,12)}' || echo 'none'); \
	 cp $(STABLE_DEFAULT_DIR)/stable_latest $(STABLE_DEFAULT_DIR)/stable_pinned; \
	 ln -sfn stable_pinned $(STABLE_DEFAULT_DIR)/pinned; \
	 SHA=$$(sha256sum $(STABLE_DEFAULT_DIR)/pinned | awk '{print $$1}'); \
	 printf '%s  pinned v%s  %s  (was %s)  %s\n' \
	   "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$NV" "$$SHA" "$$OLDSHA" \
	   "$$(git log -1 --format='%H' 2>/dev/null)" \
	   >> $(STABLE_DEFAULT_DIR)/pin.log; \
	 echo "pinned -> stable_pinned (v$$NV, $$SHA)."
	@# Freeze the runtime-read builtin RTL next to the pinned binary. The pinned
	@# binary resolves `uses builtinheap`/`builtin` via its ExeDir, i.e.
	@# $(STABLE_DEFAULT_DIR)/builtin/, which is checked BEFORE the CWD-relative
	@# fallback to the live compiler/builtin/. Snapshotting here closes the
	@# isolation hole where track A's uncommitted edits in compiler/builtin/**
	@# (its own lane) leaked into track B's pinned compiles. lib/rtl + lib/pcl are
	@# deliberately NOT frozen -- they are track B's own editable lane, which B
	@# expects live. See devdocs/progress/backlog/bug-pinned-stable-reads-live-builtin-rtl.md.
	@rm -rf $(STABLE_DEFAULT_DIR)/builtin
	@mkdir -p $(STABLE_DEFAULT_DIR)/builtin
	@cp compiler/builtin/*.pas $(STABLE_DEFAULT_DIR)/builtin/
	@echo "froze $$(ls $(STABLE_DEFAULT_DIR)/builtin/*.pas | wc -l) builtin RTL source(s) -> $(STABLE_DEFAULT_DIR)/builtin/"
	@echo "Hand to track B:  git add -u stable_linux_amd64/ && git commit -m 'chore(stable): pin vN' -- stable_linux_amd64/"
	@echo "  (-u stages the in-place-overwritten stable_pinned/stable_latest; all stable files are tracked, so nothing can dangle.)"

# Curated GREEN smoke for the library surface, against the pinned stable. May
# hard-fail (a smoke gate for track B). Keep every entry here passing; move
# anything broken to a ticket instead of letting this go red.
lib-test: pxx-stable-check
	@echo "=== lib-test: library smoke against $(PXX_STABLE) ==="
	$(PXX_STABLE) examples/sudoku/sudoku.pas /tmp/lib_sudoku
	test "$$(/tmp/lib_sudoku)" = "$$(printf '534678912672195348198342567859761423426853791713924856961537284287419635345286179\n987654321246173985351928746128537694634892157795461832519286473472319568863745219\n812753649943682175675491283154237896369845721287169534521974368438526917796318452')"
	$(PXX_STABLE) -dPXX_MANAGED_STRING test/test_collections.pas /tmp/lib_collections
	@test -n "$$(/tmp/lib_collections)" || (echo "lib smoke: collections produced no output"; exit 1)
	/tmp/lib_collections >/dev/null
	$(PXX_STABLE) test/test_math.pas /tmp/lib_math
	/tmp/lib_math >/dev/null
	$(PXX_STABLE) test/lib_sysutils.pas /tmp/lib_sysutils
	test "$$(/tmp/lib_sysutils)" = "$$(printf '0\n-123456789\n10000000000\nhello\nworld\n[]\n[pad]\n42\n-7\n-1\n100\nQ\n7\nAB3Z\nab3z\nhello\nab\nbcde\nabcde\nabcde\nhello world\nstart end\nstart end\nabc\nfoobar\nx\nx\nbase\n77\nderived')"
	$(PXX_STABLE) test/lib_random.pas /tmp/lib_random
	test "$$(/tmp/lib_random)" = "$$(printf '5 6 6 2 6 4 2 5 \n5 6 6 2 6 4 2 5 \n359 891 105 979 687 ')"
	# MulHiU64: intrinsic on CPU64, Pascal fallback elsewhere. The sweep
	# fingerprint is identical on every target iff the two agree bit for bit.
	$(PXX_STABLE) test/lib_wideint.pas /tmp/lib_wideint
	test "$$(/tmp/lib_wideint)" = "$$(printf 'sweep=16730136239701361245\nWIDEINT OK')"
	# P-256 field arithmetic (Montgomery/CIOS, 4x64 saturated limbs) checked
	# differentially against bignum's TBigInt mod-p arithmetic
	$(PXX_STABLE) -Fulib/rtl test/lib_p256field.pas /tmp/lib_p256field
	test "$$(/tmp/lib_p256field | tail -1)" = "P256FIELD OK"
	$(PXX_STABLE) test/lib_bignum_ops.pas /tmp/lib_bignum_ops
	test "$$(/tmp/lib_bignum_ops)" = "$$(printf 'chain=999999999999999999940000000000000001234499999999999999925930\ndiv=10000000000000000000100000000000000012352\nmod=12394\nidentity=yes\nf50=30414093201713378043612608166064768844377641568960512000000000000\np512=13407807929942597099574024998205846127479365820592393377723561443721764030073546976801874298166903427690031858186486050853753882811946569946433649006084096\nnegsub=-999999999999999999999999987655\nbackagain=12345\nzero=yes\nlt=TRUE TRUE FALSE\nle=TRUE TRUE FALSE\ngt=TRUE TRUE FALSE\nge=TRUE TRUE FALSE\neq=TRUE FALSE\nne=TRUE FALSE\nnegdiv=-2 -1\nnegidentity=yes')"
	$(PXX_STABLE) test/lib_vecmath.pas /tmp/lib_vecmath
	test "$$(/tmp/lib_vecmath)" = "$$(printf 'add=5.00 7.00 9.00\nsub=3.00 3.00 3.00\nmul=2.00 4.00 6.00\ndiv=2.00 2.50 3.00\nchain=9.00 12.00 15.00\neq3=yes\nneq3=yes\ndot3=32.00\ncrossXY=0.00 0.00 1.00\ncross=-3.00 6.00 -3.00\north1=0.00\north2=0.00\nnorm2=5.00\nnormalize2=0.60 0.80\nnormlen=1.00\nnormzero=0.00 0.00\nvmul3=4.00 10.00 18.00\nlerp3=5.00 10.00 15.00\nadd4=2.00 4.00 6.00 8.00\ndot4=30.00\nnormsq4=30.00\nmatI=yes\nm3sq=30.00 36.00 42.00\ndet3I=1.00\ndet3scale=24.00\ndet3=-3.00\ntrans3=4.00 2.00\ntransinv=yes\nmv3=6.00 15.00 25.00\ntpoint=2.00 3.00 4.00 1.00\ndet4scale=24.00\ndet4I=1.00\nst=4.00 9.00 16.00 1.00\nrotz=0.00 1.00 0.00 1.00\nrotx=0.00 0.00 1.00 1.00\ndetmul=yes')"
	$(PXX_STABLE) test/lib_ucomplex.pas /tmp/lib_ucomplex
	test "$$(/tmp/lib_ucomplex)" = "$$(printf 'chain=14.000000 2.000000\nadd=4.000000 2.000000\nsub=2.000000 6.000000\nmul=11.000000 -2.000000\ndiv=-1.000000 2.000000\neq=yes\nneq=yes\ncmod=5.000000\ncarg_i=1.570796\ncong=3.000000 -4.000000\ncinv=0.000000 -0.500000\ncsqrt-1=0.000000 1.000000\ncsqrt=2.000000 1.000000\ncexp_ipi_re=-1.000000\ncexp_ipi_im_small=TRUE\ncln_e=1.000000 0.000000\ncsqr=-7.000000 24.000000\nipow2_re=-1.000000\nipow2_im_small=TRUE\ncaddr=4.000000 4.000000\ncsubr=2.000000 4.000000\ncrsub=-2.000000 -4.000000\ncmulr=6.000000 8.000000\ncdivr=1.500000 2.000000\ncrdiv=0.000000 -1.000000\ncneg=-3.000000 -4.000000\ncdiv_fn=-1.000000 2.000000\nsincos_re=1.000000\nsincos_im_small=TRUE\nsame=TRUE\nnotsame=FALSE\ncstr=1.00-2.00i\ncstr0=1.50\ncstrp=-1.00+2.00i')"
	$(PXX_STABLE) test/lib_bitset.pas /tmp/lib_bitset
	test "$$(/tmp/lib_bitset)" = "$$(printf 'TRUE\nTRUE\nFALSE\nTRUE\nTRUE\nFALSE\nTRUE\nFALSE\nFALSE\nFALSE\nTRUE\nFALSE\n6\n5 10 70 150 \n4\n-1\n10\n70')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_platform.pas /tmp/lib_platform
	test "$$(/tmp/lib_platform)" = "$$(printf 'posix\nfiles\nsockets\nthreads\npal-write=3\nflush=0\ntell=2\nfile=io:2:2\nrename=0\nold-missing\nnew-readable\ndelete=0\nmkdir=0\nrmdir=0\nunsupported=-38')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_platform_net.pas /tmp/lib_platform_net
	test "$$(/tmp/lib_platform_net)" = "$$(printf 'tcp=ok\nunsupported=-38')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_platform_net_udp.pas /tmp/lib_platform_net_udp
	test "$$(/tmp/lib_platform_net_udp)" = "$$(printf 'poll=ok\nrecv=ok\npeer=ok\necho=ok\nunsupported=-38')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_platform_net_sockopt.pas /tmp/lib_platform_net_sockopt
	test "$$(/tmp/lib_platform_net_sockopt)" = "$$(printf 'name=ok\naccept-peer=ok\nsockerr=ok\nunsupported=-38')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_net.pas /tmp/lib_net
	test "$$(/tmp/lib_net)" = "$$(printf 'bound=ok\npeer=ok\ntcp=ok\nudp=ok')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_net_timeout.pas /tmp/lib_net_timeout
	test "$$(/tmp/lib_net_timeout)" = "$$(printf 'connect=ok\nrefused=ok\nrecv=ok\nrecv-timeout=ok')"
	$(PXX_STABLE) test/lib_dns_wire.pas /tmp/lib_dns_wire
	test "$$(/tmp/lib_dns_wire)" = "$$(printf 'qlen=29\nqhdr=ok\nqname=ok\nrcode=0\nid=ok\ncount=2\nip0=ok\nip1=ok\nminttl=ok\nq6type=ok\nrcode6=0\nid6=ok\ncount6=1\nip6=ok\ncname=ok\nnegttl=ok\nnegttl-none=ok')"
	$(PXX_STABLE) --mimic-fpc -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix test/lib_synapse.pas /tmp/lib_synapse
	test "$$(/tmp/lib_synapse)" = "$$(printf 'b64=SGVsbG8sIFdvcmxkIQ==\nb64d=Hello, World!\nmd5=900150983cd24fb0d6963f7d28e17f72\nsha1=a9993e364706816aba3e25717850c26c9cd0d89d\ncrc32=3421780262\nurl=a%%20b&c\nsrv-got=ping\ncli-got=pong')"
	$(PXX_STABLE) test/lib_dns_cache.pas /tmp/lib_dns_cache
	test "$$(/tmp/lib_dns_cache)" = "$$(printf 'hit=ok\nmiss-other=ok\nexpired=ok\nneg-hit=ok\nneg-expired=ok\nqtype-a=ok\nqtype-aaaa=ok\nreplace-val=ok\nreplace-count=ok\nttl-zero-noop=ok\nfull-live=ok\nevict-cap=ok\nevict-oldest=ok\nevict-newkept=ok\nv6-hit=ok\nv6-coexist=ok\nv6-expired=ok\nv6-neg=ok\ncn-hit=ok\ncn-coexist=ok\ncn-expired=ok\ncn-ttl-noop=ok')"
	$(PXX_STABLE) test/lib_dns_config.pas /tmp/lib_dns_config
	test "$$(/tmp/lib_dns_config)" = "$$(printf 'ip-ok=ok\nip-val=ok\nip-oversize=ok\nip-short=ok\nip-empty=ok\ncount=3\nns0=ok\nns1=ok\nns2=ok\nh-local=ok\nh-alias=ok\nh-ci=ok\nh-nofinalnl=ok\nh-comment=ok\nh-miss=ok\nex-count=3\nex-search=2\nex-s0=ok\nex-s1=ok\nex-ndots=2\nex-domain=ok\nc-rel0=ok\nc-rel1=ok\nc-rel2=ok\nc-rel3=ok\nc-abs0=ok\nc-abs1=ok\nc-root0=ok\nc-root1=ok\nip6-full=ok\nip6-comp=ok\nip6-loop=ok\nip6-any=ok\nip6-tail=ok\nip6-v4=ok\nip6-caps=ok\nip6-badgap=ok\nip6-badlen=ok\nip6-badlong=ok\nip6-badgrp=ok\nip6-badzone=ok\nip6-badcolon=ok\nip6-gapfull=ok\nip6-notv4=ok\nh6-loop=ok\nh6-host=ok\nh6-skip4=ok\nh6-miss=ok\nsv-basic=ok\nsv-ci=ok\nsv-alias=ok\nsv-anyproto=ok\nsv-udp=ok\nsv-nofinalnl=ok\nsv-protomiss=ok\nsv-miss=ok\nsv-comment-alias=ok')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_dns_resolve.pas /tmp/lib_dns_resolve
	test "$$(/tmp/lib_dns_resolve)" = "$$(printf 'rcode=0\ncount=2\nip0=ok\nip1=ok')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_dns_facade.pas /tmp/lib_dns_facade
	test "$$(/tmp/lib_dns_facade)" = "$$(printf 'hosts-hit=ok\nwire-rcode=0\nwire-count=2\nwire-ip0=ok')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_dns_spoof.pas /tmp/lib_dns_spoof
	test "$$(/tmp/lib_dns_spoof)" = "$$(printf 'badid=ok\ncount=0')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_dns_tcp.pas /tmp/lib_dns_tcp
	test "$$(/tmp/lib_dns_tcp)" = "$$(printf 'rcode=0\ncount=2\ntcp-fallback=ok')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_dns_multins.pas /tmp/lib_dns_multins
	test "$$(/tmp/lib_dns_multins)" = "$$(printf 'rcode=0\ncount=2\nmultins=ok')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_dns_chase.pas /tmp/lib_dns_chase
	test "$$(/tmp/lib_dns_chase)" = "$$(printf 'rcode=0\ncount=1\nchased=ok')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_dns_cache_facade.pas /tmp/lib_dns_cache_facade
	test "$$(/tmp/lib_dns_cache_facade)" = "$$(printf 'r1=0\nip1=ok\nr2=0\ncached=ok\nflushed-neg=ok\nc1=0\nc1-ip=ok\nc2=0\nc2-cached=ok')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_dns_aaaa.pas /tmp/lib_dns_aaaa
	test "$$(/tmp/lib_dns_aaaa)" = "$$(printf 'rcode=0\ncount=1\nip6=ok\nrcode6c=0\ncount6c=1\nchased6=ok')"
	$(PXX_STABLE) test/lib_dns_buildguard.pas /tmp/lib_dns_buildguard
	test "$$(/tmp/lib_dns_buildguard)" = "$$(printf 'toolong=ok\nno-overflow=ok\nbiglabel=ok\nemptylabel=ok\ntinybuf=ok\nfits=ok')"
	$(PXX_STABLE) test/lib_dns_parsefuzz.pas /tmp/lib_dns_parsefuzz
	test "$$(/tmp/lib_dns_parsefuzz)" = "$$(printf 'empty=ok\nshort-header=ok\nrunaway-name=ok\ntruncated-rr=ok\nan-lie=ok\nhuge-rdlen=ok\nreserved-label=ok\nmany-a-rcode=ok\nmany-a-cap=ok\ndone')"
	$(PXX_STABLE) test/lib_dns_config_fuzz.pas /tmp/lib_dns_config_fuzz
	test "$$(/tmp/lib_dns_config_fuzz)" = "$$(printf 'all-255=ok\ndots-only=ok\ntrailing-dot=ok\ntrailing-sp=ok\nfive-octets=ok\nhuge-octet=ok\nvalid-max=ok\nns-cap=ok\nbogus-nomatch=ok\nip6-skip=ok\ngood-line=ok\ndone')"
	@if command -v qemu-aarch64 >/dev/null 2>&1 && command -v qemu-arm >/dev/null 2>&1; then \
	  echo "=== lib-test cross: PAL net primitives under qemu-user (i386/aarch64/arm32) ==="; \
	  for arch in i386 aarch64 arm32; do \
	    $(PXX_STABLE) --target=$$arch -Fulib/rtl/platform/posix test/lib_net.pas /tmp/lib_net_$$arch >/dev/null; \
	    test "$$(tools/run_target.sh $$arch /tmp/lib_net_$$arch)" = "$$(printf 'bound=ok\npeer=ok\ntcp=ok\nudp=ok')" || { echo "cross lib_net FAIL on $$arch"; exit 1; }; \
	    $(PXX_STABLE) --target=$$arch -Fulib/rtl/platform/posix test/lib_net_timeout.pas /tmp/lib_nt_$$arch >/dev/null; \
	    test "$$(tools/run_target.sh $$arch /tmp/lib_nt_$$arch)" = "$$(printf 'connect=ok\nrefused=ok\nrecv=ok\nrecv-timeout=ok')" || { echo "cross net_timeout FAIL on $$arch"; exit 1; }; \
	    $(PXX_STABLE) --target=$$arch -Fulib/rtl/platform/posix test/lib_platform_net_udp.pas /tmp/lib_udp_$$arch >/dev/null; \
	    test "$$(tools/run_target.sh $$arch /tmp/lib_udp_$$arch)" = "$$(printf 'poll=ok\nrecv=ok\npeer=ok\necho=ok\nunsupported=-38')" || { echo "cross udp FAIL on $$arch"; exit 1; }; \
	    $(PXX_STABLE) --target=$$arch -Fulib/rtl/platform/posix test/lib_platform_net_sockopt.pas /tmp/lib_so_$$arch >/dev/null; \
	    test "$$(tools/run_target.sh $$arch /tmp/lib_so_$$arch)" = "$$(printf 'name=ok\naccept-peer=ok\nsockerr=ok\nunsupported=-38')" || { echo "cross sockopt FAIL on $$arch"; exit 1; }; \
	    echo "cross net ok: $$arch"; \
	  done; \
	else \
	  echo "=== lib-test cross: qemu-user not present, skipping cross-arch PAL net ==="; \
	fi
	$(PXX_STABLE) --platform=esp -Fulib/rtl/platform/esp test/lib_platform_esp.pas /tmp/lib_platform_esp
	test "$$(/tmp/lib_platform_esp)" = "$$(printf 'esp-idf\nopen=-38\nread=-38\nseek=-38\nflush=-38\ndelete=-38\nrename=-38\nmkdir=-38\nrmdir=-38\nsocket=-38\nreuse=-38\nnonblock=-38\nbind=-38\nconnect=-38\nlisten=-38\naccept=-38\nrecv=-38\nsend=-38\nshutdown=-38\nsockclose=-38\nsendto=-38\nrecvfrom=-38\npoll=-38\nsockerr=-38\nsockname=-38\nacceptip=-38\nunsupported=-38')"
	@echo "=== lib-test: esptimer (ESP-IDF timer callback surface) compiles to a riscv32 object with esp_timer imports ==="
	$(PXX_STABLE) --target=riscv32 --platform=esp -Fulib/rtl -Fulib/rtl/platform/esp examples/esp32/timer-c3/main/main.pas /tmp/lib_esptimer_rv.o >/dev/null
	@if command -v readelf >/dev/null 2>&1; then \
	  for sym in esp_timer_create esp_timer_start_periodic esp_timer_stop esp_timer_delete; do \
	    readelf -sW /tmp/lib_esptimer_rv.o | grep -q "UND $$sym" || { echo "esptimer object missing import: $$sym"; exit 1; }; \
	  done; \
	fi
	@if command -v readelf >/dev/null 2>&1; then \
	  echo "=== lib-test: esp32c3 (riscv32) PAL object imports lwIP socket symbols ==="; \
	  $(PXX_STABLE) --target=riscv32 -Fulib/rtl/platform/esp test/lib_platform_esp.pas /tmp/lib_esp_rv.o >/dev/null; \
	  for sym in lwip_socket lwip_sendto lwip_recvfrom lwip_poll lwip_getsockopt lwip_getsockname; do \
	    readelf -s /tmp/lib_esp_rv.o | grep -q "UND $$sym" || { echo "esp32c3 object missing import: $$sym"; exit 1; }; \
	  done; \
	  echo "esp32c3 lwIP imports ok"; \
	else \
	  echo "=== lib-test: readelf absent, skipping esp32c3 object lwIP smoke ==="; \
	fi
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_textfile.pas /tmp/lib_textfile
	test "$$(/tmp/lib_textfile)" = "$$(printf 'alpha\nbeta\ncount=2\nio=0')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_directory.pas /tmp/lib_directory
	test "$$(/tmp/lib_directory)" = "$$(printf 'mkdir=0\nchild=0\nlist=ok\nalpha=1\nchild=1\nalpha-file=1\nchild-dir=1\nalpha-size=1\nstat-file=1\nstat-dir=1')"
	$(PXX_STABLE) examples/bignum/factorial.pas /tmp/lib_factorial
	test "$$(/tmp/lib_factorial)" = "$$(printf '5! = 120\n10! = 3628800\n20! = 2432902008176640000\n1000! digits      = 2568\n1000! first 10    = 4023872600\n1000! trailing 0s = 249')"
	$(PXX_STABLE) examples/bignum/bigmath.pas /tmp/lib_bigmath
	test "$$(/tmp/lib_bigmath | tail -1)" = "ALL OK"
	$(PXX_STABLE) examples/json/jsondemo.pas /tmp/lib_jsondemo
	test "$$(/tmp/lib_jsondemo | tail -1)" = "ALL OK"
	$(PXX_STABLE) examples/calc/calcdemo.pas /tmp/lib_calcdemo
	test "$$(/tmp/lib_calcdemo | tail -1)" = "ALL OK"
	$(PXX_STABLE) examples/sat/satdemo.pas /tmp/lib_satdemo
	test "$$(/tmp/lib_satdemo | tail -1)" = "ALL OK"
	$(PXX_STABLE) examples/mathf/mathdemo.pas /tmp/lib_mathdemo
	test "$$(/tmp/lib_mathdemo | tail -1)" = "ALL OK"
	$(PXX_STABLE) -Fulib/rtl examples/vm/vmdemo.pas /tmp/lib_vmdemo
	test "$$(/tmp/lib_vmdemo | tail -1)" = "ALL OK"
	$(PXX_STABLE) examples/mandelbrot/mandelbrot.pas /tmp/lib_mandelbrot
	test "$$(/tmp/lib_mandelbrot | tail -1)" = "ALL OK"
	$(PXX_STABLE) examples/raytracer/raytracer.pas /tmp/lib_raytracer
	test "$$(/tmp/lib_raytracer | tail -1)" = "ALL OK"
	$(PXX_STABLE) examples/chess/chess.pas /tmp/lib_chess
	test "$$(/tmp/lib_chess --selftest | tail -1)" = "ALL OK"
	$(PXX_STABLE) examples/lisp/lispdemo.pas /tmp/lib_lispdemo
	test "$$(/tmp/lib_lispdemo | tail -1)" = "ALL OK"
	$(PXX_STABLE) test/lib_zlib.pas /tmp/lib_zlib
	test "$$(/tmp/lib_zlib)" = "$$(printf 'OK stored roundtrip\nOK fixed huffman\nOK dynamic huffman\nOK bad header checksum\nOK bad adler32\nOK truncated stream\nOK reserved block type\nOK gzip\nOK gzip bad crc\nOK raw deflate')"
	$(PXX_STABLE) -Fulib/rtl test/lib_base64.pas /tmp/lib_base64
	test "$$(/tmp/lib_base64 | grep -c '=ok')" = "14"
	test "$$(/tmp/lib_base64 | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) test/lib_png.pas /tmp/lib_png
	test "$$(/tmp/lib_png)" = "$$(printf '86\n137 80 78 71\nTRUE\n2x2\n255,0,0,255\n0,255,0,128\n0,0,255,64\n255,255,255,0\nFALSE\nbad chunk crc')"
	$(PXX_STABLE) test/lib_ansiterm.pas /tmp/lib_ansiterm
	test "$$(/tmp/lib_ansiterm)" = "OK"
	$(PXX_STABLE) test/lib_screen.pas /tmp/lib_screen
	test "$$(/tmp/lib_screen | tail -1)" = "ALL OK"
	$(PXX_STABLE) test/lib_cursor.pas /tmp/lib_cursor
	test "$$(/tmp/lib_cursor)" = "$$(printf '\033[3;4H\033[?25h')"
	$(PXX_STABLE) test/lib_lineedit.pas /tmp/lib_lineedit
	test "$$(/tmp/lib_lineedit | tail -1)" = "ALL OK"
	$(PXX_STABLE) test/lib_menu.pas /tmp/lib_menu
	test "$$(/tmp/lib_menu | tail -1)" = "ALL OK"
	$(PXX_STABLE) -Fuexamples/solitaire_gui test/lib_klondike.pas /tmp/lib_klondike
	test "$$(/tmp/lib_klondike | tail -1)" = "ALL OK"
	$(PXX_STABLE) -Fulib/rtl -Fuexamples/solitaire_gui examples/solitaire/console_solitaire.pas /tmp/console_solitaire
	test "$$(printf 'aq' | /tmp/console_solitaire 2>/dev/null | tail -1)" = "moves=2 won=FALSE"
	$(PXX_STABLE) -Fuexamples/g2048 test/lib_g2048.pas /tmp/lib_g2048
	test "$$(/tmp/lib_g2048 | tail -1)" = "ALL OK"
	$(PXX_STABLE) -Fulib/rtl -Fuexamples/g2048 examples/g2048/console_2048.pas /tmp/console_2048
	test "$$(printf '\033[D\033[B\033[D\033[B\033[C\033[A q' | /tmp/console_2048 2>/dev/null | tail -1)" = "score=8 over=FALSE"
	$(PXX_STABLE) test/lib_tui_app.pas /tmp/lib_tui_app
	test "$$(/tmp/lib_tui_app | tail -1)" = "ALL OK"
	$(PXX_STABLE) test/lib_keys.pas /tmp/lib_keys
	test "$$(printf 'q\033[A\033[B\033[3~\177' | /tmp/lib_keys)" = "$$(printf '113\n1001\n1002\n1010\n127')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix examples/tui/menudemo.pas /tmp/menudemo
	test "$$(printf '\033[B\033[B\r' | /tmp/menudemo | tail -1)" = "selected=Quit"
	$(PXX_STABLE) test/lib_ansirender.pas /tmp/lib_ansirender
	test "$$(/tmp/lib_ansirender)" = "OK"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_process.pas /tmp/lib_process
	test "$$(/tmp/lib_process)" = "$$(printf 'Bytes read: 12\nByte 0: 104\nByte 1: 101\nByte 2: 108\nByte 3: 108\nByte 4: 111\nByte 5: 32\nByte 6: 119\nByte 7: 111\nByte 8: 114\nByte 9: 108\nByte 10: 100\nByte 11: 10\nChild output: [hello world\n]\nChild wait status: 0\nOK')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_process_multi.pas /tmp/lib_process_multi
	test "$$(/tmp/lib_process_multi | tail -1)" = "OK"
	$(PXX_STABLE) test/lib_dynlibs.pas /tmp/lib_dynlibs
	test "$$(/tmp/lib_dynlibs)" = "$$(printf 'nil-handle=ok\nsym-nil=ok\nprocaddr-alias=ok\nunload=ok\nfree-alias=ok\nerrstr=ok')"
	$(PXX_STABLE) test/lib_unixshims.pas /tmp/lib_unixshims
	test "$$(/tmp/lib_unixshims)" = "$$(printf 'gettimeofday=ok\ntv_sec-sane=ok\ntv_usec-range=ok\nnil-tp=ok\ntzseconds=ok')"
	$(PXX_STABLE) test/lib_strpchar.pas /tmp/lib_strpchar
	test "$$(/tmp/lib_strpchar)" = "$$(printf 'strlcopy-ret=ok\nstrlcopy-trunc=ok\nstrlcopy-short=ok\nstrlcomp-eq=ok\nstrlcomp-lt=ok\nstrlcomp-gt=ok\nsleep=ok\nmove-fillchar=ok\ninttohex-ff=ok\ninttohex-pad=ok\nstringofchar=ok\nstringofchar-0=ok')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_sockets.pas /tmp/lib_sockets
	test "$$(/tmp/lib_sockets)" = "$$(printf 'htons=ok\nhtonl=ok\nroundtrip=ok\nsocket=ok\nbind=ok\nlisten=ok\nconnect=ok\naccept=ok\nsend=ok\nrecv=ok\nclose-conn=ok\nclose-cli=ok\nclose-srv=ok')"
	$(PXX_STABLE) -Fulib/rtl test/lib_sha256.pas /tmp/lib_sha256
	test "$$(/tmp/lib_sha256 | grep -c '=ok')" = "12"
	test "$$(/tmp/lib_sha256 | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_sha512.pas /tmp/lib_sha512
	test "$$(/tmp/lib_sha512 | grep -c '=ok')" = "3"
	test "$$(/tmp/lib_sha512 | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_tls13_keys.pas /tmp/lib_tls13_keys
	test "$$(/tmp/lib_tls13_keys | grep -c '=ok')" = "5"
	test "$$(/tmp/lib_tls13_keys | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_tls13_record.pas /tmp/lib_tls13_record
	test "$$(/tmp/lib_tls13_record | grep -c '=ok')" = "6"
	test "$$(/tmp/lib_tls13_record | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_tls13_hs.pas /tmp/lib_tls13_hs
	test "$$(/tmp/lib_tls13_hs | grep -c '=ok')" = "6"
	test "$$(/tmp/lib_tls13_hs | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_chacha20poly1305.pas /tmp/lib_chacha
	test "$$(/tmp/lib_chacha | grep -c '=ok')" = "7"
	test "$$(/tmp/lib_chacha | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_x25519.pas /tmp/lib_x25519
	test "$$(/tmp/lib_x25519 | grep -c '=ok')" = "6"
	test "$$(/tmp/lib_x25519 | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_aesgcm.pas /tmp/lib_aesgcm
	test "$$(/tmp/lib_aesgcm | grep -c '=ok')" = "8"
	test "$$(/tmp/lib_aesgcm | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_rsa.pas /tmp/lib_rsa
	test "$$(/tmp/lib_rsa | grep -c '=ok')" = "3"
	test "$$(/tmp/lib_rsa | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_ed25519.pas /tmp/lib_ed25519
	test "$$(/tmp/lib_ed25519 | grep -c '=ok')" = "3"
	test "$$(/tmp/lib_ed25519 | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_ecdsa_p256.pas /tmp/lib_ecdsa
	test "$$(/tmp/lib_ecdsa | grep -c '=ok')" = "2"
	test "$$(/tmp/lib_ecdsa | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_x509.pas /tmp/lib_x509
	test "$$(/tmp/lib_x509 | grep -c '=ok')" = "12"
	test "$$(/tmp/lib_x509 | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_tls.pas /tmp/lib_tls
	test "$$(/tmp/lib_tls | grep -c '=ok')" = "14"
	test "$$(/tmp/lib_tls | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_http.pas /tmp/lib_http
	test "$$(/tmp/lib_http | grep -c '=ok')" = "83"
	test "$$(/tmp/lib_http | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_http_async.pas /tmp/lib_http_async
	test "$$(/tmp/lib_http_async)" = "$$(printf 'server-done=ok\nstatus=ok\nreason=ok\nbody=ok')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_http_redirect.pas /tmp/lib_http_redirect
	test "$$(/tmp/lib_http_redirect)" = "$$(printf 'server-done=ok\nstatus=ok\nbody=ok')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_http_keepalive.pas /tmp/lib_http_keepalive
	test "$$(/tmp/lib_http_keepalive)" = "$$(printf 'server-done=ok\nbody1=ok\nalive-mid=ok\nbody2=ok')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_http_pool.pas /tmp/lib_http_pool
	test "$$(/tmp/lib_http_pool)" = "$$(printf 'server-done=ok\nbody1=ok\nbody2-reused=ok')"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_http_pool_concurrent.pas /tmp/lib_http_pool_concurrent
	test "$$(/tmp/lib_http_pool_concurrent | grep -c '=ok')" = "6"
	test "$$(/tmp/lib_http_pool_concurrent | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_http_gzip.pas /tmp/lib_http_gzip
	test "$$(/tmp/lib_http_gzip | grep -c '=ok')" = "4"
	test "$$(/tmp/lib_http_gzip | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_http_cookie.pas /tmp/lib_http_cookie
	test "$$(/tmp/lib_http_cookie | grep -c '=ok')" = "4"
	test "$$(/tmp/lib_http_cookie | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_http_serve.pas /tmp/lib_http_serve
	test "$$(/tmp/lib_http_serve | grep -c '=ok')" = "3"
	test "$$(/tmp/lib_http_serve | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_httpjson.pas /tmp/lib_httpjson
	test "$$(/tmp/lib_httpjson | grep -c '=ok')" = "6"
	test "$$(/tmp/lib_httpjson | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl/platform/posix examples/net/httpdemo.pas /tmp/httpdemo
	test "$$(/tmp/httpdemo | grep -c -e 'Welcome to frank2 net' -e 'cookie: sid=demo123' -e 'hello sid=demo123' -e 'body:   hello world' -e '^done')" = "5"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_https_mock.pas /tmp/lib_https_mock
	test "$$(/tmp/lib_https_mock | grep -c '=ok')" = "6"
	test "$$(/tmp/lib_https_mock | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl/platform/posix test/lib_dns_async.pas /tmp/lib_dns_async
	test "$$(/tmp/lib_dns_async)" = "$$(printf 'server-done=ok\nrcode=ok\ncount=ok\nip=ok\nchase-server-done=ok\nchase-rcode=ok\nchase-count=ok\nchase-ip=ok\ntimeout=ok\nv6-server-done=ok\nv6-rcode=ok\nv6-count=ok\nv6-ip=ok\ncache-1st=ok\ncache-2nd=ok\ncache-1query=ok\ntc-udp-done=ok\ntc-tcp-done=ok\ntc-rcode=ok\ntc-count=ok\ntc-ips=ok')"
	$(PXX_STABLE) -Fulib/rtl test/lib_classes.pas /tmp/lib_classes
	test "$$(/tmp/lib_classes | grep -c '=ok')" = "21"
	test "$$(/tmp/lib_classes | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/test_tlist_notify.pas /tmp/lib_tlist_notify
	test "$$(/tmp/lib_tlist_notify)" = "total ok 2 / 2"
	$(PXX_STABLE) -Fulib/rtl test/test_tcomponent.pas /tmp/lib_tcomponent
	test "$$(/tmp/lib_tcomponent)" = "total ok 9 / 9"
	$(PXX_STABLE) -Fulib/rtl test/lib_types.pas /tmp/lib_types
	test "$$(/tmp/lib_types)" = "3 4 10 20 0 1"
	$(PXX_STABLE) -Fulib/rtl test/lib_strutil.pas /tmp/lib_strutil
	test "$$(/tmp/lib_strutil | grep -c '=ok')" = "32"
	test "$$(/tmp/lib_strutil | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_format.pas /tmp/lib_format
	test "$$(/tmp/lib_format | grep -c '=ok')" = "14"
	test "$$(/tmp/lib_format | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_paths.pas /tmp/lib_paths
	test "$$(/tmp/lib_paths | grep -c '=ok')" = "14"
	test "$$(/tmp/lib_paths | grep -c 'FAIL')" = "0"
	@echo "lib-test ok (sudoku exact + collections + math + sysutils + random + wideint + p256field + bitset + ucomplex + vecmath + bignum-ops + platform + directory + bignum + json + calc + sat + mathf + vm + mandelbrot + raytracer + chess-perft + lisp + zlib + base64 + png smoke + ansiterm + ansirender + process + process-multi + dynlibs + unixshims + strpchar + sockets + sha256-hmac-hkdf + sha512 + tls13-keysched + tls13-record + tls13-hs + chacha20-poly1305 + x25519 + aes-gcm + rsa-verify + ed25519-verify + ecdsa-p256-verify + x509 + tls-seam + http + http-async + http-redirect + http-keepalive + http-pool + http-pool-concurrent + http-gzip + http-cookie + http-serve + http-json + net-demo + https-mock-seam + dns-async + dns-cache + classes + strutil + streams + format + paths) against stable v$$(cat $(STABLE_DEFAULT_DIR)/VERSION 2>/dev/null || echo '?')"

# Full Track-B library suite, distinct from compiler `make test`.
library-suite-green: pxx-stable-check
	PXX_STABLE=$(PXX_STABLE) tools/library_suite.sh green

library-suite-discovery: pxx-stable-check
	PXX_STABLE=$(PXX_STABLE) tools/library_suite.sh discovery

library-suite: pxx-stable-check
	PXX_STABLE=$(PXX_STABLE) tools/library_suite.sh all

# Dedicated GUI test suite for Track B.
gui-test: pxx-stable-check
	PXX_STABLE=$(PXX_STABLE) tools/gui_suite.sh

# Compile-smoke DASHBOARD for every demo app, against the pinned stable. Prints
# an OK/FAIL table and always exits 0 -- a discovery view, not a gate. FAILs are
# expected (they map to library/feature gaps -> tickets), not build breakers.
demos: pxx-stable-check
	@echo "=== demos: compile-smoke examples/* against $(PXX_STABLE) ==="
	@rc=0; for src in examples/primes/sieve.pas examples/sudoku/sudoku.pas \
	    examples/maze/maze.pas examples/bignum/factorial.pas examples/bignum/bigmath.pas \
	    examples/json/jsondemo.pas examples/calc/calcdemo.pas examples/sat/satdemo.pas \
	    examples/mathf/mathdemo.pas examples/vm/vmdemo.pas examples/mandelbrot/mandelbrot.pas examples/lisp/lispdemo.pas \
	    examples/raytracer/raytracer.pas \
	    examples/chess/chess.pas examples/adventure/adventure.pas \
	    examples/life/life.pas examples/player/player.pas examples/fm/fm.pas \
	    examples/gl/triangle.pas; do \
	  flags="-Fulib/pcl"; \
	  if [ "$$src" = "examples/player/player.pas" ] || [ "$$src" = "examples/fm/fm.pas" ]; then flags="$$flags -Fulib/rtl/platform/posix"; fi; \
	  if $(PXX_STABLE) $$flags "$$src" /tmp/demo_$$(basename $$src .pas) >/tmp/demo.log 2>&1; then \
	    printf '  OK    %s\n' "$$src"; \
	  else \
	    printf '  FAIL  %s  -- %s\n' "$$src" "$$(tail -1 /tmp/demo.log)"; \
	  fi; \
	done; \
	echo "(demos is a dashboard, not a gate; FAILs -> file a ticket)"; exit 0

# C interop discovery dashboard for Track B. This intentionally exits 0 for
# candidate-library gaps; keep `lib-test` as the green gate.
c-interop-devtest: pxx-stable-check
	tools/c_interop_devtest.sh

# Real-HTTPS check for the OpenSSL TLS backend (dlopen'd libssl + openssl
# s_server). Opt-in / non-hermetic (needs the openssl CLI + libssl.so.3), so it
# is NOT in the default lib-test gate; skips cleanly when prereqs are absent.
tls-openssl-devtest: pxx-stable-check
	tools/tls_openssl_devtest.sh

# From-scratch TLS 1.3 client handshake (phase 1) vs openssl s_server. Opt-in /
# non-hermetic; not in the lib-test gate.
tls13-handshake-devtest: pxx-stable-check
	tools/tls13_handshake_devtest.sh
