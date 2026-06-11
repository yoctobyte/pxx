FPC     ?= fpc
FPCFLAGS = -O2 -Tlinux -Px86_64
HYPERFINE ?= hyperfine
BENCH_RUNS ?= 30
BENCH_HELLO_RUNS ?= 10
BENCH_BATCH ?= 20
BENCH_RUNTIME_RUNS ?= 30

COMPILER     := compiler/pascal26
COMPILER_MANAGED := compiler/pascal26-managed
COMPILER_SRC := compiler/compiler.pas
COMPILER_INC := $(wildcard compiler/*.inc)
FPC_COMPILER := /tmp/pascal26-fpc
BUILD_COMPILER := /tmp/pascal26-build
VERIFY_COMPILER := /tmp/pascal26-verify
BUILD_COMPILER_MANAGED  := /tmp/pascal26-managed-build
VERIFY_COMPILER_MANAGED := /tmp/pascal26-managed-verify

STABLE_ROOT := stable_linux_amd64
STABLE_DEFAULT_DIR := $(STABLE_ROOT)/default
STABLE_MANAGED_DIR := $(STABLE_ROOT)/managed
PXXFLAGS   :=

.PHONY: all bootstrap bootstrap-check fpc-check test test-nilpy qemu-env-check test-i386 test-aarch64 test-arm32 stabilize check-stable revert benchmark benchmark-compiler-runtime benchmark-check clean distclean symbols \
        bootstrap-managed test-managed stabilize-managed check-stable-managed revert-managed test-nilpy-managed \
        progress-check

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
	$(FPC_COMPILER) $(COMPILER_SRC) $(BUILD_COMPILER)
	$(BUILD_COMPILER) $(COMPILER_SRC) $(VERIFY_COMPILER)
	cmp $(BUILD_COMPILER) $(VERIFY_COMPILER)
	mv $(BUILD_COMPILER) $(COMPILER)

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
	@if [ "$(COMPILER)" = "compiler/pascal26-managed" ]; then \
	  $(FPC_COMPILER) -dPXX_MANAGED_STRING $(COMPILER_SRC) /tmp/pascal26-from-fpc; \
	else \
	  $(FPC_COMPILER) $(COMPILER_SRC) /tmp/pascal26-from-fpc; \
	fi
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

test-nilpy: $(COMPILER)
	./$(COMPILER) test/test_nil_python_core.npy /tmp/test_nil_python_core26
	test "$$(/tmp/test_nil_python_core26)" = "$$(printf '0\n1\n1\n2\n3\n5\n10')"
	./$(COMPILER) test/test_nilpy_import_sqlite.npy /tmp/test_nilpy_import_sqlite26
	test "$$(/tmp/test_nilpy_import_sqlite26)" = "3045001"
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
	test "$$(/tmp/test_nilpy_bool26)" = "$$(printf '1\n1\n1\n0\n1\n1')"
	./$(COMPILER) test/test_nilpy_str_float.npy /tmp/test_nilpy_str_float26
	test "$$(/tmp/test_nilpy_str_float26)" = "$$(printf '3.14\n2.5\n-1.25\npi=3.14159\n3\n2')"
	! ./$(COMPILER) test/test_nilpy_slash_fail.npy /tmp/test_nilpy_slash_fail26 > /tmp/test_nilpy_slash_fail.log 2>&1
	grep -q "unsupported operator /; use // for integer division" /tmp/test_nilpy_slash_fail.log
	./$(COMPILER) test/test_nilpy_string_variant.npy /tmp/test_nilpy_string_variant26
	test "$$(/tmp/test_nilpy_string_variant26)" = "$$(printf '5\napple\n1\n0\n0\n1\n1\n1\n0\n0\n1\n1\n0\n1\n0\n0\nhello world\nhello potato\ngreen world')"
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

test-managed: COMPILER := $(COMPILER_MANAGED)
test-managed: PXXFLAGS := -dPXX_MANAGED_STRING
test-managed: test

test-nilpy-managed: COMPILER := $(COMPILER_MANAGED)
test-nilpy-managed: PXXFLAGS := -dPXX_MANAGED_STRING
test-nilpy-managed: test-nilpy

test: $(COMPILER) fpc-check
	./$(COMPILER) test/test_ansistring.pas /tmp/test_ansistring26
	test "$$(/tmp/test_ansistring26)" = "$$(printf '0\nInitially empty ok\nHello\n5\nHello\nAssignment equal ok\nhello\nHello\nCOW index write ok\nLocalString\n11\nLocal equal ok\nX\nChar assign ok\nHello World!\nHello\nHello World!\n0\nClear empty ok')"
	./$(COMPILER) test/test_dynarray_field.pas /tmp/test_dynarray_field26
	test "$$(/tmp/test_dynarray_field26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_collections.pas /tmp/test_collections26
	test "$$(/tmp/test_collections26)" = "$$(printf '100\n0\n81\n9801\n7\n328276\n0\n3\nalpha\ngamma\nBETA')"
	./$(COMPILER) test/test_managed_var_param.pas /tmp/test_managed_var_param26
	test "$$(/tmp/test_managed_var_param26)" = "$$(printf '1\n1\n1\n1\n1\n6')"
	./$(COMPILER) test/test_managed_setlength_var.pas /tmp/test_managed_setlength_var26
	test "$$(/tmp/test_managed_setlength_var26)" = "$$(printf '1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_managed_setlength_growth.pas /tmp/test_managed_setlength_growth26
	test "$$(/tmp/test_managed_setlength_growth26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_default_keyword.pas /tmp/test_default_keyword26
	test "$$(/tmp/test_default_keyword26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_op_record_result.pas /tmp/test_op_record_result26
	test "$$(/tmp/test_op_record_result26)" = "$$(printf '4 6\n4 6\n5 8\n4 6\n4 6\n4 6\n5 8\n110 220 330\n110 220 330')"
	./$(COMPILER) test/hello.pas /tmp/hello26
	test "$$(/tmp/hello26)" = "Hello, World!"
	test "$$(stat -c '%s' /tmp/hello26)" = "287"
	./$(COMPILER) test/hello.c /tmp/hello_c26
	test "$$(/tmp/hello_c26)" = "Hello, World!"
	./$(COMPILER) test/test_asm.pas /tmp/test_asm26
	/tmp/test_asm26; test "$$?" = "42"
	./$(COMPILER) test/test_asm_func.pas /tmp/test_asm_func26
	test "$$(/tmp/test_asm_func26)" = "14"
	./$(COMPILER) test/test_asm_swap.pas /tmp/test_asm_swap26
	test "$$(/tmp/test_asm_swap26)" = "$$(printf '42\n-7\n-7\n42')"
	./$(COMPILER) test/test_procaddr.pas /tmp/test_procaddr26
	test "$$(/tmp/test_procaddr26)" = "1 2 3 4 5 "
	./$(COMPILER) test/test_methodptr.pas /tmp/test_methodptr26
	test "$$(/tmp/test_methodptr26)" = "$$(printf 'code set\ndata ok')"
	./$(COMPILER) test/test_const_record_param.pas /tmp/test_const_record_param26
	test "$$(/tmp/test_const_record_param26)" = "111 222"
	./$(COMPILER) test/test_virtual_proc.pas /tmp/test_virtual_proc26
	test "$$(/tmp/test_virtual_proc26)" = "$$(printf 'B\nB')"
	./$(COMPILER) test/test_ir_virtual_call.pas /tmp/test_ir_virtual_call26
	test "$$(/tmp/test_ir_virtual_call26)" = "$$(printf '1\n2\n1\n2')"
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
	./$(COMPILER) test/test_ir_codegen_fail.pas /tmp/test_ir_codegen_fail26
	test "$$(/tmp/test_ir_codegen_fail26)" = "$$(printf '15\nFAIL')"
	./$(COMPILER) test/test_ir_unary.pas /tmp/test_ir_unary26
	test "$$(/tmp/test_ir_unary26)" = "$$(printf '%s\nOK' '-5')"
	./$(COMPILER) test/test_ir_deref.pas /tmp/test_ir_deref26
	test "$$(/tmp/test_ir_deref26)" = "$$(printf '10\n20\n100\n200')"
	./$(COMPILER) test/test_ir_call.pas /tmp/test_ir_call26
	test "$$(/tmp/test_ir_call26)" = "$$(printf '30\n30\n42')"
	./$(COMPILER) test/test_ir_binops.pas /tmp/test_ir_binops26
	test "$$(/tmp/test_ir_binops26)" = "$$(printf -- '-3\n-2\n3\n2\n8\n14\n0\n1\n25')"
	./$(COMPILER) test/test_shl.pas /tmp/test_shl26
	test "$$(/tmp/test_shl26)" = "$$(printf '16\n12\n9')"
	./$(COMPILER) test/test_op_overload.pas /tmp/test_op_overload_ir26
	test "$$(/tmp/test_op_overload_ir26)" = "$$(printf '1\n0\n1\n0\n1\n0\n10\n6')"
	./$(COMPILER) test/test_overloading.pas /tmp/test_overloading_ir26
	test "$$(/tmp/test_overloading_ir26)" = "$$(printf 'Integer: 42\nChar: A\nTwo Integers: 10, 20\nAdd integers: 12\nChar addition: XY')"
	./$(COMPILER) test/test_float_write.pas /tmp/test_float_write_ir26
	test "$$(/tmp/test_float_write_ir26)" = "$$(printf '3.50\n4\n-2.750\n1.0\n0.00\n10.5\n 1.000000000000000E+000\n-2.000000000000000E+000\n 0.000000000000000E+000\n 3.500000000000000E+000\n 1.234500000000000E+003')"
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
	./$(COMPILER) test/test_c_float.pas /tmp/c_float26
	test "$$(/tmp/c_float26)" = "$$(printf '1024.0\n16.0\n12.0')"
	cc -shared -fPIC -o /tmp/libspill.so test/spill_lib.c
	./$(COMPILER) test/test_c_argspill.pas /tmp/c_argspill26
	test "$$(LD_LIBRARY_PATH=/tmp /tmp/c_argspill26)" = "$$(printf '28\n55.0\n45')"
	./$(COMPILER) test/test_sqlite_crud.pas /tmp/sqlite_crud26
	test "$$(/tmp/sqlite_crud26)" = "$$(printf 'open=0\nprepare=0\n1 alice\n2 bob\nfinalize=0\nclose=0')"
	./$(COMPILER) test/test_string_to_pchar_auto.pas /tmp/string_to_pchar_auto26
	test "$$(/tmp/string_to_pchar_auto26)" = "$$(printf 'open=0\nprepare=0\n1 alice\n2 bob\nfinalize=0\nclose=0')"
	./$(COMPILER) test/test_auto_var.pas /tmp/test_auto_var26
	test "$$(/tmp/test_auto_var26)" = "$$(printf 'Global tests:\ng_int = 456\ng_str = hello global\ng_bool is False\ng_dbl = 3.14\nLocal tests:\nl_int = 123\nl_str = hello local\nl_bool is True\nl_rec = 10, 20\np_rec^ = 10, 20\nall auto variable tests done!')"
	./$(COMPILER) test/test_sqlite_crud_autotyped.pas /tmp/test_sqlite_crud_autotyped26
	test "$$(/tmp/test_sqlite_crud_autotyped26)" = "$$(printf 'open=0\nprepare=0\n1 alice\n2 bob\nfinalize=0\nclose=0')"
	! ./$(COMPILER) test/test_auto_var_fail.pas /tmp/test_auto_var_fail26 > /tmp/test_auto_var_fail.log 2>&1
	grep -q "use of auto variable before type is inferred" /tmp/test_auto_var_fail.log
	./$(COMPILER) test/test_lazy_var.pas /tmp/test_lazy_var26
	test "$$(/tmp/test_lazy_var26)" = "$$(printf 'Basic tests:\na = 123\nb = hello inline\nc = 3.14\nd is True\nScoping tests:\nouter x = 10\ninner x = 20\ninner y = 30\nouter x after block = 10\nMultiple declarations:\nx = 42, y = 24\nall lazy variable tests done!')"
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
	test "$$(/tmp/test_c_packed_aligned26)" = "$$(printf 'X\n42\nPackedStruct is opaque\nAlignedStruct is opaque')"
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
	./$(COMPILER) test/test_class_methods.pas /tmp/test_class_methods26
	test "$$(/tmp/test_class_methods26)" = "3"
	./$(COMPILER) test/test_visibility.pas /tmp/test_visibility26
	test "$$(/tmp/test_visibility26)" = "$$(printf '7\n3\n42\n99\n123')"
	./$(COMPILER) test/test_ptr_alias.pas /tmp/test_ptr_alias26
	test "$$(/tmp/test_ptr_alias26)" = "$$(printf '777\n888\n12\n34\n20\n30\n99\n55')"
	./$(COMPILER) test/test_ptr_deref_field.pas /tmp/test_ptr_deref_field26
	test "$$(/tmp/test_ptr_deref_field26)" = "$$(printf '10\n20\n42\n99\n1234\n5\n9999\n100\n300\n777')"
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
	grep -q "prop Caption tk=4" /tmp/test_rtti_emit_dump26.log
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
	./$(COMPILER) test/test_case_insensitive.pas /tmp/test_case_insensitive26
	test "$$(/tmp/test_case_insensitive26)" = "42"
	./$(COMPILER) test/test_case_sensitive.pas /tmp/test_case_sensitive26
	test "$$(/tmp/test_case_sensitive26)" = "$$(printf '10\n20\nupper\nlower')"
	! ./$(COMPILER) test/test_case_sensitive_error.pas /tmp/test_case_sensitive_error26 > /tmp/test_case_sensitive_error.log 2>&1
	grep -q "undefined variable (VALUE)" /tmp/test_case_sensitive_error.log
	./$(COMPILER) test/test_case_sensitive_unit.pas /tmp/test_case_sensitive_unit26
	test "$$(/tmp/test_case_sensitive_unit26)" = "$$(printf 'unit\n7')"
	./$(COMPILER) test/test_qualified_units.pas /tmp/test_qualified_units26
	test "$$(/tmp/test_qualified_units26)" = "$$(printf '3\n7\n11\n22\n101\n201')"
	./$(COMPILER) test/test_relpath_uses.pas /tmp/test_relpath_uses26
	test "$$(/tmp/test_relpath_uses26)" = "$$(printf '13\n15\n100')"
	./$(COMPILER) test/test_syncobjs.pas /tmp/test_syncobjs26
	test "$$(/tmp/test_syncobjs26)" = "$$(printf '1\n2\n3')"
	./$(COMPILER) test/test_getmem_proc.pas /tmp/test_getmem_proc26
	test "$$(/tmp/test_getmem_proc26)" = "$$(printf '1\n65\n66\n90\n1')"
	./$(COMPILER) test/test_freemem.pas /tmp/test_freemem26
	test "$$(/tmp/test_freemem26)" = "$$(printf '1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_new_dispose.pas /tmp/test_new_dispose26
	test "$$(/tmp/test_new_dispose26)" = "$$(printf '1234\n16\n1')"
	./$(COMPILER) test/test_reallocmem.pas /tmp/test_reallocmem26
	test "$$(/tmp/test_reallocmem26)" = "$$(printf '1\n50\n1\n1\n1\n77')"
	./$(COMPILER) test/test_str_val.pas /tmp/test_str_val26
	test "$$(/tmp/test_str_val26)" = "$$(printf '42\n-7\n0\n[  1234]\n100\n0\n-25\n0\n2\n1')"
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
	./$(COMPILER) -dCLI_FLAG test/test_pascal_directives.pas /tmp/test_pascal_directives_defined26
	test "$$(/tmp/test_pascal_directives_defined26)" = "$$(printf '1\n0\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_pascal_directive_messages.pas /tmp/test_pascal_directive_messages26 > /tmp/test_pascal_directive_messages.log
	grep -q "warning: warning text" /tmp/test_pascal_directive_messages.log
	grep -q "message: message text" /tmp/test_pascal_directive_messages.log
	! ./$(COMPILER) test/test_pascal_directive_error.pas /tmp/test_pascal_directive_error26 > /tmp/test_pascal_directive_error.log 2>&1
	grep -q "requested failure" /tmp/test_pascal_directive_error.log
	./$(COMPILER) test/test_pascal_conditional_include.pas /tmp/test_pascal_conditional_include26
	test "$$(/tmp/test_pascal_conditional_include26)" = "$$(printf '42\n7')"
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
	./$(COMPILER) test/test_pthread_header.pas /tmp/test_pthread_header26
	test "$$(/tmp/test_pthread_header26)" = "pthread loaded successfully"
	./$(COMPILER) test/test_c_gtk.pas /tmp/test_c_gtk26
	test "$$(/tmp/test_c_gtk26)" = "my_gtk header parsed and imported successfully"
	./$(COMPILER) test/test_type_runtime.pas /tmp/test_type_runtime26
	test "$$(/tmp/test_type_runtime26)" = "$$(printf '1\n1\n1\n0\n1\n18446744065119617025\n18446744073709551615\n9223372036854775807\n1\n-1\n-1\n-1\n18446744073709551615\n-1\n0\n2\n7\n123456\n9\n20')"
	./$(COMPILER) test/test_float.pas /tmp/test_float26
	test "$$(/tmp/test_float26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
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
	./$(COMPILER) test/test_static_array_ansistring_field.pas /tmp/test_static_array_ansistring_field26
	test "$$(/tmp/test_static_array_ansistring_field26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_ansistring_record_char_read.pas /tmp/test_ansistring_record_char_read26
	test "$$(/tmp/test_ansistring_record_char_read26)" = "$$(printf '1\n1\n1')"
	./$(COMPILER) test/test_nested_dynarray.pas /tmp/test_nested_dynarray26
	test "$$(/tmp/test_nested_dynarray26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) test/test_nested_dynarray_managed.pas /tmp/test_nested_dynarray_managed26
	test "$$(/tmp/test_nested_dynarray_managed26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
	./$(COMPILER) --threadsafe test/test_nested_dynarray_managed.pas /tmp/test_nested_dynarray_managed_threadsafe26
	test "$$(/tmp/test_nested_dynarray_managed_threadsafe26)" = "$$(printf '1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1\n1')"
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
	test "$$(/tmp/test_variant_ops26)" = "$$(printf '8\n2\n15\n7.5\n12.5\n1\n0\n0\n1\n1\n11\n1')"
	./$(COMPILER) test/test_variant_div.pas /tmp/test_variant_div26
	test "$$(/tmp/test_variant_div26)" = "$$(printf '3\n2\n3.4\n2.5')"
	./$(COMPILER) test/test_variant_string.pas /tmp/test_variant_string26
	test "$$(/tmp/test_variant_string26)" = "$$(printf 'hello\n42\nhello\nmanaged\nworld\nlocal\n7')"
	./$(COMPILER) test/test_variant_string_ops.pas /tmp/test_variant_string_ops26
	test "$$(/tmp/test_variant_string_ops26)" = "$$(printf '1\n0\n0\n1\n1\n1\n0\n0\n1\n1\n1\n1\n1\n0\n1\n1\n0\nhello world\nab\nsweet potato\ngreen tomato\n0\n1\n0\n0')"
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
	test "$$(/tmp/test_nilpy_bool26)" = "$$(printf '1\n1\n1\n0\n1\n1')"
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
	./$(COMPILER) --threadsafe test/test_multithreading.pas /tmp/test_multithreading26
	/tmp/test_multithreading26 | grep -q "multithreading test completed successfully"
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

# Validate the docs/progress board: stale BOARD.md, dangling Blocked-by slugs,
# dependency cycles, ownerless working/, commit-less done/. Fatal when run
# directly; only advisory inside 'make test' (above).
progress-check:
	@./tools/progress.sh check

# i386 cross-target slice (feature-target-i386). Grows with the backend;
# joins 'make test' when the op coverage is broad enough to matter.
test-i386: $(COMPILER)
	./$(COMPILER) --target=i386 test/hello.pas /tmp/test_i386_hello
	test "$$(tools/run_target.sh i386 /tmp/test_i386_hello)" = "Hello, World!"
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
	./$(COMPILER) --target=i386 test/test_cross_syscall.pas /tmp/test_i386_syscall
	./$(COMPILER) test/test_cross_syscall.pas /tmp/test_i386_syscall_x64
	test "$$(tools/run_target.sh i386 /tmp/test_i386_syscall)" = "$$(/tmp/test_i386_syscall_x64)"
	@echo "i386 hello + arith + procs + loops + write + varparam + syscall ok (output identical to x86-64)"

test-aarch64: $(COMPILER)
	./$(COMPILER) --target=aarch64 test/hello.pas /tmp/test_aarch64_hello
	test "$$(tools/run_target.sh aarch64 /tmp/test_aarch64_hello)" = "Hello, World!"
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
	@echo "aarch64 hello + arith + procs + loops + write + varparam + syscall ok (output identical to x86-64)"

test-arm32: $(COMPILER)
	./$(COMPILER) --target=arm32 test/hello.pas /tmp/test_arm32_hello
	test "$$(tools/run_target.sh arm32 /tmp/test_arm32_hello)" = "Hello, World!"
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
	@echo "arm32 hello + arith + procs + loops + write + varparam + syscall ok (output identical to x86-64)"

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

stabilize: test
	@echo "=== stabilize: 4-iteration fixedpoint check ==="
	/tmp/pascal26-fixedpoint $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-s4
	cmp /tmp/pascal26-next /tmp/pascal26-s4
	/tmp/pascal26-s4 $(PXXFLAGS) $(COMPILER_SRC) /tmp/pascal26-s5
	cmp /tmp/pascal26-next /tmp/pascal26-s5
	@echo "=== recording stable binary ==="
	@mkdir -p $(STABLE_DEFAULT_DIR)
	@NV=$$(( $$(cat $(STABLE_DEFAULT_DIR)/VERSION 2>/dev/null || echo 0) + 1 )); \
	 echo $$NV > $(STABLE_DEFAULT_DIR)/VERSION; \
	 cp /tmp/pascal26-s5 $(STABLE_DEFAULT_DIR)/v$$NV; \
	 ln -sfn v$$NV $(STABLE_DEFAULT_DIR)/latest; \
	 SHA=$$(sha256sum $(STABLE_DEFAULT_DIR)/latest | awk '{print $$1}'); \
	 echo "$$SHA  latest" > $(STABLE_DEFAULT_DIR)/last.sha256; \
	 printf '%s  v%s  %s  %s  %s\n' \
	   "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$NV" "$$SHA" \
	   "$$(git log -1 --format='%H')" \
	   "$$(git log -1 --format='%s')" \
	   >> $(STABLE_DEFAULT_DIR)/history.log; \
	 echo "STABLE v$$NV OK: $$SHA"

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

check-stable:
	@test -e $(STABLE_DEFAULT_DIR)/latest || \
	  (echo "No stable binary. Run: make stabilize"; exit 1)
	@(cd $(STABLE_DEFAULT_DIR) && sha256sum -c last.sha256) && \
	  echo "Stable v$$(cat $(STABLE_DEFAULT_DIR)/VERSION) OK: $$(cat $(STABLE_DEFAULT_DIR)/last.sha256)" || \
	  (echo "MISMATCH: stable binary does not match last.sha256"; exit 1)

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
