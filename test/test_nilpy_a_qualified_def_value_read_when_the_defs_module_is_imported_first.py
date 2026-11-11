# The DEFS module is imported BEFORE the module that reads its defs as values
# (the order the across_modules test deliberately does not use). A container
# result and annotated list/str/int parameters through the value.
# bug-n-a-qualified-def-value-read-is-invisible-when-the-def-s-module-is-parsed-first
import qdf_defs
import qdf_reader
print(qdf_reader.three().fittings())
print(qdf_reader.tot())
qdf_reader.run()
