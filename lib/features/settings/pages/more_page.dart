import 'package:flutter/material.dart';
import '../../../utils/url_launcher_ext.dart';
import '../../../shared/widgets/favicon.dart';
import '../../../theme/design_tokens.dart';
import '../../../shared/layouts/app_scaffold.dart';
import '../../../shared/widgets/app_button_island.dart';
import '../../../shared/widgets/app_list_group.dart';

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Widget title(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(color: cs.primary),
      ),
    );

    return AppScaffold(
      backgroundColor: AppColors.groupedBackgroundFor(context),

      leadingIslands: [
        [
          AppButtonIslandButton(
            icon: Icons.arrow_back,
            semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ],
      ],
      title: const SizedBox.shrink(),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            AppScaffold.scrollContentTop(context),
            16,
            AppScaffold.defaultScrollContentBottomSpacing,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LeaderBoard section
              title('LLM排行榜'),
              Row(
                children: const [
                  Expanded(
                    child: LeaderBoardItem(
                      url: 'https://lmarena.ai/leaderboard',
                      name: 'LMArena',
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: LeaderBoardItem(
                      url: 'https://livebench.ai/#/',
                      name: 'LiveBench',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LeaderBoardItem extends StatelessWidget {
  const LeaderBoardItem({super.key, required this.url, required this.name});

  final String url;
  final String name;

  String _hostOf(String url) {
    try {
      final u = Uri.parse(url);
      return u.host.isNotEmpty ? u.host : url;
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150),
      child: AppListGroup(
        backgroundColor: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.openUrl(url),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Favicon(url: url, size: 20),
                  const SizedBox(height: 4),
                  Text(name, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    _hostOf(url),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.textTheme.labelSmall?.color?.withValues(
                        alpha: 0.75,
                      ),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
