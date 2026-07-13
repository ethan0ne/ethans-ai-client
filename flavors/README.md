# Flavor 切换脚本使用说明

本目录配合根目录的 `build.sh`，用于在 `normal` / `miranda` 两个品牌之间切换。
两者是完全平行、对等的 flavor（各自的品牌信息定义在 `flavors/normal.sh`、
`flavors/miranda.sh`），互相切换时直接做字符串替换，不依赖 `git checkout`
之类的还原操作。

## 涉及文件

- `flavors/normal.sh`、`flavors/miranda.sh`：每个 flavor 的品牌数据（App
  名称、Android applicationId、iOS/macOS/Linux bundle id、Windows 互斥体
  名、图标源目录等）。
- `assets/normal_version/`、`assets/miranda_version/`：两个 flavor 各自的
  图标源文件（`app_icon.png` / `app_icon_dark.png` / `app_icon_macos2.png`
  / `app_icon.ico`）。
- `build.sh`：读取上面两份数据，做替换 + 调用 `flutter_launcher_icons`
  重新生成各平台图标。
- `.flavor_current`：记录当前处于哪个 flavor，仅本机有效，不提交到 git
  （见根目录 `.gitignore`）。不存在时默认视为 `normal`。

## 用法

```bash
cd client

# 只切换 flavor，不构建
./build.sh switch normal
./build.sh switch miranda

# 切换后立即构建
./build.sh miranda apk
./build.sh normal ios -- --release

# 不指定 flavor，用当前已切换的 flavor 构建
./build.sh apk

# 日常开发用 flutter run，同样会带上当前 flavor 的 APP_NAME
./build.sh run -- -d macos
./build.sh miranda run -- -d chrome
```

- `target` 支持：`apk` `appbundle` `ios` `macos` `windows` `linux` `run`
- `run` 之外的 target 走 `flutter build <target>`；`run` 走 `flutter run`
  （不需要 `<target>` 位置参数，设备用 `-- -d <device>` 传）
- `--` 之后的参数原样透传给 `flutter build` / `flutter run`

## 切换是怎么生效的

切换时脚本执行 `apply_flavor <当前flavor> -> <目标flavor>`：

1. 分别读出"当前 flavor"和"目标 flavor"在 `flavors/*.sh` 里声明的字段值。
2. 对每个被脚本接管的原生工程文件（Android/iOS/macOS/Windows/Linux 共
   ~15 个文件），把文件里旧 flavor 的值 `sed` 替换成新 flavor 的值。
3. 把目标 flavor 对应 `ICON_SOURCE_DIR`（如 `assets/miranda_version/`）
   下的 4 个图标文件复制覆盖到 `assets/` 下的同名文件。
4. 执行 `dart run flutter_launcher_icons`，用新图标重新生成各平台的
   图标产物（mipmap、AppIcon.appiconset 等），这一步会完整覆盖旧图标，
   不需要额外重置。
5. 把新 flavor 名写入 `.flavor_current`。

因为是"旧值 -> 新值"的替换，所以两个方向（normal→miranda、
miranda→normal）走的是同一套逻辑，不存在谁是"基准"、谁是"临时覆盖"的
区别。切换是**持久化**的：切到 miranda 之后不会自动变回 normal，除非你
手动 `switch normal`。

## App 内显示的名称（关于页 / 桌面标题栏）

原生工程文件里的 App 名称（Android label、iOS/macOS 展示名、Windows/Linux
窗口标题）由 `apply_flavor` 按上面的逻辑替换，构建后天然就是当前 flavor
的名字。

但 Dart 代码里有几处名称是**独立渲染的文本**，不会因为原生工程文件变了就
自动变：
- 关于页 App 名称：[lib/features/settings/pages/about_page.dart](../lib/features/settings/pages/about_page.dart)
- 桌面端关于面板：[lib/desktop/setting/about_pane.dart](../lib/desktop/setting/about_pane.dart)
- 桌面端标题栏左侧：[lib/desktop/desktop_home_page.dart](../lib/desktop/desktop_home_page.dart) 的 `_TitleBarLeading`

这三处都改用 [lib/main.dart](../lib/main.dart) 里的 `kAppName` 常量：

```dart
const String kAppName = String.fromEnvironment(
  'APP_NAME',
  defaultValue: "Ethan's AI",
);
```

`build.sh` 构建时会追加 `--dart-define=APP_NAME=$APP_NAME`（值取自当前
flavor 的 `APP_NAME` 字段），所以 `kAppName` 在编译期就已经是目标 flavor
的名字，不需要额外的运行时判断或本地化条目。之前这三处用的是写死在 4 份
ARB 文件里的 `aboutPageAppName`（固定值 "Ethan's AI"），已删除该 key，
统一改用 `kAppName`。

**注意**：这只覆盖已经用 `kAppName` 的三处。如果以后新增別的地方要展示
App 名称，直接引用 `kAppName`，不要再写死字符串或新建本地化 key。

## 调试

- 只想看会替换成什么值，不想真的动文件：
  ```bash
  source flavors/miranda.sh && echo "$APP_NAME / $ANDROID_APPLICATION_ID / $BUNDLE_ID"
  ```
- 查看当前处于哪个 flavor：
  ```bash
  cat .flavor_current 2>/dev/null || echo normal
  ```
- 怀疑某次切换没生效干净：直接 `git diff` 对比被接管的文件（见
  `build.sh` 里 `apply_flavor` 函数内 `replace_all` 调用列表），确认字段
  是否已替换为目标 flavor 的值；图标文件可以直接对比 `assets/app_icon*`
  与 `assets/<flavor>_version/` 下同名文件是否一致（`diff` 或 md5）。
- 语法检查：`bash -n build.sh`

## 新增第三个 flavor

1. 在 `flavors/` 下新建 `<name>.sh`，按现有两个文件的字段格式填好。
2. 在 `assets/<name>_version/` 下放好该 flavor 的 4 个图标源文件。
3. `build.sh` 顶部 `PLATFORMS` 和用法说明里的 `flavor: normal | miranda`
   按需更新提示文案（脚本逻辑本身不需要改，是通用的，靠
   `flavors/<name>.sh` 是否存在来校验）。
