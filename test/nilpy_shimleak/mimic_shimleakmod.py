# test/test_nilpy_a_shim_whose_guarded_import_misses_keeps_its_units.npy
# imports this as `shimleakmod`, through the mimic_ fallback. It pulls in a
# Pascal unit (socket -> mimic_socket, which uses sysutils) and then soft-misses
# a guarded import: the shape that made the importer roll back every unit the
# shim had compiled.
import socket

try:
    import definitely_no_such_module_7c1e
    HAVE = True
except ImportError:
    HAVE = False


def f():
    return "shim ok " + str(HAVE) + " " + str(socket.AF_INET)
