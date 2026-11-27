<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Qt6 Android speech callback contracts

The three upstream sources are from the pinned Qt 6.8.5 archive. Their bytes
after the fixture SPDX line are verified before applying the actual repository
patches 08 and 12 through 15. Upstream copyright and license notices are retained.

The Java fixture executes the patched adapter using recording Android API
substitutes. `javap` checks all seven native descriptors against the patched
C++ declarations. With `--qmake qmake6`, the native fixture compiles the actual
registry, callback dispatch, constructor/destructor, generation and speech state
method bodies against real Qt6 Core. JNI, the speech base and audio format are
explicit substitutes. Canceled callbacks already queued before stop, pause or
replacement are exercised on the Qt owner thread, including worker callbacks
and queued receiver destruction. Oversized speech and synthesis must return
one Input error before any provider call, including the API21 case where a
provider invokes onError before returning ERROR. Exact-limit text still reaches
the provider.

This functional regression does not qualify an Android SDK/ABI, real speech
provider, audio output, synthesis PCM or physical device. Those require the
separate Android runs.
