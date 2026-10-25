/* Diagnostic precision must not change CW, loads, or store checking. */
#include "cosim86.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void step(void) {
    if (cosim_step() != COSIM_OK) {
        fprintf(stderr, "step: %s\n", cosim_error());
        exit(1);
    }
}

int main(int argc, char **argv) {
    const int single = argc > 1 && !strcmp(argv[1], "single");
    const char *diag = getenv("COSIM_X87_PC53");
    const int capped = diag && atoi(diag);
    const uint16_t cw = single ? 0x007f : 0x037f;
    const uint64_t input = single ? UINT64_C(0x8000004000000000)
                                  : UINT64_C(0x8000000000000001);
    const uint64_t expected = single ? UINT64_C(0x8000010000000000)
                            : capped ? UINT64_C(0x8000000000000000)
                                     : UINT64_C(0x8000000000000002);
    static const uint8_t jump[] = {0xea, 0, 0, 0, 0x10};
    static const uint8_t code[] = {
        0xdb, 0xe3,                   /* FNINIT */
        0xd9, 0x2e, 0x0a, 0x01,       /* FLDCW [010a] */
        0xdb, 0x2e, 0x00, 0x01,       /* FLD m80 [0100] */
        0xd8, 0xc8,                   /* FMUL ST(0),ST(0) */
        0xd9, 0x3e, 0x10, 0x01,       /* FNSTCW [0110] */
        0xdb, 0x3e, 0x20, 0x01,       /* FSTP m80 [0120] */
        0xd9, 0xe8,                   /* FLD1 */
        0xdb, 0x1e, 0x30, 0x01        /* FISTP m32 [0130] */
    };
    cosim_init(16u << 20);
    uint8_t *ram = cosim_ram();
    memcpy(ram + 0xfffff0, jump, sizeof(jump));
    memcpy(ram + 0x10000, code, sizeof(code));
    memcpy(ram + 0x100, &input, 8);
    ram[0x108] = 0xff;
    ram[0x109] = 0x3f;
    memcpy(ram + 0x10a, &cw, 2);
    step();                           /* Far jump to test code. */
    step();
    step();
    step();
    uint32_t arch[COSIM_ARCH_WORDS];
    cosim_arch(arch);
    const int r7 = COSIM_ARCH_X87 + 3 + 3 * 7;
    if (arch[r7] != (uint32_t)input || arch[r7 + 1] != (uint32_t)(input >> 32)) {
        fprintf(stderr, "FLD lost extended input bits\n");
        return 1;
    }
    step();                           /* Arithmetic may round, but not alter CW. */
    cosim_arch(arch);
    if (arch[COSIM_ARCH_X87] != cw || arch[r7] != (uint32_t)expected ||
        arch[r7 + 1] != (uint32_t)(expected >> 32)) {
        fprintf(stderr, "arithmetic/CW mismatch: CW %04x, sig %08x%08x\n",
                arch[COSIM_ARCH_X87], arch[r7 + 1], arch[r7]);
        return 1;
    }
    step();
    for (unsigned i = 0; i < 2; i++)
        if (cosim_dut_write(0x110 + i, (cw >> (8 * i)) & 0xff) != COSIM_OK) return 1;
    step();
    for (unsigned i = 0; i < 10; i++) {
        const uint8_t b = i < 8 ? (expected >> (8 * i)) & 0xff : i == 8 ? 0xff : 0x3f;
        if (cosim_dut_write(0x120 + i, b) != COSIM_OK) {
            fprintf(stderr, "store: %s\n", cosim_error());
            return 1;
        }
    }
    if (cosim_writes_pending() || cosim_x87_adopted()) return 1;
    step();
    step();
    if (cosim_dut_write(0x130, 2) != COSIM_ERROR || cosim_x87_adopted()) {
        fprintf(stderr, "incorrect integer PCM sample was accepted\n");
        return 1;
    }
    puts("PASS: reference precision, raw load, architectural CW and strict stores");
    return 0;
}
