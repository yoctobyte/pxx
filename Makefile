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
# Per-invocation scratch root for the self-host build's intermediates.
#
# These were fixed absolute paths (/tmp/pascal26-build etc). /tmp is NOT
# per-clone, so the watcher's dedicated clone and a dev checkout on the same box
# resolved them to the SAME files: two concurrent self-host builds wrote each
# other's intermediates. The dedicated-clone isolation was real for the git tree
# and absent for the build — and what gets corrupted is the binary the
# fixedpoint gate blesses, silently.
#
# Keyed on make's own pid ($$PPID of the shell make spawns), forced to expand
# once, and EXPORTED so the recursive $(MAKE) calls share one root instead of
# minting their own. Override to pin it somewhere stable/inspectable.
PXX_TMP ?= /tmp/pxx-build-$(shell echo $$PPID)
PXX_TMP := $(PXX_TMP)
$(shell mkdir -p $(PXX_TMP))
export PXX_TMP
# Named with a -<pid> suffix on the ROOT so tools/testmgr.py's sweep can reap an
# abandoned one by pid liveness, the same way it reaps its own scratch.
FPC_COMPILER := $(PXX_TMP)/pascal26-fpc
BUILD_COMPILER := $(PXX_TMP)/pascal26-build
VERIFY_COMPILER := $(PXX_TMP)/pascal26-verify
BUILD_COMPILER_MANAGED  := $(PXX_TMP)/pascal26-managed-build
VERIFY_COMPILER_MANAGED := $(PXX_TMP)/pascal26-managed-verify

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
# Where `make demos` writes built demo binaries. Defaults to an in-checkout,
# gitignored dir so the binaries are convenient to run/inspect after a build;
# override (e.g. DEMO_OUT=/tmp/demos) for a throwaway/CI build.
DEMO_OUT   ?= build/demos
PXXFLAGS   :=
FROZEN_PXXFLAGS := -uPXX_MANAGED_STRING

.PHONY: pxx-debug
.PHONY: test-esp-idf
.PHONY: fuzz-csmith
.PHONY: test-c-conformance-i386 test-c-conformance-aarch64 test-c-conformance-arm32 test-c-conformance-riscv32 test-c-conformance-cross
.PHONY: all bootstrap bootstrap-check fpc-check test-fpc seed-from-stable test test-quick test-smoke test-opt stabilize-fast stabilize-record test-core test-threads test-asm test-asm-emit test-debug-g test-nilpy qemu-env-check test-lua test-cjson test-c-conformance test-c test-zlib test-chess-perft test-duktape test-fpjson test-uforth bench-uforth test-quickjs test-i386 test-aarch64 test-arm32 test-riscv32 test-emit-obj test-sqlite-threads test-sqlite-parity stabilize check-stable selfcheck revert benchmark benchmark-compiler-runtime benchmark-opt-levels benchmark-check clean distclean symbols \
        bootstrap-managed bootstrap-frozen test-managed test-frozen stabilize-managed stabilize-frozen check-stable-managed revert-managed test-nilpy-managed test-nilpy-frozen \
        pxx-stable-check pin lib-test library-suite library-suite-green library-suite-discovery gui-test demos c-interop-devtest tls-openssl-devtest tls13-handshake-devtest truststore-devtest tls-native-seam-devtest \
        progress-check cross-bootstrap cross-bootstrap-aarch64 cross-bootstrap-arm32 cross-bootstrap-i386 test-esp-bare test-esp-softfloat

all: $(COMPILER)

# Print any make variable's expanded value: `make print-UFORTH_WORDSETS`.
# Exists so tooling can ASK for a list this Makefile owns instead of keeping a
# second copy of it — testmgr shards test-uforth per word set and reads the set
# through here, so adding a word set to UFORTH_WORDSETS is all it takes for a
# new shard to appear. No file is ever named print-*, so the pattern rule
# cannot shadow a real target.
print-%:
	@echo '$($*)'

# Debug build of the COMPILER itself, for gdb'ing pascal26 while it compiles
# something. Written to a SEPARATE path: compiler/pascal26 and the pinned
# stable are untouched, so a debug session cannot contaminate a gate run or the
# binary every other track builds on.
#
#   make pxx-debug
#   gdb --args compiler/pascal26-debug prog.py /tmp/out
#
# -g here is the compiler's own DWARF (it is a pxx-built binary like any other),
# which is why `break PyClassCreate` works. See devdocs/dev/debug-switches.md.
pxx-debug: $(COMPILER)
	$(COMPILER) -g $(COMPILER_SRC) $(COMPILER)-debug
	@echo "built $(COMPILER)-debug  —  gdb --args $(COMPILER)-debug <in> <out>"

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


# chore-makefile-selfhost-iterate-to-convergence: this rule used to demand
# byte-identical convergence in exactly ONE pass from whatever local seed
# happened to be on disk. tools/selfhost_fixedpoint.sh's own header comment
# says that demand is simply wrong: "a stale seed legitimately needs an extra
# round (stage2 came from the OLD compiler, stage3 from the new one) --
# demanding one pass is what made a normal bootstrap look like a failure."
# testmgr already iterates for exactly this reason. Mirror that here: iterate
# up to MAX_ROUNDS, accept the first round where two consecutive stages agree,
# and only fail if convergence genuinely never happens by then -- the
# property enforced is still "the compiler reproduces itself," never weakened
# to "in however many rounds it takes," just no longer mis-timed to the seed's
# staleness.
$(COMPILER): $(COMPILER_SRC) $(COMPILER_INC)
	@test -x $(COMPILER) || \
	  (echo "self-hosted compiler seed missing. Run: make bootstrap"; exit 1)
	@cur="./$(COMPILER)"; max=4; \
	for r in $$(seq 1 $$max); do \
	  a="$(BUILD_COMPILER)-r$$r"; b="$(VERIFY_COMPILER)-r$$r"; \
	  "$$cur" $(PXXFLAGS) $(COMPILER_SRC) "$$a" || exit 1; \
	  "$$a" $(PXXFLAGS) $(COMPILER_SRC) "$$b" || exit 1; \
	  if cmp -s "$$a" "$$b"; then \
	    echo "converged after $$r round(s)"; \
	    mv "$$a" $(COMPILER); \
	    rm -f "$$b"; \
	    exit 0; \
	  fi; \
	  cur="$$a"; \
	done; \
	echo "FAIL: no fixedpoint after $$max rounds -- a real self-host regression, not a stale seed"; \
	exit 1

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
	# What this proves is that `import sqlite3` resolves the C header, links
	# libsqlite3.so.0 and CALLS it — not which sqlite the box happens to ship.
	# It used to assert = "3045001", i.e. sqlite 3.45.1, the version on the
	# machine it was written on, so it was permanently RED on every other box
	# (bug-n-nilpy-import-sqlite-asserts-host-sqlite-version). Accept any
	# well-formed 3.x.y: major*1000000 + minor*1000 + patch.
	./$(COMPILER) test/test_nilpy_import_sqlite.npy /tmp/test_nilpy_import_sqlite26
	v=$$(/tmp/test_nilpy_import_sqlite26); case "$$v" in \
	  3[0-9][0-9][0-9][0-9][0-9][0-9]) ;; \
	  *) echo "FAIL: sqlite3_libversion_number() gave '$$v', not a 3.x.y version"; exit 1;; \
	esac
	rm -f /tmp/test_nilpy_sqlite_crud.db
	./$(COMPILER) test/test_nilpy_sqlite_crud.npy /tmp/test_nilpy_sqlite_crud26
	test "$$(/tmp/test_nilpy_sqlite_crud26)" = "$$(printf '1 alice\n2 bob')"
	# re module over lib/rtl/regex.pas; expectation is CPython's own output
	# collections.Counter (dict in Counter mode); expectation is CPython's output
	# field(default_factory=dict); expectation is CPython's output
	# PEP 604 unions in annotations; expectation is CPython's output
	# tuple returns + the keyword-only marker; expectation is CPython's output
	# dict.fromkeys; expectation is CPython's output
	# a .npy program using a unit with an `array of const` parameter
	# subclassing a class from an imported unit: dotted base, from-import, and
	# an override dispatching through the base's own call site
	# configparser shim + the virtual optionxform hook a subclass overrides
	# keyword arguments bind by name, any subset (an omitted optional keeps its default)
	# a method parameter that is unannotated AND defaulted, explicit and omitted
	./$(COMPILER) test/test_nilpy_method_param_default.npy /tmp/test_nilpy_mpdef26
	test "$$(/tmp/test_nilpy_mpdef26)" = "$$(printf 'all three: p f z\ndefaulted: p f\ndefault is None: True')"
	# a field assigned from an unannotated ctor parameter becomes a variant
	./$(COMPILER) test/test_nilpy_field_from_unannotated_param.npy /tmp/test_nilpy_fldparam26
	test "$$(/tmp/test_nilpy_fldparam26)" = "$$(printf 'p f 0\nreassigned: q\nNone field: True\nafter store: set')"
	# the tkinter facade: compiled, not run - it needs an X display. Lives in
	# examples/tk/ because a .npy in test/ resolving `tk` picks up test/strings.pas
	# (a PROGRAM named Strings) ahead of the RTL unit tk.pas uses - the resolver
	# searches the source file's own directory first.
	./$(COMPILER) examples/tk/tkinter_facade.npy /tmp/test_nilpy_tkinter26
	# a field assigned `tk.Canvas(...)` keeps its class in ANY method, so calls on
	# it resolve statically and take keyword arguments (same X-display caveat)
	./$(COMPILER) examples/tk/field_class_identity.npy /tmp/test_nilpy_fldcls26
	# callable options: bound method / plain def / lambda, and a variable trace
	./$(COMPILER) examples/tk/callbacks.npy /tmp/test_nilpy_tkcb26
	./$(COMPILER) test/test_nilpy_kwargs_by_name.npy /tmp/test_nilpy_kwname26
	test "$$(/tmp/test_nilpy_kwname26)" = "$$(printf '%b' 'contiguous: root 7 hi z\ninterior hole: 0 skipped-width z\nonly the last: 0  last-only\nnone given: 0  z')"
	# a unit-qualified class construction (mod.Class(args))
	./$(COMPILER) test/test_nilpy_qualified_ctor.npy /tmp/test_nilpy_qualctor26
	test "$$(/tmp/test_nilpy_qualctor26)" = "$$(printf '1280x800\nTrue False')"
	# one Exception class serving both the Python and the sysutils surface
	./$(COMPILER) test/test_nilpy_rtl_exception_surface.npy /tmp/test_nilpy_rtlexc26
	test "$$(/tmp/test_nilpy_rtlexc26)" = "$$(printf '%b' 'mine\ncaught: \042abc\042 is an invalid integer\nend')"
	# uses order must not change whether pylib's own Exception.Create compiles
	# (bug-pascal-uses-order-breaks-pylib-exception): sysutils named first, then
	# reversed. Each also checks that the shared `Exception` name's CreateFmt
	# body wasn't corrupted onto the wrong unit's class row.
	./$(COMPILER) test/test_uses_order_pylib_exception_a.pas /tmp/test_uses_order_pylib_exc_a26
	test "$$(/tmp/test_uses_order_pylib_exc_a26)" = "$$(printf '%b' 'pylib hi\ncaught: \042abc\042 is an invalid integer\n[    3]\nend')"
	./$(COMPILER) test/test_uses_order_pylib_exception_b.pas /tmp/test_uses_order_pylib_exc_b26
	test "$$(/tmp/test_uses_order_pylib_exc_b26)" = "$$(printf '%b' 'pylib hi\ncaught: \042abc\042 is an invalid integer\n[%5d]\nend')"
	# a method on a fresh construction: class return, and omitted defaults filled
	./$(COMPILER) test/test_nilpy_ctor_suffix_defaults.npy /tmp/test_nilpy_ctorsfx26
	test "$$(/tmp/test_nilpy_ctorsfx26)" = "$$(printf 'a\nba\na 1\nba 1')"
	# return-type inference agrees between the shell pre-pass and the body parse
	./$(COMPILER) test/test_nilpy_infer_return.npy /tmp/test_nilpy_inferret26
	test "$$(/tmp/test_nilpy_inferret26)" = "$$(printf '5\n6\nv7\n5\n[1, 2, 3]')"
	# sorted(key=lambda), d.items() as a value, for-target unpacking, Cls().m()
	# the function-object ABI, dict views, len(variant), a local named `result`
	# a lambda's DEFAULT-parameter captures (key=key) reach invoke time
	./$(COMPILER) test/test_nilpy_lambda_capture.npy /tmp/test_nilpy_lamcap26
	test "$$(/tmp/test_nilpy_lamcap26)" = "$$(printf '%b' '[4, 3, 2, 1]\n[1, 2, 3, 4]\n[4, 3, 2, 1]\n[1, 2, 3, 4]')"
	# a defaulted lambda parameter the CALLER supplies overrides the default, on
	# BOTH lowerings — they are reached by body shape, not by signature
	./$(COMPILER) test/test_nilpy_lambda_default_override.npy /tmp/test_nilpy_lamdef26
	test "$$(/tmp/test_nilpy_lamdef26)" = "$$(printf '%b' '6 12\n6 12\n6 6\n11020 10220 10203\n[0, 1, 2]\n9 1')"
	# a container literal is RETURNED by a lambda, and keeps its tuple/list
	# identity, on both lowerings — and the aliased-capture shape still works
	# an int accumulator widens when a CONTAINER hands it a float, in both
	# scopes — and the range-loop promoted accumulator is untouched
	./$(COMPILER) test/test_nilpy_accumulate_float_from_container.npy /tmp/test_nilpy_accfloat26
	test "$$(/tmp/test_nilpy_accfloat26)" = "$$(printf '%b' '3.5\n3.5 3 3.5\n51090942171709440000\n20000000000000000000\n20000000000000000000\n4000000000\n[1, 2, 3]\n3.5')"
	./$(COMPILER) test/test_nilpy_lambda_container_result.npy /tmp/test_nilpy_lamctr26
	test "$$(/tmp/test_nilpy_lamctr26)" = "$$(printf '%b' '(3, 4) tuple\n[3, 4] list\n(3, 4) tuple\n[3, 4] list\n(3, 4) tuple\na-b-c\n[2, 3, 1] 3\nc-a-b 3\nx-y 2\n6\n2 7')"
	./$(COMPILER) test/test_nilpy_fnvalue_abi.npy /tmp/test_nilpy_fnvalue26
	test "$$(/tmp/test_nilpy_fnvalue26)" = "$$(printf '%b' '3\n5\n2\n2 3.0 2\n3.0\n1.0\nC\nG\n2\n4.0\n3.14 3    3.142 3.1     | 2.0')"
	# range is a VALUE — a lazy SEQUENCE: re-iterable, indexable, len-able,
	# sliceable, with constant-time membership. NOT a cursor (see the test).
	./$(COMPILER) test/test_nilpy_range_as_a_value.npy /tmp/test_nilpy_rangeval26
	test "$$(/tmp/test_nilpy_rangeval26)" = "$$(printf '%b' 'range(0, 3)\nrange(0, 10, 2)\nrange(5, 0)\n[0, 1, 2]\n[0, 1, 2]\n3 0 1 2\nTrue False False\n4 [0, 3, 6, 9]\n0 []\n[3, 2, 1]\nTrue True\nTrue False\nrange(2, 5)\n[2, 3, 4]\nrange(0, 10, 2) [0, 2, 4, 6, 8]\nrange(7, 10)\n1000000000 999999999 True False\n10 2 8\n[1, 2, 3] (0, 1, 2)\nFalse True\n[3, 2, 1, 0]\n[0, 2, 4, 6]\n[(0, \0047a\0047), (1, \0047b\0047), (2, \0047c\0047)]\n[(1, 0), (2, 1)]\n[\00470\0047, \00471\0047, \00472\0047]\n[0, 2, 4]\n[0, 1, 2]\n[0, 1, 2, 0, 1, 2]\n[0, 1, 2, 3]\n[0, 1, 2]\n[0, 1]\n7')"
	# map/filter/enumerate/zip/reversed are LAZY: an early break never reaches a
	# raise past it, a bound cursor resumes where it parked, len(map(...)) is a
	# TypeError, and each one reports CPython's own type name.
	# The quote is spelled \0047 and not \047 here: in a printf %b ARGUMENT the
	# escape is \0ddd, so \047 followed by a DIGIT swallows it as a fourth octal
	# digit and prints garbage. (In a printf FORMAT string it is \ddd instead,
	# which is why the older entries around here are spelled the other way.)
	./$(COMPILER) test/test_nilpy_lazy_map_filter.npy /tmp/test_nilpy_lazymap26
	test "$$(/tmp/test_nilpy_lazymap26)" = "$$(printf '%b' 'survived [0, 1, 2]\ncalls 3\nafter binding: 0\nafter breaking at 3: 3\nrest: [40, 50]\n[2, 4]\n[2, 3]\n[3, 6]\n[\00471\0047, \00472\0047]\n[1, 3]\n[1, \0047a\0047]\nfilter saw [1, 2]\nmap\nfilter\nenumerate\nzip\nlist_reverseiterator\n<map\nenum rest [(2, 3)]\nzip rest [(2, \0047b\0047), (3, \0047c\0047)]\nrev rest [2, 1]\n[(1, \0047a\0047), (2, \0047b\0047)]\n[(1, \0047a\0047), (2, \0047b\0047)]\n[3, 2, 1]\n[2, 4, 6]\n12\n1-2-3\n[2, 4]\n200 100')"
	# iter()/next() and the cursor object they return: partial consumption
	# leaves the REST, exhaustion is permanent, iter(iter(x)) is idempotent
	./$(COMPILER) test/test_nilpy_iter_next_cursor.npy /tmp/test_nilpy_itercur26
	test "$$(/tmp/test_nilpy_itercur26)" = "$$(printf '%b' '1\n2\n[3]\n[]\ndone\na b c\nstopped\n[\047a\047, \047b\047]\nTrue\nlist_iterator\n<list_iterator\nNone\n[1, 2, 3, 4]\nparked at 2\nresumed 3\nresumed 4\n[1, 3]\n1 a\n2 b\n0 x\n1 y')"
	./$(COMPILER) test/test_nilpy_sorted_pairs.npy /tmp/test_nilpy_sortpairs26
	test "$$(/tmp/test_nilpy_sortpairs26)" = "$$(printf '%b' '3\nb 1\nc 2\na 3\na 3\nc 2\nb 1\n[1, 2, 3]\nx 1\ny 2\n2 0 3\nbb\nnone\n11\n3')"
	# a comprehension nested in another's element, dict spread, aggregate builtins
	./$(COMPILER) test/test_nilpy_nested_comp.npy /tmp/test_nilpy_nestcomp26
	test "$$(/tmp/test_nilpy_nestcomp26)" = "$$(printf '%b' '2\nab 2\ncd 2\n2 2 2\nx 1\ny 9\nz 3\n3\n3\n14\n5 1\nTrue True False True\n4.0\n28\npear apple')"
	# a Callable parameter on a METHOD is callable in the body
	./$(COMPILER) test/test_nilpy_method_callable_param.npy /tmp/test_nilpy_mcallable26
	test "$$(/tmp/test_nilpy_mcallable26)" = "$$(printf '%b' '2\n[\047p\047, \047p!\047, \047q\047, \047q!\047]\n[\047P\047, \047Q\047]')"
	# the pathlib shim, its `/` operator, and __str__ honoured by str()/print()/f-string
	./$(COMPILER) test/test_nilpy_pathlib.npy /tmp/test_nilpy_pathlib26
	test "$$(/tmp/test_nilpy_pathlib26)" = "$$(printf 'file.txt\nfile\n.txt\ndir/sub\ndir/sub\ndir/sub\nFalse\ndir/sub')"
	# the html and tempfile shims, and an import that is not at the top of the file
	./$(COMPILER) test/test_nilpy_html_tempfile.npy /tmp/test_nilpy_htmltmp26
	test "$$(/tmp/test_nilpy_htmltmp26)" = "$$(printf '%b' '&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;\nit\047s\n<b>&\042AB&nope;\nTrue\n.pdf\nTrue\nFalse')"
	# forwarding a collected *args into a callee with ordinary parameters
	./$(COMPILER) test/test_nilpy_star_forward.npy /tmp/test_nilpy_starfwd26
	test "$$(/tmp/test_nilpy_starfwd26)" = "$$(printf 'UI/size\n1/2\na/b/c')"
	# a method on a dynamically-typed receiver, dispatched across unrelated classes
	./$(COMPILER) test/test_nilpy_dynamic_dispatch.npy /tmp/test_nilpy_dyndisp26
	test "$$(/tmp/test_nilpy_dyndisp26)" = "$$(printf '%b' 'cand3\nx\nsum1.5\ncand3, x, sum1.5\nDET:x')"
	# Python or/and yield an OPERAND; an empty string is falsy
	./$(COMPILER) test/test_nilpy_truthy_value_ops.npy /tmp/test_nilpy_truthy26
	test "$$(/tmp/test_nilpy_truthy26)" = "$$(printf '%b' 'ab\nfallback\n7\n3\nb\n0\nx\nNone\nempty\ncond ok\nempty is falsy\nloop 0\n5')"
	# a class-level `name = <literal>` attribute, and `del <local>`
	./$(COMPILER) test/test_nilpy_class_attr.npy /tmp/test_nilpy_clsattr26
	test "$$(/tmp/test_nilpy_clsattr26)" = "$$(printf '%b' 'note_counting 3 0.5 True\ncadence\nnote_counting 3')"
	# r-prefixed raw strings, and set(iterable)
	./$(COMPILER) test/test_nilpy_raw_string_set.npy /tmp/test_nilpy_rawset26
	test "$$(/tmp/test_nilpy_rawset26)" = "$$(printf '%b' 'C#\n4\nFalse\nd\\d+\n3\n0\n2\n4\n1')"
	# import X as Y (the alias wins over a same-named compiled unit)
	./$(COMPILER) test/test_nilpy_import_alias.npy /tmp/test_nilpy_import_alias26
	test "$$(/tmp/test_nilpy_import_alias26)" = "$$(printf '4\n7\n2')"
	# *args / **kwargs collected on the callee side, and print(*args)
	./$(COMPILER) test/test_nilpy_star_args.npy /tmp/test_nilpy_star_args26
	test "$$(/tmp/test_nilpy_star_args26)" = "$$(printf '%b' '0\n\n4\na 1 2.5 True\n2\n[1, 2] {\047k\047: 1}\np:\np: x 9\n7 0\n7 2\nalpha a\nbeta 2\n1 0 0\n\n1 2 1\n2 3\n[2, 3]\n[]')"
	./$(COMPILER) test/test_nilpy_configparser.npy /tmp/test_nilpy_cfgparse26
	test "$$(/tmp/test_nilpy_cfgparse26)" = "$$(printf 'sections: 2\nhas UI: True has nope: False\nget: 1280x800\ndefault lowercases: True\noption: fontsize = 13\nsubclass keeps case: True\nand rejects folded: False')"
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_subclass_unit_base.npy /tmp/test_nilpy_subbase26
	test "$$(/tmp/test_nilpy_subbase26)" = "$$(printf 'override: KeepCase\ninherited: keepcase')"
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_array_of_const_unit.npy /tmp/test_nilpy_aoc26
	test "$$(/tmp/test_nilpy_aoc26)" = "x:2"
	./$(COMPILER) test/test_nilpy_dict_fromkeys.npy /tmp/test_nilpy_fromkeys26
	test "$$(/tmp/test_nilpy_fromkeys26)" = "$$(printf 'deduped: 3 b a c\nvalue is None: True\nempty: 0')"
	./$(COMPILER) test/test_nilpy_tuple_return.npy /tmp/test_nilpy_tupret26
	test "$$(/tmp/test_nilpy_tupret26)" = "$$(printf 'index: a 2 len: 2\nunpack: a 2\nthree: 3 6 x\none-tuple: 5 1\nsubscript call: 2\niter a\niter 2\nkwonly: 7 z')"
	./$(COMPILER) test/test_nilpy_union_annotation.npy /tmp/test_nilpy_union26
	test "$$(/tmp/test_nilpy_union26)" = "$$(printf 'value: 3\nnone: True\nzero is not None: True 0\nnone is None: True\nunion of two real types keeps the first: 42')"
	./$(COMPILER) test/test_nilpy_dataclass_dict_factory.npy /tmp/test_nilpy_dcdict26
	test "$$(/tmp/test_nilpy_dcdict26)" = "$$(printf 'F 1.5 1 because 7\nfresh per construction: 0 0')"
	./$(COMPILER) test/test_nilpy_counter.npy /tmp/test_nilpy_counter26
	test "$$(/tmp/test_nilpy_counter26)" = "$$(printf 'missing reads zero: 0\nstored: 2 len: 1\nfrom list: 2 1\nafter update: 2 3 1\nmc y 3\nmc x 2\nmc z 1\ntop: y\nkey x 2\nkey y 3\nkey z 1\nas dict: 2')"
	./$(COMPILER) test/test_nilpy_re.npy /tmp/test_nilpy_re26
	test "$$(/tmp/test_nilpy_re26)" = "$$(printf 'match ok: C# C #\nno-match is None ok\nsearch: 123\nfullmatch none: True\nsub: a b c\nsub groupref: Csharp D\nfindall n: 3 C# Db E\nfindall groups n: 3\ncompiled match: True True\ncompiled via module fn: True\nescape ok: True\nstart/stop: 0 2')"
	./$(COMPILER) test/test_nilpy_variant.npy /tmp/test_nilpy_variant26
	test "$$(/tmp/test_nilpy_variant26)" = "$$(printf '5\n3.14\nTrue')"
	./$(COMPILER) test/test_nilpy_control.npy /tmp/test_nilpy_control26
	test "$$(/tmp/test_nilpy_control26)" = "$$(printf '10\n20\n30\n6\n15\n6\n3')"
	./$(COMPILER) test/test_nilpy_local_variant.npy /tmp/test_nilpy_local_variant26
	test "$$(/tmp/test_nilpy_local_variant26)" = "$$(printf '5\n3.14\nTrue\n7')"
	./$(COMPILER) test/test_nilpy_numeric_widen.npy /tmp/test_nilpy_numeric_widen26
	test "$$(/tmp/test_nilpy_numeric_widen26)" = "$$(printf '3.14')"
	./$(COMPILER) test/test_nilpy_convert.npy /tmp/test_nilpy_convert26
	test "$$(/tmp/test_nilpy_convert26)" = "$$(printf '3\n42')"
	./$(COMPILER) test/test_nilpy_bool.npy /tmp/test_nilpy_bool26
	test "$$(/tmp/test_nilpy_bool26)" = "$$(printf 'True\nTrue\nTrue\nFalse\nTrue\nTrue\nFalse\nTrue\nFalse\nTrue\nFalse\nFalse\nFalse\nzero is falsy\nfive is truthy')"
	# bool is an int subclass: &/|/^/<</>> on booleans compute, and a
	# PARENTHESIZED comparison next to a bitwise op is accepted (it is what
	# PyBitGuard's own message asks for). Unparenthesized `x & 1 == 1` must
	# still be refused -- that is the precedence typo the guard exists for.
	./$(COMPILER) test/test_nilpy_bitwise_on_booleans.npy /tmp/test_nilpy_bitwise_on_booleans26
	test "$$(/tmp/test_nilpy_bitwise_on_booleans26)" = "$$(printf 'False\nTrue\nTrue\nTrue\nFalse\nTrue\nFalse\n1\n1\n5\n8\n2\n2')"
	# ...and the OTHER half of "bool is an int": True counts as +1, never as
	# OLE's VARIANT_TRUE = -1. The guard for the Pascal side adopting FPC's -1
	# (bug-p-variant-to-int-and-char-conversion-diverges-from-fpc): NilPy must
	# never reach the Pascal VariantToInt64, and pylib used to call it DIRECTLY
	# in four places, walking around the lowering seam that keeps NilPy on
	# pylib's helpers. Counter arithmetic was among them. Diffed against CPython.
	./$(COMPILER) test/test_nilpy_bool_is_an_int_not_ole_minus_one.npy /tmp/test_nilpy_bool_int26
	test "$$(/tmp/test_nilpy_bool_int26)" = "$$(printf '2\n2\n2 1\n3\n2\nTrue 2\n2 1')"
	# Python's dot-edge float spellings `.5` and `5.` (and `.5e3` / `5.e-3`),
	# which the shared Pascal scanner cannot lex -- NilPy has its own lexer.
	./$(COMPILER) test/test_nilpy_dot_edge_float_literals.npy /tmp/test_nilpy_dot_edge_float26
	test "$$(/tmp/test_nilpy_dot_edge_float26)" = "$$(printf '0.5\n5.0\n1.25\n10.0\n500.0\n5000.0\n0.005\n-0.5\n[0.5, 1.5, 2.0]\n4.0\nhalf\n1.5\n0.5\n5.0\n1000.0')"
	# min/max at 3+ positional args fold through the 2-argument overload; the
	# 1-/2-arg forms and a user shadow at the folded arity are untouched.
	# `is` is IDENTITY in Python, never Pascal's `E is TClass` type test -- the
	# ctor on the right must actually RUN (the "ctor N" lines are the proof).
	# @dataclass generates __eq__ over the declared fields (CPython does); a
	# nested dataclass field compares BY VALUE, a hand-written __eq__ wins.
	# float str()/repr() = shortest round-tripping decimal, CPython's rule.
	# Pins two tickets that were fixed by unrelated exact-decimal work with
	# nothing guarding the behaviour; second half asserts float(str(v)) == v.
	./$(COMPILER) test/test_nilpy_float_repr_roundtrip.npy /tmp/test_nilpy_float_repr26
	test "$$(/tmp/test_nilpy_float_repr26)" = "$$(printf '3.3333333333333335\n0.3333333333333333\n0.30000000000000004\n1e-20\n1e-300\n1.23e+18\n-0.0\n0.0\n1e+16\n1e+17\n5e-324\n1.7976931348623157e+308\n2.2250738585072014e-308\n0.1\n0.2\n0.14285714285714285\n0.2857142857142857\n1e+100\n-1e-100\n123456789.12345679\n1.5\n100.0\n0.5\n3.14159265358979\n1e-05\n0.0001\n1000000000000000.0\n1e+21\n1e+22\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue')"
	# `obj += n` on a class instance: __iadd__, else __add__ + rebind, else a
	# real TypeError -- all three used to silently leave the name holding 0.
	./$(COMPILER) test/test_nilpy_augmented_assign_class_dunder.npy /tmp/test_nilpy_aug_class26
	test "$$(/tmp/test_nilpy_aug_class26)" = "$$(printf '15\n12\n48\n9\n2\n7\n21\n10\ncaught TypeError\n6\n[1, 2, 3] [1, 2, 3]')"
	# ...and the same on a class-typed FIELD (`h.acc += 5`, `self.acc += k`),
	# which takes a DIFFERENT path: a dotted target is claimed by the shared
	# expression tail before NilPy's own augmented site can see it.
	./$(COMPILER) test/test_nilpy_augmented_assign_class_field.npy /tmp/test_nilpy_aug_field26
	test "$$(/tmp/test_nilpy_aug_field26)" = "$$(printf '105\n103\n309\n44\n4\n12\n15\n14\n56\n28\n38\n11\n[1, 2, 3]\n42\nTypeError')"
	# a NilPy def named like a Pascal intrinsic wins over the intrinsic:
	# sizeof was claimed by ParseFactorCore while high/low/length declined.
	./$(COMPILER) test/test_nilpy_def_shadows_pascal_intrinsic.npy /tmp/test_nilpy_intrinsic26
	test "$$(/tmp/test_nilpy_intrinsic26)" = "$$(printf '10\n4\n2\n6\n105')"
	./$(COMPILER) test/test_nilpy_dataclass_eq.npy /tmp/test_nilpy_dataclass_eq26
	test "$$(/tmp/test_nilpy_dataclass_eq26)" = "$$(printf 'True\nFalse\nFalse\nTrue\nTrue\nFalse\nFalse\nFalse\nFalse\nTrue\nFalse\nFalse\nTrue\nTrue\nFalse\nTrue\nTrue\nFalse\nTrue')"
	# @dataclass also generates __repr__: `print(p)` printed the instance HANDLE.
	./$(COMPILER) test/test_nilpy_dataclass_repr.npy /tmp/test_nilpy_dcrepr26
	/tmp/test_nilpy_dcrepr26 | diff -u test/test_nilpy_dataclass_repr.expected -
	# `from __future__ import annotations` is a no-op, not a missing unit.
	./$(COMPILER) test/test_nilpy_future_import.npy /tmp/test_nilpy_future26
	/tmp/test_nilpy_future26 | diff -u test/test_nilpy_future_import.expected -
	# `str.lower` as a VALUE -- an UNBOUND method, which is what
	# `sorted(xs, key=str.lower)` and `map(str.upper, xs)` are made of. Both
	# entry points (the factor path and PyMakeFuncValue) build it, and the
	# `map(str, xs)` CONVERSION rows are in the same file because the two
	# forms start with the same token and are told apart by a comma.
	./$(COMPILER) test/test_nilpy_unbound_str_method.npy /tmp/test_nilpy_unbstrm26
	/tmp/test_nilpy_unbstrm26 | diff -u test/test_nilpy_unbound_str_method.expected -
	# `dict(a=1)` / `dict(**e)` / `dict()` -- Python's keywords-are-KEYS special
	# case: the keyword NAMES are dict keys, not parameter names, so the run
	# becomes the one dict argument dict() already takes. (The d.update(a=1)
	# half is deliberately NOT shipped -- see the ticket.)
	./$(COMPILER) test/test_nilpy_dict_keyword_args.npy /tmp/test_nilpy_dictkw26
	/tmp/test_nilpy_dictkw26 | diff -u test/test_nilpy_dict_keyword_args.expected -
	# Adjacent / folded string literals ("a" "b" and "a" + "b") in EVERY
	# position: as a user-def argument, a list-literal element and a dict value
	# they used to be empty, zero-length or a parse error. Found compiling
	# html5lib/constants.py, which is written in the idiom throughout.
	./$(COMPILER) test/test_nilpy_adjacent_string_literals.npy /tmp/test_nilpy_adjstr26
	/tmp/test_nilpy_adjstr26 | diff -u test/test_nilpy_adjacent_string_literals.expected -
	# @staticmethod: registered WITH the hidden class receiver slot 0 that the
	# existing UMthIsStatic dispatch already fills. Both parser passes must agree.
	./$(COMPILER) test/test_nilpy_staticmethod.npy /tmp/test_nilpy_staticm26
	/tmp/test_nilpy_staticm26 | diff -u test/test_nilpy_staticmethod.expected -
	# ...and @classmethod must keep REFUSING itself by name, not parse as a static.
	! ./$(COMPILER) test/test_nilpy_classmethod_fail.npy /tmp/test_nilpy_cmfail26 2>&1 | grep -q 'ok:'
	# every iterable-taking builtin agrees about a bare genexpr arg; set() did not.
	./$(COMPILER) test/test_nilpy_genexpr_arg_callees.npy /tmp/test_nilpy_gexarg26
	/tmp/test_nilpy_gexarg26 | diff -u test/test_nilpy_genexpr_arg_callees.expected -
	# f-string `{n=}` self-documenting form, and `!=` inside a hole.
	./$(COMPILER) test/test_nilpy_fstring_selfdoc.npy /tmp/test_nilpy_fsdoc26
	/tmp/test_nilpy_fsdoc26 | diff -u test/test_nilpy_fstring_selfdoc.expected -
	# a KeyError names the KEY (via repr, which is what CPython's str() is).
	./$(COMPILER) test/test_nilpy_keyerror_names_the_key.npy /tmp/test_nilpy_keyerr26
	/tmp/test_nilpy_keyerr26 | diff -u test/test_nilpy_keyerror_names_the_key.expected -
	# .format(): the !r conversion was dropped, and a container arg vanished.
	./$(COMPILER) test/test_nilpy_str_format_conversion_and_containers.npy /tmp/test_nilpy_fmtconv26
	/tmp/test_nilpy_fmtconv26 | diff -u test/test_nilpy_str_format_conversion_and_containers.expected -
	# enumerate(xs, START) in a FOR HEADER — the expression form always worked.
	./$(COMPILER) test/test_nilpy_enumerate_start_in_for_header.npy /tmp/test_nilpy_enstart26
	/tmp/test_nilpy_enstart26 | diff -u test/test_nilpy_enumerate_start_in_for_header.expected -
	# `"%(k)s" % {...}` — the MAPPING form of %-formatting.
	./$(COMPILER) test/test_nilpy_percent_format_mapping.npy /tmp/test_nilpy_pctmap26
	/tmp/test_nilpy_pctmap26 | diff -u test/test_nilpy_percent_format_mapping.expected -
	# `with A() as a, B() as b:` — lowered by NESTING, so exit order is free.
	./$(COMPILER) test/test_nilpy_with_multiple_managers.npy /tmp/test_nilpy_withmulti26
	/tmp/test_nilpy_withmulti26 | diff -u test/test_nilpy_with_multiple_managers.expected -
	# str.isnumeric()/istitle(), with their five neighbouring predicates.
	./$(COMPILER) test/test_nilpy_str_isnumeric_istitle.npy /tmp/test_nilpy_isnumtitle26
	/tmp/test_nilpy_isnumtitle26 | diff -u test/test_nilpy_str_isnumeric_istitle.expected -
	# RELATIVE imports (`from .mod import x`, `from . import mod`). The sibling
	# helper modules resolve relative to the SOURCE file, so this needs no `cd`
	# and is an ordinary one-line recipe like every other test here. CPython
	# cannot be the oracle (it refuses a relative import outside a package) —
	# see the test header for what is asserted instead.
	./$(COMPILER) test/test_nilpy_relative_import.npy /tmp/test_nilpy_relimp26
	/tmp/test_nilpy_relimp26 | diff -u test/test_nilpy_relative_import.expected -
	# backslash line continuation, and `class C(object):`
	./$(COMPILER) test/test_nilpy_line_continuation.npy /tmp/test_nilpy_linecont26
	/tmp/test_nilpy_linecont26 | diff -u test/test_nilpy_line_continuation.expected -
	# a SET comprehension over range() must deduplicate (elements must COLLIDE).
	./$(COMPILER) test/test_nilpy_set_comprehension_dedup.npy /tmp/test_nilpy_setcomp26
	/tmp/test_nilpy_setcomp26 | diff -u test/test_nilpy_set_comprehension_dedup.expected -
	# repr() of an exception is ClassName('msg'), not an address.
	./$(COMPILER) test/test_nilpy_exception_repr.npy /tmp/test_nilpy_excrepr26
	/tmp/test_nilpy_excrepr26 | diff -u test/test_nilpy_exception_repr.expected -
	# str() of a CONSTRUCTED exception is its message, like a caught one's.
	./$(COMPILER) test/test_nilpy_exception_str_constructed.npy /tmp/test_nilpy_excstr26
	/tmp/test_nilpy_excstr26 | diff -u test/test_nilpy_exception_str_constructed.expected -
	# subscripting a CALL RESULT: str index/slice, and chained subscripts.
	./$(COMPILER) test/test_nilpy_subscript_of_a_call_result.npy /tmp/test_nilpy_callsub26
	/tmp/test_nilpy_callsub26 | diff -u test/test_nilpy_subscript_of_a_call_result.expected -
	# `parser = Parser(1)` then `parser(2)` must call __call__, not construct.
	./$(COMPILER) test/test_nilpy_instance_named_like_its_class.npy /tmp/test_nilpy_instname26
	/tmp/test_nilpy_instname26 | diff -u test/test_nilpy_instance_named_like_its_class.expected -
	# RETIRED (feature-nilpy-class-as-a-value): a class used as a VALUE no longer
	# refuses — it constructs. The program that file pinned as an ERROR is now a
	# PASSING case inside test_nilpy_class_as_a_value.npy, which is where its
	# `for cls in [A]` shape lives. Its own header said to retire it when class
	# references became first-class values, so this is that.
	# a subscript READ on a class with no __getitem__ raises TypeError at RUN time.
	./$(COMPILER) test/test_nilpy_not_subscriptable.npy /tmp/test_nilpy_notsub26
	/tmp/test_nilpy_notsub26 | diff -u test/test_nilpy_not_subscriptable.expected -
	# `e[key()] += 1` must evaluate key() ONCE (side-effecting index observes it).
	./$(COMPILER) test/test_nilpy_augmented_subscript_index_once.npy /tmp/test_nilpy_augidx26
	/tmp/test_nilpy_augidx26 | diff -u test/test_nilpy_augmented_subscript_index_once.expected -
	./$(COMPILER) test/test_nilpy_is_identity_vs_class_test.npy /tmp/test_nilpy_is_identity26
	test "$$(/tmp/test_nilpy_is_identity26)" = "$$(printf 'ctor 1\n--- is with a construction on the right\nctor 2\nFalse\n--- is not\nctor 3\nTrue\n--- both sides constructed\nctor 4\nctor 5\nFalse\n--- nested in a call, a paren, a list\nctor 6\nFalse\nctor 7\n[False]\nctor 8\nFalse\n--- identity that is actually True\nTrue\nFalse\n--- a different class on the right is still identity, not a type test\nFalse\n--- == still constructs and compares\nctor 9\nFalse')"
	./$(COMPILER) test/test_nilpy_min_max_variadic.npy /tmp/test_nilpy_min_max_variadic26
	test "$$(/tmp/test_nilpy_min_max_variadic26)" = "$$(printf '1\n3\n0\n5\n3\n3.5\n0.5\nc\na\n4 11\n14\n1\n3\n2\n9\no\n100')"
	@# ...and the positional half of the same rule for builtins with NO pylib
	@# proc (ord/chr/abs, name-dispatched intrinsics) and for one whose arity a
	@# def happens to match (set): a call ABOVE the def reaches the builtin.
	./$(COMPILER) test/test_nilpy_def_shadows_builtin_positionally.npy /tmp/test_nilpy_defshadowpos26
	test "$$(/tmp/test_nilpy_defshadowpos26)" = "$$(printf '65\nlate-ord\nB\nlate-chr\n3\nlate-abs\n{1}\nlate-set\n1.5\nlate-float\nFalse\nlate-bool\n1\n100\n11\n7')"
	# for/while `else` (runs when the loop finished WITHOUT a break -- an empty
	# iterable still runs it; a break in a NESTED loop must not skip the outer
	# one's else) and `try ... else` (runs when the body did not raise, before
	# finally, and its own raise escapes this statement's except).
	./$(COMPILER) test/test_nilpy_loop_else.npy /tmp/test_nilpy_loop_else26
	test "$$(/tmp/test_nilpy_loop_else26)" = "$$(printf 'for-else ran\nwhile-else ran\nafter break loop\nm = 2\nempty loop else ran\nouter 1\nouter 2\nouter else ran\nouter else ran, inner skipped\nplain break i = 2\nrange else ran\nrange break i = 1\nfound\nexhausted')"
	./$(COMPILER) test/test_nilpy_try_else.npy /tmp/test_nilpy_try_else26
	test "$$(/tmp/test_nilpy_try_else26)" = "$$(printf 'else ran, x = 1\nhandler ran\nbody\nelse\nfinally\nhandler2\nfinally2\ninner body\nouter handler caught the else'"'"'s raise\nearly\nelse\nplain except still works')"
	./$(COMPILER) test/test_nilpy_membership_bool_return.npy /tmp/test_nilpy_membership_bool_return26
	test "$$(/tmp/test_nilpy_membership_bool_return26)" = "$$(printf 'True\nFalse\nTrue\nTrue\nFalse\nTrue\nTrue\nFalse\nTrue\n3\n3\n3')"
	# a sibling .py MODULE: unit scoping, its own initialisation, both import forms
	./$(COMPILER) test/test_nilpy_py_module_import.npy /tmp/test_nilpy_py_module_import26
	test "$$(/tmp/test_nilpy_py_module_import26)" = "$$(printf 'module init ran\nprogram body\n8\n8\n3 3 b\n9\n7')"
	# `from mod import NAME as ALIAS` for a value, a def and a class
	./$(COMPILER) -Futest test/test_nilpy_from_import_as_alias.npy /tmp/test_nilpy_fromas26
	/tmp/test_nilpy_fromas26 | diff -u test/test_nilpy_from_import_as_alias.expected -
	./$(COMPILER) test/test_nilpy_lambda_expression_body.npy /tmp/test_nilpy_lamexpr26
	/tmp/test_nilpy_lamexpr26 | diff -u test/test_nilpy_lambda_expression_body.expected -
	./$(COMPILER) test/test_nilpy_immediate_lambda_call.npy /tmp/test_nilpy_iife26
	/tmp/test_nilpy_iife26 | diff -u test/test_nilpy_immediate_lambda_call.expected -
	./$(COMPILER) test/test_nilpy_range_runtime_step.npy /tmp/test_nilpy_rngstep26
	/tmp/test_nilpy_rngstep26 | diff -u test/test_nilpy_range_runtime_step.expected -
	./$(COMPILER) test/test_nilpy_one_line_def_suite.npy /tmp/test_nilpy_oneline26
	/tmp/test_nilpy_oneline26 | diff -u test/test_nilpy_one_line_def_suite.expected -
	./$(COMPILER) test/test_nilpy_dunder_index_slice.npy /tmp/test_nilpy_idxslice26
	/tmp/test_nilpy_idxslice26 | diff -u test/test_nilpy_dunder_index_slice.expected -
	./$(COMPILER) test/test_nilpy_widen_binding_variant.npy /tmp/test_nilpy_widenbind26
	/tmp/test_nilpy_widenbind26 | diff -u test/test_nilpy_widen_binding_variant.expected -
	./$(COMPILER) test/test_nilpy_ast_literal_eval.npy /tmp/test_nilpy_ast_literal26
	test "$$(/tmp/test_nilpy_ast_literal26)" = "$$(printf '0.7 0.7 0.5 3\n42 -3 hi\n2\nTrue None\n1 3')"
	# atexit handlers run at exit (LIFO), io's in-memory buffers behave
	./$(COMPILER) test/test_nilpy_atexit_io.npy /tmp/test_nilpy_atexit_io26
	test "$$(/tmp/test_nilpy_atexit_io26)" = "$$(printf '5 6\nhello world\nhello 5\n world\nseed\nmain done\nsecond ran\nbye ran')"
	# a module whose FIRST line is an import: the pre-scan must not skip it
	./$(COMPILER) test/test_nilpy_module_first_import.npy /tmp/test_nilpy_module_first_import26
	test "$$(/tmp/test_nilpy_module_first_import26)" = "$$(printf 'D\n2')"
	# a dotted package import: dots mangle to underscores, and an unresolved
	# module falls back to the mimic_<module> shim (both import forms)
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_dotted_import.npy /tmp/test_nilpy_dotted_import26
	test "$$(/tmp/test_nilpy_dotted_import26)" = "$$(printf 'hello world\nhello dotted')"
	# --no-shims refuses that substitution, so "no shims" is a checked property
	! ./$(COMPILER) --no-shims -Futest/nilpy_units test/test_nilpy_dotted_import.npy /tmp/test_nilpy_noshims26 > /tmp/test_nilpy_noshims.log 2>&1
	grep -q "no-shims" /tmp/test_nilpy_noshims.log
	# try/except ImportError picks a branch at COMPILE time, both directions
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_fallback_import.npy /tmp/test_nilpy_fallback26
	test "$$(/tmp/test_nilpy_fallback26)" = "hello fallback"
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_fallback_import_try_wins.npy /tmp/test_nilpy_fallback_try26
	test "$$(/tmp/test_nilpy_fallback_try26)" = "hello try branch"
	# an import inside a function body / indented suite (pulled by the
	# pre-scan, so the body's measured extent stays valid)
	./$(COMPILER) examples/tk/import_in_body.npy /tmp/test_nilpy_impbody26
	test "$$(/tmp/test_nilpy_impbody26)" = "$$(printf 'in a suite left\nbefore\nafter both')"
	# star/kwargs METHODS, a nested class, attribute + parenthesised unpack
	# targets, and a dynamic return from a def with defaulted parameters
	./$(COMPILER) test/test_nilpy_star_methods_and_targets.npy /tmp/test_nilpy_starm26
	test "$$(/tmp/test_nilpy_starm26)" = "$$(python3 test/test_nilpy_star_methods_and_targets.npy)"
	# a declared DEFAULT is what the callee runs with — int, str and None,
	# defs and methods, every arity, plus a written None
	./$(COMPILER) test/test_nilpy_default_arguments.npy /tmp/test_nilpy_dfl26
	test "$$(/tmp/test_nilpy_dfl26)" = "$$(python3 test/test_nilpy_default_arguments.npy)"
	# a def reading a module global assigned further down the file
	./$(COMPILER) test/test_nilpy_forward_module_global.npy /tmp/test_nilpy_fwdglob26
	test "$$(/tmp/test_nilpy_fwdglob26)" = "$$(python3 test/test_nilpy_forward_module_global.npy)"
	# the Python json module surface: dumps/loads and dump/load through pathlib
	./$(COMPILER) test/test_nilpy_json_module.npy /tmp/test_nilpy_jsonmod26
	test "$$(/tmp/test_nilpy_jsonmod26)" = "$$(python3 test/test_nilpy_json_module.npy)"
	# .field off a variant when several classes declare it at different offsets
	./$(COMPILER) test/test_nilpy_ambiguous_variant_field.npy /tmp/test_nilpy_ambfld26
	test "$$(/tmp/test_nilpy_ambfld26)" = "$$(python3 test/test_nilpy_ambiguous_variant_field.npy)"
	# class attributes BESIDE an __init__ (applied first, overwritable), and a
	# keyword argument that is not a module assignment
	./$(COMPILER) test/test_nilpy_class_attrs_with_ctor.npy /tmp/test_nilpy_clsattr26
	test "$$(/tmp/test_nilpy_clsattr26)" = "$$(python3 test/test_nilpy_class_attrs_with_ctor.npy)"
	# a dispatched method whose candidates return DIFFERENT classes: the result
	# stays dynamic, so the next call on it dispatches too
	./$(COMPILER) test/test_nilpy_dispatch_result_class.npy /tmp/test_nilpy_dispres26
	test "$$(/tmp/test_nilpy_dispres26)" = "$$(python3 test/test_nilpy_dispatch_result_class.npy)"
	# a comprehension whose target is also its source, float defaults, round()
	# of a dynamic expression, and a nonlocal write reaching the enclosing frame
	./$(COMPILER) test/test_nilpy_selfassigned_comprehension.npy /tmp/test_nilpy_selfcomp26
	test "$$(/tmp/test_nilpy_selfcomp26)" = "$$(python3 test/test_nilpy_selfassigned_comprehension.npy)"
	# a Pascal unit's .Free must finalize managed fields ONCE, not twice
	./$(COMPILER) test/test_nilpy_json_reparse_heap.npy /tmp/test_nilpy_jsonrep26
	test "$$(/tmp/test_nilpy_jsonrep26)" = "$$(python3 test/test_nilpy_json_reparse_heap.npy)"
	# a TUPLE as a dict key must hash by CONTENT, not by the list handle
	./$(COMPILER) test/test_nilpy_tuple_dict_key.npy /tmp/test_nilpy_tupkey26
	test "$$(/tmp/test_nilpy_tupkey26)" = "$$(python3 test/test_nilpy_tuple_dict_key.npy)"
	# a bound method captured inside an imported .py MODULE, not just in main
	./$(COMPILER) -Futest test/test_nilpy_bound_method_in_module.npy /tmp/test_nilpy_boundmod26
	test "$$(/tmp/test_nilpy_boundmod26)" = "$$(printf 'built\nw:3\ncaptured in main\npanel')"
	# a bare name is never a method; str.format with a spec; qualified except
	./$(COMPILER) examples/tk/shadow_format_except.npy /tmp/test_nilpy_sfe26
	test "$$(/tmp/test_nilpy_sfe26)" = "$$(printf 'module function\nTap BPM: 92.5\ncaught: clipboard')"
	# a reserved-word constant (tk.END), a class named like an RTL record
	# (Text), and a property read on a fresh construction (Path(x).name)
	./$(COMPILER) examples/tk/facade_and_paths.npy /tmp/test_nilpy_facade_paths26
	test "$$(/tmp/test_nilpy_facade_paths26)" = "$$(printf 'end\nboth left center\nsong.txt\nsong\n/songs/a/song.pdf\n/songs/a/other.md')"
	# a nested def's result type, and a capture assigned after the nested def
	./$(COMPILER) test/test_nilpy_nested_def_result.npy /tmp/test_nilpy_nestdef26
	test "$$(/tmp/test_nilpy_nestdef26)" = "$$(printf 'big\nbig\n7\nyes\nno')"
	# tuple-vs-variant equality, round(x, n), enumerate() as a value,
	# and the standard exception names
	./$(COMPILER) test/test_nilpy_tuple_eq_round_enum.npy /tmp/test_nilpy_treq26
	test "$$(/tmp/test_nilpy_treq26)" = "$$(printf "miss\nhit\nFalse True\n1.23 2\n{'a': 25.0}\n1 b\n0 a\ncaught: nope")"
	# a string method on the RESULT of an unannotated def
	./$(COMPILER) test/test_nilpy_method_on_call_result.npy /tmp/test_nilpy_mcall26
	test "$$(/tmp/test_nilpy_mcall26)" = "$$(printf "['200', '100']\n640 480\npadded")"
	# an unavailable optional import compiles and fails only if used; map()
	./$(COMPILER) test/test_nilpy_optional_and_map.npy /tmp/test_nilpy_opt_map26
	test "$$(/tmp/test_nilpy_opt_map26)" = "$$(printf "False\n200 100\n['1', '2']\n[1.5, 2.0]")"
	# a mixed-type conditional as a comprehension element, and that
	# comprehension assigned back to the parameter it reads
	./$(COMPILER) test/test_nilpy_ternary_comp.npy /tmp/test_nilpy_ternary_comp26
	test "$$(/tmp/test_nilpy_ternary_comp26)" = "$$(printf "[0, 'x', 2]\n[0, 'x', 2]\n['a', 'b']")"
	# isinstance last in a genexpr filter; f(*[a,b,c]) argument unpacking
	./$(COMPILER) test/test_nilpy_genexp_isinstance_star.npy /tmp/test_nilpy_genexp_star26
	test "$$(/tmp/test_nilpy_genexp_star26)" = "$$(printf '5\n[1, 5, 3]\nTrue\n6\n6')"
	# a C library's names must not shadow a Python module qualifier
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_qualifier_vs_cproc.npy /tmp/test_nilpy_qual_cproc26
	test "$$(/tmp/test_nilpy_qual_cproc26)" = "$$(printf 'main\nbye')"
	# builtin shadowed by a parameter, [::-1] on list and str, the is* predicates
	./$(COMPILER) test/test_nilpy_builtin_shadow_slice.npy /tmp/test_nilpy_bshadow26
	test "$$(/tmp/test_nilpy_bshadow26)" = "$$(printf 'int:7\nother\n[3, 2, 1]\ncba\nTrue False False\nTrue True False\nTrue False\nTrue False')"
	# the process environment, both surfaces (CPython-diffed)
	PXX_ENV_PROBE=hello ./$(COMPILER) test/test_env_pascal.pas /tmp/test_env_pascal26
	test "$$(PXX_ENV_PROBE=hello /tmp/test_env_pascal26)" = "$$(printf 'hello\n[]\ncount ok')"
	./$(COMPILER) test/test_nilpy_environ.npy /tmp/test_nilpy_environ26
	test "$$(PXX_ENV_PROBE=hello /tmp/test_nilpy_environ26)" = "$$(printf 'hello\nNone\nfallback\nhello\ntruthy\nunset is falsey')"
	# the shape real code uses: the try block imports AND sets a flag
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_fallback_import_mixed.npy /tmp/test_nilpy_fallback_mixed26
	test "$$(/tmp/test_nilpy_fallback_mixed26)" = "$$(printf 'False\nTrue\npresent')"
	# an imported name shadows a builtin only in the module that imported it
	./$(COMPILER) test/test_nilpy_import_scope.npy /tmp/test_nilpy_import_scope26
	test "$$(/tmp/test_nilpy_import_scope26)" = "$$(printf '3\npage.size=A4\n8')"
	# rebinding a name across types widens to a variant, as Python allows
	./$(COMPILER) test/test_nilpy_rebind_type.npy /tmp/test_nilpy_rebind_type26
	test "$$(/tmp/test_nilpy_rebind_type26)" = "$$(printf 'plain string\nholder:one\n43\nback to a string')"
	# ...and rebinding across two UNRELATED CLASSES widens too: keeping one
	# static class read the other's fields at the wrong offset (SIGSEGV).
	# Includes the subclass-refinement control that must NOT widen.
	./$(COMPILER) test/test_nilpy_rebind_across_unrelated_classes.npy /tmp/test_nilpy_rebind_cls26
	/tmp/test_nilpy_rebind_cls26 | diff -u test/test_nilpy_rebind_across_unrelated_classes.expected -
	./$(COMPILER) test/test_nilpy_str_float.npy /tmp/test_nilpy_str_float26
	test "$$(/tmp/test_nilpy_str_float26)" = "$$(printf '3.14\n2.5\n-1.25\npi=3.14159\n3\n2')"
	./$(COMPILER) test/test_nilpy_string_variant.npy /tmp/test_nilpy_string_variant26
	test "$$(/tmp/test_nilpy_string_variant26)" = "$$(printf '5\napple\nTrue\nFalse\nFalse\nTrue\nTrue\nTrue\nFalse\nFalse\nTrue\nTrue\nFalse\nTrue\nlt TypeError\ngt TypeError\nhello world\nhello potato\ngreen world')"
	./$(COMPILER) test/test_nilpy_optional_param.npy /tmp/test_nilpy_optional_param26
	test "$$(/tmp/test_nilpy_optional_param26)" = "$$(printf '%b' '5\n7\n10')"
	./$(COMPILER) test/test_nilpy_stmt_semicolon.npy /tmp/test_nilpy_stmt_semicolon26
	test "$$(/tmp/test_nilpy_stmt_semicolon26)" = "$$(printf '%b' '1\n2')"
	./$(COMPILER) test/test_nilpy_no_return_annotation.npy /tmp/test_nilpy_no_return_annotation26
	test "$$(/tmp/test_nilpy_no_return_annotation26)" = "$$(printf '%b' '4\ng ran\n10\nn=5')"
	./$(COMPILER) test/test_nilpy_range_step.npy /tmp/test_nilpy_range_step26
	test "$$(/tmp/test_nilpy_range_step26)" = "$$(printf '%b' '5\n4\n3\n2\n1\n0\n2\n4\n6\n8\n4\n3\n0')"
	./$(COMPILER) test/test_nilpy_many_params.npy /tmp/test_nilpy_many_params26
	test "$$(/tmp/test_nilpy_many_params26)" = "$$(printf '55\n65\n36\n204\n80')"
	! ./$(COMPILER) test/test_nilpy_inconsistent_dedent_fail.npy /tmp/test_nilpy_inconsistent_dedent_fail26 > /tmp/test_nilpy_inconsistent_dedent_fail.log 2>&1
	grep -q "inconsistent dedent" /tmp/test_nilpy_inconsistent_dedent_fail.log
	! ./$(COMPILER) test/test_nilpy_mixed_indent_fail.npy /tmp/test_nilpy_mixed_indent_fail26 > /tmp/test_nilpy_mixed_indent_fail.log 2>&1
	grep -q "mixing tabs and spaces for indentation" /tmp/test_nilpy_mixed_indent_fail.log
	@# the STARRED forms are IMPLEMENTED now (test_nilpy_starred_unpack.npy);
	@# their two "must be refused with this message" recipes were retired with
	@# the feature. The NESTED forms are still unsupported, so theirs stay --
	@# an unsupported shape must NAME itself rather than report a perfectly good
	@# name as undefined (feature-nilpy-starred-and-nested-unpacking).
	! ./$(COMPILER) test/test_nilpy_nested_assign_target_fail.npy /tmp/test_nilpy_nested_assign_target_fail26 > /tmp/test_nilpy_nested_assign_target_fail.log 2>&1
	grep -q "NESTED assignment target" /tmp/test_nilpy_nested_assign_target_fail.log
	! ./$(COMPILER) test/test_nilpy_nested_for_target_fail.npy /tmp/test_nilpy_nested_for_target_fail26 > /tmp/test_nilpy_nested_for_target_fail.log 2>&1
	grep -q "NESTED loop target" /tmp/test_nilpy_nested_for_target_fail.log
	./$(COMPILER) test/test_nilpy_str_param.npy /tmp/test_nilpy_str_param26
	test "$$(/tmp/test_nilpy_str_param26)" = "$$(printf '2\nb\ncd\nok!')"
	./$(COMPILER) test/test_nilpy_forin.npy /tmp/test_nilpy_forin26
	/tmp/test_nilpy_forin26 | diff -u test/test_nilpy_forin.expected -
	./$(COMPILER) test/test_nilpy_case_sensitive.npy /tmp/test_nilpy_case_sensitive26
	/tmp/test_nilpy_case_sensitive26 | diff -u test/test_nilpy_case_sensitive.expected -
	./$(COMPILER) test/test_nilpy_global_scope_binding.npy /tmp/test_nilpy_global_scope_binding26
	/tmp/test_nilpy_global_scope_binding26 | diff -u test/test_nilpy_global_scope_binding.expected -
	./$(COMPILER) test/test_nilpy_param_defaults_nonconstant.npy /tmp/test_nilpy_param_defaults_nonconstant26
	/tmp/test_nilpy_param_defaults_nonconstant26 | diff -u test/test_nilpy_param_defaults_nonconstant.expected -
	./$(COMPILER) test/test_nilpy_method_param_defaults.npy /tmp/test_nilpy_method_param_defaults26
	/tmp/test_nilpy_method_param_defaults26 | diff -u test/test_nilpy_method_param_defaults.expected -
	# An EXPRESSION dataclass default is evaluated once, at the class statement,
	# into a hidden global each construction reads -- Python's own rule, and why
	# field(default_factory=...) exists. This file used to assert the REFUSAL.
	./$(COMPILER) test/test_nilpy_dataclass_expr_default.npy /tmp/test_nilpy_dcexpr26
	/tmp/test_nilpy_dcexpr26 | diff -u test/test_nilpy_dataclass_expr_default.expected -
	./$(COMPILER) test/test_nilpy_dataclass_decorator_args.npy /tmp/test_nilpy_dcargs26
	/tmp/test_nilpy_dcargs26 | diff -u test/test_nilpy_dataclass_decorator_args.expected -
	! ./$(COMPILER) test/test_nilpy_dataclass_order_fail.npy /tmp/test_nilpy_dcorder26 > /tmp/test_nilpy_dcorder.log 2>&1
	grep -q "order=True is not supported" /tmp/test_nilpy_dcorder.log
	! ./$(COMPILER) test/test_nilpy_dataclass_frozen_fail.npy /tmp/test_nilpy_dcfrozen26 > /tmp/test_nilpy_dcfrozen.log 2>&1
	grep -q "frozen=True is not supported" /tmp/test_nilpy_dcfrozen.log
	! ./$(COMPILER) test/test_nilpy_dataclass_unknown_option_fail.npy /tmp/test_nilpy_dcunk26 > /tmp/test_nilpy_dcunk.log 2>&1
	grep -q "no option named 'sorted'" /tmp/test_nilpy_dcunk.log
	./$(COMPILER) test/test_nilpy_account_program.npy /tmp/test_nilpy_acctprog26
	/tmp/test_nilpy_acctprog26 | diff -u test/test_nilpy_account_program.expected -
	./$(COMPILER) test/test_nilpy_augmented_assign_variant_operand.npy /tmp/test_nilpy_augvarop26
	/tmp/test_nilpy_augvarop26 | diff -u test/test_nilpy_augmented_assign_variant_operand.expected -
	./$(COMPILER) test/test_nilpy_floor_div_assign.npy /tmp/test_nilpy_floordivassign26
	/tmp/test_nilpy_floordivassign26 | diff -u test/test_nilpy_floor_div_assign.expected -
	./$(COMPILER) test/test_nilpy_augmented_assign_variant_field.npy /tmp/test_nilpy_augvarfield26
	/tmp/test_nilpy_augvarfield26 | diff -u test/test_nilpy_augmented_assign_variant_field.expected -
	./$(COMPILER) test/test_nilpy_bool_operand_and_or.npy /tmp/test_nilpy_boolop26
	/tmp/test_nilpy_boolop26 | diff -u test/test_nilpy_bool_operand_and_or.expected -
	./$(COMPILER) test/test_nilpy_boolop_left_operand_once.npy /tmp/test_nilpy_boolonce26
	/tmp/test_nilpy_boolonce26 | diff -u test/test_nilpy_boolop_left_operand_once.expected -
	./$(COMPILER) test/test_nilpy_default_before_star_args.npy /tmp/test_nilpy_defstar26
	/tmp/test_nilpy_defstar26 | diff -u test/test_nilpy_default_before_star_args.expected -
	./$(COMPILER) test/test_nilpy_star_args_is_a_tuple.npy /tmp/test_nilpy_stargstuple26
	/tmp/test_nilpy_stargstuple26 | diff -u test/test_nilpy_star_args_is_a_tuple.expected -
	./$(COMPILER) test/test_nilpy_unpack_keeps_class_identity.npy /tmp/test_nilpy_unpackid26
	/tmp/test_nilpy_unpackid26 | diff -u test/test_nilpy_unpack_keeps_class_identity.expected -
	./$(COMPILER) test/test_nilpy_negative_zero_repr.npy /tmp/test_nilpy_negzero26
	/tmp/test_nilpy_negzero26 | diff -u test/test_nilpy_negative_zero_repr.expected -
	./$(COMPILER) test/test_nilpy_empty_exception_subclass.npy /tmp/test_nilpy_emptyexc26
	/tmp/test_nilpy_emptyexc26 | diff -u test/test_nilpy_empty_exception_subclass.expected -
	./$(COMPILER) test/test_nilpy_one_line_class_body.npy /tmp/test_nilpy_onelineclass26
	/tmp/test_nilpy_onelineclass26 | diff -u test/test_nilpy_one_line_class_body.expected -
	./$(COMPILER) test/test_nilpy_one_line_def_in_module.npy /tmp/test_nilpy_onelinemod26
	/tmp/test_nilpy_onelinemod26 | diff -u test/test_nilpy_one_line_def_in_module.expected -
	@# a parameter/local named like a CLASS must not be typed as that class
	./$(COMPILER) test/test_nilpy_local_named_like_a_class.npy /tmp/test_nilpy_localclsname26
	/tmp/test_nilpy_localclsname26 | diff -u test/test_nilpy_local_named_like_a_class.expected -
	@# the field-path half also killed the COMPILER under -g, so that is its own row
	./$(COMPILER) -g test/test_nilpy_local_named_like_a_class.npy /tmp/test_nilpy_localclsname_g26
	/tmp/test_nilpy_localclsname_g26 | diff -u test/test_nilpy_local_named_like_a_class.expected -
	./$(COMPILER) test/test_nilpy_str_mul_str_undefined.npy /tmp/test_nilpy_strmul26
	/tmp/test_nilpy_strmul26 | diff -u test/test_nilpy_str_mul_str_undefined.expected -
	./$(COMPILER) test/test_nilpy_parent_call_after_instantiation.npy /tmp/test_nilpy_parentcall26
	/tmp/test_nilpy_parentcall26 | diff -u test/test_nilpy_parent_call_after_instantiation.expected -
	./$(COMPILER) test/test_nilpy_class_attr_hoist_leak.npy /tmp/test_nilpy_class_attr_hoist_leak26
	/tmp/test_nilpy_class_attr_hoist_leak26 | diff -u test/test_nilpy_class_attr_hoist_leak.expected -
	# calling a NON-CALLABLE segfaulted instead of raising a catchable TypeError.
	# Refuses the tags nothing callable ever wears (measured corpus-wide); an int
	# arriving as VT_INT64 shares a def's tag and is still uncovered — see the test.
	./$(COMPILER) test/test_nilpy_calling_a_non_callable.npy /tmp/test_nilpy_calling_a_non_callable26
	/tmp/test_nilpy_calling_a_non_callable26 | diff -u test/test_nilpy_calling_a_non_callable.expected -
	# a name differing from a CLASS only in CASE was hijacked by it: `class F` plus
	# `def f(a, b)` cleared the def's proc through a case-INSENSITIVE class lookup,
	# so `f(1, 2)` ran F's constructor. Python names are case-sensitive.
	./$(COMPILER) test/test_nilpy_lowercase_name_vs_class.npy /tmp/test_nilpy_lowercase_name_vs_class26
	/tmp/test_nilpy_lowercase_name_vs_class26 | diff -u test/test_nilpy_lowercase_name_vs_class.expected -
	# `*args` on a CONSTRUCTOR was never packed — the surplus arguments were passed
	# straight through and the callee read one as its TPyList (segfault, no
	# diagnostic). The plain-def and ordinary-method twins always worked.
	./$(COMPILER) test/test_nilpy_star_args_ctor.npy /tmp/test_nilpy_star_args_ctor26
	/tmp/test_nilpy_star_args_ctor26 | diff -u test/test_nilpy_star_args_ctor.expected -
	# `raise <variant>` SEGFAULTED — an exception held in a list/dict/for-in variable
	# or built through a class VALUE reached IR_RAISE as a 16-byte variant where the
	# instance POINTER belongs. Includes `raise [1]` (an object, but not an
	# exception) as a catchable TypeError. Diffed against CPython.
	./$(COMPILER) test/test_nilpy_raise_a_variant.npy /tmp/test_nilpy_raise_a_variant26
	/tmp/test_nilpy_raise_a_variant26 | diff -u test/test_nilpy_raise_a_variant.expected -
	# `__eq__` was SKIPPED as soon as one operand was a VARIANT — the dunder worked
	# with two named locals and `a == xs[0]` compared payloads, silently False. `==`
	# now routes to pyvar_eqv, the router over the equality `in`/count/index already
	# used. Includes the scalar/container regression half. Diffed against CPython.
	./$(COMPILER) test/test_nilpy_eq_dunder_variant_operand.npy /tmp/test_nilpy_eq_dunder_variant26
	/tmp/test_nilpy_eq_dunder_variant26 | diff -u test/test_nilpy_eq_dunder_variant_operand.expected -
	# a CLASS used as a VALUE — `cls = A`, a two-class registry, a subclass whose
	# base is a value, a class passed as an argument, a *args ctor, and print(cls).
	# Refused before (and a segfault before the refusal): the blob address rode as a
	# plain integer, the same shape a def/closure/bound-fn uses, so `cls(3)` jumped
	# into the RTTI blob. Diffed against CPython.
	./$(COMPILER) test/test_nilpy_class_as_a_value.npy /tmp/test_nilpy_class_as_a_value26
	/tmp/test_nilpy_class_as_a_value26 | diff -u test/test_nilpy_class_as_a_value.expected -
	./$(COMPILER) test/test_nilpy_annotated_class_attribute.npy /tmp/test_nilpy_annotated_class_attribute26
	/tmp/test_nilpy_annotated_class_attribute26 | diff -u test/test_nilpy_annotated_class_attribute.expected -
	./$(COMPILER) test/test_nilpy_class_attribute_through_class_name.npy /tmp/test_nilpy_clsattr_byname26
	/tmp/test_nilpy_clsattr_byname26 | diff -u test/test_nilpy_class_attribute_through_class_name.expected -
	# ...and through a class REFERENCE (alias, parameter, dict/list element), which
	# has no class index at compile time: read, write, inheritance, getattr/hasattr,
	# the plugin-registry shape, and the AttributeError. Diffed against CPython.
	@# len()/str()/hex() parse their argument once to learn its TYPE and rewind;
	@# the discarded parse's hoisted setup used to stay queued, so a file was read
	@# TWICE and len(f.read().upper()) answered 0. Diffed against CPython.
	./$(COMPILER) test/test_nilpy_len_of_a_file_read.npy /tmp/test_nilpy_lenread26
	/tmp/test_nilpy_lenread26 | diff -u test/test_nilpy_len_of_a_file_read.expected -
	@# map(obj.method, xs) — a bound method through map/filter/sorted, plus a
	@# method read as a VALUE off a variant receiver. Diffed against CPython.
	./$(COMPILER) test/test_nilpy_map_over_a_bound_method.npy /tmp/test_nilpy_mapbound26
	/tmp/test_nilpy_mapbound26 | diff -u test/test_nilpy_map_over_a_bound_method.expected -
	@# self.<class attribute> inside a method declared on the BASE must read the
	@# RECEIVER's class value — a 3-level chain, a non-redeclaring subclass, and
	@# super(). Diffed against CPython.
	./$(COMPILER) test/test_nilpy_inherited_class_attribute_through_self.npy /tmp/test_nilpy_inhclsattr_self26
	/tmp/test_nilpy_inhclsattr_self26 | diff -u test/test_nilpy_inherited_class_attribute_through_self.expected -
	@# round(x, n) keeps x's INTNESS — static ints, negative/computed ndigits, a
	@# bool, a variant element and an arbitrary-precision int. vs CPython.
	./$(COMPILER) test/test_nilpy_round_keeps_intness.npy /tmp/test_nilpy_roundint26
	/tmp/test_nilpy_roundint26 | diff -u test/test_nilpy_round_keeps_intness.expected -
	@# min/max with a `key=` held in a VARIABLE — every callable shape, plus a
	@# variant container and the plain numeric forms as controls. vs CPython.
	./$(COMPILER) test/test_nilpy_min_max_key_in_a_variable.npy /tmp/test_nilpy_minmaxkey26
	/tmp/test_nilpy_minmaxkey26 | diff -u test/test_nilpy_min_max_key_in_a_variable.expected -
	@# a filter BETWEEN two for-clauses gates the inner LOOP, on both comprehension
	@# paths — container-first and range-first. Diffed against CPython.
	./$(COMPILER) test/test_nilpy_filter_between_for_clauses.npy /tmp/test_nilpy_filtbetween26
	/tmp/test_nilpy_filtbetween26 | diff -u test/test_nilpy_filter_between_for_clauses.expected -
	@# a SECOND for-clause when the FIRST iterable is a range(): the counted path
	@# had no arm for the rest of the header. Diffed against CPython.
	./$(COMPILER) test/test_nilpy_two_for_clauses_over_range.npy /tmp/test_nilpy_twofor26
	/tmp/test_nilpy_twofor26 | diff -u test/test_nilpy_two_for_clauses_over_range.expected -
	@# `h[i], h[j] = h[j], h[i]` — a tuple assignment to SUBSCRIPT targets, incl.
	@# a dict, a nested subscript, an attribute base, __setitem__, a variant base
	@# and a heapify that cannot be written without it. Diffed against CPython.
	./$(COMPILER) test/test_nilpy_tuple_assign_to_subscripts.npy /tmp/test_nilpy_tuple_sub26
	/tmp/test_nilpy_tuple_sub26 | diff -u test/test_nilpy_tuple_assign_to_subscripts.expected -
	@# a def that returns None on one path and a value on another answers Any:
	@# `return None` beside `return 7` used to store a plain 0, so `x is None` was
	@# False and str(x) printed 0. Diffed against CPython.
	./$(COMPILER) test/test_nilpy_optional_return_is_none.npy /tmp/test_nilpy_optret_none26
	/tmp/test_nilpy_optret_none26 | diff -u test/test_nilpy_optional_return_is_none.expected -
	@# rebinding a PARAMETER is local to the call: a variant param is const-by-ref
	@# here, so `p = p + [9]` stored into the CALLER's slot. Mutation and `+=` on a
	@# list must still reach the caller. Diffed against CPython.
	./$(COMPILER) test/test_nilpy_rebinding_a_parameter_is_local.npy /tmp/test_nilpy_param_rebind26
	/tmp/test_nilpy_param_rebind26 | diff -u test/test_nilpy_rebinding_a_parameter_is_local.expected -
	./$(COMPILER) test/test_nilpy_class_attribute_through_a_class_reference.npy /tmp/test_nilpy_clsattr_byref26
	/tmp/test_nilpy_clsattr_byref26 | diff -u test/test_nilpy_class_attribute_through_a_class_reference.expected -
	./$(COMPILER) test/test_nilpy_inherited_class_attribute.npy /tmp/test_nilpy_inhclsattr26
	/tmp/test_nilpy_inhclsattr26 | diff -u test/test_nilpy_inherited_class_attribute.expected -
	./$(COMPILER) test/test_nilpy_class_attr_shared_slot_via_call_result.npy /tmp/test_nilpy_clsattr_callres26
	/tmp/test_nilpy_clsattr_callres26 | diff -u test/test_nilpy_class_attr_shared_slot_via_call_result.expected -
	./$(COMPILER) test/test_nilpy_overridden_class_attribute.npy /tmp/test_nilpy_ovrclsattr26
	/tmp/test_nilpy_ovrclsattr26 | diff -u test/test_nilpy_overridden_class_attribute.expected -
	./$(COMPILER) test/test_nilpy_closure_lifetime.npy /tmp/test_nilpy_closure_lifetime26
	/tmp/test_nilpy_closure_lifetime26 | diff -u test/test_nilpy_closure_lifetime.expected -
	./$(COMPILER) test/test_nilpy_lambda_arity.npy /tmp/test_nilpy_lambda_arity26
	/tmp/test_nilpy_lambda_arity26 | diff -u test/test_nilpy_lambda_arity.expected -
	./$(COMPILER) test/test_nilpy_body_scan_attribution.npy /tmp/test_nilpy_bodyscan26
	/tmp/test_nilpy_bodyscan26 | diff -u test/test_nilpy_body_scan_attribution.expected -
	./$(COMPILER) test/test_nilpy_bound_method_value_receiver_shapes.npy /tmp/test_nilpy_bmrecv26
	/tmp/test_nilpy_bmrecv26 | diff -u test/test_nilpy_bound_method_value_receiver_shapes.expected -
	./$(COMPILER) test/test_nilpy_global_read_above_its_assignment.npy /tmp/test_nilpy_globread26
	/tmp/test_nilpy_globread26 | diff -u test/test_nilpy_global_read_above_its_assignment.expected -
	./$(COMPILER) test/test_nilpy_function_value_repr.npy /tmp/test_nilpy_fnrepr26
	/tmp/test_nilpy_fnrepr26 | diff -u test/test_nilpy_function_value_repr.expected -
	./$(COMPILER) test/test_nilpy_callable_field_call_returns.npy /tmp/test_nilpy_cbfield26
	/tmp/test_nilpy_cbfield26 | diff -u test/test_nilpy_callable_field_call_returns.expected -
	./$(COMPILER) test/test_nilpy_callable_field_all_shapes.npy /tmp/test_nilpy_cbshapes26
	/tmp/test_nilpy_cbshapes26 | diff -u test/test_nilpy_callable_field_all_shapes.expected -
	./$(COMPILER) test/test_nilpy_conditional_expression_none.npy /tmp/test_nilpy_condnone26
	/tmp/test_nilpy_condnone26 | diff -u test/test_nilpy_conditional_expression_none.expected -
	./$(COMPILER) test/test_nilpy_float_repr.npy /tmp/test_nilpy_floatrepr26
	/tmp/test_nilpy_floatrepr26 | diff -u test/test_nilpy_float_repr.expected -
	./$(COMPILER) test/test_nilpy_user_class_shadows_builtin.npy /tmp/test_nilpy_shadow26
	/tmp/test_nilpy_shadow26 | diff -u test/test_nilpy_user_class_shadows_builtin.expected -
	./$(COMPILER) test/test_nilpy_dunder_index_sites.npy /tmp/test_nilpy_ixsites26
	/tmp/test_nilpy_ixsites26 | diff -u test/test_nilpy_dunder_index_sites.expected -
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_tobject_member_via_local.npy /tmp/test_nilpy_tobject_member26
	test "$$(/tmp/test_nilpy_tobject_member26)" = "$$(printf 'Dog\nDog\nDog\n42\n43')"
	./$(COMPILER) test/test_nilpy_object_arc.npy /tmp/test_nilpy_object_arc26
	test "$$(/tmp/test_nilpy_object_arc26)" = "$$(printf '3\n9\n2\n2')"
	./$(COMPILER) test/test_nilpy_class_return.npy /tmp/test_nilpy_class_return26
	test "$$(/tmp/test_nilpy_class_return26)" = "$$(printf 'a\nb\nsolo\ninner\n41\nlate')"
	./$(COMPILER) test/test_nilpy_fstrings.npy /tmp/test_nilpy_fstrings26
	# .expected file, not an inline printf: the !r cases contain single quotes,
	# which a printf '...' literal cannot carry without unreadable escaping.
	# The file is CPython's own output — regenerate with
	#   python3 test/test_nilpy_fstrings.npy > test/test_nilpy_fstrings.expected
	/tmp/test_nilpy_fstrings26 | diff -u test/test_nilpy_fstrings.expected -
	./$(COMPILER) test/test_nilpy_exceptions.npy /tmp/test_nilpy_exceptions26
	test "$$(/tmp/test_nilpy_exceptions26)" = "$$(printf 'none\nA\n10\nB\n20\nnone\nfin\nerr\nfin\ninner\nouter\n5\nbare')"
	./$(COMPILER) test/test_nilpy_kwargs.npy /tmp/test_nilpy_kwargs26
	test "$$(/tmp/test_nilpy_kwargs26)" = "$$(printf 'Hello, Ann!\nHi, Bob!\nHello, Cid?\nYo, Dee?!\nHey, Eve?\nHello, Fay!\nHello, Gus.\n111\n124\n130\n245')"
	./$(COMPILER) test/test_nilpy_defaults.npy /tmp/test_nilpy_defaults26
	test "$$(/tmp/test_nilpy_defaults26)" = "$$(printf '3\n6\nhi bob\nhi bob!\nend...\nend!\n7\n103\n106\n3\n-3\n206')"
	./$(COMPILER) test/test_nilpy_bytes.npy /tmp/test_nilpy_bytes26
	test "$$(/tmp/test_nilpy_bytes26)" = "$$(printf '4\n0\n0\n65\n66\n0\n255\n255\n65\n65\n1\n4\n1024\n0')"
	./$(COMPILER) test/test_nilpy_file_read.npy /tmp/test_nilpy_file_read26
	test "$$(/tmp/test_nilpy_file_read26)" = "$$(printf '%b' 'abc\n  abc\nabc  \nhello\nxxhello\nhelloxx\nline')"
	./$(COMPILER) test/test_nilpy_dedent.npy /tmp/test_nilpy_dedent26
	test "$$(/tmp/test_nilpy_dedent26)" = "$$(printf '%b' 'a\n  b\nc\n')"
	./$(COMPILER) test/test_nilpy_str_of_container.npy /tmp/test_nilpy_str_of_container26
	test "$$(/tmp/test_nilpy_str_of_container26)" = "$$(printf '%b' '(1, 2)\n[1, 2]\n{'\''a'\'': 1}\n(1, 2)\n(5,)\n['\''a'\'']\n(1, 2)\n[(1, 2), (3, 4)]\n(1, 2)!')"
	./$(COMPILER) test/test_nilpy_percent_format.npy /tmp/test_nilpy_percent_format26
	test "$$(/tmp/test_nilpy_percent_format26)" = "$$(printf '%b' 'bob is 42\n     3.142|\nbob       |\n5\n50%\n[[1, 2]]\n1-2\n   42|42   |00042\nff FF 10\n3.14\n1 2')"
	./$(COMPILER) test/test_nilpy_chaining.npy /tmp/test_nilpy_chaining26
	test "$$(/tmp/test_nilpy_chaining26)" = "$$(printf '%b' '6 3\n5\nA\nA,B\nB\n0012')"
	./$(COMPILER) test/test_nilpy_unknown_method.npy /tmp/test_nilpy_unknown_method26
	test "$$(/tmp/test_nilpy_unknown_method26)" = "$$(printf '%b' '5\ncb 5\n7')"
	./$(COMPILER) test/test_nilpy_super.npy /tmp/test_nilpy_super26
	test "$$(/tmp/test_nilpy_super26)" = "$$(printf '%b' 'BA 7 3 9\nCA 18')"
	./$(COMPILER) test/test_nilpy_unbound_base_init.npy /tmp/test_nilpy_unbound_base_init26
	test "$$(/tmp/test_nilpy_unbound_base_init26)" = "$$(printf '%b' 'M(1,2,base) 1 2 base\nL(3,4,5,base) 3 base\nS:B(7,base) 7 base\n9 9\nTrue True True')"
	./$(COMPILER) test/test_nilpy_classattr_expr.npy /tmp/test_nilpy_classattr_expr26
	test "$$(/tmp/test_nilpy_classattr_expr26)" = "$$(printf '%b' 'Normalt8\nNormal\n2 1 5\n1')"
	./$(COMPILER) test/test_nilpy_minmax.npy /tmp/test_nilpy_minmax26
	test "$$(/tmp/test_nilpy_minmax26)" = "$$(printf '%b' '7 3\n42 42\n7 3\n42\n9 2')"
	./$(COMPILER) test/test_nilpy_funcvalue.npy /tmp/test_nilpy_funcvalue26
	test "$$(/tmp/test_nilpy_funcvalue26)" = "$$(printf '%b' 'hi 5\nhi 7\nhi 8\nhi 9\n12\nzero\nhi x\nhi x\nhi y\n10\n5\n42\n5\n15\nvoid x\n10\ns:q\nnoargs\nnoargs')"
	./$(COMPILER) test/test_nilpy_dict_pop.npy /tmp/test_nilpy_dict_pop26
	test "$$(/tmp/test_nilpy_dict_pop26)" = "$$(printf '%b' '1\n99\n1\n0')"
	./$(COMPILER) test/test_nilpy_raise_from.npy /tmp/test_nilpy_raise_from26
	test "$$(/tmp/test_nilpy_raise_from26)" = "$$(printf '%b' '5\ncaught wrapped')"
	./$(COMPILER) test/test_nilpy_file_open.npy /tmp/test_nilpy_file_open26
	test "$$(/tmp/test_nilpy_file_open26)" = "$$(printf '%b' 'alpha\nbeta\ngamma\n3\n3')"
	@# whole-file read() past `with open` + a dict literal as a call argument
	./$(COMPILER) test/test_nilpy_file_io_and_comprehensions.npy /tmp/test_nilpy_fileiocompr26
	test "$$(/tmp/test_nilpy_fileiocompr26)" = "$$(printf '%b' 'alpha\nbeta\ngamma\n\n17\nsource 3')"
	./$(COMPILER) test/test_nilpy_or_and_value.npy /tmp/test_nilpy_or_and_value26
	test "$$(/tmp/test_nilpy_or_and_value26)" = "$$(printf '%b' 'hello\ndefault\ndefault\n2\n0\nin range\nout')"
	./$(COMPILER) test/test_nilpy_ternary_arg.npy /tmp/test_nilpy_ternary_arg26
	test "$$(/tmp/test_nilpy_ternary_arg26)" = "$$(printf '%b' 'pos\nneg\n4')"
	./$(COMPILER) test/test_nilpy_method_kwarg.npy /tmp/test_nilpy_method_kwarg26
	test "$$(/tmp/test_nilpy_method_kwarg26)" = "$$(printf '%b' 'H\ni')"
	./$(COMPILER) test/test_nilpy_variant_subscript.npy /tmp/test_nilpy_variant_subscript26
	./$(COMPILER) test/test_nilpy_variant_slice.npy /tmp/test_nilpy_variant_slice26
	test "$$(/tmp/test_nilpy_variant_slice26)" = "$$(printf '%b' 'ab\n3\n2')"
	./$(COMPILER) test/test_nilpy_variant_print_container.npy /tmp/test_nilpy_variant_print_container26
	test "$$(/tmp/test_nilpy_variant_print_container26)" = "$$(printf '%b' '[1, 2]\n[10, 20]\n{\047k\047: 1}\n7\nhi')"
	./$(COMPILER) test/test_nilpy_exception_print.npy /tmp/test_nilpy_exception_print26
	test "$$(/tmp/test_nilpy_exception_print26)" = "$$(printf '%b' 'bad value\nbad value\ngot: bad value\nboom')"
	@# f"{e}" of a caught exception shows its message, like print(e)/str(e)
	./$(COMPILER) test/test_nilpy_exception_fstring_message.npy /tmp/test_nilpy_excfstr26
	test "$$(/tmp/test_nilpy_excfstr26)" = "$$(printf '%b' 'boom\ngot: boom and boom\nbad value')"
	@# builtin runtime errors (div-by-zero, int()/float(), bad subscript,
	@# missing key) raise CATCHABLE exceptions, bare except: and typed
	./$(COMPILER) test/test_nilpy_catchable_runtime_errors.npy /tmp/test_nilpy_catchable26
	test "$$(/tmp/test_nilpy_catchable26)" = "$$(printf '%b' 'caught div (bare)\ncaught floordiv ZeroDivisionError\ncaught truediv ZeroDivisionError\ncaught int() ValueError\ncaught float() ValueError\ncaught IndexError\ncaught KeyError')"
	@# sum/max/min/any/all/sorted/set (already worked) + type(x).__name__ (new)
	./$(COMPILER) test/test_nilpy_aggregate_builtins.npy /tmp/test_nilpy_aggbuiltins26
	test "$$(/tmp/test_nilpy_aggbuiltins26)" = "$$(printf '%b' '6\n3\n1\nTrue\nTrue\n[1, 2, 3]\n3\n[1, 2, 3]\nValueError\nFoo')"
	@# a class body consisting of ONLY `pass` used to error "expected def"
	./$(COMPILER) test/test_nilpy_class_pass_body.npy /tmp/test_nilpy_clspass26
	test "$$(/tmp/test_nilpy_clspass26)" = "$$(printf '%b' 'caught: custom\nMyErr\nmade empty')"
	@# a class field's type inferred from self.x = <ctor param>, incl. inherited
	./$(COMPILER) test/test_nilpy_class_field_infer_from_ctor.npy /tmp/test_nilpy_fieldinfer26
	test "$$(/tmp/test_nilpy_fieldinfer26)" = "$$(printf '%b' '5 five\n1 one 3.14\n4 8')"
	@# `**`, `/=` (true division augmented-assign, distinct from `//=`), divmod()
	./$(COMPILER) test/test_nilpy_power_divmod_truediv.npy /tmp/test_nilpy_powdivmod26
	test "$$(/tmp/test_nilpy_powdivmod26)" = "$$(printf '%b' '1024\n0.25\n1\n-4\n-8\n512\n8.0\n9.0\n0.75\n3.5\n(3, 1)\n(-4, 1)\n(3.0, 1.5)')"
	@# a LIFTED lambda (compiled, not interpreted) discarded its own return
	@# value unconditionally -- fixed for scalar/string results
	./$(COMPILER) test/test_nilpy_lifted_lambda_return_value.npy /tmp/test_nilpy_liftedret26
	test "$$(/tmp/test_nilpy_liftedret26)" = "$$(printf '%b' '5\n('"'"'hello'"'"', '"'"'hello world'"'"')\n49\nABC\n['"'"'hi'"'"']')"
	@# sorted(key=...) now recognizes a lifted lambda / plain def / bound method
	./$(COMPILER) test/test_nilpy_sorted_key_dispatch.npy /tmp/test_nilpy_sortedkey26
	test "$$(/tmp/test_nilpy_sortedkey26)" = "$$(printf '%b' '['"'"'a'"'"', '"'"'cc'"'"', '"'"'bbb'"'"']\n['"'"'a'"'"', '"'"'cc'"'"', '"'"'bbb'"'"']\n['"'"'a'"'"', '"'"'bbb'"'"', '"'"'cc'"'"']\n[3, 2, 1]')"
	@# a builtin (`f = len`) captured as a bare value no longer segfaults
	./$(COMPILER) test/test_nilpy_builtin_value_wrapper.npy /tmp/test_nilpy_builtinval26
	test "$$(/tmp/test_nilpy_builtinval26)" = "$$(printf '%b' '['"'"'a'"'"', '"'"'cc'"'"', '"'"'bbb'"'"']\n['"'"'a'"'"', '"'"'cc'"'"', '"'"'bbb'"'"']\n3\n5\n3\n['"'"'a'"'"', '"'"'cc'"'"', '"'"'bbb'"'"']\n['"'"'a'"'"', '"'"'bbb'"'"', '"'"'cc'"'"']')"
	@# map(f, xs) / filter(f, xs) over an arbitrary callable, and filter(None, xs)
	./$(COMPILER) test/test_nilpy_map_filter_callable.npy /tmp/test_nilpy_mapfilter26
	test "$$(/tmp/test_nilpy_mapfilter26)" = "$$(printf '%b' '[2, 4, 6]\n[1, 2, 3]\n[3, 6, 9]\n[1, 2, 3]\n[2, 3]\n[2, 3]\n[1, 2, 3]')"
	@# a class defining __len__/__contains__ is measured/searched BY IT, not
	@# read as raw bytes off the wrong builtin-container overload
	./$(COMPILER) test/test_nilpy_dunder_len_contains.npy /tmp/test_nilpy_dunderlc26
	test "$$(/tmp/test_nilpy_dunderlc26)" = "$$(printf '%b' '3\nTrue\nFalse\nFalse\n3\n5\n2\nTrue\nTrue\ncaught len: TypeError\ncaught in: TypeError')"
	@# a class defining __call__ is callable as obj(args); no __call__ raises.
	@# The tail covers a DYNAMIC receiver (dict/list/call-result/parameter),
	@# which used to call the instance pointer as code and dump core
	@# (bug-nilpy-a-call-dunder-on-an-instance-is-not-dispatched).
	./$(COMPILER) test/test_nilpy_dunder_call.npy /tmp/test_nilpy_dundercall26
	test "$$(/tmp/test_nilpy_dundercall26)" = "$$(printf '%b' '15\n25\nhi\n6\ncaught: TypeError\ndict: 6\nlist: 7\ncall result: 103\nparam 1: 9\nparam 0: hi\nparam 3: 7\ninherited: 15\ninherited via dict: 15\ndynamic no-__call__: TypeError')"
	@# a class defining __getitem__/__setitem__ routes subscript read/write
	./$(COMPILER) test/test_nilpy_dunder_getitem_setitem.npy /tmp/test_nilpy_dundergetset26
	test "$$(/tmp/test_nilpy_dundergetset26)" = "$$(printf '%b' '20\n99\n[10, 99, 30]\n42\n-1\n10\ncaught: TypeError')"
	@# b.decode() with no arg (defaults to utf-8) used to segfault — no
	@# zero-argument overload, so it bound to decode(encoding) uninitialised
	./$(COMPILER) test/test_nilpy_bytes_decode.npy /tmp/test_nilpy_bytesdec26
	test "$$(/tmp/test_nilpy_bytesdec26)" = "$$(printf '%b' 'abc\nabc\n3\nabc!\nTrue\nhi')"
	@# context-manager protocol: __enter__ runs, `as` binds ITS RESULT, __exit__
	@# runs on the normal AND exception paths; with open(...) unchanged
	./$(COMPILER) test/test_nilpy_with_protocol.npy /tmp/test_nilpy_withproto26
	test "$$(/tmp/test_nilpy_withproto26)" = "$$(printf '%b' 'enter one\nbody sees ENTERVAL-one\nexit one\nenter two\nexit two\ncaught after exit\nenter outer\nenter inner\nnested body\nexit inner\nexit outer\nenter bare\nbare body\nexit bare\nfiledata\ndone')"
	@# an undefined operand pair raises a CATCHABLE TypeError at RUN time, not a
	@# build abort — try/except around it must compile and execution continue
	./$(COMPILER) test/test_nilpy_unsupported_operand_raises.npy /tmp/test_nilpy_unsupop26
	test "$$(/tmp/test_nilpy_unsupop26)" = "$$(printf '%b' 'caught add\ncaught sub\ncaught mul\ncaught truediv\ncaught neg\ncaught list concat\nstill running\n7')"
	@# reflected dunders: b.__r<op>__(a) when the left operand cannot; a class
	@# declaring BOTH must use the DIRECT one when it is on the left
	./$(COMPILER) test/test_nilpy_dunder_reflected.npy /tmp/test_nilpy_dunderrf26
	test "$$(/tmp/test_nilpy_dunderrf26)" = "$$(printf '%b' 'radd:3\nrsub:3\nrmul:3\nrtruediv:3\nrfloordiv:3\nrmod:3\nrpow:3\nradd:10\ndirect\nreflected\n7 -1 12 4.0 3 1 32\nab [1, 2] abab')"
	@# __floordiv__ / __mod__ / __pow__; str % stays FORMATTING, numeric // % **
	@# unaffected (incl. negative-operand rules)
	./$(COMPILER) test/test_nilpy_dunder_arith2.npy /tmp/test_nilpy_dunderar226
	test "$$(/tmp/test_nilpy_dunderar226)" = "$$(printf '%b' '2\n1\n343\nFLOORDIV\nMOD\nPOW\n2 -3 1 2 1024\n3.0 1.5\n5 apples')"
	@# unary dunders: abs() -> __abs__, ~ -> __invert__; no dunder = TypeError
	./$(COMPILER) test/test_nilpy_dunder_unary.npy /tmp/test_nilpy_dunderun26
	test "$$(/tmp/test_nilpy_dunderun26)" = "$$(printf '%b' '5\n7\nINVERTED\ncaught invert\n30\n9 9 2.5\n-1 -6 0')"
	@# bitwise/shift dunders on a user class; no dunder = catchable TypeError,
	@# NOT the segfault this used to be. Set/dict operators must stay intact.
	./$(COMPILER) test/test_nilpy_dunder_bitwise.npy /tmp/test_nilpy_dunderbit26
	test "$$(/tmp/test_nilpy_dunderbit26)" = "$$(printf '%b' 'AND1\nOR2\nXOR3\nLSHIFT4\nRSHIFT5\ncaught and\ncaught lshift\n[2, 3]\n[1, 2, 3]\n[1, 3]\n2\n2 7 5 16 8')"
	@# `!=` prefers a declared __ne__ (CPython calls it rather than negating
	@# __eq__); with only __eq__ the negation is still derived
	./$(COMPILER) test/test_nilpy_dunder_ne.npy /tmp/test_nilpy_dunderne26
	test "$$(/tmp/test_nilpy_dunderne26)" = "$$(printf '%b' 'NE-CALLED\nNE-CALLED\nTrue\nFalse\nFalse\nTrue\nTrue\nFalse\nTrue\nTrue\nFalse\nTrue')"
	@# list ordering is LEXICOGRAPHIC, not by heap address; cases deliberately
	@# defeat allocation order (the list allocated first must sort last)
	./$(COMPILER) test/test_nilpy_list_ordering.npy /tmp/test_nilpy_listord26
	test "$$(/tmp/test_nilpy_listord26)" = "$$(printf '%b' 'content < False\ncontent > True\ncontent <= False\ncontent >= True\neq < False\neq <= True\neq > False\neq >= True\nprefix < False\nprefix > True\nplain < True\nnested < False\neq == True\nne != True')"
	@# truthiness protocol: __bool__ wins, else __len__() != 0, else "any
	@# instance is true". Static receivers only — a parameter/container element
	@# is a runtime variant and still needs runtime dunder dispatch.
	./$(COMPILER) test/test_nilpy_dunder_bool.npy /tmp/test_nilpy_dunderbool26
	test "$$(/tmp/test_nilpy_dunderbool26)" = "$$(printf '%b' 'boolfalse falsy\nbooltrue truthy\nlenzero falsy\nlentwo truthy\nboth falsy\nplain truthy\nnot boolfalse True\nnot booltrue False\nnot lenzero True\nnot lentwo False\nnot both True\nnot plain False\ntemp falsy\nor fallback\nand kept')"
	@# ordering dunders: __lt__/__le__/__gt__/__ge__ decide </>, including
	@# CPython's REFLECTED fallback (only __lt__ defined still answers `>`);
	@# no dunder at all raises rather than comparing pointers
	./$(COMPILER) test/test_nilpy_dunder_ordering.npy /tmp/test_nilpy_dunderord26
	test "$$(/tmp/test_nilpy_dunderord26)" = "$$(printf '%b' 'False\nTrue\nFalse\nTrue\nTrue\nFalse\nFalse\nTrue\ncaught lt: TypeError\nFalse')"
	@# a name first bound inside an if/for block is visible to a later
	@# top-level assignment's RHS; def/class bodies stay real scopes
	./$(COMPILER) test/test_nilpy_module_block_scope.npy /tmp/test_nilpy_modblockscope26
	test "$$(/tmp/test_nilpy_modblockscope26)" = "$$(printf '%b' '3\n4\n4\n5\n7\nTrue\n5\n3\n2')"
	@# exec()'s host-call dispatch reads the receiver from the bound method
	@# itself, not a hardcoded "vm" key
	./$(COMPILER) test/test_nilpy_pyeval_no_vm_key.npy /tmp/test_nilpy_novmkey26
	test "$$(/tmp/test_nilpy_novmkey26)" = "[42, 43]"
	@# exec()'s expression grammar had no rule for ** at all
	./$(COMPILER) test/test_nilpy_pyeval_power_operator.npy /tmp/test_nilpy_pyevalpow26
	test "$$(/tmp/test_nilpy_pyevalpow26)" = "[1024, 512, -4, 0.5]"
	@# a promo LOCAL must start zeroed: the scope-exit PXXPromoClear releases a
	@# tag==1 payload as a string, so stale frame bytes freed a live block
	./$(COMPILER) test/test_nilpy_promo_local_zero_init.npy /tmp/test_nilpy_promozero26
	test "$$(/tmp/test_nilpy_promozero26)" = "1"
	@# select.select() actually polls (it was a stub answering "nothing ready")
	./$(COMPILER) test/test_nilpy_select_stdin_ready.npy /tmp/test_nilpy_selready26
	/tmp/test_nilpy_selready26 < test/test_nilpy_select_stdin_ready.stdin | diff -u test/test_nilpy_select_stdin_ready.expected -
	@# a host method whose params MIX a variant with register-sized kinds
	./$(COMPILER) test/test_nilpy_pyeval_host_mixed_params.npy /tmp/test_nilpy_pyevalmix26
	/tmp/test_nilpy_pyevalmix26 | diff -u test/test_nilpy_pyeval_host_mixed_params.expected -
	@# a comprehension's loop variable is scoped to itself, not the enclosing
	@# scope: an outer binding of the same name must survive untouched
	./$(COMPILER) test/test_nilpy_comprehension_scope.npy /tmp/test_nilpy_compscope26
	test "$$(/tmp/test_nilpy_compscope26)" = "$$(printf '%b' '5 [1, 2, 3]\nouter {'"'"'a'"'"': 1, '"'"'b'"'"': 1}\n99 [1, 2]\nouter [[1, 2]]\n[1, 2, 3] [9]\n7 [0, 2, 4]')"
	./$(COMPILER) test/test_nilpy_dynattr.npy /tmp/test_nilpy_dynattr26
	test "$$(/tmp/test_nilpy_dynattr26)" = "$$(printf '%b' '105\n110')"
	./$(COMPILER) test/test_nilpy_dynattr_class.npy /tmp/test_nilpy_dynattr_class26
	test "$$(/tmp/test_nilpy_dynattr_class26)" = "105"
	./$(COMPILER) test/test_nilpy_dynattr_augassign.npy /tmp/test_nilpy_dynattr_augassign26
	test "$$(/tmp/test_nilpy_dynattr_augassign26)" = "15"
	./$(COMPILER) test/test_nilpy_lambda_stub.npy /tmp/test_nilpy_lambda_stub26
	test "$$(/tmp/test_nilpy_lambda_stub26)" = "$$(printf '%b' 'A\nB\nok')"
	test "$$(/tmp/test_nilpy_variant_subscript26)" = "$$(printf '%b' '1\n2\n20\n99')"
	./$(COMPILER) test/test_nilpy_dyncall.npy /tmp/test_nilpy_dyncall26
	test "$$(/tmp/test_nilpy_dyncall26)" = "42"
	./$(COMPILER) test/test_nilpy_exec_stub.npy /tmp/test_nilpy_exec_stub26
	test "$$(/tmp/test_nilpy_exec_stub26)" = "5"
	./$(COMPILER) test/test_nilpy_genexpr.npy /tmp/test_nilpy_genexpr26
	test "$$(/tmp/test_nilpy_genexpr26)" = "$$(printf '%b' '1-2-3\nA, B, C\n3\n6')"
	./$(COMPILER) test/test_nilpy_list_comp.npy /tmp/test_nilpy_list_comp26
	test "$$(/tmp/test_nilpy_list_comp26)" = "$$(printf '%b' '1\n4\n9\n16\n10\n11\n12\n2\n3\n4')"
	./$(COMPILER) test/test_nilpy_str_concat.npy /tmp/test_nilpy_str_concat26
	test "$$(/tmp/test_nilpy_str_concat26)" = "$$(printf '%b' 'abcd\nefgh\nx=5 t=hi end\nplain and 5\nfirst line second line')"
	./$(COMPILER) test/test_nilpy_trailing_comma.npy /tmp/test_nilpy_trailing_comma26
	test "$$(/tmp/test_nilpy_trailing_comma26)" = "$$(printf '%b' 'exec mode=interpret token=dup\n7')"
	./$(COMPILER) test/test_nilpy_for_variant.npy /tmp/test_nilpy_for_variant26
	test "$$(/tmp/test_nilpy_for_variant26)" = "$$(printf '%b' '10\n20\n30')"
	./$(COMPILER) test/test_nilpy_unpack_callable.npy /tmp/test_nilpy_unpack_callable26
	test "$$(/tmp/test_nilpy_unpack_callable26)" = "$$(printf '%b' 'native ran\n5\n6\n7\n8')"
	# bug-nilpy-void-def-assigned-and-called-crashes: a `-> None` def assigned to
	# a plain name, then called through the generic dynamic-call bridge (no
	# Callable-typed field/param signature involved)
	./$(COMPILER) test/test_nilpy_void_def_value_call.npy /tmp/test_nilpy_voiddefval26
	test "$$(/tmp/test_nilpy_voiddefval26)" = "$$(printf '%b' 'native ran\nNone\ndone\nNone\n1')"
	./$(COMPILER) test/test_nilpy_optional_return.npy /tmp/test_nilpy_optional_return26
	test "$$(/tmp/test_nilpy_optional_return26)" = "$$(printf '%b' 'native\nternary ok\n7')"
	./$(COMPILER) test/test_nilpy_encode.npy /tmp/test_nilpy_encode26
	test "$$(/tmp/test_nilpy_encode26)" = "$$(printf '%b' '3\n65\n67\n2\nhi\nhi\n4\n90\n2\nb')"
	./$(COMPILER) test/test_nilpy_bytes_ann.npy /tmp/test_nilpy_bytes_ann26
	./$(COMPILER) test/test_nilpy_bytes_literal.npy /tmp/test_nilpy_bytes_literal26
	test "$$(/tmp/test_nilpy_bytes_literal26)" = "$$(printf '%b' '5\n104\n1\n-1\n4')"
	./$(COMPILER) test/test_nilpy_method_str_chain.npy /tmp/test_nilpy_method_str_chain26
	test "$$(/tmp/test_nilpy_method_str_chain26)" = "HI"
	test "$$(/tmp/test_nilpy_bytes_ann26)" = "$$(printf '%b' '3\n65\n0')"
	./$(COMPILER) test/test_nilpy_tuples.npy /tmp/test_nilpy_tuples26
	test "$$(/tmp/test_nilpy_tuples26)" = "$$(printf '%b' 'ab\ncd\nef\n6\np\nq\n3\n5\n6')"
	./$(COMPILER) test/test_nilpy_tuple_in_find.npy /tmp/test_nilpy_tuple_in_find26
	test "$$(/tmp/test_nilpy_tuple_in_find26)" = "$$(printf '%b' 'True\nTrue\nFalse\n3\n1\n4\n-1\n3\n-1')"
	./$(COMPILER) test/test_nilpy_expr_arg.npy /tmp/test_nilpy_expr_arg26
	test "$$(/tmp/test_nilpy_expr_arg26)" = "$$(printf '%b' 'xy\n|x|\n|y|\n4\n6')"
	./$(COMPILER) test/test_nilpy_attrs.npy /tmp/test_nilpy_attrs26
	test "$$(/tmp/test_nilpy_attrs26)" = "$$(printf '%b' 'True\nFalse\n7\nhi\n42\nfallback')"
	./$(COMPILER) test/test_nilpy_stmt_after_for.npy /tmp/test_nilpy_stmt_after_for26
	test "$$(/tmp/test_nilpy_stmt_after_for26)" = "$$(printf '%b' '3\n3\n2\n90')"
	./$(COMPILER) test/test_nilpy_ctor_kwargs.npy /tmp/test_nilpy_ctor_kwargs26
	test "$$(/tmp/test_nilpy_ctor_kwargs26)" = "$$(printf '%b' 'dup\n3\nTrue\nswap\n7\nFalse\nover\n9\n\n0')"
	./$(COMPILER) test/test_nilpy_variant_bitwise.npy /tmp/test_nilpy_variant_bitwise26
	test "$$(/tmp/test_nilpy_variant_bitwise26)" = "$$(printf '%b' '44\n255\n240\n256\n16\n-4\n255\n1\n3\ncaught RuntimeError\ncaught via Exception base')"
	./$(COMPILER) test/test_nilpy_property.npy /tmp/test_nilpy_property26
	/tmp/test_nilpy_property26 | diff -u test/test_nilpy_property.expected -
	./$(COMPILER) test/test_nilpy_float_conv.npy /tmp/test_nilpy_float_conv26
	test "$$(/tmp/test_nilpy_float_conv26)" = "$$(printf '%b' '3.5\n-2.25\n10.0\n1000.0\n0.025\n7.0\n3.5\ncaught float ValueError\ncaught empty float\ndone')"
	./$(COMPILER) test/test_nilpy_none_local.npy /tmp/test_nilpy_none_local26
	test "$$(/tmp/test_nilpy_none_local26)" = "$$(printf '%b' '97\n-1')"
	./$(COMPILER) test/test_nilpy_int_base.npy /tmp/test_nilpy_int_base26
	test "$$(/tmp/test_nilpy_int_base26)" = "$$(printf '255\n2\n511\n-26\n255\n42\n7\n1295\ncaught ValueError\ncaught empty\ncaught bad base\ndone')"
	./$(COMPILER) test/test_nilpy_ternary.npy /tmp/test_nilpy_ternary26
	test "$$(/tmp/test_nilpy_ternary26)" = "$$(printf '%b' '-1\n0\npos\nb\nc\n10\n20')"
	./$(COMPILER) test/test_nilpy_os_path.npy /tmp/test_nilpy_os_path26
	test "$$(/tmp/test_nilpy_os_path26)" = "$$(printf 'True\nFalse\n/a/b\n/a/b\n/b\n/a/b\n/\n\nTrue\nFalse\n/a/c\n/a/b')"
	./$(COMPILER) test/test_nilpy_suites.npy /tmp/test_nilpy_suites26
	test "$$(/tmp/test_nilpy_suites26)" = "$$(printf '0\n1\n2\n14\n1\n2\n3\nbig\n3')"
	./$(COMPILER) test/test_nilpy_truthiness.npy /tmp/test_nilpy_truthiness26
	test "$$(/tmp/test_nilpy_truthiness26)" = "$$(printf 's truthy\ne falsy\nnot s -> False\nTrue\nFalse')"
	./$(COMPILER) test/test_nilpy_print_kwargs.npy /tmp/test_nilpy_print_kwargs26
	test "$$(/tmp/test_nilpy_print_kwargs26 2>/dev/null)" = "$$(printf 'ab\nx|y|\nplain\nmulti 1 2\nafter stderr\nnl end\nflush only')"
	test "$$(/tmp/test_nilpy_print_kwargs26 2>&1 >/dev/null)" = "to stderr"
	./$(COMPILER) test/test_nilpy_to_bytes.npy /tmp/test_nilpy_to_bytes26
	test "$$(/tmp/test_nilpy_to_bytes26)" = "$$(printf '8\n10\n0\n10\n254\n255\n-2\n255\n0\n255\n-1\n255\n8\n44\n1\n300\n300\n4\n258\n-2\n6\n8 0 4\n1 2 2\n71\n70\n71\n201\n10\n8 101\n9\n8 0 1\n1 70\n9\n[1, 2, 8]')"
	@# input() / input(prompt): stdin-driven, like test_eof_stdin.pas. `Input` is a
	@# standard Pascal identifier, so the name needs its own NilPy arm.
	./$(COMPILER) test/test_nilpy_input_builtin.npy /tmp/test_nilpy_input26
	test "$$(printf 'one\ntwo\n' | /tmp/test_nilpy_input26)" = "$$(printf 'first:one\nprompt> second:two\n3 3\nONE\none-two\no t\nTrue False')"
	@# input() at EOF RAISES EOFError — it is what ends `while True: input()`.
	@# Returning '' made uforth's repl() spin forever (regression-test-uforth-00).
	./$(COMPILER) test/test_nilpy_input_eof_raises.npy /tmp/test_nilpy_input_eof26
	/tmp/test_nilpy_input_eof26 < test/test_nilpy_input_eof_raises.stdin | diff -u test/test_nilpy_input_eof_raises.expected -
	@# print(sep=) — read by a prescan, since separators are injected before
	@# the keyword is reached; nested sep= must not be mistaken for print's
	./$(COMPILER) test/test_nilpy_print_sep.npy /tmp/test_nilpy_print_sep26
	test "$$(/tmp/test_nilpy_print_sep26)" = "$$(printf 'a-b\na, b, c\n1|2|3\nab\nx\na b\na-b!\nx+y z\na_m n\nq>r\nn=5::tail\n{'"'"'a'"'"': 1}#d\n[1, 2] l')"
	@# .format() with three or more placeholders (and with none)
	./$(COMPILER) test/test_nilpy_format_multiarg.npy /tmp/test_nilpy_format_multiarg26
	test "$$(/tmp/test_nilpy_format_multiarg26)" = "$$(printf '1 two 3.5\n1 3.5 two\n3.5-3.5\n    1|two  |3.50\n1 2 3 4 5 6 7 8\n1\n1 two\ntwotwo\n   1\n{literal} 1\nplain')"
	@# list(<bytes>)/tuple(<bytes>) — the byte VALUES, not an empty list
	./$(COMPILER) test/test_nilpy_list_of_bytes.npy /tmp/test_nilpy_list_of_bytes26
	test "$$(/tmp/test_nilpy_list_of_bytes26)" = "$$(printf '[44, 1, 0, 0, 0, 0, 0, 0]\n(44, 1, 0, 0, 0, 0, 0, 0)\n8\n44\n1\n45\n[44, 1, 0, 0]\n[44, 1, 0, 0]\n[]')"
	@# the guard: a user class declaring to_bytes must win over the intrinsic
	./$(COMPILER) test/test_nilpy_to_bytes_user_class_wins.npy /tmp/test_nilpy_tb_userwins26
	test "$$(/tmp/test_nilpy_tb_userwins26)" = "$$(printf 'packet:7\npacket:1\nframe:2\nreg:16\nreg:32\nregcount:8')"
	./$(COMPILER) test/test_nilpy_comp_iterable.npy /tmp/test_nilpy_comp_iterable26
	test "$$(/tmp/test_nilpy_comp_iterable26)" = "$$(printf '2\n3\n4\nr 0\nr 1\nr 2\n66')"
	./$(COMPILER) test/test_nilpy_mixed_return_variant.npy /tmp/test_nilpy_mixed_return_variant26
	test "$$(/tmp/test_nilpy_mixed_return_variant26)" = "$$(printf 'pos\n42\n1 2\na b\n43')"
	./$(COMPILER) test/test_nilpy_variant_str_boxing.npy /tmp/test_nilpy_variant_str_boxing26
	test "$$(/tmp/test_nilpy_variant_str_boxing26)" = "$$(printf 'hello changed\nabcdef\npos\n500000 abcdef')"
	./$(COMPILER) test/test_nilpy_escape_decode.npy /tmp/test_nilpy_escape_decode26
	test "$$(/tmp/test_nilpy_escape_decode26)" = "$$(printf '2\n0 255\n3 65 99\n3\n1\n5\n4')"
	./$(COMPILER) test/test_nilpy_comp_filter.npy /tmp/test_nilpy_comp_filter26
	test "$$(/tmp/test_nilpy_comp_filter26)" = "$$(printf '4 2 5\n3 0 4 8\n0\n4 16\n2 ab cde\n3\n3')"
	@# a def with no return, or one falling off the end, must not leak
	@# whatever garbage a prior call left in the return register/slot
	./$(COMPILER) test/test_nilpy_implicit_return_none.npy /tmp/test_nilpy_implret26
	test "$$(/tmp/test_nilpy_implret26)" = "$$(printf '1073794252\n0\nTrue\n0\nTrue')"
	@# a[i] = b[j] = v must store into EVERY target, not just the rightmost
	./$(COMPILER) test/test_nilpy_chained_subscript_assign.npy /tmp/test_nilpy_chainedsub26
	test "$$(/tmp/test_nilpy_chainedsub26)" = "$$(printf '[3, 3]\n%s\n42 42\n[6, 2, 3]' "['x', 'y'] 7 7")"
	@# enumerate/zip/items/most_common pairs print with parens, like real tuples
	./$(COMPILER) test/test_nilpy_builtin_pairs_are_tuples.npy /tmp/test_nilpy_pairtuples26
	test "$$(/tmp/test_nilpy_pairtuples26)" = "$$(printf '%b' "[(0, 'a'), (1, 'b')]\n[(1, 'a'), (2, 'b')]\n[('a', 1), ('b', 2)]\n[('a', 3), ('b', 1), ('c', 1)]")"
	@# chr() refuses an out-of-byte-range argument instead of silently truncating
	./$(COMPILER) test/test_nilpy_chr_range_check.npy /tmp/test_nilpy_chrrange26
	test "$$(/tmp/test_nilpy_chrrange26)" = "$$(printf '%b' 'A\n233\ncaught: chr out of range\ncaught: chr negative')"
	@# min()/max() over a bare string (any iterable), not just a list or two scalars
	./$(COMPILER) test/test_nilpy_minmax_over_string.npy /tmp/test_nilpy_minmax26
	test "$$(/tmp/test_nilpy_minmax26)" = "$$(printf '%b' 'c\na\n3\n1\n7\n2.1')"
	@# "{} and {}".format(a, b) -- two positional placeholders, not just one
	./$(COMPILER) test/test_nilpy_str_format_multiarg.npy /tmp/test_nilpy_fmtmulti26
	test "$$(/tmp/test_nilpy_fmtmulti26)" = "$$(printf 'a and 2\n3.1 then x\n5')"
	@# math.fabs and os.path.basename were unresolvable names
	./$(COMPILER) test/test_nilpy_math_fabs_os_basename.npy /tmp/test_nilpy_mathos26
	test "$$(/tmp/test_nilpy_mathos26)" = "$$(printf '3.5\n2.0\nc.txt\n\nnoslash')"
	@# a unit-level proc called qualified can omit a trailing defaulted parameter
	./$(COMPILER) test/test_nilpy_qualified_proc_omitted_default.npy /tmp/test_nilpy_qualdefault26
	test "$$(/tmp/test_nilpy_qualdefault26)" = "$$(printf 'a 0\nb 5\nc 0 False\nd 7 True')"
	@# a keyword argument resolves against the whole OVERLOAD SET, not just the
	@# first same-named routine found (unit-qualified proc and class method)
	./$(COMPILER) test/test_nilpy_kwarg_overload_set.npy /tmp/test_nilpy_kwovlset26
	test "$$(/tmp/test_nilpy_kwovlset26)" = "$$(printf 'hi\nhi\nHI\nhi\nraw: a raw string\nnamed color=red width=3\nnamed color= width=9')"
	@# a lambda value stored in a name and CALLED, not just passed around
	./$(COMPILER) test/test_nilpy_lambda_real_value.npy /tmp/test_nilpy_lambdareal26
	test "$$(/tmp/test_nilpy_lambdareal26)" = "$$(printf '6\n12')"
	@# map()/filter() over a lambda and a named def, via list() and via for
	./$(COMPILER) test/test_nilpy_map_filter_lambda_def.npy /tmp/test_nilpy_mapfilterld26
	test "$$(/tmp/test_nilpy_mapfilterld26)" = "$$(printf '%b' '[2, 3, 4]\n[2, 3, 4]\n[2, 3]\n2\n4\n6\n2\n3\n[2, 4, 6]\n[2, 3]\n2\n4\n6\n2\n3')"
	@# list.sort(reverse=) -- the in-place method, not just the sorted() function
	./$(COMPILER) test/test_nilpy_list_sort_method.npy /tmp/test_nilpy_sortmethod26
	/tmp/test_nilpy_sortmethod26 | diff -u test/test_nilpy_list_sort_method.expected -
	@# d[k] = None stores a real None, and a def with no return annotation parses
	./$(COMPILER) test/test_nilpy_none_variant_residuals.npy /tmp/test_nilpy_noneresid26
	test "$$(/tmp/test_nilpy_noneresid26)" = "$$(printf 'None\nTrue\nhi')"
	@# a bare generator expression as a call argument and in a return statement
	./$(COMPILER) test/test_nilpy_genexpr_arg.npy /tmp/test_nilpy_genexprarg26
	test "$$(/tmp/test_nilpy_genexprarg26)" = "$$(printf '%b' 'def __body__():\n    a\n    b\n    c\n12\n[2, 3, 4]\nTrue')"
	@# a DOTTED package import (from a.b import c / import a.b / import a.b as x)
	./$(COMPILER) test/test_nilpy_dotted_package_import.npy /tmp/test_nilpy_dottedimport26
	test "$$(/tmp/test_nilpy_dottedimport26)" = "dotted imports ok"
	@# a nested def's own default parameter captures by value, at definition time
	./$(COMPILER) test/test_nilpy_nested_def_default_capture.npy /tmp/test_nilpy_defcap26
	test "$$(/tmp/test_nilpy_defcap26)" = "$$(printf '11\n21\n15')"
	@# a def parameter default naming an ENCLOSING local, and mem[a:b] = mem[c:d]
	./$(COMPILER) test/test_nilpy_closure_captured_default_and_slice_assign.npy /tmp/test_nilpy_closuredefslice26
	test "$$(/tmp/test_nilpy_closuredefslice26)" = "$$(printf 'hi\n97 98 99 97 98 99')"
	@# str.join preallocated instead of reallocating per item (perf)
	./$(COMPILER) test/test_nilpy_str_join_perf_fix.npy /tmp/test_nilpy_joinperf26
	test "$$(/tmp/test_nilpy_joinperf26)" = "$$(printf '%b' 'a,bb,ccc\nxyz\n\nsingle\none, two, three, four\ncaught type error')"
	./$(COMPILER) test/test_nilpy_return_none_variant.npy /tmp/test_nilpy_return_none_variant26
	test "$$(/tmp/test_nilpy_return_none_variant26)" = "$$(printf 'a NONE\nb NONE\nc 9')"
	./$(COMPILER) test/test_nilpy_none_str_field.npy /tmp/test_nilpy_none_str_field26
	/tmp/test_nilpy_none_str_field26 | diff -u test/test_nilpy_none_str_field.expected -
	./$(COMPILER) test/test_nilpy_bytes_repr.npy /tmp/test_nilpy_bytes_repr26
	test "$$(/tmp/test_nilpy_bytes_repr26)" = "$$(printf "b'abc\\\\n'\nb'abc'\nb'held'\nb'tab\\\\there'\nb\"q'q\"\nb'dq\"dq'")"
	./$(COMPILER) test/test_nilpy_slices.npy /tmp/test_nilpy_slices26
	test "$$(/tmp/test_nilpy_slices26)" = "$$(printf 'cde\nabc\nfgh\nabcdefgh\nfgh\nab\ndef\n\n\nab\n3\n3\n65\n67\n2\n66\n90\n65\n66\n0\n3\n20\n20\n40\n50\n5')"
	./$(COMPILER) test/test_nilpy_set.npy /tmp/test_nilpy_set26
	test "$$(/tmp/test_nilpy_set26)" = "$$(printf '1\n3\nTrue\nTrue\nFalse\nTrue\n0\n2\nTrue\nFalse\n2\nTrue\nFalse\n1')"
	./$(COMPILER) test/test_nilpy_dict.npy /tmp/test_nilpy_dict26
	test "$$(/tmp/test_nilpy_dict26)" = "$$(printf '2\n3\n2\nTrue\nFalse\n3\n-1\n2\n200\n1\nFalse\n2\n2\n7\n8\n2\n1\n2\n0\n1\n3\nFalse\n0\nFalse\n9\n1\n4\n1')"
	./$(COMPILER) test/test_nilpy_literals.npy /tmp/test_nilpy_literals26
	test "$$(/tmp/test_nilpy_literals26)" = "$$(printf '65536\n15\n10\n1000000\ntri\nple')"
	./$(COMPILER) test/test_nilpy_operators.npy /tmp/test_nilpy_operators26
	test "$$(/tmp/test_nilpy_operators26)" = "$$(printf '61440\n65535\n3855\n1024\n256\n255\n32\n240\n15\n12\n24\n4\n1\n8\n9\n6\n96\n24\n142\n140\n2.5\n2.0\n3')"
	./$(COMPILER) test/test_nilpy_annotated.npy /tmp/test_nilpy_annotated26
	test "$$(/tmp/test_nilpy_annotated26)" = "$$(printf 'True\n42\n1.5\nhi')"
	./$(COMPILER) test/test_nilpy_list.npy /tmp/test_nilpy_list26
	test "$$(/tmp/test_nilpy_list26)" = "$$(printf '3\n1\n2\n3\n3\n4\n10\n42\n10\n3\n0\nhello\n2.5\nTrue\n3\n9\n1\n2\n0\n3\na\nccc\n2\n20\n2')"
	./$(COMPILER) test/test_nilpy_factory.npy /tmp/test_nilpy_factory26
	test "$$(/tmp/test_nilpy_factory26)" = "$$(printf '0\n0\n2\n0\n6')"
	./$(COMPILER) test/test_nilpy_classvar_counter.npy /tmp/test_nilpy_classvar_counter26
	test "$$(/tmp/test_nilpy_classvar_counter26)" = "$$(printf 'dup 1\nswap 2\ndrop 3')"
	./$(COMPILER) test/test_nilpy_membership.npy /tmp/test_nilpy_membership26
	test "$$(/tmp/test_nilpy_membership26)" = "$$(printf 'True\nFalse\nTrue\nTrue\nFalse\nTrue\nTrue\nFalse\nFalse\nTrue\nTrue\nFalse\n3\n7\n3\n7\n-1\n2.5')"
	# ...and membership over OBJECTS consults __eq__ (it compared boxed handles,
	# so an equal-but-distinct object read as absent). Covers in/not in/index/
	# count/remove/dict keys, both __eq__ shapes, and the no-__eq__ identity control.
	./$(COMPILER) test/test_nilpy_membership_eq_dunder.npy /tmp/test_nilpy_memeq26
	/tmp/test_nilpy_memeq26 | diff -u test/test_nilpy_membership_eq_dunder.expected -
	# ...and the __hash__ half of that pair, which decides the BUCKET: an
	# unannotated `def __hash__` returns a Variant, the guard admitted only the
	# integer RetKinds, so the key hashed by IDENTITY and an __eq__-equal key
	# missed — nondeterministically, since collisions are memory layout.
	# Covers both dunder spellings, a real bucket collision, and sets.
	./$(COMPILER) test/test_nilpy_user_hash_dict_key.npy /tmp/test_nilpy_userhash26
	/tmp/test_nilpy_userhash26 | diff -u test/test_nilpy_user_hash_dict_key.expected -
	# A method chain rooted at a frontend INTRINSIC: open(p).read().strip() was
	# "unexpected token" at the SECOND link, because the suffix cluster was a
	# sequence of loops and a suffix was only reachable in the order they
	# appeared. Covers the sibling intrinsics too — a per-intrinsic fix would
	# have left str()/int() chains broken.
	./$(COMPILER) test/test_nilpy_intrinsic_result_chain.npy /tmp/test_nilpy_chain26
	/tmp/test_nilpy_chain26 | diff -u test/test_nilpy_intrinsic_result_chain.expected -
	# WHICH string type a file's reads yield is decided by the MODE, a run-time
	# value — so four accessors hard-coding it got four answers wrong in one
	# direction or the other (text read(n)/readline gave bytes, binary
	# read()/readlines gave str). On pinned this file does not even COMPILE:
	# readline().strip() was "TPyBytes has no method strip".
	./$(COMPILER) test/test_nilpy_file_read_follows_the_mode.npy /tmp/test_nilpy_readmode26
	/tmp/test_nilpy_readmode26 | diff -u test/test_nilpy_file_read_follows_the_mode.expected -
	# isinstance(x, t) with t a VALUE — an aliased class, or a tuple of types
	# held in a name (the six idiom). The lowering resolved it by NAME, so
	# `A = B` then isinstance(x, A) was a COMPILE error for a name that had
	# just constructed an instance. An UNBOUND name still errors by name.
	./$(COMPILER) test/test_nilpy_isinstance_over_a_type_value.npy /tmp/test_nilpy_isinstval26
	/tmp/test_nilpy_isinstval26 | diff -u test/test_nilpy_isinstance_over_a_type_value.expected -
	# A 2- or 3-parameter lambda is COMPILED, not shipped as pyeval source and
	# re-walked per call. An output diff cannot see this — the answers were
	# already right — so the assertion is that NO lambda body text survives in
	# the binary. bug-nilpy-multi-parameter-lambdas-are-still-interpreted
	./$(COMPILER) test/test_nilpy_multi_param_lambda_is_compiled.npy /tmp/test_nilpy_mplam26
	/tmp/test_nilpy_mplam26 | diff -u test/test_nilpy_multi_param_lambda_is_compiled.expected -
	test "$$(strings /tmp/test_nilpy_mplam26 | grep -cE 'a \+ b \+ k|a \* b \+ c|x \* 2')" = "0"
	# ...and a FOUR-argument call through a callable VALUE, which had no runtime
	# dispatcher at all: the old lowering called through the callee payload as a
	# code ADDRESS, correct for a def and a SEGFAULT for a lambda.
	./$(COMPILER) test/test_nilpy_arity_four_dynamic_call.npy /tmp/test_nilpy_a4call26
	/tmp/test_nilpy_a4call26 | diff -u test/test_nilpy_arity_four_dynamic_call.expected -
	# pyeval's runtime errors are catchable RAISES, not writeln + Halt: a
	# try/except around an interpreted body could not run at all. Reaching the
	# interpreted path needs a lambda capturing a LOCAL managed string (the one
	# shape the lift still refuses) — a module global would compile and prove
	# nothing. bug-nilpy-pyeval-runtime-errors-halt-instead-of-raising
	./$(COMPILER) test/test_nilpy_pyeval_errors_are_catchable.npy /tmp/test_nilpy_pyevalerr26
	/tmp/test_nilpy_pyevalerr26 | diff -u test/test_nilpy_pyeval_errors_are_catchable.expected -
	# hash(x): pylib's PyVarHashKey exposed. Every row asserts the INVARIANT
	# (equal values hash equal), never a number — CPython salts strings per
	# process. bug-n-hash-builtin-is-not-implemented
	./$(COMPILER) test/test_nilpy_hash_builtin.npy /tmp/test_nilpy_hash26
	/tmp/test_nilpy_hash26 | diff -u test/test_nilpy_hash_builtin.expected -
	! ./$(COMPILER) test/test_nilpy_isinstance_unknown_type_fail.npy /tmp/test_nilpy_isinstfail26 2>&1 | grep -q 'ok:'
	# ...and sorting OBJECTS consults __lt__ (via the reflected arm) or __gt__;
	# it fell through to a numeric compare and raised "expected a number".
	./$(COMPILER) test/test_nilpy_sort_lt_dunder.npy /tmp/test_nilpy_sortlt26
	/tmp/test_nilpy_sortlt26 | diff -u test/test_nilpy_sort_lt_dunder.expected -
	# divmod() over objects: __divmod__ / reflected __rdivmod__, and a TypeError
	# (not a runtime-219 crash) for a class declaring neither.
	./$(COMPILER) test/test_nilpy_divmod_dunder.npy /tmp/test_nilpy_divmod26
	/tmp/test_nilpy_divmod26 | diff -u test/test_nilpy_divmod_dunder.expected -
	# repr() of a USER object: it had no overload, so a class handle was read as
	# a string and answered ''. Covers direct-vs-boxed and the retain hazard.
	./$(COMPILER) test/test_nilpy_repr_of_user_object.npy /tmp/test_nilpy_reprobj26
	/tmp/test_nilpy_reprobj26 | diff -u test/test_nilpy_repr_of_user_object.expected -
	# `del c[k]` dispatches __delitem__ -- both node shapes (a class with
	# __getitem__ too, and one with only __delitem__), key evaluated once.
	./$(COMPILER) test/test_nilpy_delitem_dunder.npy /tmp/test_nilpy_delitem26
	/tmp/test_nilpy_delitem26 | diff -u test/test_nilpy_delitem_dunder.expected -
	# arithmetic/ordering dunders dispatch on a VARIANT operand too (compile-time
	# dispatch keys on a static class a variant does not have). All 8 arith entry
	# points plus pycmp_v's three-way ordering.
	./$(COMPILER) test/test_nilpy_variant_operand_arith_dunders.npy /tmp/test_nilpy_vararith26
	/tmp/test_nilpy_vararith26 | diff -u test/test_nilpy_variant_operand_arith_dunders.expected -
	# a scalar-then-class rebind INSIDE a block widens (it kept the scalar's type,
	# so the operands were added as handles). if/try/for/while + scalar controls.
	./$(COMPILER) test/test_nilpy_block_nested_rebind_widens.npy /tmp/test_nilpy_blkrebind26
	/tmp/test_nilpy_blkrebind26 | diff -u test/test_nilpy_block_nested_rebind_widens.expected -
	# a COUNT-FIRST sequence repeat returned from a def (`return u * [7]`) infers
	# as the sequence, not Integer. Controls pin ordinary `*` and `**`.
	./$(COMPILER) test/test_nilpy_reversed_sequence_repeat_return.npy /tmp/test_nilpy_revrepeat26
	/tmp/test_nilpy_revrepeat26 | diff -u test/test_nilpy_reversed_sequence_repeat_return.expected -
	# a method name two pylib containers both declare, on a receiver with no
	# static class, dispatches at RUNTIME; and a conditional whose arms disagree
	# widens instead of claiming the then-arm's type.
	./$(COMPILER) test/test_nilpy_variant_receiver_method_dispatch.npy /tmp/test_nilpy_vardispatch26
	/tmp/test_nilpy_vardispatch26 | diff -u test/test_nilpy_variant_receiver_method_dispatch.expected -
	# startswith/endswith with a TUPLE of prefixes answered False silently.
	./$(COMPILER) test/test_nilpy_startswith_tuple.npy /tmp/test_nilpy_swtuple26
	/tmp/test_nilpy_swtuple26 | diff -u test/test_nilpy_startswith_tuple.expected -
	# `0 ** 0.5` HUNG (PyMathLn's normalising loop never terminates for x <= 0).
	./$(COMPILER) test/test_nilpy_pow_domain.npy /tmp/test_nilpy_powdomain26
	/tmp/test_nilpy_powdomain26 | diff -u test/test_nilpy_pow_domain.expected -
	# `f(1, b=7)` on a def that also has *rest/**kw was rejected as "multiple
	# values for parameter 'b'" -- the star packer filled b's default first.
	./$(COMPILER) test/test_nilpy_kwarg_with_star_params.npy /tmp/test_nilpy_kwstar26
	/tmp/test_nilpy_kwstar26 | diff -u test/test_nilpy_kwarg_with_star_params.expected -
	# str.isascii() -- note the EMPTY string is True, unlike its isspace/isdigit
	# siblings which are False.
	./$(COMPILER) test/test_nilpy_str_isascii.npy /tmp/test_nilpy_isascii26
	/tmp/test_nilpy_isascii26 | diff -u test/test_nilpy_str_isascii.expected -
	# bytes.hex() -- zero-padded to two digits per byte, lowercase.
	./$(COMPILER) test/test_nilpy_bytes_hex.npy /tmp/test_nilpy_byteshex26
	/tmp/test_nilpy_byteshex26 | diff -u test/test_nilpy_bytes_hex.expected -
	# bytes vs bytearray are distinct Python types over one TPyBytes: repr,
	# type().__name__ and isinstance, and the tag must survive slice/concat.
	./$(COMPILER) test/test_nilpy_bytearray_vs_bytes.npy /tmp/test_nilpy_bavsb26
	/tmp/test_nilpy_bavsb26 | diff -u test/test_nilpy_bytearray_vs_bytes.expected -
	# a multi-argument exception ctor SEGFAULTED (Exception.Create takes one msg;
	# the surplus args were emitted anyway). CPython renders them as a tuple.
	./$(COMPILER) test/test_nilpy_exception_multi_arg.npy /tmp/test_nilpy_excmulti26
	/tmp/test_nilpy_excmulti26 | diff -u test/test_nilpy_exception_multi_arg.expected -
	# os.path.split / normpath / getsize / expanduser
	./$(COMPILER) test/test_nilpy_os_path_more.npy /tmp/test_nilpy_ospathmore26
	/tmp/test_nilpy_ospathmore26 | diff -u test/test_nilpy_os_path_more.expected -
	# set.symmetric_difference / set.isdisjoint / dict.fromkeys(seq, value)
	./$(COMPILER) test/test_nilpy_set_dict_gaps.npy /tmp/test_nilpy_setdictgaps26
	/tmp/test_nilpy_setdictgaps26 | diff -u test/test_nilpy_set_dict_gaps.expected -
	# str.maketrans / str.translate -- CPython's ordinal-keyed dict table exactly,
	# so a hand-written dict literal works as a table too.
	./$(COMPILER) test/test_nilpy_str_translate.npy /tmp/test_nilpy_strtrans26
	/tmp/test_nilpy_strtrans26 | diff -u test/test_nilpy_str_translate.expected -
	# repr() of a VARIANT holding a user instance was '' (two variant reprs, only
	# one knew about objects); and a tuple-unpack target was undefined in a later
	# assignment's RHS. Both found by running a realistic program vs CPython.
	./$(COMPILER) test/test_nilpy_repr_of_variant_object.npy /tmp/test_nilpy_reprvar26
	/tmp/test_nilpy_reprvar26 | diff -u test/test_nilpy_repr_of_variant_object.expected -
	# dict.update(<variant>) SEGFAULTED -- two typed overloads, and an
	# unannotated parameter matches neither, so it read a dict as a list.
	./$(COMPILER) test/test_nilpy_dict_update_variant.npy /tmp/test_nilpy_dictupdv26
	/tmp/test_nilpy_dictupdv26 | diff -u test/test_nilpy_dict_update_variant.expected -
	# The shared argument COUNTER tracked () and [] but not BRACES, so every comma
	# inside a dict/set literal argument counted as an argument SEPARATOR: a
	# 2-entry literal made update() look 2-arity, no overload matched, and
	# resolution fell back to the first-declared one (TPyList) which read a dict
	# as a list. A trailing comma miscounted identically with no literal at all.
	./$(COMPILER) test/test_nilpy_call_arg_count_braces_and_trailing_comma.npy /tmp/test_nilpy_argcnt26
	/tmp/test_nilpy_argcnt26 | diff -u test/test_nilpy_call_arg_count_braces_and_trailing_comma.expected -
	# An attribute off a subscript of a CALL RESULT answered 7 -- VT_OBJECT, the
	# variant TAG word -- for every field whatever its type. The NilPy selector
	# loop had a variant arm for `.name(` but none for a bare `.name`, so the
	# attribute fell through to the field builder and read slot offset 0. The
	# method spelling always worked, which is what located the missing arm.
	./$(COMPILER) test/test_nilpy_attr_off_subscript_of_call_result.npy /tmp/test_nilpy_attrsub26
	/tmp/test_nilpy_attrsub26 | diff -u test/test_nilpy_attr_off_subscript_of_call_result.expected -
	# issubclass() was absent entirely ("undefined variable"). With class NAMES
	# the answer is a compile-time fact, so it folds the parent-chain walk at
	# parse time; a class held in a VARIABLE is refused with a diagnostic saying
	# so rather than answering a plausible False (isinstance's runtime fallback
	# has no subclass twin, and adding one needs a re-pin).
	./$(COMPILER) test/test_nilpy_issubclass.npy /tmp/test_nilpy_issub26
	/tmp/test_nilpy_issub26 | diff -u test/test_nilpy_issubclass.expected -
	# `a |= <set>` silently did nothing (the desugar used the general or-token and
	# never reached the set path). In place, like +=/extend -- aliases must see it.
	./$(COMPILER) test/test_nilpy_set_augmented_union.npy /tmp/test_nilpy_setaug26
	/tmp/test_nilpy_setaug26 | diff -u test/test_nilpy_set_augmented_union.expected -
	# ...and the METHOD spellings of the same four operations (update,
	# intersection_update, difference_update, symmetric_difference_update),
	# which pylib declares as set* and nothing mapped onto. One table consulted
	# by every resolution path, so the receiver SHAPES are the rows; the
	# subscript one also fixed a segfault (only TPyDict declared `update`, so a
	# set was walked as a dict).
	# break / continue: implemented after the ticket was filed and never given a
	# test. Rows are what a loop-exit lowering can break independently: nesting,
	# an exit crossing a try (finally must still run), `while True`, for/else.
	# `rd().z` did not PARSE when rd() returns a module global pre-created by a
	# def above it, while binding the result first was fine. Rows vary what
	# follows the call -- field, method, subscript, chain -- since each is a
	# different selector arm and the failure was in the parse.
	./$(COMPILER) test/test_nilpy_selector_off_call_returning_a_global.npy /tmp/test_nilpy_selglob26
	/tmp/test_nilpy_selglob26 | diff -u test/test_nilpy_selector_off_call_returning_a_global.expected -
	# sorted(xs, key=None) RAISED, where CPython defines key=None as the default
	# (no key function) -- the shape an optional key threaded through a helper
	# hands over. The variant->Pointer coercion picks a None-tolerant form when
	# the CALLEE declares a default of nil; map(None, xs) must still refuse.
	# callable(x) was absent. The predicate was already in pylib (PyVarIsCallable),
	# just not in its interface; the __call__ row is the half that is not free --
	# such an instance is an ordinary VT_OBJECT, so the class RTTI has to answer.
	# math.log died as `undefined variable (log)` -- the RTL spells it Ln, a pure
	# NAME difference, while log10/log2 (same name in both) always worked. The
	# two-argument form stays refused on purpose: CPython's is an unsnapped
	# quotient and the RTL's LogN snaps, so mapping it would be wrong in the last
	# place. The last row is the exact quotient a user writes instead.
	# frozenset: the VALUE is a set's, so the rows that matter are the ones that
	# make the difference visible -- repr, type().__name__, isinstance both ways.
	# Equality is where the kinds must NOT be strict: frozenset({1,2}) == {1,2}.
	# self.__class__.__name__ raised AttributeError at RUN time while
	# type(self).__name__ -- the same question -- worked. Lowers to that same
	# call; the rows are receiver SHAPES, since a bare name and a call result
	# take different parsers and both had to learn it.
	# Optional[str] collapsed to plain str, so the CALL SITE converted a None
	# argument into a string -- it arrived tagged VT_STRING and `is None` was
	# correctly False about it. The "" rows are the ones a fix that boxed a nil
	# str handle as None would get wrong.
	# **kwargs re-expanded at a FORWARDED call site. The recorded lesson: with
	# keywords the argument COUNT no longer says WHICH parameters are filled
	# (dflt(1, c=9) fills a and c, skipping b), so the count-dispatch is dropped
	# and every parameter is passed, falling back to the callee's own default.
	# getattr/hasattr with a COMPUTED name -- a command dispatcher, the canonical
	# use. The runtime resolver already existed; what had to be built was a
	# hasattr predicate asking what the GETTER resolves, and normalising bound
	# methods in a module that dispatches by a runtime name (a method read by a
	# name no token spells is invisible to the scan that normally does it).
	# mk().items() did not parse while mk().keys()/.values() did: `items` is the
	# one of the three that collides with TPyDict's default Items[] PROPERTY, so
	# the remap of a Python spelling to pylib's name has to run BEFORE property
	# resolution, not beside the method lookup.
	# xs[0].n = 9 did not parse, while READING it, `xs[0].n += 1` and binding the
	# element first all worked: the lvalue branch was entered on `name .` alone.
	# The entry test is now "continues into .member after the bracket", which is
	# false for a bare xs[0] = v -- that keeps its own setitem lowering.
	# Construction-site argument shapes: C(**kw) on a **kwargs ctor, C(*xs), and
	# the sharp one -- a keyword whose name matches a FIELD the ctor's own body
	# declares (self.k = len(kw)), which was rejected as "got multiple values
	# for field 'k'". The def and method twins are the controls.
	./$(COMPILER) test/test_nilpy_ctor_star_and_kwargs.npy /tmp/test_nilpy_ctorargs26
	# ...and the full ctor shape (fixed + defaulted + *rest + **kw at once): b=5
	# must still bind to the PARAMETER while z=6 falls through to the dict.
	# `import <c-header>` from a .npy is a DESIGNED feature (the wrapper-free
	# NilPy-to-C arc). An earlier attempt to stop `import string` finding
	# string.h gated the route off entirely and turned four tests red; only its
	# POSITION moved. This goes red immediately if that happens again.
	./$(COMPILER) test/test_nilpy_import_c_header_still_works.npy /tmp/test_nilpy_imphdr26
	test "$$(/tmp/test_nilpy_imphdr26)" = "$$(printf 'malloc/free ok\nabs         3')"
	./$(COMPILER) test/test_nilpy_ctor_kwargs_fallthrough.npy /tmp/test_nilpy_ctorkwf26
	/tmp/test_nilpy_ctorkwf26 | diff -u test/test_nilpy_ctor_kwargs_fallthrough.expected -
	/tmp/test_nilpy_ctorargs26 | diff -u test/test_nilpy_ctor_star_and_kwargs.expected -
	./$(COMPILER) test/test_nilpy_store_attr_of_an_element.npy /tmp/test_nilpy_elemattr26
	/tmp/test_nilpy_elemattr26 | diff -u test/test_nilpy_store_attr_of_an_element.expected -
	./$(COMPILER) test/test_nilpy_selector_on_a_dict_returning_call.npy /tmp/test_nilpy_dictsel26
	/tmp/test_nilpy_dictsel26 | diff -u test/test_nilpy_selector_on_a_dict_returning_call.expected -
	./$(COMPILER) test/test_nilpy_getattr_computed_name.npy /tmp/test_nilpy_getattrc26
	/tmp/test_nilpy_getattrc26 | diff -u test/test_nilpy_getattr_computed_name.expected -
	./$(COMPILER) test/test_nilpy_kwargs_forwarded.npy /tmp/test_nilpy_kwfwd26
	/tmp/test_nilpy_kwfwd26 | diff -u test/test_nilpy_kwargs_forwarded.expected -
	./$(COMPILER) test/test_nilpy_optional_str_none.npy /tmp/test_nilpy_optstr26
	/tmp/test_nilpy_optstr26 | diff -u test/test_nilpy_optional_str_none.expected -
	./$(COMPILER) test/test_nilpy_class_name_chain.npy /tmp/test_nilpy_clsname26
	/tmp/test_nilpy_clsname26 | diff -u test/test_nilpy_class_name_chain.expected -
	./$(COMPILER) test/test_nilpy_frozenset.npy /tmp/test_nilpy_frozenset26
	/tmp/test_nilpy_frozenset26 | diff -u test/test_nilpy_frozenset.expected -
	./$(COMPILER) test/test_nilpy_math_log.npy /tmp/test_nilpy_mathlog26
	/tmp/test_nilpy_mathlog26 | diff -u test/test_nilpy_math_log.expected -
	./$(COMPILER) test/test_nilpy_callable_builtin.npy /tmp/test_nilpy_callable26
	/tmp/test_nilpy_callable26 | diff -u test/test_nilpy_callable_builtin.expected -
	./$(COMPILER) test/test_nilpy_sorted_key_none.npy /tmp/test_nilpy_keynone26
	/tmp/test_nilpy_keynone26 | diff -u test/test_nilpy_sorted_key_none.expected -
	./$(COMPILER) test/test_nilpy_break_continue.npy /tmp/test_nilpy_brkcont26
	/tmp/test_nilpy_brkcont26 | diff -u test/test_nilpy_break_continue.expected -
	# set EQUALITY is by MEMBERSHIP, not position ({1,2} == {2,1}), and a set is
	# never equal to a sequence. Both routes must agree: the operator and the
	# container walk used to carry two copies of the positional compare.
	# (1, 2) == [1, 2] answered True. The guard was held back when the set half
	# landed because it fires for every value whose FKind was never stamped -- so
	# the second half of this file sweeps every tuple/list constructor for
	# type(x).__name__, and all of them already agree with CPython.
	# e.args -- derived from the Message, since a pxx Exception carries one
	# string; KeyError stores the raw key instead, because its message is already
	# repr'd, and that is what also settled repr(KeyError(...)).
	# float formatting takes its digits from the double's EXACT decimal
	# expansion. Scaling by a power of ten manufactured ties -- 0.15 * 10 is
	# exactly 1.5 -- so "%.1f" % 0.15 printed 0.2 and 0.45 printed 0.4, wrong in
	# both directions.
	./$(COMPILER) test/test_nilpy_float_format_exact.npy /tmp/test_nilpy_ffexact26
	/tmp/test_nilpy_ffexact26 | diff -u test/test_nilpy_float_format_exact.expected -
	./$(COMPILER) test/test_nilpy_exception_args.npy /tmp/test_nilpy_excargs26
	/tmp/test_nilpy_excargs26 | diff -u test/test_nilpy_exception_args.expected -
	# `raise KeyError(42)` SEGFAULTED: every builtin exception ctor took an
	# AnsiString, so a non-string single argument was read as a string handle.
	./$(COMPILER) test/test_nilpy_exception_non_string_argument.npy /tmp/test_nilpy_excnonstr26
	/tmp/test_nilpy_excnonstr26 | diff -u test/test_nilpy_exception_non_string_argument.expected -
	# the builtin format(v[, spec]) — an intercept, because sysutils' Format
	# shadows the name once a program imports anything reaching it.
	./$(COMPILER) test/test_nilpy_format_builtin.npy /tmp/test_nilpy_fmtbuiltin26
	/tmp/test_nilpy_fmtbuiltin26 | diff -u test/test_nilpy_format_builtin.expected -
	# zip(a, b, c) — three and four streams; two-way must still yield a PAIR.
	./$(COMPILER) test/test_nilpy_zip_n_way.npy /tmp/test_nilpy_zipnway26
	/tmp/test_nilpy_zipnway26 | diff -u test/test_nilpy_zip_n_way.expected -
	./$(COMPILER) test/test_nilpy_tuple_is_not_a_list.npy /tmp/test_nilpy_tupnotlist26
	/tmp/test_nilpy_tupnotlist26 | diff -u test/test_nilpy_tuple_is_not_a_list.expected -
	./$(COMPILER) test/test_nilpy_set_equality_is_membership.npy /tmp/test_nilpy_seteq26
	/tmp/test_nilpy_seteq26 | diff -u test/test_nilpy_set_equality_is_membership.expected -
	./$(COMPILER) test/test_nilpy_set_update_methods.npy /tmp/test_nilpy_setupd26
	/tmp/test_nilpy_setupd26 | diff -u test/test_nilpy_set_update_methods.expected -
	# `xs[0].update(d)` on a dict element SEGFAULTED: a variant receiver picked an
	# overload by ARITY alone, and the scorer that should have decided compared
	# type KINDS -- two class parameters both being tyClass, every candidate tied
	# and the first declaration (update(TPyList)) always won, so a TPyDict was
	# walked as a TPyList. The scorer now ranks exact CLASS identity above a
	# kind-only match. Rows vary the receiver AND the argument kind: mapping,
	# iterable of pairs and variant must each reach a different overload.
	./$(COMPILER) test/test_nilpy_overload_by_class_through_a_variant.npy /tmp/test_nilpy_ovlcls26
	/tmp/test_nilpy_ovlcls26 | diff -u test/test_nilpy_overload_by_class_through_a_variant.expected -
	# a module name rebound INSIDE a block from a subscript / .values() loop /
	# list() wrapper kept the module binding's type -- len() read a pointer.
	./$(COMPILER) test/test_nilpy_module_name_rebound_in_a_block.npy /tmp/test_nilpy_modrebind26
	/tmp/test_nilpy_modrebind26 | diff -u test/test_nilpy_module_name_rebound_in_a_block.expected -
	# min()/max() of a VARIANT holding a list read it as a STRING and raised
	# "empty sequence" -- the only single-arg overload took an AnsiString.
	./$(COMPILER) test/test_nilpy_min_max_of_a_variant_list.npy /tmp/test_nilpy_minmaxvar26
	/tmp/test_nilpy_minmaxvar26 | diff -u test/test_nilpy_min_max_of_a_variant_list.expected -
	# `%-*s` -- dynamic width/precision from an argument -- raised
	# "unsupported format character *". The starred arg is consumed before the value.
	./$(COMPILER) test/test_nilpy_percent_star_width.npy /tmp/test_nilpy_pctstar26
	/tmp/test_nilpy_pctstar26 | diff -u test/test_nilpy_percent_star_width.expected -
	# STARRED unpack targets: `a, *rest = xs`, `*init, last = xs`, `p, *mid, q`.
	# The starred name is always a LIST (even from a tuple) and too few values
	# is a ValueError, not an IndexError.
	./$(COMPILER) test/test_nilpy_starred_unpack.npy /tmp/test_nilpy_starunpack26
	/tmp/test_nilpy_starunpack26 | diff -u test/test_nilpy_starred_unpack.expected -
	./$(COMPILER) test/test_nilpy_any_params.npy /tmp/test_nilpy_any_params26
	test "$$(/tmp/test_nilpy_any_params26)" = "$$(printf 'got\ngot\n20\n3')"
	./$(COMPILER) test/test_nilpy_method_return_types.npy /tmp/test_nilpy_method_return_types26
	test "$$(/tmp/test_nilpy_method_return_types26)" = "$$(printf '7\nTrue\nFalse\n2.5\n14\ntext\nTEXT')"
	./$(COMPILER) test/test_nilpy_class_field_identity.npy /tmp/test_nilpy_class_field_identity26
	test "$$(/tmp/test_nilpy_class_field_identity26)" = "$$(printf 'dup\nswap\nDUP\nSWAP\ndup\ndup\nDUP')"
	./$(COMPILER) test/test_nilpy_str_methods.npy /tmp/test_nilpy_str_methods26
	test "$$(/tmp/test_nilpy_str_methods26)" = "$$(printf 'HELLO, WORLD! 123\nhello, world! 123\nMIXED\nmixed\n42\nWORD7\nhello, world! 123\nHELLO, WORLD! 123\nFORTH\n\nALREADY UPPER\nalready lower\nDIGITS 0123 AND !@# STAY\nEMOJI STAYS >>> OK\nHello, World! 123\naB\nxyz\nB\nTrue\n[padded]\n[padded  ]\n[  padded]\n[]\n[]\n[tabbed]\nTrue\nFalse\nTrue\nFalse\nTrue\nTrue\nFalse\n2\n0\n-1\n0\n1\n2\nTrue\nFalse\nFalse\nTrue\nMIXED\nmixed\nTrue\nH\ne\n3\nH\n3\n5\n0\n2\na,b,c\nabc\nsolo\n[]\na|b|c\na||b\n1\nFORTH|is|fun\n0\n0\none|two|three\n1\n0\n2\n3\nDUP|SWAP|DROP\n2\n12\n[  7]\n007\nabc\n[****]\nx y\n...42 5\na')"
	./$(COMPILER) test/test_nilpy_isinstance.npy /tmp/test_nilpy_isinstance26
	test "$$(/tmp/test_nilpy_isinstance26)" = "$$(printf 'num\nnum\ntext\nword\ncall\nnum')"
	./$(COMPILER) test/test_nilpy_optional.npy /tmp/test_nilpy_optional26
	test "$$(/tmp/test_nilpy_optional26)" = "$$(printf 'dup\n0\nFalse\n65536')"
	./$(COMPILER) test/test_nilpy_variant_str_ownership.npy /tmp/test_nilpy_variant_str_ownership26
	test "$$(/tmp/test_nilpy_variant_str_ownership26)" = "$$(printf '1\n2\none\ntwo\n2\n1\n2\n3 4\n9 2 3\naaa 9\nbbb 2\nccc 3\naaa 9')"
	./$(COMPILER) test/test_nilpy_floordiv_modulo.npy /tmp/test_nilpy_floordiv_modulo26
	test "$$(/tmp/test_nilpy_floordiv_modulo26)" = "$$(printf '7 3 2 1 0\n7 -3 -3 -2 0\n-7 3 -3 2 0\n-7 -3 2 -1 0\n8 4 2 0 0\n8 -4 -2 0 0\n-8 4 -2 0 0\n-8 -4 2 0 0\n0 5 0 0 0\n0 -5 0 0 0\n1 7 0 1 0\n-1 7 -1 6 0\n1 -7 -1 -6 0\n-1 -7 0 -1 0\n3.0 1.5\n-4.0 0.5\n-4.0 -0.5')"
	./$(COMPILER) test/test_nilpy_int_str_builtins.npy /tmp/test_nilpy_int_str_builtins26
	test "$$(/tmp/test_nilpy_int_str_builtins26)" = "$$(printf '42 -7 9 3 2 -2 1\nab  True False 5 -5 2.5 0.0\n34\n101 14 2\n2 2.75\n0 0\n9 4 1 0\n-9 -5 1 0\n10 5 0 0\n-10 -5 0 0')"
	./$(COMPILER) test/test_nilpy_pyexpr_semantics.npy /tmp/test_nilpy_pyexpr_semantics26
	test "$$(/tmp/test_nilpy_pyexpr_semantics26)" = "$$(printf 'False\nTrue\nTrue\nTrue\nTrue\nababab ababab x \n4 3 4\n4 True\nTrue\nTrue False True')"
	./$(COMPILER) test/test_nilpy_variant_operator_sweep.npy /tmp/test_nilpy_variant_operator_sweep26
	test "$$(/tmp/test_nilpy_variant_operator_sweep26)" = "$$(printf '7 -7 8 6 14\n-7 7 -6 -8 -14\n0 0 1 -1 0\n3 1 3.5\n-4 1 -3.5\n0 0 0.0\n2.5 -2.5 3.5 5.0\n-2.5 2.5 -1.5 -5.0\nab ab!\n !\nTrue False True\nFalse True False\n2 3\nTrue False\nTrue False\n1 1.5 z True\n5 5 5 -5\nTrue False True\n1 2 1.5 2.5\n97 b\nTrue False True False True False\nFalse True')"
	./$(COMPILER) test/test_nilpy_method_str_return.npy /tmp/test_nilpy_method_str_return26
	test "$$(/tmp/test_nilpy_method_str_return26)" = "$$(printf 'alpha 1 True 2.5\nalpha! alpha literal\nbeta -2 False fallback\nalpha alpha! 5 6\nalphaalpha!\nnc')"
	./$(COMPILER) test/test_nilpy_variant_polymorphic_builtins.npy /tmp/test_nilpy_variant_polymorphic_builtins26
	test "$$(/tmp/test_nilpy_variant_polymorphic_builtins26)" = "$$(printf '2 abab abab\n0  \n3 xyzxyz xyzxyz\n1 qq qq\n9 9\n-6 -6\n0 0\n3.0 3.0\n-1.0 -1.0\n97 1 aaa\n122 1 zzz\n3\n2')"
	./$(COMPILER) test/test_nilpy_list_repeat.npy /tmp/test_nilpy_list_repeat26
	test "$$(/tmp/test_nilpy_list_repeat26)" = "$$(printf '[0, 0, 0, 0] 4\n['"'"'a'"'"', '"'"'a'"'"', '"'"'a'"'"'] 3\n[1, 2, 1, 2]\n[] []\n[[0], [0]]\n[[0, 9], [0, 9]]\n[0, 1, 2]')"
	./$(COMPILER) test/test_nilpy_function_values.npy /tmp/test_nilpy_function_values26
	test "$$(/tmp/test_nilpy_function_values26)" = "$$(printf '1\n11\nONE\n12\nONE 13\nTEN 23\n34')"
	./$(COMPILER) test/test_nilpy_variant_builtin_sweep.npy /tmp/test_nilpy_variant_builtin_sweep26
	test "$$(/tmp/test_nilpy_variant_builtin_sweep26)" = "$$(printf '3 1 5 7\n7 14 -7 True\n7 1 A\n-2 1 -3 5\n3 6 3 True\n-3 2 A\n0 0 0 5\n0 0 0 False\n0 1 A\n1.5 -1.5 3.0\n2.5 2.5 5.0\n2 ['"'"'a'"'"', '"'"'b'"'"'] True AB\n1 ['"'"'c'"'"'] True C\n0 [] False ')"
	./$(COMPILER) test/test_nilpy_none.npy /tmp/test_nilpy_none26
	test "$$(/tmp/test_nilpy_none26)" = "$$(printf '1 text None\nTrue False\nFalse True\nNone None 1\n1 False\nNone True\nx False\n[1, None, '"'"'x'"'"']\nmissing\nfalsy ok\nFalse True')"
	./$(COMPILER) test/test_nilpy_variant_arith_nested.npy /tmp/test_nilpy_variant_arith_nested26
	test "$$(/tmp/test_nilpy_variant_arith_nested26)" = "$$(printf '66\n509\n72\n8.0\na-b-')"
	./$(COMPILER) test/test_nilpy_builtins_list_enum.npy /tmp/test_nilpy_builtins_list_enum26
	test "$$(/tmp/test_nilpy_builtins_list_enum26)" = "$$(printf '[3, 1, 2] [3, 1, 2, 9]\n['"'"'a'"'"', '"'"'b'"'"', '"'"'c'"'"']\n[2, 1, 3]\n['"'"'y'"'"', '"'"'x'"'"']\n0xff 0x0 -0x10 0xfff\n2\n1\n3\n0 a\n1 b\n2 c\n0 h\n1 i\n0 x 1\n1 y 1')"
	./$(COMPILER) test/test_nilpy_unpack.npy /tmp/test_nilpy_unpack26
	test "$$(/tmp/test_nilpy_unpack26)" = "$$(printf '1 2\n2 1\np 2 3.5\n7 8\na 1\nb 2\nc 3\n6\na 1\nb 2\nc 3')"
	./$(COMPILER) test/test_nilpy_comparison_chaining.npy /tmp/test_nilpy_comparison_chaining26
	test "$$(/tmp/test_nilpy_comparison_chaining26)" = "$$(printf 'True\nFalse\nTrue\nTrue\nTrue\nFalse\nTrue\ncall\nTrue')"
	./$(COMPILER) test/test_pascal_forward_class_ok.pas /tmp/test_pascal_forward_class_ok26
	test "$$(/tmp/test_pascal_forward_class_ok26)" = "7"
	@# a SECOND class of the same name in one unit must be refused, naming it
	@./$(COMPILER) test/test_pascal_duplicate_class_fail.pas /tmp/test_pascal_dup_class26 2>&1 \
	  | grep -q 'duplicate class name TFoo' \
	  || { echo 'test_pascal_duplicate_class_fail: FAIL - expected a duplicate-class-name error'; exit 1; }
	@# a PARAMETERLESS function's bare own name read as a value means different
	@# things in objfpc (its Result) and delphi (a recursive call), so it warns by
	@# default. Exactly one site here is ambiguous; the explicit Result / F() /
	@# with-param forms must stay quiet, or the warning becomes noise and gets
	@# tuned out. bug-paramless-self-recursion-silent-result-read
	@n=$$(./$(COMPILER) test/test_pascal_self_result_warn.pas /tmp/test_pascal_self_result_warn26 2>&1 \
	   | grep -c 'bare own name'); \
	 test "$$n" = "1" \
	  || { echo "test_pascal_self_result_warn: FAIL - expected exactly 1 bare-own-name warning, got $$n"; exit 1; }
	test "$$(/tmp/test_pascal_self_result_warn26)" = "$$(printf '5\n1\n8\n42\n6\n42\n100')"
	@# ... and --no-warn-self-result silences it
	@n=$$(./$(COMPILER) --no-warn-self-result test/test_pascal_self_result_warn.pas /tmp/test_pascal_self_result_warn26 2>&1 \
	   | grep -c 'bare own name'); \
	 test "$$n" = "0" \
	  || { echo "test_pascal_self_result_warn: FAIL - --no-warn-self-result did not silence the warning"; exit 1; }
	@# the {$$MODE DELPHI} half: there the SAME spelling is a recursive call, not a
	@# Result read, and the warning must stay silent because its text would be
	@# false. Both halves match FPC 3.2.2 under -Mobjfpc / -Mdelphi respectively.
	./$(COMPILER) test/test_pascal_self_result_delphi.pas /tmp/test_pascal_self_result_delphi26
	test "$$(/tmp/test_pascal_self_result_delphi26)" = "$$(printf '42\n4\n7\n3\n10')"
	@n=$$(./$(COMPILER) test/test_pascal_self_result_delphi.pas /tmp/test_pascal_self_result_delphi26 2>&1 \
	   | grep -c 'bare own name'); \
	 test "$$n" = "0" \
	  || { echo "test_pascal_self_result_delphi: FAIL - warning must not fire in delphi mode (it recurses there; the message would be false)"; exit 1; }
	@# FPC's -M<mode> command-line switch. The source carries NO mode directive —
	@# which is how real Delphi projects ship — so the two runs must DIFFER, and
	@# the test cannot pass by accident if the flag is ignored. Both expectations
	@# match FPC 3.2.2 under the same flag. compat-pascal-no-command-line-mode-switch
	./$(COMPILER) test/test_pascal_mode_switch_cli.pas /tmp/test_pascal_mode_cli26
	test "$$(/tmp/test_pascal_mode_cli26)" = "$$(printf '7\n1')"
	./$(COMPILER) -Mdelphi test/test_pascal_mode_switch_cli.pas /tmp/test_pascal_mode_cli_d26
	test "$$(/tmp/test_pascal_mode_cli_d26)" = "$$(printf '42\n4')"
	@# -Mobjfpc is the default dialect; other mode names are accepted but inert, so
	@# a build script's -Mtp does not die on an unknown option
	./$(COMPILER) -Mobjfpc test/test_pascal_mode_switch_cli.pas /tmp/test_pascal_mode_cli_o26
	test "$$(/tmp/test_pascal_mode_cli_o26)" = "$$(printf '7\n1')"
	./$(COMPILER) -Mtp test/test_pascal_mode_switch_cli.pas /tmp/test_pascal_mode_cli_tp26
	test "$$(/tmp/test_pascal_mode_cli_tp26)" = "$$(printf '7\n1')"
	@# a source-level mode directive OVERRIDES the command line, as in FPC
	./$(COMPILER) -Mobjfpc test/test_pascal_self_result_delphi.pas /tmp/test_pascal_mode_override26
	test "$$(/tmp/test_pascal_mode_override26)" = "$$(printf '42\n4\n7\n3\n10')"
	./$(COMPILER) test/test_nilpy_method_on_fresh_construction.npy /tmp/test_nilpy_method_fresh_ctor26
	test "$$(/tmp/test_nilpy_method_fresh_ctor26)" = "$$(printf '5\n7\na9\n6\n3 a3\n[1, 2]')"
	./$(COMPILER) test/test_nilpy_discarded_string_result.npy /tmp/test_nilpy_discarded_string_result26
	test "$$(/tmp/test_nilpy_discarded_string_result26)" = "$$(printf '5 [0, 1, 2, 3, 4]\n5\ns99 m99 6 6\n8 101 102')"
	./$(COMPILER) test/test_nilpy_lambda_returned_from_def.npy /tmp/test_nilpy_lambda_returned26
	test "$$(/tmp/test_nilpy_lambda_returned26)" = "$$(printf '2 11 6 2\n2 101\n6 1005\n8 2\n2 21')"
	./$(COMPILER) test/test_nilpy_annotated_module_global.npy /tmp/test_nilpy_annotated_module_global26
	test "$$(/tmp/test_nilpy_annotated_module_global26)" = "$$(printf '2\n5 8 AB 2 1\n1 1 7 ab 3')"
	@# str()/print()/f-string of a class instance with no dunders rendered the
	@# HANDLE as an integer, and a CLASS-TYPED None printed as 0 — while repr()
	@# and a container element were right, so the rendering paths disagreed
	./$(COMPILER) test/test_nilpy_str_of_an_instance_and_a_class_typed_none.npy /tmp/test_nilpy_strinst26
	/tmp/test_nilpy_strinst26 | diff -u test/test_nilpy_str_of_an_instance_and_a_class_typed_none.expected -
	@# type(2 ** 70).__name__ answered <unknown>: an arbitrary-precision int
	@# wears a tag at or above VT_PROMO_BASE and the name mapping stopped below it
	./$(COMPILER) test/test_nilpy_type_name_of_a_big_int.npy /tmp/test_nilpy_typebig26
	/tmp/test_nilpy_typebig26 | diff -u test/test_nilpy_type_name_of_a_big_int.expected -
	@# a def whose return is `2 ** 70` or a wide literal answered 0 — `**`
	@# lowers to a variant-returning call while the scan read the literals
	./$(COMPILER) test/test_nilpy_def_returning_a_big_int.npy /tmp/test_nilpy_defretbig26
	/tmp/test_nilpy_defretbig26 | diff -u test/test_nilpy_def_returning_a_big_int.expected -
	@# a def whose whole return is a FIELD READ was typed as the RECEIVER's
	@# class; it printed right by coincidence and type() on it segfaulted
	./$(COMPILER) test/test_nilpy_def_returning_a_field.npy /tmp/test_nilpy_defretfield26
	/tmp/test_nilpy_defretfield26 | diff -u test/test_nilpy_def_returning_a_field.expected -
	@# `del d[k]` where d is an unannotated (variant) dict/list parameter — the
	@# del lowering dispatched on the receiver's STATIC type and refused it
	./$(COMPILER) test/test_nilpy_del_on_a_variant_receiver.npy /tmp/test_nilpy_delvar26
	/tmp/test_nilpy_delvar26 | diff -u test/test_nilpy_del_on_a_variant_receiver.expected -
	@# __repr__/__str__ return a str BY CONTRACT: an unannotated `return self.n`
	@# over an unannotated field inferred a variant, the runtime renderer
	@# declined it, and repr(obj) came back EMPTY while print(obj) was right
	./$(COMPILER) test/test_nilpy_repr_dunder_returns_str.npy /tmp/test_nilpy_reprdunder26
	/tmp/test_nilpy_reprdunder26 | diff -u test/test_nilpy_repr_dunder_returns_str.expected -
	@# abs(-0.0), min/max tie-breaking (CPython returns the FIRST) and sum()'s
	@# compensated summation — sum([1e16, 1.0, -1e16]) dropped the 1.0 entirely
	./$(COMPILER) test/test_nilpy_abs_minmax_sum_oracle.npy /tmp/test_nilpy_amsum26
	/tmp/test_nilpy_amsum26 | diff -u test/test_nilpy_abs_minmax_sum_oracle.expected -
	@# float formatting rounds ties to EVEN: "%.0f" % 7.5 is 8, not 7 — it used
	@# to round the FRACTION alone, which loses the parity half-even needs
	./$(COMPILER) test/test_nilpy_format_half_even.npy /tmp/test_nilpy_halfeven26
	/tmp/test_nilpy_halfeven26 | diff -u test/test_nilpy_format_half_even.expected -
	@# round(x, n) keeps x's TYPE: round(6, 2) is 6, not 6.0 — the two-argument
	@# form used to disagree with the one-argument one in the same program
	./$(COMPILER) test/test_nilpy_round_ndigits_keeps_int.npy /tmp/test_nilpy_roundint26
	/tmp/test_nilpy_roundint26 | diff -u test/test_nilpy_round_ndigits_keeps_int.expected -
	@# an override whose return type differs from its base's: the base's slot
	@# used to take the value with no conversion, so a float override of an int
	@# base printed 1.5's IEEE BITS and an int override of a float base either
	@# rendered 6 as 6.0 or failed to emit at all
	./$(COMPILER) test/test_nilpy_override_return_type_differs.npy /tmp/test_nilpy_ovrret26
	/tmp/test_nilpy_ovrret26 | diff -u test/test_nilpy_override_return_type_differs.expected -
	@# a module-level name rebound from a FIELD READ inside a block — the
	@# textbook linked-list walk, which segfaulted on its second iteration
	./$(COMPILER) test/test_nilpy_module_name_from_a_field_in_a_block.npy /tmp/test_nilpy_modfield26
	/tmp/test_nilpy_modfield26 | diff -u test/test_nilpy_module_name_from_a_field_in_a_block.expected -
	@# a field assigned from a module-level CONSTANT — `self.state = NEW`. Every
	@# global type was rejected with "cannot infer the type of field"; CPython is
	@# the oracle for the expectation
	./$(COMPILER) test/test_nilpy_field_from_module_global.npy /tmp/test_nilpy_field_from_global26
	/tmp/test_nilpy_field_from_global26 | diff -u test/test_nilpy_field_from_module_global.expected -
	./$(COMPILER) test/test_nilpy_method_string_result_ownership.npy /tmp/test_nilpy_method_string_result26
	test "$$(/tmp/test_nilpy_method_string_result26)" = "$$(printf 'lit 7 kk-7 kk 9\n3 1 4 2 1\nzz 99 zz\n300 zz-99')"
	./$(COMPILER) test/test_nilpy_sorted_sequences.npy /tmp/test_nilpy_sorted_sequences26
	test "$$(/tmp/test_nilpy_sorted_sequences26)" = "$$(printf '[('"'"'a'"'"', 1), ('"'"'b'"'"', 2)]\n[[1, '"'"'a'"'"'], [2, '"'"'b'"'"']]\n[('"'"'a'"'"', 1), ('"'"'a'"'"', 2)]\n[(1,), (1, 2), (1, 2, 3)]\n[1, 2, 3]\n['"'"'a'"'"', '"'"'b'"'"']\n[[1, [2, 1]], [1, [2, 3]]]\n('"'"'b'"'"', 0) ('"'"'a'"'"', 1)\n[('"'"'b'"'"', 2), ('"'"'a'"'"', 1)]')"
	./$(COMPILER) test/test_nilpy_is_identity.npy /tmp/test_nilpy_is_identity26
	test "$$(/tmp/test_nilpy_is_identity26)" = "$$(printf 'False True True False\nTrue False\nFalse True True\nTrue\nFalse True\nTrue\nTrue False False True\nFalse True\ncopied same')"
	./$(COMPILER) test/test_nilpy_callable_param_heap_callable.npy /tmp/test_nilpy_callable_param26
	test "$$(/tmp/test_nilpy_callable_param26)" = "$$(printf '6\n7\n1005\n42\n-1\n42\n105\n105 8\n105\n11 21\ninc 2')"
	./$(COMPILER) test/test_nilpy_return_ownership.npy /tmp/test_nilpy_return_ownership26
	test "$$(/tmp/test_nilpy_return_ownership26)" = "$$(printf 'ctor 1\nlocal 2\nctor 3\nfield 7\nelem 8\nfield elem\n500 499')"
	./$(COMPILER) test/test_nilpy_set_literal_dedup.npy /tmp/test_nilpy_set_literal_dedup26
	test "$$(/tmp/test_nilpy_set_literal_dedup26)" = "$$(printf '3\n3\n3\n2\n4\nTrue False True\n4\n4\n1 2\n[1, 2, 3]')"
	@# a callable where a str parameter is declared must be REFUSED, naming the parameter
	@./$(COMPILER) test/test_nilpy_callable_to_str_param_fails.npy /tmp/test_nilpy_callable_to_str_param26 2>&1 \
	  | grep -q 'expects text for parameter "s"' \
	  || { echo 'test_nilpy_callable_to_str_param_fails: FAIL - expected a compile error naming the parameter'; exit 1; }
	./$(COMPILER) test/test_nilpy_float_repeat_typeerror.npy /tmp/test_nilpy_float_repeat_typeerror26
	test "$$(timeout 20 /tmp/test_nilpy_float_repeat_typeerror26 2>&1 || true)" = "$$(printf 'ababab ababab ababab\nUnhandled exception: TypeError: expected an integer to repeat a str by, got float')"
	@# ...and the same diagnostics are CATCHABLE — PyTypeError raises, it no
	@# longer Halt(219)s (bug-nilpy-pytypeerror-halts-instead-of-raising)
	./$(COMPILER) test/test_nilpy_typeerror_is_catchable.npy /tmp/test_nilpy_typeerror_catch26
	test "$$(/tmp/test_nilpy_typeerror_catch26)" = "$$(printf 'caught repeat\ncaught len\ncaught int\ncaught fmt\ncaught sep\ncaught max\ncaught call-None\ncaught ord\ncaught strindex\ncaught set\ncaught join\ncaught bytearray\ncaught fnf\nas Exception\nafter')"
	@# mismatched operand types raise instead of doing pointer math; every line
	@# of the expectation is CPython's own output for the same file
	./$(COMPILER) test/test_nilpy_mixed_type_operands.npy /tmp/test_nilpy_mixed_type_operands26
	test "$$(/tmp/test_nilpy_mixed_type_operands26)" = "$$(printf 'sub TypeError\ndiv TypeError\nlt TypeError\nle TypeError\ngt TypeError\nge TypeError\nmul-dict TypeError\nsub-list TypeError\nababab ababab\n2 1.5 1 1\nTrue True False True\n[1, 2, 1, 2]\n[1, 2, 1, 2]\nTrue True False True True\n5 apples\na-b\n[1, 2, 1, 3]\n[1]\nleftover TypeError\nno specifier\nfloat sub TypeError\nfloat lt TypeError\n5.0 1.5 True')"
	@# a BARE `return` must not end the return-type inference scan -- it is
	@# `return None` in Python, and ending there let tyInteger win over the
	@# real returns that followed
	./$(COMPILER) test/test_nilpy_return_type_inference.npy /tmp/test_nilpy_ret_infer26
	test "$$(/tmp/test_nilpy_ret_infer26)" = "$$(printf 'str\n[1, 2]\n2.5\n5\ndeep\nstr\nouter')"
	@# `return <subscript>`/`return <slice>` on a variant/string receiver, and a
	@# self-referential chr() accumulator's return type
	./$(COMPILER) test/test_nilpy_bare_return_subscript_slice.npy /tmp/test_nilpy_bare_ret_subslice26
	test "$$(/tmp/test_nilpy_bare_ret_subslice26)" = "$$(printf 'a\na\nab\nprefix_\na\n1.5\nTrue\n[1]\na\n1\nv\n[1, 2]\nhello world')"
	@# a `for` target reused after a non-string binding (and the reverse order)
	./$(COMPILER) test/test_nilpy_for_variable_reuse.npy /tmp/test_nilpy_for_var_reuse26
	test "$$(/tmp/test_nilpy_for_var_reuse26)" = "$$(printf 'a\nZ\na\nZ\na\nZ\na\nZ\na\nb\n5\n1.5\nTrue\n1\n2')"
	@# a method call / subscript on a PARENTHESISED expression
	./$(COMPILER) test/test_nilpy_postfix_after_parens.npy /tmp/test_nilpy_parenpost26
	/tmp/test_nilpy_parenpost26 | diff -u test/test_nilpy_postfix_after_parens.expected -
	@# zip() inside a COMPREHENSION parses (the zip intercept is statement-only)
	./$(COMPILER) test/test_nilpy_zip_in_a_comprehension.npy /tmp/test_nilpy_zipcomp26
	/tmp/test_nilpy_zipcomp26 | diff -u test/test_nilpy_zip_in_a_comprehension.expected -
	@# a for target inside a def is a LOCAL, not the module global of that name
	./$(COMPILER) test/test_nilpy_loop_target_in_a_def_is_local.npy /tmp/test_nilpy_loctgt26
	/tmp/test_nilpy_loctgt26 | diff -u test/test_nilpy_loop_target_in_a_def_is_local.expected -
	@# an `except ... as e` binder is scoped to its handler, so a later
	@# ordinary `e = ...` does not land in the exception-typed slot
	./$(COMPILER) test/test_nilpy_except_as_binder_scope.npy /tmp/test_nilpy_exc_as26
	/tmp/test_nilpy_exc_as26 | diff -u test/test_nilpy_except_as_binder_scope.expected -
	@# a def returning None on one arm and a CONTAINER on another answers a
	@# VARIANT -- a nil object pointer rendered as [] and crashed every consumer
	./$(COMPILER) test/test_nilpy_none_beside_a_container_return.npy /tmp/test_nilpy_none_container26
	/tmp/test_nilpy_none_container26 | diff -u test/test_nilpy_none_beside_a_container_return.expected -
	@# an EXPLICIT None separator means whitespace runs, like split() itself
	./$(COMPILER) test/test_nilpy_split_none_separator.npy /tmp/test_nilpy_split_none26
	@# .expected, not an inline printf: the expectation is full of Python reprs
	@# of string lists, and a single quote ends a single-quoted printf
	/tmp/test_nilpy_split_none26 | diff -u test/test_nilpy_split_none_separator.expected -
	@# a MULTI-name `for` target whose names are already bound at module scope
	./$(COMPILER) test/test_nilpy_for_multiname_target_reuses_name.npy /tmp/test_nilpy_for_multiname26
	test "$$(/tmp/test_nilpy_for_multiname26)" = "$$(printf 'x,y\nx,y\nx,y\nx,y\n[%s]\nx,y\npqr\n3 10\none 2\nann ann,zz\nbo bo,zz\nfn x,y' "'x', 'y'")"
	@# a missing attribute raises AttributeError instead of answering None
	./$(COMPILER) test/test_nilpy_missing_attribute_raises.npy /tmp/test_nilpy_missattr26
	test "$$(/tmp/test_nilpy_missattr26)" = "$$(printf 'caught foo\ncaught upper\ncaught nope\ncaught getx\nTrue\nFalse\n1\ndef\n42\nAB')"
	@# redefining a top-level def replaces the earlier body (same arity wins;
	@# different arity, methods, and rebind-to-value already worked)
	./$(COMPILER) test/test_nilpy_redefine_def.npy /tmp/test_nilpy_redefdef26
	test "$$(/tmp/test_nilpy_redefdef26)" = "$$(printf '2\n3\n2\n5')"
	@# %e/%E/%g/%G no longer collapse onto %f
	./$(COMPILER) test/test_nilpy_percent_e_g_format.npy /tmp/test_nilpy_pctformat26
	test "$$(/tmp/test_nilpy_pctformat26)" = "$$(printf '1.500000e+03\n1.500000E+03\n1.23e+03\n1.5e+06\n0.0001\n100\n0\n0.000000e+00\n-1.500000e+03\n1.23457e+08\n3.141592654\n1\n1.500000\n1.50')"
	@# `xs += ys` on a VARIANT-typed list extends in place instead of rebinding
	./$(COMPILER) test/test_nilpy_augmented_add_variant_list.npy /tmp/test_nilpy_augaddvar26
	test "$$(/tmp/test_nilpy_augaddvar26)" = "$$(printf '[1, 9]\n[1, 5]\n[1, 9]\n[1, 9]\n[1, 9]\n[1, 8]')"
	./$(COMPILER) test/test_nilpy_exception_no_leak.npy /tmp/test_nilpy_excnoleak26
	test "$$(/tmp/test_nilpy_excnoleak26)" = "640000"
	@if [ -x /usr/bin/time ]; then \
	  /usr/bin/time -v /tmp/test_nilpy_excnoleak26 2>/tmp/excnoleak.time >/dev/null; \
	  rss=$$(grep -oE 'Maximum resident set size .kbytes.: [0-9]+' /tmp/excnoleak.time | grep -oE '[0-9]+$$'); \
	  if [ -n "$$rss" ] && [ "$$rss" -gt 90000 ]; then echo "caught-exception-object leak regressed: RSS $${rss}KB (>90MB over 640k raises; pre-fix was ~105MB, fixed is ~75MB)"; exit 1; else echo "exception-no-leak: OK (RSS $${rss}KB)"; fi; \
	else echo "/usr/bin/time absent; exception-object RSS leak guard skipped"; fi
	@# `target[key] op= value` on a dict/list/Counter subscript (found already fixed)
	./$(COMPILER) test/test_nilpy_augmented_subscript_assign.npy /tmp/test_nilpy_augsubassign26
	test "$$(/tmp/test_nilpy_augsubassign26)" = "$$(printf '{'"'"'a'"'"': 2}\n[6, 2]\n2\n14\n[1, 1, 30]')"
	@# print() evaluates every argument before writing any of them
	./$(COMPILER) test/test_nilpy_print_arg_eval_order.npy /tmp/test_nilpy_printorder26
	test "$$(/tmp/test_nilpy_printorder26)" = "$$(printf '%b' 'label = ERR\n1 2 3\na b c\n[1, 2] {'"'"'k'"'"': 1}\nx 5 3.14 True None\nbefore side\n1 2 3\nlead 1 2 3')"
	@# mixed str/number `and`/`or` returns the operand, not a Boolean
	./$(COMPILER) test/test_nilpy_mixed_type_bool_op.npy /tmp/test_nilpy_boolop26
	test "$$(/tmp/test_nilpy_boolop26)" = "$$(printf '%b' '5\nx\nx\na\nx\n1\n5\nx\n0\ntruthy\ndefault\ndefault\ndefault\nval\n5\n['"'"'12'"'"', '"'"'+'"'"', '"'"'34'"'"', '"'"'*'"'"', '"'"'2'"'"']')"
	@# math.floor/math.ceil must return an int, not the RTL Math unit's own
	@# Double->Double Floor/Ceil that `import math` would otherwise reach
	./$(COMPILER) test/test_nilpy_math_floor_ceil_int.npy /tmp/test_nilpy_mathfloor26
	test "$$(/tmp/test_nilpy_mathfloor26)" = "$$(printf '%b' '2 3\n-3 -2\n2 2\n3\n3 2 2.7\n-2 2 -2 0\n2 -2 0\n-6\n-3.0 3.0\n-3.0 3.0\n-3.0 3.0')"
	@# f-string format specs: precision, exponential, width/alignment incl. ^
	@# (center) and an explicit fill char
	@# the same specs on values whose STATIC type is a variant (list/dict element,
	@# unannotated param or attribute) — these bound the Int64 overload and
	@# truncated a float / raised on a str
	./$(COMPILER) test/test_nilpy_fstring_spec_on_variant.npy /tmp/test_nilpy_fmtspecvar26
	/tmp/test_nilpy_fmtspecvar26 | diff -u test/test_nilpy_fstring_spec_on_variant.expected -
	./$(COMPILER) test/test_nilpy_fstring_format_spec.npy /tmp/test_nilpy_fmtspec26
	test "$$(/tmp/test_nilpy_fmtspec26)" = "$$(printf '%b' '3.14\n    F\n   42\n3\n1.23e+03\n    hi    \n    hi     \n********hi\nhi********\n****hi****\n  7  \n00007\n-0003\n000-3\n3.142\n***3.1****\nx    |\n    3|')"
	@# a managed STRING local minted after the prologue zero-init pass was never
	@# nil'd, so the loop's first store released stale frame bytes -> SIGSEGV
	./$(COMPILER) test/test_nilpy_str_local_loop_zeroinit.npy /tmp/test_nilpy_str_local_zi26
	test "$$(/tmp/test_nilpy_str_local_zi26)" = "$$(printf 'a\nb\nx\nx\ny\nz\ny\nz\n65\n66\ng\nh\n1\n2\ni\nj\nk\nl')"
	@# chr() of a VARIANT read the 16-byte slot as an ordinal -- Ord grew a
	@# route-to-pylib arm for non-ordinal operands and Chr never did
	./$(COMPILER) test/test_nilpy_chr_of_variant.npy /tmp/test_nilpy_chr_of_variant26
	test "$$(/tmp/test_nilpy_chr_of_variant26)" = "$$(printf 'a b\nb\nabc\na\na A\nz\n97 98\ncaught chr')"
	@# a CHAR ordered against a STRING compared an ordinal with an ADDRESS, so
	@# every < was True and every > False whatever the characters were
	./$(COMPILER) test/test_nilpy_char_ordering.npy /tmp/test_nilpy_char_ordering26
	test "$$(/tmp/test_nilpy_char_ordering26)" = "$$(printf 'False True True False\nTrue True False False\nTrue False True False\nTrue False\nTrue False\nTrue True\n{\0475\047: 1}\n[\0475\047, \0473\047]\n123 3\n[\04712\047, \047+\047, \04734\047, \047*\047, \0472\047]\na lower\nZ upper\n9 digit\n! other')"
	@# a variant holding a STRING must be subscriptable -- pyvar_getitem cast to
	@# TObject before checking the tag, so `for w in words: w[0]` SEGFAULTED
	./$(COMPILER) test/test_nilpy_variant_str_index.npy /tmp/test_nilpy_variant_str_index26
	test "$$(/tmp/test_nilpy_variant_str_index26)" = "$$(printf 'a\na\nb\na d\nc\ncaught index\nTrue False\na [\047apple\047, \047avocado\047]\nb [\047banana\047, \047blueberry\047]\n7 5')"
	@# f.write("text") must write the TEXT -- it resolved to the TPyBytes overload
	@# and wrote ~18 KB of adjacent process memory into the file instead
	./$(COMPILER) test/test_nilpy_file_write_text.npy /tmp/test_nilpy_file_write26
	test "$$(/tmp/test_nilpy_file_write26)" = "$$(printf 'hello\n6\n5 a\nbb\n[]\n5000\nfirst\nsecond')"
	# close()/readlines() on a read-mode handle (still a TPyList under the read-slurp model)
	./$(COMPILER) test/test_nilpy_file_close_readlines.npy /tmp/test_nilpy_file_closerl26
	test "$$(/tmp/test_nilpy_file_closerl26)" = "$$(printf '3\none\ntwo\nthree')"
	# a NilPy module shipped in a LIBRARY ROOT is importable, and a Pascal unit
	# of a different name still wins its own lookup (import re -> lib/rtl/re.pas)
	./$(COMPILER) -Futest/nilpylib test/test_nilpy_import_py_from_library_path.npy /tmp/test_nilpy_pylibpath26
	test "$$(/tmp/test_nilpy_pylibpath26)" = "$$(printf 'lib:x\n42\nbbnbnb')"
	# a dynamically-typed receiver picks its candidate class by ARITY when the
	# argument count settles it (songformatter's `var.get()`)
	./$(COMPILER) test/test_nilpy_variant_method_pick_by_arity.npy /tmp/test_nilpy_arity26
	test "$$(/tmp/test_nilpy_arity26)" = "$$(printf '42\n1')"
	# f.write(x) reaches the STRING overload whenever x is a str at RUN time,
	# not only when it is statically one (overload pick by argument type)
	./$(COMPILER) test/test_nilpy_write_overload_by_arg_type.npy /tmp/test_nilpy_wovl26
	test "$$(/tmp/test_nilpy_wovl26)" = "$$(printf 'via-param\nxconcat\nfmt!\nlocal?\ndirect-literal\nbytes-arg')"
	# open() answers ONE class in every mode: reuse of a name across w/a/r, the
	# silent .write-to-a-widened-read-class data loss, iteration, readlines()
	./$(COMPILER) test/test_nilpy_open_one_class_every_mode.npy /tmp/test_nilpy_open_one_class26
	test "$$(/tmp/test_nilpy_open_one_class26)" = "$$(printf '[one\n]\nafter-append:one|two|\niter:one\niter:two\nlines:2')"
	# a name bound by `with open(...) as f:` reused later for a plain `f = open(...)`
	./$(COMPILER) test/test_nilpy_with_name_reuse.npy /tmp/test_nilpy_with_name_reuse26
	test "$$(/tmp/test_nilpy_with_name_reuse26)" = "$$(printf '2\n[one\ntwo\n]')"
	@# `"x" * n` must be LINEAR -- the large sizes here are the regression guard,
	@# the old quadratic routine could not finish this file
	./$(COMPILER) test/test_nilpy_str_repeat_linear.npy /tmp/test_nilpy_str_repeat26
	test "$$(timeout 60 /tmp/test_nilpy_str_repeat26)" = "$$(printf 'xxxxx ababab abcabc\nababab\n[] [] []\n1 1000\n80000\n200000\n1000000\n300000 a b c c')"
	@# a nested def that CAPTURES and then ESCAPES must carry its captures: the
	@# bridge marshals the body's own arity before them, not a hardcoded one
	# `def w` TWICE in one enclosing def: Python rebinds the name, so the later
	# body wins from its def statement on and the statements BETWEEN see the
	# earlier one. Both used to register under `outer.w` and the second was
	# unreachable -- uforth's two w_include defs, and its whole ANS FILE word set.
	./$(COMPILER) test/test_nilpy_nested_def_redefined_in_one_scope.npy /tmp/test_nilpy_redef26
	test "$$(/tmp/test_nilpy_redef26)" = "$$(printf '%b' 'between: 11\nafter: 110\n11 110\n1 2 3 3\n[5, 7]\n42\n2')"
	./$(COMPILER) test/test_nilpy_escaping_closure.npy /tmp/test_nilpy_escaping_closure26
	test "$$(/tmp/test_nilpy_escaping_closure26)" = "$$(printf '42\n42\n13\n16\n42\n3\n6\n42\n42\n7')"
	@# ...at EVERY arity. The bridge's per-arity table had gaps (no 10, no 12,
	@# nothing past 13) and rounded UP, which segfaults rather than degrading --
	@# uforth's MARKER (1 own + 11 captures) is what found it.
	./$(COMPILER) test/test_nilpy_escaping_closure_many_captures.npy /tmp/test_nilpy_closure_caps26
	test "$$(/tmp/test_nilpy_closure_caps26)" = "$$(printf '843\n952\n1173\n1398\n2217\n1181\n1 2 3 108')"
	@# a function returning a CONTAINER ELEMENT hands back a borrow, not a +1 --
	@# the container's own reference must survive the caller's scope exit, and a
	@# returned CONSTRUCTION must still not be retained twice
	./$(COMPILER) test/test_nilpy_returned_container_element_survives.npy /tmp/test_nilpy_borrowret26
	test "$$(/tmp/test_nilpy_borrowret26)" = "$$(printf '3 [1, 5, 3]\n4 9\n4 7\n8 8 15\n[4, 5, 6] [7, 8]\n[1, 5, 11]')"
	# `nonlocal` through an ESCAPING closure: the by-ref capture used to be bound
	# as a VALUE, so the body stored through the value-as-address and died. Now a
	# heap CELL is bound, which also gives the escaped counter shared state.
	# After `for i in range(...)` the name holds the LAST VALUE YIELDED, and an
	# EMPTY range leaves an existing binding alone. The counter used to be the
	# user's variable, which left the failing value on exit and `start` on zero
	# iterations. A comprehension's loop name must still not leak.
	./$(COMPILER) test/test_nilpy_range_counter_after_loop.npy /tmp/test_nilpy_range_after26
	test "$$(/tmp/test_nilpy_range_after26)" = "$$(printf 'i 2\nj 7\nk 9\nd 1\nm 99\np 7\nnested 2 1\nbreak 4\nonce 0\nsum 6 last 3\nrebound 20\ncomp [0, 1, 2] untouched\ncomp2 [0, 4, 8]\ncomputed 2')"
	./$(COMPILER) test/test_nilpy_nonlocal_escaping_closure.npy /tmp/test_nilpy_nonlocal_esc26
	test "$$(/tmp/test_nilpy_nonlocal_esc26)" = "$$(printf 'before\nafter\n1\n2\n3\n1 2 1\nalive: 2\nreadonly: 7\ntwo: 2020 3030\nfloat: 0.75 1.0\nlist: 1 2\nassign plain: 41\nassign nonlocal: 41\nassign counter: 1 2 3\nshared a: 1\nshared b: 99\nshared c: 1\nshared d: 15\nshared e: 9\nshared f: 2\ndirect: 2\nboth: 2')"
	@# a PROVABLE operand-type clash warns at compile time -- and still raises at
	@# run time, so the diagnostic and the program agree. It must NOT abort:
	@# `if False: 3 - "ab"` is legal CPython (decide-nilpy-mixed-type-operand-policy).
	./$(COMPILER) test/test_nilpy_static_operand_clash.npy /tmp/test_nilpy_static_clash26 2>&1 \
	  | grep -c "warning: Nil Python: operator" | grep -qx 6 \
	  || { echo 'test_nilpy_static_operand_clash: FAIL - expected 6 provable-clash warnings'; exit 1; }
	test "$$(/tmp/test_nilpy_static_clash26)" = "$$(printf 'sub TE\nadd TE\ndiv TE\nfdiv TE\nlt TE\nge TE\nababab ababab\n3/ab\n4 2 1.25 abc True True')"
	./$(COMPILER) test/test_nilpy_none_value_semantics.npy /tmp/test_nilpy_none_value_semantics26
	test "$$(/tmp/test_nilpy_none_value_semantics26)" = "$$(printf 'False False True True\nFalse False True\nFalse False\nFalse False\nFalse False\nFalse False\nTrue False\nTrue False False False False\nFalse False False False\nNone None v=None False\nNone\nn None a None\nTrue True True True True\ngood')"
	@# int(<str>) is arbitrary precision: the digits are data, so the width
	@# cannot be decided at compile time and Python's int has none. It used to
	@# answer the value mod 2^64, read signed, in silence.
	./$(COMPILER) test/test_nilpy_int_of_string_is_arbitrary_precision.npy /tmp/test_nilpy_int_str_promo26
	test "$$(/tmp/test_nilpy_int_str_promo26)" = "$$(printf '12345678901234567890\n123456789012345678901234567890\n123456789012345678901234567890123456789012345678901234567890\n-123456789012345678901234567890\n12345678901234567890\nTrue\nTrue\n123456789012345678901234567891\n246913578024691357802469135780\n0\n123456789012345\n0\nTrue\nTrue\nTrue\n42\n-8\n8\n0\n40\n6\nValueError\nValueError\nValueError\n123456789012345678901234567890')"
	@# a two-name for-target over a VARIANT container: a list of pairs reached
	@# through an erased type used to be unboxed as a dict and raise. .items()
	@# is the one thing that still says 'dict' after the suffix is stripped.
	./$(COMPILER) test/test_nilpy_for_two_names_over_a_variant.npy /tmp/test_nilpy_for2var26
	@# .expected, not an inline printf: the expectation contains Python's repr of
	@# a list of STRINGS (['ab', 'cd']), and a single quote inside a
	@# single-quoted printf ENDS the quote — so the inline form silently encoded
	@# [ab, cd] and could never match, no matter what the compiler did.
	/tmp/test_nilpy_for2var26 | diff -u test/test_nilpy_for_two_names_over_a_variant.expected -
	@# /= and **= on a class instance dispatch __itruediv__ / __ipow__ (then the
	@# binary form and rebind). Both used to raise 'expected a number, got object'.
	./$(COMPILER) test/test_nilpy_truediv_pow_assign_class_dunder.npy /tmp/test_nilpy_tdivpow26
	test "$$(/tmp/test_nilpy_tdivpow26)" = "$$(printf '5\n9\n25 32\n3\n8\n4\n16\n81\n[2, 1.0]\n[32, 1.0]\n[2.0, 2.0]\n{'"'"'a'"'"': 9}\n2.0\n1024\n0.5\n1180591620717411303424\nTypeError')"
	@# hasattr over a receiver whose class is a RUN-TIME fact (list element, dict
	@# value, untyped parameter): the declared-field half is answered by testing
	@# the object's class against the set that declares the name.
	./$(COMPILER) test/test_nilpy_hasattr_variant_receiver.npy /tmp/test_nilpy_hasattr_var26
	test "$$(/tmp/test_nilpy_hasattr_var26)" = "$$(printf 'True False\nTrue True False\nTrue False\nTrue False\nFalse True\n1 2\npresent missing\nTrue\nTrue\nTrue True False\nFalse False False')"
	./$(COMPILER) test/test_nilpy_return_nested_def.npy /tmp/test_nilpy_return_nested_def26
	test "$$(/tmp/test_nilpy_return_nested_def26)" = "$$(printf '11 21\n2\n101\n1001 2002\n35\n45\n8 9 10')"
	./$(COMPILER) test/test_nilpy_lambda_sibling_capture.npy /tmp/test_nilpy_lambda_sibling_capture26
	test "$$(/tmp/test_nilpy_lambda_sibling_capture26)" = "$$(printf 'F 11 fwd\nF 11 fwd\nB 21 back\nB 21 back\nC 1 2 3\nR 5\nR 5\nR 5\nR 5')"
	./$(COMPILER) test/test_nilpy_nested_def.npy /tmp/test_nilpy_nested_def26
	./$(COMPILER) test/test_nilpy_nested_def_capture.npy /tmp/test_nilpy_nested_def_capture26
	test "$$(/tmp/test_nilpy_nested_def_capture26)" = "$$(printf '11\n|x||y|\n11\n223\n13')"
	test "$$(/tmp/test_nilpy_nested_def26)" = "$$(printf '11\n34\n200\n7')"
	./$(COMPILER) test/test_nilpy_str_repeat.npy /tmp/test_nilpy_str_repeat26
	test "$$(/tmp/test_nilpy_str_repeat26)" = "$$(printf '300\nababab 6\nqq\nzzy\n12')"
	./$(COMPILER) test/test_nilpy_long_string.npy /tmp/test_nilpy_long_string26
	test "$$(/tmp/test_nilpy_long_string26)" = "$$(printf '300\n1000\nx\n400 y\n300\n300\n0 1 xxx')"
	./$(COMPILER) test/test_nilpy_subscript_suffix.npy /tmp/test_nilpy_subscript_suffix26
	test "$$(/tmp/test_nilpy_subscript_suffix26)" = "$$(printf 'b a c c\nB c a\ny 10\nv\ny z X\nq 1\n1')"
	./$(COMPILER) test/test_nilpy_unary_minus_precedence.npy /tmp/test_nilpy_unary_minus_precedence26
	test "$$(/tmp/test_nilpy_unary_minus_precedence26)" = "$$(printf -- '-4 1 -4 1\n-4 -1 3 -1\n-14 -5 -3.5 -9 9\n-4.0 0.5 0\n-4 1 -14 -3\n3 3')"
	./$(COMPILER) test/test_nilpy_print_container.npy /tmp/test_nilpy_print_container26
	test "$$(/tmp/test_nilpy_print_container26)" = "$$(printf "['a', 'bb']\n[1, 2, 3]\n[]\n[1.5, True, 'x']\n['a', 'b']\n{'k': 'v', 'n': 2}\n[[1, 2], ['a']]")"
	./$(COMPILER) test/test_nilpy_one_char_string.npy /tmp/test_nilpy_one_char_string26
	test "$$(/tmp/test_nilpy_one_char_string26)" = "$$(printf 'd 1\ndx\nq!\nz! 1\na 1\nbb 2\n97 b True ab\naaa True')"
	./$(COMPILER) test/test_nilpy_inheritance.npy /tmp/test_nilpy_inheritance26
	test "$$(/tmp/test_nilpy_inheritance26)" = "$$(printf 'rex has 4\nwoof\ntom has 4\nmeow 9\nwoof rex2 has 4\nwoof ax has 4\nmeow bx has 4\n... cx has 2')"
	./$(COMPILER) test/test_nilpy_variant_method_call.npy /tmp/test_nilpy_variant_method_call26
	test "$$(/tmp/test_nilpy_variant_method_call26)" = "$$(printf '2 20 True\n5 50 False\none 21\ntwo 24\n<alpha>\n<beta>\n20 <alpha>\n4\n25')"
	./$(COMPILER) test/test_nilpy_variant_unbox.npy /tmp/test_nilpy_variant_unbox26
	test "$$(/tmp/test_nilpy_variant_unbox26)" = "$$(printf '7 -3 0\n2.5 -0.5\nab z\nTrue False\n8 6 14 3 1 -7\n4 -21\n3.5 5.0\nabc\nTrue True True\n4\nabz\n2.0')"
	./$(COMPILER) test/test_nilpy_dataclass.npy /tmp/test_nilpy_dataclass26
	test "$$(/tmp/test_nilpy_dataclass26)" = "$$(printf '3\n4\n25\n10\nfull 1.5 2 False custom\ndefaults 2.5 7 True std\nmix 9.0 7 True std')"
	./$(COMPILER) test/test_nilpy_dict_comprehension.npy /tmp/test_nilpy_dict_comprehension26
	test "$$(/tmp/test_nilpy_dict_comprehension26)" = "$$(printf '%b' '3\n60\n9\n3\n4')"
	./$(COMPILER) test/test_nilpy_captured_class.npy /tmp/test_nilpy_captured_class26
	test "$$(/tmp/test_nilpy_captured_class26)" = "$$(printf '%b' 'HE\n?\n2')"
	./$(COMPILER) test/test_nilpy_method_nested_def.npy /tmp/test_nilpy_method_nested_def26
	test "$$(/tmp/test_nilpy_method_nested_def26)" = "$$(printf '%b' '23\n23')"
	./$(COMPILER) test/test_nilpy_optional_int_none.npy /tmp/test_nilpy_optional_int_none26
	test "$$(/tmp/test_nilpy_optional_int_none26)" = "$$(printf '%b' '7\n42\n0')"
	./$(COMPILER) test/test_nilpy_variant_in.npy /tmp/test_nilpy_variant_in26
	test "$$(/tmp/test_nilpy_variant_in26)" = "$$(printf '%b' '2 in list\n5 not in list\nk in dict')"
	./$(COMPILER) test/test_nilpy_is_none_typed.npy /tmp/test_nilpy_is_none_typed26
	test "$$(/tmp/test_nilpy_is_none_typed26)" = "$$(printf '%b' '11\nobj-live\nTrue\nTrue\n1\ncompound-yes\n[1]\nTrue\n1\nFalse\nFalse\nTrue\n5\nNone')"
	./$(COMPILER) test/test_nilpy_bytes_setslice_variant.npy /tmp/test_nilpy_bytes_setslice_variant26
	/tmp/test_nilpy_bytes_setslice_variant26 | diff -u test/test_nilpy_bytes_setslice_variant.expected -
	@# `seq * n` where the COUNT has no static type (uforth's FILL)
	./$(COMPILER) test/test_nilpy_sequence_repeat_variant_count.npy /tmp/test_nilpy_seqrep26
	/tmp/test_nilpy_seqrep26 | diff -u test/test_nilpy_sequence_repeat_variant_count.expected -
	./$(COMPILER) test/test_nilpy_unnamed_managed_temp_init.npy /tmp/test_nilpy_unnamed_managed_temp_init26
	test "$$(/tmp/test_nilpy_unnamed_managed_temp_init26)" = "75"
	./$(COMPILER) test/test_nilpy_not_container.npy /tmp/test_nilpy_not_container26
	test "$$(/tmp/test_nilpy_not_container26)" = "$$(printf '%b' 'xs-truthy\nB\nd-truthy\nD')"
	./$(COMPILER) test/test_nilpy_variant_to_str_param.npy /tmp/test_nilpy_variant_to_str_param26
	test "$$(/tmp/test_nilpy_variant_to_str_param26)" = "$$(printf '%b' 'WORLD\nHELLO\nWORLD\nworld')"
	./$(COMPILER) test/test_nilpy_variant_return_to_class.npy /tmp/test_nilpy_variant_return_to_class26
	test "$$(/tmp/test_nilpy_variant_return_to_class26)" = "$$(printf '%b' 'none-ok\nfound-ok')"
	./$(COMPILER) examples/shell/shell0.npy /tmp/test_nilpy_shell026
	/tmp/test_nilpy_shell026 | grep -q "hello portable userland"
	# set operators (&, |, -, ^) and PEP 584 dict union (|); expectation is CPython's own output
	@# several classes declare a callable field of one name, with DIFFERENT
	@# offsets: the class must be decided at RUN time, not hard-cast
	./$(COMPILER) test/test_nilpy_variant_field_call_runtime_dispatch.npy /tmp/test_nilpy_vfcalldisp26
	/tmp/test_nilpy_vfcalldisp26 | diff -u test/test_nilpy_variant_field_call_runtime_dispatch.expected -
	@# __repr__/__str__ on a user instance reached only as a container ELEMENT
	./$(COMPILER) test/test_nilpy_container_element_repr.npy /tmp/test_nilpy_celemrepr26
	/tmp/test_nilpy_celemrepr26 | diff -u test/test_nilpy_container_element_repr.expected -
	./$(COMPILER) test/test_nilpy_set_ops.npy /tmp/test_nilpy_setops26
	@# .expected: a set operator now RETURNS a set, so these repr as {2, 3} —
	@# the old inline expectation encoded the list-repr this ticket removed.
	/tmp/test_nilpy_setops26 | diff -u test/test_nilpy_set_ops.expected -
	# bin()/oct() builtins, and enumerate(xs, start) / enumerate(xs, start=N); expectation is CPython's own output
	./$(COMPILER) test/test_nilpy_bin_oct_enumerate_start.npy /tmp/test_nilpy_bome26
	test "$$(/tmp/test_nilpy_bome26)" = "$$(printf '%b' '0b1010 0o12 0xa\n-0b101 -0o5\n0b0 0o0\n[(1, \047a\047), (2, \047b\047)]\n[(5, \047a\047), (6, \047b\047)]\n[(0, \047a\047), (1, \047b\047)]')"
	# str.rsplit()/partition()/rpartition(); expectation is CPython's own output
	./$(COMPILER) test/test_nilpy_str_rsplit_partition.npy /tmp/test_nilpy_rsplit26
	test "$$(/tmp/test_nilpy_rsplit26)" = "$$(printf '%b' '[\047hell\047, \047 w\047, \047rld\047]\n[\047hello w\047, \047rld\047]\n[\047a,b\047, \047c\047, \047d\047]\n(\047hello\047, \047 \047, \047world\047)\n(\047hello w\047, \047o\047, \047rld\047)\n(\047hello world\047, \047\047, \047\047)\n(\047\047, \047\047, \047hello world\047)\n[\047\047]')"
	# list + non-list used to silently corrupt (reinterpreting the list pointer
	# as string data); then became a COMPILE error, which was loud but still
	# diverged from CPython -- a try/except around it could not build. Now a
	# genuine runtime TypeError, so this COMPILES and the handler runs.
	./$(COMPILER) test/test_nilpy_list_plus_nonlist_fail.npy /tmp/test_nilpy_lpnl_fail26
	test "$$(/tmp/test_nilpy_lpnl_fail26)" = "$$(printf '%b' 'caught list+str\nstill running')"
	# set methods: issubset/issuperset/union/intersection/difference/add/discard/remove; expectation is CPython's own output
	./$(COMPILER) test/test_nilpy_set_methods.npy /tmp/test_nilpy_setmeth26
	test "$$(/tmp/test_nilpy_setmeth26)" = "$$(printf '%b' 'False\nTrue\nTrue\n[1, 2, 3]\n[2, 3]\n[1]\n[1, 2, 3, 4]\n[2, 3, 4]\n[2, 3, 4]\n[3, 4]')"
	# arithmetic operator dunders (__add__/__sub__/__mul__/__truediv__) on a user class; expectation is CPython's own output
	./$(COMPILER) test/test_nilpy_operator_dunders.npy /tmp/test_nilpy_opdunder26
	test "$$(/tmp/test_nilpy_opdunder26)" = "$$(printf '%b' '(5, 8)\n(3, 4)\n(12, 18)\n(2.0, 3.0)')"
	# a class with no matching dunder used to silently compute garbage instead of
	# erroring; then became a COMPILE error, which was loud but still diverged
	# from CPython -- a try/except around it could not build. Now a genuine
	# runtime TypeError, so this COMPILES and the handler runs.
	./$(COMPILER) test/test_nilpy_operator_dunder_missing_fail.npy /tmp/test_nilpy_nodunder_fail26
	test "$$(/tmp/test_nilpy_nodunder_fail26)" = "$$(printf '%b' 'caught missing __add__\nstill running')"
	# a str method returning a CONTAINER, subscripted immediately, on a VARIABLE
	# receiver: the route cleared recName so the subscript had no class to
	# resolve against and the AN_CALL reached IR lowering unlowered
	./$(COMPILER) test/test_nilpy_str_method_subscript.npy /tmp/test_nilpy_strmsub26
	test "$$(/tmp/test_nilpy_strmsub26)" = "$$(printf '%b' 'World\nHello\nc\n[\047a\047, \047b\047, \047c\047]\nb\ny\nH\nhello,world\nPAD\nb\n72\ntwo')"
	# the `,` thousands separator, and unsupported specs raising instead of
	# HALTING the process. Also: a float spec naming no type and no precision is
	# Python's general form, not fixed-6.
	./$(COMPILER) test/test_nilpy_format_thousands.npy /tmp/test_nilpy_fth26
	test "$$(/tmp/test_nilpy_fth26)" = "$$(printf '%b' '1,234,567\n-1,234,567\n0\n999\n1,000\n9,876,543,210\n100\n1234567\n42 ff 00007\nbad spec caught\nstill running\n1,234.50\n1,234.5\n1,234,567.25\n1234.50\n      3.14\n75%\n1.234500e+03\n1234.5\n-9,876.5')"
	# extended slices xs[lo:hi:step] for any non-zero step — only the whole-range
	# reverse [::-1] used to work. Bounds are CPython's slice.indices(): with a
	# negative step the omitted defaults AND the clamps differ from a plain slice.
	# Also covers tupleness across a reversal, and step 0 raising catchably.
	./$(COMPILER) test/test_nilpy_slice_step.npy /tmp/test_nilpy_slicestep26
	test "$$(/tmp/test_nilpy_slicestep26)" = "$$(printf '%b' 'bd\naceg\nadg\nceg\nace\nhgfedcba\nhfdb\nedc\nhgf\nhgfed\n[]\n[]\n[]\n[]\na\nh\n[1, 3, 5]\n[0, 2, 4, 6]\n[7, 6, 5, 4, 3, 2, 1, 0]\n[7, 4, 1]\n[6, 4, 2]\n[]\n(4, 3, 2, 1)\n(1, 3)\n(2, 4)\naceg\nhfdb\n[0, 3, 6]\nhfdb\n[0, 3, 6]\nstep-zero ValueError caught\nstep-zero ValueError caught on list\nstill running')"
	# type(x).__name__ reported the PASCAL class backing the value (TPyList for a
	# list) — silently wrong — and refused scalars outright. tuple/list share one
	# class, so the answer needs FIsTuple at run time, not a class name.
	./$(COMPILER) test/test_nilpy_type_name.npy /tmp/test_nilpy_typename26
	test "$$(/tmp/test_nilpy_typename26)" = "$$(printf '%b' 'Dog\nAnimal\nint\nfloat\nbool\nstr\nNoneType\nlist\ndict\ndict\nbytes\ntuple\nlist\ntuple\ntuple\nint\nstr\nfloat\nNoneType\nbool\nlist\ntuple\ndict\nint str list tuple')"
	# for-in over a list iterates it LIVE. The bound used to be snapshotted while
	# the element fetch read the live list, so mutation mid-loop diverged: growth
	# was silently missed and shrinking ran off the end into an IndexError.
	./$(COMPILER) test/test_nilpy_iterate_live_list.npy /tmp/test_nilpy_livelist26
	test "$$(/tmp/test_nilpy_livelist26)" = "$$(printf '%b' '[1, 2, 3, 9]\n[1, 2, 3, 9]\n[1, 2, 3]\n[1, 2, 3]\n[1, 3]\n[2, 4]\n[1]\n[]\n[2, 4, 6]\n[2, 3]\n0 1\n1 2\n2 3\na 1\nb 2\na 1\nb 2\na\nb\nc\n90\nempty ok\n[1, 3]')"
	# del l[i] — a plain list index was a compile error; only del d[k] and
	# del l[a:b] worked. Out of range RAISES (a slice clamps), and the index
	# expression must be evaluated exactly once.
	# pop(i) shifted the tail with a RAW slot copy, leaving the vacated tail slot
	# aliasing a LIVE element -- the next append released it. Refcounted elements
	# only; a list of ints hides it entirely.
	./$(COMPILER) test/test_nilpy_list_pop_at_index_keeps_the_rest.npy /tmp/test_nilpy_popat26
	test "$$(/tmp/test_nilpy_popat26)" = "$$(printf '%b' '(\047tag\047, 0) [(\047tag\047, 1), (\047z\047, 9)]\n[(\047tag\047, 1), (\047tag\047, 2), (\047z\047, 9)]\n[(\047tag\047, 0), (\047tag\047, 2), (\047tag\047, 3), (\047z\047, 9)]\n[(\047tag\047, 0), (\047tag\047, 1), (\047z\047, 9)]\n[(\047tag\047, 1), (\047tag\047, 0)]\n[(\047tag\047, 0), (\047tag\047, 2), (\047z\047, 9)]\n[[3, 4], [5, 6]]\n[\047bb\047, \047cc\047]\n[(\047tag\047, 0), (\047z\047, 9)]\n(\047tag\047, 0) [(\047tag\047, 1), (\047z\047, 9)]\n[(\047tag\047, 0), (\047tag\047, 1), (\047tag\047, 2), (\047tag\047, 3), (\047tag\047, 4)]')"
	./$(COMPILER) test/test_nilpy_del_list_index.npy /tmp/test_nilpy_delidx26
	test "$$(/tmp/test_nilpy_delidx26)" = "$$(printf '%b' '[0, 2, 3, 4]\n[0, 2, 3]\n[2, 3]\nIndexError\n[2, 3]\nIndexError neg\n[2, 3]\n[1, 2, 3]\n[8, 9]\n1\n{\047b\047: 2}\n[1, 4, 5]\n[]\n0')"
	# a str is an iterable: sorted/zip/enumerate over one passed the string HANDLE
	# where an object pointer was expected and SEGFAULTED with no diagnostic
	# (sorted printed [] first). The calls are built by a fixed FindProc index, so
	# Pascal overloads are never consulted — the str is exploded at the call site.
	./$(COMPILER) test/test_nilpy_str_iterable_builtins.npy /tmp/test_nilpy_striter26
	test "$$(/tmp/test_nilpy_striter26)" = "$$(printf '%b' '[\047a\047, \047b\047, \047c\047]\n[\047a\047, \047b\047, \047c\047]\n3\nabc\n[\047c\047, \047b\047, \047a\047]\n[(\047c\047, \047x\047), (\047a\047, \047y\047), (\047b\047, \047z\047)]\n[(\047c\047, 1), (\047a\047, 2), (\047b\047, 3)]\n[(1, \047c\047), (2, \047a\047), (3, \047b\047)]\n[(0, \047c\047), (1, \047a\047), (2, \047b\047)]\n[(1, \047c\047), (2, \047a\047), (3, \047b\047)]\n[(-2, \047c\047), (-1, \047a\047), (0, \047b\047)]\n1 c\n2 a\n3 b\n(\047c\047, \047x\047)\n(0, \047c\047)\n[]\n[]\n[]\n[1, 2, 3]\n[(1, 1), (2, 2), (3, 3)]\n[(0, 1), (1, 2), (2, 3)]\n[\047a\047, \047b\047, \047c\047]\n[\047b\047, \047a\047, \047c\047]\nbac')"
	# in-place mutators return None. list.remove/insert and dict.remove/update
	# were PROCEDURES, so reading their result read a value never written —
	# garbage (1592266472), '()', or a spurious IndexError, silently.
	./$(COMPILER) test/test_nilpy_mutators_return_none.npy /tmp/test_nilpy_mutnone26
	test "$$(/tmp/test_nilpy_mutnone26)" = "$$(printf '%b' 'None\n[9, 3, 1, 2]\nNone\n[3, 1, 2]\nNone\n[(\047a\047, 1), (\047z\047, 2)]\nNone\n[(\047q\047, 5)]\nTrue\nTrue\nTrue\ninsert result is falsy\n[9, 3, 2, 4]\n[(\047a\047, 9), (\047z\047, 2)]\n[(\047z\047, 2)]\n[(\047a\047, 2), (\047b\047, 1)]')"
	# dict.copy() (shallow) and dict.popitem() (LIFO, KeyError when empty, yields a
	# TUPLE) — both were "TPyDict has no method ..."
	./$(COMPILER) test/test_nilpy_dict_copy_popitem.npy /tmp/test_nilpy_dictcp26
	test "$$(/tmp/test_nilpy_dictcp26)" = "$$(printf '%b' '[(\047a\047, 1), (\047b\047, 2)]\n[(\047a\047, 1), (\047b\047, 2)]\n[(\047a\047, 1), (\047b\047, 2), (\047z\047, 9)]\n[1, 2]\n[]\n[(\047a\047, 1), (\047b\047, 2)]\n(\047c\047, 3)\n[(\047a\047, 1), (\047b\047, 2)]\n(\047b\047, 2)\n[(\047a\047, 1)]\n(\047a\047, 1)\n[]\nKeyError on empty\nstill running\ntuple\n[(\047k\047, 5)]\n[(\047a\047, 1), (\047b\047, 2)]\n[\047a\047, \047b\047]\n[1, 2]\n[]\n[]\n[(\047x\047, 1), (\047y\047, 2)]\n[\047x\047, \047y\047]\n[1, 2]\n[(\047x\047, 1), (\047y\047, 2)]\nq 9')"
	# format-spec gaps that were all "unsupported format spec": the SIGN flag
	# ('+', '-', ' '), the '#' ALTERNATE form, '_' grouping and the 'c' type, plus
	# .precision on a STRING (truncates). Ordering is the point: zero padding goes
	# between the sign and the digits (+00042) and INSIDE the base prefix
	# (0x0000002a). The string overload also still HALTED on a bad spec.
	./$(COMPILER) test/test_nilpy_format_sign_flag.npy /tmp/test_nilpy_fsign26
	test "$$(/tmp/test_nilpy_fsign26)" = "$$(printf '%b' '+42\n-42\n42\n-42\n 42\n-42\n+0\n 0\n+42\n-42\n  +42|\n42++++++|\n++++++42|\n+++42+++|\n+00042\n-00042\n 00042\n+3.14\n-3.14\n 3.14\n     +3.14|\n+000003.14\n+1,234,567\n-1,234,567\n+3.14\n+2a\n+101010\n+42\n+3.1\n 42\n0x2a\n0X2A\n0o52\n0b101010\n0x0\n-0x2a\n0x0000002a\n-0x000002a\n      0x2a|\n2a########|\n+0x2a\n0x12d687\n0x2a\n1_234_567\n-1_234_567\n42\n1_234_567\n+1_234_567\nA\n*\nab\nabcdef\n|\nabc     |\n     abc|\nstring spec ValueError caught\nstill running\n+42|-42| 42|\n+42     |\n0x2a|0o52|0X2A|\n0x0000002a|\nHi!\n03.14|+3.142|3.14      |\nabcdef=42 (2a)\n42%')"
	# `()` — the EMPTY tuple. The tuple-vs-grouping test scanned for a top-level
	# COMMA, so `()` was read as parens around nothing: "expected expression".
	# Zero-argument CALLS share the shape and must stay unaffected.
	./$(COMPILER) test/test_nilpy_empty_tuple.npy /tmp/test_nilpy_emptytup26
	test "$$(/tmp/test_nilpy_emptytup26)" = "$$(printf '%b' '()\n0\ntuple\nTrue\nFalse\n(1, 2)\n(1, 2)\n()\n[]\n[]\nempty loop ok\n1 2\nFalse\n()\n0\n%\n100%\n1\n0\nX')"
	# inf/-inf/nan print Python-spelled (lower case). Pascal's FloatToStr says
	# Inf/-Inf/Nan and MUST keep saying it, so the respelling is NilPy-only and
	# keyed on the float tag — a string reading "Inf" stays untouched.
	./$(COMPILER) test/test_nilpy_inf_nan_spelling.npy /tmp/test_nilpy_infnan26
	test "$$(/tmp/test_nilpy_infnan26)" = "$$(printf '%b' 'inf\n-inf\nnan\ninf\n-inf\nnan\ninf\n[inf, -inf]\n(inf, -inf)\n{\047k\047: inf}\ninf\n-inf\nInf\nInf\n[\047Inf\047]\nTrue\n3\n2.5\n2.5\n-0.125\n[1.5, 2.5]\n2.5\nTrue\nTrue\nFalse')"
	# os.path.isdir / isfile / splitext, which were "undefined variable (os)".
	# A missing path is False for isdir/isfile (CPython's rule), and splitext
	# splits at the last dot of the BASENAME — a leading dot is not an extension.
	./$(COMPILER) test/test_nilpy_os_path_gaps.npy /tmp/test_nilpy_ospath26
	test "$$(/tmp/test_nilpy_ospath26)" = "$$(printf '%b' 'True\nFalse\nFalse\nTrue\nFalse\nFalse\nFalse\nFalse\n(\047f.tar\047, \047.gz\047)\n(\047noext\047, \047\047)\n(\047/a/b/c\047, \047.txt\047)\n(\047x\047, \047.\047)\n(\047\047, \047\047)\n(\047.bashrc\047, \047\047)\n(\047/a/b/.hidden\047, \047\047)\n(\047/a.b/c\047, \047\047)\n(\047a.b/c\047, \047\047)\ntuple\nf.tar\n.gz\nc.txt\n/a/b\na/b\nTrue')"
	# the optional start/end WINDOW on find/rfind/index/count/startswith/endswith.
	# The window is a SLICE (clamps, takes negative bounds) and a returned INDEX is
	# rebased onto the original string — dropping that offset is the silent half.
	./$(COMPILER) test/test_nilpy_str_search_window.npy /tmp/test_nilpy_strwin26
	test "$$(/tmp/test_nilpy_strwin26)" = "$$(printf '%b' '4\n7\n7\n-1\n-1\n7\n7\n7\n4\n7\n-1\n3\n2\n2\n0\n1\n7\n7\nindex raises ValueError\nTrue\nTrue\nTrue\nFalse\nTrue\nTrue\nTrue\nFalse\n-1\n0\nFalse\nstill running')"
	# the `assert` statement, which was "undefined variable (assert)". The
	# condition goes through PyMakeTruthy (so Python's truthiness rules are the
	# shared ones), and a BARE assert carries an EMPTY message, as CPython does.
	./$(COMPILER) test/test_nilpy_assert.npy /tmp/test_nilpy_assert26
	test "$$(/tmp/test_nilpy_assert26)" = "$$(printf '%b' 'pass ok\ncaught: boom\nbare len: 0\nempty list is falsy\nempty dict is falsy\nempty str is falsy\nNone is falsy\nzero is falsy\ntruthy ok\n5\nin def: must be positive\nvia Exception: generic\nn was 3\nstill running')"
	# an int and a float that compare equal are the SAME dict key. `1 == 1.0` was
	# already True but the dict key path disagreed, so 1.0 missed a 1 key —
	# silently. Equal keys must hash equal, so an integral float hashes as its int.
	./$(COMPILER) test/test_nilpy_numeric_dict_keys.npy /tmp/test_nilpy_numkey26
	test "$$(/tmp/test_nilpy_numkey26)" = "$$(printf '%b' '1\nfloat\nfloat\nTrue\na\nTrue\nx\n1\nf\nm\nbig\nTrue\nhalf\nTrue\nFalse\nFalse\n1\nnz\n3\none\nstr-one\ntwo-five\nnan\nTrue\nFalse')"
	# `n /= 2` at MODULE level. Python's / is always true division, so the target
	# becomes a float — but the module type collector only matched `name = expr`,
	# so the name kept an int slot and printed the Double's raw BITS: i=8; i/=4
	# printed 0. Correct inside a def all along.
	./$(COMPILER) test/test_nilpy_module_true_divide_assign.npy /tmp/test_nilpy_tdiv26
	test "$$(/tmp/test_nilpy_tdiv26)" = "$$(printf '%b' '2.0\n2.5\n1.25\n0.333333\n2.0\n2.0\n4.5\n2.0\n4\n1\n9\n3\n6\n2\n16\n3.5\n2.0')"
	# `x in <bytes>` — a bytes SUBSEQUENCE or an integer BYTE VALUE. The bytes
	# receiver had no arm in the `in` dispatch and fell through to pycontains (a
	# TPyList scan), answering False for every bytes needle. Out-of-range int raises.
	./$(COMPILER) test/test_nilpy_bytes_membership.npy /tmp/test_nilpy_bymem26
	test "$$(/tmp/test_nilpy_bymem26)" = "$$(printf '%b' 'True\nTrue\nTrue\nFalse\nTrue\nTrue\nTrue\nFalse\nTrue\nFalse\nTrue\nValueError for 300\nValueError for -1\nTrue\nFalse\nbranch taken\n[b\047a\047]\nTrue\nFalse\nstill running')"
	# sorted(<dict>, key=...) — sorted() only accepted a TPyList, so a dict WITH a
	# key function had no overload to bind to (dict alone and list+key both worked)
	./$(COMPILER) test/test_nilpy_sorted_dict_key.npy /tmp/test_nilpy_sdk26
	test "$$(/tmp/test_nilpy_sdk26)" = "$$(printf '%b' '[\047a\047, \047b\047, \047c\047]\n[\047a\047, \047b\047, \047c\047]\n[\047c\047, \047b\047, \047a\047]\n[\047c\047, \047b\047, \047a\047]\n[(\047a\047, 1), (\047b\047, 2), (\047c\047, 3)]\n[\047a\047, \047b\047, \047c\047] [1, 2, 3]\n[1, 2, 3] [3, 2, 1] [3, 2, 1]')"
	# tuple() and pow(): the tuple TYPE existed but not its constructor, and pow
	# was undefined though ** worked
	./$(COMPILER) test/test_nilpy_tuple_pow_builtins.npy /tmp/test_nilpy_tpb26
	test "$$(/tmp/test_nilpy_tpb26)" = "$$(printf '%b' '(1, 2, 3)\n(\047a\047, \047b\047, \047c\047)\n()\n(1, 2) 1 2\n(1, 2, 3)\n[4, 5]\n1024 1 27\n8.0 0.5\n1024')"
	# numeric builtin gaps: float("inf"/"nan") raised ValueError, min/max were not
	# variadic, sum() took no start value
	./$(COMPILER) test/test_nilpy_numeric_builtins.npy /tmp/test_nilpy_numbi26
	test "$$(/tmp/test_nilpy_numbi26)" = "$$(printf '%b' 'True\nTrue\nTrue\nTrue\nTrue\n1.5 -2.0 3.5\nabc ValueError\n1 3\n0 9\n1 3\n2 9\n6 16\n0 5\n1.5 b')"
	# list.reverse() — IN PLACE. reversed()/[::-1] build a NEW sequence and worked;
	# the in-place method was absent, so xs.reverse() did not compile.
	./$(COMPILER) test/test_nilpy_list_reverse.npy /tmp/test_nilpy_lrev26
	test "$$(/tmp/test_nilpy_lrev26)" = "$$(printf '%b' '[1, 3, 5]\n[5, 3, 1]\n[1]\n[]\n[4, 3, 2, 1]\n[1, 2, 3, 4]\n[1, 2, 3, 4]\n[4, 3, 2, 1]\n[2.5, \047a\047, 1]')"
	# str.index()/rindex(): find/rfind that RAISE ValueError when absent. index was
	# missing from the str-method table entirely, so the raising form did not compile.
	./$(COMPILER) test/test_nilpy_str_index.npy /tmp/test_nilpy_stridx26
	test "$$(/tmp/test_nilpy_stridx26)" = "$$(printf '%b' '6 4 7\n7 9\n-1 -1\nindex ValueError\nrindex ValueError\nindex-from ValueError')"
	# a DERIVED tuple must stay a tuple: one representation backs list and tuple,
	# so slice/concat/repeat/reverse each have to carry the FIsTuple flag. They
	# did not, so (1,2,3)[1:] printed [2, 3]. print(t) alone was always right,
	# which is what hid it.
	./$(COMPILER) test/test_nilpy_tuple_identity.npy /tmp/test_nilpy_tupleid26
	test "$$(/tmp/test_nilpy_tupleid26)" = "$$(printf '%b' '(1, 2, 3)\n(2, 3)\n(1, 2)\n(3, 2, 1)\n(1, 2, 3, 4)\n(1, 2, 3, 1, 2, 3)\n[2, 3]\n[3, 2, 1]\n[1, 2, 3, 4]\n[1, 2, 3, 1, 2, 3]\n[1, 2, 3]\n[1, 2, 3]\n[3, 2, 1]\n(5,)\n(5, 5)')"
	# range() over a VARIANT bound (an unannotated parameter) compared the
	# tyInteger counter against the variant's BOX — always true, so the loop
	# never terminated. An annotated param, a literal and a module-level var all
	# worked, so nothing in the corpus caught it; a hanging test looks slow.
	./$(COMPILER) test/test_nilpy_range_variant_bound.npy /tmp/test_nilpy_rangevar26
	test "$$(/tmp/test_nilpy_rangevar26)" = "$$(printf '%b' '[0, 1, 4, 9]\n[2, 3, 4]\n[0, 3, 6, 9]\n[0, 1, 2]\n[]\n[0, 2, 4]\n[0, 1, 2, 3]\n[0, 1, 2]')"
	# round(x, n): negative n was IGNORED (round(1234.5678,-2) gave 1235.0), ties
	# went half-UP instead of half-to-EVEN, and the rounding was done on x*10**n
	# in doubles — which collapses 2.675 and 2.665 to the same apparent tie and
	# is why the last line was divergent until pyround_n moved onto the exact
	# decimal expansion. Every value here is now CPython's.
	./$(COMPILER) test/test_nilpy_round.npy /tmp/test_nilpy_round26
	test "$$(/tmp/test_nilpy_round26)" = "$$(printf '%b' '0 2 2 4 0 -2\n1 -2\n0.12 2.0\n2.35 0.14 1.0\n3.142 3.1\n1200.0 1230.0 16000.0\n-1200.0\n2.67 2.67\n9.99 0.04 0.3 100.0\n1.0 0.0 -0.0 0.0')"
	# hex/bin/oct of an ARBITRARY-PRECISION int. pylib's take Int64, so a value past
	# a machine word had no matching overload; a PromoInt overload is unwritable (a
	# PromoInt parameter cannot reach the runtime), so the frontend lowers a
	# promo-typed argument to promocore's PXXPromoToBase. See the test's header.
	./$(COMPILER) test/test_nilpy_hex_bin_oct_bigint.npy /tmp/test_nilpy_hexbig26
	/tmp/test_nilpy_hexbig26 | diff -u test/test_nilpy_hex_bin_oct_bigint.expected -
	# The promotable-int DEFAULT: an int that GROWS past 2^63 stays exact. Every
	# line of this test was wrong before it landed, each a different way a promo
	# reaches code that assumed a machine int (renderers, repeat counts,
	# truthiness, float mixing, call/return boundaries, captures, floor div/mod).
	# .expected is CPython's own output for the same file.
	./$(COMPILER) test/test_nilpy_int_promotion_default.npy /tmp/test_nilpy_intpromo26
	/tmp/test_nilpy_intpromo26 | diff -u test/test_nilpy_int_promotion_default.expected -
	# A comprehension nested inside one whose OUTER iterable is range(): the inner
	# build stayed hoisted to the enclosing statement, so it ran ONCE with the
	# outer variable at its initial value and every row was an ALIAS of that one
	# list. A matrix built the ordinary way had identical rows and a matrix
	# multiply over it returned plausible wrong numbers. .expected is CPython's.
	./$(COMPILER) test/test_nilpy_nested_comprehension_over_range.npy /tmp/test_nilpy_nestcomp26
	/tmp/test_nilpy_nestcomp26 | diff -u test/test_nilpy_nested_comprehension_over_range.expected -
	# `d[k] += 1` where the BASE is a variant (a nested container, or a local
	# bound from one): the variant subscript route only handled a plain `=`, so
	# an augmented token fell through to the getter and the store was never
	# built — silently. The statically-typed base took a different path and was
	# already correct, which is what hid it. .expected is CPython's.
	./$(COMPILER) test/test_nilpy_augmented_subscript_variant_base.npy /tmp/test_nilpy_augsubvar26
	/tmp/test_nilpy_augsubvar26 | diff -u test/test_nilpy_augmented_subscript_variant_base.expected -
	# A hoisting sub-expression (a string method call) in a `while` condition was
	# flushed OUTSIDE the loop and evaluated once, so the condition went stale;
	# folding it into the whole condition instead broke `and`'s short circuit.
	# Each operand carries its own setup. .expected is CPython's.
	./$(COMPILER) test/test_nilpy_while_condition_hoist.npy /tmp/test_nilpy_whilehoist26
	/tmp/test_nilpy_whilehoist26 | diff -u test/test_nilpy_while_condition_hoist.expected -
	# A nested def's OWN local was recorded as a capture when a sibling def bound
	# the same name, and a third sibling forward-calling it then failed with
	# "captures op, which is not in scope at this call". .expected is CPython's.
	./$(COMPILER) test/test_nilpy_nested_def_own_local_not_a_capture.npy /tmp/test_nilpy_ndcap26
	/tmp/test_nilpy_ndcap26 | diff -u test/test_nilpy_nested_def_own_local_not_a_capture.expected -
	# list, tuple and set share one representation, so only a KIND stamped at
	# construction tells them apart. isinstance asked a CLASS test and answered
	# True for list AND tuple whatever the value was; a set was not stamped at
	# all and reported type().__name__ == 'list'. .expected is CPython's.
	./$(COMPILER) test/test_nilpy_container_kind_tag.npy /tmp/test_nilpy_ckt26
	/tmp/test_nilpy_ckt26 | diff -u test/test_nilpy_container_kind_tag.expected -
	# `for i in range(4): body` on one line — the range and zip forms hand-rolled
	# newline+indent+block, so `for` was the only compound statement demanding an
	# indent. .expected is CPython's.
	./$(COMPILER) test/test_nilpy_for_inline_suite.npy /tmp/test_nilpy_fis26
	/tmp/test_nilpy_fis26 | diff -u test/test_nilpy_for_inline_suite.expected -
	# repr() and range() as an ITERABLE: both existed in the runtime but were not
	# reachable from where a program uses them — repr's name was bound to nothing,
	# and range materialised only inside a literal `list(`. .expected is CPython's.
	./$(COMPILER) test/test_nilpy_repr_and_range_consumers.npy /tmp/test_nilpy_reprrange26
	/tmp/test_nilpy_reprrange26 | diff -u test/test_nilpy_repr_and_range_consumers.expected -
	# A method with REQUIRED parameters called with EMPTY parens must diagnose, not
	# crash: the empty-parens shortcut used to skip the arity loop outright, so the
	# callee read an uninitialised frame. Negative case first, then every shape the
	# guard could have broken.
	@./$(COMPILER) test/test_nilpy_method_arity_missing_args_fails.npy /tmp/test_nilpy_arity_fail26 2>&1 \
	  | grep -q 'm() requires 1 argument' \
	  || { echo 'test_nilpy_method_arity_missing_args_fails: FAIL - expected a compile error naming the method'; exit 1; }
	./$(COMPILER) test/test_nilpy_method_arity_ok.npy /tmp/test_nilpy_arity_ok26
	/tmp/test_nilpy_arity_ok26 | diff -u test/test_nilpy_method_arity_ok.expected -
	# Mutating a dict while iterating it is NOT DETECTED — a DELIBERATE divergence
	# (devdocs/dev/nilpy-semantics-divergences.md). These expectations are
	# deliberately NOT CPython's: every program in that file is one CPython rejects,
	# which is why the divergence is acceptable. Do NOT make this match python3.
	./$(COMPILER) test/test_nilpy_dict_mutation_during_iteration.npy /tmp/test_nilpy_dictmut26
	/tmp/test_nilpy_dictmut26 | diff -u test/test_nilpy_dict_mutation_during_iteration.expected -
	# print() converted a container argument to TEXT as it evaluated it, so
	# `print(zs, zs.pop(), zs)` showed the list before AND after the pop. The
	# arguments were already hoisted into temps; the conversions just ran BEFORE
	# the hoist, so the TEXT got hoisted. See the test's header.
	./$(COMPILER) test/test_nilpy_print_container_arg_freshness.npy /tmp/test_nilpy_pargord26
	/tmp/test_nilpy_pargord26 | diff -u test/test_nilpy_print_container_arg_freshness.expected -
	# Subscripting a SEQUENCE with an object that declares no __index__ raised
	# IndexError (the instance HANDLE used as a position) instead of TypeError; a
	# DICT must still accept an object KEY. Three subscript paths needed it. See
	# the test's header.
	./$(COMPILER) test/test_nilpy_index_dunder_typeerror.npy /tmp/test_nilpy_idxdun26
	test "$$(/tmp/test_nilpy_idxdun26)" = "$$(printf '%b' 'obj-key-ok\n20 c 120\nlist TypeError\nstr TypeError\nbytes TypeError\n20 b 121')"
	# list.append/extend/sort/reverse returned SELF, so `x = l.sort()` yielded the
	# list where Python yields None — silent, and in the direction where NilPy
	# looks correct and CPython breaks. The list-LITERAL desugar keeps a Self
	# result under the separate name append_self. See the test's header.
	./$(COMPILER) test/test_nilpy_list_mutators_return_none.npy /tmp/test_nilpy_lmut26
	/tmp/test_nilpy_lmut26 | diff -u test/test_nilpy_list_mutators_return_none.expected -
	# Chained assignment (`a = b = 5`, ONE evaluation of the RHS) and `**=` (its
	# own token, desugared through the same PyMakePow so the __pow__ dunders still
	# dispatch, and widening because 2 ** -1 is a float). See the test's header.
	./$(COMPILER) test/test_nilpy_chained_assign_powassign.npy /tmp/test_nilpy_chpow26
	test "$$(/tmp/test_nilpy_chpow26)" = "$$(printf '%b' '5 5\nhi hi hi\n7 7 1\n6\n[1, 2, 3] [1, 2, 3]\n2 2\n8\n0.5\n2.0\n0.5 2.0\n4')"
	# A SECOND for-clause in one comprehension — the flatten idiom — failed with
	# "undefined variable (c)". The clauses nest left to right (a recursion), AND
	# the loop variable's rename had to cover the whole remainder, because the next
	# clause's ITERABLE names the previous clause's variable. See the test header.
	./$(COMPILER) test/test_nilpy_comprehension_two_for.npy /tmp/test_nilpy_c2for26
	/tmp/test_nilpy_c2for26 | diff -u test/test_nilpy_comprehension_two_for.expected -
	# bytearray() had only () and (Integer) overloads, so no bytes could be put in
	# one at construction. bytearray(bytes) is a COPY not an alias, and an element
	# outside 0..255 raises ValueError rather than truncating. See the test header.
	./$(COMPILER) test/test_nilpy_bytearray_ctor.npy /tmp/test_nilpy_bactor26
	test "$$(/tmp/test_nilpy_bactor26)" = "$$(printf '%b' '3 97 98 99\n122\n120 65\n3 1 3\n0\n3 0\n0\nValueError')"
	# Two methods of one class could not both declare a nested def of the SAME
	# name: the method body pre-pass ran BEFORE the nest prefix was set, so every
	# method's nested def registered under its bare name. A plain def already set
	# its prefix first — which is why two plain functions never collided.
	./$(COMPILER) test/test_nilpy_nested_def_name_per_method.npy /tmp/test_nilpy_ndpm26
	test "$$(/tmp/test_nilpy_ndpm26)" = "$$(printf '%b' '11 99 20 15\n11 99')"
	# A nested def in a METHOD reading self.<field> inferred its RETURN TYPE from
	# the RECEIVER, not the field, so the caller read the field slot as an object
	# pointer and printed an empty line. PyInferExprType's receiver branch required
	# a '(' and so only ever handled obj.method(...). See the test's header.
	./$(COMPILER) test/test_nilpy_nested_def_self_field.npy /tmp/test_nilpy_nselffld26
	test "$$(/tmp/test_nilpy_nselffld26)" = "$$(printf '%b' '17 7 17 17\n17 hi 17\n3 6')"
	# A lambda could not call a SIBLING NESTED def — the lifted body is compiled
	# after the enclosing def's epilogue, when PyNestPrefix has been popped, so the
	# name could not be qualified. Not a capture problem: a non-capturing sibling
	# failed identically. See the test's header.
	./$(COMPILER) test/test_nilpy_lambda_sibling_def.npy /tmp/test_nilpy_lamsib26
	test "$$(/tmp/test_nilpy_lamsib26)" = "$$(printf '%b' '11 15 16 11\n11 6 11\n11')"
	# The stdlib shim table builds a call by NAME (FindProc), which never consults
	# overloads — so adding an overload for a case it got wrong did NOTHING,
	# silently. The call site now re-targets by ARITY. See the test's header.
	./$(COMPILER) test/test_nilpy_stdlib_shim_arity.npy /tmp/test_nilpy_shimarity26
	test "$$(/tmp/test_nilpy_shimarity26)" = "$$(printf '%b' 'a/b\na/b/c\na/b/c/d\n/x/y/z\na/c\ndflt')"
	# A keyword argument must steer overload SELECTION. The same-unit half landed
	# 2026-08-01; the CROSS-UNIT case is how one Python builtin is normally split —
	# key= needs PyCallKey1, which lives in pyeval, while min resolves from pylib.
	# .expected file rather than an inline printf: the output contains quotes.
	./$(COMPILER) test/test_nilpy_kwarg_overload.npy /tmp/test_nilpy_kwovl26
	/tmp/test_nilpy_kwovl26 | diff -u test/test_nilpy_kwarg_overload.expected -
	# list(range(...)) and str.expandtabs(). NilPy's range is not a value, it is the counted-loop
	# lowering in a for header, so list(range(3)) did not compile. Materialised
	# ONLY inside list( — a general range value would make print(range(3)) print a
	# list where CPython prints range(0, 3). See the test's header.
	./$(COMPILER) test/test_nilpy_range_into_list.npy /tmp/test_nilpy_rangelist26
	test "$$(/tmp/test_nilpy_rangelist26)" = "$$(printf '%b' '[0, 1, 2]\n[1, 2, 3]\n[0, 3, 6, 9]\n[3, 2, 1]\n[]\n[]\n[-3, -1, 1]\n[0, 1, 2, 3]\n[0, 1, 2]\n10\n[0, 1, 9]\nValueError\na   b a       b     \nab  c abcd    e a b c\na\nb   c\na b ab no tabs\n9')"
	# pow(base, exp, mod): modular exponentiation, incl. the sign-of-the-modulus
	# rule, the negative-exponent modular inverse, and doubling-based products so a
	# 2^62 modulus does not overflow Int64. See the test's header.
	./$(COMPILER) test/test_nilpy_pow_mod.npy /tmp/test_nilpy_powmod26
	test "$$(/tmp/test_nilpy_powmod26)" = "$$(printf '%b' '24 1024 1 0\n8 -2 2 -3\n560583526\n1 0\n3 5 11\n281250002\nValueError-zero-mod\nValueError-not-invertible\n1,234,567\nbd [2, 4] ace fedcba')"
	# Python has no overloading: a module-level `def sorted(x)` REPLACES the
	# builtin. A user def merely joined the overload set and lost on ARGUMENT FIT,
	# so the program silently printed the builtin's answer. See the test's header;
	# expectations are CPython's.
	./$(COMPILER) test/test_nilpy_user_def_shadows_builtin.npy /tmp/test_nilpy_defshadow26
	test "$$(/tmp/test_nilpy_defshadow26)" = "$$(printf '%b' 'mine-sorted mine-counter\nmine-len mine-len mine-len mine-len\nmine-len\nmine-abs mine-str mine-min mine-max\nmine-sum mine-int mine-list mine-round\nmine-divmod mine-hex mine-reversed mine-enumerate\nmine-float mine-bool mine-bool')"
	# A Python annotation is metadata, not enforcement: `-> int` returning 2.5 gave
	# 4612811918334230528 (the double's IEEE bits). And a returned EXPRESSION was
	# typed by the smallest operand in it. See the test's header; expectations are
	# CPython's.
	./$(COMPILER) test/test_nilpy_def_return_type.npy /tmp/test_nilpy_defret26
	test "$$(/tmp/test_nilpy_defret26)" = "$$(printf '%b' '2.5 1 2.5 0.5\n1.5 2.5 1.5 1.5\n0.25 1.5 7 6\nlate')"
	# A field initialised from a small int LITERAL was 4 bytes wide and wrapped at
	# 2^31, while the `int` ANNOTATION gave 8 — PyTypeFromTokenIndex disagreeing
	# with itself. See the test's own header; expectations are CPython's.
	./$(COMPILER) test/test_nilpy_int_field_width.npy /tmp/test_nilpy_intfld26
	test "$$(/tmp/test_nilpy_intfld26)" = "$$(printf '%b' '1073741824\n2147483648\n4294967296\n1099511627776\n4611686018427387904\n-4294967296\n4294967296')"
	# %r is repr(), not str(): the conversion switch lumped 's' and 'r' together,
	# so "%r" % "v" printed v instead of 'v'. Only string operands diverged.
	./$(COMPILER) test/test_nilpy_percent_repr.npy /tmp/test_nilpy_pctrepr26
	test "$$(/tmp/test_nilpy_pctrepr26)" = "$$(printf '%b' '\047v\047\nv\n5\n2.5\n[1, 2]\n{\047k\047: 1}\nk=\047v\047\n\047a\047 and \047b\047\n[    \047ab\047]\n[\047ab\047    ]\nTrue\nx y\n42 03.14 ff\n"it\047s"\n"it\047s"\n\047say "hi"\047\n\047both \\\047 and "\047\n\047plain\047\n["it\047s", \047say "hi"\047]\n\047tab\\there\047')"
	# str.format must honour EXPLICIT positional indices: the field was thrown
	# away and arguments substituted sequentially, so "{1}{0}" printed in the
	# wrong order. Only reordering/repeating indices expose it.
	./$(COMPILER) test/test_nilpy_str_format_indices.npy /tmp/test_nilpy_fmtidx26
	test "$$(/tmp/test_nilpy_fmtidx26)" = "$$(printf '%b' 'ba\nab\nab\nx-x\ny-y\n7\n7\n[   ab]\n[   cd]\n{literal} v\n3.14 and 2.7')"
	# bool(x) is Python truthiness and must consult __bool__/__len__, agreeing
	# with `if x:` and `not x` — it had no NilPy arm and never reached them
	./$(COMPILER) test/test_nilpy_bool_protocol.npy /tmp/test_nilpy_boolproto26
	test "$$(/tmp/test_nilpy_boolproto26)" = "$$(printf '%b' 'False False True True\nTrue True False False\nif-bf: falsy\nif-l3: truthy\nif-np: truthy\nFalse True True False True\nFalse True False True False True\nTrue False\nFalse\nFalse True\nFalse False False True True\nFalse\nTrue')"
	# mixed-type operands must raise TypeError even when BOTH types are known at
	# compile time: the guard lives in the runtime pyvar_* helpers, which a
	# fully-static binop never reaches, so `3 - [1,2]` did pointer math. Operands
	# here are DIRECT literals, never unpacked from a container — that is what
	# test_nilpy_mixed_type_operands could not reach.
	./$(COMPILER) test/test_nilpy_static_mixed_type_guard.npy /tmp/test_nilpy_statguard26
	test "$$(/tmp/test_nilpy_statguard26)" = "$$(printf '%b' 'int-list  TypeError\nint/list  TypeError\nint//list TypeError\nint%list  TypeError\nint<list  TypeError\nint>=list TypeError\nstr-list  TypeError\nstr<int   TypeError\nlist//int TypeError\nlist%int  TypeError\nstr-str  TypeError\nstr/str  TypeError\nstr//str TypeError\n[1, 3]\n[1, 2, 1, 2] abab\n5 ok\n5 3.5 3 1\n2.5 2 True\nTrue True True\n[1, 2] ab\nTrue')"
	# ordering two statically-typed sequences must compare CONTENTS: the static
	# binop path lowered to a raw handle compare and answered from HEAP
	# ADDRESSES. Every case is written so allocation order DISAGREES with
	# content order, which a coincidental test cannot catch.
	./$(COMPILER) test/test_nilpy_sequence_ordering.npy /tmp/test_nilpy_seqord26
	test "$$(/tmp/test_nilpy_seqord26)" = "$$(printf '%b' 'False\nTrue\nFalse\nTrue\nFalse True False True True\nTrue\nFalse\nTrue\nFalse True\nFalse True\nTrue\nFalse\nTrue True\nFalse True')"
	# Pascal TYPED constants (`const N: T = v`) must hold their value under a
	# NilPy main: CompilePendingGlobalInits was called by ParseProgram and by the
	# C frontend's main, but never by the NilPy driver, so every typed constant
	# in every used unit silently read as zero. The reportlab units shim is the
	# real-world exposure (every measurement became 0.0).
	./$(COMPILER) test/test_nilpy_typed_const_import.npy /tmp/test_nilpy_typedconst26
	test "$$(/tmp/test_nilpy_typedconst26)" = "$$(printf '%b' '72.0\n2.834645669291339\n28.346456692913385\nTrue\nTrue\nTrue\nTrue')"
	# a name bound as a LOCAL inside a def (assignment or for-target, nested
	# blocks included) must not widen or pre-create the same-named MODULE
	# global; `global nm` takes that back; and a def that only READS a global
	# assigned further down must still resolve
	./$(COMPILER) test/test_nilpy_def_local_shadows_module_global.npy /tmp/test_nilpy_deflocal26
	test "$$(/tmp/test_nilpy_deflocal26)" = "$$(printf '%b' 'hello\n1\nADD2\nfor-done\n11\nnested\n21\nwritten\nread-ok\nctrl-ok')"
	# a module global whose name is also a PARAMETER of a def above it: the
	# parameter shadows it, so the def's body must not force the global into
	# existence as a bare variant and kill its class identity (and with it every
	# compile-time dunder dispatch); expectation is CPython's own output
	./$(COMPILER) test/test_nilpy_global_shadowed_by_param.npy /tmp/test_nilpy_gshadow26
	test "$$(/tmp/test_nilpy_gshadow26)" = "$$(printf '%b' '1\nADD2\nADD1\nFalse\nTrue\n10\nADD2\nADD2\n8\n7')"
	# unary minus dunder (__neg__) on a user class; expectation is CPython's own output
	./$(COMPILER) test/test_nilpy_neg_dunder.npy /tmp/test_nilpy_negdunder26
	test "$$(/tmp/test_nilpy_negdunder26)" = "$$(printf '%b' 'Neg(-5)\nNeg(3)\n-5\n-6\n-4')"
	# cpyext M1 "hello-ext" — BLOCKED on
	# The module source is platonically named ./hello_ext.c, the same basename as
	# the unit — which used to drop it silently
	# (bug-c-uses-path-basename-collides-with-enclosing-unit-name). Skipped until
	# that landed rather than renamed around; unskipped now that it has.
	./$(COMPILER) -Futest/nilpy_units -Ilib/cpyext/include test/test_cpyext_hello.npy /tmp/test_cpyext_hello26
	test "$$(/tmp/test_cpyext_hello26)" = "42"
	# cpyext M2 "arguments and errors": PyArg_ParseTuple/Py_BuildValue over
	# "i l d s s# O", PyErr_SetString propagating into a NilPy `except`
	./$(COMPILER) -Futest/nilpy_units -Ilib/cpyext/include test/test_cpyext_args_errors.npy /tmp/test_cpyext_args_errors26
	test "$$(/tmp/test_cpyext_args_errors26)" = "$$(printf '9.0\nHELLO\n6\n99\n5\ncaught: x must be non-negative')"
	# cpyext M3 "strings and containers": PyList_*/PyDict_* construction +
	# iteration (PyDict_Next), Unicode/bytes round-trip via PyBytes_* distinct
	# from PyUnicode_*
	./$(COMPILER) -Futest/nilpy_units -Ilib/cpyext/include test/test_cpyext_containers.npy /tmp/test_cpyext_containers26
	test "$$(/tmp/test_cpyext_containers26)" = "$$(printf '10\n2,3,1\nb:1,a:3,n:2\n5:hello')"
	# cpyext M4 "a real extension from PyPI": MarkupSafe 3.0.3's real,
	# unmodified _speedups.c (test/nilpy_units/vendor/), verified against the
	# SAME extension's own output under real CPython, not a hand-typed guess
	./$(COMPILER) -Futest/nilpy_units -Ilib/cpyext/include test/test_cpyext_markupsafe.npy /tmp/test_cpyext_markupsafe26
	test "$$(/tmp/test_cpyext_markupsafe26)" = "$$(printf '&lt;b&gt;hi &amp; &#34;bye&#34; &#39;all&#39;&lt;/b&gt;\nplain text, no specials')"
	# cpyext M5 "a Cython-generated module": Cython 3.2.9's unmodified output
	# for test/nilpy_units/vendor/cyadd.pyx (8224 lines from 11), compiled by
	# cfront. Proves real PEP 489 init (Py_mod_create/Py_mod_exec are EXECUTED),
	# module-dict function objects rather than a static PyMethodDef table, and
	# METH_FASTCALL. Both -D flags are load-bearing — see that vendor README.
	# M5b dropped `-X binding=False` at GENERATION time, so those functions are
	# now instances of Cython's CyFunction HEAP TYPE. The last five lines are the
	# only ones that can tell that apart from a plain builtin function; every
	# number above them reads the same either way.
	# PyErr_Format / PyUnicode_FromFormat take a printf SUPERSET (%U %S %R %A).
	# vsnprintf knows none of them and consumed NO argument for them, so anything
	# after one read the wrong va_arg. Each line is what the same calls print
	# under real CPython 3.12.
	./$(COMPILER) -Futest/nilpy_units -Ilib/cpyext/include test/test_cpyext_errformat.npy /tmp/test_cpyext_errformat26
	# The literal quote and percent characters travel as printf ARGUMENTS, not as
	# escapes in the format: make expands %% to % before running a recipe, but
	# testmgr extracts this line and runs it directly, so a %%-escape means two
	# different things in the two paths. Same family as the absolute-/tmp-path trap
	# in devdocs/dev/gating-and-waiting.md.
	test "$$(/tmp/test_cpyext_errformat26)" = "$$(printf 'U=[keyname]\nS=[1234]\nR=[%s]\nA=[%s]\nmix=[keyname][77]\ns=[txt] d=[-5]\nld=[9876543210] zd=[42]\npct=[100%s] c=[Z]\nx=[ff] wide=[    7]\nfmt=[keyname][5]' "'keyname'" "'keyname'" "%")"
	./$(COMPILER) -DPy_LIMITED_API=0x030c0000 -DCYTHON_COMPRESS_STRINGS=0 -Futest/nilpy_units -Ilib/cpyext/include test/test_cpyext_cython.npy /tmp/test_cpyext_cython26
	test "$$(/tmp/test_cpyext_cython26)" = "$$(printf '42\n0\n3000000\n1\n720\n3628800\n479001600\n22\n22\n22\n22\n42\nbadkw raised\ncython_function_or_method\ncyadd\ncysub\na,b\nn,i,r')"
	# A str-method NAME a user class also declares (find/index/count/title/strip/
	# split/replace/upper/startswith/format/ljust) dispatches on the receiver's
	# RUNTIME tag, not on a hardcoded name list. Both receivers travel through the
	# same dynamically typed loop variable, so a compile-time choice is wrong for
	# one of them whichever way it is made.
	./$(COMPILER) test/test_nilpy_str_method_name_collides_with_class_method.npy /tmp/test_nilpy_strcoll26
	/tmp/test_nilpy_strcoll26 | diff -u test/test_nilpy_str_method_name_collides_with_class_method.expected -
	# __exit__ runs on EVERY way out of a `with` body — return, break, continue,
	# fall-through and the exception path. The finally body must be a STATEMENT;
	# as a bare call expression it was pruned as an unused value on every arm but
	# the exception one, which is why only that arm ever measured correct.
	./$(COMPILER) test/test_nilpy_with_early_exit_runs_exit.npy /tmp/test_nilpy_withexit26
	/tmp/test_nilpy_withexit26 | diff -u test/test_nilpy_with_early_exit_runs_exit.expected -
	# A VARIANT argument binding a CLASS parameter is unwrapped TAG-CHECKED:
	# tuple/sorted/bytes/reversed/sum over a variant holding a string used to
	# segfault. Both payload kinds are swept because the list payload was always
	# correct, so testing only that would have shown nothing.
	./$(COMPILER) test/test_nilpy_builtin_over_variant_receiver.npy /tmp/test_nilpy_bvrecv26
	/tmp/test_nilpy_bvrecv26 | diff -u test/test_nilpy_builtin_over_variant_receiver.expected -

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
	# PXX_THREADSAFE is set by --threadsafe and only by it. Both spellings are
	# asserted: with only the ON case, a define set unconditionally would pass.
	./$(COMPILER) test/threadsafe_define.pas /tmp/test_tsdefine_off26
	test "$$(/tmp/test_tsdefine_off26)" = "plain"
	./$(COMPILER) --threadsafe test/threadsafe_define.pas /tmp/test_tsdefine_on26
	test "$$(/tmp/test_tsdefine_on26)" = "threadsafe"
	# ...and the per-target heap-lock defines. PXX_TS_HARDLOCK was dead on every
	# build (set below an early Exit that x86-64 always took), so x86-64
	# --threadsafe ran the allocator-racing finalization path the define exists
	# to prevent. bug-a-x86-64-early-exit-skips-target-defines
	./$(COMPILER) test/threadsafe_lockdefine.pas /tmp/test_tslock_off26
	test "$$(/tmp/test_tslock_off26)" = "$$(printf 'no-hardlock\nno-softlock')"
	./$(COMPILER) --threadsafe test/threadsafe_lockdefine.pas /tmp/test_tslock_on26
	test "$$(/tmp/test_tslock_on26)" = "$$(printf 'hardlock\nno-softlock')"
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
	@# --threadsafe + -dPXX_HEAP_DEBUG together used to HANG (self-deadlock on the
	@# heap spinlock: PXXFree runs inside the emitted locked region and its
	@# PXXDbgFlush had a managed local whose finalize re-took the same lock).
	@# All three builds must agree, so a fix cannot pass by disabling either mode.
	./$(COMPILER) --threadsafe test/test_threadsafe_heap_debug_combo.pas /tmp/test_tshd_ts26
	test "$$(/tmp/test_tshd_ts26)" = "$$(printf '110 110\n110 survivor-ok\nblockx churn-ok')"
	./$(COMPILER) -dPXX_HEAP_DEBUG test/test_threadsafe_heap_debug_combo.pas /tmp/test_tshd_hd26
	test "$$(/tmp/test_tshd_hd26)" = "$$(printf '110 110\n110 survivor-ok\nblockx churn-ok')"
	./$(COMPILER) --threadsafe -dPXX_HEAP_DEBUG test/test_threadsafe_heap_debug_combo.pas /tmp/test_tshd_both26
	test "$$(/tmp/test_tshd_both26)" = "$$(printf '110 110\n110 survivor-ok\nblockx churn-ok')"
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
	# data-parallel loop runtime (palparallel PXXParallelFor): exact partition (each index once), values, edge ranges. worker count is host-dependent, so gate on the deterministic tail.
	./$(COMPILER) --threadsafe test/test_parallel_for.pas /tmp/test_parallel_for26
	test "$$(/tmp/test_parallel_for26 | tail -n 4)" = "$$(printf 'visitErr=0\nvalErr=0\nedgeErr=0\nPARALLELFOR OK')"
	# `parallel for` LANGUAGE surface: parse-time worker synthesis + PXXParallelFor dispatch (exact partition, values)
	./$(COMPILER) --threadsafe test/test_parallel_for_lang.pas /tmp/test_parallel_for_lang26
	test "$$(/tmp/test_parallel_for_lang26)" = "$$(printf 'visitErr=0\nvalErr=0\nPARFORLANG OK')"
	# `parallel for` without --threadsafe = clear compile error, not a heisencrash
	! ./$(COMPILER) test/test_parallel_for_lang.pas /tmp/test_parallel_for_guard26 > /tmp/test_parallel_for_guard.log 2>&1
	grep -q "requires --threadsafe" /tmp/test_parallel_for_guard.log
	# `parallel for` scalar capture (Phase A): enclosing scalars by-ref via the frame pointer (read + write-back)
	./$(COMPILER) --threadsafe test/test_parallel_for_capture.pas /tmp/test_parallel_for_capture26
	test "$$(/tmp/test_parallel_for_capture26)" = "$$(printf 'readErr=0\ntotal=4950\nPARFORCAP OK')"
	# `parallel for` named-type aggregate capture (B-1): local fixed array + dyn array + record by-ref via the frame pointer
	./$(COMPILER) --threadsafe test/test_parallel_for_capture_aggr.pas /tmp/test_parallel_for_capture_aggr26
	test "$$(/tmp/test_parallel_for_capture_aggr26 | tail -n 1)" = "PARFORAGGR OK"
	# `parallel for` ansistring capture: Length + char-index + compare of a captured string (needs the p^[k] fix)
	./$(COMPILER) --threadsafe test/test_parallel_for_capture_string.pas /tmp/test_parallel_for_capture_string26
	test "$$(/tmp/test_parallel_for_capture_string26 | tail -n 1)" = "PARFORSTR OK"
	./$(COMPILER) --threadsafe test/test_parallel_for_capture_callee.pas /tmp/test_parallel_for_capture_callee26
	test "$$(/tmp/test_parallel_for_capture_callee26 | tail -n 1)" = "PARFORCALLEE OK"
	./$(COMPILER) --threadsafe test/test_parallel_for_capture_scalar_types.pas /tmp/test_parallel_for_capture_scalar_types26
	test "$$(/tmp/test_parallel_for_capture_scalar_types26 | tail -n 1)" = "PARFORSCALARTYPES OK"
	# async (per-thread coroutine scheduler) composes with parallel (OS threads): each worker runs its own reactor
	./$(COMPILER) --threadsafe test/test_async_parallel_compat.pas /tmp/test_async_parallel_compat26
	test "$$(/tmp/test_async_parallel_compat26 | tail -n 1)" = "ASYNC x PARALLEL OK"
	# __pxxmulhi_u64: unsigned 64x64->128 high half (x86-64 mul / aarch64 umulh)
	./$(COMPILER) test/test_mulhi.pas /tmp/test_mulhi26
	test "$$(/tmp/test_mulhi26 | tail -1)" = "MULHI OK"
	# whole-array assign to a var param (copy sized from the open-array
	# placeholder -> 1000-element overrun) + N-D whole-array assign
	./$(COMPILER) test/test_array_var_param_assign.pas /tmp/test_avpa26
	test "$$(/tmp/test_avpa26 | tail -1)" = "ARRAY VAR PARAM ASSIGN OK"
	# an OPEN ARRAY value param gets its own COPY (FPC's rule): the callee's
	# x[0] := n was visible to the caller. Every row diffed against FPC,
	# including the ones that already agreed -- var open arrays and named
	# dyn-array value params must keep aliasing.
	./$(COMPILER) test/test_open_array_value_param_copies.pas /tmp/test_oavp26
	test "$$(/tmp/test_oavp26 | tail -1)" = "OPEN ARRAY VALUE PARAM OK"
	test "$$(/tmp/test_oavp26 | head -2 | tail -1)" = "open by value      : 1"
	# function RESULTS of the aggregate kinds. A set-returning function used to
	# answer the EMPTY set on every target, and a fixed-array one element 0 and
	# zeros -- both silent. Every row diffed against FPC.
	./$(COMPILER) test/test_aggregate_function_results.pas /tmp/test_aggret26
	test "$$(/tmp/test_aggret26 | tail -1)" = "AGGREGATE FUNCTION RESULTS OK"
	test "$$(/tmp/test_aggret26 | head -1)" = "set lit   TRUE TRUE FALSE"
	test "$$(/tmp/test_aggret26 | head -7 | tail -1)" = "arr       8 9 10"
	# a fixed-array call result as a `const` / by-value array ARGUMENT (the last
	# aggregate that still demanded an lvalue); a `var` one is still refused
	test "$$(/tmp/test_aggret26 | tail -2 | head -1)" = "arr as arg 27 19 54"
	# ...and the Result SLOT, which was one element wide with no dim spans:
	# array[0..3] overran into the return address, an N-D result indexed with
	# no strides, and a non-Integer element got an Integer stride.
	test "$$(/tmp/test_aggret26 | head -9 | tail -1)" = "arr4      1 2 3 4"
	test "$$(/tmp/test_aggret26 | head -10 | tail -1)" = "arr 2d    1 2 3 4"
	test "$$(/tmp/test_aggret26 | head -11 | tail -1)" = "arr 3d    105 106 115 116 125 126 205 206 215 216 225 226"
	test "$$(/tmp/test_aggret26 | head -12 | tail -1)" = "arr str   aa bb cc"
	test "$$(/tmp/test_aggret26 | head -13 | tail -1)" = "arr rec   1 2 3 4"
	# indexing the CALL directly and then selecting a field: ResolveNodeRec had
	# a case for every AN_INDEX base kind except a CALL, so the selector was
	# applied at offset 0 and every field answered the first one.
	./$(COMPILER) test/test_index_call_result_field.pas /tmp/test_idxcall26
	test "$$(/tmp/test_idxcall26 | tail -1)" = "INDEX CALL RESULT FIELD OK"
	test "$$(/tmp/test_idxcall26 | head -2 | tail -1)" = "on call   1 2 3 4 5 6"
	# a string[N] field in a record's VARIANT part: the variant-part builder had
	# no frozen-string arm, so the field was 8 bytes (undersizing the record) and
	# typed tyFixedString instead of tyString+UFldStrCap (so it read as an
	# address). Every other branch type was already right.
	./$(COMPILER) test/test_variant_part_string_field.pas /tmp/test_vpstr26
	test "$$(/tmp/test_vpstr26 | tail -1)" = "VARIANT PART STRING FIELD OK"
	test "$$(/tmp/test_vpstr26 | head -1)" = "scalar  1 aa 2"
	test "$$(/tmp/test_vpstr26 | head -5 | tail -1)" = "trunc   abcdef 6"
	test "$$(/tmp/test_vpstr26 | head -7 | tail -1)" = "no ovr  22 abcdef"
	# write(c:width) on a Char: x86-64 was the ONLY backend that dropped the
	# field width (the four cross targets and FPC all pad), so the default
	# target silently produced ragged columns.
	./$(COMPILER) test/test_write_char_field_width.pas /tmp/test_wcw26
	test "$$(/tmp/test_wcw26 | tail -1)" = "WRITE CHAR FIELD WIDTH OK"
	test "$$(/tmp/test_wcw26 | head -3 | tail -1)" = "[    q]"
	test "$$(/tmp/test_wcw26 | head -6 | tail -1)" = "[q][q]"
	test "$$(/tmp/test_wcw26 | head -8 | tail -1)" = "   x   y"
	# ...and the VARIABLE-width rows, in a program with NO uses clause
	test "$$(/tmp/test_wcw26 | head -11 | tail -3 | tr '\n' '|')" = "[   ab]|[    q]|[ TRUE]|"
	test "$$(/tmp/test_wcw26 | head -14 | tail -3 | tr '\n' '|')" = "[    5]|[ 3.50]|[ab][  abc]|"
	# a metaclass-typed FIELD as a receiver. The parser recognises a metaclass
	# receiver from a LIST of base node kinds (variable, cast, array element --
	# the last added at b328 for this same bug) and a FIELD was never in it.
	./$(COMPILER) test/test_metaclass_field_receiver.pas /tmp/test_mcfld26
	test "$$(/tmp/test_mcfld26 | tail -1)" = "METACLASS FIELD RECEIVER OK"
	test "$$(/tmp/test_mcfld26 | head -4 | tail -1)" = "named   der TDer 7"
	test "$$(/tmp/test_mcfld26 | head -7 | tail -1)" = "classfld der"
	test "$$(/tmp/test_mcfld26 | head -8 | tail -1)" = "ctor    B|BD"
	# ...and the fifth spelling, a metaclass returned from a FUNCTION: it never
	# reached that list at all (the call-result suffix walker owns it), so
	# `Give.Kind` lowered to IR_UNSUPPORTED. All five now share NodeMetaclassCi.
	./$(COMPILER) test/test_metaclass_call_receiver.pas /tmp/test_mccall26
	test "$$(/tmp/test_mccall26 | tail -1)" = "METACLASS CALL RECEIVER OK"
	test "$$(/tmp/test_mccall26 | head -3 | tail -1)" = "call    der TDer"
	test "$$(/tmp/test_mccall26 | head -5 | tail -1)" = "args    base der"
	test "$$(/tmp/test_mccall26 | head -6 | tail -1)" = "ctor    BDB"
	# record operator overloads with MIXED operand types. The in-record
	# signature skip was depth-blind and stopped at the ';' separating parameter
	# groups; and once it parsed, the operator table turned out to be keyed on
	# the LEFT operand alone, so TVec+TVec and TVec+Integer collided silently.
	./$(COMPILER) test/test_op_overload_mixed_operands.pas /tmp/test_opmix26
	test "$$(/tmp/test_opmix26 | tail -1)" = "OP OVERLOAD MIXED OPERANDS OK"
	test "$$(/tmp/test_opmix26 | head -3 | tail -1)" = "mul   (3,6)"
	test "$$(/tmp/test_opmix26 | head -11 | tail -1)" = "pick  (4,6) (3,6)"
	# a by-value SET or string[N] param gets its own COPY too -- the callee's
	# `s := s + [7]` / `s := 'changed'` wrote through to the CALLER on x86-64,
	# aarch64 and arm32 (riscv32 already matched FPC). Every row diffed
	# against FPC, including var write-back and the const escape hatch.
	./$(COMPILER) test/test_set_shortstring_value_param_copies.pas /tmp/test_ssvp26
	test "$$(/tmp/test_ssvp26 | tail -1)" = "SET SHORTSTRING VALUE PARAM OK"
	test "$$(/tmp/test_ssvp26 | head -1)" = "set value  : ok"
	test "$$(/tmp/test_ssvp26 | head -2 | tail -1)" = "str20 value: orig"
	test "$$(/tmp/test_ssvp26 | head -12 | tail -1)" = "forwarded  : orig"
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
	# statement-atomic writeln from parallel-for WORKERS (read-only lines, no
	# worker heap alloc): every 100-char line must stay whole, all 200 present.
	./$(COMPILER) --threadsafe test/test_parallel_writeln_atomic.pas /tmp/test_parallel_writeln_atomic26
	/tmp/test_parallel_writeln_atomic26 > /tmp/pwa26.out
	test "$$(tail -n1 /tmp/pwa26.out)" = "PARWROK"
	test "$$(grep -cE '^A{49}-1[0-9]{3}-B{49}$$' /tmp/pwa26.out)" = "200"
	test "$$(grep -oE '\-1[0-9]{3}\-' /tmp/pwa26.out | sort -u | wc -l)" = "200"
	# policy-aware runtime (feature-parallel-for-scheduling-policy): every
	# distribution (chunked/onDemand/guided + worker-count modes) covers the range
	# exactly once — a broken atomic-counter work-steal would drop/double indices.
	./$(COMPILER) --threadsafe test/test_parallel_policy.pas /tmp/test_parallel_policy26
	test "$$(/tmp/test_parallel_policy26)" = "PARPOL OK"
	# `parallel(P) for` language surface: policy clause lowers to PXXParallelForPP;
	# bare/preset/var-policy all cover exactly once; `parallel` stays a normal ident.
	./$(COMPILER) --threadsafe test/test_parallel_policy_lang.pas /tmp/test_parallel_policy_lang26
	test "$$(/tmp/test_parallel_policy_lang26)" = "PARPOLLANG OK"
	# reduction(op: v): private per-worker partial folded under PXXReduceLock —
	# exact deterministic +/xor results (a race would flake the sum).
	./$(COMPILER) --threadsafe test/test_parallel_reduction.pas /tmp/test_parallel_reduction26
	test "$$(/tmp/test_parallel_reduction26)" = "PARRED OK"
	# parallel(named args) for: bare enum / dist|workers keys / cap|chunk|n ints
	# folded to PXXParallelForN; each form covers exactly once, composes w/ reduction.
	./$(COMPILER) --threadsafe test/test_parallel_policy_named.pas /tmp/test_parallel_policy_named26
	test "$$(/tmp/test_parallel_policy_named26)" = "PARNAMED OK"

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
	# promotable int: arbitrary precision, exact against CPython (feature-a-promotable-int)
	./$(COMPILER) test/test_promoint.pas /tmp/test_promoint26
	test "$$(/tmp/test_promoint26)" = "$$(printf '0\n12\n60\n7\n2\n2\n-5\n25\n7\nlt\ngt\neq\nsame\n265252859812191058636308480000000\n0\n265252859812191058636308480\n109361473\n-15511210043330985984000000\n15511210043330985984000000\n9223372036854775808\n18446744073709551614\n18446744073709551616\n-18446744073709551616\n18446744073709551616\n1\n42\n265252859812191058636308480000000\n265252859812191058636308480000000\n265252859812191058636308480000002\n530505719624382117272616960000000\nvgt\n10\n2\nogt\n1')"
	# ...and it is ARBITRARY PRECISION: 25! is exact, not 25! mod 2^64
	# PromoInt in PASCAL: `shr` (lexed as an IDENT, so PromoOpHelper missed it and
	# the generic path shifted two slot ADDRESSES) and every T(n) value cast
	# (which punned the address). Pointer(n) must stay the slot address.
	# A PromoInt PARAMETER: promo joins the by-ref aggregate class every large
	# record already uses, with the CALLER copying into a hidden temp (PXXPromoCopy,
	# which RETAINS the heap tier's managed payload — a raw 16-byte copy would not).
	# Covers both tiers, mutation not aliasing the caller, and a base conversion
	# written in ordinary Pascal against the type.
	# Low(Int64) with -1: the one pair the inline tier cannot compute — x86 raises
	# SIGFPE because the quotient 2^63 does not fit, and `*` trapped inside its own
	# division-based overflow oracle. Found by a 4770-pair sweep vs a Python oracle.
	# writeln/write/Str of Inf/-Inf/NaN. FIVE formatters normalised into [1,10) with
	# a loop that never terminates on a non-finite value; the x86-64 fixed-form twin
	# did not hang but printed 9223372036854775809.000000. Run under a TIMEOUT — a
	# regression here is a HANG, not a wrong line.
	./$(COMPILER) test/test_writeln_nonfinite_float.pas /tmp/test_writeln_nonfinite26
	test "$$(timeout 20 /tmp/test_writeln_nonfinite26)" = "$$(printf ' Inf\n Inf\n[ Inf]\n Inf\n Inf\n-Inf\n[-Inf]\n-Inf\n Nan\n[ Nan]\n Nan\n 1.0000000000000000E+000\n-2.5000000000000000E+000\n 0.0000000000000000E+000\n 1.0000000000000001E+300\n3.50\n  -0.125')"
	./$(COMPILER) test/test_promoint_minint64_div.pas /tmp/test_promoint_minint26
	test "$$(/tmp/test_promoint_minint26)" = "$$(printf '9223372036854775808\n9223372036854775808\n0\n-9223372036854775808\n0\n-9223372036854775808\n9223372036854775807\n9223372036854775807\n-1180591620717411303424')"
	./$(COMPILER) test/test_promoint_parameter.pas /tmp/test_promoint_param26
	test "$$(/tmp/test_promoint_param26)" = "$$(printf '12 12 24 13\n12\n70000000000 70000000000\n140000000000 140000000000 70000000001\n70000000000\nff\n400000000000000000 0x400000000000000000\n0')"
	./$(COMPILER) test/test_promoint_shr_and_casts.pas /tmp/test_promoint_shrcast26
	test "$$(/tmp/test_promoint_shrcast26)" = "$$(printf '127 127\n15 15\n510\n1180591620717411303424\n1\n32\n12 12 12 12\n12 12 12 12\n12 12\nA\nFALSE\nTRUE\n70000000000\n70000000000')"
	./$(COMPILER) test/test_promoint_overflow.pas /tmp/test_promoint_overflow26
	test "$$(/tmp/test_promoint_overflow26)" = "15511210043330985984000000"
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
	# char-index through a pointer-to-string deref (p^[k]) reads chars, not the handle (bug-pascal-ptr-deref-string-index)
	./$(COMPILER) test/test_ptr_deref_string_index.pas /tmp/test_ptr_deref_string_index26
	test "$$(/tmp/test_ptr_deref_string_index26)" = "PTRSTRIDX OK"
	# method defaults must not shift onto the previous slot (bug-pascal-method-default-param-self-shift)
	./$(COMPILER) test/test_method_default_param_b246.pas /tmp/test_method_default_param_b24626
	test "$$(/tmp/test_method_default_param_b24626)" = "$$(printf 'a=1 b=2\na=9 b=2\na=9 b=8\nx=1 msg=hi n=3 len=2\nx=2 msg=yo n=3 len=2\nx=3 msg=hey n=7 len=3')"
	# `overload` is a real token: class-body directive loop must consume it (bug-pascal-class-body-overload-directive)
	./$(COMPILER) test/test_class_overload_directive_b247.pas /tmp/test_class_overload_directive_b24726
	test "$$(/tmp/test_class_overload_directive_b24726)" = "$$(printf 'name=<none>\nbase ping\ntag=base\nderived ping\ntag=derived')"
	# method + ctor overloads resolve by ARGUMENT TYPE, not first-name-match (bug-pascal-method-overload-ignores-arg-types)
	./$(COMPILER) test/test_method_overload_types_b248.pas /tmp/test_method_overload_types_b24826
	test "$$(/tmp/test_method_overload_types_b24826)" = "$$(printf 'ctor=none\nint 1\nstr xy\nstr x\ntwice-int=42\ntwice-str=abab\nctor=str:zed\nctor=int\nsub-ctor=str:sub\nstr hi\nint 7')"
	# FREE-FUNCTION overloads resolve by CLASS IDENTITY too, not first-arity-match:
	# an unrelated class bound to any class-typed parameter and the callee read one
	# object through another's layout. Descendants must still widen, and a TObject
	# param must still accept anything (bug-a-overload-resolution-ignores-class-identity)
	./$(COMPILER) test/test_overload_class_identity.pas /tmp/test_overload_class_identity26
	test "$$(/tmp/test_overload_class_identity26)" = "$$(printf '1\n2\n1\n9\n9')"
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
	# an interface VALUE is ONE pointer (the instance — FPC's ABI), so it fits a
	# pointer-shaped container and casts back: the fcl-fpcunit listener-list shape
	./$(COMPILER) test/test_interface_single_pointer_abi_b337.pas /tmp/test_intf_1ptr_b33726
	test "$$(/tmp/test_intf_1ptr_b33726)" = "$$(printf 'greet a 1\nsize-is-one-word: TRUE\ngreet a 2\nsame-object: TRUE\ngreet a 3\nfrom slot 0: a\nfrom slot 1: b\nnil-is-nil: TRUE')"
	# libc-free signal HANDLERS with a Pascal callback: hook fires, program
	# RESUMES (SA_RESTORER + rt_sigreturn); no-hook reverts to default and
	# re-raises, so an unhandled SIGTERM still exits 143 killed-by-signal
	./$(COMPILER) -Fulib/rtl test/test_signal_handler_callback_b336.pas /tmp/test_sig_cb_b33626
	test "$$(/tmp/test_sig_cb_b33626)" = "$$(printf 'hits=2\nresumed after handler')"
	./$(COMPILER) -Fulib/rtl test/test_signal_default_revert_b336.pas /tmp/test_sig_dfl_b33626
	/tmp/test_sig_dfl_b33626 >/dev/null 2>&1; test "$$?" = "143"
	# initialised STRING vars, global (kind-1 pending init) and local
	./$(COMPILER) test/test_var_string_initializer_b335.pas /tmp/test_var_strinit_b33526
	test "$$(/tmp/test_var_strinit_b33526)" = "$$(printf 'global/local 42\nmut/local 42')"
	# open-array params in RECORD methods (+ [..] open-array literals to any
	# instance method — were parsed as SET literals)
	./$(COMPILER) test/test_record_method_open_array_b334.pas /tmp/test_rec_openarr_b33426
	test "$$(/tmp/test_rec_openarr_b33426)" = "$$(printf 'sum=106\nlit=130\nspan=14')"
	# record-ctor results as full expressions: operator dispatch sees the lifted
	# temp's record; postfix selectors chain on the factory result
	./$(COMPILER) test/test_record_ctor_expr_tails_b333.pas /tmp/test_rec_ctor_tails_b33326
	test "$$(/tmp/test_rec_ctor_tails_b33326)" = "$$(printf 'sum-op: 11,22\nchain:  15\nboth:   6')"
	# &keyword escaped identifiers, methods NAMED after type keywords
	# (class function Integer(...)), class-of forward references
	./$(COMPILER) test/test_escaped_ident_keyword_methods_b332.pas /tmp/test_esc_kw_b33226
	test "$$(/tmp/test_esc_kw_b33226)" = "$$(printf 'tag=late\nesc=42\nkw=5\nvar=9\noct=511')"
	# record helper for <type> v1: instance methods on plain-typed values,
	# Self = target by reference (generics' ALeft.ToLower shape)
	./$(COMPILER) test/test_record_helper_for_string_b331.pas /tmp/test_rec_helper_b33126
	test "$$(/tmp/test_rec_helper_b33126)" = "$$(printf 'lower:  hello\ndouble: HeLLoHeLLo\nbang:   HeLLo!\nparam: mixed\nsq:     49\nmask:   2147483648\nbits:   32')"
	./$(COMPILER) test/test_type_helper_for_spelling.pas /tmp/test_type_helper_spelling26
	test "$$(/tmp/test_type_helper_spelling26)" = "42 0"
	# FPC {$MACRO ON} text macros ({$define name := body}), RolDWord-family
	# System rotates (builtin soft-alias), Int8/16/32 value-cast names
	./$(COMPILER) test/test_text_macros_rotates_b330.pas /tmp/test_macros_rot_b33026
	test "$$(/tmp/test_macros_rot_b33026)" = "$$(printf 'a=2 b=3\nrol=3\nror=3221225472\nrolq=24\ni8=-1\ni16=-1\ni32=-1')"
	# rtl-generics dialect prereqs: array[Byte], PUInt8-family names, local
	# var-section ordinal initializers, compound-assign statements (+= -= *= /=)
	./$(COMPILER) test/test_dialect_generics_prereqs_b329.pas /tmp/test_generics_prereq_b32926
	test "$$(/tmp/test_generics_prereq_b32926)" = "$$(printf 'span=256\nadler=1572875\ncompound=48\nsecond-call a resets: 1')"
	# a metaclass ARRAY ELEMENT as receiver: Map[0].Tag (virtual class method),
	# Map[0].Create (virtual ctor) — fell to plain-pointer paths, silent garbage
	./$(COMPILER) test/test_metaclass_array_element_b328.pas /tmp/test_mc_elem_b32826
	test "$$(/tmp/test_mc_elem_b32826)" = "$$(printf 'via var:   A\nvia elem0: A\nvia elem1: base\nname:      TA\nmade:      A inst=TA')"
	# an untyped BOOLEAN const keeps tyBoolean (was collapsed to integer; fpjson's
	# Create([S]) with const S=True built a NUMBER element)
	./$(COMPILER) test/test_bool_const_varrec_b326.pas /tmp/test_bool_const_b32626
	test "$$(/tmp/test_bool_const_b32626)" = "$$(printf 'vt=1 b=TRUE\nvt=1 b=FALSE\nvt=0 i=3\nvt=1 b=TRUE\npick=bool')"
	# Str(F,S) no-width = FPC's scientific default ` d.dddE+eee`; explicit widths
	# and writeln floats unchanged (fcl-json compares Str output on both sides)
	./$(COMPILER) test/test_str_float_fpc_default_b327.pas /tmp/test_str_float_b32726
	test "$$(/tmp/test_str_float_b32726)" = "$$(printf '[ 1.2000000000000000E+000]\n[ 0.0000000000000000E+000]\n[-1.5000000000000000E+000]\n[   1.200]\n1.20')"
	# System.X(...) must beat a same-named METHOD of the enclosing class (qUnit=-2
	# is explicit) — fpjson's System.Delete dispatched to TJSONArray.Delete, crash
	./$(COMPILER) test/test_system_qualified_vs_method_b323.pas /tmp/test_sysqual_b32326
	test "$$(/tmp/test_sysqual_b32326)" = "$$(printf 'got=def\nmethod Delete(7)')"
	# an INTEGER argument must not overload-match a Boolean parameter —
	# TJSONArray.Create([1,2,3]) built [true,true,true]
	./$(COMPILER) test/test_overload_no_int_to_boolean_b324.pas /tmp/test_ovl_bool_b32426
	test "$$(/tmp/test_ovl_bool_b32426)" = "$$(printf 'n=int\nw=int\nb=bool\ni=int')"
	# is/as open-world: recognise subclasses from LATER units (runtime RTTI-blob
	# parent walk); bare TObject instances carry a real VMT so `is` cannot walk garbage
	./$(COMPILER) test/test_isas_open_world_b325.pas /tmp/test_isas_ow_b32526
	test "$$(/tmp/test_isas_ow_b32526)" = "$$(printf 'is=TRUE\nas=later\nplain is=FALSE')"
	# array-of-const boxing: PChar(S) = vtPChar(6) not vtPointer; class instance =
	# vtObject(7) not vtInteger (fpjson's TJSONArray.Create([PChar(S)]) raised)
	./$(COMPILER) test/test_varrec_pchar_object_b320.pas /tmp/test_varrec_pchar_b32026
	test "$$(/tmp/test_varrec_pchar_b32026)" = "$$(printf '  [0] vtype=0 int=42\n  [1] vtype=6 pchar-first=A\n  [2] vtype=7 obj.tag=77\n  [3] vtype=11 str=managed')"
	# method overloads distinguished only by CLASS IDENTITY: rec-aware decl
	# registration + exact-class-beats-ancestor ranking; the TJSONData(x) cast in
	# fpjson's Add(TJSONObject) recursed into ITSELF to stack overflow
	./$(COMPILER) test/test_overload_class_identity_b321.pas /tmp/test_ovl_classid_b32126
	test "$$(/tmp/test_ovl_classid_b32126)" = "$$(printf 'Add(TDer)\nAdd(TBase)\nAdd(TBase)\nAdd(Integer)')"
	# `on E: Exception` must catch exception classes from LATER-compiled units —
	# the descendant enumeration is per-unit; root Exception now matches all
	./$(COMPILER) test/test_except_cross_unit_class_b322.pas /tmp/test_exc_openworld_b32226
	test "$$(/tmp/test_exc_openworld_b32226)" = "$$(printf 'caught ELate: late class\nafter')"
	# ...and the general case: a NON-root target whose descendants live in a later
	# unit. Matched by a runtime RTTI parent-chain walk, not an enumeration (b339)
	./$(COMPILER) test/test_except_open_world_descendant_b339.pas /tmp/test_exc_openworld_b33926
	test "$$(/tmp/test_exc_openworld_b33926 | tail -1)" = "PASS"
	# ExceptAddr = the RAISE SITE (the return address the call to the raise stub
	# pushed), not the nil stub it used to be (b340)
	./$(COMPILER) test/test_exceptaddr_b340.pas /tmp/test_exceptaddr_b34026
	test "$$(/tmp/test_exceptaddr_b34026 | tail -1)" = "PASS"
	# WideChar values in STRING contexts (assign, +concat, string param) convert to
	# UTF-8 via builtin helpers; surrogate PAIR -> one 4-byte code point (fpjson \uXXXX);
	# was silently retained as a string POINTER -> memory corruption + crash
	./$(COMPILER) test/test_widechar_to_utf8_b319.pas /tmp/test_widechar_utf8_b31926
	test "$$(/tmp/test_widechar_utf8_b31926)" = "$$(printf '1=\303\270 len=2\n2=\360\237\214\237 len=4\n3=x\303\251\n4=Abc\n5=\303\270\n6=AB\n7=\n8=TRUE')"
	# the `^`/`[` arm of the same double case: `Slot(0)^ := 111;` emitted the call and
	# skipped `^ := 111` to the ';' with NO diagnostic, so the store never happened
	# (crtl's atexit stored every handler as 0). Read position was always correct.
	./$(COMPILER) test/test_stmt_call_result_deref_b387.pas /tmp/test_stmt_call_deref_b38726
	test "$$(/tmp/test_stmt_call_deref_b38726)" = "$$(printf 'a=111\nb=222\nc=333\nd=44\ne=55\nf=112')"
	# a SELECTOR after a function call used as a STATEMENT was silently dropped —
	# GetBox.Poke; / GetBox.SetVal(42); / GetBox.Val := 5; / GetBoxAt(0).M(..) all
	# vanished with no diagnostic (fpjson's RegisterTest registered 0 of 203 tests)
	./$(COMPILER) test/test_stmt_call_result_selector_b318.pas /tmp/test_stmt_call_selector_b31826
	test "$$(/tmp/test_stmt_call_selector_b31826)" = "$$(printf 'poke val=0\na=42\nb=5\nc=7\nd=7')"
	# a ROUTINE-LOCAL const array of CLASS REFERENCES registered a PENDING GLOBAL init
	# holding the routine-local symbol index — rolled back with the scope, so main lowered
	# a dangling IR_LEA ("invalid symbol in lea"). Verified against FPC.
	./$(COMPILER) test/test_local_const_classref_array_b317.pas /tmp/test_local_const_classref_b31726
	test "$$(/tmp/test_local_const_classref_b31726)" = "$$(printf '0=TA\n1=TB\n0=TA\n1=TB\ng0=TB\ng1=TA')"
	# `obj.F()` — EMPTY parens on a method whose params ALL have defaults (fcl-json writes
	# `J.FormatJSON()`); the arg loop had no ZERO-argument case (verified vs FPC)
	./$(COMPILER) test/test_empty_paren_default_args_b316.pas /tmp/test_empty_paren_b31626
	test "$$(/tmp/test_empty_paren_b31626)" = "$$(printf 'fmt2\nfmt2\nfmt1\nplain')"
	# an overloaded method's BODY must not clobber a DIFFERENT overload's table entry
	# (fpjson: ten Insert(Index,...) bodies clobbered the one-arg Insert; verified vs FPC)
	./$(COMPILER) test/test_method_overload_arity_rebind_b315.pas /tmp/test_method_overload_b31526
	test "$$(/tmp/test_method_overload_b31526)" = "oneintstr(x)bool(T)dbl"
	# a VARIANT argument binds a VARIANT parameter, not the first merely-compatible
	# overload (a Variant is compatible with every scalar; verified against FPC)
	./$(COMPILER) test/test_variant_arg_prefers_variant_overload.pas /tmp/test_variant_overload26
	test "$$(/tmp/test_variant_overload26)" = "$$(printf 'variant\nvariant\nvariant\nvariant\nint\nstr\nfloat\nvariant\nint\nint')"
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
	# bug-pascal-array-of-pointer-deref-loses-the-record-type: `arr[i]^.Field`
	# through a NAMED array-type alias whose element is a pointer-to-record
	# (typinfo's TPropList = array[..] of PPropInfo shape) must resolve every
	# field, not just the first.
	./$(COMPILER) test/test_arr_of_ptr_elemrec_b354.pas /tmp/test_arr_of_ptr_elemrec_b35426
	test "$$(/tmp/test_arr_of_ptr_elemrec_b35426)" = "10 20 30"
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
	test "$$(/tmp/test_high_low_const_expr26)" = "$$(printf '256\n256\n255 -32768 2\n2147483646\n7\n1\n0 9\n0 9 -5 5\na e\n10\n5')"
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
	! ./$(COMPILER) test/test_ordinal_default_on_string_param_fail.pas /tmp/test_odsp26 > /tmp/test_odsp.log 2>&1
	grep -q "string parameter's default must be a string literal" /tmp/test_odsp.log
	! ./$(COMPILER) test/test_string_default_on_ordinal_param_fail.pas /tmp/test_sdop26 > /tmp/test_sdop.log 2>&1
	grep -q "string literal cannot be the default for a non-string parameter" /tmp/test_sdop.log
	! ./$(COMPILER) test/test_forin_string_char_fail.pas /tmp/test_fsc26 > /tmp/test_fsc.log 2>&1
	grep -q "loop variable must be of type Char" /tmp/test_fsc.log
	! ./$(COMPILER) test/test_interface_field_access_fail.pas /tmp/test_ifaf26 > /tmp/test_ifaf.log 2>&1
	grep -q 'interface has no member "fi"' /tmp/test_ifaf.log
	./$(COMPILER) test/test_interface_ascast_temp_lifetime.pas /tmp/test_iatl26
	test "$$(/tmp/test_iatl26)" = "$$(printf 'in P w=107\nalive v=7\ndestroy 7\ndone')"
	./$(COMPILER) test/test_interface_ascast_dead_branch_temp.pas /tmp/test_iadb26
	test "$$(/tmp/test_iadb26)" = "120"
	./$(COMPILER) test/test_interface_mainbody_ascast_temp.pas /tmp/test_imbt26
	test "$$(/tmp/test_imbt26)" = "$$(printf 'cast=107\nafter nil\ndestroy 7')"
	# Dynamic IR arrays: one function body that lowers to > 262144 IR nodes (the old
	# fixed MAX_IR cap) must compile — bug-pascal-ir-node-hard-limit-max-ir. Generated
	# at build time (a committed source would be ~300 KB); local array keeps it off the
	# global-fixup table, wide-but-few statements stay under the AST cap and seq-walk
	# recursion depth. 180 statements x 400 terms ~= 340k IR nodes; sum = 180*2200.
	# NOTE (bug-test-core-oversized-job-6gb-flaky): each stress test's generator is
	# EMBEDDED in its compile line via $$(python3 -c "...; print(p)"). testmgr's
	# split_jobs starts a job at a line BEGINNING with the compiler, and a separate
	# generator line lands in the PREVIOUS job while sharing the /tmp filename with
	# the next — union-find then chained every stress test plus an innocent unit test
	# into one ~6.8 GB job that flaked under load and serialized the tier. Embedded,
	# each stress test is its own job with its own learned mem/duration.
	./$(COMPILER) "$$(python3 -c "t='+'.join('a[%d]'%(k%10) for k in range(400)); L=['program p;','procedure big;','var s: int64; a: array[0..9] of int64; i: longint;','begin','  for i := 0 to 9 do a[i] := i + 1;','  s := 0;']+['  s := s + '+t+';']*180+['  writeln(s);','end;','begin big; end.']; p='/tmp/test_ir_overflow_large.pas'; open(p,'w').write(chr(10).join(L)+chr(10)); print(p)")" /tmp/test_ir_overflow_large26
	test "$$(/tmp/test_ir_overflow_large26)" = "396000"
	# Dynamic AST arrays: a function body with > 516096 AST nodes (the old fixed
	# INLINE_AST_BASE per-proc cap) must compile — feature-dynamic-compiler-tables.
	# 350 statements x 400 terms ~= 560k AST nodes; sum = 350*2200. Local array +
	# few-wide statements keep it off the global-fixup table and under seq-walk depth.
	./$(COMPILER) "$$(python3 -c "t='+'.join('a[%d]'%(k%10) for k in range(400)); L=['program p;','procedure big;','var s: int64; a: array[0..9] of int64; i: longint;','begin','  for i := 0 to 9 do a[i] := i + 1;','  s := 0;']+['  s := s + '+t+';']*350+['  writeln(s);','end;','begin big; end.']; p='/tmp/test_ast_overflow_large.pas'; open(p,'w').write(chr(10).join(L)+chr(10)); print(p)")" /tmp/test_ast_overflow_large26
	test "$$(/tmp/test_ast_overflow_large26)" = "770000"
	# Dynamic token arrays: a source with more tokens than the initial 65536 reserve
	# must grow the token buffer (EnsureTokCapacity), not overflow — feature-dynamic-
	# compiler-tables. 12000 tiny procs ~= 72k tokens (one doubling). The old 2M cap
	# is exercised by the sqlite corpus (Track T), not a unit test (a >2M-token program
	# trips MAX_PROCS/MAX_AST first). self-host already lexes ~1M tokens per build.
	./$(COMPILER) "$$(python3 -c "L=['program p;']+['procedure q%d; begin end;'%i for i in range(12000)]+['begin','  writeln(42);','end.']; p='/tmp/test_token_growth.pas'; open(p,'w').write(chr(10).join(L)+chr(10)); print(p)")" /tmp/test_token_growth26
	test "$$(/tmp/test_token_growth26)" = "42"
	# Dynamic Syms arrays: >16384 symbols (the EnsureSymCapacity initial reserve) must
	# grow the parallel Sym* arrays, not overflow — feature-dynamic-compiler-tables.
	./$(COMPILER) "$$(python3 -c "L=['program p;','var']+['  v%d: longint;'%i for i in range(20000)]+['begin','  v0 := 7; writeln(v0);','end.']; p='/tmp/test_sym_growth.pas'; open(p,'w').write(chr(10).join(L)+chr(10)); print(p)")" /tmp/test_sym_growth26
	test "$$(/tmp/test_sym_growth26)" = "7"
	# Dynamic UField arrays: a struct with >16384 fields (the EnsureUFieldCapacity
	# reserve) must grow the UFld* pool — feature-dynamic-compiler-tables. Access low
	# fields (offset 0/4) to sidestep a separate pre-existing huge-struct high-offset bug.
	./$(COMPILER) "$$(python3 -c "L=['struct s {']+['  int f%d;'%i for i in range(20000)]+['};','int main(void){ struct s b; b.f0=7; b.f1=35; return b.f0+b.f1; }']; p='/tmp/test_ufield_growth.c'; open(p,'w').write(chr(10).join(L)+chr(10)); print(p)")" /tmp/test_ufield_growth26
	/tmp/test_ufield_growth26; test $$? -eq 42
	./$(COMPILER) test/test_dynarray_of_fixed_array.pas /tmp/test_dynarray_of_fixed_array26
	test "$$(/tmp/test_dynarray_of_fixed_array26 | tail -1)" = "total ok 13 / 13"
	./$(COMPILER) test/test_class_managed_fields_finalize.pas /tmp/test_class_managed_fields_finalize26
	test "$$(/tmp/test_class_managed_fields_finalize26)" = "$$(printf 'basic freed=1 order=HT\nalias freed=1\nls=keep-me\nafter alias freed=2\nruntime freed=2')"
	./$(COMPILER) test/test_member_visibility.pas /tmp/test_member_visibility26
	test "$$(/tmp/test_member_visibility26)" = "$$(printf '7\n30\n3\n1')"
	# class consts are class-SCOPED, not unscoped globals: two classes' same-named
	# private consts must not clobber, and a class const must not clobber a unit
	# global (bug-pascal-class-const-visibility). FPC-differential identical.
	./$(COMPILER) test/test_class_const_scope.pas /tmp/test_class_const_scope26
	test "$$(/tmp/test_class_const_scope26 | tail -1)" = "CLASS CONST OK"
	# the mirror rule for FIELDS: inside a method the class's own field beats a
	# unit-level const of the same name, and reads and writes must agree
	# (bug-unit-const-shadows-a-field). FPC-differential identical.
	./$(COMPILER) test/test_unit_const_vs_field.pas /tmp/test_unit_const_vs_field26
	test "$$(/tmp/test_unit_const_vs_field26 | tail -1)" = "UNIT CONST VS FIELD OK"
	./$(COMPILER) --strict-visibility test/test_member_visibility.pas /tmp/test_member_visibility_strict26
	test "$$(/tmp/test_member_visibility_strict26)" = "$$(printf '7\n30\n3\n1')"
	! ./$(COMPILER) --strict-visibility test/test_member_visibility_strict_fail.pas /tmp/test_mvsf26 > /tmp/test_mvsf.log 2>&1
	grep -q "cannot access strict private" /tmp/test_mvsf.log
	! ./$(COMPILER) --strict-visibility test/test_method_visibility_strict_fail.pas /tmp/test_methvsf26 > /tmp/test_methvsf.log 2>&1
	grep -q "cannot access strict private" /tmp/test_methvsf.log
	# strict-private CLASS CONST reached from a descendant method (tclass12b shape)
	./$(COMPILER) test/test_class_const_visibility_strict_fail.pas /tmp/test_ccvsf_lax26 > /tmp/test_ccvsf_lax.log 2>&1
	! ./$(COMPILER) --strict-visibility test/test_class_const_visibility_strict_fail.pas /tmp/test_ccvsf26 > /tmp/test_ccvsf.log 2>&1
	grep -q "cannot access strict private" /tmp/test_ccvsf.log
	# --strict-fpc umbrella: bundles case/operator/visibility/require-forward (NOT
	# StrictOverload), so an ordinary RTL-using program still compiles under it...
	# A float LITERAL must be the nearest double to the text written. The old
	# rational scaler was 1 ULP low on 23 of 490 sampled literals, silently.
	# bug-a-float-literal-lexer-is-not-correctly-rounded
	./$(COMPILER) -Fulib/rtl test/lex_float_literal.pas /tmp/lex_float_literal26
	test "$$(/tmp/lex_float_literal26 | tail -1)" = "LEXFLOAT OK"
	# write(v:w:d) must not overflow Int64 into 2^63's own digits, and must round
	# the way FPC does (half away from zero).
	# bug-b-writeln-float-with-17-decimals-prints-garbage
	./$(COMPILER) test/lib_writefloat_fixed.pas /tmp/lib_writefloat_fixed26
	test "$$(/tmp/lib_writefloat_fixed26 | tail -1)" = "WRITEFLOAT OK"
	# ...and past 2^53 the digits it prints must be the VALUE's digits, not the
	# binary granularity a divide-down loop recovers there. The WriteLn tail of
	# the same program carries those; expectations are exact (decimal.Decimal),
	# not FPC. bug-a-write-fixed-emits-false-digits-past-1e22
	test "$$(/tmp/lib_writefloat_fixed26 | grep -c '^99999999999999991611392$$')" = "1"
	test "$$(/tmp/lib_writefloat_fixed26 | grep -c '^10000000000000000905969664$$')" = "1"
	test "$$(/tmp/lib_writefloat_fixed26 | grep -c '^1000000000000000019884624838656\.00$$')" = "1"
	test "$$(/tmp/lib_writefloat_fixed26 | grep -c '^-99999999999999991611392\.00$$')" = "1"
	test "$$(/tmp/lib_writefloat_fixed26 | grep -c '^       99999999999999991611392$$')" = "1"
	# ...and the FRACTION is exact too, not ~16 digits then zeros. Expectations
	# from decimal.Decimal(float(x)), half-away-from-zero.
	# bug-a-write-fixed-fraction-digits-past-16-are-invented
	test "$$(/tmp/lib_writefloat_fixed26 | grep -c '^0.333333333333333314829616256247$$')" = "1"
	test "$$(/tmp/lib_writefloat_fixed26 | grep -c '^0.1000000000000000055511151$$')" = "1"
	test "$$(/tmp/lib_writefloat_fixed26 | grep -c '^1 2 3$$')" = "1"
	test "$$(/tmp/lib_writefloat_fixed26 | grep -c '^10.0$$')" = "1"
	./$(COMPILER) --strict-fpc -Fulib/rtl test/lib_strict_fpc.pas /tmp/lib_strict_fpc26
	test "$$(/tmp/lib_strict_fpc26)" = "42 OK"
	# ...and --strict-fpc reproduces FPC's SHIFT widths, asymmetry included: a
	# variable operand wraps at its declared width and shl masks the count to 5
	# bits, while FPC's own constant FOLDER does neither. The default dialect
	# deliberately diverges (decide-shift-operator-promotion-width), which is
	# why this row needs the flag. Every value is fpc -O1's own output.
	# ESP: an ordinal/ordinal float operator takes its depth from the TARGET,
	# because its operands supply none — a declared Double used to hold
	# float32's 1/3 on xtensa/riscv32 and nowhere else. A Single target and an
	# expression that already has a float operand are the controls.
	# A SoC target must be BYTE-IDENTICAL to the generic spelling it defaults
	# from: --target=esp32c3 is what --target=riscv32 has always meant, and
	# esp32s3 what xtensa meant. If these ever diverge, the capability table has
	# started disagreeing with the constants it replaced.
	# decide-esp-soc-axis-and-capability-table
	./$(COMPILER) --target=riscv32 test/test_esp_float_depth_from_target.pas /tmp/test_soc_rv26
	./$(COMPILER) --target=esp32c3 test/test_esp_float_depth_from_target.pas /tmp/test_soc_c326
	cmp /tmp/test_soc_rv26 /tmp/test_soc_c326
	./$(COMPILER) --esp-profile=bare --target=xtensa test/test_esp_bare.pas /tmp/test_soc_xt26
	./$(COMPILER) --esp-profile=bare --target=esp32s3 test/test_esp_bare.pas /tmp/test_soc_s326
	cmp /tmp/test_soc_xt26 /tmp/test_soc_s326
	./$(COMPILER) test/test_esp_float_depth_from_target.pas /tmp/test_espdepth26
	test "$$(/tmp/test_espdepth26 | tail -1)" = "ESP FLOAT DEPTH OK"
	test "$$(/tmp/test_espdepth26 | head -2 | tr '\n' '|')" = "0.33333333333333331483|0.33333334326744079590|"
	test "$$(/tmp/test_espdepth26 | head -6 | tail -2 | tr '\n' '|')" = "0.83333333333333325932|0.11111111111111110494|"
	./$(COMPILER) --strict-fpc test/test_strict_fpc_shift_widths.pas /tmp/test_strictshift26
	test "$$(/tmp/test_strictshift26 | tail -1)" = "STRICT FPC SHIFT WIDTHS OK"
	test "$$(/tmp/test_strictshift26 | head -5 | tr '\n' '|')" = "1099511627776|9223372036854775804|2147483648|2048|2048|"
	# ...and WITHOUT the flag the same file keeps the native-width answers
	./$(COMPILER) test/test_strict_fpc_shift_widths.pas /tmp/test_nativeshift26
	test "$$(/tmp/test_nativeshift26 | head -5 | tr '\n' '|')" = "1099511627776|9223372036854775804|2147483648|8796093022208|8796093022208|"
	# ...and it activates its member flags (StrictCase rejects a duplicate label
	# that the lax default accepts). feature-strict-fpc-umbrella.
	./$(COMPILER) test/strict_fpc_case_fail.pas /tmp/strict_fpc_case_lax26 > /tmp/strict_fpc_case_lax.log 2>&1
	! ./$(COMPILER) --strict-fpc test/strict_fpc_case_fail.pas /tmp/strict_fpc_case26 > /tmp/strict_fpc_case.log 2>&1
	grep -q "duplicate or overlapping case label" /tmp/strict_fpc_case.log
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
	! ./$(COMPILER) test/test_undefined_field_fail.pas /tmp/test_udf26 > /tmp/test_udf.log 2>&1
	grep -q "no such member on this record/class" /tmp/test_udf.log
	# A `procedure` method has no result and cannot be read as a value. It used to
	# COMPILE and hand back whatever was in the return register
	# (bug-p-procedure-method-in-an-expression-yields-garbage). The _ok half pins
	# the three shapes the check must NOT reject -- a constructor as a value (also
	# IsFunc=False), a `(`-led statement through an as-cast, and plain procedure
	# call statements.
	! ./$(COMPILER) test/test_procedure_as_value_fail.pas /tmp/test_pav26 > /tmp/test_pav.log 2>&1
	grep -q "is a procedure and has no result" /tmp/test_pav.log
	./$(COMPILER) test/test_procedure_as_value_ok.pas /tmp/test_pav_ok26
	test "$$(/tmp/test_pav_ok26 | tail -1)" = "PASS"
	# A selector on a CONSTRUCTOR result -- the chain was dropped, so an Integer
	# got the instance pointer and the program printed garbage silently
	# (bug-p-member-off-a-constructor-result-yields-garbage). The Make() lines in
	# there are the control: the same shape on a function result always worked.
	./$(COMPILER) test/test_ctor_result_member.pas /tmp/test_tcrm26
	test "$$(/tmp/test_tcrm26 | tail -1)" = "PASS"
	# `.Free` off anything but a bare variable -- a[0].Free, d[0].Free, r.f.Free,
	# h.f.Free, (o as T).Free all died as "no such member", because Free is not a
	# member of any class the frontend knows and only the literal `ident . Free ;`
	# token shape was recognised (bug-p-free-and-destroy-only-work-on-a-simple-
	# variable). Asserts the SEMANTICS: destructor runs, a user Free wins, nil is
	# a no-op.
	./$(COMPILER) test/test_free_designator.pas /tmp/test_tfd26
	test "$$(/tmp/test_tfd26 | tail -1)" = "PASS"
	# syncobjs.TCriticalSection must actually exclude -- it was a no-op stub with
	# TryEnter always True (bug-b-criticalsection-was-a-no-op-stub).
	./$(COMPILER) test/test_criticalsection.pas /tmp/test_tcs26
	test "$$(/tmp/test_tcs26 | tail -1)" = "PASS"
	# a VIRTUAL method with a 64-bit param AND a 64-bit result: every 32-bit
	# backend's virtual-call path pushed one word per arg, dropping the high half
	# (bug-a-virtual-method-int64-in-and-out-32bit). x86-64 was never affected, so
	# this line only guards the shape; the value is in the CROSS runs.
	./$(COMPILER) test/test_virtual_int64_param_and_result.pas /tmp/test_tvi26
	test "$$(/tmp/test_tvi26 | tail -1)" = "PASS"
	# the full 32-bit call-argument MATRIX: every by-value shape that is not one
	# word (Int64, Double, Single, set) crossed with every call KIND (direct,
	# indirect, virtual). Each 32-bit backend wrote that ladder out once per kind
	# and the copies drifted -- i386's virtual path had no double and no single
	# case, arm32's had no single, i386's indirect had no set, riscv32's indirect
	# had none of them (feature-a-unify-32bit-call-argument-marshalling). Like the
	# line above, x86-64 only guards the SHAPE here; the values are in the CROSS runs.
	./$(COMPILER) test/test_call_arg_marshalling_32bit.pas /tmp/test_cam26
	test "$$(/tmp/test_cam26 | tail -1)" = "PASS"
	# what a RECORD may legally contain (b347): no published, no protected (records don't
	# inherit), a class method must be static, a ctor needs a mandatory parameter, and a
	# local/anonymous record type gets FIELDS ONLY. All were parse-and-dropped before.
	./$(COMPILER) test/test_record_rules_ok.pas /tmp/test_record_rules_ok26
	test "$$(/tmp/test_record_rules_ok26 | tail -1)" = "PASS"
	! ./$(COMPILER) test/test_record_published_fail.pas /tmp/test_recpub26 > /tmp/test_recpub.log 2>&1
	grep -q "cannot have a published section" /tmp/test_recpub.log
	! ./$(COMPILER) test/test_record_protected_fail.pas /tmp/test_recprot26 > /tmp/test_recprot.log 2>&1
	grep -q "cannot have protected members" /tmp/test_recprot.log
	! ./$(COMPILER) test/test_record_ctor_noparam_fail.pas /tmp/test_recctor26 > /tmp/test_recctor.log 2>&1
	grep -q "at least one parameter without a default" /tmp/test_recctor.log
	! ./$(COMPILER) test/test_record_local_advanced_fail.pas /tmp/test_recloc26 > /tmp/test_recloc.log 2>&1
	grep -q "can only have fields" /tmp/test_recloc.log
	# class-NESTED types by qualified name (TOuter.TInner) + SizeOf of one; TSysCharSet
	# was missing from SysUtils entirely (b348; tdefault8 / tset4)
	./$(COMPILER) test/test_nested_class_type_b348.pas /tmp/test_nested_class_type26
	test "$$(/tmp/test_nested_class_type26 | tail -1)" = "PASS"
	# `case` evaluates its selector EXACTLY once — it used to re-evaluate per label
	# element, so `case F(x) of` ran F up to N times (b346; ~510 pasmith divergences)
	./$(COMPILER) test/test_case_selector_single_eval.pas /tmp/test_case_single_eval26
	test "$$(/tmp/test_case_single_eval26 | tail -1)" = "PASS"
	# two enum TYPES are distinct: `c := banana` used to store TFruit's ordinal into a
	# TColor (silently green). Rejected now — without breaking casts/Ord/call results
	! ./$(COMPILER) test/test_enum_identity_fail.pas /tmp/test_enumid26 > /tmp/test_enumid.log 2>&1
	grep -q "cannot assign a value of enum type" /tmp/test_enumid.log
	./$(COMPILER) test/test_enum_identity_ok.pas /tmp/test_enumid_ok26
	test "$$(/tmp/test_enumid_ok26 | tail -1)" = "PASS"
	# an unspecialized generic template is not a type: it has no zero value (tdefault11/12)
	! ./$(COMPILER) test/test_default_unspecialized_generic_fail.pas /tmp/test_defgen26 > /tmp/test_defgen.log 2>&1
	grep -q "must be specialized" /tmp/test_defgen.log
	# --strict / {$STRICT ON}: FPC-parity routine visibility (require-forward, b363).
	# Positive: forward + mutual recursion + unit/builtin calls bind under strict.
	./$(COMPILER) -Fulib/rtl test/test_require_forward_strict.pas /tmp/test_reqfwd26
	test "$$(/tmp/test_reqfwd26)" = "$$(printf 'TRUE\nTRUE\nabove\n42\n2')"
	# Negative: call-before-define without forward compiles by DEFAULT, errors under --strict.
	./$(COMPILER) test/test_require_forward_strict_fail.pas /tmp/test_reqfwdneg26 > /dev/null
	! ./$(COMPILER) --strict test/test_require_forward_strict_fail.pas /tmp/test_reqfwdneg26 > /tmp/test_reqfwd.log 2>&1
	grep -q "routine used before its declaration" /tmp/test_reqfwd.log
	# `sealed` is enforced: no descendants, no abstract methods, not also `abstract`
	# (tsealed1/2/3) — while a sealed LEAF and a plain abstract class stay legal
	! ./$(COMPILER) test/test_sealed_class_fail.pas /tmp/test_sealed26 > /tmp/test_sealed.log 2>&1
	grep -q "cannot derive from the sealed class" /tmp/test_sealed.log
	! ./$(COMPILER) test/test_sealed_abstract_method_fail.pas /tmp/test_sealedam26 > /tmp/test_sealedam.log 2>&1
	grep -q "sealed class cannot have an abstract method" /tmp/test_sealedam.log
	! ./$(COMPILER) test/test_sealed_abstract_class_fail.pas /tmp/test_sealedac26 > /tmp/test_sealedac.log 2>&1
	grep -q "cannot be both abstract and sealed" /tmp/test_sealedac.log
	./$(COMPILER) test/test_sealed_ok.pas /tmp/test_sealed_ok26
	test "$$(/tmp/test_sealed_ok26 | tail -1)" = "PASS"
	./$(COMPILER) test/test_forward_ptr_record_field.pas /tmp/test_fwd_ptr_rec26
	test "$$(/tmp/test_fwd_ptr_rec26 | tail -1)" = "PASS"
	! ./$(COMPILER) test/test_pointer_member_fail.pas /tmp/test_ptr_member_fail26 > /tmp/test_ptr_member_fail.log 2>&1
	grep -q "a pointer has no members" /tmp/test_ptr_member_fail.log
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
	./$(COMPILER) test/test_managed_record_return_reuse.pas /tmp/test_managed_record_return_reuse26
	test "$$(/tmp/test_managed_record_return_reuse26)" = "$$(printf '10 123\n10 123\n20 246\n10 123\n20 246')"
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
	# SA_SIGINFO (x86-64): the dispatch stub parks si_code / si_addr / the
	# ucontext* before calling the hook. si_addr is checked against the address
	# the test deliberately faults on ($DEAD0000 = 3735879680), so a wrong union
	# offset cannot pass; the SIGUSR1 half checks a NEGATIVE si_code
	# (SI_TKILL = -6), which is what the stub's sign-extension exists for.
	./$(COMPILER) test/test_signal_siginfo.pas /tmp/test_signal_siginfo26
	test "$$(/tmp/test_signal_siginfo26)" = "$$(printf 'segv code=1\nsegv addr=3735879680\nctx set=TRUE\nusr1 code=-6\nstage=2')"
	# PC rewrite: the handler points the saved ucontext PC at a Pascal proc
	# that raises, and the fault is caught by the try/except the faulting
	# code was already inside. The pc-is-the-fault line is the exact check
	# of the per-arch PC offset -- rewriting the wrong ucontext word would
	# clobber an unrelated register instead.
	./$(COMPILER) test/test_signal_pc_rewrite.pas /tmp/test_signal_pcrw26
	test "$$(/tmp/test_signal_pcrw26)" = "$$(printf 'pc-is-the-fault=TRUE\ncode=1 addr=3735879680\ncaught a fault as an exception, hits=1\nand execution continued')"
	# Float-exception mask control (feature-float-exception-mask-control):
	# the default stays quiet IEEE (Inf/NaN propagate -- a deliberate decision,
	# so this half is a PIN test), the mask round-trips, and with a cause
	# unmasked the SSE instruction traps SIGFPE with the si_code that says
	# WHICH -- FLTDIV 3 / FLTOVF 4 / FLTUND 5 / FLTRES 6 / FLTINV 7, the fact
	# an FPC-style runtime error 205/206/207/208 mapping is built out of.
	# A literal-concat passed to a Variant parameter: IR folds 'p' + 'q' to one
	# tyString literal, and the variant store took its source kind from the AST
	# (tyAnsiString) -- so it boxed a static literal as a heap handle and the
	# argument arrived EMPTY. Plain-Pascal reachable; found through NilPy.
	./$(COMPILER) test/test_variant_literal_concat_arg.pas /tmp/test_var_litcat26
	test "$$(/tmp/test_var_litcat26)" = "$$(printf '[pq]\n[pq]\n[pq]\n[xy]\n[pqr]\n[ab]\ndirect: pq')"
	./$(COMPILER) test/test_float_exception_mask.pas /tmp/test_float_exc_mask26
	test "$$(/tmp/test_float_exc_mask26)" = "$$(printf 'default mask=63\nquiet 1/0= Inf\nquiet overflow= Inf\nquiet 0/0= Nan\nprev=63 now=59\nafter restore=63 (returned 59)\ntrapped si_code=3\ntrapped si_code=4\ntrapped si_code=7\ntrapped si_code=5\ntrapped si_code=6\nmask after=63\nquiet again= Inf\nFPE_FLTDIV=3 FLTOVF=4 FLTUND=5 FLTRES=6 FLTINV=7')"
	# --fpc-float-errors: the opt-in FPC emulation on top of that mask. The
	# entry unmasks what FPC unmasks and a SIGFPE hook decodes si_code into
	# FPC's runtime error -- 208 float div-zero / 205 overflow / 207 invalid,
	# all three measured against FPC 3.x. The SAME source built WITHOUT the
	# flag must still print Inf and exit 0: that is the default this feature
	# exists NOT to change.
	./$(COMPILER) --fpc-float-errors test/test_fpc_float_errors.pas /tmp/test_fpc_ferr26
	/tmp/test_fpc_ferr26; test "$$?" = "0"
	/tmp/test_fpc_ferr26 div; test "$$?" = "208"
	/tmp/test_fpc_ferr26 ovf; test "$$?" = "205"
	/tmp/test_fpc_ferr26 inv; test "$$?" = "207"
	test "$$(/tmp/test_fpc_ferr26 div)" = "Runtime error 208 (division by zero)"
	./$(COMPILER) test/test_fpc_float_errors.pas /tmp/test_fpc_ferr_off26
	test "$$(/tmp/test_fpc_ferr_off26 div)" = "no trap, r= Inf"
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
	# Rust fixed array of structs (feature-rust-corpus-chess enabler): arr[i].field
	# read/write + tuple arr[i].0 over the shared array-of-record codegen — the
	# [Move; 256] move-list stand-in for the engine's ArrayVec<Move, 256>.
	./$(COMPILER) test/test_rust_struct_array.rs /tmp/test_rust_struct_array26
	test "$$(/tmp/test_rust_struct_array26)" = "$$(printf 'checksum 1202\nsq 30')"
	# Rust chess FULL legality (feature-rust-corpus-chess): Move packed into one i64
	# (from|to<<6|flags<<12) replaces the engine's Move struct + ArrayVec; EP, castling,
	# promotion, underpromotion + check detection. Node counts match the reference perft
	# through depth 5 from startpos and a promotion-heavy CPW position through depth 3.
	# Also exercises 5-param internal calls (r8/r9 register spill, REmitParamRegSpill).
	./$(COMPILER) test/test_rust_chess_perft_full.rs /tmp/test_rust_chess_perft_full26
	test "$$(/tmp/test_rust_chess_perft_full26)" = "$$(printf 'perft1 20\nperft2 400\nperft3 8902\nperft4 197281\nperft5 4865609\npromo1 24\npromo2 496\npromo3 9483\nkiwi1 48\nkiwi2 2039\nkiwi3 97862')"
	# Rust chess ENGINE (feature-rust-corpus-chess): faithful struct-based branch —
	# real Move struct held in [Move; 256] passed as &[Move] (slice-of-record), make/
	# unmake, negamax, and UCI best-move output via char casts. perft(4) exact +
	# picks the mate-in-1 rook lift a1a8. Exercises fixed-array-of-structs and
	# slice-of-struct (arr[i].field / slice[i].field) end to end.
	./$(COMPILER) test/test_rust_chess_engine.rs /tmp/test_rust_chess_engine26
	test "$$(/tmp/test_rust_chess_engine26)" = "$$(printf 'perft4 197281\nbestmove a1a8')"
	# Rust chess SEARCH (feature-rust-corpus-chess, stage-6 gate "search finds a mate"):
	# material-eval negamax with mate scoring on the same movegen. Finds a forced
	# mate-in-1 (depth 2) and mate-in-2 (depth 4), and does NOT see them one ply
	# shallower — proving real minimax depth, not a static-eval artifact.
	./$(COMPILER) test/test_rust_chess_search.rs /tmp/test_rust_chess_search26
	test "$$(/tmp/test_rust_chess_search26)" = "$$(printf 'mate1 1 score 999999\nshallow 0 score 200\nmate2 1 score 999997\nmate2shallow 0 score 500\nstarteval 0')"
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
	# Zig 5/6-param internal calls (feature-zig-frontend): r8/r9 arg-register spill
	# via the shared REmitParamRegSpill — the old case i of 0..3 SIGILL'd on param 5.
	./$(COMPILER) test/test_zig_manyparams.zig /tmp/test_zig_manyparams26
	test "$$(/tmp/test_zig_manyparams26)" = "$$(printf 'a5 15 a6 21\nrec 103')"
	# Zig slice parameters (feature-zig-frontend): `fn f(s: []T, ...)` — the 16-byte
	# __ptr/__len record passed by address; s[i] rw + s.len through the pointer.
	./$(COMPILER) test/test_zig_slice_params.zig /tmp/test_zig_slice_params26
	test "$$(/tmp/test_zig_slice_params26)" = "$$(printf 'sum 15\nscaled 13 53 n 5')"
	# Zig chess perft (feature-zig-frontend, real-load bug-probe): full-legality
	# movegen exercising []i64 slice params, array literals, 5-param recursion +
	# deep control flow. Node counts match the reference (startpos d4, Kiwipete d3).
	./$(COMPILER) test/test_zig_chess_perft.zig /tmp/test_zig_chess_perft26
	test "$$(/tmp/test_zig_chess_perft26)" = "$$(printf 'perft4 197281\nkiwi3 97862')"
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
	test "$$(/tmp/test_default_params_methods26 | tail -1)" = "total ok 31 / 31"
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
	# Ord/Chr/Length/Succ/Pred/Low/High fold in const decls, case labels, array bounds
	./$(COMPILER) test/test_const_expr_builtins.pas /tmp/test_const_expr_builtins26
	test "$$(/tmp/test_const_expr_builtins26)" = "ok"
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
	test "$$(/tmp/test_dynarray_copy26)" = "$$(printf '3\n30\n40\n50\n2\n50\n60\n2\n30 60\n3\n1 10 100\n2 20 200\n3 30 300\n6 60\n6 10 60\n10 999\n5 400\n0 777\n0')"
	# ...and the SAME one-argument shorthand with a string `Copy` overload in
	# scope, which takes an entirely different parse path (the no-overload-match
	# fallback, not the bare intrinsic). Both arms implement dynarray Copy, and
	# before the fix they failed with two different messages -- exactly how a
	# double case stays half-broken.
	./$(COMPILER) test/test_dynarray_copy_uses_sysutils.pas /tmp/test_dyncopy_sysutils26
	test "$$(/tmp/test_dyncopy_sysutils26)" = "$$(printf '3 1 3\n1 99\nell\n5 4')"
	# Copy() over MANAGED elements must RETAIN what it copied. Run TWICE, the
	# second time with -dPXX_HEAP_DEBUG: without the poison a plain run passes
	# even when the retain is missing, because the freed bytes still hold the old
	# text. That second line is the one that can actually fail.
	# Copy() from a dyn-array EXPRESSION (nested element, record field) rather than
	# a bare name. Not folded into test_dynarray_copy.pas because that file is in
	# the cross differentials and the nested element source dies on riscv32 for an
	# unrelated pre-existing reason
	# (bug-a-riscv32-nested-dynamic-array-element-write-segfaults).
	./$(COMPILER) test/test_dynarray_copy_expr_source.pas /tmp/test_dyncopy_expr26
	test "$$(/tmp/test_dyncopy_expr26)" = "$$(printf '3 10 30\n10 99\n2 20\n3 7 9\n9 77\n1 9\nkeep REPLACED also\nalso SECOND')"
	./$(COMPILER) -dPXX_HEAP_DEBUG test/test_dynarray_copy_expr_source.pas /tmp/test_dyncopy_expr_hd26
	test "$$(/tmp/test_dyncopy_expr_hd26)" = "$$(printf '3 10 30\n10 99\n2 20\n3 7 9\n9 77\n1 9\nkeep REPLACED also\nalso SECOND')"
	./$(COMPILER) test/test_dynarray_copy_managed_elems.pas /tmp/test_dyncopy_managed26
	test "$$(/tmp/test_dyncopy_managed26)" = "checks 2211 fails 0"
	./$(COMPILER) -dPXX_HEAP_DEBUG test/test_dynarray_copy_managed_elems.pas /tmp/test_dyncopy_managed_hd26
	test "$$(/tmp/test_dyncopy_managed_hd26)" = "checks 2211 fails 0"
	./$(COMPILER) test/test_val_builtin.pas /tmp/test_val_builtin26
	test "$$(/tmp/test_val_builtin26)" = "$$(printf '5 0\n55 0\n0 2\n-42 0\n88 0\n0 1\n1000000000000 0\n0')"
	./$(COMPILER) test/test_hilo_swap.pas /tmp/test_hilo_swap26
	test "$$(/tmp/test_hilo_swap26)" = "$$(printf '10 11 43776\n0 5 1280\n255 170 -21761\n0 86 22016\n18 52 13330\n237 204 -13075\n4660 22136 1450709556\n60875 43400 -1450644021\n39612 57072 3740310204\n287454020 1432778632 6153737367135073092\n4294967295 4294967295 -1\n2291772091 3437096703 14762217934866197179\n12 8 51200\n18 52 13330\n0 5 1280\n12 8 51200\n18 52 13330\n156 64 16540\n4660 22136 1450709556\n287454020 1432778632 6153737367135073092')"
	./$(COMPILER) test/test_overload_no_narrowing.pas /tmp/test_overload_no_narrowing26
	test "$$(/tmp/test_overload_no_narrowing26)" = "$$(printf 'longint 5\nbyte 200\nword 40000\nlongint 100000\nint64 5000000000\nbyte 200\nword 40000\nbyte 7\n')"
	./$(COMPILER) --mimic-fpc test/test_procvar_value_context.pas /tmp/test_procvar_value_context26
	test "$$(/tmp/test_procvar_value_context26)" = "procvar-value-context OK"
	./$(COMPILER) --mimic-fpc test/test_procvar_fpc_mode.pas /tmp/test_procvar_fpc_mode26
	test "$$(/tmp/test_procvar_fpc_mode26)" = "procvar-fpc-mode OK"
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
	# a 1-D GLOBAL pointer array with an element the flat pre-scan can't fold (&g,
	# (void*)0, &a[i][j], a cast) was zero-skipped WHOLE; now defers to the walker
	# LOCAL multidim brace elision: short rows zero-fill, never bleed (b367)
	./$(COMPILER) test/clocal_multidim_brace_elision_b367.c /tmp/clocal_mdbe_b36726
	test "$$(/tmp/clocal_mdbe_b36726)" = "$$(printf 'a=1 0 2 0\nb=3 4 6\nc=3 4 6\nd=9 0 8 7\ne=1 0 2 3 0\nf=1.5 0.0 2.5')"
	# pragma pack(N)/push/pop must cap member alignment (was parsed away; b366)
	./$(COMPILER) test/cpragma_pack_b366.c /tmp/cpragma_pack_b36626
	test "$$(/tmp/cpragma_pack_b36626)" = "$$(printf 'A=5 offA=1\nB=8 offB=4\nC=6 offC=2\nD=8 offD=4')"
	./$(COMPILER) test/cglobal_1d_ptr_array_addr_init_b350.c /tmp/cglobal_1d_ptr_array_b35026
	test "$$(/tmp/cglobal_1d_ptr_array_b35026)" = "$$(printf 'g474=7 7\nholes=-1 7 -1 7\nmix=null hi zz\ndeep=6 2\nunsized=7 -1 7 n=3\ndblderef=7')"
	# a SCALAR pointer global init the fast paths can't fold ((char*)&g, &st.f,
	# arr+1) was silently skipped (null pointer); now defers to a replay at main
	./$(COMPILER) test/cglobal_scalar_ptr_init_defer_b351.c /tmp/cglobal_scalar_ptr_b35126
	test "$$(/tmp/cglobal_scalar_ptr_b35126)" = "7 3 1 2 5 6 3 lit"
	# UNION bitfields must all start at bit 0 (they were packed sequentially like
	# struct bitfields -- f2 read bits 14..27, silent wrong value vs the gcc oracle)
	./$(COMPILER) test/cunion_bitfield_overlap_b352.c /tmp/cunion_bitfield_b35226
	test "$$(/tmp/cunion_bitfield_b35226)" = "$$(printf 'f0=fffffffb f1=3ffb f2=3ffb f3=fffffffb sz=4\nafter: f0=ffffc005 f1=5\nstruct: a=5 b=9\nstruct after: a=5 b=3')"
	# >32-bit bitfield ARITHMETIC reduces to the field's exact bit-precision (gcc):
	# +,-,*,<< wrap mod 2^width, signed sign-extends, pre-inc/dec yields the wrapped
	# value (bug-c-long-long-bitfield-promotion arithmetic residual). gcc-differential.
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cbitfield_arith_precision.c /tmp/cbitfield_arith26
	test "$$(/tmp/cbitfield_arith26)" = "$$(printf 'mul33=0 mul40=0 mul41=1099511627776\ns.q=-549755813888 sadd=-6\npre=0 predec=1099511627774 post=0')"
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
	./$(COMPILER) test/test_alloca.c /tmp/test_alloca26
	test "$$(/tmp/test_alloca26)" = "7088718"
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
	./$(COMPILER) test/cstruct_over256_fields.c /tmp/cstruct_over256_fields26
	/tmp/cstruct_over256_fields26; test "$$?" = "42"
	./$(COMPILER) test/cpartial_multidim_index.c /tmp/cpartial_multidim_index26
	/tmp/cpartial_multidim_index26; test "$$?" = "42"
	./$(COMPILER) test/cmultidim_row_decay.c /tmp/cmultidim_row_decay26
	/tmp/cmultidim_row_decay26; test "$$?" = "42"
	./$(COMPILER) test/csizeof_array_type.c /tmp/csizeof_array_type26
	/tmp/csizeof_array_type26; test "$$?" = "42"
	./$(COMPILER) test/cptr_to_multidim_array.c /tmp/cptr_to_multidim_array26
	/tmp/cptr_to_multidim_array26; test "$$?" = "42"
	./$(COMPILER) test/cptr_to_array_param.c /tmp/cptr_to_array_param26
	/tmp/cptr_to_array_param26; test "$$?" = "42"
	./$(COMPILER) test/cmultidim_row_address.c /tmp/cmultidim_row_address26
	/tmp/cmultidim_row_address26; test "$$?" = "42"
	./$(COMPILER) test/clocal_fnptr_array.c /tmp/clocal_fnptr_array26
	/tmp/clocal_fnptr_array26; test "$$?" = "42"
	./$(COMPILER) test/csigned_unsigned_compare64.c /tmp/csigned_unsigned_compare6426
	/tmp/csigned_unsigned_compare6426; test "$$?" = "42"
	./$(COMPILER) test/cglobal_ptr_to_struct_array_elem.c /tmp/cglobal_ptr_to_struct_array_elem26
	/tmp/cglobal_ptr_to_struct_array_elem26; test "$$?" = "42"
	./$(COMPILER) test/csubint_compare_promote.c /tmp/csubint_compare_promote26
	/tmp/csubint_compare_promote26; test "$$?" = "42"
	./$(COMPILER) test/cmultidim_nested_index_subscript.c /tmp/cmultidim_nested_index_subscript26
	/tmp/cmultidim_nested_index_subscript26; test "$$?" = "42"
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
	./$(COMPILER) test/cfloat_array_decay_addr_b378.c /tmp/cfloat_array_decay_addr_b37826
	/tmp/cfloat_array_decay_addr_b37826; test "$$?" = "42"
	./$(COMPILER) test/cfinalizers_on_main_return_b379.c /tmp/cfinalizers_main_b37926
	/tmp/cfinalizers_main_b37926; test "$$?" = "42"
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
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cpredefined_macros_b166.c /tmp/cpredefined_macros_b16626
	/tmp/cpredefined_macros_b16626; test "$$?" = "42"
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
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cptrdiff_vararg_b.c /tmp/cptrdiff_vararg_b26
	/tmp/cptrdiff_vararg_b26; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cbool_normalise_b.c /tmp/cbool_normalise_b26
	/tmp/cbool_normalise_b26; test "$$?" = "42"
	./$(COMPILER) --threadsafe -Ilib/crtl/include -Ilib/crtl/src test/cpthread_needs_threadsafe_b.c /tmp/cpthread_needs_threadsafe_b26
	/tmp/cpthread_needs_threadsafe_b26; test "$$?" = "42"
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
	./$(COMPILER) test/csizeof_member_chain_through_pointer.c /tmp/csizeof_member_chain26
	/tmp/csizeof_member_chain26; test "$$?" = "42"
	./$(COMPILER) test/cstatic_init_cast.c /tmp/cstatic_init_cast26
	/tmp/cstatic_init_cast26; test "$$?" = "42"
	./$(COMPILER) test/cchar_plain_signedness.c /tmp/cchar_plain_signedness26
	/tmp/cchar_plain_signedness26; test "$$?" = "42"
	./$(COMPILER) test/cchar_promotion_contexts.c /tmp/cchar_promotion_contexts26
	/tmp/cchar_promotion_contexts26; test "$$?" = "42"
	# bug-cfront-error-directive-silently-ignored: #error stops a LIVE branch,
	# stays silent in a not-taken one (the half with the regression risk — the
	# corpora hold 1200+ #errors, essentially all behind untaken guards).
	./$(COMPILER) test/cerror_directive.c /tmp/cerror_directive26
	/tmp/cerror_directive26; test "$$?" = "42"
	@./$(COMPILER) test/cerror_directive_fail.c /tmp/cerror_directive_fail26 2>&1 \
	  | grep -q 'configuration is unsupported' \
	  || { echo 'cerror_directive_fail: FAIL - #error in a live branch must stop the compile and name its text'; exit 1; }
	# bug-cfront-sizeof-unparenthesised-subscript: the unary sizeof operand is a
	# unary-expression, so the whole postfix chain applies — `sizeof a[0]` (and
	# the ARRAY_SIZE idiom built on it) used to be a parse error. gcc-differential.
	./$(COMPILER) test/csizeof_postfix_unparen.c /tmp/csizeof_postfix_unparen26
	/tmp/csizeof_postfix_unparen26; test "$$?" = "42"
	# bug-cfront-undeclared-type-in-cast-treated-as-zero: a cast to an undeclared
	# type name is an ERROR with a did-you-mean (it used to degrade to the value
	# 0 — a NULL fn pointer crashing far from the cast); value position keeps its
	# degrade-to-0 leniency, which is what the corpora rely on.
	./$(COMPILER) test/cundeclared_type_value_pos.c /tmp/cundeclared_type_value_pos26
	/tmp/cundeclared_type_value_pos26; test "$$?" = "42"
	@./$(COMPILER) test/cundeclared_type_cast_fail.c /tmp/cundeclared_type_cast_fail26 2>&1 \
	  | grep -q "unknown type name '_PyCFunctionFastWithKeywords' in cast; did you mean 'PyCFunctionFastWithKeywords'" \
	  || { echo 'cundeclared_type_cast_fail: FAIL - a cast to an undeclared type must error and suggest the near miss'; exit 1; }
	# #if `?:`, #line renumbering, and __LINE__ inside #if — three evaluator gaps
	# that only became visible once #error above stopped being a no-op.
	./$(COMPILER) test/cpreproc_cond_line.c /tmp/cpreproc_cond_line26
	/tmp/cpreproc_cond_line26; test "$$?" = "42"
	./$(COMPILER) test/carch_predefines.c /tmp/carch_predefines26
	/tmp/carch_predefines26; test "$$?" = "42"
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
	# csmith seed 79: a SUFFIX re-runs the constant ladder, it does not widen the
	# rung the unsuffixed ladder picked. 0x9745DC78L fits a signed long, so it is
	# a positive long -- typed unsigned long it converted the negative int32 it is
	# compared against into a huge unsigned and the comparison silently flipped.
	# 1588 csmith lines reduced to that one line. Expectations are gcc's.
	./$(COMPILER) test/chex_long_suffix_literal.c /tmp/chex_long_suffix26
	test "$$(/tmp/chex_long_suffix26)" = "$$(printf 'hexL   1\nhex    1\ndecL   1\nhexLL  1\nhexU   0\nplain  1')"
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
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/ccompound_literal_addrof.c /tmp/ccompound_literal_addrof26
	/tmp/ccompound_literal_addrof26; test "$$?" = "42"
	./$(COMPILER) test/csubnormal_literal.c /tmp/csubnormal_literal26
	/tmp/csubnormal_literal26; test "$$?" = "42"
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
	./$(COMPILER) test/ccompound_literal_scalar_b368.c /tmp/ccompound_literal_scalar_b36826
	/tmp/ccompound_literal_scalar_b36826; test "$$?" = "42"
	./$(COMPILER) test/cindirect_call_stackargs_b369.c /tmp/cindirect_call_stackargs_b36926
	/tmp/cindirect_call_stackargs_b36926; test "$$?" = "42"
	./$(COMPILER) test/cpreproc_paste_no_arg_expand_b370.c /tmp/cpreproc_paste_no_arg_expand_b37026
	/tmp/cpreproc_paste_no_arg_expand_b37026; test "$$?" = "42"
	./$(COMPILER) test/cpreproc_body_string_param_b371.c /tmp/cpreproc_body_string_param_b37126
	/tmp/cpreproc_body_string_param_b37126; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cmath_rint_lrint_b372.c /tmp/cmath_rint_lrint_b37226
	/tmp/cmath_rint_lrint_b37226; test "$$?" = "42"
	./$(COMPILER) test/cbitfield_mixed_type_pack_b373.c /tmp/cbitfield_mixed_type_pack_b37326
	/tmp/cbitfield_mixed_type_pack_b37326; test "$$?" = "42"
	./$(COMPILER) test/cswitch_unsigned_negative_case_b374.c /tmp/cswitch_unsigned_negative_case_b37426
	/tmp/cswitch_unsigned_negative_case_b37426; test "$$?" = "42"
	./$(COMPILER) test/cdesignated_enum_index_unsized_b375.c /tmp/cdesignated_enum_index_unsized_b37526
	/tmp/cdesignated_enum_index_unsized_b37526; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cprintf_exact_digits_b376.c /tmp/cprintf_exact_digits_b37626
	/tmp/cprintf_exact_digits_b37626; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cmath_exp_correct_round_b377.c /tmp/cmath_exp_correct_round_b37726
	/tmp/cmath_exp_correct_round_b37726; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cmath_log_correct_round_b378.c /tmp/cmath_log_correct_round_b37826
	/tmp/cmath_log_correct_round_b37826; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cmath_cbrt_correct_round_b379.c /tmp/cmath_cbrt_correct_round_b37926
	/tmp/cmath_cbrt_correct_round_b37926; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cmath_pow_correct_round_b380.c /tmp/cmath_pow_correct_round_b38026
	/tmp/cmath_pow_correct_round_b38026; test "$$?" = "42"
	./$(COMPILER) test/cfloat_cast_narrow_b381.c /tmp/cfloat_cast_narrow_b38126
	/tmp/cfloat_cast_narrow_b38126; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cmath_log2_expm1_family_b382.c /tmp/cmath_log2_expm1_family_b38226
	/tmp/cmath_log2_expm1_family_b38226; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cmath_hyperbolic_family_b383.c /tmp/cmath_hyperbolic_family_b38326
	/tmp/cmath_hyperbolic_family_b38326; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cmath_hypot_correct_round_b384.c /tmp/cmath_hypot_correct_round_b38426
	/tmp/cmath_hypot_correct_round_b38426; test "$$?" = "42"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/cmath_trig_family_b385.c /tmp/cmath_trig_family_b38526
	/tmp/cmath_trig_family_b38526; test "$$?" = "42"
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
	# bug-c-undeclared-identifier-as-function-pointer-becomes-null: an undeclared
	# identifier passed where a known callee's parameter is a POINTER must be a
	# hard error, not a warning-plus-0 that later calls/derefs through NULL.
	! ./$(COMPILER) test/cundeclared_fnptr_arg_rejected_b167.c /tmp/cundeclared_fnptr_arg_rejected_b16726 > /tmp/cundeclared_fnptr_arg_rejected_b167.log 2>&1
	grep -q "undeclared identifier passed as argument" /tmp/cundeclared_fnptr_arg_rejected_b167.log
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
	./$(COMPILER) test/test_copy_char_promote.pas /tmp/test_copy_char_promote26
	test "$$(/tmp/test_copy_char_promote26)" = "$$(printf '[a]\n[z]\n[ell]')"
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
	# for-in over a SET CONSTRUCTOR (members in ORDINAL order, not source order)
	# and over a string LITERAL (source order) -- both were refused outright
	./$(COMPILER) test/test_forin_literal_sources.pas /tmp/test_forin_lit26
	test "$$(/tmp/test_forin_lit26 | tail -1)" = "FORIN LITERAL SOURCES OK"
	test "$$(/tmp/test_forin_lit26 | head -1)" = "ints  1 2 3 5 "
	test "$$(/tmp/test_forin_lit26 | head -5 | tail -1)" = "mixed 1 2 3 7 9 "
	test "$$(/tmp/test_forin_lit26 | head -8 | tail -1)" = "lit   h.e.l.l.o."
	./$(COMPILER) test/test_forin_enumerator.pas /tmp/test_forin_enumerator26
	test "$$(/tmp/test_forin_enumerator26)" = "$$(printf 'x=11\nx=22\nx=33\nsum=66')"
	./$(COMPILER) test/test_forin_record_enumerator_b355.pas /tmp/test_forin_record_enumerator_b35526
	test "$$(/tmp/test_forin_record_enumerator_b35526)" = "$$(printf 'i=10\ni=20\ni=30\ni=40\nsum=100')"
	./$(COMPILER) test/test_operator_implicit_shortstring_b356.pas /tmp/test_operator_implicit_shortstring_b35626
	test "$$(/tmp/test_operator_implicit_shortstring_b35626)" = "$$(printf 'seven\nconverted: len=10')"
	./$(COMPILER) test/test_method_pointer_virtual_b357.pas /tmp/test_method_pointer_virtual_b35726
	test "$$(/tmp/test_method_pointer_virtual_b35726)" = "$$(printf 'nonvirt=15\nvirt-base=6\nvirt-deriv=1005\ndirect=1005')"
	./$(COMPILER) test/test_method_pointer_arg_b361.pas /tmp/test_method_pointer_arg_b36126
	test "$$(/tmp/test_method_pointer_arg_b36126)" = "$$(printf 'cb=15\ncb=6\ncb=1005')"
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
	./$(COMPILER) test/test_shortstring_trunc.pas /tmp/test_shortstring_trunc26
	test "$$(/tmp/test_shortstring_trunc26)" = "$$(printf 'aaaa 4\nb-ok\nabcdefgh 8\nabcdefgh 8\nxxxx 4\nguard-ok\nyyyy 4\npguard-ok\nzzzz 4\nmguard-ok\naaaa 4\nbbbb 4\naguard-ok\nabcd 4')"
	./$(COMPILER) test/test_not_ord_bitwise.pas /tmp/test_not_ord_bitwise26
	test "$$(/tmp/test_not_ord_bitwise26)" = "$$(printf '%s\n' -2 -2 158 254 254 254 -2)"
	./$(COMPILER) test/test_record_cast_field_offset.pas /tmp/test_record_cast_fo26
	test "$$(/tmp/test_record_cast_fo26)" = "$$(printf '%s\n' 305419896 2596069104 1311768467463790320 5 5 not-ok notor-ok)"
	./$(COMPILER) test/test_u64_to_double.pas /tmp/test_u64_to_double26
	test "$$(/tmp/test_u64_to_double26)" = "$$(printf '%s\n' assign-ok field-ok cmp-ok round-ok small-ok signed-ok)"
	./$(COMPILER) test/test_qword_literal_binop.pas /tmp/test_qword_lit26
	test "$$(/tmp/test_qword_lit26)" = "$$(printf '%s\n' 18085043209385476867 4210752250 50529028 18085043209385476867 cmp-ok neg-ok)"
	./$(COMPILER) test/test_shift_operand_width.pas /tmp/test_shift_ow26
	test "$$(/tmp/test_shift_ow26)" = "$$(printf '%s\n' 2147483648 2147483648 36028797014769664 -4294967296)"
	./$(COMPILER) test/test_overflow_checks_qplus.pas /tmp/test_qplus26
	test "$$(/tmp/test_qplus26)" = "$$(printf 'wrapped 0\ncaught=4')"
	./$(COMPILER) test/test_overflow_qplus_narrow.pas /tmp/test_qplus_narrow26
	test "$$(/tmp/test_qplus_narrow26)" = "caught=5 clean=4 wrap=-294967296"
	./$(COMPILER) test/test_variant_fn_return_forward.pas /tmp/test_variant_fn_return_forward26
	test "$$(/tmp/test_variant_fn_return_forward26)" = "$$(printf '2 77\n2 77\n2 77\nforwarded')"
	./$(COMPILER) test/test_open_array_of_variant.pas /tmp/test_open_array_of_variant26
	test "$$(/tmp/test_open_array_of_variant26)" = "$$(printf '35\n7\n9')"
	./$(COMPILER) test/test_overflow_succ_pred.pas /tmp/test_qplus_sp26
	test "$$(/tmp/test_qplus_sp26)" = "$$(printf 'wrapped-hi 4294967295\ncaught=3')"
	./$(COMPILER) test/test_range_checks_rplus.pas /tmp/test_rplus26
	test "$$(/tmp/test_rplus26)" = "$$(printf 'lax-b 44\ncaught=3')"
	./$(COMPILER) test/test_range_checks_reads.pas /tmp/test_rplus_r26
	test "$$(/tmp/test_rplus_r26)" = "caught=4"
	./$(COMPILER) test/test_range_checks_dynfield.pas /tmp/test_rplus_df26
	test "$$(/tmp/test_rplus_df26)" = "caught=2"
	./$(COMPILER) test/test_range_checks_nd.pas /tmp/test_rplus_nd26
	test "$$(/tmp/test_rplus_nd26)" = "ok 42 7 caught=2"
	./$(COMPILER) test/test_io_checks_iplus.pas /tmp/test_iplus26
	test "$$(/tmp/test_iplus26)" = "ioresult=TRUE caught=1"
	./$(COMPILER) test/test_io_checks_mimic.pas /tmp/test_iplus_lax26
	test "$$(/tmp/test_iplus_lax26)" = "caught=1"
	./$(COMPILER) --mimic-fpc test/test_io_checks_mimic.pas /tmp/test_iplus_mim26
	test "$$(/tmp/test_iplus_mim26)" = "caught=1"
	./$(COMPILER) test/test_param_array_lowbound.pas /tmp/test_palb26
	test "$$(/tmp/test_palb26)" = "7 8 caught=2"
	./$(COMPILER) test/test_range_checks_enum_field.pas /tmp/test_rplus_ef26
	test "$$(/tmp/test_rplus_ef26)" = "$$(printf 'e 9\nok 7 5 4 caught=4')"
	./$(COMPILER) test/test_forin_bounds_nd.pas /tmp/test_forin_bnd26
	test "$$(/tmp/test_forin_bnd26)" = "$$(printf '%s \n%s \n%s \n%s \n' '10 20 30' '50 60 70' '1 2 9' '3 4 5')"
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
	./$(COMPILER) test/test_interface_com_value_param.pas /tmp/test_interface_com_value_param26
	test "$$(/tmp/test_interface_com_value_param26)" = "$$(printf 'go\nafter DoStash freed=0\ngo\nafter nil freed=1')"
	./$(COMPILER) test/test_interface_com_default.pas /tmp/test_interface_com_default26
	test "$$(/tmp/test_interface_com_default26)" = "$$(printf 'before nil\nDTOR ran\nafter nil')"
	./$(COMPILER) test/test_tinterfacedobject_builtin.pas /tmp/test_tio_builtin26
	test "$$(/tmp/test_tio_builtin26)" = "$$(printf 'go\ndestroyed=1\ndestroyed=2\nsurvived scope exit')"
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
	./$(COMPILER) -Futest/units_defscope test/test_pascal_define_unit_scope_order1.pas /tmp/test_pascal_define_unit_scope_order126
	test "$$(/tmp/test_pascal_define_unit_scope_order126)" = "$$(printf 'ua\nub does not see it')"
	./$(COMPILER) -Futest/units_defscope test/test_pascal_define_unit_scope_order2.pas /tmp/test_pascal_define_unit_scope_order226
	test "$$(/tmp/test_pascal_define_unit_scope_order226)" = "$$(printf 'ub does not see it\nua')"
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
	test "$$(/tmp/test_conformance_1_26)" = "$$(printf 'shape 0 square area=9.00 tag=5000000004\nshape 1 circle area=12.00 tag=1000000000\nshape 2 generic area=0.00 tag=1000000007\ntotal area=21.00\npts len=3 high=2\n  pt p 0,0\n  pt p 2,1\n  pt p 4,4\n  i 42\n  q 9000000000\n  b TRUE\n  s mixed\nv int=123\ncaught: boom\ncaught=1\nconcat=abcdef len=6\nV...V.')"
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
	test "$$(/tmp/test_shr_width26)" = "$$(printf '9223372036854775804\n2147483644\n9223372036854775804\n1099511627776\n256\n2147483648\n-16\n2147483648\n1099511627776\n4503599627370496')"
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
	./$(COMPILER) test/test_open_array_managed_length.pas /tmp/test_open_array_managed_length26
	test "$$(/tmp/test_open_array_managed_length26)" = "$$(printf 'varstr 4 3 0\nw0 w1 w2 w3 \nconststr 4 3\nvalstr 4 3\nvarint 5 4\n42\nvarstr 2 1 0\nw0 w1\nconststr 2 1\nvarint 3 2\n42')"
	./$(COMPILER) -Itest/unitinit test/test_unit_init_begin_form.pas /tmp/test_unit_init_begin_form26
	test "$$(/tmp/test_unit_init_begin_form26)" = "$$(printf '7\n8\n222')"
	./$(COMPILER) -Itest/unitinit test/test_unit_finalization.pas /tmp/test_unit_finalization26
	test "$$(/tmp/test_unit_finalization26)" = "$$(printf 'init runs\ninit2 runs\nmain done\nfinalization2 runs\nfinalization runs')"
	./$(COMPILER) -Itest/unitinit test/test_unit_finalization_halt.pas /tmp/test_unit_finalization_halt26
	out="$$(/tmp/test_unit_finalization_halt26; echo "rc=$$?")"; \
	test "$$out" = "$$(printf 'init runs\ninit2 runs\nbefore halt\nfinalization2 runs\nfinalization runs\nrc=3')"
	./$(COMPILER) test/test_static_array_length.pas /tmp/test_static_array_length26
	test "$$(/tmp/test_static_array_length26)" = "$$(printf '3\n2\n64\n60\n3\n2\n0\n5\n9\n5')"
	./$(COMPILER) -Itest/builtin_shadow test/test_builtin_name_demote.pas /tmp/test_builtin_name_demote26
	test "$$(/tmp/test_builtin_name_demote26)" = "$$(printf '10000\n60\nsys-ok')"
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
	test "$$(/tmp/test_const_precedence26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_const_typecast.pas /tmp/test_const_typecast26
	test "$$(/tmp/test_const_typecast26)" = "$$(printf '4503599627370496\n4503599627370495\n300\n1\n65535\n-56\n4294967295\n-1\n1\n65535')"
	# NativeUInt/NativeInt(field) widens the FIELD's width, not the cast's
	./$(COMPILER) test/test_nativeint_cast_field.pas /tmp/test_nativeint_cast_field26
	test "$$(/tmp/test_nativeint_cast_field26)" = "$$(printf '16\n16\n16\n16\n16\n15\n0')"
	./$(COMPILER) test/test_const_array_of_string.pas /tmp/test_const_array_of_string26
	test "$$(/tmp/test_const_array_of_string26)" = "$$(printf 'aa bb cc dd \na b c d \nxx yy zz \nzzz bb')"
	# a const/var array of string[N] copies CHARS into the frozen slot (it stored
	# the source handle), and an element store clamps to the element's capacity
	# a fixed-array PARAMETER must not swallow a scalar argument: its
	# Params[].TypeKind is the ELEMENT kind, so it looked like the Integer
	# overload and won on declaration order (Sum(n) then segfaulted)
	# FPC's rule: an integer argument prefers an integer parameter over a float
	# one even when it NARROWS -- and losslessness still ranks among the ints
	./$(COMPILER) test/test_overload_int_prefers_int.pas /tmp/test_ovl_int26
	test "$$(/tmp/test_ovl_int26 | tail -1)" = "OVERLOAD INT PREFERS INT OK"
	test "$$(/tmp/test_ovl_int26 | head -4 | tr '\n' '|')" = "Fa int int int int int dbl|Fb byte byte byte byte|Fc i64 i64 i64 i64|Fd int i64 i64 int int|"
	./$(COMPILER) test/test_overload_array_vs_scalar.pas /tmp/test_ovl_arr_scalar26
	test "$$(/tmp/test_ovl_arr_scalar26 | tail -1)" = "OVERLOAD ARRAY VS SCALAR OK"
	test "$$(/tmp/test_ovl_arr_scalar26 | head -4 | tr '\n' '|')" = "arr    6|call   6|var    50|lit    70|"
	./$(COMPILER) test/test_const_array_of_string_n.pas /tmp/test_const_array_of_string_n26
	test "$$(/tmp/test_const_array_of_string_n26)" = "$$(printf '[dd][ff]\n[gg][ii]\n[jj][ll]\n[abc][xy]\n[p][s]\n[v0][v2]\n2 2 3\n[m1][m2]\n[abc][zz] 3')"
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
	./$(COMPILER) test/test_fixed_array_copy_managed.pas /tmp/test_fixed_array_copy_managed26
	test "$$(/tmp/test_fixed_array_copy_managed26)" = "$$(printf 'pqr\npqr\npqr\nxyzw\ngs0gs12\nabcd\nf0f1f2\nOK')"
	./$(COMPILER) test/test_record_byvalue_managed_small.pas /tmp/test_record_byvalue_managed_small26
	test "$$(/tmp/test_record_byvalue_managed_small26)" = "$$(printf '104 7 14\n204 9 18\n2 7\n104 7 14\n204 9 18\n2 7\n104 7 14\n204 9 18\n2 7\nOK')"
	./$(COMPILER) test/test_dynarray_whole_assign.pas /tmp/test_dynarray_whole_assign26
	test "$$(/tmp/test_dynarray_whole_assign26)" = "$$(printf '8 42 7\n3 pqr\n3 pqr\n8 42 42\n77 77 88 88\n77 77 88 88\nzz zz b b\n1 9 2 3\n1 9\nOK')"
	./$(COMPILER) test/test_i386_int64_high_half.pas /tmp/test_i386_int64_high_half26
	test "$$(/tmp/test_i386_int64_high_half26)" = "$$(printf '1\n-1\n1\n-1\n1\n1\n0\n3\nOK')"
	./$(COMPILER) test/test_int64_cast_of_nativeint.pas /tmp/test_int64_cast_of_nativeint26
	test "$$(/tmp/test_int64_cast_of_nativeint26)" = "$$(printf '5\n-3\n-3\n7\n7000000\n1234567890\n1\nOK')"
	./$(COMPILER) test/test_writeln_float_exact.pas /tmp/test_writeln_float_exact26
	test "$$(/tmp/test_writeln_float_exact26)" = "$$(printf ' 1.0000000000000000E+030\n 1.0000000000000000E+100\n 9.9999999999999997E+199\n 9.9999999999999995E-021\n 1.2345678901234500E+014\n 2.4999999999999999E+100\n 1.0000000000000000E+100\n 0.0000000000000000E+000\n 1.0000000000000000E+000\n-2.5000000000000000E+000\n 4.9406564584124654E-324\n 9.9998886718268301E-321\n 1.7976931348623157E+308\n 1.0000000000000001E-001\n 9.9999999999999982E+099\nOK')"
	./$(COMPILER) test/test_writeln_float_width.pas /tmp/test_writeln_float_width26
	test "$$(/tmp/test_writeln_float_width26)" = "$$(printf '[      3.1416]\n[     -3.1416]\n[  10.0]\n[    1]\n[   -1]\n[123456.0]\n[    0.00]\n[      100000000000000000000.00]\n[     -100000000000000000000.00]\n[3.14]\nOK')"
	./$(COMPILER) -O2 test/test_warn_ignored_directives.pas /tmp/test_warn_ignored_directives26 2>/dev/null | grep -c warning | grep -qx 0
	test "$$(./$(COMPILER) -O2 --warn-ignored-directives test/test_warn_ignored_directives.pas /tmp/test_warn_ignored_directives26 2>&1 | grep -c warning)" = "6"
	test "$$(/tmp/test_warn_ignored_directives26)" = "$$(printf '1\n1')"
	./$(COMPILER) test/test_shadow_program_over_unit.pas /tmp/test_shadow_program_over_unit26
	test "$$(/tmp/test_shadow_program_over_unit26)" = "$$(printf 'mine\nmine-trim\nX\n7')"
	# `uses a, b` binds the LAST unit's routine, as FPC does — both orders, and
	# both call shapes (parameterless binds via FindProcBound, with-args via
	# MatchProcCall/MatchElig; fixing one left the other wrong)
	./$(COMPILER) -Futest test/test_shadow_last_uses_wins.pas /tmp/test_shadow_last_uses26
	test "$$(/tmp/test_shadow_last_uses26)" = "$$(printf 'B\nB')"
	./$(COMPILER) -Futest test/test_shadow_first_uses_hidden.pas /tmp/test_shadow_first_uses26
	test "$$(/tmp/test_shadow_first_uses26)" = "$$(printf 'A\nA')"
	./$(COMPILER) test/test_math_intrinsics_no_uses.pas /tmp/test_math_intrinsics_no_uses26
	test "$$(/tmp/test_math_intrinsics_no_uses26)" = "$$(printf '4.0\n0.0\n1.0\n1.0\n0.0\n3.14159\n7')"
	./$(COMPILER) test/test_writeln_text_char.pas /tmp/test_writeln_text_char26
	test "$$(/tmp/test_writeln_text_char26)" = "$$(printf 'ax   x  Z|\nab42 3.5|\nABCD\nOK')"
	./$(COMPILER) test/test_promoint_function_result.pas /tmp/test_promoint_function_result26
	test "$$(/tmp/test_promoint_function_result26)" = "$$(printf '12\n10000000000000000000000000000000000000000\n12\n24\n10000000000000000000000000000000000000000\n13\n1\nOK')"
	./$(COMPILER) test/test_promoint_parameter_32bit.pas /tmp/test_promoint_parameter_32bit26
	test "$$(/tmp/test_promoint_parameter_32bit26)" = "$$(printf '16\n0\n36\n4\n263\n768\n257\n256\n62500000000000000000000000000\n142857142857142857142857142857\nOK')"
	./$(COMPILER) test/test_promoint_arg_literal_and_result.pas /tmp/test_promoint_arg_literal26
	test "$$(/tmp/test_promoint_arg_literal26)" = "$$(printf '24\n-10\n4865804016353280000\n14\n2000000\n14\n12\nintstr\n15511210043330985984000000\nOK')"
	./$(COMPILER) test/test_index_getter_string_property.pas /tmp/test_index_getter_string26
	test "$$(/tmp/test_index_getter_string26)" = "$$(printf 'h\nh\no\ne\na\nb\ny\nhello\n5 hello\nOK')"
	./$(COMPILER) test/test_interlocked_no_uses.pas /tmp/test_interlocked_no_uses26
	test "$$(/tmp/test_interlocked_no_uses26)" = "$$(printf '6 6\n5 5\n5 42\n42 50\n50 99\n99 99\n101 101\n101 1001\nOK')"
	./$(COMPILER) -Fulib/rtl test/test_assert_raises_with_sysutils.pas /tmp/test_assert_raises26
	test "$$(/tmp/test_assert_raises26)" = "$$(printf 'passed\ncaught: EAssertionFailed: boom\nnomsg: EAssertionFailed: Assertion failed\nstill running\nOK')"
	./$(COMPILER) test/test_static_array_managed_scope_exit.pas /tmp/test_static_array_managed_scope_exit26
	test "$$(/tmp/test_static_array_managed_scope_exit26)" = "$$(printf '0\nOK')"
	./$(COMPILER) test/test_string_array_element_charwrite.pas /tmp/test_string_array_element_charwrite26
	test "$$(/tmp/test_string_array_element_charwrite26)" = "$$(printf '4x\n5x\n6x\n4y\n6z\nxyz\nOK')"
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
	test "$$(/tmp/test_float_write_ir26)" = "$$(printf '3.50\n4\n-2.750\n1.0\n0.00\n10.5\n 1.0000000000000000E+000\n-2.0000000000000000E+000\n 0.0000000000000000E+000\n 3.5000000000000000E+000\n 1.2345000000000000E+003')"
	./$(COMPILER) test/test_shared_object.pas /tmp/shared_object26
	test "$$(/tmp/shared_object26)" = "97"
	./$(COMPILER) test/test_c_import.pas /tmp/c_import26
	test "$$(/tmp/c_import26)" = "42"
	# a .c pulled as a UNIT: globals reserved AND initialized, forward-declared
	# static resolved, crtl's own <stdarg.h> found (gcc-differential)
	./$(COMPILER) -Futest test/test_c_unit_globals.pas /tmp/c_unit_globals26
	test "$$(/tmp/c_unit_globals26)" = "$$(printf '31\n8')"
	# bug-cfront-c-name-binds-to-pascal-routine-at-wrong-arity: in a mixed
	# Pascal+C build a C DECLARATION wins over a same-named Pascal routine of
	# another arity (was: bound to the Pascal one, out-param never written), and
	# an UNDECLARED call to such a name is refused rather than mis-bound.
	./$(COMPILER) -Futest test/test_c_cross_ns_arity.pas /tmp/c_cross_ns_arity26
	test "$$(/tmp/c_cross_ns_arity26)" = "time=1"
	@./$(COMPILER) -Futest test/test_c_cross_ns_arity_fail.pas /tmp/c_cross_ns_arity_fail26 2>&1 \
	  | grep -q "call to undeclared function 'time' would bind to the Pascal routine 'Time'" \
	  || { echo 'c_cross_ns_arity_fail: FAIL - an undeclared C call must not bind to a Pascal routine of another arity'; exit 1; }
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
	./$(COMPILER) test/test_ansistring_cast_extern_pchar.pas /tmp/test_ansistring_cast_extern_pchar26
	test "$$(/tmp/test_ansistring_cast_extern_pchar26)" = "$$(printf 'direct=hello len=5\nviavar=hello len=5')"
	./$(COMPILER) test/test_ansistring_cast_fnptr.pas /tmp/test_ansistring_cast_fnptr26
	test "$$(/tmp/test_ansistring_cast_fnptr26)" = "fnptr=world len=5"
	./$(COMPILER) test/test_widechar_var_to_string.pas /tmp/test_widechar_var_to_string26
	test "$$(/tmp/test_widechar_var_to_string26)" = "$$(printf 'direct=A\nviavar=B')"
	./$(COMPILER) test/test_widechar_var_concat.pas /tmp/test_widechar_var_concat26
	test "$$(/tmp/test_widechar_var_concat26)" = "$$(printf 'concat=xA\nlconcat=Ay\nwordadd=3000')"
	./$(COMPILER) test/test_widechar_var_to_string_arg.pas /tmp/test_widechar_var_to_string_arg26
	test "$$(/tmp/test_widechar_var_to_string_arg26)" = "$$(printf 'assign=A\nconcat=xA\narg=A')"
	./$(COMPILER) test/test_nested_interface_as_cast.pas /tmp/test_nested_interface_as_cast26
	test "$$(/tmp/test_nested_interface_as_cast26)" = "inline=101"
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
	test "$$(/tmp/test_rtti_reg26)" = "$$(printf 'Count: 3\nClass 0: TInterfacedObject\nClass 1: TBase\nClass 2: TChild')"
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
	test "$$(/tmp/test_syncobjs26)" = "$$(printf '1\n2\n3\n4')"
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
	test "$$(/tmp/test_dynarray_params26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	# the shared managed-block header: strings, dynarrays and objects
	./$(COMPILER) test/test_managed_block_header.pas /tmp/test_managed_block_header26
	test "$$(/tmp/test_managed_block_header26)" = "managed block header ok"
	# the META word: the ASCII flag, and the reserved low-32 budget
	./$(COMPILER) test/test_managed_block_meta.pas /tmp/test_managed_block_meta26
	test "$$(/tmp/test_managed_block_meta26)" = "managed block meta ok"
	# UCS4Char: FPC-parity type surface, plus the UTF-8 conversion (a pxx extension)
	./$(COMPILER) test/test_ucs4char.pas /tmp/test_ucs4char26
	test "$$(/tmp/test_ucs4char26)" = "ucs4char ok"
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
	# Nested dyn-array ALIASING (replaces test_nested_cow.pas — nested
	# copy-on-write was x86-64's alone and is gone; see
	# bug-a-x86-64-dynarray-assignment-copies-instead-of-aliasing). All 19
	# values diffed against an FPC build of the same file.
	./$(COMPILER) test/test_nested_alias.pas /tmp/test_nested_alias26
	test "$$(/tmp/test_nested_alias26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_variant.pas /tmp/test_variant26
	test "$$(/tmp/test_variant26)" = "$$(printf '42\n-7\nQ\n3.14\nTrue\n100')"
	./$(COMPILER) test/test_variant_ops.pas /tmp/test_variant_ops26
	test "$$(/tmp/test_variant_ops26)" = "$$(printf '8\n2\n15\n7.5\n12.5\nTRUE\nFALSE\nFALSE\nTRUE\nTRUE\n11\nTRUE')"
	./$(COMPILER) test/test_variant_byvalue_param.pas /tmp/test_variant_byvalue_param26
	test "$$(/tmp/test_variant_byvalue_param26)" = "$$(printf 'byval: 2\nafter write: clobbered\nconst: 2\nbyval: 42\nafter write: clobbered\nconst: 42\nbyval: hi\nafter write: clobbered\nconst: hi\ncaller intact: hi\nafter byref: written\nthree: 1 str 7\nthree: 5 lit 8\nroundtrip: rt\nbyval: 3.5\nafter write: clobbered\nfloat intact: 3.5')"
	./$(COMPILER) test/test_variant_div.pas /tmp/test_variant_div26
	test "$$(/tmp/test_variant_div26)" = "$$(printf '3\n2\n3.4\n2.5')"
	# A typecast of a Variant CONVERTS (FPC/Delphi semantics); it used to
	# reinterpret the 16-byte record and answer the tag word, and the float
	# kinds segfaulted. Diffed against an FPC build of the same file except
	# the two lines its own comments flag as conversion-level divergences.
	./$(COMPILER) test/test_variant_typecast.pas /tmp/test_variant_typecast26
	test "$$(/tmp/test_variant_typecast26)" = "$$(printf '9\n9\n9\n9\n9\n9\n9\n9.00\n9.00\nTRUE\n2.50\n2.50\n2\n2\nTRUE\n-1\n255\n-1.0\nTrue\nA\ntext\ntext\nA\n21\n2.500')"
	# ...and FPC's Variant->Char rule under --strict-fpc: render the variant,
	# take character 1 (Char(65) = '6'). The DEFAULT dialect answers Chr(n) —
	# the one row that deliberately does not track FPC. Diffed against an FPC
	# build of the same file.
	./$(COMPILER) --strict-fpc test/test_variant_typecast_strict.pas /tmp/test_variant_typecast_strict26
	test "$$(/tmp/test_variant_typecast_strict26)" = "$$(printf '6\n7\n1\n2\nT\nh\n0\n9\n-1\n255')"
	./$(COMPILER) test/test_variant_string.pas /tmp/test_variant_string26
	test "$$(/tmp/test_variant_string26)" = "$$(printf 'hello\n42\nhello\nmanaged\nworld\nlocal\n7')"
	./$(COMPILER) test/test_variant_string_ops.pas /tmp/test_variant_string_ops26
	test "$$(/tmp/test_variant_string_ops26)" = "$$(printf 'TRUE\nFALSE\nFALSE\nTRUE\nTRUE\nTRUE\nFALSE\nFALSE\nTRUE\nTRUE\nTRUE\nTRUE\nTRUE\nFALSE\nTRUE\nTRUE\nFALSE\nhello world\nab\nsweet potato\ngreen tomato\nFALSE\nTRUE\nFALSE\nFALSE')"
	./$(COMPILER) test/test_float_intrinsics.pas /tmp/test_float_intrinsics26
	test "$$(/tmp/test_float_intrinsics26)" = "$$(printf '3\n-3\n4\n2\n4\n0.7500\n3.0')"
	./$(COMPILER) test/test_nil_python_core.npy /tmp/test_nil_python_core26
	test "$$(/tmp/test_nil_python_core26)" = "$$(printf '0\n1\n1\n2\n3\n5\n10')"
	# re module over lib/rtl/regex.pas; expectation is CPython's own output
	# collections.Counter (dict in Counter mode); expectation is CPython's output
	# field(default_factory=dict); expectation is CPython's output
	# PEP 604 unions in annotations; expectation is CPython's output
	# tuple returns + the keyword-only marker; expectation is CPython's output
	# dict.fromkeys; expectation is CPython's output
	# a .npy program using a unit with an `array of const` parameter
	# subclassing a class from an imported unit: dotted base, from-import, and
	# an override dispatching through the base's own call site
	# configparser shim + the virtual optionxform hook a subclass overrides
	# keyword arguments bind by name, any subset (an omitted optional keeps its default)
	# a method parameter that is unannotated AND defaulted, explicit and omitted
	./$(COMPILER) test/test_nilpy_method_param_default.npy /tmp/test_nilpy_mpdef26
	test "$$(/tmp/test_nilpy_mpdef26)" = "$$(printf 'all three: p f z\ndefaulted: p f\ndefault is None: True')"
	# a field assigned from an unannotated ctor parameter becomes a variant
	./$(COMPILER) test/test_nilpy_field_from_unannotated_param.npy /tmp/test_nilpy_fldparam26
	test "$$(/tmp/test_nilpy_fldparam26)" = "$$(printf 'p f 0\nreassigned: q\nNone field: True\nafter store: set')"
	# the tkinter facade: compiled, not run - it needs an X display. Lives in
	# examples/tk/ because a .npy in test/ resolving `tk` picks up test/strings.pas
	# (a PROGRAM named Strings) ahead of the RTL unit tk.pas uses - the resolver
	# searches the source file's own directory first.
	./$(COMPILER) examples/tk/tkinter_facade.npy /tmp/test_nilpy_tkinter26
	# a field assigned `tk.Canvas(...)` keeps its class in ANY method, so calls on
	# it resolve statically and take keyword arguments (same X-display caveat)
	./$(COMPILER) examples/tk/field_class_identity.npy /tmp/test_nilpy_fldcls26
	# callable options: bound method / plain def / lambda, and a variable trace
	./$(COMPILER) examples/tk/callbacks.npy /tmp/test_nilpy_tkcb26
	./$(COMPILER) test/test_nilpy_kwargs_by_name.npy /tmp/test_nilpy_kwname26
	test "$$(/tmp/test_nilpy_kwname26)" = "$$(printf '%b' 'contiguous: root 7 hi z\ninterior hole: 0 skipped-width z\nonly the last: 0  last-only\nnone given: 0  z')"
	# a unit-qualified class construction (mod.Class(args))
	./$(COMPILER) test/test_nilpy_qualified_ctor.npy /tmp/test_nilpy_qualctor26
	test "$$(/tmp/test_nilpy_qualctor26)" = "$$(printf '1280x800\nTrue False')"
	# one Exception class serving both the Python and the sysutils surface
	./$(COMPILER) test/test_nilpy_rtl_exception_surface.npy /tmp/test_nilpy_rtlexc26
	test "$$(/tmp/test_nilpy_rtlexc26)" = "$$(printf '%b' 'mine\ncaught: \042abc\042 is an invalid integer\nend')"
	# uses order must not change whether pylib's own Exception.Create compiles
	# (bug-pascal-uses-order-breaks-pylib-exception): sysutils named first, then
	# reversed. Each also checks that the shared `Exception` name's CreateFmt
	# body wasn't corrupted onto the wrong unit's class row.
	./$(COMPILER) test/test_uses_order_pylib_exception_a.pas /tmp/test_uses_order_pylib_exc_a26
	test "$$(/tmp/test_uses_order_pylib_exc_a26)" = "$$(printf '%b' 'pylib hi\ncaught: \042abc\042 is an invalid integer\n[    3]\nend')"
	./$(COMPILER) test/test_uses_order_pylib_exception_b.pas /tmp/test_uses_order_pylib_exc_b26
	test "$$(/tmp/test_uses_order_pylib_exc_b26)" = "$$(printf '%b' 'pylib hi\ncaught: \042abc\042 is an invalid integer\n[%5d]\nend')"
	# a method on a fresh construction: class return, and omitted defaults filled
	./$(COMPILER) test/test_nilpy_ctor_suffix_defaults.npy /tmp/test_nilpy_ctorsfx26
	test "$$(/tmp/test_nilpy_ctorsfx26)" = "$$(printf 'a\nba\na 1\nba 1')"
	# return-type inference agrees between the shell pre-pass and the body parse
	./$(COMPILER) test/test_nilpy_infer_return.npy /tmp/test_nilpy_inferret26
	test "$$(/tmp/test_nilpy_inferret26)" = "$$(printf '5\n6\nv7\n5\n[1, 2, 3]')"
	# sorted(key=lambda), d.items() as a value, for-target unpacking, Cls().m()
	# the function-object ABI, dict views, len(variant), a local named `result`
	# a lambda's DEFAULT-parameter captures (key=key) reach invoke time
	./$(COMPILER) test/test_nilpy_lambda_capture.npy /tmp/test_nilpy_lamcap26
	test "$$(/tmp/test_nilpy_lamcap26)" = "$$(printf '%b' '[4, 3, 2, 1]\n[1, 2, 3, 4]\n[4, 3, 2, 1]\n[1, 2, 3, 4]')"
	# a defaulted lambda parameter the CALLER supplies overrides the default, on
	# BOTH lowerings — they are reached by body shape, not by signature
	./$(COMPILER) test/test_nilpy_lambda_default_override.npy /tmp/test_nilpy_lamdef26
	test "$$(/tmp/test_nilpy_lamdef26)" = "$$(printf '%b' '6 12\n6 12\n6 6\n11020 10220 10203\n[0, 1, 2]\n9 1')"
	# a container literal is RETURNED by a lambda, and keeps its tuple/list
	# identity, on both lowerings — and the aliased-capture shape still works
	# an int accumulator widens when a CONTAINER hands it a float, in both
	# scopes — and the range-loop promoted accumulator is untouched
	./$(COMPILER) test/test_nilpy_accumulate_float_from_container.npy /tmp/test_nilpy_accfloat26
	test "$$(/tmp/test_nilpy_accfloat26)" = "$$(printf '%b' '3.5\n3.5 3 3.5\n51090942171709440000\n20000000000000000000\n20000000000000000000\n4000000000\n[1, 2, 3]\n3.5')"
	./$(COMPILER) test/test_nilpy_lambda_container_result.npy /tmp/test_nilpy_lamctr26
	test "$$(/tmp/test_nilpy_lamctr26)" = "$$(printf '%b' '(3, 4) tuple\n[3, 4] list\n(3, 4) tuple\n[3, 4] list\n(3, 4) tuple\na-b-c\n[2, 3, 1] 3\nc-a-b 3\nx-y 2\n6\n2 7')"
	./$(COMPILER) test/test_nilpy_fnvalue_abi.npy /tmp/test_nilpy_fnvalue26
	test "$$(/tmp/test_nilpy_fnvalue26)" = "$$(printf '%b' '3\n5\n2\n2 3.0 2\n3.0\n1.0\nC\nG\n2\n4.0\n3.14 3    3.142 3.1     | 2.0')"
	# range is a VALUE — a lazy SEQUENCE: re-iterable, indexable, len-able,
	# sliceable, with constant-time membership. NOT a cursor (see the test).
	./$(COMPILER) test/test_nilpy_range_as_a_value.npy /tmp/test_nilpy_rangeval26
	test "$$(/tmp/test_nilpy_rangeval26)" = "$$(printf '%b' 'range(0, 3)\nrange(0, 10, 2)\nrange(5, 0)\n[0, 1, 2]\n[0, 1, 2]\n3 0 1 2\nTrue False False\n4 [0, 3, 6, 9]\n0 []\n[3, 2, 1]\nTrue True\nTrue False\nrange(2, 5)\n[2, 3, 4]\nrange(0, 10, 2) [0, 2, 4, 6, 8]\nrange(7, 10)\n1000000000 999999999 True False\n10 2 8\n[1, 2, 3] (0, 1, 2)\nFalse True\n[3, 2, 1, 0]\n[0, 2, 4, 6]\n[(0, \0047a\0047), (1, \0047b\0047), (2, \0047c\0047)]\n[(1, 0), (2, 1)]\n[\00470\0047, \00471\0047, \00472\0047]\n[0, 2, 4]\n[0, 1, 2]\n[0, 1, 2, 0, 1, 2]\n[0, 1, 2, 3]\n[0, 1, 2]\n[0, 1]\n7')"
	# map/filter/enumerate/zip/reversed are LAZY: an early break never reaches a
	# raise past it, a bound cursor resumes where it parked, len(map(...)) is a
	# TypeError, and each one reports CPython's own type name.
	# The quote is spelled \0047 and not \047 here: in a printf %b ARGUMENT the
	# escape is \0ddd, so \047 followed by a DIGIT swallows it as a fourth octal
	# digit and prints garbage. (In a printf FORMAT string it is \ddd instead,
	# which is why the older entries around here are spelled the other way.)
	./$(COMPILER) test/test_nilpy_lazy_map_filter.npy /tmp/test_nilpy_lazymap26
	test "$$(/tmp/test_nilpy_lazymap26)" = "$$(printf '%b' 'survived [0, 1, 2]\ncalls 3\nafter binding: 0\nafter breaking at 3: 3\nrest: [40, 50]\n[2, 4]\n[2, 3]\n[3, 6]\n[\00471\0047, \00472\0047]\n[1, 3]\n[1, \0047a\0047]\nfilter saw [1, 2]\nmap\nfilter\nenumerate\nzip\nlist_reverseiterator\n<map\nenum rest [(2, 3)]\nzip rest [(2, \0047b\0047), (3, \0047c\0047)]\nrev rest [2, 1]\n[(1, \0047a\0047), (2, \0047b\0047)]\n[(1, \0047a\0047), (2, \0047b\0047)]\n[3, 2, 1]\n[2, 4, 6]\n12\n1-2-3\n[2, 4]\n200 100')"
	# iter()/next() and the cursor object they return: partial consumption
	# leaves the REST, exhaustion is permanent, iter(iter(x)) is idempotent
	./$(COMPILER) test/test_nilpy_iter_next_cursor.npy /tmp/test_nilpy_itercur26
	test "$$(/tmp/test_nilpy_itercur26)" = "$$(printf '%b' '1\n2\n[3]\n[]\ndone\na b c\nstopped\n[\047a\047, \047b\047]\nTrue\nlist_iterator\n<list_iterator\nNone\n[1, 2, 3, 4]\nparked at 2\nresumed 3\nresumed 4\n[1, 3]\n1 a\n2 b\n0 x\n1 y')"
	./$(COMPILER) test/test_nilpy_sorted_pairs.npy /tmp/test_nilpy_sortpairs26
	test "$$(/tmp/test_nilpy_sortpairs26)" = "$$(printf '%b' '3\nb 1\nc 2\na 3\na 3\nc 2\nb 1\n[1, 2, 3]\nx 1\ny 2\n2 0 3\nbb\nnone\n11\n3')"
	# a comprehension nested in another's element, dict spread, aggregate builtins
	./$(COMPILER) test/test_nilpy_nested_comp.npy /tmp/test_nilpy_nestcomp26
	test "$$(/tmp/test_nilpy_nestcomp26)" = "$$(printf '%b' '2\nab 2\ncd 2\n2 2 2\nx 1\ny 9\nz 3\n3\n3\n14\n5 1\nTrue True False True\n4.0\n28\npear apple')"
	# a Callable parameter on a METHOD is callable in the body
	./$(COMPILER) test/test_nilpy_method_callable_param.npy /tmp/test_nilpy_mcallable26
	test "$$(/tmp/test_nilpy_mcallable26)" = "$$(printf '%b' '2\n[\047p\047, \047p!\047, \047q\047, \047q!\047]\n[\047P\047, \047Q\047]')"
	# the pathlib shim, its `/` operator, and __str__ honoured by str()/print()/f-string
	./$(COMPILER) test/test_nilpy_pathlib.npy /tmp/test_nilpy_pathlib26
	test "$$(/tmp/test_nilpy_pathlib26)" = "$$(printf 'file.txt\nfile\n.txt\ndir/sub\ndir/sub\ndir/sub\nFalse\ndir/sub')"
	# the html and tempfile shims, and an import that is not at the top of the file
	./$(COMPILER) test/test_nilpy_html_tempfile.npy /tmp/test_nilpy_htmltmp26
	test "$$(/tmp/test_nilpy_htmltmp26)" = "$$(printf '%b' '&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;\nit\047s\n<b>&\042AB&nope;\nTrue\n.pdf\nTrue\nFalse')"
	# forwarding a collected *args into a callee with ordinary parameters
	./$(COMPILER) test/test_nilpy_star_forward.npy /tmp/test_nilpy_starfwd26
	test "$$(/tmp/test_nilpy_starfwd26)" = "$$(printf 'UI/size\n1/2\na/b/c')"
	# a method on a dynamically-typed receiver, dispatched across unrelated classes
	./$(COMPILER) test/test_nilpy_dynamic_dispatch.npy /tmp/test_nilpy_dyndisp26
	test "$$(/tmp/test_nilpy_dyndisp26)" = "$$(printf '%b' 'cand3\nx\nsum1.5\ncand3, x, sum1.5\nDET:x')"
	# Python or/and yield an OPERAND; an empty string is falsy
	./$(COMPILER) test/test_nilpy_truthy_value_ops.npy /tmp/test_nilpy_truthy26
	test "$$(/tmp/test_nilpy_truthy26)" = "$$(printf '%b' 'ab\nfallback\n7\n3\nb\n0\nx\nNone\nempty\ncond ok\nempty is falsy\nloop 0\n5')"
	# a class-level `name = <literal>` attribute, and `del <local>`
	./$(COMPILER) test/test_nilpy_class_attr.npy /tmp/test_nilpy_clsattr26
	test "$$(/tmp/test_nilpy_clsattr26)" = "$$(printf '%b' 'note_counting 3 0.5 True\ncadence\nnote_counting 3')"
	# r-prefixed raw strings, and set(iterable)
	./$(COMPILER) test/test_nilpy_raw_string_set.npy /tmp/test_nilpy_rawset26
	test "$$(/tmp/test_nilpy_rawset26)" = "$$(printf '%b' 'C#\n4\nFalse\nd\\d+\n3\n0\n2\n4\n1')"
	# import X as Y (the alias wins over a same-named compiled unit)
	./$(COMPILER) test/test_nilpy_import_alias.npy /tmp/test_nilpy_import_alias26
	test "$$(/tmp/test_nilpy_import_alias26)" = "$$(printf '4\n7\n2')"
	# *args / **kwargs collected on the callee side, and print(*args)
	./$(COMPILER) test/test_nilpy_star_args.npy /tmp/test_nilpy_star_args26
	test "$$(/tmp/test_nilpy_star_args26)" = "$$(printf '%b' '0\n\n4\na 1 2.5 True\n2\n[1, 2] {\047k\047: 1}\np:\np: x 9\n7 0\n7 2\nalpha a\nbeta 2\n1 0 0\n\n1 2 1\n2 3\n[2, 3]\n[]')"
	./$(COMPILER) test/test_nilpy_configparser.npy /tmp/test_nilpy_cfgparse26
	test "$$(/tmp/test_nilpy_cfgparse26)" = "$$(printf 'sections: 2\nhas UI: True has nope: False\nget: 1280x800\ndefault lowercases: True\noption: fontsize = 13\nsubclass keeps case: True\nand rejects folded: False')"
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_subclass_unit_base.npy /tmp/test_nilpy_subbase26
	test "$$(/tmp/test_nilpy_subbase26)" = "$$(printf 'override: KeepCase\ninherited: keepcase')"
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_array_of_const_unit.npy /tmp/test_nilpy_aoc26
	test "$$(/tmp/test_nilpy_aoc26)" = "x:2"
	./$(COMPILER) test/test_nilpy_dict_fromkeys.npy /tmp/test_nilpy_fromkeys26
	test "$$(/tmp/test_nilpy_fromkeys26)" = "$$(printf 'deduped: 3 b a c\nvalue is None: True\nempty: 0')"
	./$(COMPILER) test/test_nilpy_tuple_return.npy /tmp/test_nilpy_tupret26
	test "$$(/tmp/test_nilpy_tupret26)" = "$$(printf 'index: a 2 len: 2\nunpack: a 2\nthree: 3 6 x\none-tuple: 5 1\nsubscript call: 2\niter a\niter 2\nkwonly: 7 z')"
	./$(COMPILER) test/test_nilpy_union_annotation.npy /tmp/test_nilpy_union26
	test "$$(/tmp/test_nilpy_union26)" = "$$(printf 'value: 3\nnone: True\nzero is not None: True 0\nnone is None: True\nunion of two real types keeps the first: 42')"
	./$(COMPILER) test/test_nilpy_dataclass_dict_factory.npy /tmp/test_nilpy_dcdict26
	test "$$(/tmp/test_nilpy_dcdict26)" = "$$(printf 'F 1.5 1 because 7\nfresh per construction: 0 0')"
	./$(COMPILER) test/test_nilpy_counter.npy /tmp/test_nilpy_counter26
	test "$$(/tmp/test_nilpy_counter26)" = "$$(printf 'missing reads zero: 0\nstored: 2 len: 1\nfrom list: 2 1\nafter update: 2 3 1\nmc y 3\nmc x 2\nmc z 1\ntop: y\nkey x 2\nkey y 3\nkey z 1\nas dict: 2')"
	./$(COMPILER) test/test_nilpy_re.npy /tmp/test_nilpy_re26
	test "$$(/tmp/test_nilpy_re26)" = "$$(printf 'match ok: C# C #\nno-match is None ok\nsearch: 123\nfullmatch none: True\nsub: a b c\nsub groupref: Csharp D\nfindall n: 3 C# Db E\nfindall groups n: 3\ncompiled match: True True\ncompiled via module fn: True\nescape ok: True\nstart/stop: 0 2')"
	./$(COMPILER) test/test_nilpy_variant.npy /tmp/test_nilpy_variant26
	test "$$(/tmp/test_nilpy_variant26)" = "$$(printf '5\n3.14\nTrue')"
	./$(COMPILER) test/test_nilpy_class.npy /tmp/test_nilpy_class26
	test "$$(/tmp/test_nilpy_class26)" = "25"
	./$(COMPILER) test/test_nilpy_widen_fix.npy /tmp/test_nilpy_widen_fix26
	# CPython's answer, not pxx's. This expectation used to record 5.0/7.0 —
	# the bug itself, kept green by the test
	# (bug-nilpy-int-prints-as-float-when-the-name-is-widened-later).
	test "$$(/tmp/test_nilpy_widen_fix26)" = "$$(printf '5\n3.14\n7\n2.5')"
	./$(COMPILER) test/test_nilpy_call_return_infer.npy /tmp/test_nilpy_call_return_infer26
	test "$$(/tmp/test_nilpy_call_return_infer26)" = "42"
	./$(COMPILER) test/test_nilpy_c_define_const.npy /tmp/test_nilpy_c_define_const26
	test "$$(/tmp/test_nilpy_c_define_const26)" = "$$(printf '0\n100\n101')"
	./$(COMPILER) test/test_nilpy_c_pointer.npy /tmp/test_nilpy_c_pointer26
	test "$$(/tmp/test_nilpy_c_pointer26)" = "1"
	./$(COMPILER) test/test_nilpy_convert.npy /tmp/test_nilpy_convert26
	test "$$(/tmp/test_nilpy_convert26)" = "$$(printf '3\n42')"
	./$(COMPILER) test/test_nilpy_bool.npy /tmp/test_nilpy_bool26
	test "$$(/tmp/test_nilpy_bool26)" = "$$(printf 'True\nTrue\nTrue\nFalse\nTrue\nTrue\nFalse\nTrue\nFalse\nTrue\nFalse\nFalse\nFalse\nzero is falsy\nfive is truthy')"
	# bool is an int subclass: &/|/^/<</>> on booleans compute, and a
	# PARENTHESIZED comparison next to a bitwise op is accepted (it is what
	# PyBitGuard's own message asks for). Unparenthesized `x & 1 == 1` must
	# still be refused -- that is the precedence typo the guard exists for.
	./$(COMPILER) test/test_nilpy_bitwise_on_booleans.npy /tmp/test_nilpy_bitwise_on_booleans26
	test "$$(/tmp/test_nilpy_bitwise_on_booleans26)" = "$$(printf 'False\nTrue\nTrue\nTrue\nFalse\nTrue\nFalse\n1\n1\n5\n8\n2\n2')"
	# ...and the OTHER half of "bool is an int": True counts as +1, never as
	# OLE's VARIANT_TRUE = -1. The guard for the Pascal side adopting FPC's -1
	# (bug-p-variant-to-int-and-char-conversion-diverges-from-fpc): NilPy must
	# never reach the Pascal VariantToInt64, and pylib used to call it DIRECTLY
	# in four places, walking around the lowering seam that keeps NilPy on
	# pylib's helpers. Counter arithmetic was among them. Diffed against CPython.
	./$(COMPILER) test/test_nilpy_bool_is_an_int_not_ole_minus_one.npy /tmp/test_nilpy_bool_int26
	test "$$(/tmp/test_nilpy_bool_int26)" = "$$(printf '2\n2\n2 1\n3\n2\nTrue 2\n2 1')"
	# Python's dot-edge float spellings `.5` and `5.` (and `.5e3` / `5.e-3`),
	# which the shared Pascal scanner cannot lex -- NilPy has its own lexer.
	./$(COMPILER) test/test_nilpy_dot_edge_float_literals.npy /tmp/test_nilpy_dot_edge_float26
	test "$$(/tmp/test_nilpy_dot_edge_float26)" = "$$(printf '0.5\n5.0\n1.25\n10.0\n500.0\n5000.0\n0.005\n-0.5\n[0.5, 1.5, 2.0]\n4.0\nhalf\n1.5\n0.5\n5.0\n1000.0')"
	# min/max at 3+ positional args fold through the 2-argument overload; the
	# 1-/2-arg forms and a user shadow at the folded arity are untouched.
	# `is` is IDENTITY in Python, never Pascal's `E is TClass` type test -- the
	# ctor on the right must actually RUN (the "ctor N" lines are the proof).
	# @dataclass generates __eq__ over the declared fields (CPython does); a
	# nested dataclass field compares BY VALUE, a hand-written __eq__ wins.
	# float str()/repr() = shortest round-tripping decimal, CPython's rule.
	# Pins two tickets that were fixed by unrelated exact-decimal work with
	# nothing guarding the behaviour; second half asserts float(str(v)) == v.
	./$(COMPILER) test/test_nilpy_float_repr_roundtrip.npy /tmp/test_nilpy_float_repr26
	test "$$(/tmp/test_nilpy_float_repr26)" = "$$(printf '3.3333333333333335\n0.3333333333333333\n0.30000000000000004\n1e-20\n1e-300\n1.23e+18\n-0.0\n0.0\n1e+16\n1e+17\n5e-324\n1.7976931348623157e+308\n2.2250738585072014e-308\n0.1\n0.2\n0.14285714285714285\n0.2857142857142857\n1e+100\n-1e-100\n123456789.12345679\n1.5\n100.0\n0.5\n3.14159265358979\n1e-05\n0.0001\n1000000000000000.0\n1e+21\n1e+22\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue\nTrue')"
	# `obj += n` on a class instance: __iadd__, else __add__ + rebind, else a
	# real TypeError -- all three used to silently leave the name holding 0.
	./$(COMPILER) test/test_nilpy_augmented_assign_class_dunder.npy /tmp/test_nilpy_aug_class26
	test "$$(/tmp/test_nilpy_aug_class26)" = "$$(printf '15\n12\n48\n9\n2\n7\n21\n10\ncaught TypeError\n6\n[1, 2, 3] [1, 2, 3]')"
	# ...and the same on a class-typed FIELD (`h.acc += 5`, `self.acc += k`),
	# which takes a DIFFERENT path: a dotted target is claimed by the shared
	# expression tail before NilPy's own augmented site can see it.
	./$(COMPILER) test/test_nilpy_augmented_assign_class_field.npy /tmp/test_nilpy_aug_field26
	test "$$(/tmp/test_nilpy_aug_field26)" = "$$(printf '105\n103\n309\n44\n4\n12\n15\n14\n56\n28\n38\n11\n[1, 2, 3]\n42\nTypeError')"
	# a NilPy def named like a Pascal intrinsic wins over the intrinsic:
	# sizeof was claimed by ParseFactorCore while high/low/length declined.
	./$(COMPILER) test/test_nilpy_def_shadows_pascal_intrinsic.npy /tmp/test_nilpy_intrinsic26
	test "$$(/tmp/test_nilpy_intrinsic26)" = "$$(printf '10\n4\n2\n6\n105')"
	./$(COMPILER) test/test_nilpy_dataclass_eq.npy /tmp/test_nilpy_dataclass_eq26
	test "$$(/tmp/test_nilpy_dataclass_eq26)" = "$$(printf 'True\nFalse\nFalse\nTrue\nTrue\nFalse\nFalse\nFalse\nFalse\nTrue\nFalse\nFalse\nTrue\nTrue\nFalse\nTrue\nTrue\nFalse\nTrue')"
	./$(COMPILER) test/test_nilpy_is_identity_vs_class_test.npy /tmp/test_nilpy_is_identity26
	test "$$(/tmp/test_nilpy_is_identity26)" = "$$(printf 'ctor 1\n--- is with a construction on the right\nctor 2\nFalse\n--- is not\nctor 3\nTrue\n--- both sides constructed\nctor 4\nctor 5\nFalse\n--- nested in a call, a paren, a list\nctor 6\nFalse\nctor 7\n[False]\nctor 8\nFalse\n--- identity that is actually True\nTrue\nFalse\n--- a different class on the right is still identity, not a type test\nFalse\n--- == still constructs and compares\nctor 9\nFalse')"
	./$(COMPILER) test/test_nilpy_min_max_variadic.npy /tmp/test_nilpy_min_max_variadic26
	test "$$(/tmp/test_nilpy_min_max_variadic26)" = "$$(printf '1\n3\n0\n5\n3\n3.5\n0.5\nc\na\n4 11\n14\n1\n3\n2\n9\no\n100')"
	@# ...and the positional half of the same rule for builtins with NO pylib
	@# proc (ord/chr/abs, name-dispatched intrinsics) and for one whose arity a
	@# def happens to match (set): a call ABOVE the def reaches the builtin.
	./$(COMPILER) test/test_nilpy_def_shadows_builtin_positionally.npy /tmp/test_nilpy_defshadowpos26
	test "$$(/tmp/test_nilpy_defshadowpos26)" = "$$(printf '65\nlate-ord\nB\nlate-chr\n3\nlate-abs\n{1}\nlate-set\n1.5\nlate-float\nFalse\nlate-bool\n1\n100\n11\n7')"
	# for/while `else` (runs when the loop finished WITHOUT a break -- an empty
	# iterable still runs it; a break in a NESTED loop must not skip the outer
	# one's else) and `try ... else` (runs when the body did not raise, before
	# finally, and its own raise escapes this statement's except).
	./$(COMPILER) test/test_nilpy_loop_else.npy /tmp/test_nilpy_loop_else26
	test "$$(/tmp/test_nilpy_loop_else26)" = "$$(printf 'for-else ran\nwhile-else ran\nafter break loop\nm = 2\nempty loop else ran\nouter 1\nouter 2\nouter else ran\nouter else ran, inner skipped\nplain break i = 2\nrange else ran\nrange break i = 1\nfound\nexhausted')"
	./$(COMPILER) test/test_nilpy_try_else.npy /tmp/test_nilpy_try_else26
	test "$$(/tmp/test_nilpy_try_else26)" = "$$(printf 'else ran, x = 1\nhandler ran\nbody\nelse\nfinally\nhandler2\nfinally2\ninner body\nouter handler caught the else'"'"'s raise\nearly\nelse\nplain except still works')"
	./$(COMPILER) test/test_nilpy_membership_bool_return.npy /tmp/test_nilpy_membership_bool_return26
	test "$$(/tmp/test_nilpy_membership_bool_return26)" = "$$(printf 'True\nFalse\nTrue\nTrue\nFalse\nTrue\nTrue\nFalse\nTrue\n3\n3\n3')"
	# a sibling .py MODULE: unit scoping, its own initialisation, both import forms
	./$(COMPILER) test/test_nilpy_py_module_import.npy /tmp/test_nilpy_py_module_import26
	test "$$(/tmp/test_nilpy_py_module_import26)" = "$$(printf 'module init ran\nprogram body\n8\n8\n3 3 b\n9\n7')"
	./$(COMPILER) test/test_nilpy_ast_literal_eval.npy /tmp/test_nilpy_ast_literal26
	test "$$(/tmp/test_nilpy_ast_literal26)" = "$$(printf '0.7 0.7 0.5 3\n42 -3 hi\n2\nTrue None\n1 3')"
	# atexit handlers run at exit (LIFO), io's in-memory buffers behave
	./$(COMPILER) test/test_nilpy_atexit_io.npy /tmp/test_nilpy_atexit_io26
	test "$$(/tmp/test_nilpy_atexit_io26)" = "$$(printf '5 6\nhello world\nhello 5\n world\nseed\nmain done\nsecond ran\nbye ran')"
	# a module whose FIRST line is an import: the pre-scan must not skip it
	./$(COMPILER) test/test_nilpy_module_first_import.npy /tmp/test_nilpy_module_first_import26
	test "$$(/tmp/test_nilpy_module_first_import26)" = "$$(printf 'D\n2')"
	# a dotted package import: dots mangle to underscores, and an unresolved
	# module falls back to the mimic_<module> shim (both import forms)
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_dotted_import.npy /tmp/test_nilpy_dotted_import26
	test "$$(/tmp/test_nilpy_dotted_import26)" = "$$(printf 'hello world\nhello dotted')"
	# --no-shims refuses that substitution, so "no shims" is a checked property
	! ./$(COMPILER) --no-shims -Futest/nilpy_units test/test_nilpy_dotted_import.npy /tmp/test_nilpy_noshims26 > /tmp/test_nilpy_noshims.log 2>&1
	grep -q "no-shims" /tmp/test_nilpy_noshims.log
	# try/except ImportError picks a branch at COMPILE time, both directions
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_fallback_import.npy /tmp/test_nilpy_fallback26
	test "$$(/tmp/test_nilpy_fallback26)" = "hello fallback"
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_fallback_import_try_wins.npy /tmp/test_nilpy_fallback_try26
	test "$$(/tmp/test_nilpy_fallback_try26)" = "hello try branch"
	# an import inside a function body / indented suite (pulled by the
	# pre-scan, so the body's measured extent stays valid)
	./$(COMPILER) examples/tk/import_in_body.npy /tmp/test_nilpy_impbody26
	test "$$(/tmp/test_nilpy_impbody26)" = "$$(printf 'in a suite left\nbefore\nafter both')"
	# star/kwargs METHODS, a nested class, attribute + parenthesised unpack
	# targets, and a dynamic return from a def with defaulted parameters
	./$(COMPILER) test/test_nilpy_star_methods_and_targets.npy /tmp/test_nilpy_starm26
	test "$$(/tmp/test_nilpy_starm26)" = "$$(python3 test/test_nilpy_star_methods_and_targets.npy)"
	# a declared DEFAULT is what the callee runs with — int, str and None,
	# defs and methods, every arity, plus a written None
	./$(COMPILER) test/test_nilpy_default_arguments.npy /tmp/test_nilpy_dfl26
	test "$$(/tmp/test_nilpy_dfl26)" = "$$(python3 test/test_nilpy_default_arguments.npy)"
	# a def reading a module global assigned further down the file
	./$(COMPILER) test/test_nilpy_forward_module_global.npy /tmp/test_nilpy_fwdglob26
	test "$$(/tmp/test_nilpy_fwdglob26)" = "$$(python3 test/test_nilpy_forward_module_global.npy)"
	# the Python json module surface: dumps/loads and dump/load through pathlib
	./$(COMPILER) test/test_nilpy_json_module.npy /tmp/test_nilpy_jsonmod26
	test "$$(/tmp/test_nilpy_jsonmod26)" = "$$(python3 test/test_nilpy_json_module.npy)"
	# .field off a variant when several classes declare it at different offsets
	./$(COMPILER) test/test_nilpy_ambiguous_variant_field.npy /tmp/test_nilpy_ambfld26
	test "$$(/tmp/test_nilpy_ambfld26)" = "$$(python3 test/test_nilpy_ambiguous_variant_field.npy)"
	# class attributes BESIDE an __init__ (applied first, overwritable), and a
	# keyword argument that is not a module assignment
	./$(COMPILER) test/test_nilpy_class_attrs_with_ctor.npy /tmp/test_nilpy_clsattr26
	test "$$(/tmp/test_nilpy_clsattr26)" = "$$(python3 test/test_nilpy_class_attrs_with_ctor.npy)"
	# a dispatched method whose candidates return DIFFERENT classes: the result
	# stays dynamic, so the next call on it dispatches too
	./$(COMPILER) test/test_nilpy_dispatch_result_class.npy /tmp/test_nilpy_dispres26
	test "$$(/tmp/test_nilpy_dispres26)" = "$$(python3 test/test_nilpy_dispatch_result_class.npy)"
	# a comprehension whose target is also its source, float defaults, round()
	# of a dynamic expression, and a nonlocal write reaching the enclosing frame
	./$(COMPILER) test/test_nilpy_selfassigned_comprehension.npy /tmp/test_nilpy_selfcomp26
	test "$$(/tmp/test_nilpy_selfcomp26)" = "$$(python3 test/test_nilpy_selfassigned_comprehension.npy)"
	# a Pascal unit's .Free must finalize managed fields ONCE, not twice
	./$(COMPILER) test/test_nilpy_json_reparse_heap.npy /tmp/test_nilpy_jsonrep26
	test "$$(/tmp/test_nilpy_jsonrep26)" = "$$(python3 test/test_nilpy_json_reparse_heap.npy)"
	# a TUPLE as a dict key must hash by CONTENT, not by the list handle
	./$(COMPILER) test/test_nilpy_tuple_dict_key.npy /tmp/test_nilpy_tupkey26
	test "$$(/tmp/test_nilpy_tupkey26)" = "$$(python3 test/test_nilpy_tuple_dict_key.npy)"
	# a bound method captured inside an imported .py MODULE, not just in main
	./$(COMPILER) -Futest test/test_nilpy_bound_method_in_module.npy /tmp/test_nilpy_boundmod26
	test "$$(/tmp/test_nilpy_boundmod26)" = "$$(printf 'built\nw:3\ncaptured in main\npanel')"
	# a bare name is never a method; str.format with a spec; qualified except
	./$(COMPILER) examples/tk/shadow_format_except.npy /tmp/test_nilpy_sfe26
	test "$$(/tmp/test_nilpy_sfe26)" = "$$(printf 'module function\nTap BPM: 92.5\ncaught: clipboard')"
	# a reserved-word constant (tk.END), a class named like an RTL record
	# (Text), and a property read on a fresh construction (Path(x).name)
	./$(COMPILER) examples/tk/facade_and_paths.npy /tmp/test_nilpy_facade_paths26
	test "$$(/tmp/test_nilpy_facade_paths26)" = "$$(printf 'end\nboth left center\nsong.txt\nsong\n/songs/a/song.pdf\n/songs/a/other.md')"
	# a nested def's result type, and a capture assigned after the nested def
	./$(COMPILER) test/test_nilpy_nested_def_result.npy /tmp/test_nilpy_nestdef26
	test "$$(/tmp/test_nilpy_nestdef26)" = "$$(printf 'big\nbig\n7\nyes\nno')"
	# tuple-vs-variant equality, round(x, n), enumerate() as a value,
	# and the standard exception names
	./$(COMPILER) test/test_nilpy_tuple_eq_round_enum.npy /tmp/test_nilpy_treq26
	test "$$(/tmp/test_nilpy_treq26)" = "$$(printf "miss\nhit\nFalse True\n1.23 2\n{'a': 25.0}\n1 b\n0 a\ncaught: nope")"
	# a string method on the RESULT of an unannotated def
	./$(COMPILER) test/test_nilpy_method_on_call_result.npy /tmp/test_nilpy_mcall26
	test "$$(/tmp/test_nilpy_mcall26)" = "$$(printf "['200', '100']\n640 480\npadded")"
	# an unavailable optional import compiles and fails only if used; map()
	./$(COMPILER) test/test_nilpy_optional_and_map.npy /tmp/test_nilpy_opt_map26
	test "$$(/tmp/test_nilpy_opt_map26)" = "$$(printf "False\n200 100\n['1', '2']\n[1.5, 2.0]")"
	# a mixed-type conditional as a comprehension element, and that
	# comprehension assigned back to the parameter it reads
	./$(COMPILER) test/test_nilpy_ternary_comp.npy /tmp/test_nilpy_ternary_comp26
	test "$$(/tmp/test_nilpy_ternary_comp26)" = "$$(printf "[0, 'x', 2]\n[0, 'x', 2]\n['a', 'b']")"
	# isinstance last in a genexpr filter; f(*[a,b,c]) argument unpacking
	./$(COMPILER) test/test_nilpy_genexp_isinstance_star.npy /tmp/test_nilpy_genexp_star26
	test "$$(/tmp/test_nilpy_genexp_star26)" = "$$(printf '5\n[1, 5, 3]\nTrue\n6\n6')"
	# a C library's names must not shadow a Python module qualifier
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_qualifier_vs_cproc.npy /tmp/test_nilpy_qual_cproc26
	test "$$(/tmp/test_nilpy_qual_cproc26)" = "$$(printf 'main\nbye')"
	# builtin shadowed by a parameter, [::-1] on list and str, the is* predicates
	./$(COMPILER) test/test_nilpy_builtin_shadow_slice.npy /tmp/test_nilpy_bshadow26
	test "$$(/tmp/test_nilpy_bshadow26)" = "$$(printf 'int:7\nother\n[3, 2, 1]\ncba\nTrue False False\nTrue True False\nTrue False\nTrue False')"
	# the process environment, both surfaces (CPython-diffed)
	PXX_ENV_PROBE=hello ./$(COMPILER) test/test_env_pascal.pas /tmp/test_env_pascal26
	test "$$(PXX_ENV_PROBE=hello /tmp/test_env_pascal26)" = "$$(printf 'hello\n[]\ncount ok')"
	./$(COMPILER) test/test_nilpy_environ.npy /tmp/test_nilpy_environ26
	test "$$(PXX_ENV_PROBE=hello /tmp/test_nilpy_environ26)" = "$$(printf 'hello\nNone\nfallback\nhello\ntruthy\nunset is falsey')"
	# the shape real code uses: the try block imports AND sets a flag
	./$(COMPILER) -Futest/nilpy_units test/test_nilpy_fallback_import_mixed.npy /tmp/test_nilpy_fallback_mixed26
	test "$$(/tmp/test_nilpy_fallback_mixed26)" = "$$(printf 'False\nTrue\npresent')"
	# an imported name shadows a builtin only in the module that imported it
	./$(COMPILER) test/test_nilpy_import_scope.npy /tmp/test_nilpy_import_scope26
	test "$$(/tmp/test_nilpy_import_scope26)" = "$$(printf '3\npage.size=A4\n8')"
	# rebinding a name across types widens to a variant, as Python allows
	./$(COMPILER) test/test_nilpy_rebind_type.npy /tmp/test_nilpy_rebind_type26
	test "$$(/tmp/test_nilpy_rebind_type26)" = "$$(printf 'plain string\nholder:one\n43\nback to a string')"
	# ...and rebinding across two UNRELATED CLASSES widens too: keeping one
	# static class read the other's fields at the wrong offset (SIGSEGV).
	# Includes the subclass-refinement control that must NOT widen.
	./$(COMPILER) test/test_nilpy_rebind_across_unrelated_classes.npy /tmp/test_nilpy_rebind_cls26
	/tmp/test_nilpy_rebind_cls26 | diff -u test/test_nilpy_rebind_across_unrelated_classes.expected -
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
	test "$$(/tmp/test_float_write26)" = "$$(printf '3.50\n4\n-2.750\n1.0\n0.00\n10.5\n 1.0000000000000000E+000\n-2.0000000000000000E+000\n 0.0000000000000000E+000\n 3.5000000000000000E+000\n 1.2345000000000000E+003')"
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
	# Self-host chain. Every stage compiles to a PID-unique temp name and
	# rename(2)s it into place, never onto the path the next line execs.
	# The names here are fixed (/tmp/pascal26-self, -next, -fixedpoint), so two
	# jobs of one testmgr run — or a dev `make` and the watcher in plain /tmp —
	# share them: one process writing the path another is about to exec is
	# ETXTBSY, "Text file busy", a red that has nothing to do with the code
	# (observed twice on 2026-08-02, test-core and test-smoke). rename() is
	# atomic within a filesystem and gives the path a fresh inode, so an exec
	# sees a complete binary or the previous one, never a half-written file
	# somebody holds a write fd to. Source and destination MUST stay on one
	# filesystem — across one, mv degrades to copy-in-place and reintroduces
	# exactly the window this closes.
	./$(COMPILER) $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-self.$$$$.tmp && mv -f /tmp/pascal26-self.$$$$.tmp /tmp/pascal26-self
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
	/tmp/pascal26-self $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-next.$$$$.tmp && mv -f /tmp/pascal26-next.$$$$.tmp /tmp/pascal26-next
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
	/tmp/pascal26-next $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-fixedpoint.$$$$.tmp && mv -f /tmp/pascal26-fixedpoint.$$$$.tmp /tmp/pascal26-fixedpoint
	cmp /tmp/pascal26-next /tmp/pascal26-fixedpoint
	./$(COMPILER) $(PXXFLAGS) --threadsafe $(COMPILER_SRC) /tmp/pascal26-threadsafe-self.$$$$.tmp && mv -f /tmp/pascal26-threadsafe-self.$$$$.tmp /tmp/pascal26-threadsafe-self
	/tmp/pascal26-threadsafe-self $(PXXFLAGS) --threadsafe $(COMPILER_SRC) /tmp/pascal26-threadsafe-next.$$$$.tmp && mv -f /tmp/pascal26-threadsafe-next.$$$$.tmp /tmp/pascal26-threadsafe-next
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
	# a Variant holding a CLASS, and the unbox back to a scalar: both halves
	# were x86-64-only gaps, so every target must print the same line
	./$(COMPILER) --target=i386 test/test_variant_class_cross.pas /tmp/test_i386_varcls
	test "$$(tools/run_target.sh i386 /tmp/test_i386_varcls)" = "end 7 100"
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
	# string[N] truncation incl. a heap record holding a shortstring field reached
	# through a pointer (bug-cross-pointer-store-record-with-shortstring-field)
	./$(COMPILER) --target=i386 test/test_shortstring_trunc.pas /tmp/test_i386_sstrunc
	./$(COMPILER) test/test_shortstring_trunc.pas /tmp/test_i386_sstrunc_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_sstrunc)" = "$$(/tmp/test_i386_sstrunc_x64)"
	# Int64/QWord -> Double at full 64-bit width incl. unsigned top-bit values
	# (bug-cross-32bit-int64-to-double-low-word / bug-pascal-qword-to-double-signed)
	./$(COMPILER) --target=i386 test/test_u64_to_double.pas /tmp/test_i386_u64d
	./$(COMPILER) test/test_u64_to_double.pas /tmp/test_i386_u64d_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_u64d)" = "$$(/tmp/test_i386_u64d_x64)"
	# {$$Q+} add/sub/unsigned-mul raise catchable EIntOverflow (signed checked
	# MUL stays deferred on 32-bit pairs — feature-overflow-checks-cross-and-intrinsics)
	./$(COMPILER) --target=i386 test/test_overflow_checks_qplus.pas /tmp/test_i386_qplus
	test "$$(tools/run_target.sh i386 /tmp/test_i386_qplus)" = "$$(printf 'wrapped 0\ncaught=4')"
	./$(COMPILER) --target=i386 test/test_overflow_qplus_narrow.pas /tmp/test_i386_qplus_narrow
	test "$$(tools/run_target.sh i386 /tmp/test_i386_qplus_narrow)" = "$$(printf 'caught=5 clean=4 wrap=-294967296')"
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
	# cdecl indirect call (dlsym'd C fn through a cdecl proc-type value) — b362
	# libc-free signal handlers on i386 (b371): hook fires + program RESUMES;
	# no hook = revert to SIG_DFL + re-raise (dies 143).
	./$(COMPILER) --target=i386 -Fulib/rtl test/test_signal_handler_callback_b336.pas /tmp/test_i386_sigcb
	test "$$(tools/run_target.sh i386 /tmp/test_i386_sigcb)" = "$$(printf 'hits=2\nresumed after handler')"
	./$(COMPILER) --target=i386 -Fulib/rtl test/test_signal_default_revert_b336.pas /tmp/test_i386_sigdfl
	tools/run_target.sh i386 /tmp/test_i386_sigdfl > /dev/null 2>&1; test "$$?" = "143"
	# SA_SIGINFO: si_code/si_addr/ucontext* reach Pascal. si_addr is asserted
	# against the address the program itself faulted on (union at 12 on ILP32,
	# not 16), and the negative SI_TKILL is the sign canary. The callback test
	# above is the OTHER half of the acceptance here: setting SA_SIGINFO flips
	# i386's frame shape, so a program that still resumes after its hook proves
	# the restorer's TWO coupled changes (119->173, and dropping the plain
	# frame's `pop eax`) both landed with it.
	./$(COMPILER) --target=i386 test/test_signal_siginfo.pas /tmp/test_i386_siginfo
	test "$$(tools/run_target.sh i386 /tmp/test_i386_siginfo)" = "$$(printf 'segv code=1\nsegv addr=3735879680\nctx set=TRUE\nusr1 code=-6\nstage=2')"
	# PC rewrite: the handler points the saved ucontext PC at a Pascal proc
	# that raises, and the fault is caught by the try/except the faulting
	# code was already inside. The pc-is-the-fault line is the exact check
	# of the per-arch PC offset -- rewriting the wrong ucontext word would
	# clobber an unrelated register instead.
	./$(COMPILER) --target=i386 test/test_signal_pc_rewrite.pas /tmp/test_i386_pcrw
	test "$$(tools/run_target.sh i386 /tmp/test_i386_pcrw)" = "$$(printf 'pc-is-the-fault=TRUE\ncode=1 addr=3735879680\ncaught a fault as an exception, hits=1\nand execution continued')"
	./$(COMPILER) --target=i386 test/test_cdecl_indirect.pas /tmp/test_i386_cdeclind
	test "$$(tools/run_target.sh i386 /tmp/test_i386_cdeclind)" = "$$(printf '4.0\n1024.0\n12.0')"
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
	# parallel for + full capture (scalar/array/record/string) — data-parallel loop on i386
	./$(COMPILER) --threadsafe --target=i386 test/test_parallel_for_lang.pas /tmp/test_i386_parfor
	test "$$(tools/run_target.sh i386 /tmp/test_i386_parfor | tail -n 1)" = "PARFORLANG OK"
	./$(COMPILER) --threadsafe --target=i386 test/test_parallel_for_capture_aggr.pas /tmp/test_i386_parcap
	test "$$(tools/run_target.sh i386 /tmp/test_i386_parcap | tail -n 1)" = "PARFORAGGR OK"
	./$(COMPILER) --threadsafe --target=i386 test/test_parallel_for_capture_string.pas /tmp/test_i386_parstr
	test "$$(tools/run_target.sh i386 /tmp/test_i386_parstr | tail -n 1)" = "PARFORSTR OK"
	# scheduling policy + reduction + named-arg clause on i386 (Track T cross gate)
	./$(COMPILER) --threadsafe --target=i386 test/test_parallel_policy.pas /tmp/test_i386_parpol
	test "$$(tools/run_target.sh i386 /tmp/test_i386_parpol)" = "PARPOL OK"
	./$(COMPILER) --threadsafe --target=i386 test/test_parallel_policy_lang.pas /tmp/test_i386_parpollang
	test "$$(tools/run_target.sh i386 /tmp/test_i386_parpollang)" = "PARPOLLANG OK"
	./$(COMPILER) --threadsafe --target=i386 test/test_parallel_reduction.pas /tmp/test_i386_parred
	test "$$(tools/run_target.sh i386 /tmp/test_i386_parred)" = "PARRED OK"
	./$(COMPILER) --threadsafe --target=i386 test/test_parallel_policy_named.pas /tmp/test_i386_parnamed
	test "$$(tools/run_target.sh i386 /tmp/test_i386_parnamed)" = "PARNAMED OK"
	./$(COMPILER) --threadsafe --target=i386 test/test_parallel_writeln_atomic.pas /tmp/test_i386_pwa
	tools/run_target.sh i386 /tmp/test_i386_pwa > /tmp/test_i386_pwa.out
	test "$$(tail -n1 /tmp/test_i386_pwa.out)" = "PARWROK"
	test "$$(grep -cE '^A{49}-1[0-9]{3}-B{49}$$' /tmp/test_i386_pwa.out)" = "200"
	test "$$(grep -oE '\-1[0-9]{3}\-' /tmp/test_i386_pwa.out | sort -u | wc -l)" = "200"
	@echo "i386 hello + arith + procs + loops + write + varparam + syscall + heap + string + record + dynarray + exception + float + float-params + variant + variant-single + byref-params + setlen-str + setlen-varparam + in-operator + loadfile + sysopen-family + args + string-cow + frozen-strlen-deref + rec-arr-store + aoc-types + many-params + conformance2 + shortcircuit + ptr-arith + case-range + global-init + typed-const + multidim + named-array + record-2darray + param-2darray + multidim3d + const-alias + float-const + stackless-generator + proctype + scheduler + scheduler-exc + classes + method-pointers + aggregate-return + metaclass-rtti + rtti-typinfo + streaming + streaming-enumset + lfm + interfaces + dynarray-field + nested-dynarray-setlen + method-implicit-field + forin-implicit-field + dynarray-global-after-method + forin-member-access + call-result-member + collections + timer + reactor + asyncecho + extern-c + extern-c-float + c-entry + c-args + c-double-to-int + readln + eof-stdin ok (output identical to x86-64)"

test-aarch64: $(COMPILER)
	./$(COMPILER) --target=aarch64 test/hello.pas /tmp/test_aarch64_hello
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_hello)" = "Hello, World!"
	# a Variant holding a CLASS, and the unbox back to a scalar: both halves
	# were x86-64-only gaps, so every target must print the same line
	./$(COMPILER) --target=aarch64 test/test_variant_class_cross.pas /tmp/test_aarch64_varcls
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_varcls)" = "end 7 100"
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
	# string[N] truncation incl. a heap record holding a shortstring field reached
	# through a pointer (bug-cross-pointer-store-record-with-shortstring-field)
	./$(COMPILER) --target=aarch64 test/test_shortstring_trunc.pas /tmp/test_aarch64_sstrunc
	./$(COMPILER) test/test_shortstring_trunc.pas /tmp/test_aarch64_sstrunc_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_sstrunc)" = "$$(/tmp/test_aarch64_sstrunc_x64)"
	# Int64/QWord -> Double at full 64-bit width incl. unsigned top-bit values
	# (bug-cross-32bit-int64-to-double-low-word / bug-pascal-qword-to-double-signed)
	./$(COMPILER) --target=aarch64 test/test_u64_to_double.pas /tmp/test_aarch64_u64d
	./$(COMPILER) test/test_u64_to_double.pas /tmp/test_aarch64_u64d_x64
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_u64d)" = "$$(/tmp/test_aarch64_u64d_x64)"
	# {$$Q+} overflow-checked arithmetic raises catchable EIntOverflow (aarch64 leg)
	./$(COMPILER) --target=aarch64 test/test_overflow_checks_qplus.pas /tmp/test_aarch64_qplus
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_qplus)" = "$$(printf 'wrapped 0\ncaught=4')"
	./$(COMPILER) --target=aarch64 test/test_overflow_qplus_narrow.pas /tmp/test_aarch64_qplus_narrow
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_qplus_narrow)" = "$$(printf 'caught=5 clean=4 wrap=-294967296')"
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
	# libc-free signal handlers on aarch64 (b370): hook fires + program RESUMES;
	# no hook = revert to SIG_DFL + re-raise (dies 143). arm64 has NO sa_restorer
	# and puts sa_mask at offset 16 — its own port, not a copy of the x86-64 one.
	./$(COMPILER) --target=aarch64 -Fulib/rtl test/test_signal_handler_callback_b336.pas /tmp/test_aarch64_sigcb
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_sigcb)" = "$$(printf 'hits=2\nresumed after handler')"
	./$(COMPILER) --target=aarch64 -Fulib/rtl test/test_signal_default_revert_b336.pas /tmp/test_aarch64_sigdfl
	tools/run_target.sh aarch64 /tmp/test_aarch64_sigdfl > /dev/null 2>&1; test "$$?" = "143"
	# SA_SIGINFO: si_code/si_addr/ucontext* reach Pascal. si_addr is asserted
	# against the address the program itself faulted on, so a wrong union offset
	# (16 here, 12 on ILP32) cannot pass; the negative SI_TKILL is the sign canary.
	./$(COMPILER) --target=aarch64 test/test_signal_siginfo.pas /tmp/test_aarch64_siginfo
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_siginfo)" = "$$(printf 'segv code=1\nsegv addr=3735879680\nctx set=TRUE\nusr1 code=-6\nstage=2')"
	# PC rewrite: the handler points the saved ucontext PC at a Pascal proc
	# that raises, and the fault is caught by the try/except the faulting
	# code was already inside. The pc-is-the-fault line is the exact check
	# of the per-arch PC offset -- rewriting the wrong ucontext word would
	# clobber an unrelated register instead.
	./$(COMPILER) --target=aarch64 test/test_signal_pc_rewrite.pas /tmp/test_aarch64_pcrw
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_pcrw)" = "$$(printf 'pc-is-the-fault=TRUE\ncode=1 addr=3735879680\ncaught a fault as an exception, hits=1\nand execution continued')"
	# cdecl indirect call (dlsym'd C fn through a cdecl proc-type value) — b362
	./$(COMPILER) --target=aarch64 test/test_cdecl_indirect.pas /tmp/test_aarch64_cdeclind
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_cdeclind)" = "$$(printf '4.0\n1024.0\n12.0')"
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
	# parallel for + capture on aarch64. Multi-aggregate capture bus-errored until
	# bug-a-parallel-for-aarch64-multi-capture: BSS base was not 8-aligned, so the
	# --threadsafe I/O lock's 64-bit ldaxr SIGBUS'd for some CodeLen parities.
	./$(COMPILER) --threadsafe --target=aarch64 test/test_parallel_for_lang.pas /tmp/test_aarch64_parfor
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_parfor | tail -n 1)" = "PARFORLANG OK"
	./$(COMPILER) --threadsafe --target=aarch64 test/test_parallel_for_capture.pas /tmp/test_aarch64_parcap
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_parcap | tail -n 1)" = "PARFORCAP OK"
	./$(COMPILER) --threadsafe --target=aarch64 test/test_parallel_for_capture_aggr.pas /tmp/test_aarch64_parcapaggr
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_parcapaggr | tail -n 1)" = "PARFORAGGR OK"
	./$(COMPILER) --threadsafe --target=aarch64 test/test_parallel_for_capture_string.pas /tmp/test_aarch64_parcapstr
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_parcapstr | tail -n 1)" = "PARFORSTR OK"
	# scheduling policy + reduction + named-arg clause on aarch64 (Track T cross gate)
	./$(COMPILER) --threadsafe --target=aarch64 test/test_parallel_policy.pas /tmp/test_aarch64_parpol
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_parpol)" = "PARPOL OK"
	./$(COMPILER) --threadsafe --target=aarch64 test/test_parallel_policy_lang.pas /tmp/test_aarch64_parpollang
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_parpollang)" = "PARPOLLANG OK"
	./$(COMPILER) --threadsafe --target=aarch64 test/test_parallel_reduction.pas /tmp/test_aarch64_parred
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_parred)" = "PARRED OK"
	./$(COMPILER) --threadsafe --target=aarch64 test/test_parallel_policy_named.pas /tmp/test_aarch64_parnamed
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_parnamed)" = "PARNAMED OK"
	./$(COMPILER) --threadsafe --target=aarch64 test/test_parallel_writeln_atomic.pas /tmp/test_aarch64_pwa
	tools/run_target.sh aarch64 /tmp/test_aarch64_pwa > /tmp/test_aarch64_pwa.out
	test "$$(tail -n1 /tmp/test_aarch64_pwa.out)" = "PARWROK"
	test "$$(grep -cE '^A{49}-1[0-9]{3}-B{49}$$' /tmp/test_aarch64_pwa.out)" = "200"
	test "$$(grep -oE '\-1[0-9]{3}\-' /tmp/test_aarch64_pwa.out | sort -u | wc -l)" = "200"
	@echo "aarch64 hello + arith + procs + loops + write + varparam + syscall + heap + string + record + dynarray + exception + float + variant + variant-single + setlen-str + setlen-varparam + str-length-index + in-operator + loadfile + sysopen-family + args + open-array-params + string-cow + frozen-strlen-deref + rec-arr-store + huge-frame + varrec-alloc + aoc-types + many-params + conformance2 + shortcircuit + ptr-arith + case-range + global-init + typed-const + multidim + named-array + record-2darray + param-2darray + multidim3d + const-alias + float-const + classes + method-pointers + aggregate-return + metaclass-rtti + rtti-typinfo + streaming + streaming-enumset + lfm + interfaces + dynarray-field + nested-dynarray-setlen + method-implicit-field + forin-implicit-field + dynarray-global-after-method + forin-member-access + call-result-member + collections + timer + reactor + asyncecho + extern-c + extern-c-float + c-entry + c-args + c-double-to-int + readln + eof-stdin ok (output identical to x86-64)"

test-riscv32: $(COMPILER)
	# frozen inline strings (string[N]): riscv32 had NO frozen store, no frozen Length
	# and no frozen->managed arg materialisation, so this printed len=0 and segfaulted.
	# Output must match the x86-64 oracle exactly (b345)
	./$(COMPILER) --target=riscv32 test/test_frozen_string_cross_b305.pas /tmp/test_riscv32_frozen
	tools/run_target.sh riscv32 /tmp/test_riscv32_frozen > /tmp/test_riscv32_frozen.out
	test "$$(cat /tmp/test_riscv32_frozen.out)" = "$$(printf 'len=5\nf=hello\nassigned=hello len=5\nbyvalue=5\nfirst=h\nderef=hello\nderef-arg=5\nre-len=2 re=hi re-arg=2')"
	# string[N] truncation incl. a heap record holding a shortstring field reached
	# through a pointer (bug-cross-pointer-store-record-with-shortstring-field)
	./$(COMPILER) --target=riscv32 test/test_shortstring_trunc.pas /tmp/test_riscv32_sstrunc
	./$(COMPILER) test/test_shortstring_trunc.pas /tmp/test_riscv32_sstrunc_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_sstrunc)" = "$$(/tmp/test_riscv32_sstrunc_x64)"
	# Int64/QWord -> Double at full 64-bit width incl. unsigned top-bit values
	# (bug-cross-32bit-int64-to-double-low-word / bug-pascal-qword-to-double-signed)
	./$(COMPILER) --target=riscv32 test/test_u64_to_double.pas /tmp/test_riscv32_u64d
	./$(COMPILER) test/test_u64_to_double.pas /tmp/test_riscv32_u64d_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_u64d)" = "$$(/tmp/test_riscv32_u64d_x64)"
	# {$$Q+} add/sub/unsigned-mul raise catchable EIntOverflow (riscv32 full for
	# the unsigned rows; signed checked MUL stays deferred on 32-bit pairs)
	./$(COMPILER) --target=riscv32 test/test_overflow_checks_qplus.pas /tmp/test_riscv32_qplus
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_qplus)" = "$$(printf 'wrapped 0\ncaught=4')"
	./$(COMPILER) --target=riscv32 test/test_overflow_qplus_narrow.pas /tmp/test_riscv32_qplus_narrow
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_qplus_narrow)" = "$$(printf 'caught=5 clean=4 wrap=-294967296')"
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
	# libc-free signal handlers on riscv32 (b371): hook fires + program RESUMES;
	# no hook = revert to SIG_DFL + re-raise (dies 143).
	./$(COMPILER) --target=riscv32 -Fulib/rtl test/test_signal_handler_callback_b336.pas /tmp/test_riscv32_sigcb
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_sigcb)" = "$$(printf 'hits=2\nresumed after handler')"
	./$(COMPILER) --target=riscv32 -Fulib/rtl test/test_signal_default_revert_b336.pas /tmp/test_riscv32_sigdfl
	tools/run_target.sh riscv32 /tmp/test_riscv32_sigdfl > /dev/null 2>&1; test "$$?" = "143"
	# SA_SIGINFO: si_code/si_addr/ucontext* reach Pascal. si_addr is asserted
	# against the address the program itself faulted on — on ILP32 the siginfo
	# preamble is NOT padded, so the union starts at 12, not 16; this is what
	# measured that. The negative SI_TKILL is the sign canary.
	./$(COMPILER) --target=riscv32 test/test_signal_siginfo.pas /tmp/test_riscv32_siginfo
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_siginfo)" = "$$(printf 'segv code=1\nsegv addr=3735879680\nctx set=TRUE\nusr1 code=-6\nstage=2')"
	# PC rewrite: the handler points the saved ucontext PC at a Pascal proc
	# that raises, and the fault is caught by the try/except the faulting
	# code was already inside. The pc-is-the-fault line is the exact check
	# of the per-arch PC offset -- rewriting the wrong ucontext word would
	# clobber an unrelated register instead.
	./$(COMPILER) --target=riscv32 test/test_signal_pc_rewrite.pas /tmp/test_riscv32_pcrw
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_pcrw)" = "$$(printf 'pc-is-the-fault=TRUE\ncode=1 addr=3735879680\ncaught a fault as an exception, hits=1\nand execution continued')"
	# by-value record params over 4 bytes (up to 8): both words must cross
	# (they silently truncated to word 1 -- bug-riscv32-byval-record-param-one-word)
	./$(COMPILER) --target=riscv32 test/test_arm32_record_byval_wide.pas /tmp/test_riscv32_recwide
	test "$$(tools/run_target.sh riscv32 /tmp/test_riscv32_recwide)" = "$$(printf '1 2\n1 2\n111 222\n1 7 8 2\n1 2 3 4 7 8\n1 2 3 7 8\n1 2 3 4 5 7 8\n200 7\ndone')"
	# managed-record operator chain (TBigInt: Boolean + dynarray = 8 bytes byval)
	./$(COMPILER) --target=riscv32 -Fulib/rtl test/lib_bignum_ops.pas /tmp/test_riscv32_bignum
	tools/run_target.sh riscv32 /tmp/test_riscv32_bignum > /tmp/test_riscv32_bignum.out
	./$(COMPILER) -Fulib/rtl test/lib_bignum_ops.pas /tmp/test_riscv32_bignum_x64
	/tmp/test_riscv32_bignum_x64 > /tmp/test_riscv32_bignum_x64.out
	diff /tmp/test_riscv32_bignum_x64.out /tmp/test_riscv32_bignum.out
	# ---- shared Pascal cross battery (mirrors test-arm32; bug-test-riscv32-thin-coverage).
	#      SKIP lines are explicit feature gaps, not silent omissions.
	./$(COMPILER) --target=riscv32 test/hello.pas /tmp/test_rv32x_hello
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_hello)" = "Hello, World!"
	# inline expansion (feature-inline-routines): -O2 == -O0 on this cross target.
	./$(COMPILER) --target=riscv32 test/test_inline_expand.pas /tmp/test_rv32x_inl_o0
	./$(COMPILER) --target=riscv32 -O2 test/test_inline_expand.pas /tmp/test_rv32x_inl_o2
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_inl_o0)" = "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_inl_o2)"
	./$(COMPILER) --target=riscv32 test/test_record_temp_byval_arg.pas /tmp/test_rv32x_rectemp
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_rectemp)" = "$$(printf '18\n46')"
	./$(COMPILER) --target=riscv32 test/test_ctor_string_literal_arg.pas /tmp/test_rv32x_ctorstrlit
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_ctorstrlit)" = "$$(printf 'field:hello\nc1\nafter1\nc2\nafter2\nc3\nc4\nafter3\nmsg:hello\nafter4')"
	# SKIP test/test_arm32_virtual_wide.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	./$(COMPILER) --target=riscv32 test/test_single_in_aggregate.pas /tmp/test_rv32x_singleagg
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_singleagg)" = "$$(printf '1.5 2.5 3.5\n9.500 8.250 7.125\n2.0 4.0 6.0\n10.0')"
	./$(COMPILER) --target=riscv32 test/test_i386_arith.pas /tmp/test_rv32x_arith
	./$(COMPILER) test/test_i386_arith.pas /tmp/test_rv32x_arith_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_arith)" = "$$(/tmp/test_rv32x_arith_x64)"
	./$(COMPILER) --target=riscv32 test/test_i386_procs.pas /tmp/test_rv32x_procs
	./$(COMPILER) test/test_i386_procs.pas /tmp/test_rv32x_procs_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_procs)" = "$$(/tmp/test_rv32x_procs_x64)"
	./$(COMPILER) --target=riscv32 test/test_i386_loops.pas /tmp/test_rv32x_loops
	./$(COMPILER) test/test_i386_loops.pas /tmp/test_rv32x_loops_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_loops)" = "$$(/tmp/test_rv32x_loops_x64)"
	./$(COMPILER) --target=riscv32 test/test_i386_write.pas /tmp/test_rv32x_write
	./$(COMPILER) test/test_i386_write.pas /tmp/test_rv32x_write_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_write)" = "$$(/tmp/test_rv32x_write_x64)"
	./$(COMPILER) --target=riscv32 test/test_i386_varparam.pas /tmp/test_rv32x_varparam
	./$(COMPILER) test/test_i386_varparam.pas /tmp/test_rv32x_varparam_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_varparam)" = "$$(/tmp/test_rv32x_varparam_x64)"
	# SKIP test/test_cross_syscall.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	./$(COMPILER) --target=riscv32 test/test_cross_heap.pas /tmp/test_rv32x_heap
	./$(COMPILER) test/test_cross_heap.pas /tmp/test_rv32x_heap_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_heap)" = "$$(/tmp/test_rv32x_heap_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_cross_string.pas /tmp/test_rv32x_string
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_string.pas /tmp/test_rv32x_string_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_string)" = "$$(/tmp/test_rv32x_string_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_cross_record.pas /tmp/test_rv32x_record
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_record.pas /tmp/test_rv32x_record_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_record)" = "$$(/tmp/test_rv32x_record_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_cross_dynarray.pas /tmp/test_rv32x_dynarray
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_dynarray.pas /tmp/test_rv32x_dynarray_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_dynarray)" = "$$(/tmp/test_rv32x_dynarray_x64)"
	# UN-SKIPPED 2026-08-07: the gap was IR_SETLEN_DYN handing PXXDynSetLen the
	# array's HANDLE instead of its slot address, so SetLength on a nested array
	# silently did nothing (bug-a-riscv32-nested-dynamic-array-element-write-segfaults).
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_nested_dynarray_setlen.pas /tmp/test_rv32x_nestsetlen
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_nested_dynarray_setlen.pas /tmp/test_rv32x_nestsetlen_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_nestsetlen)" = "$$(/tmp/test_rv32x_nestsetlen_x64)"
	@# ...and the whole-array assignment battery, whose AliasesNested case is the
	@# same shape; deliberately not wired before, because it landed red on the above.
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_dynarray_whole_assign.pas /tmp/test_rv32x_dynwhole
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_dynarray_whole_assign.pas /tmp/test_rv32x_dynwhole_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_dynwhole)" = "$$(/tmp/test_rv32x_dynwhole_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_exception.pas /tmp/test_rv32x_exception
	./$(COMPILER) test/test_cross_exception.pas /tmp/test_rv32x_exception_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_exception)" = "$$(/tmp/test_rv32x_exception_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_float.pas /tmp/test_rv32x_float
	./$(COMPILER) test/test_cross_float.pas /tmp/test_rv32x_float_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_float)" = "$$(/tmp/test_rv32x_float_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_float_return.pas /tmp/test_rv32x_fret
	./$(COMPILER) test/test_cross_float_return.pas /tmp/test_rv32x_fret_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_fret)" = "$$(/tmp/test_rv32x_fret_x64)"
	./$(COMPILER) --target=riscv32 test/test_arm32_arg_runtime.pas /tmp/test_rv32x_args
	./$(COMPILER) test/test_arm32_arg_runtime.pas /tmp/test_rv32x_args_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_args alpha beta)" = "$$(/tmp/test_rv32x_args_x64 alpha beta)"
	# SKIP test/test_cross_variant.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_cross_variant_single.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	./$(COMPILER) --target=riscv32 test/test_cross_strresult.pas /tmp/test_rv32x_strresult
	./$(COMPILER) test/test_cross_strresult.pas /tmp/test_rv32x_strresult_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_strresult)" = "$$(/tmp/test_rv32x_strresult_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_cross_setlen_str.pas /tmp/test_rv32x_setlen_str
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_setlen_str.pas /tmp/test_rv32x_setlen_str_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_setlen_str)" = "$$(/tmp/test_rv32x_setlen_str_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_cross_setlen_varparam.pas /tmp/test_rv32x_setlen_vp
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_setlen_varparam.pas /tmp/test_rv32x_setlen_vp_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_setlen_vp)" = "$$(/tmp/test_rv32x_setlen_vp_x64)"
	# SKIP test/test_cross_frozen_strlen_deref.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	./$(COMPILER) --target=riscv32 test/test_managed_strlen_deref.pas /tmp/test_rv32x_managed_strlen
	./$(COMPILER) test/test_managed_strlen_deref.pas /tmp/test_rv32x_managed_strlen_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_managed_strlen)" = "$$(/tmp/test_rv32x_managed_strlen_x64)"
	./$(COMPILER) --target=riscv32 test/test_not_int64_expr.pas /tmp/test_rv32x_not64
	./$(COMPILER) test/test_not_int64_expr.pas /tmp/test_rv32x_not64_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_not64)" = "$$(/tmp/test_rv32x_not64_x64)"
	./$(COMPILER) --target=riscv32 test/test_uint32_write.pas /tmp/test_rv32x_u32w
	./$(COMPILER) test/test_uint32_write.pas /tmp/test_rv32x_u32w_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_u32w)" = "$$(/tmp/test_rv32x_u32w_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_cross_record_array_store.pas /tmp/test_rv32x_rec_arr_store
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_record_array_store.pas /tmp/test_rv32x_rec_arr_store_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_rec_arr_store)" = "$$(/tmp/test_rv32x_rec_arr_store_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_cross_str_length_index.pas /tmp/test_rv32x_str_li
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_str_length_index.pas /tmp/test_rv32x_str_li_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_str_li)" = "$$(/tmp/test_rv32x_str_li_x64)"
	# SKIP test/test_cross_in_operator.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_cross_managed_aggregate_locals.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_cross_loadfile.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_cross_sysopen_family.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_cross_string_cow.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_cross_var_string_param.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_cross_openarray_string.pas /tmp/test_rv32x_openarray_string
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_openarray_string.pas /tmp/test_rv32x_openarray_string_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_openarray_string)" = "$$(/tmp/test_rv32x_openarray_string_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_cross_stack_params.pas /tmp/test_rv32x_stack_params
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_stack_params.pas /tmp/test_rv32x_stack_params_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_stack_params)" = "$$(/tmp/test_rv32x_stack_params_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_int64.pas /tmp/test_rv32x_int64
	./$(COMPILER) test/test_cross_int64.pas /tmp/test_rv32x_int64_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_int64)" = "$$(/tmp/test_rv32x_int64_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_cross_int64_byref.pas /tmp/test_rv32x_int64_byref
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_int64_byref.pas /tmp/test_rv32x_int64_byref_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_int64_byref)" = "$$(/tmp/test_rv32x_int64_byref_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_array_of_const_types.pas /tmp/test_rv32x_aoc_types
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_array_of_const_types.pas /tmp/test_rv32x_aoc_types_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_aoc_types)" = "$$(/tmp/test_rv32x_aoc_types_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_cross_write_pchar.pas /tmp/test_rv32x_write_pchar
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_cross_write_pchar.pas /tmp/test_rv32x_write_pchar_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_write_pchar)" = "$$(/tmp/test_rv32x_write_pchar_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_static_open_array.pas /tmp/test_rv32x_static_open
	./$(COMPILER) test/test_cross_static_open_array.pas /tmp/test_rv32x_static_open_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_static_open)" = "$$(/tmp/test_rv32x_static_open_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_many_params.pas /tmp/test_rv32x_many_params
	./$(COMPILER) test/test_cross_many_params.pas /tmp/test_rv32x_many_params_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_many_params)" = "$$(/tmp/test_rv32x_many_params_x64)"
	./$(COMPILER) --target=riscv32 test/test_conformance_2.pas /tmp/test_rv32x_conf2
	./$(COMPILER) test/test_conformance_2.pas /tmp/test_rv32x_conf2_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_conf2)" = "$$(/tmp/test_rv32x_conf2_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_shortcircuit.pas /tmp/test_rv32x_scx
	./$(COMPILER) test/test_cross_shortcircuit.pas /tmp/test_rv32x_scx_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_scx)" = "$$(/tmp/test_rv32x_scx_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_ptr_arith.pas /tmp/test_rv32x_pa
	./$(COMPILER) test/test_cross_ptr_arith.pas /tmp/test_rv32x_pa_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_pa)" = "$$(/tmp/test_rv32x_pa_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_case_range.pas /tmp/test_rv32x_cr
	./$(COMPILER) test/test_cross_case_range.pas /tmp/test_rv32x_cr_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_cr)" = "$$(/tmp/test_rv32x_cr_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_global_init.pas /tmp/test_rv32x_gi
	./$(COMPILER) test/test_cross_global_init.pas /tmp/test_rv32x_gi_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_gi)" = "$$(/tmp/test_rv32x_gi_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_typed_const.pas /tmp/test_rv32x_tc
	./$(COMPILER) test/test_cross_typed_const.pas /tmp/test_rv32x_tc_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_tc)" = "$$(/tmp/test_rv32x_tc_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_multidim.pas /tmp/test_rv32x_md
	./$(COMPILER) test/test_cross_multidim.pas /tmp/test_rv32x_md_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_md)" = "$$(/tmp/test_rv32x_md_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_named_array.pas /tmp/test_rv32x_na
	./$(COMPILER) test/test_cross_named_array.pas /tmp/test_rv32x_na_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_na)" = "$$(/tmp/test_rv32x_na_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_record_2darray.pas /tmp/test_rv32x_r2
	./$(COMPILER) test/test_cross_record_2darray.pas /tmp/test_rv32x_r2_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_r2)" = "$$(/tmp/test_rv32x_r2_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_param_2darray.pas /tmp/test_rv32x_pa2
	./$(COMPILER) test/test_cross_param_2darray.pas /tmp/test_rv32x_pa2_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_pa2)" = "$$(/tmp/test_rv32x_pa2_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_multidim3d.pas /tmp/test_rv32x_d3
	./$(COMPILER) test/test_cross_multidim3d.pas /tmp/test_rv32x_d3_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_d3)" = "$$(/tmp/test_rv32x_d3_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_const_alias.pas /tmp/test_rv32x_ca
	./$(COMPILER) test/test_cross_const_alias.pas /tmp/test_rv32x_ca_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_ca)" = "$$(/tmp/test_rv32x_ca_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_float_const.pas /tmp/test_rv32x_fc
	./$(COMPILER) test/test_cross_float_const.pas /tmp/test_rv32x_fc_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_fc)" = "$$(/tmp/test_rv32x_fc_x64)"
	# SKIP test/test_scheduler.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_scheduler_exc.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	./$(COMPILER) --target=riscv32 test/test_async_sl.pas /tmp/test_rv32x_asl
	./$(COMPILER) test/test_async_sl.pas /tmp/test_rv32x_asl_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_asl)" = "$$(/tmp/test_rv32x_asl_x64)"
	# SKIP test/test_channel.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	./$(COMPILER) --target=riscv32 test/test_methodptr.pas /tmp/test_rv32x_mptr
	./$(COMPILER) test/test_methodptr.pas /tmp/test_rv32x_mptr_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_mptr)" = "$$(/tmp/test_rv32x_mptr_x64)"
	./$(COMPILER) --target=riscv32 test/test_methcall.pas /tmp/test_rv32x_mcall
	./$(COMPILER) test/test_methcall.pas /tmp/test_rv32x_mcall_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_mcall)" = "$$(/tmp/test_rv32x_mcall_x64)"
	./$(COMPILER) --target=riscv32 test/test_cross_sets.pas /tmp/test_rv32x_sets
	./$(COMPILER) test/test_cross_sets.pas /tmp/test_rv32x_sets_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_sets)" = "$$(/tmp/test_rv32x_sets_x64)"
	# SKIP test/test_classref.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_class_of.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_rtti.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_streaming.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_streaming_enumset.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_lfm.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	./$(COMPILER) --target=riscv32 test/test_interfaces.pas /tmp/test_rv32x_iface
	./$(COMPILER) test/test_interfaces.pas /tmp/test_rv32x_iface_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_iface)" = "$$(/tmp/test_rv32x_iface_x64)"
	# SKIP test/test_interface_arc.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	./$(COMPILER) --target=riscv32 test/test_uint64_ops.pas /tmp/test_rv32x_u64
	./$(COMPILER) test/test_uint64_ops.pas /tmp/test_rv32x_u64_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_u64)" = "$$(/tmp/test_rv32x_u64_x64)"
	# SKIP test/test_interfaces_is.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_interfaces_as.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_interfaces_param.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_interfaces_inherit.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	./$(COMPILER) --target=riscv32 test/test_interfaces_multi_secondary.pas /tmp/test_rv32x_iface_multi
	./$(COMPILER) test/test_interfaces_multi_secondary.pas /tmp/test_rv32x_iface_multi_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_iface_multi)" = "$$(/tmp/test_rv32x_iface_multi_x64)"
	# SKIP test/test_cross_aggregate_return.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	./$(COMPILER) --target=riscv32 test/test_cross_aggregate_stackargs.pas /tmp/test_rv32x_aggstk
	./$(COMPILER) test/test_cross_aggregate_stackargs.pas /tmp/test_rv32x_aggstk_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_aggstk)" = "$$(/tmp/test_rv32x_aggstk_x64)"
	./$(COMPILER) --target=riscv32 test/test_inheritance_dispatch.pas /tmp/test_rv32x_cls
	./$(COMPILER) test/test_inheritance_dispatch.pas /tmp/test_rv32x_cls_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_cls)" = "$$(/tmp/test_rv32x_cls_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_dynarray_field.pas /tmp/test_rv32x_dynfield
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_dynarray_field.pas /tmp/test_rv32x_dynfield_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_dynfield)" = "$$(/tmp/test_rv32x_dynfield_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_method_implicit_field.pas /tmp/test_rv32x_mif
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_method_implicit_field.pas /tmp/test_rv32x_mif_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_mif)" = "$$(/tmp/test_rv32x_mif_x64)"
	# SKIP test/test_forin_implicit_field.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_dynarray_global_after_method.pas /tmp/test_rv32x_dgam
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_dynarray_global_after_method.pas /tmp/test_rv32x_dgam_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_dgam)" = "$$(/tmp/test_rv32x_dgam_x64)"
	# SKIP test/test_forin_member_access.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_call_result_member.pas /tmp/test_rv32x_crm
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_call_result_member.pas /tmp/test_rv32x_crm_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_crm)" = "$$(/tmp/test_rv32x_crm_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_collections.pas /tmp/test_rv32x_collections
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_collections.pas /tmp/test_rv32x_collections_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_collections)" = "$$(/tmp/test_rv32x_collections_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_const_record_temp.pas /tmp/test_rv32x_constrectemp
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_const_record_temp.pas /tmp/test_rv32x_constrectemp_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_constrectemp)" = "$$(/tmp/test_rv32x_constrectemp_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_const_record_temp_managed.pas /tmp/test_rv32x_constrectemp_managed
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_const_record_temp_managed.pas /tmp/test_rv32x_constrectemp_managed_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_constrectemp_managed)" = "$$(/tmp/test_rv32x_constrectemp_managed_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_set_runtime.pas /tmp/test_rv32x_setrt
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_set_runtime.pas /tmp/test_rv32x_setrt_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_setrt)" = "$$(/tmp/test_rv32x_setrt_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_managed_record_temp_init.pas /tmp/test_rv32x_mrti
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_managed_record_temp_init.pas /tmp/test_rv32x_mrti_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_mrti)" = "$$(/tmp/test_rv32x_mrti_x64)"
	./$(COMPILER) -dPXX_MANAGED_STRING --target=riscv32 test/test_dynarray_copy.pas /tmp/test_rv32x_dyncopy
	./$(COMPILER) -dPXX_MANAGED_STRING test/test_dynarray_copy.pas /tmp/test_rv32x_dyncopy_x64
	test "$$(tools/run_target.sh riscv32 /tmp/test_rv32x_dyncopy)" = "$$(/tmp/test_rv32x_dyncopy_x64)"
	# SKIP test/test_timer.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_reactor.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_asyncecho.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_extern_c.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	# SKIP test/test_extern_c_float.pas on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	./$(COMPILER) --target=riscv32 test/ccross_entry.c /tmp/test_rv32x_centry
	tools/run_target.sh riscv32 /tmp/test_rv32x_centry; test "$$?" = "42"
	./$(COMPILER) --target=riscv32 test/ccross_args.c /tmp/test_rv32x_cargs
	tools/run_target.sh riscv32 /tmp/test_rv32x_cargs; test "$$?" = "42"
	./$(COMPILER) --target=riscv32 test/ccross_double_to_int.c /tmp/test_rv32x_cd2i
	tools/run_target.sh riscv32 /tmp/test_rv32x_cd2i; test "$$?" = "42"
	./$(COMPILER) --target=riscv32 test/test_readln.pas /tmp/test_rv32x_readln
	./$(COMPILER) test/test_readln.pas /tmp/test_rv32x_readln_x64
	test "$$(printf '100 200 300\n42\n10 20\nhello world\nQ\nSKIP\n-5\n' | tools/run_target.sh riscv32 /tmp/test_rv32x_readln)" = "$$(printf '100 200 300\n42\n10 20\nhello world\nQ\nSKIP\n-5\n' | /tmp/test_rv32x_readln_x64)"
	./$(COMPILER) --target=riscv32 test/test_eof_stdin.pas /tmp/test_rv32x_eof
	./$(COMPILER) test/test_eof_stdin.pas /tmp/test_rv32x_eof_x64
	test "$$(printf 'alpha\nbeta\ngamma' | tools/run_target.sh riscv32 /tmp/test_rv32x_eof)" = "$$(printf 'alpha\nbeta\ngamma' | /tmp/test_rv32x_eof_x64)"
	./$(COMPILER) --target=riscv32 test/cunsigned_int_arith_b121.c /tmp/test_rv32x_cuarith
	tools/run_target.sh riscv32 /tmp/test_rv32x_cuarith; test "$$?" = "42"
	./$(COMPILER) --target=riscv32 test/cunsigned_semantics_sweep_b138.c /tmp/test_rv32x_cusweep
	tools/run_target.sh riscv32 /tmp/test_rv32x_cusweep; test "$$?" = "42"
	# SKIP test/cunsigned_div_mod_b123.c on riscv32: backend feature gap (see bug-test-riscv32-thin-coverage notes)
	@echo "riscv32 c-entry + c-args + c-double-to-int + c-unsigned-arith + c-unsigned-div + hello + stackless-generator + readln + eof-stdin + exception + args + typed-const + global-init + set-param + inline-asm + record-byval-wide + bignum-ops + shared-pascal-battery ok"

test-arm32: $(COMPILER)
	./$(COMPILER) --target=arm32 test/hello.pas /tmp/test_arm32_hello
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_hello)" = "Hello, World!"
	# a Variant holding a CLASS, and the unbox back to a scalar: both halves
	# were x86-64-only gaps, so every target must print the same line
	./$(COMPILER) --target=arm32 test/test_variant_class_cross.pas /tmp/test_arm32_varcls
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_varcls)" = "end 7 100"
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
	# string[N] truncation incl. a heap record holding a shortstring field reached
	# through a pointer (bug-cross-pointer-store-record-with-shortstring-field)
	./$(COMPILER) --target=arm32 test/test_shortstring_trunc.pas /tmp/test_arm32_sstrunc
	./$(COMPILER) test/test_shortstring_trunc.pas /tmp/test_arm32_sstrunc_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_sstrunc)" = "$$(/tmp/test_arm32_sstrunc_x64)"
	# Int64/QWord -> Double at full 64-bit width incl. unsigned top-bit values
	# (bug-cross-32bit-int64-to-double-low-word / bug-pascal-qword-to-double-signed)
	./$(COMPILER) --target=arm32 test/test_u64_to_double.pas /tmp/test_arm32_u64d
	./$(COMPILER) test/test_u64_to_double.pas /tmp/test_arm32_u64d_x64
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_u64d)" = "$$(/tmp/test_arm32_u64d_x64)"
	# {$$Q+} add/sub/unsigned-mul raise catchable EIntOverflow (signed checked
	# MUL stays deferred on 32-bit pairs — feature-overflow-checks-cross-and-intrinsics)
	./$(COMPILER) --target=arm32 test/test_overflow_checks_qplus.pas /tmp/test_arm32_qplus
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_qplus)" = "$$(printf 'wrapped 0\ncaught=4')"
	./$(COMPILER) --target=arm32 test/test_overflow_qplus_narrow.pas /tmp/test_arm32_qplus_narrow
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_qplus_narrow)" = "$$(printf 'caught=5 clean=4 wrap=-294967296')"
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
	# cdecl indirect call (dlsym'd C fn through a cdecl proc-type value) — b362
	# libc-free signal handlers on arm32 (b371): hook fires + program RESUMES;
	# no hook = revert to SIG_DFL + re-raise (dies 143).
	./$(COMPILER) --target=arm32 -Fulib/rtl test/test_signal_handler_callback_b336.pas /tmp/test_arm32_sigcb
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_sigcb)" = "$$(printf 'hits=2\nresumed after handler')"
	./$(COMPILER) --target=arm32 -Fulib/rtl test/test_signal_default_revert_b336.pas /tmp/test_arm32_sigdfl
	tools/run_target.sh arm32 /tmp/test_arm32_sigdfl > /dev/null 2>&1; test "$$?" = "143"
	# SA_SIGINFO: si_code/si_addr/ucontext* reach Pascal. si_addr is asserted
	# against the address the program itself faulted on (union at 12 on ILP32,
	# not 16), and the negative SI_TKILL is the sign canary. The callback test
	# above is the OTHER half of the acceptance here: setting SA_SIGINFO flips
	# arm32's frame shape, so a program that still resumes after its hook proves
	# the restorer's sigreturn->rt_sigreturn flip landed with it.
	./$(COMPILER) --target=arm32 test/test_signal_siginfo.pas /tmp/test_arm32_siginfo
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_siginfo)" = "$$(printf 'segv code=1\nsegv addr=3735879680\nctx set=TRUE\nusr1 code=-6\nstage=2')"
	# PC rewrite: the handler points the saved ucontext PC at a Pascal proc
	# that raises, and the fault is caught by the try/except the faulting
	# code was already inside. The pc-is-the-fault line is the exact check
	# of the per-arch PC offset -- rewriting the wrong ucontext word would
	# clobber an unrelated register instead.
	./$(COMPILER) --target=arm32 test/test_signal_pc_rewrite.pas /tmp/test_arm32_pcrw
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_pcrw)" = "$$(printf 'pc-is-the-fault=TRUE\ncode=1 addr=3735879680\ncaught a fault as an exception, hits=1\nand execution continued')"
	./$(COMPILER) --target=arm32 test/test_cdecl_indirect.pas /tmp/test_arm32_cdeclind
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_cdeclind)" = "$$(printf '4.0\n1024.0\n12.0')"
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
	# parallel for + full capture (scalar/array/record/string) — data-parallel loop on arm32
	./$(COMPILER) --threadsafe --target=arm32 test/test_parallel_for_lang.pas /tmp/test_arm32_parfor
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_parfor | tail -n 1)" = "PARFORLANG OK"
	./$(COMPILER) --threadsafe --target=arm32 test/test_parallel_for_capture_aggr.pas /tmp/test_arm32_parcap
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_parcap | tail -n 1)" = "PARFORAGGR OK"
	./$(COMPILER) --threadsafe --target=arm32 test/test_parallel_for_capture_string.pas /tmp/test_arm32_parstr
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_parstr | tail -n 1)" = "PARFORSTR OK"
	# scheduling policy + reduction + named-arg clause on arm32 (Track T cross gate)
	./$(COMPILER) --threadsafe --target=arm32 test/test_parallel_policy.pas /tmp/test_arm32_parpol
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_parpol)" = "PARPOL OK"
	./$(COMPILER) --threadsafe --target=arm32 test/test_parallel_policy_lang.pas /tmp/test_arm32_parpollang
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_parpollang)" = "PARPOLLANG OK"
	./$(COMPILER) --threadsafe --target=arm32 test/test_parallel_reduction.pas /tmp/test_arm32_parred
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_parred)" = "PARRED OK"
	./$(COMPILER) --threadsafe --target=arm32 test/test_parallel_policy_named.pas /tmp/test_arm32_parnamed
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_parnamed)" = "PARNAMED OK"
	./$(COMPILER) --threadsafe --target=arm32 test/test_parallel_writeln_atomic.pas /tmp/test_arm32_pwa
	tools/run_target.sh arm32 /tmp/test_arm32_pwa > /tmp/test_arm32_pwa.out
	test "$$(tail -n1 /tmp/test_arm32_pwa.out)" = "PARWROK"
	test "$$(grep -cE '^A{49}-1[0-9]{3}-B{49}$$' /tmp/test_arm32_pwa.out)" = "200"
	test "$$(grep -oE '\-1[0-9]{3}\-' /tmp/test_arm32_pwa.out | sort -u | wc -l)" = "200"
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

# test-sqlite-external-vs-self-compiled-parity: the same deterministic
# CREATE TABLE / INSERT / SELECT ... ORDER BY workload run through TWO
# independent SQLite builds and diffed byte-for-byte:
#   1. test/test_sqlite_parity_external.pas  — the external libsqlite3.so.0
#      import path (`uses sqlite3`, the same binding test_sqlite_crud.pas /
#      test_sqlite_crud_autotyped.pas use).
#   2. test/csqlite_parity_selfcompiled.c    — a self-compiled unity build of
#      library_candidates/sqlite/sqlite3.c (the amalgamation) over the
#      libc-free crtl, same shape as csqlite_file_probe.c/csqlite_thread_test.c.
# Both databases are :memory: (no /tmp file, no cross-run race). Skips when
# the gitignored sqlite amalgamation is absent, like test-cjson/test-sqlite-
# threads. NOT in `make test` (large 3rd-party build); run explicitly.
test-sqlite-parity: $(COMPILER)
	@if [ ! -f "$(SQLITE_SRC)/sqlite3.c" ]; then \
	  echo "test-sqlite-parity: SKIP — no sqlite amalgamation at $(SQLITE_SRC)/sqlite3.c"; \
	  exit 0; \
	fi; \
	wd="$$(mktemp -d)"; trap 'rm -rf "$$wd"' EXIT; \
	echo "test-sqlite-parity: building external-libsqlite3 path (Pascal, uses sqlite3) ..."; \
	./$(COMPILER) test/test_sqlite_parity_external.pas "$$wd/ext" || exit 1; \
	echo "test-sqlite-parity: building self-compiled amalgamation path (C, sqlite3.c unity build) ..."; \
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src -I$(SQLITE_SRC) \
	  test/csqlite_parity_selfcompiled.c "$$wd/self" || exit 1; \
	"$$wd/ext" > "$$wd/ext.out" || exit 1; \
	"$$wd/self" > "$$wd/self.out" || exit 1; \
	if diff -u "$$wd/ext.out" "$$wd/self.out" > "$$wd/diff.txt"; then \
	  echo "test-sqlite-parity: PASS — external libsqlite3.so.0 and self-compiled amalgamation agree byte-for-byte"; \
	else \
	  echo "test-sqlite-parity: FAIL — external vs self-compiled output differs"; \
	  cat "$$wd/diff.txt"; \
	  exit 1; \
	fi

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
# needs gcc). PASSING as of 2026-08-09 — byte-identical to the gcc oracle,
# verified against the pinned compiler. The "currently blocked, two compiler
# blockers" note that used to be here was stale; both are fixed.
ZLIB_SRC ?= library_candidates/zlib
test-zlib: $(COMPILER)
	@if [ ! -f "$(ZLIB_SRC)/zlib.h" ]; then \
	  echo "test-zlib: SKIP — no zlib tree at $(ZLIB_SRC) (tools/install_lib_candidates.sh zlib)"; \
	  exit 0; \
	fi; \
	command -v gcc >/dev/null 2>&1 || { echo "test-zlib: SKIP — gcc oracle not found"; exit 0; }; \
	echo "building gcc oracle ..."; \
	gcc -w -DHAVE_UNISTD_H -I$(ZLIB_SRC) -o /tmp/pxx_zlib_oracle \
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
# Duktape (embeddable JS engine) curated smoke — GC + IEEE-754 double semantics
# (feature-c-corpus-duktape). Unity build of crtl + the duktape 2.7.0 amalgamation
# + test/duktape/duk_smoke.c; stdout byte-compared against duk_smoke.expected
# (itself verified byte-identical to a gcc-built duk_smoke's output) and exit 42
# required. Skips if the gitignored tree is absent
# (tools/install_lib_candidates.sh duktape). NOT in `make test` (3rd-party).
DUKTAPE_SRC ?= library_candidates/duktape/src
test-duktape: $(COMPILER)
	@if [ ! -f "$(DUKTAPE_SRC)/duktape.c" ]; then \
	  echo "test-duktape: SKIP — no duktape tree at $(DUKTAPE_SRC) (tools/install_lib_candidates.sh duktape)"; \
	  exit 0; \
	fi; \
	echo "compiling duktape smoke ..."; \
	wd="$$(mktemp -d)"; trap 'rm -rf "$$wd"' EXIT; \
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src -I$(DUKTAPE_SRC) \
	  test/duktape/duk_smoke.c "$$wd/duk_smoke" > /dev/null || exit 1; \
	"$$wd/duk_smoke" > "$$wd/got.txt" 2>&1; rc=$$?; \
	if [ "$$rc" != "42" ]; then \
	  echo "test-duktape: FAIL — exit $$rc (want 42)"; tail -5 "$$wd/got.txt"; exit 1; \
	fi; \
	if diff -u test/duktape/duk_smoke.expected "$$wd/got.txt" > "$$wd/diff.txt"; then \
	  echo "test-duktape: PASS — curated JS smoke byte-exact"; \
	else \
	  echo "test-duktape: FAIL — output mismatch"; head -12 "$$wd/diff.txt"; exit 1; \
	fi

# QuickJS-ng (real JS engine, ~85k lines plain C99) curated smoke — the
# feature-c-corpus-quickjs gate. Unity build (test/quickjs/runner.c: EMSCRIPTEN
# switch-dispatch profile + __TINYC__ 32-bit limbs); evals test/quickjs/smoke.js
# and byte-compares stdout against smoke.expected (verified byte-identical to a
# gcc-built runner's output). Exercises JSValue struct returns through
# fn-pointer tables, exact number->string, closures/prototypes/GC/JSON/regex.
# Skips if the gitignored tree is absent (tools/install_lib_candidates.sh quickjs).
# NOT in `make test` (3rd-party).
# Second case: a real pure-compute JS library (js-sha256 v0.11.1, vendored via
# tools/install_lib_candidates.sh js-sha256) run under the compiled qjs with a
# known-answer-test driver (test/quickjs/sha256_driver.js — NIST FIPS 180-4 /
# RFC 4231 vectors); stdout byte-compared against sha256.expected (generated
# from the gcc-built runner, all-PASS verified against the published vectors).
QUICKJS_SRC ?= library_candidates/quickjs
JSSHA256_SRC ?= library_candidates/js-sha256
test-quickjs: $(COMPILER)
	@if [ ! -f "$(QUICKJS_SRC)/quickjs.c" ]; then \
	  echo "test-quickjs: SKIP — no quickjs tree at $(QUICKJS_SRC) (tools/install_lib_candidates.sh quickjs)"; \
	  exit 0; \
	fi; \
	echo "compiling quickjs runner ..."; \
	wd="$$(mktemp -d)"; trap 'rm -rf "$$wd"' EXIT; \
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src -I$(QUICKJS_SRC) \
	  test/quickjs/runner.c "$$wd/qjs" > /dev/null || exit 1; \
	"$$wd/qjs" "$$(cat test/quickjs/smoke.js)" > "$$wd/got.txt" 2>&1; rc=$$?; \
	if [ "$$rc" != "0" ]; then \
	  echo "test-quickjs: FAIL — exit $$rc"; tail -5 "$$wd/got.txt"; exit 1; \
	fi; \
	if diff -u test/quickjs/smoke.expected "$$wd/got.txt" > "$$wd/diff.txt"; then \
	  echo "test-quickjs: PASS — curated JS smoke byte-exact"; \
	else \
	  echo "test-quickjs: FAIL — output mismatch"; head -12 "$$wd/diff.txt"; exit 1; \
	fi; \
	if [ ! -f "$(JSSHA256_SRC)/src/sha256.js" ]; then \
	  echo "test-quickjs: SKIP library case — no js-sha256 at $(JSSHA256_SRC) (tools/install_lib_candidates.sh js-sha256)"; \
	  exit 0; \
	fi; \
	{ printf 'var window = globalThis;\n'; \
	  cat "$(JSSHA256_SRC)/src/sha256.js" test/quickjs/sha256_driver.js; } > "$$wd/sha256_cat.js"; \
	"$$wd/qjs" "$$(cat "$$wd/sha256_cat.js")" > "$$wd/sha_got.txt" 2>&1; rc=$$?; \
	if [ "$$rc" != "0" ]; then \
	  echo "test-quickjs: FAIL — sha256 library exit $$rc"; tail -5 "$$wd/sha_got.txt"; exit 1; \
	fi; \
	if diff -u test/quickjs/sha256.expected "$$wd/sha_got.txt" > "$$wd/diff2.txt"; then \
	  echo "test-quickjs: PASS — js-sha256 library KAT byte-exact (13 vectors)"; \
	else \
	  echo "test-quickjs: FAIL — js-sha256 output mismatch"; head -12 "$$wd/diff2.txt"; exit 1; \
	fi

# fcl-json's own 203-case suite (fpjson + fpcunit, FPC release_3_2_2 sources)
# under a pxx-built runner — the strongest OOP/RTL exerciser in the Pascal
# corpus (feature-fpjson-fpcunit-suite-target). Track B shape: builds with
# $(PXX_STABLE), never rebuilds the compiler. Stages upstream sources flat into
# a temp dir (unit resolution wants one dir; -Fu order alone is insufficient)
# with our test/fpjson/testutils.pas SHADOWING upstream testutils.pp, then runs
# test/fpjson/tjrun.pp (walks the registry itself — the ITestListener interface
# dispatch has a separate open bug). Asserts 203 run / 0 failures / 0 errors.
# Skips if the gitignored tree is absent (tools/install_lib_candidates.sh fcl-json).
FCLJSON_SRC ?= library_candidates/fcl-json/packages
test-fpjson:
	@test -x $(PXX_STABLE) || { echo "test-fpjson: no stable compiler at $(PXX_STABLE)"; exit 1; }
	@if [ ! -f "$(FCLJSON_SRC)/fcl-json/src/fpjson.pp" ]; then \
	  echo "test-fpjson: SKIP — no fcl-json tree at $(FCLJSON_SRC) (tools/install_lib_candidates.sh fcl-json)"; \
	  exit 0; \
	fi; \
	wd="$$(mktemp -d)"; trap 'rm -rf "$$wd"' EXIT; \
	root="$$(pwd)"; \
	for d in fcl-json/src fcl-json/tests fcl-fpcunit/src; do \
	  for f in "$$root/$(FCLJSON_SRC)/$$d"/*; do \
	    case "$$(basename "$$f")" in testutils.pp) continue ;; esac; \
	    ln -sf "$$f" "$$wd/"; \
	  done; \
	done; \
	cp test/fpjson/testutils.pas test/fpjson/tjrun.pp "$$wd/"; \
	echo "compiling fpjson suite runner ..."; \
	( cd "$$wd" && "$$root/$(PXX_STABLE)" --mimic-fpc \
	    -Fu"$$root/lib/rtl" -Fu"$$root/lib/rtl/platform/posix" \
	    tjrun.pp "$$wd/tjrun" ) > /dev/null || exit 1; \
	"$$wd/tjrun" > "$$wd/out.txt" 2>&1; rc=$$?; \
	tail -1 "$$wd/out.txt"; \
	if [ "$$rc" = "0" ] && grep -q "run: 203  failures: 0  errors: 0" "$$wd/out.txt"; then \
	  echo "test-fpjson: PASS — 203/203"; \
	else \
	  echo "test-fpjson: FAIL (exit $$rc)"; tail -12 "$$wd/out.txt"; exit 1; \
	fi

# uforth (a real Python Forth VM, ~4300 lines single-file + layered .UFO stdlib)
# compiled UNMODIFIED as Nil-Python — the Track N forcing corpus
# (feature-nilpy-corpus-uforth). Smoke: uforth.py compiles, STD.UFO loads, and
# both NATIVE and PYTHON-bodied stdlib words evaluate — `1 2 + .` (native `+`) and
# `10 3 / .` (`/` is a PYTHON block, exec'd via the pyeval bridge + bound-method
# env) — expecting "3" then "3", clean exit. Skips if the tree is absent:
#   git clone git@github.com:yoctobyte/uforth ~/projects/uforth
UFORTH_SRC ?= $(HOME)/projects/uforth
# uforth's OWN corpora, run DIFFERENTIALLY: the same uforth.py under CPython is
# the oracle, so there is nothing recorded here to go stale when uforth moves.
# The smoke above proves it boots; these prove it computes.
#
# tests/_drv_file.fth is deliberately ABSENT — it is the one file still
# differing (the ANS FILE word set: uforth's two same-named w_include nested
# defs, and `1+` unresolved inside an INCLUDEd helper). Listed by name in
# bug-nilpy-uforth-file-word-set-include-redefinition rather than silently
# skipped, so adding it back is the gate for that ticket.
# The `tests/_drv_*.fth` drivers are DELIBERATELY not here. They were local
# debugging scratch on one box — never committed to uforth, absent from its git
# history entirely — so every clone reported "6 of 10 corpora absent" for files
# that were never going to arrive (user, 2026-08-08). Track T wants regression
# signal, not somebody's debug wrappers: (a) that uforth compiles and runs, and
# (b) Gerry Jackson's Forth 2012 suite in `tests/`, which is the real corpus and
# is measured per word set in bug-nilpy-uforth-ans-word-set-suite-4-of-13-open.
# That suite is now enrolled below (UFORTH_WORDSETS), all 13 word sets green.
UFORTH_CORPUS ?= testje.for testjefixed.for testjefix2.for testjefix3.for
# Gerry Jackson's Forth 2012 / ANS suite, one entry per WORD SET. These files
# are tracked in uforth, so every clone has them — unlike the old `_drv_*.fth`
# wrappers, which existed on one box and nowhere else.
#
# Each needs a driver that INCLUDEs the four harness files and then the word
# set. The driver has to live INSIDE the uforth tree: INCLUDED resolves through
# uforth's own resolve_path, so a driver in a scratch dir cannot reach
# prelimtest.fth. So the recipe GENERATES one per word set into
# $(UFORTH_SRC)/tests/ and deletes it again (the EXIT trap covers an
# interrupted run too). Nothing is left behind and uforth needs no commit.
#
# THE NAME CARRIES THE PID, and the trap's glob is scoped to that pid. It used
# to be `_pxxdrv_<wordset>.fth` with a trap of `rm -rf .../_pxxdrv_*.fth`, and
# $(UFORTH_SRC) is ONE tree shared by every clone on the box — the dev checkout
# and the watcher's. So two concurrent `make test-uforth` runs wrote the same
# filenames, and whichever finished first deleted the other's in-flight drivers
# with that glob. Observed 2026-08-08: a manual run and the watcher's full tier
# overlapped, and the watcher published test-uforth#00 as a RED that was purely
# the collision.
#
# The trap also catches INT/TERM/HUP, not just EXIT. A bare `trap ... EXIT` does
# NOT run when the shell is killed by an untrapped signal, so every timed-out or
# Ctrl-C'd run leaked its drivers into somebody else's tree — there was a
# `_pxxdrv_blocktest.fth.fth` sitting in $(UFORTH_SRC)/tests from an earlier
# kill when this was found.
#
# A trap cannot be the whole answer, because SIGKILL is not trappable and that
# is exactly how testmgr ends a job past its budget. Measured 2026-08-11: **87
# leaked drivers**, 71 of them blocktest — which was independent evidence of
# which word set kept being killed, before anything was timed. So the recipe
# also SWEEPS on entry: any `_pxxdrv_<pid>_*` whose creating pid is gone is
# removed. Scoped by liveness rather than by age or a bare glob, because a
# concurrent run's drivers are live and deleting those is the collision this
# whole naming scheme exists to prevent. (PID reuse can spare a stale file for
# one more sweep; harmless.)
#
# COST: blocktest is by far the slowest — ~240s under pxx against CPython's
# ~80s, because it is a memory-walk and hash workload. The other twelve
# together are seconds. Whoever tunes tier placement should know the ~6 minutes
# is almost entirely that one file.
#
# SHARDING (feature-t-shard-the-uforth-ans-suite-per-word-set). Both lists are
# `?=`, so testmgr shards this target by OVERRIDING them on the make command
# line — `make test-uforth UFORTH_CORPUS= UFORTH_WORDSETS=blocktest.fth` is one
# shard. That is why each loop tolerates an EMPTY list (`for f in $(LIST) ""`
# plus a skip): a shard that runs only word sets passes an empty UFORTH_CORPUS,
# and a bare `for f in ; do` is a shell syntax error, not an empty loop.
#
# The compile + smoke prologue (~28s) is paid by EVERY shard, since each is an
# independent `make` with its own scratch dir. That is the deliberate trade:
# ~28s x N of otherwise-idle CPU buys a wall time bounded by the SLOWEST WORD
# SET instead of their SUM, on a box sized for 12 concurrent jobs.
#
# The pxx run and the CPython oracle are INDEPENDENT — same inputs, different
# runtimes — so they run CONCURRENTLY and are joined by `wait`. That takes the
# oracle off the critical path everywhere (~80s of blocktest's ~320s). Their
# outputs go to separate files and both read `in.txt` through their own
# redirection, so there is nothing shared to race on. Deliberately NOT cached
# across runs: a stale oracle turns a real regression into a false green, which
# is the one failure mode this whole differential exists to prevent.
UFORTH_WORDSETS ?= core.fr coreplustest.fth doubletest.fth exceptiontest.fth \
                   facilitytest.fth localstest.fth memorytest.fth \
                   searchordertest.fth stringtest.fth coreexttest.fth \
                   blocktest.fth toolstest.fth filetest.fth
test-uforth: $(COMPILER)
	@if [ ! -f "$(UFORTH_SRC)/uforth.py" ]; then \
	  echo "test-uforth: SKIP — no uforth tree at $(UFORTH_SRC) (git clone git@github.com:yoctobyte/uforth $(UFORTH_SRC))"; \
	  exit 0; \
	fi; \
	wd="$$(mktemp -d)"; \
	trap 'rm -rf "$$wd" "$(UFORTH_SRC)"/tests/_pxxdrv_$$$$_*.fth' EXIT INT TERM HUP; \
	root="$$(pwd)"; \
	for d in "$(UFORTH_SRC)"/tests/_pxxdrv_*.fth; do \
	  [ -e "$$d" ] || continue; \
	  p="$${d##*/_pxxdrv_}"; p="$${p%%_*}"; \
	  kill -0 "$$p" 2>/dev/null || rm -f "$$d"; \
	done; \
	echo "compiling uforth.py as Nil-Python ..."; \
	"$$root/$(COMPILER)" "$(UFORTH_SRC)/uforth.py" "$$wd/uforth" > /dev/null || \
	  { echo "test-uforth: FAIL — uforth.py did not compile"; exit 1; }; \
	printf '1 2 + .\n10 3 / .\nBYE\n' | ( cd "$(UFORTH_SRC)" && timeout 60 "$$wd/uforth" ) > "$$wd/out.txt" 2>&1; rc=$$?; \
	if [ "$$rc" != "0" ] || ! grep -q "^3 3 " "$$wd/out.txt"; then \
	  echo "test-uforth: FAIL (exit $$rc)"; tail -8 "$$wd/out.txt"; exit 1; \
	fi; \
	echo "test-uforth: smoke PASS — compiles, STD.UFO loads, native + PYTHON-bodied words evaluate"; \
	if ! command -v python3 > /dev/null 2>&1; then \
	  echo "test-uforth: corpus SKIP — no python3 to be the oracle"; exit 0; \
	fi; \
	echo "running uforth's own corpora, DIFFERENTIAL against CPython ..."; \
	bad=0; ok=0; miss=0; missing=""; want=0; \
	for f in $(UFORTH_CORPUS) ""; do \
	  [ -n "$$f" ] || continue; \
	  want=$$((want+1)); \
	  if [ ! -f "$(UFORTH_SRC)/$$f" ]; then \
	    miss=$$((miss+1)); missing="$$missing $$f"; continue; \
	  fi; \
	  printf '"%s" INCLUDE\nBYE\n' "$$f" > "$$wd/in.txt"; \
	  ( cd "$(UFORTH_SRC)" && timeout 180 "$$wd/uforth" < "$$wd/in.txt" ) > "$$wd/p.out" 2>&1 & pp=$$!; \
	  ( cd "$(UFORTH_SRC)" && timeout 180 python3 uforth.py < "$$wd/in.txt" ) > "$$wd/c.out" 2>&1 & cp=$$!; \
	  wait $$pp || true; wait $$cp || true; \
	  if diff -q "$$wd/p.out" "$$wd/c.out" > /dev/null 2>&1; then \
	    ok=$$((ok+1)); \
	  else \
	    bad=$$((bad+1)); echo "  DIFF $$f"; diff -u "$$wd/c.out" "$$wd/p.out" | head -12; \
	  fi; \
	done; \
	echo "running the Forth 2012 / ANS suite per WORD SET, DIFFERENTIAL against CPython ..."; \
	for f in $(UFORTH_WORDSETS) ""; do \
	  [ -n "$$f" ] || continue; \
	  want=$$((want+1)); \
	  if [ ! -f "$(UFORTH_SRC)/tests/$$f" ]; then \
	    miss=$$((miss+1)); missing="$$missing tests/$$f"; continue; \
	  fi; \
	  drv="_pxxdrv_$$$$_$$f.fth"; \
	  printf 'S" prelimtest.fth" INCLUDED\nS" tester.fr" INCLUDED\nS" utilities.fth" INCLUDED\nS" errorreport.fth" INCLUDED\nS" %s" INCLUDED\n' "$$f" > "$(UFORTH_SRC)/tests/$$drv"; \
	  printf '"tests/%s" INCLUDE\nBYE\n' "$$drv" > "$$wd/in.txt"; \
	  ( cd "$(UFORTH_SRC)" && timeout 900 "$$wd/uforth" < "$$wd/in.txt" ) > "$$wd/p.out" 2>&1 & pp=$$!; \
	  ( cd "$(UFORTH_SRC)" && timeout 900 python3 uforth.py < "$$wd/in.txt" ) > "$$wd/c.out" 2>&1 & cp=$$!; \
	  wait $$pp || true; wait $$cp || true; \
	  rm -f "$(UFORTH_SRC)/tests/$$drv"; \
	  if diff -q "$$wd/p.out" "$$wd/c.out" > /dev/null 2>&1; then \
	    ok=$$((ok+1)); \
	  else \
	    bad=$$((bad+1)); echo "  DIFF word set $$f"; diff -u "$$wd/c.out" "$$wd/p.out" | head -12; \
	  fi; \
	done; \
	if [ "$$miss" != "0" ]; then \
	  echo "test-uforth: INCOMPLETE — $$miss of $$want corpora absent from $(UFORTH_SRC):$$missing"; \
	  echo "test-uforth:   (present-but-unrun corpora are invisible in the count below — see UFORTH_CORPUS)"; \
	fi; \
	if [ "$$bad" != "0" ]; then \
	  echo "test-uforth: FAIL — $$bad of $$((ok+bad)) corpora differ from CPython"; exit 1; \
	fi; \
	echo "test-uforth: PASS — smoke + $$ok/$$want corpora byte-identical to CPython$${missing:+ ($$miss ABSENT)}"

# uforth cross-runtime speed oracle (feature-t-uforth-benchmark-harness):
# the SAME uforth.py under CPython vs pxx-compiled-native, wall + max-RSS +
# speedup. Uses the CURRENT $(COMPILER) (pinned stable is too old to lex
# uforth's char-code literals). Skips cleanly when uforth/python3 absent.
# `make bench-uforth` = quick set; `make bench-uforth BENCH_FULL=1` adds the
# ELF-HASH outlier. Rows -> devdocs/progress/tstate/bench.tsv.
bench-uforth: $(COMPILER)
	@tools/uforth_bench.py --pxx ./$(COMPILER) $(if $(BENCH_FULL),--full,)

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
	# bug-cfront-no-entry-stub-for-xtensa: C compiles for the ESP ISAs in the only
	# shape that means anything there — a relocatable object exporting app_main,
	# no entry stub (no OS, no syscall ABI). The file's #if guards also pin
	# <limits.h>'s target-width LONG_MAX/INT_MAX on xtensa, which was the
	# coverage blind spot the ticket was opened for.
	./$(COMPILER) --target=xtensa test/cxtensa_obj.c /tmp/cxtensa_obj_xt.o
	readelf -h /tmp/cxtensa_obj_xt.o | grep -q 'REL (Relocatable file)'
	readelf -h /tmp/cxtensa_obj_xt.o | grep -q 'Xtensa'
	readelf -s /tmp/cxtensa_obj_xt.o | grep -q 'FUNC    GLOBAL DEFAULT    1 app_main'
	readelf -s /tmp/cxtensa_obj_xt.o | grep -q 'UND ext_notify'
	readelf -r /tmp/cxtensa_obj_xt.o | grep -q 'R_XTENSA_32'
	./$(COMPILER) --target=riscv32 test/cxtensa_obj.c /tmp/cxtensa_obj_rv.o
	readelf -h /tmp/cxtensa_obj_rv.o | grep -q 'REL (Relocatable file)'
	readelf -s /tmp/cxtensa_obj_rv.o | grep -q 'FUNC    GLOBAL DEFAULT    1 app_main'
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
	@./$(COMPILER) test/test_esp_bare_atomic.pas /tmp/test_esp_bare_atomic_oracle >/dev/null && /tmp/test_esp_bare_atomic_oracle > /tmp/test_esp_bare_atomic.oracle
	@RV=$$(ls $$HOME/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1); \
	if [ -z "$$RV" ]; then echo "Espressif qemu-system-riscv32 not installed; esp32c3 atomics run skipped"; else \
	  ESP_RUN_TIMEOUT=10 tools/esp_run_bare.sh --chip esp32c3 test/test_esp_bare_atomic.pas > /tmp/test_esp_bare_atomic.c3 2>/dev/null; \
	  if diff -u /tmp/test_esp_bare_atomic.oracle /tmp/test_esp_bare_atomic.c3; then echo "esp32c3 atomics ok (UART output == x86-64 oracle)"; \
	  else echo "esp32c3 atomics MISMATCH"; exit 1; fi; fi
	@./$(COMPILER) test/test_esp_bare_largeframe.pas /tmp/test_esp_bare_lf_oracle >/dev/null && /tmp/test_esp_bare_lf_oracle > /tmp/test_esp_bare_lf.oracle
	@XT=$$(ls $$HOME/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1); \
	if [ -z "$$XT" ]; then echo "Espressif qemu-system-xtensa not installed; esp32s3 large-frame run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32s3 test/test_esp_bare_largeframe.pas > /tmp/test_esp_bare_lf.s3 2>/dev/null; \
	  if diff -u /tmp/test_esp_bare_lf.oracle /tmp/test_esp_bare_lf.s3; then echo "esp32s3 call0 large-frame ok (>128B frame via ADDMI == x86-64 oracle)"; \
	  else echo "esp32s3 call0 large-frame MISMATCH"; exit 1; fi; fi
	# bug-a-pxx-callee-uses-internal-abi-for-64bit-params-called-from-c: the
	# xtensa C ABI starts a 64-bit argument at an EVEN word index; pxx now applies
	# that rule unconditionally on BOTH sides (caller pad + callee spill), so a
	# routine called from C reads the same registers gcc wrote. These calls put
	# the 64-bit value at odd word indices 1, 3 and 5 (the last straddling a7 into
	# the stack area) plus an even control case.
	@./$(COMPILER) test/test_esp_bare_arg64.pas /tmp/test_esp_arg64_oracle >/dev/null && /tmp/test_esp_arg64_oracle > /tmp/test_esp_arg64.oracle
	@RV=$$(ls $$HOME/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1); \
	if [ -z "$$RV" ]; then echo "Espressif qemu-system-riscv32 not installed; esp32c3 arg64 run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32c3 test/test_esp_bare_arg64.pas > /tmp/test_esp_arg64.c3 2>/dev/null; \
	  if diff -u /tmp/test_esp_arg64.oracle /tmp/test_esp_arg64.c3; then echo "esp32c3 odd-index 64-bit args ok (UART output == x86-64 oracle)"; \
	  else echo "esp32c3 odd-index 64-bit args MISMATCH"; exit 1; fi; fi
	@XT=$$(ls $$HOME/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1); \
	if [ -z "$$XT" ]; then echo "Espressif qemu-system-xtensa not installed; esp32s3 arg64 run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32s3 test/test_esp_bare_arg64.pas > /tmp/test_esp_arg64.s3 2>/dev/null; \
	  if diff -u /tmp/test_esp_arg64.oracle /tmp/test_esp_arg64.s3; then echo "esp32s3 odd-index 64-bit args ok (UART output == x86-64 oracle)"; \
	  else echo "esp32s3 odd-index 64-bit args MISMATCH"; exit 1; fi; fi
	@./$(COMPILER) test/test_esp_frozen_string.pas /tmp/test_esp_frz_oracle >/dev/null && /tmp/test_esp_frz_oracle > /tmp/test_esp_frz.oracle
	@RV=$$(ls $$HOME/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1); \
	if [ -z "$$RV" ]; then echo "Espressif qemu-system-riscv32 not installed; esp32c3 frozen-string run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32c3 test/test_esp_frozen_string.pas > /tmp/test_esp_frz.c3 2>/dev/null; \
	  if diff -u /tmp/test_esp_frz.oracle /tmp/test_esp_frz.c3; then echo "esp32c3 frozen string[N] ok (UART output == x86-64 oracle)"; \
	  else echo "esp32c3 frozen string MISMATCH"; exit 1; fi; fi
	@XT=$$(ls $$HOME/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1); \
	if [ -z "$$XT" ]; then echo "Espressif qemu-system-xtensa not installed; esp32s3 frozen-string run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32s3 test/test_esp_frozen_string.pas > /tmp/test_esp_frz.s3 2>/dev/null; \
	  if diff -u /tmp/test_esp_frz.oracle /tmp/test_esp_frz.s3; then echo "esp32s3 frozen string[N] ok (UART output == x86-64 oracle)"; \
	  else echo "esp32s3 frozen string MISMATCH"; exit 1; fi; fi
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
	@./$(COMPILER) test/test_esp_stack_args.pas /tmp/test_esp_stack_args_oracle >/dev/null && /tmp/test_esp_stack_args_oracle > /tmp/test_esp_stack_args.oracle
	@RV=$$(ls $$HOME/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 2>/dev/null | head -1); \
	if [ -z "$$RV" ]; then echo "Espressif qemu-system-riscv32 not installed; esp32c3 stack-args run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32c3 test/test_esp_stack_args.pas > /tmp/test_esp_stack_args.c3 2>/dev/null; \
	  if diff -u /tmp/test_esp_stack_args.oracle /tmp/test_esp_stack_args.c3; then echo "esp32c3 >6-word args ok (UART output == x86-64 oracle)"; \
	  else echo "esp32c3 stack args MISMATCH"; exit 1; fi; fi
	@XT=$$(ls $$HOME/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa 2>/dev/null | head -1); \
	if [ -z "$$XT" ]; then echo "Espressif qemu-system-xtensa not installed; esp32s3 stack-args run skipped"; else \
	  ESP_RUN_TIMEOUT=8 tools/esp_run_bare.sh --chip esp32s3 test/test_esp_stack_args.pas > /tmp/test_esp_stack_args.s3 2>/dev/null; \
	  if diff -u /tmp/test_esp_stack_args.oracle /tmp/test_esp_stack_args.s3; then echo "esp32s3 (Call0) >6-word args ok (UART output == x86-64 oracle)"; \
	  else echo "esp32s3 stack args MISMATCH"; exit 1; fi; fi
	@$(MAKE) --no-print-directory test-esp-softfloat

# Runtime 64-bit-integer gate for the ESP backends: the soft-float library is
# almost entirely Int64 math, so it doubles as the proof that runtime 64-bit
# arithmetic (add/sub/mul/div/mod/shifts/compares + Int64 params/returns) works
# on BOTH ESP backends. The same kernel source runs on the x86-64 oracle and on
# the riscv32 (esp32c3) + xtensa (esp32s3) QEMU targets; any output mismatch
# means a 64-bit op miscompiles. Each chip is skipped when its Espressif qemu is
# absent. (feature-esp-int64-arith)
# ESP-IDF (not bare-metal) runtime check: builds a program into the real IDF,
# boots it under the Espressif qemu fork and diffs the serial output. Needs a
# full ESP-IDF checkout, so it is NOT part of `make test` — run it when touching
# argument marshalling, the esp PAL, or anything that crosses into the SDK.
#
# The timer demo is the case worth guarding: it calls
# esp_timer_start_periodic(handle, period: Int64), and passing a 64-bit
# argument to a C function was broken on BOTH backends for a month with no
# symptom other than a callback that never fired
# (bug-esp-timer-callback-never-dispatched). Nothing in the bare-metal suite
# calls into C, so nothing there could have caught it.
test-esp-idf: $(COMPILER)
	@[ -f $$HOME/esp/esp-idf/export.sh ] || { echo "ESP-IDF not installed; test-esp-idf skipped"; exit 0; }
	@for chip in esp32c3 esp32s3; do \
	  echo "--- $$chip esp_timer callback"; \
	  ESP_RUN_TIMEOUT=25 ESP_PXXFLAGS="--no-signals -Fu$(CURDIR)/lib/rtl -Fu$(CURDIR)/lib/rtl/platform/esp" \
	    tools/esp_run.sh --chip $$chip examples/esp32/timer-c3/main/main.pas 2>/dev/null \
	    | grep "PXX timer" > /tmp/test_esp_idf_timer.$$chip || true; \
	  printf 'PXX timer: started\nPXX timer: tick=1\nPXX timer: tick=2\nPXX timer: tick=3\nPXX timer: tick=4\nPXX timer: tick=5\nPXX timer: done ticks=5 status=0\n' > /tmp/test_esp_idf_timer.expected; \
	  if diff -u /tmp/test_esp_idf_timer.expected /tmp/test_esp_idf_timer.$$chip; then \
	    echo "$$chip esp_timer callback ok"; \
	  else echo "$$chip esp_timer callback MISMATCH"; exit 1; fi; \
	done

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
	# Quick-tier canaries for the OTHER two frontends (the Pascal ones follow).
	# Broad-not-deep, self-summarising, ~1s each: a Track N or C change had no
	# fast check at all between "it built" and the 554s suite.
	# qc_* names deliberately avoid the smoke_* namespace these recipes share.
	./$(COMPILER) test/quick_canary_nilpy.npy /tmp/qc_nilpy26
	test "$$(/tmp/qc_nilpy26 | tail -1)" = "total ok 23 / 23"
	./$(COMPILER) -Ilib/crtl/include -Ilib/crtl/src test/quick_canary_c.c /tmp/qc_c26
	test "$$(/tmp/qc_c26 | tail -1)" = "total ok 22 / 22"
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
	./$(COMPILER) test/test_fwd_ptr_alias_field.pas /tmp/smoke_fwdptralias26
	test "$$(/tmp/smoke_fwdptralias26)" = "11 22"

# test-smoke: the pre-commit iteration gate = test-quick + the full self-host
# byte-identity chain (the artifacts stabilize-core pins). Catches self-host
# miscompiles that a runtime-only pass cannot (see
# bug-selfhost-multifn-ifelse-miscompile).
test-smoke: test-quick
	# self-host byte-identity chain (the artifacts stabilize-core pins)
	./$(COMPILER) $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-self.$$$$.tmp && mv -f /tmp/pascal26-self.$$$$.tmp /tmp/pascal26-self
	/tmp/pascal26-self $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-next.$$$$.tmp && mv -f /tmp/pascal26-next.$$$$.tmp /tmp/pascal26-next
	/tmp/pascal26-next test/bootstrap_features.pas /tmp/smoke_boot26
	test "$$(/tmp/smoke_boot26)" = "$$(printf '120\n98\ncase-ok\n0')"
	/tmp/pascal26-next $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-fixedpoint.$$$$.tmp && mv -f /tmp/pascal26-fixedpoint.$$$$.tmp /tmp/pascal26-fixedpoint
	cmp /tmp/pascal26-next /tmp/pascal26-fixedpoint
	cp /tmp/pascal26-fixedpoint /tmp/pascal26-s5.$$$$.tmp && mv -f /tmp/pascal26-s5.$$$$.tmp /tmp/pascal26-s5

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
	# C: a string LITERAL argument to a Pointer param, through a shim whose
	# retained body contains a call — the shape the -O3 inline splice
	# temp-captures. Only -O3 lost the +8 frozen-string length-prefix skip, so
	# the callee got a pointer at the length byte: __pxx_open("/etc/localtime")
	# failed and localtime() silently reported UTC for every zone.
	@for o in -O0 -O2 -O3; do \
	  ./$(COMPILER) $$o -Ilib/crtl/include -Ilib/crtl/src test/c_inline_strlit_arg.c /tmp/c_inl_strlit >/dev/null && \
	  out=$$(/tmp/c_inl_strlit); \
	  [ "$$out" = "literal_ok=1 variable_ok=1" ] || \
	    { echo "FAIL: c_inline_strlit_arg at $$o -> $$out"; exit 1; }; \
	done; echo 'c_inline_strlit_arg: -O0/-O2/-O3 agree'
	./$(COMPILER) --threadsafe test/test_atomic64.pas /tmp/opt0_atomic64 >/dev/null
	./$(COMPILER) -O1 --threadsafe test/test_atomic64.pas /tmp/opt1_atomic64 >/dev/null
	/tmp/opt0_atomic64 > /tmp/opt0_a64.out; /tmp/opt1_atomic64 > /tmp/opt1_a64.out
	cmp /tmp/opt0_a64.out /tmp/opt1_a64.out
	# -O1 self-compile fixedpoint: an -O1-built compiler rebuilding itself at
	# -O1 must reach byte-identity too
	./$(COMPILER) -O1 $(COMPILER_SRC) /tmp/pascal26-o1a.$$$$.tmp && mv -f /tmp/pascal26-o1a.$$$$.tmp /tmp/pascal26-o1a
	/tmp/pascal26-o1a -O1 $(COMPILER_SRC) /tmp/pascal26-o1b.$$$$.tmp && mv -f /tmp/pascal26-o1b.$$$$.tmp /tmp/pascal26-o1b
	/tmp/pascal26-o1b -O1 $(COMPILER_SRC) /tmp/pascal26-o1c.$$$$.tmp && mv -f /tmp/pascal26-o1c.$$$$.tmp /tmp/pascal26-o1c
	cmp /tmp/pascal26-o1b /tmp/pascal26-o1c
	# -O2 self-compile fixedpoint (register calling convention, feature-callconv-
	# register-args): an -O2-built compiler rebuilding itself at -O2 reaches
	# byte-identity too. Gates the r14/r15 param-residency codegen.
	./$(COMPILER) -O2 $(COMPILER_SRC) /tmp/pascal26-o2a.$$$$.tmp && mv -f /tmp/pascal26-o2a.$$$$.tmp /tmp/pascal26-o2a
	/tmp/pascal26-o2a -O2 $(COMPILER_SRC) /tmp/pascal26-o2b.$$$$.tmp && mv -f /tmp/pascal26-o2b.$$$$.tmp /tmp/pascal26-o2b
	/tmp/pascal26-o2b -O2 $(COMPILER_SRC) /tmp/pascal26-o2c.$$$$.tmp && mv -f /tmp/pascal26-o2c.$$$$.tmp /tmp/pascal26-o2c
	cmp /tmp/pascal26-o2b /tmp/pascal26-o2c
	# -O2 now carries the W1 mirror / leaf-index fold / last-arg collapse
	# (promoted 2026-07-11 after a 564-program -O0-vs differential). -O3 keeps
	# the register-lifetime passes (r8-r13 scratch, loop/float residency); an
	# -O3-built compiler rebuilding itself at -O3 must reach byte-identity too.
	./$(COMPILER) -O3 $(COMPILER_SRC) /tmp/pascal26-o3a.$$$$.tmp && mv -f /tmp/pascal26-o3a.$$$$.tmp /tmp/pascal26-o3a
	/tmp/pascal26-o3a -O3 $(COMPILER_SRC) /tmp/pascal26-o3b.$$$$.tmp && mv -f /tmp/pascal26-o3b.$$$$.tmp /tmp/pascal26-o3b
	/tmp/pascal26-o3b -O3 $(COMPILER_SRC) /tmp/pascal26-o3c.$$$$.tmp && mv -f /tmp/pascal26-o3c.$$$$.tmp /tmp/pascal26-o3c
	cmp /tmp/pascal26-o3b /tmp/pascal26-o3c
	@echo "test-opt OK (differential corpus + -O1/-O2 fixedpoint)"

# stabilize-fast: THE DEFAULT PATH TO A PIN. test-smoke instead of the full
# suite, and the already-proven fixedpoint binary is recorded directly (the full
# target's s4/s5 re-derivations only re-prove what cmp(next,fixedpoint)
# established). ~35s, against ~25min for `stabilize`.
#
# POLICY, user 2026-08-09, revising the old "fine for iteration; run full
# stabilize before batch/milestone pins": **all-target verification belongs to a
# RELEASE, not to a pin.** A pin exists to hand other tracks a working compiler,
# and they — and the human — are BLOCKED while it runs. Paying 25 minutes of
# cross-target breadth up front buys protection against something that is cheap
# to undo (move `pinned` back; see `make revert`), while the one property a bad
# pin could poison for everyone — a compiler that cannot reproduce itself — is
# exactly what test-smoke's self->next->fixedpoint chain proves in seconds.
#
# This is the same "confirm native, offload the matrix" split CLAUDE.md already
# states for the per-fix loop; the pin bar had simply never been brought in line
# with it. Track T sweeps the matrix against the pinned sha asynchronously and
# files what it finds.
#
# Use full `stabilize` for a RELEASE, or when Track T is PROVEN down.
stabilize-fast: test-smoke
	$(MAKE) stabilize-record

stabilize: test
	@echo "=== stabilize: 4-iteration fixedpoint check ==="
	/tmp/pascal26-fixedpoint $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-s4.$$$$.tmp && mv -f /tmp/pascal26-s4.$$$$.tmp /tmp/pascal26-s4
	cmp /tmp/pascal26-next /tmp/pascal26-s4
	/tmp/pascal26-s4 $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-s5.$$$$.tmp && mv -f /tmp/pascal26-s5.$$$$.tmp /tmp/pascal26-s5
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
	/tmp/pascal26-fixedpoint $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-s4.$$$$.tmp && mv -f /tmp/pascal26-s4.$$$$.tmp /tmp/pascal26-s4
	cmp /tmp/pascal26-next /tmp/pascal26-s4
	/tmp/pascal26-s4 $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-s5.$$$$.tmp && mv -f /tmp/pascal26-s5.$$$$.tmp /tmp/pascal26-s5
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
	# Structural, and FIRST because it costs ~0.1s and its failure mode is
	# invisible at run time: a crtl header declaring a function whose definition
	# no auto-pull from that header reaches. The program links, and the symbol
	# resolves against GLIBC instead — right name, not necessarily the same ABI.
	# Bitten twice (<sys/socket.h>, <inttypes.h>), fixed two different ways, and
	# nothing checked the rule they both satisfy until this.
	python3 tools/crtl_reachability.py
	# The crtl function -> header map the compiler reads is GENERATED from these
	# same files. Fails when a crtl function was added without regenerating —
	# which would leave it invisible to a C89-style hand prototype, i.e. a glibc
	# import in a libc-free build. Regenerate with: python3 tools/gen_crtl_map.py
	python3 tools/gen_crtl_map.py --check
	# Every unit under lib/** compiles as a bare `uses`. The smoke programs
	# below reach most units, and "most" is how lib/pcl/tkhtmlview.pas stayed
	# broken for its entire life -- 398 lines that had never once compiled, on
	# any binary including pinned, because no gate ever named the file.
	# ~16s parallel across 138 units.
	PXX_STABLE=$(PXX_STABLE) python3 tools/lib_units_compile.py
	$(PXX_STABLE) examples/sudoku/sudoku.pas /tmp/lib_sudoku
	test "$$(/tmp/lib_sudoku)" = "$$(printf '534678912672195348198342567859761423426853791713924856961537284287419635345286179\n987654321246173985351928746128537694634892157795461832519286473472319568863745219\n812753649943682175675491283154237896369845721287169534521974368438526917796318452')"
	$(PXX_STABLE) -dPXX_MANAGED_STRING test/test_collections.pas /tmp/lib_collections
	@test -n "$$(/tmp/lib_collections)" || (echo "lib smoke: collections produced no output"; exit 1)
	/tmp/lib_collections >/dev/null
	$(PXX_STABLE) test/test_math.pas /tmp/lib_math
	/tmp/lib_math >/dev/null
	# nilsh — the portable-userland shell (feature-demo-portable-userland phase 1).
	# Applet dispatch + real pipes in NilPy. It is plain Python, so CPython is the
	# oracle: the SAME source must print the same session under python3, which is
	# the cross-runtime half of the thesis the demo exists to show.
	$(PXX_STABLE) examples/shell/nilsh.npy /tmp/lib_nilsh
	test "$$(/tmp/lib_nilsh | tail -n 1)" = "nilsh: unknown applet: nosuch"
	@if command -v python3 >/dev/null 2>&1; then \
	  python3 examples/shell/nilsh.npy > /tmp/lib_nilsh_cpy.txt 2>&1; \
	  /tmp/lib_nilsh > /tmp/lib_nilsh_pxx.txt 2>&1; \
	  diff /tmp/lib_nilsh_cpy.txt /tmp/lib_nilsh_pxx.txt >/dev/null \
	    && echo "  lib-test: nilsh output identical to CPython" \
	    || { echo "FAIL: nilsh diverges from CPython"; diff /tmp/lib_nilsh_cpy.txt /tmp/lib_nilsh_pxx.txt | head -10; exit 1; }; \
	else echo "  lib-test: python3 absent, skipping the nilsh CPython diff"; fi
	# Log10/Log2/LogN land exactly on the integer for exact powers of the base
	# (Trunc(Log10(n)) + 1 is the digit-count idiom everyone writes), and values
	# a hair off a power are NOT flattened onto it.
	$(PXX_STABLE) -Fulib/rtl test/lib_log_exactness.pas /tmp/lib_log_exactness
	test "$$(/tmp/lib_log_exactness | tail -n 1)" = "LOGEXACT OK"
	# TextReadChar (FPC's read(f, c)) consumes ONE character and interleaves with
	# TextReadLn — expectations measured against FPC, not reasoned about.
	$(PXX_STABLE) -Fulib/rtl test/lib_textreadchar.pas /tmp/lib_textreadchar
	test "$$(/tmp/lib_textreadchar | tail -n 1)" = "TEXTREADCHAR OK"
	# The FPC threading surface where FPC code looks for it: WaitFor as a
	# FUNCTION returning ReturnValue, the BeginThread family, and an empty
	# cthreads shim. Expectations are FPC's own output for the same program.
	$(PXX_STABLE) --threadsafe -Fulib/rtl test/lib_fpc_thread_surface.pas /tmp/lib_fpc_thread_surface
	test "$$(/tmp/lib_fpc_thread_surface | tail -n 1)" = "FPCTHREAD OK"
	# TThread reached through `uses Classes` — FPC's own uses line, no {$IFDEF FPC}
	# split. The non-threaded half of the bargain (classes still building WITHOUT
	# --threadsafe) is asserted by every other classes test above, which do not
	# pass the flag.
	$(PXX_STABLE) --threadsafe -Fulib/rtl test/lib_classes_tthread.pas /tmp/lib_classes_tthread
	test "$$(/tmp/lib_classes_tthread | tail -n 1)" = "CLASSESTHREAD OK"
	# FPC surface the differential probe found missing: Eoln, the legacy
	# TSeekOrigin names, IncMonth's end-of-month clamp. Expectations measured
	# against an FPC build, per the ticket's method note.
	$(PXX_STABLE) -Fulib/rtl test/lib_fpc_surface_2026_08.pas /tmp/lib_fpc_surface
	test "$$(/tmp/lib_fpc_surface | tail -n 1)" = "FPCSURFACE OK"
	# TStrings.CommaText/DelimitedText: 43 cases whose expectations are FPC's own
	# output, including the two quoting rules a from-the-description
	# implementation gets wrong ("a"b is TWO items; a"b" is one literal item).
	$(PXX_STABLE) -Fulib/rtl test/lib_commatext.pas /tmp/lib_commatext
	test "$$(/tmp/lib_commatext | tail -n 1)" = "COMMATEXT OK"
	# The Python math surface (NilPy's `import math` resolves against lib/rtl's
	# math unit): e/tau/inf/nan, isnan/isinf, pow, log(x,base), atan2,
	# degrees/radians, copysign's sign-bit rule, isclose, factorial, comb.
	$(PXX_STABLE) -Fulib/rtl test/lib_math_python_surface.pas /tmp/lib_math_python_surface
	test "$$(/tmp/lib_math_python_surface | tail -n 1)" = "MATHPY OK"
	# Ln/Log10/Log2/Exp/Power correctly rounded, asserted on the BITS (a digit
	# comparison would measure our float formatter as much as the function).
	# The Log10 cases at the end are ones where GLIBC is the wrong one — verified
	# against 60-digit arithmetic — so do not "fix" them to match CPython.
	$(PXX_STABLE) -Fulib/rtl test/lib_math_correctly_rounded.pas /tmp/lib_math_correctly_rounded
	test "$$(/tmp/lib_math_correctly_rounded | tail -n 1)" = "MATHROUND OK"
	# Canary for a change in ANOTHER lane: a Pascal RTL name that collides with
	# a libc one silently hijacks it in every C program (pxxcio does `uses math`).
	# nan(tag): positive quiet NaN carrying the tag as its payload, base 0 —
	# "077" is octal and "0x10" is hex, the rows a decimal-only parser misses.
	$(PXX_STABLE) -Ilib/crtl/include -Ilib/crtl/src test/cmath_nan_payload.c /tmp/cmath_nan_payload
	test "$$(/tmp/cmath_nan_payload)" = "$$(printf 'empty      7FF8000000000000\n1          7FF8000000000001\n12345      7FF8000000003039\n0x10       7FF8000000000010\nabc        7FF8000000000000\n077        7FF800000000003F\nbig        7FF8000000000001')"
	$(PXX_STABLE) test/cmath_no_pascal_hijack.c /tmp/cmath_no_pascal_hijack
	test "$$(/tmp/cmath_no_pascal_hijack)" = "$$(printf 'pow=1024 1.41421\nlog=1.386294361 log10=3.000000000 log2=3.000000000\nexp=2.718281828\natan2=0.785398163 0.463647609 1.107148718\ncopysign=-3 3\nisnan=1 0\nisinf=1 0\nnan=1 1\nhypot=5.000000000 fmod=1\nsqrt=1.414213562 ceil=-2 floor=-3')"
	# TCriticalSection: excludes under contention AND blocks rather than spins.
	# The output is identical either way — the property that separates a futex
	# mutex from the spinlock it replaced is CPU TIME, so assert that: three
	# waiters queued behind a 0.6s hold burnt 1.73s of user CPU as a spinlock and
	# 0.00s as a futex mutex. 1s is far above the noise and far below a regression.
	$(PXX_STABLE) --threadsafe -Fulib/rtl test/lib_criticalsection_blocking.pas /tmp/lib_cs_blocking
	test "$$(/tmp/lib_cs_blocking)" = "$$(printf 'count=8000\nCSBLOCK OK')"
	@if command -v /usr/bin/time >/dev/null 2>&1; then \
	  u=$$(/usr/bin/time -f '%U' /tmp/lib_cs_blocking 2>&1 >/dev/null | tail -n 1); \
	  awk -v u="$$u" 'BEGIN { if (u+0 > 1.0) { print "FAIL: TCriticalSection waiters burnt " u "s of user CPU — spinning, not blocking"; exit 1 } \
	                          else print "  lib-test: TCriticalSection waiters blocked (user CPU " u "s)" }'; \
	else \
	  echo "  lib-test: /usr/bin/time absent, skipping the TCriticalSection spin check"; \
	fi
	$(PXX_STABLE) test/lib_sysutils.pas /tmp/lib_sysutils
	test "$$(/tmp/lib_sysutils)" = "$$(printf '0\n-123456789\n10000000000\nhello\nworld\n[]\n[pad]\n42\n-7\n-1\n100\nQ\n7\nAB3Z\nab3z\nhello\nab\nbcde\nabcde\nabcde\nhello world\nstart end\nstart end\nabc\nfoobar\nx\nx\nbase\n77\nderived')"
	# regex engine: 61 checks whose expectations are CPython's re output for the
	# same pattern/subject pairs, including every songformatter pattern
	$(PXX_STABLE) -Fulib/rtl test/lib_regex.pas /tmp/lib_regex
	test "$$(/tmp/lib_regex | tail -n 1)" = "REGEX OK"
	# regex engine: 61 checks whose expectations are CPython's re output for the
	# same pattern/subject pairs, including every songformatter pattern
	$(PXX_STABLE) -Fulib/rtl test/lib_regex.pas /tmp/lib_regex
	test "$$(/tmp/lib_regex | tail -n 1)" = "REGEX OK"
	$(PXX_STABLE) test/lib_random.pas /tmp/lib_random
	test "$$(/tmp/lib_random)" = "$$(printf '5 6 6 2 6 4 2 5 \n5 6 6 2 6 4 2 5 \n359 891 105 979 687 ')"
	# per-stream PRNG state: reproducibility + independent split streams (no lock)
	$(PXX_STABLE) test/lib_randomstate.pas /tmp/lib_randomstate
	test "$$(/tmp/lib_randomstate | tail -n 1)" = "RANDOMSTATE OK"
	# IPv6 over the PAL: sockaddr_in6 layout + loopback round trip (skips if the
	# host has no AF_INET6 — a broken layout is the target, not the CI netstack)
	$(PXX_STABLE) -Fulib/rtl -Fulib/rtl/platform/posix test/lib_ipv6.pas /tmp/lib_ipv6
	/tmp/lib_ipv6 | tail -n 1 | grep -qE '^IPV6 (OK|SKIP)'
	# IPv6 through net.pas, and proof the IPv4 path still works after
	# TNetAddress gained a Family field
	$(PXX_STABLE) -Fulib/rtl -Fulib/rtl/platform/posix test/lib_net6.pas /tmp/lib_net6
	/tmp/lib_net6 | tail -n 1 | grep -qE '^NET6 (OK|SKIP)'
	# IPV6_V6ONLY escape hatch: asserted BEHAVIOURALLY (can a v4 client reach a
	# :: listener), not by setsockopt's return, since the point is that the
	# option takes effect rather than being accepted and ignored.
	$(PXX_STABLE) -Fulib/rtl -Fulib/rtl/platform/posix test/lib_net_v6only.pas /tmp/lib_net_v6only
	test "$$(/tmp/lib_net_v6only | tail -1)" = "NETV6ONLY OK"
	# Connect-by-name and the decided A-first / AAAA-fallback ordering. Every
	# ordering assertion checks which FAMILY won, since "it connected" is true
	# under either order. localhost only, so no network.
	$(PXX_STABLE) -Fulib/rtl -Fulib/rtl/platform/posix test/lib_netconnect.pas /tmp/lib_netconnect
	test "$$(/tmp/lib_netconnect | tail -1)" = "NETCONNECT OK"
	# asyncnet over ::1 — the coroutine reactor is family-agnostic, so this runs
	# the v6 socket calls against the SAME accept/recv/send the v4 tests use
	$(PXX_STABLE) -Fulib/rtl -Fulib/rtl/platform/posix test/lib_asyncnet6.pas /tmp/lib_asyncnet6
	/tmp/lib_asyncnet6 | tail -n 1 | grep -qE '^ASYNCNET6 (OK|SKIP)'
	# NilPy -> Tcl/Tk embed, headless. Needs xvfb-run + the system libtcl/libtk
	# 8.6, so it SKIPS cleanly when either is missing rather than reddening a gate
	# over an absent GUI stack. The .npy auto-closes via `after`, so it terminates
	# on its own — nothing here can hang the suite waiting on a window.
	# <inttypes.h> completeness: PRI/SCN macros must match OUR stdint.h widths
	# (glibc's differ), plus imaxabs/imaxdiv/strtoimax/strtoumax actually exist.
	# printf-free on purpose — a wrong length modifier is a varargs bug, so a
	# printf-based check would be testing the bug with the bug.
	$(PXX_STABLE) -Ilib/crtl/include -Ilib/crtl/include/sys -Ilib/crtl/src test/crtl_inttypes.c /tmp/crtl_inttypes
	/tmp/crtl_inttypes; test "$$?" = "42"
	# clock(): plausible CPU microseconds with a NON-NEGATIVE delta between
	# readings — the property the __pxx_clock Int64-cast workaround protected.
	# The rounding CONTRACT: Pascal ties-to-even, C half-away-from-zero, and the
	# RoundTo family. The three frontends disagree BY DESIGN, each matching its
	# own reference — pinned so nobody "harmonises" them.
	$(PXX_STABLE) -Fulib/rtl test/lib_rounding_contract.pas /tmp/lib_rounding_contract
	test "$$(/tmp/lib_rounding_contract | tail -n 1)" = "ROUNDING OK"
	# longjmp usable as a VALUE, not only as a call — C 7.13 requires it to be a
	# real function, and tcc passes it as a function pointer.
	# anonymous mmap gives REAL pages and mprotect really flips them executable —
	# the JIT shape tcc -run needs. Both used to be no-op stubs.
	$(PXX_STABLE) -Ilib/crtl/include -Ilib/crtl/src test/cmman_jit_exec_pages.c /tmp/cmman_jit_exec_pages
	/tmp/cmman_jit_exec_pages; test "$$?" = "42"
	$(PXX_STABLE) -Ilib/crtl/include -Ilib/crtl/src test/crtl_longjmp_as_value.c /tmp/crtl_longjmp_as_value
	/tmp/crtl_longjmp_as_value; test "$$?" = "42"
	$(PXX_STABLE) -Ilib/crtl/include -Ilib/crtl/src test/cmath_lround.c /tmp/cmath_lround
	test "$$(/tmp/cmath_lround)" = "$$(printf '0.5 lround=1 llround=1 lrint=0\n1.5 lround=2 llround=2 lrint=2\n2.5 lround=3 llround=3 lrint=2\n3.5 lround=4 llround=4 lrint=4\n-0.5 lround=-1 llround=-1 lrint=0\n-1.5 lround=-2 llround=-2 lrint=-2\n-2.5 lround=-3 llround=-3 lrint=-2\n2.7 lround=3 llround=3 lrint=3\n-2.7 lround=-3 llround=-3 lrint=-3\n0.0 lround=0 llround=0 lrint=0')"
	# The integral-part family at the signed-zero and 2^52 boundaries. The
	# frexp(inf) row is a LIVENESS check — the old body looped forever there, so
	# a regression shows up as this target hanging, not as a mismatch.
	$(PXX_STABLE) -Ilib/crtl/include -Ilib/crtl/src test/cmath_integral_family.c /tmp/cmath_integral_family
	test "$$(/tmp/cmath_integral_family)" = "$$(printf 'fabs(-0)=+0\ntrunc(-0.5)=-0\nround(-0)=-0\nrint(-0.5)=-0\nfrexp(-0)=-0 e=0\nmodf(-1) fr=-0 ip=-1\ntrunc(1e300)=+1e+300\nround(-1e300)=-1e+300\nmodf(1e300) fr=+0 ip=+1e+300\nround(0.49999999999999994)=+0\nfrexp(inf)=+inf')"
	$(PXX_STABLE) -Ilib/crtl/include -Ilib/crtl/include/sys -Ilib/crtl/src test/crtl_clock_monotonic.c /tmp/crtl_clock_monotonic
	/tmp/crtl_clock_monotonic; test "$$?" = "42"
	# poll() over a SET (not a loop over a per-handle poll), and the LINKAGE that
	# a declared-but-unimplemented crtl function silently gave away: a body-less
	# declaration binds to libc.so.6 and still prints the right answers.
	$(PXX_STABLE) -Ilib/crtl/include -Ilib/crtl/include/sys -Ilib/crtl/src test/crtl_poll_set.c /tmp/crtl_poll_set
	test "$$(/tmp/crtl_poll_set)" = "$$(printf 'timeout r=0 rev0=0 rev1=0\nready r=1 rev0=0 rev1in=1\nboth r=2 in0=1 in1=1\nnval r=1 nval=1\nzero r=0')"
	@if command -v readelf >/dev/null 2>&1; then \
	  n=$$(readelf -d /tmp/crtl_poll_set 2>/dev/null | grep -c NEEDED); \
	  test "$$n" = "0" || (echo "FAIL: crtl_poll_set has $$n DT_NEEDED — poll bound to libc"; exit 1); \
	  echo "  lib-test: crtl_poll_set is self-contained (no DT_NEEDED)"; \
	else echo "  lib-test: readelf absent, skipping the poll linkage check"; fi
	# atexit on BOTH exit paths. The `return`-from-main case is the one with
	# teeth: it leaves through the entry stub's finalizer runner, not through
	# crtl's exit(), so a handler list kept on the C side would pass the exit()
	# row here and silently skip the row above it.
	$(PXX_STABLE) -Ilib/crtl/include -Ilib/crtl/include/sys -Ilib/crtl/src test/crtl_atexit.c /tmp/crtl_atexit
	test "$$(/tmp/crtl_atexit)"   = "$$(printf 'main-returns\nh3\nh2\nh1')"
	/tmp/crtl_atexit; test "$$?" = "0"
	test "$$(/tmp/crtl_atexit e)" = "$$(printf 'via-exit\nchild-exit')"
	/tmp/crtl_atexit e; test "$$?" = "4"
	test "$$(/tmp/crtl_atexit x)" = "via-_Exit"
	/tmp/crtl_atexit x; test "$$?" = "5"
	test "$$(/tmp/crtl_atexit n)" = "registered ok=100 bad=0"
	@if command -v readelf >/dev/null 2>&1; then \
	  n=$$(readelf -d /tmp/crtl_atexit 2>/dev/null | grep -c NEEDED); \
	  test "$$n" = "0" || (echo "FAIL: crtl_atexit has $$n DT_NEEDED — atexit bound to libc"; exit 1); \
	  echo "  lib-test: crtl_atexit is self-contained (no DT_NEEDED)"; \
	else echo "  lib-test: readelf absent, skipping the atexit linkage check"; fi
	# Payne-Hanek huge-argument trig: sin/cos/tan past 1e8, expected values are
	# the correctly-rounded doubles judged against 400-digit references.
	$(PXX_STABLE) -Ilib/crtl/include -Ilib/crtl/include/sys -Ilib/crtl/src test/crtl_trig_huge.c /tmp/crtl_trig_huge
	/tmp/crtl_trig_huge; test "$$?" = "42"
	# exp2 was declared in math.h and never defined — linked, then died at runtime
	$(PXX_STABLE) -Ilib/crtl/include -Ilib/crtl/include/sys -Ilib/crtl/src test/crtl_exp2.c /tmp/crtl_exp2
	/tmp/crtl_exp2; test "$$?" = "42"
	@if command -v xvfb-run >/dev/null 2>&1 && [ -e /usr/lib/$$(uname -m)-linux-gnu/libtk8.6.so.0 ]; then \
	  $(PXX_STABLE) -Fulib/pcl -Fulib/rtl -Fulib/rtl/platform/posix examples/tk/hello.npy /tmp/lib_tk_hello >/dev/null && \
	  test "$$(xvfb-run -a /tmp/lib_tk_hello)" = "ok: nilpy tk window shown and closed" && \
	  $(PXX_STABLE) -Fulib/pcl -Fulib/rtl -Fulib/rtl/platform/posix examples/tk/widgets.npy /tmp/lib_tk_widgets >/dev/null && \
	  test "$$(xvfb-run -a /tmp/lib_tk_widgets | tail -n 4)" = "$$(printf 'entry = typed into an entry\ntext  = and into a text widget\nlabel = widgets, one TkEval each\nok: nilpy tk widgets shown and closed')" && \
	  $(PXX_STABLE) -Fulib/pcl -Fulib/rtl -Fulib/rtl/platform/posix examples/tk/kwargs.npy /tmp/lib_tk_kwargs >/dev/null && \
	  test "$$(xvfb-run -a /tmp/lib_tk_kwargs | tr -d '\n')" = "get HELLOafter-delete LOvar bkwargs ok" && \
	  $(PXX_STABLE) -Fulib/pcl -Fulib/rtl -Fulib/rtl/platform/posix examples/tk/callbacks.npy /tmp/lib_tk_callbacks >/dev/null && \
	  test "$$(xvfb-run -a /tmp/lib_tk_callbacks | tail -n 6)" = "$$(printf 'trace fired\nstr trace fired\nbbox [1, 1, 10, 10]\nhits 1\nscroll ok True True\nlambda scroll ok True True')" && \
	  echo "  tk-nilpy: ok"; \
	else \
	  echo "  tk-nilpy: SKIP (no xvfb-run or no libtk8.6)"; \
	fi
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
	$(PXX_STABLE) --mimic-fpc -Fuexternal/synapse -Fulib/rtl -Fulib/rtl/platform/posix test/lib_synapse_transitive_unit.pas /tmp/lib_synapse_transitive_unit
	test "$$(/tmp/lib_synapse_transitive_unit)" = "ok"
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
	# dynlibs under the opt-in libc profile. The RUN is x86-64 + i386 (the two
	# targets this box has a runtime loader for); for arm32/aarch64 the ELF is
	# checked STATICALLY instead, which is what the open item actually doubts —
	# that the per-target interpreter and the libc import come out right. A
	# missing sysroot is a host gap, not a pxx one, so it must not read as a pass.
	@echo "=== lib-test: dynlibs (opt-in -dPXX_DYNLIB_LIBC) ==="
	$(PXX_STABLE) -dPXX_DYNLIB_LIBC -Fulib/rtl test/test_dynlib.pas /tmp/lib_dynlib
	test "$$(/tmp/lib_dynlib)" = "$$(printf 'strlen: 5\nunloaded: TRUE')"
	@for arch in i386 arm32 aarch64; do \
	  $(PXX_STABLE) --target=$$arch -dPXX_DYNLIB_LIBC -Fulib/rtl test/test_dynlib.pas /tmp/lib_dynlib_$$arch >/dev/null || { echo "dynlib compile FAIL on $$arch"; exit 1; }; \
	  case $$arch in \
	    i386)    want=/lib/ld-linux.so.2 ;; \
	    arm32)   want=/lib/ld-linux.so.3 ;; \
	    aarch64) want=/lib/ld-linux-aarch64.so.1 ;; \
	  esac; \
	  got=$$(strings -a /tmp/lib_dynlib_$$arch | grep -m1 "^/lib.*ld-"); \
	  test "$$got" = "$$want" || { echo "dynlib $$arch interpreter: got '$$got' want '$$want'"; exit 1; }; \
	  readelf -d /tmp/lib_dynlib_$$arch 2>/dev/null | grep -q "NEEDED.*libc.so.6" || { echo "dynlib $$arch: no NEEDED libc.so.6"; exit 1; }; \
	  echo "  dynlib $$arch: interpreter + libc import ok (static)"; \
	done
	@if command -v qemu-i386 >/dev/null 2>&1; then \
	  test "$$(qemu-i386 /tmp/lib_dynlib_i386)" = "$$(printf 'strlen: 5\nunloaded: TRUE')" \
	    && echo "  dynlib i386: dlopen/dlsym/dlclose RUN ok under qemu" \
	    || { echo "dynlib i386 run FAIL"; exit 1; }; \
	else echo "  dynlib i386: qemu-i386 absent, run not verified"; fi
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
	test "$$(/tmp/lib_directory)" = "$$(printf 'mkdir=0\nchild=0\nlist=ok\nalpha=1\nchild=1\nalpha-file=1\nchild-dir=1\nalpha-size=1\nstat-file=1\nstat-dir=1\nodir-dir=1\nodir-file-rejected=1')"
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
	# Deterministic now that klondike seeds the built-in System PRNG directly
	# (was drawing from an unseeded generator via a name collision with unit
	# random — bug-lib-test-console-solitaire-flaky). moves=0 = the fixed seed-1
	# deal has no immediate auto-play; klondike move logic is covered by lib_klondike.
	test "$$(printf 'aq' | /tmp/console_solitaire 2>/dev/null | tail -1)" = "moves=0 won=FALSE"
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
	# RSASSA-PSS against a pinned OpenSSL-produced signature (hermetic: the
	# vector is recorded, so no openssl is needed at gate time). PSS is what
	# TLS 1.3 REQUIRES for an RSA CertificateVerify.
	$(PXX_STABLE) -Fulib/rtl test/lib_rsa_pss.pas /tmp/lib_rsa_pss
	test "$$(/tmp/lib_rsa_pss | grep -c '=ok')" = "7"
	test "$$(/tmp/lib_rsa_pss | tail -1)" = "RSAPSS OK"
	$(PXX_STABLE) -Fulib/rtl test/lib_ed25519.pas /tmp/lib_ed25519
	test "$$(/tmp/lib_ed25519 | grep -c '=ok')" = "3"
	test "$$(/tmp/lib_ed25519 | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_ecdsa_p256.pas /tmp/lib_ecdsa
	test "$$(/tmp/lib_ecdsa | grep -c '=ok')" = "2"
	test "$$(/tmp/lib_ecdsa | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_x509.pas /tmp/lib_x509
	test "$$(/tmp/lib_x509 | grep -c '=ok')" = "17"
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
	# the integer parsers: radix prefixes, the Int64 boundaries, and that all
	# four entry points give the SAME answer (they used to disagree). Compiles
	# under FPC; expectations read off it.
	$(PXX_STABLE) -Fulib/rtl test/lib_strtoint.pas /tmp/lib_strtoint
	test "$$(/tmp/lib_strtoint | grep -c '=ok')" = "36"
	test "$$(/tmp/lib_strtoint | tail -1)" = "STRTOINT OK"
	$(PXX_STABLE) -Fulib/rtl test/lib_strutil.pas /tmp/lib_strutil
	test "$$(/tmp/lib_strutil | grep -c '=ok')" = "37"
	test "$$(/tmp/lib_strutil | grep -c 'FAIL')" = "0"
	$(PXX_STABLE) -Fulib/rtl test/lib_format.pas /tmp/lib_format
	test "$$(/tmp/lib_format | grep -c '=ok')" = "27"
	test "$$(/tmp/lib_format | grep -c 'FAIL')" = "0"
	# Format('%.Nf') on the EXACT decimal expansion: no Int64 threshold at
	# ~9e13 (silent) or ~9.2e16 (garbage), and no 10^prec overflow.
	# bug-b-format-fixed-overflows-int64-and-loses-digits
	$(PXX_STABLE) -Fulib/rtl test/lib_format_fixed.pas /tmp/lib_format_fixed
	test "$$(/tmp/lib_format_fixed | grep -c '=ok')" = "40"
	test "$$(/tmp/lib_format_fixed | tail -1)" = "FORMATFIXED OK"
	$(PXX_STABLE) -Fulib/rtl test/lib_paths.pas /tmp/lib_paths
	test "$$(/tmp/lib_paths | grep -c '=ok')" = "20"
	test "$$(/tmp/lib_paths | grep -c 'FAIL')" = "0"
	# FloatToStr against FPC: every expectation in the table came from an
	# FPC-built copy of the same program, so this compiles under FPC too.
	$(PXX_STABLE) -Fulib/rtl test/lib_floattostr.pas /tmp/lib_floattostr
	test "$$(/tmp/lib_floattostr | tail -1)" = "FLOATTOSTR OK"
	# DNS backend selection: the default (dns_wire) must be undisturbed by the
	# new backend, and -dPXX_DNS_RESOLVED must agree with it. Both use only
	# localhost, so neither needs the network; the resolved half skips itself
	# where systemd-resolved is absent, which is a supported configuration.
	$(PXX_STABLE) -Fulib/rtl test/lib_dns_resolved.pas /tmp/lib_dns_wire_default
	test "$$(/tmp/lib_dns_wire_default | tail -1)" = "DNSRESOLVED OK"
	$(PXX_STABLE) -dPXX_DNS_RESOLVED -Fulib/rtl test/lib_dns_resolved.pas /tmp/lib_dns_resolved
	test "$$(/tmp/lib_dns_resolved | tail -1)" = "DNSRESOLVED OK"
	# The getaddrinfo backend, same two ways. Its ABI assertions (struct
	# addrinfo's field offsets, pinned against gcc offsetof) run in the second
	# build and are the load-bearing part: a wrong offset yields a plausible
	# wrong address rather than a failure. -dPXX_DYNLIB_LIBC is required with
	# -dPXX_DNS_LIBC and the build refuses without it; running the libc variant
	# unconditionally follows the existing test_dynlib precedent in `make test`.
	$(PXX_STABLE) -Fulib/rtl test/lib_dns_libc.pas /tmp/lib_dns_libc_default
	test "$$(/tmp/lib_dns_libc_default | tail -1)" = "DNSLIBC OK"
	$(PXX_STABLE) -dPXX_DNS_LIBC -dPXX_DYNLIB_LIBC -Fulib/rtl -Fulib/rtl/platform/posix test/lib_dns_libc.pas /tmp/lib_dns_libc
	test "$$(/tmp/lib_dns_libc | tail -1)" = "DNSLIBC OK"
	# A spawned child inherits the parent's environment (every spawn site used
	# to hard-code an empty envp, i.e. handed each child `env -i`).
	$(PXX_STABLE) -Fulib/rtl test/lib_child_env.pas /tmp/lib_child_env
	test "$$(/tmp/lib_child_env | tail -1)" = "CHILDENV OK"
	# The M_* math constants, and <strings.h>: both were absent, and an
	# undeclared identifier is a silent 0 rather than an error.
	$(PXX_STABLE) test/cmath_constants.c /tmp/cmath_constants
	/tmp/cmath_constants
	$(PXX_STABLE) test/cstrings_bsd.c /tmp/cstrings_bsd
	/tmp/cstrings_bsd
	# The assumed-libc batch: behavioural, and the whole output is diffed
	# against the SAME file built by gcc, so there are no recorded expectations
	# to drift. Cases chosen where these differ from their obvious cousins.
	$(PXX_STABLE) test/cstring_batch.c /tmp/cstring_batch
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -w -o /tmp/cstring_batch_gcc test/cstring_batch.c 2>/dev/null; \
	  /tmp/cstring_batch_gcc > /tmp/cstring_batch_gcc.txt; \
	  /tmp/cstring_batch > /tmp/cstring_batch_pxx.txt; \
	  diff /tmp/cstring_batch_gcc.txt /tmp/cstring_batch_pxx.txt || \
	    { echo 'FAIL: cstring_batch differs from gcc'; exit 1; }; \
	  echo 'cstring_batch: identical to gcc'; \
	else echo 'cstring_batch: SKIP (no gcc)'; /tmp/cstring_batch >/dev/null; fi
	# strerror was a stub returning "error" for every errnum, which made perror
	# and strerror_r useless. Table generated FROM gcc, so both streams are
	# diffed against it — stderr separately, since perror writes there.
	$(PXX_STABLE) test/cerrno_strings.c /tmp/cerrno_strings
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -w -o /tmp/cerrno_strings_gcc test/cerrno_strings.c 2>/dev/null; \
	  /tmp/cerrno_strings_gcc > /tmp/cerrno_gcc.out 2> /tmp/cerrno_gcc.err; \
	  /tmp/cerrno_strings > /tmp/cerrno_pxx.out 2> /tmp/cerrno_pxx.err; \
	  diff /tmp/cerrno_gcc.out /tmp/cerrno_pxx.out && \
	  diff /tmp/cerrno_gcc.err /tmp/cerrno_pxx.err || \
	    { echo 'FAIL: cerrno_strings differs from gcc'; exit 1; }; \
	  echo 'cerrno_strings: identical to gcc'; \
	else echo 'cerrno_strings: SKIP (no gcc)'; /tmp/cerrno_strings >/dev/null 2>&1; fi
	# LINKAGE, not just output: this file calls htons/ntohl, and the whole point
	# of bug-cfront-spurious-dt-needed-libc-with-no-imports is that doing so used
	# to make the binary pull a glibc DT_NEEDED for a function crtl implements.
	# The output diff above cannot see that -- it passes either way on a glibc
	# host -- so assert the linkage directly, or the fix regresses silently and
	# only a cross target without a sysroot ever notices.
	@if command -v readelf >/dev/null 2>&1; then \
	  n=$$(readelf -d /tmp/cerrno_strings 2>/dev/null | grep -c NEEDED); \
	  test "$$n" = "0" || { echo "FAIL: cerrno_strings has $$n DT_NEEDED, want 0"; \
	    readelf -d /tmp/cerrno_strings | grep NEEDED; exit 1; }; \
	  echo 'cerrno_strings: statically linked, no DT_NEEDED'; \
	else echo 'cerrno_strings: linkage check SKIP (no readelf)'; fi
	# printf %a/%A, the +/space flags on float conversions, and NAN's sign.
	# %a was a CRASH off x86-64: it fell to the unknown-conversion path, which
	# did not consume the double, so stack-based varargs shifted and the next
	# %s read a garbage pointer. Diffed against gcc.
	$(PXX_STABLE) test/cprintf_hexfloat.c /tmp/cprintf_hexfloat
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -w -o /tmp/cprintf_hexfloat_gcc test/cprintf_hexfloat.c -lm 2>/dev/null; \
	  /tmp/cprintf_hexfloat_gcc > /tmp/chf_gcc.out; /tmp/cprintf_hexfloat > /tmp/chf_pxx.out; \
	  diff /tmp/chf_gcc.out /tmp/chf_pxx.out || \
	    { echo 'FAIL: cprintf_hexfloat differs from gcc'; exit 1; }; \
	  echo 'cprintf_hexfloat: identical to gcc'; \
	else echo 'cprintf_hexfloat: SKIP (no gcc)'; /tmp/cprintf_hexfloat >/dev/null; fi
	# read/write/close/lseek: declared by <unistd.h>, implemented nowhere until
	# 2026-08-05, so raw I/O silently imported them from glibc. Diffed against
	# gcc; the linkage is asserted too, since the diff passes either way here.
	$(PXX_STABLE) test/cposix_io.c /tmp/cposix_io
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -w -o /tmp/cposix_io_gcc test/cposix_io.c 2>/dev/null; \
	  /tmp/cposix_io_gcc > /tmp/cposix_io_gcc.out; /tmp/cposix_io > /tmp/cposix_io_pxx.out; \
	  diff /tmp/cposix_io_gcc.out /tmp/cposix_io_pxx.out || \
	    { echo 'FAIL: cposix_io differs from gcc'; exit 1; }; \
	  echo 'cposix_io: identical to gcc'; \
	else echo 'cposix_io: SKIP (no gcc)'; /tmp/cposix_io >/dev/null; fi
	# atof/bsearch diffed against gcc; rand asserts only the PROPERTIES C fixes,
	# since the sequence is deliberately not glibc's and must not be compared
	$(PXX_STABLE) test/cstdlib_batch3.c /tmp/cstdlib_batch3
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -w -o /tmp/cstdlib_batch3_gcc test/cstdlib_batch3.c 2>/dev/null; \
	  /tmp/cstdlib_batch3_gcc > /tmp/csb3_gcc.out; /tmp/cstdlib_batch3 > /tmp/csb3_pxx.out; \
	  diff /tmp/csb3_gcc.out /tmp/csb3_pxx.out || \
	    { echo 'FAIL: cstdlib_batch3 differs from gcc'; exit 1; }; \
	  echo 'cstdlib_batch3: identical to gcc'; \
	else echo 'cstdlib_batch3: SKIP (no gcc)'; /tmp/cstdlib_batch3 >/dev/null; fi
	@if command -v readelf >/dev/null 2>&1; then \
	  for b in /tmp/cposix_io /tmp/cstdlib_batch3; do \
	    n=$$(readelf -d $$b 2>/dev/null | grep -c NEEDED); \
	    test "$$n" = "0" || { echo "FAIL: $$b has $$n DT_NEEDED, want 0"; exit 1; }; \
	  done; echo 'cposix_io/cstdlib_batch3: statically linked'; fi
	# <wchar.h>/<wctype.h>: wcslen, the twelve isw* predicates, towlower/towupper.
	# Whole output diffed against gcc -- no recorded expectations -- over the
	# full range -1..255 plus four wide values, because the claim being tested
	# is "everything above 127 is FALSE in the C locale", which a few-letter
	# test would not catch an over-clever implementation failing.
	$(PXX_STABLE) test/cwctype.c /tmp/cwctype
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -w -o /tmp/cwctype_gcc test/cwctype.c 2>/dev/null; \
	  /tmp/cwctype_gcc > /tmp/cwctype_gcc.out; /tmp/cwctype > /tmp/cwctype_pxx.out; \
	  diff /tmp/cwctype_gcc.out /tmp/cwctype_pxx.out || \
	    { echo 'FAIL: cwctype differs from gcc'; exit 1; }; \
	  echo 'cwctype: identical to gcc'; \
	else echo 'cwctype: SKIP (no gcc)'; /tmp/cwctype >/dev/null; fi
	# and it must be STATICALLY linked -- these functions existing as glibc
	# imports is the bug this file was written for, and the output diff above
	# passes either way on a glibc host
	@if command -v readelf >/dev/null 2>&1; then \
	  n=$$(readelf -d /tmp/cwctype 2>/dev/null | grep -c NEEDED); \
	  test "$$n" = "0" || { echo "FAIL: cwctype has $$n DT_NEEDED, want 0"; exit 1; }; \
	  echo 'cwctype: statically linked, no DT_NEEDED'; fi
	# strtol overflow clamping + ERANGE + base-0 octal, and limits.h's LONG_MAX
	# matching the actual width of long. Assertions are target-independent
	# booleans, so the same expected output holds on 32- and 64-bit targets.
	$(PXX_STABLE) test/cstrtol_range.c /tmp/cstrtol_range
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -w -o /tmp/cstrtol_range_gcc test/cstrtol_range.c 2>/dev/null; \
	  /tmp/cstrtol_range_gcc > /tmp/cstrtol_gcc.txt; \
	  /tmp/cstrtol_range > /tmp/cstrtol_pxx.txt; \
	  diff /tmp/cstrtol_gcc.txt /tmp/cstrtol_pxx.txt || \
	    { echo 'FAIL: cstrtol_range differs from gcc'; exit 1; }; \
	  echo 'cstrtol_range: identical to gcc'; \
	else echo 'cstrtol_range: SKIP (no gcc)'; /tmp/cstrtol_range >/dev/null; fi
	# localtime honouring the timezone. Run ONCE PER ZONE with TZ in the
	# environment — glibc caches the zone until tzset(), so a self-contained
	# setenv loop silently compares UTC against UTC and passes for every zone.
	$(PXX_STABLE) test/ctime_localtime.c /tmp/ctime_localtime
	@if command -v gcc >/dev/null 2>&1 && [ -d /usr/share/zoneinfo ]; then \
	  gcc -w -o /tmp/ctime_localtime_gcc test/ctime_localtime.c 2>/dev/null; \
	  for z in UTC Europe/Amsterdam America/New_York Asia/Kolkata Australia/Sydney; do \
	    TZ=$$z /tmp/ctime_localtime_gcc > /tmp/ctl_gcc.txt; \
	    TZ=$$z /tmp/ctime_localtime > /tmp/ctl_pxx.txt; \
	    diff /tmp/ctl_gcc.txt /tmp/ctl_pxx.txt || \
	      { echo "FAIL: ctime_localtime differs from gcc for $$z"; exit 1; }; \
	  done; \
	  echo 'ctime_localtime: identical to gcc (5 zones)'; \
	else echo 'ctime_localtime: SKIP (no gcc or no zoneinfo)'; /tmp/ctime_localtime >/dev/null; fi
	# sscanf's EOF-vs-0 return contract, and the math surface. The boundary
	# cases are the point: EOF means input ran out before any conversion, 0
	# means input was there and did not match, and callers loop on != EOF.
	$(PXX_STABLE) test/cscanf_math.c /tmp/cscanf_math
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -w -o /tmp/cscanf_math_gcc test/cscanf_math.c -lm 2>/dev/null; \
	  /tmp/cscanf_math_gcc > /tmp/csm_gcc.txt 2>&1; \
	  /tmp/cscanf_math > /tmp/csm_pxx.txt 2>&1; \
	  diff /tmp/csm_gcc.txt /tmp/csm_pxx.txt || \
	    { echo 'FAIL: cscanf_math differs from gcc'; exit 1; }; \
	  echo 'cscanf_math: identical to gcc'; \
	else echo 'cscanf_math: SKIP (no gcc)'; /tmp/cscanf_math >/dev/null; fi
	# dup/dup2 — asserted behaviourally (the duplicate reads the same file, and
	# dup2 lands on the descriptor it was given), not just that it returned >= 0.
	$(PXX_STABLE) test/cdup.c /tmp/cdup
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -w -o /tmp/cdup_gcc test/cdup.c 2>/dev/null; \
	  /tmp/cdup_gcc > /tmp/cdup_gcc.txt 2>&1; /tmp/cdup > /tmp/cdup_pxx.txt 2>&1; \
	  diff /tmp/cdup_gcc.txt /tmp/cdup_pxx.txt || \
	    { echo 'FAIL: cdup differs from gcc'; exit 1; }; \
	  echo 'cdup: identical to gcc'; \
	else echo 'cdup: SKIP (no gcc)'; /tmp/cdup >/dev/null; fi
	# chdir/symlink/link. Behavioural: chdir must make a RELATIVE path resolve
	# against the new directory, lstat must see a link where stat follows it.
	# Run from /tmp because the test chdir's around.
	$(PXX_STABLE) test/cfileops.c /tmp/cfileops
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -w -o /tmp/cfileops_gcc test/cfileops.c 2>/dev/null; \
	  (cd /tmp && /tmp/cfileops_gcc) > /tmp/cfo_gcc.txt 2>&1; \
	  (cd /tmp && /tmp/cfileops) > /tmp/cfo_pxx.txt 2>&1; \
	  diff /tmp/cfo_gcc.txt /tmp/cfo_pxx.txt || \
	    { echo 'FAIL: cfileops differs from gcc'; exit 1; }; \
	  echo 'cfileops: identical to gcc'; \
	else echo 'cfileops: SKIP (no gcc)'; (cd /tmp && /tmp/cfileops) >/dev/null; fi
	# struct stat's fields: nlink/uid/gid/rdev and atime/ctime were hardcoded.
	# Asserted through consequences — nlink rises with a hard link and falls
	# when it is removed, a directory's nlink counts its subdirectories.
	$(PXX_STABLE) test/cstat_fields.c /tmp/cstat_fields
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -w -o /tmp/cstat_fields_gcc test/cstat_fields.c 2>/dev/null; \
	  /tmp/cstat_fields_gcc > /tmp/csf_gcc.txt 2>&1; \
	  /tmp/cstat_fields > /tmp/csf_pxx.txt 2>&1; \
	  diff /tmp/csf_gcc.txt /tmp/csf_pxx.txt || \
	    { echo 'FAIL: cstat_fields differs from gcc'; exit 1; }; \
	  echo 'cstat_fields: identical to gcc'; \
	else echo 'cstat_fields: SKIP (no gcc)'; /tmp/cstat_fields >/dev/null; fi
	# Process/user ids, pipe, kill, sleep, getpagesize. Behavioural: the pipe
	# must move bytes and kill(pid,0) must tell a live process from an absent
	# one, so a stub returning success would fail here.
	$(PXX_STABLE) test/cproc_ids.c /tmp/cproc_ids
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -w -o /tmp/cproc_ids_gcc test/cproc_ids.c 2>/dev/null; \
	  /tmp/cproc_ids_gcc > /tmp/cpi_gcc.txt 2>&1; \
	  /tmp/cproc_ids > /tmp/cpi_pxx.txt 2>&1; \
	  diff /tmp/cpi_gcc.txt /tmp/cpi_pxx.txt || \
	    { echo 'FAIL: cproc_ids differs from gcc'; exit 1; }; \
	  echo 'cproc_ids: identical to gcc'; \
	else echo 'cproc_ids: SKIP (no gcc)'; /tmp/cproc_ids >/dev/null; fi
	# isatty via the TCGETS ioctl. Checks /dev/null and a directory as well as
	# a real tty (/dev/ptmx): the tempting fstat+S_ISCHR implementation answers
	# 1 for /dev/null, so a one-sided test would pass against it.
	$(PXX_STABLE) test/cisatty.c /tmp/cisatty
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -w -o /tmp/cisatty_gcc test/cisatty.c 2>/dev/null; \
	  /tmp/cisatty_gcc > /tmp/cia_gcc.txt 2>&1; /tmp/cisatty > /tmp/cia_pxx.txt 2>&1; \
	  diff /tmp/cia_gcc.txt /tmp/cia_pxx.txt || \
	    { echo 'FAIL: cisatty differs from gcc'; exit 1; }; \
	  echo 'cisatty: identical to gcc'; \
	else echo 'cisatty: SKIP (no gcc)'; /tmp/cisatty >/dev/null; fi
	# crtl against gcc's libc, which is the oracle for this surface: the whole
	# output is diffed against the SAME file built by gcc, so there are no
	# recorded expectations to drift.
	$(PXX_STABLE) test/crtl_libc_oracle.c /tmp/crtl_libc_oracle
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -o /tmp/crtl_libc_oracle_gcc test/crtl_libc_oracle.c -lm 2>/dev/null; \
	  /tmp/crtl_libc_oracle_gcc > /tmp/crtl_libc_gcc.txt; \
	  /tmp/crtl_libc_oracle > /tmp/crtl_libc_pxx.txt; \
	  if diff /tmp/crtl_libc_gcc.txt /tmp/crtl_libc_pxx.txt >/dev/null; then \
	    echo "  crtl-oracle: ok (byte-identical to gcc's libc)"; \
	  else \
	    echo "  crtl-oracle: FAIL (diverges from gcc)"; \
	    diff /tmp/crtl_libc_gcc.txt /tmp/crtl_libc_pxx.txt; exit 1; \
	  fi; \
	else echo "  crtl-oracle: SKIP (no gcc to diff against)"; fi
	# setjmp/longjmp + fenv against gcc. Separate file: longjmp unwinds out of
	# the enclosing function, so it must not share a main() with the rest.
	$(PXX_STABLE) test/crtl_setjmp_oracle.c /tmp/crtl_setjmp_oracle
	@if command -v gcc >/dev/null 2>&1; then \
	  gcc -o /tmp/crtl_setjmp_gcc test/crtl_setjmp_oracle.c -lm 2>/dev/null; \
	  /tmp/crtl_setjmp_gcc > /tmp/crtl_setjmp_g.txt; \
	  /tmp/crtl_setjmp_oracle > /tmp/crtl_setjmp_p.txt; \
	  if diff /tmp/crtl_setjmp_g.txt /tmp/crtl_setjmp_p.txt >/dev/null; then \
	    echo "  crtl-setjmp: ok (byte-identical to gcc)"; \
	  else \
	    echo "  crtl-setjmp: FAIL (diverges from gcc)"; \
	    diff /tmp/crtl_setjmp_g.txt /tmp/crtl_setjmp_p.txt; exit 1; \
	  fi; \
	else echo "  crtl-setjmp: SKIP (no gcc to diff against)"; fi
	# exec() as a library, driven from a .npy: the whole output is diffed
	# against CPython's for the same file (test/lib_pyexec.npy is valid .py)
	$(PXX_STABLE) -Fulib/rtl -Fulib/rtl/platform/posix test/lib_pyexec.npy /tmp/lib_pyexec
	test "$$(/tmp/lib_pyexec | tail -1)" = "inner 1099511627776"
	test "$$(/tmp/lib_pyexec | grep -c '^')" = "8"
	@if command -v python3 >/dev/null 2>&1; then \
	  cp test/lib_pyexec.npy /tmp/lib_pyexec_oracle.py; \
	  python3 /tmp/lib_pyexec_oracle.py > /tmp/lib_pyexec_cpython.txt; \
	  /tmp/lib_pyexec > /tmp/lib_pyexec_pxx.txt; \
	  if diff /tmp/lib_pyexec_cpython.txt /tmp/lib_pyexec_pxx.txt >/dev/null; then \
	    echo "  pyexec: ok (byte-identical to CPython)"; \
	  else \
	    echo "  pyexec: FAIL (diverges from CPython)"; \
	    diff /tmp/lib_pyexec_cpython.txt /tmp/lib_pyexec_pxx.txt; exit 1; \
	  fi; \
	else echo "  pyexec: ok (no python3 for the CPython diff)"; fi
	# Format's %g / %e, every row read off an FPC build of the same file
	$(PXX_STABLE) -Fulib/rtl test/lib_format_ge.pas /tmp/lib_format_ge
	test "$$(/tmp/lib_format_ge | grep -c '=ok')" = "31"
	test "$$(/tmp/lib_format_ge | tail -1)" = "FORMATGE OK"
	# TStrings' Name=Value surface, every row read off an FPC build of the
	# same file (it compiles under both)
	$(PXX_STABLE) -Fulib/rtl test/lib_strings_namevalue.pas /tmp/lib_namevalue
	test "$$(/tmp/lib_namevalue | tail -1)" = "NAMEVALUE OK"
	# TStrings.Text at the BYTE level -- CRLF and LF print identically and
	# SetText accepts either, so only the length and the character codes can
	# see the difference. Compiles under FPC too; expectations read off it.
	$(PXX_STABLE) -Fulib/rtl test/lib_strings_text.pas /tmp/lib_strings_text
	test "$$(/tmp/lib_strings_text | grep -c '=ok')" = "11"
	test "$$(/tmp/lib_strings_text | tail -1)" = "STRINGSTEXT OK"
	# markdown against the CommonMark reference (expectations came from
	# markdown-it-py; python-markdown agrees on all but its ul/ol merge quirk)
	$(PXX_STABLE) -Fulib/rtl test/lib_markdown.pas /tmp/lib_markdown
	test "$$(/tmp/lib_markdown | grep -c '=ok')" = "17"
	test "$$(/tmp/lib_markdown | tail -1)" = "MARKDOWN OK"
	@echo "lib-test ok (sudoku exact + collections + math + sysutils + random + randomstate + ipv6 + net6 + asyncnet6 + crtl-inttypes + crtl-trig-huge + crtl-exp2 + crtl-oracle + crtl-setjmp + tk-nilpy + wideint + p256field + bitset + ucomplex + vecmath + bignum-ops + platform + directory + bignum + json + calc + sat + mathf + vm + mandelbrot + raytracer + chess-perft + lisp + zlib + base64 + png smoke + ansiterm + ansirender + process + process-multi + dynlibs + unixshims + strpchar + sockets + sha256-hmac-hkdf + sha512 + tls13-keysched + tls13-record + tls13-hs + chacha20-poly1305 + x25519 + aes-gcm + rsa-verify + rsa-pss + ed25519-verify + ecdsa-p256-verify + x509 + tls-seam + http + http-async + http-redirect + http-keepalive + http-pool + http-pool-concurrent + http-gzip + http-cookie + http-serve + http-json + net-demo + https-mock-seam + dns-async + dns-cache + classes + strutil + streams + format + paths + floattostr + pyexec + format-ge + namevalue + markdown) against stable v$$(cat $(STABLE_DEFAULT_DIR)/VERSION 2>/dev/null || echo '?')"

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
	@echo "=== demos: build ALL examples/* against $(PXX_STABLE) into $(DEMO_OUT)/ ==="
	@mkdir -p $(DEMO_OUT)
	@# A demo that uses palparallel needs --threadsafe (the compiler rejects
	@# `parallel for` without it), so the flag is derived per source.
	@# Discover every example PROGRAM (skip esp32 — cross-only, needs the IDF
	@# toolchain, not $(PXX_STABLE)). Unit search path = each demo's own dir, every
	@# example dir that holds a `unit` (so a cross-dir engine like klondike resolves),
	@# plus the libs. This replaces the old hand-maintained list so a new demo builds
	@# with no Makefile edit.
	@unitdirs=`grep -rlE '^[[:space:]]*unit[[:space:]]' examples --include='*.pas' | grep -v '/esp32/' | xargs -r -n1 dirname | sort -u`; \
	 fu=; for d in $$unitdirs; do fu="$$fu -Fu$$d"; done; \
	 fail=0; n=0; ok=0; \
	 for src in `grep -rlE '^[[:space:]]*program[[:space:]]' examples --include='*.pas' | grep -v '/esp32/' | sort`; do \
	   dir=`dirname $$src`; base=`basename $$src .pas`; n=$$((n+1)); \
	   ts=; grep -qE '^[[:space:]]*uses.*palparallel|\bpalparallel\b' "$$src" && ts=--threadsafe; \
	   if $(PXX_STABLE) $$ts -Fu$$dir $$fu -Fulib/pcl -Fulib/rtl -Fulib/rtl/platform/posix "$$src" "$(DEMO_OUT)/$$base" >$(DEMO_OUT)/.build.log 2>&1; then \
	     printf '  OK    %s\n' "$$src"; ok=$$((ok+1)); \
	   else \
	     printf '  FAIL  %s  -- %s\n' "$$src" "`tail -1 $(DEMO_OUT)/.build.log`"; fail=1; \
	   fi; \
	 done; \
	 echo "=== demos: $$ok/$$n built into $(DEMO_OUT)/ (esp32 skipped — cross-only) ==="; \
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

# Chain validation against a system-style trust store (feature-tls-system-trust-store).
# Generates a root->intermediate->leaf chain with the openssl CLI and asserts the
# accept/reject matrix. Hermetic (no network) but needs openssl, so it is opt-in
# and not in the lib-test gate; skips cleanly when openssl is absent.
truststore-devtest: pxx-stable-check
	tools/truststore_devtest.sh

# From-scratch TLS 1.3 client handshake (phase 1) vs openssl s_server. Opt-in /
# non-hermetic; not in the lib-test gate.
tls13-handshake-devtest: pxx-stable-check
	tools/tls13_handshake_devtest.sh

# The native TLS 1.3 backend through the tls.pas seam: three server signature
# schemes accepted, four refusals (untrusted root, hostname mismatch, empty and
# missing trust file). Opt-in / non-hermetic; not in the lib-test gate.
tls-native-seam-devtest: pxx-stable-check
	tools/tls_native_seam_devtest.sh
