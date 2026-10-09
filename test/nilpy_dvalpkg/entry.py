from .vec import norm, unit
def f(m: list) -> tuple:
    cols = [tuple(m[i][j] + (1.0 if i == j else 0.0) for i in range(3)) for j in range(3)]
    axis = max(cols, key=norm)
    return unit(axis)
