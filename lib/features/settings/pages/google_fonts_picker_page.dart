import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../l10n/app_localizations.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_list_tile.dart';
import '../../../theme/design_tokens.dart';

class GoogleFontsPickerPage extends StatefulWidget {
  const GoogleFontsPickerPage({super.key, required this.title});
  final String title;
  @override
  State<GoogleFontsPickerPage> createState() => _GoogleFontsPickerPageState();
}

class _GoogleFontsPickerPageState extends State<GoogleFontsPickerPage> {
  late final TextEditingController _filterCtrl;

  @override
  void initState() {
    super.initState();
    _filterCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final brightness = Theme.of(context).brightness;
    final allFonts = GoogleFonts.asMap().keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return AppScaffold(
      backgroundColor: AppColors.groupedBackgroundFor(context),
      extendBodyBehindAppBar: false,
      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Lucide.ArrowLeft,
            semanticLabel: l10n.settingsPageBackButton,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: AppScaffoldTitle(widget.title),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _filterCtrl,
              decoration: InputDecoration(
                hintText: l10n.fontPickerFilterHint,
                isDense: true,
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white10
                    : Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.28),
                    width: 0.8,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filtered(allFonts).length,
              itemBuilder: (context, i) {
                final fam = _filtered(allFonts)[i];
                return AppListTile(
                  onTap: () => Navigator.of(context).pop(fam),
                  title: Text(
                    fam,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      color: cs.onSurface,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  trailing: Text(
                    'Aa字',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.getFont(
                      fam,
                      fontSize: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<String> _filtered(List<String> all) {
    final q = _filterCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((e) => e.toLowerCase().contains(q)).toList();
  }
}
