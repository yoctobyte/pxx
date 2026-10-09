# A def passed as a VALUE from a module lexed AFTER the def's own module.
# `other` reaches vec first, so entry.py (which passes vec.norm as a key) lies
# past vec in the token stream. The value-use scan stopped at the end of the
# module being parsed, so norm kept its typed ABI and the key bridge called it
# as a function object: IndexError or SIGSEGV (TSP entry.py `max(cols,
# key=norm)`).
from . import other, entry
print(other.speed((3.0, 4.0, 0.0)))
m = [[-1.0, 0.0, 0.0], [0.0, -1.0, 0.0], [0.0, 0.0, 1.0]]
print(entry.f(m))
