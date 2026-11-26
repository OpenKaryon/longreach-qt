<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Qt5 Activity shutdown regression inputs

The two original Qt5.15.19 Java files retain their upstream license notices.
The test removes the leading SPDX annotation and verifies the pinned hashes.
Actual patched dispatch/cleanup methods execute with recorded Android/native
boundaries. This is a host ordering check, not Android guest qualification.
