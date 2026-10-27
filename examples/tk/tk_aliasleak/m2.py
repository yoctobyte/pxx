import configparser


def g():
    c = configparser.ConfigParser()
    c.add_section("s")
    return c.has_section("s")
