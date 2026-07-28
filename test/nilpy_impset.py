# A user-defined `set`, the shape songformatter's settings.py has. It shadows
# the builtin ONLY in the modules that import it by name.
def set(section, option, value):
    return section + "." + option + "=" + value
