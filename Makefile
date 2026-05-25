FPC     ?= fpc
FPCFLAGS = -O2 -Tlinux -Px86_64

COMPILER     := compiler/pascal26
COMPILER_SRC := compiler/compiler.pas
COMPILER_INC := $(wildcard compiler/*.inc)

.PHONY: all test clean bootstrap-check

all: bootstrap-check $(COMPILER)

bootstrap-check:
	@which $(FPC) > /dev/null 2>&1 || \
	  (echo "fpc not found. Install: sudo apt install fpc"; exit 1)

$(COMPILER): $(COMPILER_SRC) $(COMPILER_INC)
	$(FPC) $(FPCFLAGS) -o$(COMPILER) $(COMPILER_SRC)

test: $(COMPILER)
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
	./$(COMPILER) $(COMPILER_SRC) /tmp/pascal26-self
	/tmp/pascal26-self test/hello.pas /tmp/self-hello26
	test "$$(/tmp/self-hello26)" = "Hello, World!"

clean:
	rm -f $(COMPILER) compiler/*.o compiler/*.ppu
