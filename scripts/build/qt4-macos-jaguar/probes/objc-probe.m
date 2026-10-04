// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

#import <Foundation/Foundation.h>
int main(void) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *s = [NSString stringWithFormat:@"objc-probe %@ %d", @"ok", 10];
    NS_DURING
        [NSException raise:@"ProbeException" format:@"expected"];
    NS_HANDLER
        printf("caught %s\n", [[localException name] cString]);
    NS_ENDHANDLER
    printf("%s\n", [s cString]);
    [pool release];
    return 0;
}
