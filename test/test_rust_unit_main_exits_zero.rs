// A unit `fn main()` must exit 0. It is registered with a Result slot nothing
// writes, and the driver exited with main's return register, so the status was
// whatever that register held: 0 on x86-64, aarch64, arm32 and riscv32, 81 on
// i386 (v449, with or without the helper call below). test_rust_option.rs and
// test_rust_result.rs printed the right output there and still failed. The
// helper call puts a live i32 result in the register before main returns.
fn helper() -> i32 {
    77
}

fn main() {
    let x = helper();
    let _y = x + 4;
}
