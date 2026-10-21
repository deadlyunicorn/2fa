import 'package:flutter/material.dart';

/// Responsive wrapper that centers and constrains content to a maximum width
/// on wide screens (>= 840 dp) according to UX specification (§7).
class ResponsiveContentWrapper extends StatelessWidget {
  const ResponsiveContentWrapper({
    required this.child,
    this.maxWidth = 720.0,
    this.breakpoint = 840.0,
    super.key,
  });

  final Widget child;
  final double maxWidth;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= breakpoint) {
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          );
        }
        return child;
      },
    );
  }
}
