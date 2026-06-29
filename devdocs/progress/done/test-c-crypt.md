# Implement a C interop regression test for passphrase hashing (`crypt.h`)

- **Type:** test
- **Status:** done
- **Closed 2026-06-29 (board cleanup):** `test/test_c_crypt.pas` wired in
  `Makefile:1214` with pass-assertion (commit `0d695bfc`). Left stuck at
  in-progress.
- **Track:** C (C frontend interop testing)
- **Owner:** Antigravity
- **Opened:** 2026-06-28

## Motivation

To verify the robustness and correctness of PXX's auto-import capability against standard system libraries, we need a regression test for the passphrase hashing library (`crypt.h` in `libcrypt`).

This test will exercise:
1. Complex struct mapping (`struct crypt_data`).
2. Macro constant mapping (`CRYPT_OUTPUT_SIZE`, `CRYPT_MAX_PASSPHRASE_SIZE`).
3. Calling thread-safe and non-thread-safe SysV C functions (`crypt`, `crypt_r`).
4. Reinterpreting and passing pointers to strings and structures.

## Scope

1. **Test implementation**:
   - Create `test/test_c_crypt.pas`.
   - Use `uses crypt;` to auto-import the header.
   - Define test cases for standard SHA-512 crypt hashing (`$6$salt$`).
   - Verify that thread-safe hashing (`crypt_r`) correctly writes output into the `crypt_data` record structure.
2. **Integration**:
   - Wire the test into `test/` regression suite or execute it directly to verify.

## Acceptance

- `test/test_c_crypt.pas` compiles successfully.
- Running the compiled binary performs passphrase hashing, asserts correct outcomes, and exits with status 0.

## Log
- 2026-06-28 — ticket opened and taken.
