// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon

package org.longreachqt.examples;

import android.os.Bundle;
import java.io.File;
import org.qtproject.qt5.android.bindings.QtActivity;

public class SmokeActivity extends QtActivity {
    private boolean extrasDiagnostics;

    // Read-only observations for the explicit Extras diagnostic. Normal smoke
    // does not schedule a watcher or change Activity/Qt state.
    private void observeExtrasState(String phase) {
        if (!extrasDiagnostics) return;
        android.util.Log.i("LongreachLifecycle", "phase=" + phase
            + " finishing=" + isFinishing() + " focus=" + hasWindowFocus()
            + " task=" + getTaskId() + " instance=" + System.identityHashCode(this));
        // Old Dalvik enumerates every declared field and tries to resolve the
        // unused API11 ClipboardManager type. Keep API10 observation public.
        if (android.os.Build.VERSION.SDK_INT < 11) return;
        try {
            Class<?> nativeClass = Class.forName("org.qtproject.qt5.android.QtNative");
            java.lang.reflect.Field mutex = nativeClass.getDeclaredField("m_mainActivityMutex");
            mutex.setAccessible(true);
            synchronized (mutex.get(null)) {
                java.lang.reflect.Field paused = nativeClass.getDeclaredField("m_activityPaused");
                java.lang.reflect.Field actions = nativeClass.getDeclaredField("m_lostActions");
                java.lang.reflect.Field activity = nativeClass.getDeclaredField("m_activity");
                paused.setAccessible(true); actions.setAccessible(true); activity.setAccessible(true);
                android.app.Activity current = (android.app.Activity) activity.get(null);
                android.util.Log.i("LongreachLifecycle", "phase=" + phase
                    + " paused=" + paused.getBoolean(null)
                    + " queued=" + ((java.util.Collection<?>) actions.get(null)).size()
                    + " activity=" + (current == null ? "null" : current.getClass().getName())
                    + " finishing=" + (current != null && current.isFinishing()));
            }
        } catch (Exception error) {
            android.util.Log.w("LongreachLifecycle", "Could not observe Qt Activity state", error);
        }
    }

    private void watchExtrasCompletion(final File files) {
        final android.os.Handler handler = new android.os.Handler(android.os.Looper.getMainLooper());
        handler.postDelayed(new Runnable() {
            private int polls, samples;
            @Override public void run() {
                File result = new File(files, "selftest-result.txt");
                if (result.isFile() && result.length() > 0) {
                    observeExtrasState("post-main-" + (++samples));
                    if (samples == 3) return;
                }
                if (++polls < 180) handler.postDelayed(this, 500);
            }
        }, 500);
    }

    @Override public void onPause() { super.onPause(); observeExtrasState("onPause"); }
    @Override public void onResume() { super.onResume(); observeExtrasState("onResume"); }
    @Override public void onStop() { super.onStop(); observeExtrasState("onStop"); }
    @Override public void onDestroy() { observeExtrasState("onDestroy-entry"); super.onDestroy(); observeExtrasState("onDestroy-return"); }

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
        extrasDiagnostics = "--android-extras".equals(getIntent().getStringExtra("applicationArguments"));
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
        if (extrasDiagnostics) watchExtrasCompletion(files);
    }
}