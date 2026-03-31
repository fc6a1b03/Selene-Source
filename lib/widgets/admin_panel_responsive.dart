import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:selene/design/design_system.dart';

class AdminPanelLayout {
  const AdminPanelLayout._();

  static bool isCompactWidth(double width) => width < 840;

  static bool isTightWidth(double width) => width < 560;

  static double dialogWidth(double width, {double maxWidth = 640}) {
    return math.min(maxWidth, math.max(320, width - 48));
  }
}

class AdminSectionHeader extends StatelessWidget {
  const AdminSectionHeader({
    super.key,
    required this.isDark,
    required this.title,
    required this.description,
    this.actions = const <Widget>[],
    this.trailing,
    this.contentSpacing = 16,
  });

  final bool isDark;
  final String title;
  final String description;
  final List<Widget> actions;
  final Widget? trailing;
  final double contentSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = AdminPanelLayout.isCompactWidth(
          constraints.maxWidth,
        );
        final Widget titleBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              title,
              style: AppTypography.headlineLargeStyle(isDark: isDark),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: AppTypography.bodyMediumStyle(isDark: isDark).copyWith(
                color: AppColors.textSecondary(isDark: isDark),
              ),
            ),
          ],
        );
        final Widget? actionBlock = actions.isEmpty
            ? null
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: compact ? WrapAlignment.start : WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: titleBlock),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
              if (actionBlock != null) ...<Widget>[
                SizedBox(height: contentSpacing),
                actionBlock,
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: titleBlock),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: 16),
              trailing!,
            ],
            if (actionBlock != null) ...<Widget>[
              const SizedBox(width: 16),
              Flexible(child: actionBlock),
            ],
          ],
        );
      },
    );
  }
}
