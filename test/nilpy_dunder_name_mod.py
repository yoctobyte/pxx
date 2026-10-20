# Imported by test_nilpy_dunder_name_and_stdout_none: its own main guard must
# not run on import.
print("module name:", __name__)
if __name__ == "__main__":
    print("MODULE MAIN BLOCK RAN")
