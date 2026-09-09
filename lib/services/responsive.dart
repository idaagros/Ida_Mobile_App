// lib/services/responsive.dart
//
// Shared breakpoint logic for making screens behave differently on a
// wide browser window versus a phone, instead of the same single
// mobile-designed column stretching across whatever width it's given.
// Nothing in this app currently branches by screen width at all -
// this is the foundation that lets individual screens start doing so,
// one at a time, without each screen inventing its own breakpoint
// numbers or its own definition of "wide enough for a grid."
//
// Breakpoints follow common practice, not an arbitrary choice:
// <600 = phone, 600-1024 = tablet/narrow-desktop, >1024 = desktop.
// These match Material Design's own guidance, so they'll feel
// familiar rather than idiosyncratic to this app specifically.

import 'package:flutter/material.dart';

class Responsive {
  static const double mobileBreakpoint = 600;
  static const double desktopBreakpoint = 1024;

  static bool isMobile(BuildContext context) =>
      MediaQuery.of(context).size.width < mobileBreakpoint;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w >= mobileBreakpoint && w < desktopBreakpoint;
  }

  static bool isDesktop(BuildContext context) =>
      MediaQuery.of(context).size.width >= desktopBreakpoint;

  // How many grid columns a tile/card grid should use at the current
  // width - the single most common question a retrofitted screen asks.
  // 1 on phone (today's behaviour, unchanged), 2 on tablet, 3 on
  // desktop. A screen can override this default by calling
  // gridColumnsForWidth directly with its own thresholds if a
  // particular layout needs a different count.
  static int gridColumns(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return gridColumnsForWidth(w);
  }

  static int gridColumnsForWidth(double width) {
    if (width >= desktopBreakpoint) return 3;
    if (width >= mobileBreakpoint) return 2;
    return 1;
  }

  // Desktop-web-specific problem this exists to solve: a mobile-
  // designed form or content block stretched edge-to-edge across a
  // 1920px browser window looks broken, not spacious. Constrains
  // content to a sensible reading/working width and centers it,
  // while leaving mobile screens completely untouched (returns the
  // child as-is below the desktop breakpoint).
  static Widget constrainedContent(BuildContext context, Widget child,
      {double maxWidth = 1100}) {
    if (!isDesktop(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
