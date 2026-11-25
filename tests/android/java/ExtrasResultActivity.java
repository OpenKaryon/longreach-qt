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
        finish();
    }
}
