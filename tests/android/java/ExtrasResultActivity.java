// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
package org.longreachqt.examples;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;

public final class ExtrasResultActivity extends Activity {
    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);
        byte[] payload = getIntent().getByteArrayExtra("longreach.payload");
        if (payload == null) {
            setResult(RESULT_CANCELED);
        } else {
            Intent result = new Intent();
            result.putExtra("longreach.reply", payload);
            setResult(RESULT_OK, result);
        }
        // Exercise a real result Activity lifecycle before returning. Closing
        // directly in onCreate can leave the API10 caller waiting for visibility.
        final android.widget.TextView content = new android.widget.TextView(this);
        content.setText("AndroidExtras activity result");
        setContentView(content);
        content.getViewTreeObserver().addOnPreDrawListener(new android.view.ViewTreeObserver.OnPreDrawListener() {
            @Override public boolean onPreDraw() {
                content.getViewTreeObserver().removeOnPreDrawListener(this);
                content.post(new Runnable() {
                    @Override public void run() {
                        android.util.Log.i("LongreachLifecycle", "result Activity first frame completed");
                        finish();
                    }
                });
                return true;
            }
        });
    }
}
