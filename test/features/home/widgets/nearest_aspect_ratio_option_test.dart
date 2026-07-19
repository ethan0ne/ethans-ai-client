import 'package:Kelivo/features/home/widgets/chat_input_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const options = ['1:1', '16:9', '9:16', '4:3', '3:4', '3:2', '2:3'];

  test('挑选与实际宽高最接近的横屏比例', () {
    expect(nearestAspectRatioOption(const Size(1920, 1080), options), '16:9');
  });

  test('挑选与实际宽高最接近的竖屏比例', () {
    expect(nearestAspectRatioOption(const Size(1080, 1920), options), '9:16');
  });

  test('正方形素材优先选中 1:1 而不是数值上更接近的其他比例', () {
    expect(nearestAspectRatioOption(const Size(1000, 1000), options), '1:1');
  });

  test('对数尺度比较使竖屏/横屏选项保持对称，而非被数值范围偏向横屏', () {
    // 4:3 (1.333) 和 3:4 (0.75) 到 1:1 的对数距离应完全对称——一个稍宽于
    // 3:4 的素材应该选中 3:4，而不是因为线性差值更小就被拉向 1:1。
    expect(nearestAspectRatioOption(const Size(780, 1000), options), '3:4');
  });

  test('尺寸为 0 或负数时返回 null', () {
    expect(nearestAspectRatioOption(const Size(0, 100), options), isNull);
    expect(nearestAspectRatioOption(const Size(100, 0), options), isNull);
    expect(nearestAspectRatioOption(const Size(-10, 100), options), isNull);
  });

  test('选项列表为空时返回 null', () {
    expect(nearestAspectRatioOption(const Size(1920, 1080), const []), isNull);
  });

  test('忽略格式不合法的选项，仍从其余选项里选出结果', () {
    expect(
      nearestAspectRatioOption(const Size(1920, 1080), const [
        'bogus',
        '16:9',
        '0:5',
        '5:0',
      ]),
      '16:9',
    );
  });

  test('全部选项格式不合法时返回 null', () {
    expect(
      nearestAspectRatioOption(const Size(1920, 1080), const ['bogus', '0:5']),
      isNull,
    );
  });
}
