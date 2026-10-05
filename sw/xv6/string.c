#include "types.h"

void* memset(void *dst, int c, uint n) {
    char *cdst = (char *) dst;
    uint8_t byte = (uint8_t)c;
    if (((uint32_t)dst & 3) == 0 && (n & 3) == 0) {
        uint32_t w = byte | (byte << 8) | (byte << 16) | (byte << 24);
        uint32_t *wdst = (uint32_t *)dst;
        uint wn = n >> 2;
        for (uint i = 0; i < wn; i++) {
            wdst[i] = w;
        }
        return dst;
    }
    for(int i = 0; i < n; i++){
        cdst[i] = c;
    }
    return dst;
}

int memcmp(const void *v1, const void *v2, uint n) {
    const uchar *s1 = (const uchar *) v1;
    const uchar *s2 = (const uchar *) v2;
    while (n-- > 0) {
        if (*s1 != *s2)
            return *s1 - *s2;
        s1++;
        s2++;
    }
    return 0;
}

void* memmove(void *dst, const void *src, uint n) {
    const char *s = src;
    char *d = dst;
    if (s < d && s + n > d){
        s += n;
        d += n;
        while (n-- > 0)
            *--d = *--s;
    } else {
        while (n-- > 0)
            *d++ = *s++;
    }
    return dst;
}

// Like strncpy but guaranteed to NUL-terminate.
char* safestrcpy(char *s, const char *t, int n) {
    char *os = s;
    if(n <= 0)
        return os;
    while(--n > 0 && (*s++ = *t++) != 0)
        ;
    *s = 0;
    return os;
}

int strlen(const char *s) {
    int n = 0;
    for(; s[n]; n++)
        ;
    return n;
}

int strncmp(const char *p, const char *q, uint n) {
    while(n > 0 && *p && *p == *q)
        n--, p++, q++;
    if(n == 0)
        return 0;
    return (uchar)*p - (uchar)*q;
}

char* strncpy(char *s, const char *t, int n) {
    char *os = s;
    while(n-- > 0 && (*s++ = *t++) != 0)
        ;
    while(n-- > 0)
        *s++ = 0;
    return os;
}
