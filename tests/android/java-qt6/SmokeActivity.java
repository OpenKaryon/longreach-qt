// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

package org.longreachqt.examples;

import android.os.Bundle;
import android.system.ErrnoException;
import android.system.Os;
import java.io.File;
import org.qtproject.qt.android.bindings.QtActivity;

public class SmokeActivity extends QtActivity {
    @Override
    public void onCreate(Bundle state) {
        File files = getFilesDir();
        new File(files, "selftest-result.txt").delete();
        try {
            Os.setenv("LONGREACH_APP_FILES", files.getAbsolutePath(), true);
            Os.setenv("TMPDIR", files.getAbsolutePath(), true);
            String backend = getIntent().getStringExtra("qtQuickBackend");
            if (backend != null)
                Os.setenv("QT_QUICK_BACKEND", backend, true);
        } catch (ErrnoException error) {
            throw new IllegalStateException("Could not set private example paths", error);
        }
        super.onCreate(state);
    }
}
