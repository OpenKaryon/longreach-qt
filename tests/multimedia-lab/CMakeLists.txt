# multimedia-lab: media/camera/audio manual smoke lab.
#
# Two halves, one per era, because Qt 4 and Qt 5 both ship a module called
# QtMultimedia and they share the name and nothing else. main.cpp holds the Qt 5
# and Qt 6 window and checks - player, playlist, camera, video widget - and
# lab_qt4.cpp holds the Qt 4 ones, which are the low-level layer: audio devices,
# formats, video frames and surfaces. The application, its name and its
# --selftest contract are the same on all three.
#
# Qt 4 builds it with multimedia-lab.pro (main.cpp and lab_qt4.cpp).
smoke_add_app(multimedia-lab
    MODULES Core Gui Widgets Multimedia MultimediaWidgets TextToSpeech
    SOURCES main.cpp speech_tab.cpp speech_tab.h ../common/smokecheck.h
)
