// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
package org.qtproject.qt.android.speech;
import java.util.*;
import android.speech.tts.TextToSpeech;

class TtsGenerationFixture extends QtTextToSpeech {
    static final List<String> events = new ArrayList<String>();
    TtsGenerationFixture(long id) { super(new android.content.Context(), id, "fixture"); }
    void notifyReady(long id,long g){events.add("ready:"+id+":"+g);}
    void notifyError(long id,long g,long reason){events.add("error:"+id+":"+g+":"+reason);}
    void notifySpeaking(long id,long g){events.add("start:"+id+":"+g);}
    void notifyRangeStart(long id,long g,int s,int e,int f){events.add("range:"+id+":"+g+":"+s+":"+e);}
    void notifyBeginSynthesis(long id,long g,int r,int format,int c){events.add("begin:"+id+":"+g+":"+r+":"+format+":"+c);}
    void notifyAudioAvailable(long id,long g,byte[] b){events.add("audio:"+id+":"+g+":"+b.length);}
    void notifyEndSynthesis(long id,long g){events.add("end:"+id+":"+g);}
    static void require(boolean b,String s){if(!b)throw new AssertionError(s+" "+events);}
    static void expected(String... values){require(events.equals(Arrays.asList(values)),"callback sequence");events.clear();}
    public static void main(String[] args) {
        TextToSpeech.synchronousInit=true;
        TtsGenerationFixture e=new TtsGenerationFixture(41); TextToSpeech t=TextToSpeech.last;
        expected("ready:41:0");
        e.say("old",2); String old=t.ids.get(0);
        e.say("new",3); String current=t.ids.get(1);
        require(!old.equals(current),"utterance IDs reused");
        t.progress.onStart(current); t.progress.onDone(old); t.progress.onError(old, -1);
        t.progress.onRangeStart(current,0,3,0); t.progress.onDone(current);
        expected("start:41:3","ready:41:2","error:41:2:4","range:41:3:0:3","ready:41:3");
        // Java preserves tokens. The C++ queue decides whether a request is current.
        t.result=TextToSpeech.ERROR; e.say("invalid input",4); expected("error:41:4:3");
        e.setPitch(1.5f,4); e.setRate(1.5f,4); expected("error:41:4:2","error:41:4:2");
        t.result=TextToSpeech.SUCCESS; e.say("cancel",5); e.stop();
        require(t.stops==1,"stop not sent"); expected("error:41:5:4");
        e.synthesize("pcm",6); String synth=t.ids.get(t.ids.size()-1);
        t.progress.onBeginSynthesis(synth,16000,android.media.AudioFormat.ENCODING_PCM_16BIT,1);
        t.progress.onAudioAvailable(synth,new byte[]{1,2,3}); t.progress.onDone(synth);
        expected("begin:41:6:16000:2:1","audio:41:6:3","end:41:6");
        for(String bad:new String[]{null,"UtteranceId","UtteranceId:0","UtteranceId:-1","UtteranceId:01","UtteranceId:+1","UtteranceId:9223372036854775808","SynthesizeId:no"}){
            t.progress.onStart(bad);t.progress.onDone(bad);t.progress.onError(bad,-1);
            t.progress.onAudioAvailable(bad,new byte[0]);
        }
        expected();
        e.shutdown(); require(t.shutdowns==1,"shutdown not sent");
        TextToSpeech.synchronousInit=false;
        TtsGenerationFixture failed=new TtsGenerationFixture(42);
        TextToSpeech.last.init.onInit(TextToSpeech.ERROR); expected("error:42:0:1");
        System.out.println("PASS Java inline/async init, request tokens, input/config errors, stop and synthesis callbacks");
    }
}
