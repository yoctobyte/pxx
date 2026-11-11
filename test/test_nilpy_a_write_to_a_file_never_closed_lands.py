# `open(p, "w").write("DATA")` created the file and left it EMPTY: nothing
# drained the buffer when the handle was dropped without close(). CPython
# flushes on deallocation, which makes the one-liner a normal idiom.
# bug-n-a-write-to-a-file-that-is-never-closed-is-silently-lost
p = "/tmp/test_nilpy_unclosed_f.txt"
open(p, "w").write("DATA")
with open(p) as f:
    print(repr(f.read()))

def w(path):
    h = open(path, "w")
    h.write("IN_DEF")

q = "/tmp/test_nilpy_unclosed_g.txt"
w(q)
with open(q) as f:
    print(repr(f.read()))
