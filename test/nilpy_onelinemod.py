# Imported by test_nilpy_one_line_def_in_module.npy.
#
# The FIRST logical line is a one-line `def` on purpose — that is the whole bug.
# The lexer normalises `def f(): ...` into the canonical NEWLINE INDENT ... DEDENT,
# but it only recognised the header when the preceding token was a line break,
# asking `TokCount = 0` of the WHOLE token stream. A `.py` module is lexed by
# PyLexAppend on top of the importing program's tokens, so at the module's first
# token TokCount is not 0 and the previous token is the main file's tkEOF —
# the rule never fired and the module died on "unexpected token".
#
# Everything below the first line was already working and is here as the control:
# the same construct one line later took the normal path.
def get(): return "first-line-def"

CONST = 11

class K: pass

def later(): return "later-def"

def mk(): return K()

class Holder:
    def __init__(self, v): self.v = v
    def doubled(self): return self.v * 2

def indented():
    return "indented-still-fine"
