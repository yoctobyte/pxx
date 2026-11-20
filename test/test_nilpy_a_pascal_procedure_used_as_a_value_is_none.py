# A Pascal PROCEDURE called where Python wants a value answers None, as a
# CPython function that returns nothing does. It used to read the result
# register: the argument (3), a pointer, and `v is None` False. Called as a
# statement it still runs, once.
# bug-n-a-procedure-shim-in-value-position-yields-a-number-not-none
import pvprobe

print(pvprobe.poke(3))
v = pvprobe.poke(4)
print(v is None, v)
pvprobe.poke(5)
print(pvprobe.pokes())
k = pvprobe.K()
print(k.touch())
k.touch()
print([k.touch(), k.touch()])
print(k.hits)
print("x" if pvprobe.poke(1) is None else "y", pvprobe.pokes())
