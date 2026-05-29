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

.PHONY: all bootstrap bootstrap-check fpc-check test stabilize check-stable revert benchmark benchmark-check clean distclean

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
	./$(COMPILER) --experimental-ir-codegen test/test_ir_codegen.pas /tmp/test_ir_codegen26
	test "$$(/tmp/test_ir_codegen26)" = "$$(printf '15\nOK')"
	./$(COMPILER) --experimental-ir-codegen test/test_ir_codegen_fail.pas /tmp/test_ir_codegen_fail26
	test "$$(/tmp/test_ir_codegen_fail26)" = "$$(printf '15\nFAIL')"
	./$(COMPILER) --experimental-ir-codegen test/test_ir_unary.pas /tmp/test_ir_unary26
	test "$$(/tmp/test_ir_unary26)" = "$$(printf '%s\nOK' '-5')"
	./$(COMPILER) --experimental-ir-codegen test/test_ir_deref.pas /tmp/test_ir_deref26
	test "$$(/tmp/test_ir_deref26)" = "$$(printf '10\n20\n100\n200')"
	./$(COMPILER) --experimental-ir-codegen test/test_ir_call.pas /tmp/test_ir_call26
	test "$$(/tmp/test_ir_call26)" = "$$(printf '30\n30\n42')"
	./$(COMPILER) --experimental-ir-codegen test/test_ir_binops.pas /tmp/test_ir_binops26
	test "$$(/tmp/test_ir_binops26)" = "$$(printf -- '-3\n-2\n3\n2\n8\n14\n0\n1\n25')"
	./$(COMPILER) test/test_shared_object.pas /tmp/shared_object26
	test "$$(/tmp/shared_object26)" = "97"
	./$(COMPILER) test/test_c_import.pas /tmp/c_import26
	test "$$(/tmp/c_import26)" = "42"
	./$(COMPILER) test/test_c_preprocess.pas /tmp/c_preprocess26
	test "$$(/tmp/c_preprocess26)" = "42"
	./$(COMPILER) --debug test/test_c_preprocess.pas /tmp/c_preprocess_debug26 > /tmp/c_preprocess_debug26.log
	grep -q "C preprocessor: expand function" /tmp/c_preprocess_debug26.log
	test "$$(/tmp/c_preprocess_debug26)" = "42"
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
	./$(COMPILER) test/test_heap.pas /tmp/test_heap26
	test "$$(/tmp/test_heap26)" = "$$(printf '1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_class.pas /tmp/test_class26
	test "$$(/tmp/test_class26)" = "$$(printf '1\n1\n1\n42\n100\n999\n888')"
	./$(COMPILER) test/test_class_methods.pas /tmp/test_class_methods26
	test "$$(/tmp/test_class_methods26)" = "3"
	./$(COMPILER) test/test_static_methods.pas /tmp/test_static_methods26
	test "$$(/tmp/test_static_methods26)" = "$$(printf '7\n11\n25')"
	./$(COMPILER) test/test_write_fmt.pas /tmp/test_write_fmt26
	test "$$(/tmp/test_write_fmt26)" = "$$(printf '    42\n    -7\n1000\n  0\n    hi\n   ab\n99\nx')"
	./$(COMPILER) test/test_math_unit.pas /tmp/test_math_unit26
	test "$$(/tmp/test_math_unit26)" = "$$(printf '42\n999\n10\n20\n256\n6\n144')"
	./$(COMPILER) test/test_generic_func.pas /tmp/test_generic_func26
	test "$$(/tmp/test_generic_func26)" = "$$(printf '7\n10\n3\n4\n5\n1\n10\n99\n42')"
	./$(COMPILER) test/test_overloading.pas /tmp/test_overloading26
	test "$$(/tmp/test_overloading26)" = "$$(printf 'Integer: 42\nChar: 65\nTwo Integers: 10, 20\nAdd integers: 12\nChar addition: XY')"
	./$(COMPILER) test/test_op_overload.pas /tmp/test_op_overload26
	test "$$(/tmp/test_op_overload26)" = "$$(printf '1\n0\n1\n0\n1\n0\n10\n6')"
	./$(COMPILER) test/test_loop_control.pas /tmp/test_loop_control26
	test "$$(/tmp/test_loop_control26)" = "$$(printf '8\n5\n8\n7\n3')"
	./$(COMPILER) test/test_pascal_directives.pas /tmp/test_pascal_directives26
	test "$$(/tmp/test_pascal_directives26)" = "$$(printf '1\n0\n1\n1\n1\n0\n1\n1\n1')"
	./$(COMPILER) -dCLI_FLAG test/test_pascal_directives.pas /tmp/test_pascal_directives_defined26
	test "$$(/tmp/test_pascal_directives_defined26)" = "$$(printf '1\n0\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_strict_overload.pas /tmp/test_strict_overload26
	test "$$(/tmp/test_strict_overload26)" = "$$(printf '5\n65')"
	! ./$(COMPILER) test/test_strict_overload_error.pas /tmp/test_strict_overload_error26 > /tmp/test_strict_overload_error.log 2>&1
	grep -q "overloaded routine requires overload directive" /tmp/test_strict_overload_error.log
	./$(COMPILER) --strict-overload test/test_overloading.pas /tmp/test_overloading_strict26
	test "$$(/tmp/test_overloading_strict26)" = "$$(printf 'Integer: 42\nChar: 65\nTwo Integers: 10, 20\nAdd integers: 12\nChar addition: XY')"
	./$(COMPILER) test/test_sizeof.pas /tmp/test_sizeof26
	test "$$(/tmp/test_sizeof26)" = "$$(printf '1\n1\n2\n2\n4\n4\n4\n4\n8\n8\n8\n8\n8\n8\n8\n1\n1')"
	! ./$(COMPILER) test/test_sizeof_error.pas /tmp/test_sizeof_error26 > /tmp/test_sizeof_error.log 2>&1
	grep -q "SizeOf: unknown type" /tmp/test_sizeof_error.log
	./$(COMPILER) test/test_type_runtime.pas /tmp/test_type_runtime26
	test "$$(/tmp/test_type_runtime26)" = "$$(printf '1\n1\n1\n0\n1\n18446744065119617025\n18446744073709551615\n9223372036854775807\n1\n-1\n-1\n-1\n18446744073709551615\n-1\n0\n2\n7\n123456\n9\n20')"
	./$(COMPILER) test/test_float.pas /tmp/test_float26
	test "$$(/tmp/test_float26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_dynarray.pas /tmp/test_dynarray26
	test "$$(/tmp/test_dynarray26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_float_literals.pas /tmp/test_float_literals26
	test "$$(/tmp/test_float_literals26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_float_write.pas /tmp/test_float_write26
	test "$$(/tmp/test_float_write26)" = "$$(printf '3.50\n4\n-2.750\n1.0\n0.00\n10.5\n 1.000000000000000E+000\n-2.000000000000000E+000\n 0.000000000000000E+000\n 3.500000000000000E+000\n 1.234500000000000E+003')"
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
	! ./$(COMPILER) test/test_reraise_error.pas /tmp/test_reraise_error26 > /tmp/test_reraise_error.log 2>&1
	grep -q "raise without expression requires an exception handler" /tmp/test_reraise_error.log
	./$(COMPILER) test/test_exception_unit_unhandled.pas /tmp/test_exception_unit_unhandled26
	! /tmp/test_exception_unit_unhandled26 > /tmp/test_exception_unit_unhandled.out 2> /tmp/test_exception_unit_unhandled.log
	grep -q "Unhandled exception" /tmp/test_exception_unit_unhandled.log
	./$(COMPILER) test/test_exception_unhandled.pas /tmp/test_exception_unhandled26
	! /tmp/test_exception_unhandled26 > /tmp/test_exception_unhandled.out 2> /tmp/test_exception_unhandled.log
	grep -q "Unhandled exception" /tmp/test_exception_unhandled.log
	test ! -s /tmp/test_exception_unhandled.out
	./$(COMPILER) --no-unhandled-handler test/test_exception_unhandled.pas /tmp/test_exception_silent26
	! /tmp/test_exception_silent26 > /tmp/test_exception_silent.out 2> /tmp/test_exception_silent.log
	test ! -s /tmp/test_exception_silent.log
	./$(COMPILER) -fno-unhandled-handler test/test_exception_unhandled.pas /tmp/test_exception_silent_alias26
	! /tmp/test_exception_silent_alias26 > /tmp/test_exception_silent_alias.out 2> /tmp/test_exception_silent_alias.log
	test ! -s /tmp/test_exception_silent_alias.log
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
	/tmp/pascal26-self test/test_heap.pas /tmp/self-test_heap26
	test "$$(/tmp/self-test_heap26)" = "$$(printf '1\n1\n1\n1\n1\n1')"
	/tmp/pascal26-self test/test_math_unit.pas /tmp/self-test_math_unit26
	test "$$(/tmp/self-test_math_unit26)" = "$$(printf '42\n999\n10\n20\n256\n6\n144')"
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
	/tmp/pascal26-next test/test_heap.pas /tmp/next-test_heap26
	test "$$(/tmp/next-test_heap26)" = "$$(printf '1\n1\n1\n1\n1\n1')"
	/tmp/pascal26-next test/test_math_unit.pas /tmp/next-test_math_unit26
	test "$$(/tmp/next-test_math_unit26)" = "$$(printf '42\n999\n10\n20\n256\n6\n144')"
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
	@NV=$$(( $$(cat $(STABLE_DIR)/VERSION) + 1 )); \
	 echo $$NV > $(STABLE_DIR)/VERSION; \
	 cp /tmp/pascal26-s5 $(STABLE_DIR)/pascal26-v$$NV; \
	 cp /tmp/pascal26-s5 $(STABLE_DIR)/pascal26-stable; \
	 SHA=$$(sha256sum $(STABLE_DIR)/pascal26-stable | awk '{print $$1}'); \
	 echo "$$SHA  pascal26-stable" > $(STABLE_DIR)/last.sha256; \
	 printf '%s  v%s  %s  %s  %s\n' \
	   "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$NV" "$$SHA" \
	   "$$(git log -1 --format='%H')" \
	   "$$(git log -1 --format='%s')" \
	   >> $(STABLE_DIR)/history.log; \
	 echo "STABLE v$$NV OK: $$SHA"

