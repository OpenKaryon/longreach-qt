package org.longreachqt.donut.quick;

import android.app.Activity;
import android.os.Bundle;
import android.widget.TextView;

public class QuickCoverActivity extends Activity {
    public void onCreate(Bundle state) {
        super.onCreate(state);
        TextView cover = new TextView(this);
        cover.setText("Quick smoke lifecycle check");
        setContentView(cover);
    }
}
