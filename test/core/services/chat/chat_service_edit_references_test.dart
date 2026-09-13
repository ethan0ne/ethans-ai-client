import 'package:flutter_test/flutter_test.dart';

import 'package:Kelivo/core/models/chat_input_data.dart';
import 'package:Kelivo/core/models/chat_message.dart';
import 'package:Kelivo/core/services/chat/chat_service.dart';

void main() {
  test('手打的引用样式文本不会被猜测成附件引用', () {
    final message = ChatMessage(
      role: 'user',
      content: '请搜索 @Image: Image 1',
      conversationId: 'conversation-edit-plain-at',
      hostedImagesJson:
          '[{"id":"img-1","url":"https://example.com/img-1","mimeType":"image/jpeg"}]',
    );

    expect(ChatService().editAttachmentReferences(message), isEmpty);
  });

  test('编辑托管消息时恢复图片和文件引用 token', () {
    final message = ChatMessage(
      role: 'user',
      content: '请比较 @Image: Image 2 和 @Image: Image 1',
      conversationId: 'conversation-edit-references',
      hostedImagesJson:
          '[{"id":"img-1","url":"https://example.com/img-1","mimeType":"image/jpeg"},{"id":"img-2","url":"https://example.com/img-2","mimeType":"image/jpeg"}]',
      hostedFilesJson:
          '[{"id":"file-1","filename":"需求说明.pdf","mimeType":"application/pdf","url":"https://example.com/file-1"}]',
      attachmentReferencesJson:
          '[{"type":"text","text":"请比较 "},{"type":"attachment","token":"@Image: Image 2","attachment_id":"img-2"},{"type":"text","text":" 和 "},{"type":"attachment","token":"@Image: Image 1","attachment_id":"img-1"}]',
    );

    final references = ChatService().editAttachmentReferences(message);

    expect(references, hasLength(2));
    expect(references[0].token, '@Image: Image 2');
    expect(references[0].fileId, 'img-2');
    expect(references[1].token, '@Image: Image 1');
    expect(references[1].fileId, 'img-1');
  });

  test('编辑本地消息时恢复草稿附件索引', () {
    final message = ChatMessage(
      role: 'user',
      content: '请看 @Image: photo.png\n[image:/tmp/photo.png]',
      conversationId: 'conversation-edit-local-references',
      attachmentReferencesJson:
          '[{"type":"text","text":"请看 "},{"type":"attachment","token":"@Image: photo.png","draft_image_index":0},{"type":"text","text":"\\n"}]',
    );

    final references = ChatService().editAttachmentReferences(message);

    expect(references, hasLength(1));
    expect(references.single.token, '@Image: photo.png');
    expect(references.single.draftImageIndex, 0);
  });

  test('编辑引用历史附件的消息时恢复会话级引用', () {
    final message = ChatMessage(
      role: 'user',
      content: '请修改 @Image: Image 2',
      conversationId: 'conversation-edit-history-reference',
      attachmentReferencesJson:
          '[{"type":"text","text":"请修改 "},{"type":"attachment","token":"@Image: Image 2","attachment_id":"img-2"}]',
    );

    final references = ChatService().editAttachmentReferences(
      message,
      conversationCandidates: const [
        ChatImageReferenceCandidate(
          id: 'history:img-2',
          fileId: 'img-2',
          label: 'Image 2',
          mimeType: 'image/jpeg',
        ),
      ],
    );

    expect(references, hasLength(1));
    expect(references.single.token, '@Image: Image 2');
    expect(references.single.fileId, 'img-2');
  });
}
