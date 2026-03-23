# 白守 (BaiShou) - Mock 与单元测试规范

本文档定义了白守开发过程中的单元测试规范，特别是**Mock 的编写与使用**。所有的后继开发者在提交涉及网络、数据库或本地存储的代码前，均需要按照此标准编写测试用例。

## 1. 核心理念

我们使用 [mocktail](https://pub.dev/packages/mocktail) 作为唯一的 Mock 框架，摒弃传统的 `mockito`，原因如下：
- **不用生成代码**：没有 `build_runner`，提升测试速度与流畅度。
- **原生空安全**：与 Dart 3.x 完美兼容。
- **语义清晰**：支持直观的 `when()`, `verify()`, `any()`。

## 2. 目录结构

所有测试文件必须保存在项目根目录的 `test/` 文件夹下，且内部结构需要**严格镜像** `lib/` 下的目录层级。

```text
test/
├── mocks/                    # [核心] 全局共享的 Mock 类
│   ├── mock_api_config_service.dart
│   └── mock_ai_client.dart
├── test_helpers/             # [核心] 测试辅助工具集
│   └── database_helpers.dart # 内存数据库工厂、Seed 数据函数等
├── core/                     # 对应 lib/core/
├── features/                 # 对应 lib/features/
└── agent/                    # 对应 lib/agent/
    └── rag/
        └── embedding_migration_test.dart
```

## 3. Mock 编写与组织规范

### 3.1 全局复用
**绝对禁止**在业务测试文件（`xxx_test.dart`）里直接定义 Mock 类。
所有的 Mock 类必须统一声明在 `test/mocks/` 下，文件命名按 `mock_<original_name>.dart` 格式。

*示例 (`test/mocks/mock_api_config_service.dart`):*
```dart
import 'package:mocktail/mocktail.dart';
import 'package:baishou/core/services/api_config_service.dart';

class MockApiConfigService extends Mock implements ApiConfigService {}
```

### 3.2 复杂类型的 Fallback
如果你在 `any()` 或 `captureAny()` 中使用了自定义类型，必须使用 `registerFallbackValue` 注册回退值。这部分注册逻辑可以放到 `test/test_helpers/` 中的统一函数里并在 `setUpAll` 时调用。

## 4. 测试范式：AAA (Arrange, Act, Assert)

我们在编写 `test()` 用例时，强制要求遵循 AAA 范式，并且用**中文**为核心步骤写好结构注释，保持极度清晰。

```dart
test('当用户点击同步时，应该调用同步服务', () async {
  // Arrange（准备）: 配置 Mock 行为
  when(() => mockSyncService.syncData()).thenAnswer((_) async => true);

  // Act（执行）: 调用被测方法
  final result = await controller.triggerSync();

  // Assert（断言）: 验证返回值和执行次数
  expect(result, isTrue);
  verify(() => mockSyncService.syncData()).called(1);
});
```

## 5. 语言与描述规范

- `group()` 的描述使用中文，指明模块或类的行为。
- `test()` 的描述使用中文，并使用 **"应该..."** (Should...) 的句式。
- 测试相关的核心注释必须是中文。
