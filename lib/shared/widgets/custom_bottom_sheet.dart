import 'package:flutter/material.dart';

import 'app_popup_sheet.dart';

typedef CustomBottomSheetBuilder =
    Widget Function(BuildContext context, ScrollController scrollController);

/// Compatibility entry point for callers that need a sheet-owned scroll
/// controller. The route chrome and adaptive surface come from
/// [PopupContentFrame] through [showAppPopupSheet].
Future<T?> showCustomBottomSheet<T>({
  required BuildContext context,
  required String title,
  required CustomBottomSheetBuilder builder,
  int? count,
  String? closeSemanticLabel,
  double partialHeightFactor = 0.60,
  double expandedHeightFactor = 0.90,
}) {
  final screenHeight = MediaQuery.sizeOf(context).height;
  final maxFactor = expandedHeightFactor > partialHeightFactor
      ? expandedHeightFactor
      : partialHeightFactor;
  return showAppPopupSheet<T>(
    context: context,
    title: count != null && count > 1 ? '$title  $count' : title,
    closeSemanticLabel: closeSemanticLabel,
    constraints: BoxConstraints(maxHeight: screenHeight * maxFactor),
    isScrollControlled: true,
    builder: (sheetContext) => _CustomPopupSheetBody(builder: builder),
  );
}

class _CustomPopupSheetBody extends StatefulWidget {
  const _CustomPopupSheetBody({required this.builder});

  final CustomBottomSheetBuilder builder;

  @override
  State<_CustomPopupSheetBody> createState() => _CustomPopupSheetBodyState();
}

class _CustomPopupSheetBodyState extends State<_CustomPopupSheetBody> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _scrollController);
}
