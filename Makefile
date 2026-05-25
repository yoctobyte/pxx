FPC     ?= fpc
FPCFLAGS = -O2 -Tlinux -Px86_64
HYPERFINE ?= hyperfine
BENCH_RUNS ?= 30
BENCH_HELLO_RUNS ?= 10
BENCH_BATCH ?= 20

COMPILER     := compiler/pascal26
COMPILER_SRC := compiler/compiler.pas
COMPILER_INC := $(wildcard compiler/*.inc)
FPC_COMPILER := /tmp/pascal26-fpc
BUILD_COMPILER := /tmp/pascal26-build
VERIFY_COMPILER := /tmp/pascal26-verify

STABLE_DIR := stable

.PHONY: all bootstrap bootstrap-check fpc-check test stabilize check-stable benchmark benchmark-check clean distclean

all: $(COMPILER)

bootstrap-check:
	@which $(FPC) > /dev/null 2>&1 || \
	  (echo "fpc not found. Install: sudo apt install fpc"; exit 1)

bootstrap: bootstrap-check
	$(FPC) $(FPCFLAGS) -o$(FPC_COMPILER) $(COMPILER_SRC)
	$(FPC_COMPILER) $(COMPILER_SRC) $(BUILD_COMPILER)
	$(BUILD_COMPILER) $(COMPILER_SRC) $(VERIFY_COMPILER)
	cmp $(BUILD_COMPILER) $(VERIFY_COMPILER)
	mv $(BUILD_COMPILER) $(COMPILER)

$(COMPILER): $(COMPILER_SRC) $(COMPILER_INC)
	@test -x $(COMPILER) || \
	  (echo "self-hosted compiler seed missing. Run: make bootstrap"; exit 1)
	./$(COMPILER) $(COMPILER_SRC) $(BUILD_COMPILER)
	$(BUILD_COMPILER) $(COMPILER_SRC) $(VERIFY_COMPILER)
	cmp $(BUILD_COMPILER) $(VERIFY_COMPILER)
	mv $(BUILD_COMPILER) $(COMPILER)

fpc-check: bootstrap-check $(COMPILER)
	$(FPC) $(FPCFLAGS) -o$(FPC_COMPILER) $(COMPILER_SRC)
	$(FPC_COMPILER) $(COMPILER_SRC) /tmp/pascal26-from-fpc
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
	  --command-name 'self-hosted pascal26: $(BENCH_BATCH) x hello' 'for i in $$(seq 1 $(BENCH_BATCH)); do ./$(COMPILER) test/hello.pas /tmp/hello-bench-self >/dev/null; done'
	stat -c '%n %s bytes' /tmp/pascal26-bench-fpc /tmp/pascal26-bench-self /tmp/hello-bench-fpc /tmp/hello-bench-self
	test "$$(/tmp/hello-bench-fpc)" = "Hello, World!"
	test "$$(/tmp/hello-bench-self)" = "Hello, World!"
	/tmp/pascal26-bench-self test/hello.pas /tmp/bench-compiler-hello >/dev/null
	test "$$(/tmp/bench-compiler-hello)" = "Hello, World!"

test: $(COMPILER) fpc-check
	./$(COMPILER) test/hello.pas /tmp/hello26
	test "$$(/tmp/hello26)" = "Hello, World!"
	./$(COMPILER) test/bootstrap_features.pas /tmp/bootstrap_features26
	test "$$(/tmp/bootstrap_features26)" = "$$(printf '120\n98\ncase-ok\n0')"
	./$(COMPILER) test/paramcount_if.pas /tmp/paramcount_if26
	test "$$(/tmp/paramcount_if26 dummy)" = "argc-ok"
	./$(COMPILER) test/records.pas /tmp/records26
	test "$$(/tmp/records26)" = "$$(printf '42\n7\n11\n22')"
	./$(COMPILER) test/fileio.pas /tmp/fileio26
	test "$$(/tmp/fileio26 test/hello.pas | sed -n '1,3p')" = "$$(printf 'test/hello.pas\n14\n54')"
	./$(COMPILER) test/string_compare.pas /tmp/string_compare26
	test "$$(/tmp/string_compare26)" = "$$(printf '1\n1\n1')"
	./$(COMPILER) test/record_string_field.pas /tmp/record_string_field26
	test "$$(/tmp/record_string_field26)" = "$$(printf '1\n4')"
	./$(COMPILER) test/vars.pas /tmp/vars26
	test "$$(/tmp/vars26)" = "$$(printf 'Sum: 42\nCountdown:\n5\n4\n3\n2\n1\nSquares:\n1\n4\n9\n16\n25\nbig\nloop 0\nloop 1\nloop 2')"
	./$(COMPILER) test/arrays.pas /tmp/arrays26
	test "$$(/tmp/arrays26)" = "$$(printf 'Squares:\n0\n1\n4\n9\n16\n25\n36\n49\n64\n81\nH\ni\n!')"
	./$(COMPILER) test/strings.pas /tmp/strings26
	test "$$(/tmp/strings26)" = "$$(printf 'Hello, World!\nPascal26\n13\nPascal26\n8')"
	./$(COMPILER) $(COMPILER_SRC) /tmp/pascal26-self
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
	/tmp/pascal26-self test/fileio.pas /tmp/self-fileio26
	test "$$(/tmp/self-fileio26 test/hello.pas | sed -n '1,3p')" = "$$(printf 'test/hello.pas\n14\n54')"
	/tmp/pascal26-self $(COMPILER_SRC) /tmp/pascal26-next
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
	/tmp/pascal26-next test/fileio.pas /tmp/next-fileio26
	test "$$(/tmp/next-fileio26 test/hello.pas | sed -n '1,3p')" = "$$(printf 'test/hello.pas\n14\n54')"
	/tmp/pascal26-next $(COMPILER_SRC) /tmp/pascal26-fixedpoint
	cmp /tmp/pascal26-next /tmp/pascal26-fixedpoint

stabilize: test
	@echo "=== stabilize: 4-iteration fixedpoint check ==="
	/tmp/pascal26-fixedpoint $(COMPILER_SRC) /tmp/pascal26-s4
	cmp /tmp/pascal26-next /tmp/pascal26-s4
	/tmp/pascal26-s4 $(COMPILER_SRC) /tmp/pascal26-s5
	cmp /tmp/pascal26-next /tmp/pascal26-s5
	@echo "=== recording stable binary ==="
	@mkdir -p $(STABLE_DIR)
	@cp /tmp/pascal26-s5 $(STABLE_DIR)/pascal26-stable
	@sha256sum $(STABLE_DIR)/pascal26-stable | sed 's|$(STABLE_DIR)/||' > $(STABLE_DIR)/last.sha256
	@printf '%s  %s  %s  %s\n' \
	  "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	  "$$(awk '{print $$1}' $(STABLE_DIR)/last.sha256)" \
	  "$$(git log -1 --format='%H')" \
	  "$$(git log -1 --format='%s')" \
	  >> $(STABLE_DIR)/history.log
	@echo "STABLE OK: $$(cat $(STABLE_DIR)/last.sha256)"

check-stable:
	@test -f $(STABLE_DIR)/pascal26-stable || \
	  (echo "No stable binary. Run: make stabilize"; exit 1)
	@(cd $(STABLE_DIR) && sha256sum -c last.sha256) && \
	  echo "Stable binary OK: $$(cat $(STABLE_DIR)/last.sha256)" || \
	  (echo "MISMATCH: stable binary does not match last.sha256"; exit 1)

clean:
	rm -f compiler/*.o compiler/*.ppu

distclean: clean
	rm -f $(COMPILER)
