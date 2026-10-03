import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_dialog.dart';

class LoadingDialogCard extends StatelessWidget {
  const LoadingDialogCard({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final hasLabel = label != null && label!.trim().isNotEmpty;

    return Center(
      child: AppDialogSurface(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 96, maxWidth: 240),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              hasLabel ? 16 : 18,
              20,
              hasLabel ? 16 : 18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CupertinoActivityIndicator(radius: 16),
                if (hasLabel) ...[
                  const SizedBox(height: 12),
                  Text(
                    label!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
