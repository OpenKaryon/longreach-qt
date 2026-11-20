// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

package org.longreachqt.examples;

import android.os.Bundle;
import java.io.File;
import org.qtproject.qt5.android.bindings.QtActivity;

public class SmokeActivity extends QtActivity {
    private static void checkActivityBindings() {
        if (android.os.Build.VERSION.SDK_INT >= 11) {
            try {
                Class<?> actionMode = Class.forName("android.view.ActionMode");
                Class<?> callback = Class.forName("android.view.ActionMode$Callback");
                Class<?> fragment = Class.forName("android.app.Fragment");
                for (String name : new String[] {"onActionModeStarted", "onActionModeFinished",
                        "super_onActionModeStarted", "super_onActionModeFinished"})
                    QtActivity.class.getDeclaredMethod(name, actionMode);
                QtActivity.class.getDeclaredMethod("onAttachFragment", fragment);
                QtActivity.class.getDeclaredMethod("super_onAttachFragment", fragment);
                QtActivity.class.getDeclaredMethod("onWindowStartingActionMode", callback);
                QtActivity.class.getDeclaredMethod("super_onWindowStartingActionMode", callback);
            } catch (Exception error) {
                throw new IllegalStateException("QtActivity API11 callbacks are missing", error);
            }
            android.util.Log.i("LongreachJava", "QtActivity API11 callback signatures PASS");
        } else {
            try {
                Class<?> bridge = Class.forName("org.qtproject.qt5.android.QtActivityLegacy");
                if (!bridge.isAssignableFrom(QtActivity.class) || bridge.getDeclaredMethods().length != 10)
                    throw new IllegalStateException("Incomplete legacy callback interface");
            } catch (Exception error) {
                throw new IllegalStateException("QtActivity API10 callback bridge is missing", error);
            }
            android.util.Log.i("LongreachJava", "QtActivity API10 legacy callback interface PASS");
        }
    }

    @Override
    public void onCreate(Bundle state) {
        checkActivityBindings();
        File files = getFilesDir();
        new File(files, "selftest-result.txt").delete();
        ENVIRONMENT_VARIABLES += "\tLONGREACH_APP_FILES=" + files.getAbsolutePath()
                + "\tTMPDIR=" + files.getAbsolutePath();
        if (getIntent().getBooleanExtra("debugQtPlugins", false))
            ENVIRONMENT_VARIABLES += "\tQT_DEBUG_PLUGINS=1"
                    + "\tQT_LOGGING_RULES=qt.core.library.debug=true;qt.core.plugin.loader.debug=true;qt.qml.import.debug=true";
        String backend = getIntent().getStringExtra("qtQuickBackend");
        if (backend != null)
            ENVIRONMENT_VARIABLES += "\tQT_QUICK_BACKEND=" + backend;
        String depth = getIntent().getStringExtra("qtRasterImageDepth");
        if ("16".equals(depth) || "32".equals(depth))
            ENVIRONMENT_VARIABLES += "\tQT_ANDROID_RASTER_IMAGE_DEPTH=" + depth;
        super.onCreate(state);
    }
}