// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
package org.qtproject.qt5.android.bindings;

import android.os.Process;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;

// This fixture shares the bindings package only to configure the existing
// QtServiceLoader before its standard onCreate path loads the native client.
public final class LongreachExtrasService extends QtService {
    private File reportDirectory;

    @Override
    protected void onCreateHook() {
        reportDirectory = new File(getFilesDir(), "extras-service-" + Process.myPid());
        if (reportDirectory.exists() || !reportDirectory.mkdirs())
            throw new IllegalStateException("Service report directory must be fresh");
        m_loader.ENVIRONMENT_VARIABLES += "\tLONGREACH_APP_FILES=" + reportDirectory.getAbsolutePath()
                + "\tTMPDIR=" + reportDirectory.getAbsolutePath();
        m_loader.APPLICATION_PARAMETERS = "--android-extras-service";
        super.onCreateHook();
    }

    @Override
    public void onDestroy() {
        try {
            FileOutputStream output = new FileOutputStream(new File(reportDirectory, "on-destroy.txt"));
            try {
                output.write((Integer.toString(Process.myPid()) + "\n").getBytes("UTF-8"));
                output.flush();
            } finally {
                output.close();
            }
        } catch (IOException error) {
            throw new IllegalStateException("Could not save Service onDestroy receipt", error);
        }
        // The real delegate quits the native event loop, joins the Qt thread
        // and exits this separate service process. No test-side Process.kill.
        super.onDestroy();
    }
}
