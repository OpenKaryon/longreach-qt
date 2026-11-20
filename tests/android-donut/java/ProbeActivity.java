package org.longreachqt.donut;

import android.app.Activity;
import android.os.Bundle;
import android.util.Log;
import android.widget.TextView;
import java.io.FileOutputStream;

public class ProbeActivity extends Activity {
    private native int runProbe(String filesDirectory);

    public void onCreate(Bundle state) {
        super.onCreate(state);
        TextView status = new TextView(this);
        try {
            NativeLoader.load(this);
            int result = runProbe(getFilesDir().getAbsolutePath());
            FileOutputStream completion = new FileOutputStream(new java.io.File(getFilesDir(), "probe-result.txt"));
            try {
                completion.write(Integer.toString(result).getBytes("US-ASCII"));
            } finally {
                completion.close();
            }
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
