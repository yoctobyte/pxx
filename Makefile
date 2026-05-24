FPC     ?= fpc
FPCFLAGS = -O2 -Tlinux -Px86_64

COMPILER     := compiler/pascal26
COMPILER_SRC := compiler/compiler.pas

.PHONY: all test clean bootstrap-check

all: bootstrap-check $(COMPILER)

bootstrap-check:
	@which $(FPC) > /dev/null 2>&1 || \
	  (echo "fpc not found. Install: sudo apt install fpc"; exit 1)

$(COMPILER): $(COMPILER_SRC)
	$(FPC) $(FPCFLAGS) -o$(COMPILER) $(COMPILER_SRC)

test: $(COMPILER)
	./$(COMPILER) test/hello.pas /tmp/hello26
	/tmp/hello26
	./$(COMPILER) test/bootstrap_features.pas /tmp/bootstrap_features26
	/tmp/bootstrap_features26
	./$(COMPILER) test/paramcount_if.pas /tmp/paramcount_if26
	/tmp/paramcount_if26

clean:
	rm -f $(COMPILER) compiler/*.o compiler/*.ppu
