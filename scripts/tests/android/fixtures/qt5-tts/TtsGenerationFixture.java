// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
package org.qtproject.qt5.android.speech;
import android.speech.tts.*;
import android.content.*;
import android.os.*;
import java.util.*;

// Actual Java adapter, recording Android substitute; no native bridge or audio.
class TtsGenerationFixture extends QtTextToSpeech {
    static int readyCalls, errorCalls;
    final List<String> events = Collections.synchronizedList(new ArrayList<String>());
    TtsGenerationFixture() {
        super(new Context(), 42L);
        if (!TextToSpeech.last.started) TextToSpeech.last.finishInit(TextToSpeech.SUCCESS);
        events.clear();
    }
    @Override public void notifyReady(long id) { require(id == 42L, "init engine id"); readyCalls++; }
    @Override public void notifyError(long id) { require(id == 42L, "error engine id"); errorCalls++; }
    @Override public void notifyUtterance(long id, long token, boolean speaking) {
        require(id == 42L, "utterance engine id");
        events.add(token + ":" + speaking);
    }
    static void require(boolean value, String message) { if (!value) throw new AssertionError(message); }
    public static void main(String[] args) {
        for (int api : new int[] {10, 14, 15, 21}) {
            Build.VERSION.SDK_INT = api;
            TtsGenerationFixture e = new TtsGenerationFixture();
            TextToSpeech t = TextToSpeech.last;
            require(t.earlyRegistrations == 0, "listener must wait for bound service");
            require((api < 15) == (t.completed != null), "listener API boundary");
            require(e.say("A", 7L) == TextToSpeech.SUCCESS, "successful dispatch");
            require(e.say("B", Long.MAX_VALUE) == TextToSpeech.SUCCESS, "max-token dispatch");
            require(t.ids.equals(Arrays.asList("QtSpeech:7", "QtSpeech:9223372036854775807")), "tag IDs");
            require(e.events.isEmpty(), "Speaking belongs to native legacy dispatch / modern onStart");
            if (api < 15) {
                t.complete(t.ids.get(0)); t.complete(t.ids.get(1));
                require(e.events.equals(Arrays.asList("7:false", Long.MAX_VALUE + ":false")), "legacy tokens");
            } else {
                t.progress.onStart(t.ids.get(1)); t.progress.onDone(t.ids.get(0));
                t.progress.onError(t.ids.get(1));
                require(e.events.equals(Arrays.asList(Long.MAX_VALUE + ":true", "7:false", Long.MAX_VALUE + ":false")), "modern callbacks preserve token and policy");
            }
            e.events.clear();
            for (String bad : new String[] {null, "UtteranceId", "QtSpeech:", "QtSpeech:0", "QtSpeech:-1", "QtSpeech:+7", "QtSpeech:07", "QtSpeech:7 ", "QtSpeech:9223372036854775808"}) {
                if (api < 15) t.complete(bad);
                else { t.progress.onStart(bad); t.progress.onDone(bad); t.progress.onError(bad); }
            }
            require(e.events.isEmpty(), "malformed token");
            t.result = TextToSpeech.ERROR;
            require(e.say("error", 8L) == TextToSpeech.ERROR, "return start failure");
            t.throwOnSpeak = true;
            require(e.say("exception", 9L) == TextToSpeech.ERROR, "translate runtime failure");
            require(e.events.isEmpty(), "dispatch failure emits no untagged completion");
            if (api < 15) {
                t.throwOnSpeak = false; t.result = TextToSpeech.SUCCESS; t.fast = true;
                require(e.say("fast", 10L) == TextToSpeech.SUCCESS, "fast dispatch");
                require(e.events.equals(Arrays.asList("10:false")), "fast callback token");
            }
            if (api < 15) {
                TextToSpeech.failRegistration = true;
                readyCalls = errorCalls = 0;
                new TtsGenerationFixture();
                require(readyCalls == 0 && errorCalls == 1, "failed registration must not publish Ready");
                TextToSpeech.failRegistration = false;
            }
            TextToSpeech.synchronousInit = true;
            readyCalls = errorCalls = 0;
            new TtsGenerationFixture();
            require(readyCalls == 1 && errorCalls == 0, "early init callback delivered exactly once after assignment");
            require(api >= 15 || TextToSpeech.last.completed != null, "early init installed legacy callback");
            TextToSpeech.synchronousInit = false;
            System.out.println("PASS actual Java adapter API" + api + " token/listener/error/malformed contracts");
        }
    }
}
