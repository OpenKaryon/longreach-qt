<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Qt5 ServiceConnection ownership inputs

Original Qt5.15.19 sources retain their upstream notices. The host test removes
the leading SPDX line, verifies their hashes, applies the production patch and
executes actual C++/Java methods with recorded JNI/Android boundaries. This is
an ownership protocol regression, not an Android ABI or concurrent-destruction
qualification. A real SDK/guest retained-handle control is required separately.
