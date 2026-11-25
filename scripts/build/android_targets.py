# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 OpenKaryon
"""Android SDK names and existing artifact locations.

Kept separate from execution so make help and build-all --list need no SDK,
PowerShell, Docker or network. API4 ARM exposes its configured static/raster
installed SDK; its original combined recipe remains a separate legacy target.
"""
from typing import NamedTuple


class AndroidTarget(NamedTuple):
    qt: int
    abi: str
    api: int
    profile: str

    @property
    def image(self) -> str:
        return f'longreach-qt{self.qt}-android-{self.profile}:llvm21'

    @property
    def artifacts(self) -> str:
        if self.qt == 4 and self.api == 4:
            return 'artifacts/qt4-android-donut-sdk'
        return f'artifacts/qt{self.qt}-android-{self.profile}'


ANDROID_TARGETS = {
    'qt4-android-arm': AndroidTarget(4, 'armeabi', 4, 'donut-armeabi'),
    'qt4-android-i386': AndroidTarget(4, 'x86', 10, 'gingerbread-x86'),
    'qt4-android-amd64': AndroidTarget(4, 'x86_64', 21, 'lollipop-x86_64'),
    'qt4-android-arm64': AndroidTarget(4, 'arm64-v8a', 21, 'lollipop-arm64-v8a'),
    'qt5-android-armv7': AndroidTarget(5, 'armeabi-v7a', 10, 'gingerbread'),
    'qt5-android-i386': AndroidTarget(5, 'x86', 10, 'gingerbread-x86'),
    'qt5-android-amd64': AndroidTarget(5, 'x86_64', 21, 'lollipop-x86_64'),
    'qt5-android-arm64': AndroidTarget(5, 'arm64-v8a', 21, 'lollipop-arm64-v8a'),
    'qt6-android-armv7': AndroidTarget(6, 'armeabi-v7a', 21, 'lollipop'),
    'qt6-android-i386': AndroidTarget(6, 'x86', 21, 'lollipop-x86'),
    'qt6-android-amd64': AndroidTarget(6, 'x86_64', 21, 'lollipop-x86_64'),
    'qt6-android-arm64': AndroidTarget(6, 'arm64-v8a', 21, 'lollipop-arm64-v8a'),
}
LEGACY_TARGET = 'qt4-android-arm-legacy'
QT_VERSIONS = {4: '4.8.7', 5: '5.15.19', 6: '6.8.5'}


def artifact_dir(target: str) -> str:
    return ANDROID_TARGETS[target].artifacts


def startable_targets(pending, running):
    """Android owns shared host tools and runs alone, including SDK mode.

    Put Android first once desktop jobs drain, so new desktop work cannot
    indefinitely postpone an Android target already waiting in the queue.
    """
    if any(t in ANDROID_TARGETS for t in running):
        return []
    android = [t for t in pending if t in ANDROID_TARGETS]
    if android and not running:
        return android[:1]
    if android:
        return []
    return list(pending)
