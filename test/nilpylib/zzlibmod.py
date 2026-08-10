# A NilPy module living in a LIBRARY ROOT rather than beside the importer.
# Reached via -Fu; the shipped lib/rtl and lib/pcl roots take the same path.
# feature-nilpy-import-a-py-module-from-the-library-path
def greet(who):
    return "lib:" + who

VALUE = 41
