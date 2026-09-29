# Imported by test_nilpy_semicolons_at_an_imported_modules_top_level.npy. Every
# top-level line below puts two or more simple statements on one line.
a = 1; b = 2
s = 0
s += 5; s -= 2; s *= 3
name = "x"; names = [name, "y"];
log = []
def note(v):
    log.append(v)
note(1); note(2); print("module ran", len(log))
if a < b: note(3); note(4)
for i in range(2): s += i; note(i)
total = a + b; total += s
