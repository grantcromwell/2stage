#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
arm_compiler=${ARM_GCC:-arm-none-eabi-gcc}
"$arm_compiler" -mcpu=cortex-a9 -marm -mfloat-abi=soft -O2 -ffreestanding -fno-builtin -fno-stack-protector -Wall -Wextra -Werror -nostdlib -nostartfiles -Wl,-T,ocm.ld,-Map,firmware.map startup.S firmware.c -lgcc -o firmware.elf
