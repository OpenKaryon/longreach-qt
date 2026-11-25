<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Qt5 Android speech regression inputs

The three upstream Qt source files are unmodified Qt 5.15.19 inputs, apart
from a leading SPDX annotation removed by the test before hashing/applying
patches. Original Qt copyright and license notices remain in each file.
Their SHA256 identities are locked in `qt5-android-tts.py`; the source archive
is the same pinned input as the Android SDK build.

The test applies the actual Android TTS patch stack. Java executes with narrow
recording Android substitutes. Native cases compile the changed dispatch,
state and lifecycle methods against real QtCore, replacing JNI/Android calls
and the speech base interface. This checks queued delivery, reentrancy and
object lifetime, not Android ABI linkage, a real TTS engine or audible speech.
