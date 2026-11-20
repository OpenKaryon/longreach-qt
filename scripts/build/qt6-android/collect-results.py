# SPDX-License-Identifier: GPL-3.0-or-later
"""Compatibility entry point for the common Android API21 result collector."""
from pathlib import Path
import runpy

runpy.run_path(str(Path(__file__).resolve().parents[1] / 'android-api21/collect-results.py'), run_name='__main__')