check-stable:
	@test -f $(STABLE_DIR)/pascal26-stable || \
	  (echo "No stable binary. Run: make stabilize"; exit 1)
	@(cd $(STABLE_DIR) && sha256sum -c last.sha256) && \
	  echo "Stable v$$(cat $(STABLE_DIR)/VERSION) OK: $$(cat $(STABLE_DIR)/last.sha256)" || \
	  (echo "MISMATCH: stable binary does not match last.sha256"; exit 1)

revert:
	@V=$$(cat $(STABLE_DIR)/VERSION); \
	 TV=$${VERSION:-$$((V-1))}; \
	 test "$$TV" -ge 1 2>/dev/null || (echo "Usage: make revert VERSION=N"; exit 1); \
	 test "$$TV" -le "$$V" || (echo "v$$TV does not exist (current is v$$V)"; exit 1); \
	 test -f $(STABLE_DIR)/pascal26-v$$TV || \
	   (echo "Binary stable/pascal26-v$$TV missing — may need to rebuild from that commit"; exit 1); \
	 cp $(STABLE_DIR)/pascal26-v$$TV $(COMPILER); \
	 echo "Reverted $(COMPILER) to stable v$$TV (was v$$V)"; \
	 echo "Run 'make test' to verify, or 'make stabilize' to record as new stable."

clean:
	rm -f compiler/*.o compiler/*.ppu

distclean: clean
	rm -f $(COMPILER)
