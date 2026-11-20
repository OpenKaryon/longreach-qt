// SPDX-License-Identifier: GPL-3.0-or-later
package org.longreachqt.donut;

import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;

/** Shared loader for the static API4 and shared-runtime API21 packages. */
public final class NativeLoader {
    private NativeLoader() {}

    public static void load(Context context) {
        try {
            ApplicationInfo app = context.getPackageManager().getApplicationInfo(
                    context.getPackageName(), PackageManager.GET_META_DATA);
            if (app.metaData != null && app.metaData.getBoolean("org.longreachqt.sharedRuntime", false))
                System.loadLibrary("c++_shared");
        } catch (PackageManager.NameNotFoundException failure) {
            throw new IllegalStateException("Cannot read own native runtime metadata", failure);
        }
        System.loadLibrary("donut_probe");
    }
}
