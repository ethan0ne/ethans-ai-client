import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:Kelivo/core/services/chat/chat_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getApplicationCachePath() async => '$path/cache';

  @override
  Future<String?> getTemporaryPath() async => '$path/tmp';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'kelivo_version_selections_test_',
    );
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ChatService version selections network boundary', () {
    test(
      'versionSelectionsForNetwork strips the local hosted: prefix',
      () async {
        // Reproduces the reported bug: `setSelectedVersion` is always called
        // with the pager's `hosted:`-prefixed groupId (see
        // `message_list_view.dart`'s `gid = message.groupId ?? message.id`,
        // where hosted messages' local `groupId` is canonicalized to
        // `hosted:$serverGroupId`). A send/regenerate/edit network call must
        // send the BARE server group id — the backend's `group_id` column
        // has no such prefix — or the server silently ignores the entry
        // (wrong key, no match) and falls back to whatever it last had,
        // instead of the version the user actually just switched to.
        final service = ChatService();
        await service.init();
        final conversation = await service.createDraftConversation(
          title: 'Chat',
        );

        await service.setSelectedVersion(
          conversation.id,
          'hosted:6a4c4473-a174-403d-92bc-1c7d2702d811',
          1,
        );

        expect(service.getVersionSelections(conversation.id), {
          'hosted:6a4c4473-a174-403d-92bc-1c7d2702d811': 1,
        });
        expect(service.versionSelectionsForNetwork(conversation.id), {
          '6a4c4473-a174-403d-92bc-1c7d2702d811': 1,
        });
      },
    );

    test(
      'versionSelectionsForNetwork leaves already-bare keys untouched',
      () async {
        final service = ChatService();
        await service.init();
        final conversation = await service.createDraftConversation(
          title: 'Chat',
        );

        await service.setSelectedVersion(
          conversation.id,
          '6a4c4473-a174-403d-92bc-1c7d2702d811',
          2,
        );

        expect(service.versionSelectionsForNetwork(conversation.id), {
          '6a4c4473-a174-403d-92bc-1c7d2702d811': 2,
        });
      },
    );
  });
}
