// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 OpenKaryon
//
// widgets-gallery - builds one tab per widget cluster (for the visual window)
// and runs a headless behavioural self-test over the same widget classes.
#ifndef GALLERY_H
#define GALLERY_H

class QWidget;
class SmokeReporter;

// Build the tab widget shown in GUI mode: each function returns a page that
// constructs a representative set of that cluster's widgets.
QWidget *makeButtonsTab();
QWidget *makeInputsTab();
QWidget *makeRangesTab();
QWidget *makeItemViewsTab();
QWidget *makeContainersTab();
QWidget *makeTextTab();
QWidget *makeGraphicsTab();
QWidget *makePopupsTab();
QWidget *makeWindowPopupLabTab();
QWidget *makeShapedWindowsTab();
QWidget *makeNativeDialogsTab();
QWidget *makeFontsDpiTab();
QWidget *makeModelViewStressTab();
QWidget *makeClipboardDragDropTab();
QWidget *makeWinExtrasTaskbarTab();

QWidget *buildGallery();             // assembles all tabs
void checkGalleryRendering(SmokeReporter &r);

// Headless behavioural checks over the widget classes (used by --selftest).
void checkWidgets(SmokeReporter &r);
void checkItemViewWidgets(SmokeReporter &r);
void checkLayoutsAndWindows(SmokeReporter &r);
void checkDialogs(SmokeReporter &r);
void checkGraphicsScene(SmokeReporter &r);
void checkGraphicsExtensionPoints(SmokeReporter &r);
#ifdef SMOKE_HAVE_WINEXTRAS
void checkWinExtras(SmokeReporter &r);
#endif
void checkStyleOptions(SmokeReporter &r);
void checkAbstractBasesViaConcrete(SmokeReporter &r);
void checkGestures(SmokeReporter &r);
void checkUndoFramework(SmokeReporter &r);
void checkPrinting(SmokeReporter &r);
void checkMdiMovieTrayMisc(SmokeReporter &r);
void checkDragDropEvents(SmokeReporter &r);
void checkGraphicsExtras(SmokeReporter &r);
void checkEventCatalogue(SmokeReporter &r);
void checkModelBasesAndFileModels(SmokeReporter &r);
void checkMiscQtBaseTail(SmokeReporter &r);
void checkAccessibilityAndModelHelpers(SmokeReporter &r);
void checkQtBaseWidgetsTail2(SmokeReporter &r);
void checkMultimediaWidgets(SmokeReporter &r);
// Defined by the Qt 4-only sources selected in widgets/CMakeLists.txt and
// called only from main.cpp's Qt 4 branch.
void addQt3SupportChecks(SmokeReporter &r);
void addQtBaseQt4Checks(SmokeReporter &r);
void addPlatform4Checks(SmokeReporter &r);
void addQtBaseWidgetsTail2Qt4Checks(SmokeReporter &r);
void addAccessibilityQt4Checks(SmokeReporter &r);

#endif // GALLERY_H
