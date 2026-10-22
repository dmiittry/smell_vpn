import 'dart:math' as math;

import 'package:flutter/material.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final padding = MediaQuery.sizeOf(context).width >= 900 ? 36.0 : 22.0;
      final horizontal = math.max(padding, (bounds.maxWidth - 1100) / 2);
      return ListView.builder(
        padding: EdgeInsets.symmetric(
          vertical: padding,
          horizontal: horizontal,
        ),
        itemCount: children.length,
        itemBuilder: (context, index) => children[index],
      );
    },
  );
}
