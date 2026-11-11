# queue.Queue(maxsize=2): a keyword binds against a constructor overload set
# whose first arm takes no parameters.
# bug-n-a-keyword-argument-does-not-bind-when-a-constructor-overload-set-contains-a-zero-parameter-arm
import queue
b = queue.Queue(maxsize=2)
b.put(1)
print(b.qsize(), b.maxsize, b.full())
b.put(2)
print(b.full(), b.get(), b.qsize())
c = queue.Queue()
print(c.maxsize, c.empty())
d = queue.Queue(3)
print(d.maxsize)
