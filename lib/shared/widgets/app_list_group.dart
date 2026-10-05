import 'package:flutter/material.dart';

import '../../theme/design_tokens.dart';
import '../../theme/app_font_weights.dart';
import 'app_dialog_controls.dart';
import 'app_list_tile.dart';
import 'ios_tactile.dart';

/// Icon action aligned to a grouped-list section header.
class AppListGroupHeaderAction extends StatelessWidget {
  const AppListGroupHeaderAction({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.size = 20,
    this.enabled = true,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return IosIconButton(
      icon: icon,
      size: size,
      minSize: 40,
      color: primary,
      pressedColor: primary,
      semanticLabel: semanticLabel,
      enabled: enabled,
      onTap: onTap,
    );
  }
}

/// Standard spacing for multiple actions at the end of a section header.
class AppListGroupHeaderActions extends StatelessWidget {
  const AppListGroupHeaderActions({
    super.key,
    required this.children,
    this.spacing = AppSpacing.xxs,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < children.length; index++) ...[
          if (index > 0) SizedBox(width: spacing),
          children[index],
        ],
      ],
    );
  }
}

/// Section label used above grouped settings/list rows across the client.
class AppListGroupHeader extends StatelessWidget {
  const AppListGroupHeader({
    super.key,
    required this.title,
    this.first = false,
    this.padding,
    this.color,
    this.leading,
    this.trailing,
  });

  final String title;
  final bool first;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final defaultPadding = trailing == null
        ? EdgeInsets.fromLTRB(
            AppSpacing.lg - AppSpacing.md,
            first ? 0 : AppSpacing.lg,
            AppSpacing.lg - AppSpacing.md,
            AppSpacing.xs,
          )
        : EdgeInsets.fromLTRB(
            AppSpacing.lg - AppSpacing.md,
            first ? 0 : AppSpacing.lg - AppSpacing.xs,
            AppSpacing.lg - AppSpacing.md,
            first ? 0 : 0,
          );
    return Padding(
      padding: padding ?? defaultPadding,
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.start,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: AppFontWeights.semibold,
                color: color ?? AppColors.secondaryLabel(brightness),
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.xs),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Shared surface for grouped app lists.
///
/// The group owns the shared palette fill, clipping and corner radius. Static
/// outline borders are omitted; callers may pass [outlineColor] for transient
/// states such as desktop hover. [boxShadow] is available for elevated popup
/// lists while keeping their edge treatment consistent with regular groups.
class AppListGroup extends StatelessWidget {
  const AppListGroup({
    super.key,
    required Widget child,
    this.backgroundColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.md)),
    this.outlineColor,
    this.outlineWidth = 1,
    this.boxShadow,
    this.margin,
    this.padding,
    this.width,
    this.height,
    this.constraints,
    this.clipBehavior = Clip.antiAlias,
  }) : child = child,
       children = null;

  const AppListGroup.list({
    super.key,
    required List<Widget> children,
    this.backgroundColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(AppRadius.md)),
    this.outlineColor,
    this.outlineWidth = 1,
    this.boxShadow,
    this.margin,
    this.padding,
    this.width,
    this.height,
    this.constraints,
    this.clipBehavior = Clip.antiAlias,
  }) : child = null,
       children = children;

  final Widget? child;
  final List<Widget>? children;
  final Color? backgroundColor;
  final BorderRadiusGeometry borderRadius;
  final Color? outlineColor;
  final double outlineWidth;
  final List<BoxShadow>? boxShadow;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final BoxConstraints? constraints;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inDialog = AppDialogControlScope.of(context);
    final content =
        child ??
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _alignTileDividers(
            children!,
            context,
            dialogHasDesignedBackground:
                inDialog &&
                (AppDialogControlScope.hasBackgroundOf(context) ||
                    (backgroundColor?.a ?? 0) > 0 ||
                    outlineColor != null),
          ),
        );

    return Container(
      width: width,
      height: height,
      constraints: constraints,
      margin: margin,
      padding: padding,
      clipBehavior: inDialog && backgroundColor == null && outlineColor == null
          ? Clip.none
          : clipBehavior,
      decoration: BoxDecoration(
        color:
            backgroundColor ??
            (inDialog
                ? Colors.transparent
                : AppColors.listGroupSurfaceFor(theme)),
        borderRadius: borderRadius,
        border: outlineColor == null
            ? null
            : Border.all(color: outlineColor!, width: outlineWidth),
        boxShadow: boxShadow,
      ),
      child: inDialog && ((backgroundColor?.a ?? 0) > 0 || outlineColor != null)
          ? AppDialogControlScope(hasDesignedBackground: true, child: content)
          : content,
    );
  }
}

List<Widget> _alignTileDividers(
  List<Widget> children,
  BuildContext context, {
  required bool dialogHasDesignedBackground,
}) {
  final aligned = List<Widget>.of(children);
  for (var index = 0; index < children.length; index++) {
    final divider = children[index];
    if (divider is! AppListDivider) continue;

    AppListTileDividerMetrics? row;
    for (var previous = index - 1; previous >= 0; previous--) {
      final sibling = children[previous];
      if (sibling is AppListDivider) continue;
      if (sibling is AppListTileDividerMetrics) {
        row = sibling as AppListTileDividerMetrics;
      }
      break;
    }
    if (row == null) {
      for (var next = index + 1; next < children.length; next++) {
        final sibling = children[next];
        if (sibling is AppListDivider) continue;
        if (sibling is AppListTileDividerMetrics) {
          row = sibling as AppListTileDividerMetrics;
        }
        break;
      }
    }
    if (row != null) {
      aligned[index] = divider.aligned(
        row.dividerInsets(
          context,
          dialogHasDesignedBackground: dialogHasDesignedBackground,
        ),
      );
    }
  }
  return aligned;
}

/// Palette-aware separator shared by grouped list sections.
class AppListDivider extends StatelessWidget {
  const AppListDivider({
    super.key,
    this.indent = 16,
    this.endIndent = 16,
    this.height = 1,
    this.thickness = 1,
    this.color,
  });

  const AppListDivider.forTile({
    super.key,
    required bool hasLeading,
    double horizontalPadding = 16,
    double minLeadingWidth = 24,
    double horizontalTitleGap = 16,
    double? leadingWidth,
    double? trailingPadding,
    this.height = 1,
    this.thickness = 1,
    this.color,
  }) : indent =
           horizontalPadding +
           (hasLeading
               ? (leadingWidth != null && leadingWidth > minLeadingWidth
                         ? leadingWidth
                         : minLeadingWidth) +
                     horizontalTitleGap
               : 0),
       endIndent = trailingPadding ?? horizontalPadding;

  final double indent;
  final double endIndent;
  final double height;
  final double thickness;
  final Color? color;

  AppListDivider aligned(AppListDividerInsets insets) => AppListDivider(
    key: key,
    indent: insets.indent,
    endIndent: insets.endIndent,
    height: height,
    thickness: thickness,
    color: color,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Divider(
      height: height,
      thickness: thickness,
      indent: indent,
      endIndent: endIndent,
      color: color ?? AppColors.listDividerFor(theme),
    );
  }
}
