# Regression test for bug-n-a-tuple-returning-str-method-prints-raw-memory-when-returned-from-a-def
# (closed 2026-11-10: it passes at latest; expected = python3).
def p(x: str):
    return x.partition(" ")
print(p("C minor"))                # raw memory
print("C minor".partition(" "))    # ('C', ' ', 'minor')   <- correct
