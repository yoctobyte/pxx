def cyadd(int a, int b):
    return a + b

def cyfact(int n):
    cdef int i, r = 1
    for i in range(1, n + 1):
        r *= i
    return r
