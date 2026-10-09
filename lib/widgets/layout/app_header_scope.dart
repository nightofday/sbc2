import 'package:flutter/widgets.dart';

/// Widgets every page shows at the right of its header, such as the stock
/// alerts bell. Provided once by the shell and read by [AppPage], so a page
/// does not have to add them itself.
class AppHeaderScope extends InheritedWidget {
  final Widget? trailing;

  const AppHeaderScope({super.key, this.trailing, required super.child});

  static Widget? trailingOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppHeaderScope>()?.trailing;

  @override
  bool updateShouldNotify(AppHeaderScope oldWidget) =>
      trailing != oldWidget.trailing;
}
