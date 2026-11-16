package org.longreachqt.donut;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.widget.TextView;

public class ProbeActivity extends Activity {
    private native int runProbe(String filesDirectory);

    public void onCreate(Bundle state) {
        super.onCreate(state);
        TextView status = new TextView(this);
        try {
            System.loadLibrary("donut_probe");
            int result = runProbe(getFilesDir().getAbsolutePath());
            String message = "Native probe returned " + result;
            Log.i("LongreachDonut", message);
            status.setText(message);
        } catch (Throwable failure) {
            Log.e("LongreachDonut", "Native probe failed to load or run", failure);
            status.setText(failure.toString());
        }
        setContentView(status);
    }
}
