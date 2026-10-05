#include "types.h"

// Software division routines for RV32I (without M-extension)

uint32_t __udivsi3(uint32_t num, uint32_t den) {
    uint32_t quot = 0, qbit = 1;
    if (den == 0) return 0;
    while ((int32_t)den >= 0 && den < num) {
        den <<= 1;
        qbit <<= 1;
    }
    while (qbit) {
        if (num >= den) {
            num -= den;
            quot |= qbit;
        }
        den >>= 1;
        qbit >>= 1;
    }
    return quot;
}

uint32_t __umodsi3(uint32_t num, uint32_t den) {
    if (den == 0) return 0;
    uint32_t qbit = 1;
    while ((int32_t)den >= 0 && den < num) {
        den <<= 1;
        qbit <<= 1;
    }
    while (qbit) {
        if (num >= den) {
            num -= den;
        }
        den >>= 1;
        qbit >>= 1;
    }
    return num;
}

int32_t __divsi3(int32_t num, int32_t den) {
    int sign = 1;
    if (num < 0) { num = -num; sign = -sign; }
    if (den < 0) { den = -den; sign = -sign; }
    return sign > 0 ? __udivsi3(num, den) : -__udivsi3(num, den);
}

int32_t __modsi3(int32_t num, int32_t den) {
    int sign = (num < 0) ? -1 : 1;
    if (num < 0) num = -num;
    if (den < 0) den = -den;
    return sign > 0 ? __umodsi3(num, den) : -__umodsi3(num, den);
}
