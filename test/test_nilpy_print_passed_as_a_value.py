# Regression test for bug-n-a-builtin-function-is-not-a-first-class-value
# (closed 2026-11-10: it passes at latest; expected = python3).
def call_it(f, text):
    f(text)

def own(text):
    print("own:", text)

call_it(own, "a user function as a value works")   # fine
call_it(print, "print as a value")                 # pascal26:8: error: undefined variable (print)
