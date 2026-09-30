part of 'assistant_settings_edit_page.dart';

class _InstructionInjectionsTab extends StatelessWidget {
  const _InstructionInjectionsTab({required this.assistantId});

  final String assistantId;

  @override
  Widget build(BuildContext context) =>
      InstructionInjectionPage(assistantId: assistantId, embedded: true);
}

class _WorldBooksTab extends StatelessWidget {
  const _WorldBooksTab({required this.assistantId});

  final String assistantId;

  @override
  Widget build(BuildContext context) =>
      WorldBookPage(assistantId: assistantId, embedded: true);
}
