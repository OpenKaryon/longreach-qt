/* SPDX-License-Identifier: LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only
 * Copyright (C) 2026 OpenKaryon
 *
 * Included in every compile of the i386 target (see clang-wrapper.sh). The
 * 11.3 SDK's AppKit headers name NSItemProvider and NSExtensionContext, which
 * Foundation declares for the 64-bit runtime only; nothing on i386 uses them,
 * but the headers do not compile without a declaration. */
#if defined(__OBJC__) && defined(__i386__)
#import <Foundation/Foundation.h>
@interface NSItemProvider : NSObject
@end
@interface NSExtensionContext : NSObject
@end
#endif
