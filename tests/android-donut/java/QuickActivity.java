package org.longreachqt.donut.quick;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Rect;
import android.os.Bundle;
import android.view.MotionEvent;
import android.view.View;

public class QuickActivity extends Activity {
    private static final int WIDTH = 220;
    private static final int HEIGHT = 260;

    volatile boolean ready;
    volatile boolean checked;
    volatile int frameColor;
    volatile int frames;
    volatile int pauses;
    volatile int resumes;
    volatile boolean focused;
    private QuickView display;

    private native boolean openScene();
    private native int renderScene(int[] pixels);
    private native boolean pointer(int x, int y, boolean pressed);

    public void onCreate(Bundle state) {
        super.onCreate(state);
        System.loadLibrary("donut_probe");
        ready = openScene();
        display = new QuickView();
        setContentView(display);
    }

    protected void onPause() {
        super.onPause();
        pauses++;
    }

    protected void onResume() {
        super.onResume();
        resumes++;
        if (display != null)
            display.invalidate();
    }

    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        focused = hasFocus;
    }

    View display() {
        return display;
    }

    private final class QuickView extends View {
        private final int[] pixels = new int[WIDTH * HEIGHT];
        private final Bitmap frame = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888);
        private final Rect destination = new Rect();

        QuickView() {
            super(QuickActivity.this);
        }

        protected void onDraw(Canvas canvas) {
            if (!ready)
                return;
            int color = renderScene(pixels);
            frame.setPixels(pixels, 0, WIDTH, 0, 0, WIDTH, HEIGHT);
            destination.set(0, 0, getWidth(), getHeight());
            canvas.drawBitmap(frame, null, destination, null);
            frameColor = color;
            frames++;
        }

        public boolean onTouchEvent(MotionEvent event) {
            int action = event.getAction();
            if (ready && (action == MotionEvent.ACTION_DOWN || action == MotionEvent.ACTION_UP)) {
                int x = (int) (event.getX() * WIDTH / getWidth());
                int y = (int) (event.getY() * HEIGHT / getHeight());
                checked = pointer(x, y, action == MotionEvent.ACTION_DOWN);
                invalidate();
            }
            return ready;
        }
    }
}
