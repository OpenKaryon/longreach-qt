# painting-lab: focused raster/text/alpha/print-preview lab.
smoke_add_app(painting-lab
    MODULES Core Gui Widgets PrintSupport Svg
    SOURCES main.cpp ../common/smokecheck.h
)
