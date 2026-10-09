import math
def norm(a: tuple) -> float:
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
def unit(a: tuple) -> tuple:
    n = norm(a)
    return (a[0] / n, a[1] / n, a[2] / n)
