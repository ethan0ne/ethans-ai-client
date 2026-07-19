import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_font_weights.dart';

/// Whether the "processing files" step (document text extraction / OCR
/// before a send) is active, and — when the current step tracks a known
/// file count — how far through it (0..1). `progress == null` while active
/// means "no total known yet" (e.g. the OCR step, which hands a whole batch
/// to one call instead of going file-by-file) — falls back to an
/// indeterminate spinner, same look this had before progress existed.
class FileProcessingStatus {
  const FileProcessingStatus({this.active = false, this.progress});

  final bool active;
  final double? progress;

  static const idle = FileProcessingStatus();
}

class FileProcessingIndicator extends StatelessWidget {
  const FileProcessingIndicator({super.key, this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    // Match _ReasoningSection styling from ChatMessageWidget
    final bg = cs.primaryContainer.withValues(alpha: isDark ? 0.25 : 0.30);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress,
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                progress != null
                    ? l10n.homePageProcessingFilesProgress(
                        (progress! * 100).round(),
                      )
                    : l10n.homePageProcessingFiles,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: AppFontWeights.emphasis,
                  color: cs.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
