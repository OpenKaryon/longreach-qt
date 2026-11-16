package org.longreachqt.donut.quick;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Intent;
import android.content.Context;
import android.os.Bundle;
import android.os.SystemClock;
import android.util.Log;
import android.view.MotionEvent;
import android.view.View;
import java.io.FileOutputStream;

public class QuickInstrumentation extends Instrumentation {
    private static final String TAG = "LongreachDonut";
    private static final int OFF = 0xff3a404b;
    private static final int ON = 0xff50b848;
    private final StringBuilder report = new StringBuilder();

    public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        start();
    }

    private Intent activity(Class<?> type) {
        return new Intent(getTargetContext(), type).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    }

    private void waitForFrame(QuickActivity app, int color, int after) {
        long deadline = SystemClock.uptimeMillis() + 8000;
        while (SystemClock.uptimeMillis() < deadline) {
            if (app.frames > after && app.frameColor == color)
                return;
            SystemClock.sleep(50);
        }
        throw new IllegalStateException("Expected frame color " + Integer.toHexString(color)
                                        + ", actual " + Integer.toHexString(app.frameColor));
    }

    private void tap(final QuickActivity app) {
        long deadline = SystemClock.uptimeMillis() + 8000;
        while (!app.focused && SystemClock.uptimeMillis() < deadline)
            SystemClock.sleep(50);
        if (!app.focused)
            throw new IllegalStateException("Quick activity did not receive window focus");
        final int[] point = new int[2];
        runOnMainSync(new Runnable() {
            public void run() {
                View view = app.display();
                view.getLocationOnScreen(point);
                point[0] += view.getWidth() / 2;
                point[1] += view.getHeight() / 2;
            }
        });
        long now = SystemClock.uptimeMillis();
        MotionEvent down = MotionEvent.obtain(now, now, MotionEvent.ACTION_DOWN, point[0], point[1], 0);
        MotionEvent up = MotionEvent.obtain(now, now + 40, MotionEvent.ACTION_UP, point[0], point[1], 0);
        try {
            sendPointerSync(down);
            sendPointerSync(up);
        } finally {
            down.recycle();
            up.recycle();
        }
    }

    private void passed(String check) {
        String line = "PASS: " + check;
        Log.i(TAG, line);
        report.append(line).append('\n');
    }

    private void saveReport() throws java.io.IOException {
        FileOutputStream file = getTargetContext().openFileOutput("quick-smoke.txt", Context.MODE_PRIVATE);
        try {
            file.write(report.toString().getBytes("UTF-8"));
        } finally {
            file.close();
        }
    }

    public void onStart() {
        Bundle result = new Bundle();
        try {
            QuickActivity app = (QuickActivity) startActivitySync(activity(QuickActivity.class));
            waitForFrame(app, OFF, 0);
            passed("qrc and first frame");
            int beforeTap = app.frames;
            tap(app);
            waitForFrame(app, ON, beforeTap);
            if (!app.checked)
                throw new IllegalStateException("Tap did not reach QML switch");
            passed("Android tap updates QML and frame");

            int before = app.resumes;
            int beforePause = app.pauses;
            final Activity cover = startActivitySync(activity(QuickCoverActivity.class));
            waitForIdleSync();
            if (app.pauses <= beforePause)
                throw new IllegalStateException("Android did not pause the Quick activity");
            int beforeResume = app.frames;
            runOnMainSync(new Runnable() {
                public void run() { cover.finish(); }
            });
            long deadline = SystemClock.uptimeMillis() + 8000;
            while (app.resumes == before && SystemClock.uptimeMillis() < deadline)
                SystemClock.sleep(50);
            if (app.resumes <= before || !app.checked)
                throw new IllegalStateException("Quick activity did not resume with its state");
            waitForFrame(app, ON, beforeResume);
            beforeTap = app.frames;
            tap(app);
            waitForFrame(app, OFF, beforeTap);
            passed("Android pause and resume preserve input and rendering");
            saveReport();
            Log.i(TAG, "Quick smoke passed");
            result.putString("result", "Quick smoke passed");
            finish(Activity.RESULT_OK, result);
        } catch (Throwable failure) {
            Log.e(TAG, "Quick smoke failed", failure);
            result.putString("result", failure.toString());
            finish(Activity.RESULT_CANCELED, result);
        }
    }
}
