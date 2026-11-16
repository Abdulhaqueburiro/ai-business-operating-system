import 'package:flutter/material.dart';

/// Screens at least this wide (web, tablet, desktop) get the wide layout:
/// a top bar instead of the bottom bar and more columns.
const double kWideBreakpoint = 720;

bool isWideWidth(double width) => width >= kWideBreakpoint;

bool isWide(BuildContext context) =>
    isWideWidth(MediaQuery.sizeOf(context).width);

/// Centers page content and keeps it from stretching too wide on big screens.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.child,
    this.maxWidth = 880,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 24),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
