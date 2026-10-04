// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
static void *worker(void *arg) { return (void *)((long)arg + 1); }
int main(void) {
    pthread_t t; void *r = 0;
    if (pthread_create(&t, 0, worker, (void *)41) != 0) return 1;
    pthread_join(t, &r);
    long long a = 1234567890123LL, b = 97;
    printf("c-probe ok thread=%ld div=%lld mod=%lld\n", (long)r, a / b, a % b);
    return 0;
}
