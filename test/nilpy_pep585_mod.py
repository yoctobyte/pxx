# Helper module for test_nilpy_a_pep585_alias_binds_its_origin_type:
# the aliases are defined here and imported BY NAME, as tsp/ephem/__init__.py
# imports Vec3 and State from tsp/ephem/spk.py.

Vec3 = tuple[float, float, float]
State = tuple[float, float, float, float, float, float]


def position(t: float) -> Vec3:
    return (t, 2.0 * t, 3.0 * t)


def state(t: float) -> State:
    x, y, z = position(t)
    return (x, y, z, 1.0, 2.0, 3.0)
