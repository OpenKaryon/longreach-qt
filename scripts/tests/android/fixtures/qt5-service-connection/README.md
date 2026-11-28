<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Qt5 ServiceConnection ownership inputs

Original Qt5.15.19 sources retain their upstream notices. The host test removes
the leading SPDX line, verifies their hashes, applies the production patch and
executes actual C++/Java methods with recorded JNI/Android boundaries. This is
an ownership protocol regression, not an Android ABI or concurrent-destruction
qualification. A real SDK/guest retained-handle control is required separately.

The supported lifetime contract requires callers to prevent new service callbacks
and wait for in-flight callbacks before C++ destruction starts, including the
derived destructor. Base-destructor handle cleanup alone cannot make concurrent
callback/destruction safe. A separate asynchronous-close implementation is outside
this contract; these fixtures do not establish concurrent-destruction safety.
