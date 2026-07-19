import 'package:Kelivo/features/home/controllers/streaming_content_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('markResponseStarted 在有 notifier 时把 responseStarted 置为 true', () {
    final notifier = StreamingContentNotifier();
    notifier.getNotifier('msg-1');

    notifier.markResponseStarted('msg-1');

    expect(notifier.getNotifier('msg-1').value.responseStarted, isTrue);
  });

  test('markResponseStarted 不会影响已有的正文/推理内容', () {
    final notifier = StreamingContentNotifier();
    notifier.getNotifier('msg-1');
    notifier.updateContent('msg-1', '已经收到的正文', 10);
    notifier.updateReasoning('msg-1', reasoningText: '推理中');

    notifier.markResponseStarted('msg-1');

    final value = notifier.getNotifier('msg-1').value;
    expect(value.responseStarted, isTrue);
    expect(value.content, '已经收到的正文');
    expect(value.reasoningText, '推理中');
  });

  test('markResponseStarted 对不存在的 messageId 不抛异常也不创建 notifier', () {
    final notifier = StreamingContentNotifier();
    expect(() => notifier.markResponseStarted('missing'), returnsNormally);
    expect(notifier.hasNotifier('missing'), isFalse);
  });

  test('后续的 updateContent/updateReasoning 更新不会把 responseStarted 重置为 false', () {
    final notifier = StreamingContentNotifier();
    notifier.getNotifier('msg-1');
    notifier.markResponseStarted('msg-1');

    notifier.updateContent('msg-1', '继续输出', 20);
    notifier.updateReasoning('msg-1', reasoningText: '继续推理');
    notifier.notifyToolPartsUpdated('msg-1');
    notifier.forceRebuild('msg-1');

    expect(notifier.getNotifier('msg-1').value.responseStarted, isTrue);
  });
}
