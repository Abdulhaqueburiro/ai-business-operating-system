import 'package:flutter/material.dart';

/// Lets any screen inside the main frame switch tabs:
/// 0 Home, 1 Orders, 2 Stock, 3 Customers, 4 More.
class ShellScope extends InheritedWidget {
  const ShellScope({
    super.key,
    required this.selectTab,
    required super.child,
  });

  final void Function(int index) selectTab;

  static ShellScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
}
