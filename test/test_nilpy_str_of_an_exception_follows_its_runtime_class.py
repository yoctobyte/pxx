# str(e) follows the RUNTIME class's __str__, whatever the except clause names.
# bug-n-str-of-a-pascal-declared-exception-ignores-str-when-caught-as-a-base
import struct
from urllib.error import URLError, HTTPError

class MyErr(ValueError):
    def __str__(self):
        return "mine"

class Plain(ValueError):
    pass

def show(e):
    return str(e) + " | " + f"{e}"

for mk in (lambda: ValueError("v"), lambda: KeyError("k"), lambda: MyErr("x"),
           lambda: Plain("p"), lambda: URLError("boom")):
    try:
        raise mk()
    except Exception as e:
        print(type(e).__name__, show(e))
try:
    raise MyErr("x")
except ValueError as e:
    print(str(e))
try:
    struct.unpack(">I", b"ab")
except struct.error as e:
    print("struct", str(e)[:20])
try:
    raise URLError("boom")
except OSError as e:
    print(e)
print(str(ValueError("plain")), str(Plain("q")))
