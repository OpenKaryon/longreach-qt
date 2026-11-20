package org.longreachqt.donut.quick;

import android.app.Activity;
import org.longreachqt.donut.NativeLoader;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Rect;
import android.os.Bundle;
import android.view.MotionEvent;
import android.view.View;

public class QuickActivity extends Activity {
    static final int SCENE_SWITCH = 0;
    static final int SCENE_QML = 1;
    static final int SCENE_WIDGETS = 2;

    int frameWidth;
    int frameHeight;
    private boolean active;

    protected int sceneMode() {
        return SCENE_SWITCH;
    }

    volatile boolean ready;
    volatile boolean checked;
    volatile int frameColor;
    volatile int frames;
    volatile int visibleSection;
    volatile int pauses;
    volatile int resumes;
    volatile boolean focused;
    private QuickView display;

    private native boolean openScene(int mode, int width, int height);
    private native int renderScene(int[] pixels);
    private native boolean pointer(int x, int y, int action);

    public void onCreate(Bundle state) {
        super.onCreate(state);
        NativeLoader.load(this);
        frameWidth = sceneMode() != SCENE_SWITCH ? 480 : 220;
        frameHeight = sceneMode() != SCENE_SWITCH ? 320 : 260;
        ready = openScene(sceneMode(), frameWidth, frameHeight);
        display = new QuickView();
        setContentView(display);
    }

    protected void onPause() {
        super.onPause();
        active = false;
        pauses++;
    }

    protected void onResume() {
        super.onResume();
        active = true;
        resumes++;
        if (display != null) {
            ready = openScene(sceneMode(), frameWidth, frameHeight);
            display.invalidate();
        }
    }

    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        focused = hasFocus;
    }

    native int[] controlCenter(int index);

    View display() {
        return display;
    }

    private final class QuickView extends View {
        private final int[] pixels = new int[frameWidth * frameHeight];
        private final Bitmap frame = Bitmap.createBitmap(frameWidth, frameHeight, Bitmap.Config.ARGB_8888);
        private final Rect destination = new Rect();

        QuickView() {
            super(QuickActivity.this);
        }

        protected void onDraw(Canvas canvas) {
            if (!ready)
                return;
            int result = renderScene(pixels);
            frame.setPixels(pixels, 0, frameWidth, 0, 0, frameWidth, frameHeight);
            destination.set(0, 0, getWidth(), getHeight());
            canvas.drawBitmap(frame, null, destination, null);
            if (sceneMode() != SCENE_SWITCH) {
                visibleSection = result;
                if (active)
                    postInvalidateDelayed(80);
            } else {
                frameColor = result;
            }
            frames++;
        }

        public boolean onTouchEvent(MotionEvent event) {
            int action = event.getAction();
            if (ready && (action == MotionEvent.ACTION_DOWN || action == MotionEvent.ACTION_UP
                    || action == MotionEvent.ACTION_MOVE || action == MotionEvent.ACTION_CANCEL)) {
                int x = (int) (event.getX() * frameWidth / getWidth());
                int y = (int) (event.getY() * frameHeight / getHeight());
                checked = pointer(x, y, action == MotionEvent.ACTION_CANCEL ? MotionEvent.ACTION_UP : action);
                invalidate();
            }
            return ready;
        }
    }
}
