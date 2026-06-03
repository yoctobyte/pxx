# ESP32 And ESP-IDF Direction

ESP32 is an important long-term target because Espressif already provides a
large, practical C SDK. ESP-IDF covers GPIO, Wi-Fi, Bluetooth, I2C, SPI, flash,
timers, tasks, queues, and board support across a wide spread of ESP32 devices.
Most application-level development is intentionally similar across chips even
though the CPUs vary.

The goal for PXX is not to replace that SDK. The goal is to compile small native
programs that can use it directly, without paying the slow edit/compile/test
cost of the usual C++/Arduino-style build stack and without moving the program
into a VM such as MicroPython.

## Why Wrapper-Free C Matters Here

The SQLite/Nil Python proof is a model for ESP-IDF:

- import a real C header directly;
- extract usable constants, function signatures, typed pointers, and handles;
- call C APIs from a frontend that is not C;
- keep handwritten wrappers optional instead of mandatory;
- generate a native binary, not interpreter bytecode.

For ESP32, that means a Pascal or Nil Python program should eventually be able
to call ESP-IDF APIs directly:

```pascal
uses esp_gpio;

begin
  gpio_set_direction(2, GPIO_MODE_OUTPUT);
  gpio_set_level(2, 1);
end.
```

or, from a Python-shaped frontend:

```python
import esp_gpio

gpio_set_direction(2, GPIO_MODE_OUTPUT)
gpio_set_level(2, 1)
```

The important part is that `esp_gpio` should come from the vendor header model,
not from a hand-maintained wrapper layer that must chase the SDK forever.

## Target Profiles

FreeRTOS compatibility is useful, but it should be a target profile rather than
the core runtime identity.

- **Bare-metal profile:** PXX owns startup, memory policy, interrupts, and the
  default hardware hooks. The program model is "this is our binary, this is our
  microcontroller, run."
- **ESP-IDF / FreeRTOS profile:** PXX emits code that fits inside the ESP-IDF
  application model, uses Espressif startup/link/flash support, and calls
  FreeRTOS/ESP-IDF APIs directly.
- **Hosted POSIX profile:** the current Linux path.

This keeps the language and compiler semantics separate from the platform
services. FreeRTOS tasks, queues, timers, and synchronization can be imported C
APIs first, with optional Pascal/Nil Python facades later.

## CPU Families

ESP32 is not one CPU target:

- original ESP32: Xtensa LX6;
- ESP32-S2/S3: Xtensa LX7;
- ESP32-C3/C6/H2 and related parts: 32-bit RISC-V;
- newer parts continue to mix device capability and CPU family.

Espressif made most of the SDK portable above that layer. PXX should exploit
that split: implement CPU backends underneath, while riding the stable ESP-IDF
API surface above.

RISC-V ESP32 parts are the likely first embedded entry point because the ISA and
tooling are cleaner. Xtensa can follow once the target abstraction is proven.

## Likely Staging

1. **ESP-IDF header import proof on the host.** Parse selected ESP-IDF headers
   and prove constants/signatures can be extracted without emitting ESP32 code.
2. **RISC-V backend.** Target RV32 ESP32-class parts first.
3. **ESP-IDF integration path.** Emit an object or ELF that ESP-IDF can link and
   flash. This proves hardware behavior while reusing Espressif's image and boot
   machinery.
4. **Fast direct path.** Once ABI, startup, memory, and image layout are stable,
   bypass more of the slow build stack.
5. **Optional facades.** Add small friendly units only where they improve the
   user experience. The C import remains the ground truth.

## Runtime Stance

ESP32 devices can have enough RAM to run heavier systems, but the point of PXX
is to keep the default program native and direct. MicroPython improves iteration
speed at the cost of memory, speed, and runtime overhead. FreeRTOS gives a
useful platform model, but it is still a platform service, not the language
runtime.

The preferred direction is:

- native code by default;
- explicit ownership rules;
- syscall-free allocator hooks for bare metal;
- optional RTOS allocation/task hooks for ESP-IDF profiles;
- fast rebuilds through cached or preprocessed SDK metadata where possible.

The design law from C interop still applies: C imports should be usable directly
from every frontend; handwritten wrappers are optional sugar, never required
infrastructure.
