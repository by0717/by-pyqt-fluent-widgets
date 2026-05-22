# Test Runner UI 与 Basic Input Interface 集成方案

## 📋 需求分析

### 用户需求
- ✅ 在 `TestRunnerUI` 中选择测试项目
- ✅ 然后在 `BasicInputInterface` 中执行这些选定的测试
- ✅ 不改变 `BasicInputInterface` 的界面外观
- ✅ 支持8个并行窗口，每个窗口可运行不同的测试

### 核心设计原则
1. **解耦设计**: 两个模块通过信号/槽通信，互不直接依赖
2. **无界面改动**: 复用现有的 ExecutionWindow UI 组件
3. **架构兼容**: 与现有的扫描枪集成无缝配合

---

## 🏗️ 当前架构分析

### TestRunnerUI 架构
```
TestRunnerUI (容器)
├── 主选择器标签页
│   └── TestSelector (详情展示)
├── 按钮1-8的选择器标签页
│   └── TestSelector x8 (无详情)
└── 测试执行标签页
    ├── 按钮1-8的控制组
    │   ├── 开始/停止按钮
    │   ├── 进度条
    │   └── 日志显示
    └── 全局日志
```

**核心数据结构**:
```python
self.test_sets = {1-8: [test_id1, test_id2, ...]}  # 每个按钮绑定的测试列表
self.test_executors = {1-8: TestExecutor}  # 每个按钮的执行线程
```

### BasicInputInterface 架构
```
ExecutionInterface (容器)
├── 控制区域
│   ├── 窗口数量选择
│   ├── 全局配置选择
│   └── 扫描枪控制
├── 窗口网格
│   └── ExecutionWindow x8 (每个都是独立执行单元)
│       ├── MAC输入框
│       ├── 开始/停止执行按钮
│       ├── 进度条
│       └── 输出日志
```

**核心数据结构**:
```python
self.execution_windows = [ExecutionWindow x8]  # UI实例
self.windows_layout = QGridLayout  # 8个窗口的布局
self.scanner_manager = ScannerManager  # 扫描枪管理
```

**执行流程**:
```
ExecutionWindow.start_execution()
    ↓
创建 CommandExecutor 线程
    ↓
CommandExecutor.run()
    ├─→ 循环执行 self.config['commands']
    └─→ 发出信号: output_signal, progress_signal, finished_signal
    ↓
ExecutionWindow 收到信号更新UI
```

---

## 🔄 集成方案（分层设计）

### 方案概述：模块间通信流程

```
┌─────────────────────────────────────────────────────────────┐
│                    TestRunnerUI                              │
│                  (测试选择/管理界面)                          │
│                                                              │
│  [按钮1选择] [按钮2选择] ... [按钮8选择]                      │
│  test_sets = {1: [test_id...], 2: [...], ...}              │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ 发送信号: tests_ready(button_index, test_ids)
                     ↓
┌─────────────────────────────────────────────────────────────┐
│              BasicInputInterface                             │
│           (测试执行/显示界面)                                 │
│                                                              │
│  接收信号 → 转换成 ExecutionWindow 的输入参数                 │
│  ExecutionWindow x8 (8个并行执行单元)                         │
│  ├─ Window 1: 执行 test_ids (来自 TestRunner)              │
│  ├─ Window 2: 执行 test_ids (来自 TestRunner)              │
│  └─ ...                                                     │
└─────────────────────────────────────────────────────────────┘
```

### 核心改动点（不动界面，只改逻辑）

#### 1. **CommandExecutor 改造** (基础层)

**现状**:
```python
class CommandExecutor(QThread):
    def __init__(self, window_id, config):
        self.config = config  # config来自 dateTimeInterface
        # 执行流程: 遍历 config['commands']
```

**改造方案**:
```python
class CommandExecutor(QThread):
    def __init__(self, window_id, test_ids=None, config=None):
        # 模式1: 执行测试项目 (来自 TestRunner)
        # test_ids: [test_id1, test_id2, ...]
        
        # 模式2: 执行配置命令 (原有方式)
        # config: dateTimeInterface 的配置
        
        # 优先级: 如果 test_ids 存在，执行测试; 否则执行配置命令
```

**执行逻辑**:
```python
def run(self):
    if self.test_ids:
        self._execute_tests()  # 新: 执行测试项目
    else:
        self._execute_config()  # 原: 执行配置命令
```

#### 2. **ExecutionWindow 改造** (中间层)

**新增接口**:
```python
class ExecutionWindow(QFrame):
    # 原有方法保持不变
    def start_execution(self):  # 保持原样: 执行全局配置
        pass
    
    # 新增方法: 支持执行测试项目
    def execute_tests(self, test_ids):
        """执行指定的测试项目列表
        
        参数:
            test_ids: 测试ID列表 [id1, id2, ...]
        
        调用方: ExecutionInterface 或 外部信号
        """
        # 创建 CommandExecutor，传入 test_ids
        # 更新UI状态
        # 启动执行
```

#### 3. **ExecutionInterface 改造** (上层)

**新增功能**:
```python
class ExecutionInterface(QWidget):
    # 新增信号: 接收来自 TestRunner 的测试选择
    tests_received = Signal(int, list)  # (button_index, test_ids)
    
    def receive_tests_from_runner(self, button_index, test_ids):
        """接收来自 TestRunner 的测试项目
        
        这是 TestRunner 与 BasicInterface 之间的桥接方法
        """
        # 验证按钮索引有效性
        # 获取对应的 ExecutionWindow
        window = self.execution_windows[button_index]
        # 调用 window.execute_tests(test_ids)
```

#### 4. **TestRunnerUI 改造** (信号发送端)

**新增功能**:
```python
class TestRunnerUI(QWidget):
    # 新增信号: 向 BasicInterface 发送测试选择
    send_tests_to_interface = Signal(int, list)  # (button_index, test_ids)
    
    def on_button_selection_changed(self, button_index, selected_tests):
        """用户在选择器中选择测试时"""
        self.test_sets[button_index] = selected_tests
        # 发送信号到 BasicInterface (可选)
        # self.send_tests_to_interface.emit(button_index, selected_tests)
    
    def send_to_interface(self, button_index):
        """用户点击"发送到执行界面"按钮时"""
        test_ids = self.test_sets[button_index]
        # 获取 BasicInterface 引用
        # 调用 interface.receive_tests_from_runner(button_index, test_ids)
```

---

## 📊 详细改动清单

### 第一步: 修改 `CommandExecutor`
**文件**: `basic_input_interface.py`

```python
# 原有: def __init__(self, window_id, config)
# 新增: def __init__(self, window_id, config=None, test_ids=None, test_manager=None)

# 在 run() 方法中添加条件分支:
if self.test_ids:
    self._execute_tests()     # 执行测试模式
else:
    self._execute_config()    # 执行配置模式 (原有逻辑)

# 新增 _execute_tests() 方法:
def _execute_tests(self):
    """执行测试项目"""
    for test_id in self.test_ids:
        test = self.test_manager.get_test(test_id)
        # 从 test 中提取执行步骤
        # 发出 output_signal, progress_signal 等
```

**优点**:
- 复用 CommandExecutor 的信号机制
- 不改变 ExecutionWindow 的 UI 显示逻辑
- 支持混合执行（可以同时支持测试和配置命令）

### 第二步: 修改 `ExecutionWindow`
**文件**: `basic_input_interface.py`

```python
class ExecutionWindow(QFrame):
    def execute_tests(self, test_ids):
        """新增方法: 执行测试项目"""
        # 从哪里获取 test_manager? 
        # 方案1: 作为参数传入
        # 方案2: 从 parent().parent() 获取
        
        # 创建 CommandExecutor 时传入 test_ids
        self.executor = CommandExecutor(
            self.window_id,
            config=None,
            test_ids=test_ids,
            test_manager=test_manager
        )
        
        # 后续逻辑与 start_execution() 完全一致
        # 信号连接、UI状态更新等
```

**注意**:
- 保持原有的 `start_execution()` 方法不变（执行全局配置）
- `execute_tests()` 作为新的执行入口
- UI 界面完全不变

### 第三步: 修改 `ExecutionInterface`
**文件**: `basic_input_interface.py`

```python
class ExecutionInterface(QWidget):
    def __init__(self, parent=None):
        # ... 现有代码 ...
        
        # 新增: 获取 test_manager 引用
        self.test_manager = getattr(parent, 'test_manager', None)
    
    def receive_tests_from_runner(self, button_index, test_ids):
        """接收来自 TestRunner 的测试项目"""
        if not (0 <= button_index < len(self.execution_windows)):
            print(f"❌ 无效的按钮索引: {button_index}")
            return
        
        window = self.execution_windows[button_index]
        # 调用窗口的新方法
        window.execute_tests(test_ids)
```

### 第四步: 修改 `TestRunnerUI`
**文件**: `test_runner_ui.py`

```python
class TestRunnerUI(QWidget):
    # 新增信号
    tests_sent = Signal(int, list)  # (button_index, test_ids)
    
    def __init__(self, parent=None):
        # 保存 parent 引用
        self.main_window = parent
    
    def send_tests_to_window(self, button_index):
        """发送测试到 BasicInterface"""
        test_ids = self.test_sets[button_index]
        
        # 方案1: 通过信号
        self.tests_sent.emit(button_index, test_ids)
        
        # 方案2: 直接调用
        if hasattr(self.main_window, 'basicInputInterface'):
            self.main_window.basicInputInterface.receive_tests_from_runner(
                button_index, test_ids
            )
```

---

## 🔗 集成连接点

### 在主窗口中连接两个模块

**位置**: `main_window.py` 或应用启动代码

```python
class MainWindow(QMainWindow):
    def __init__(self):
        # 初始化两个界面
        self.test_runner_ui = TestRunnerUI(parent=self)
        self.basic_interface = ExecutionInterface(parent=self)
        
        # 方式1: 通过信号连接
        self.test_runner_ui.tests_sent.connect(
            self.basic_interface.receive_tests_from_runner
        )
        
        # 方式2: 保存引用便于直接调用
        self.test_runner_ui.basic_interface = self.basic_interface
```

---

## 🎯 执行流程示例

### 场景: 用户在 TestRunnerUI 中选择测试，然后在 BasicInterface 中执行

**Step 1**: 用户在 TestRunnerUI 的"按钮1选择器"中选择 [test_001, test_002, test_003]
```
TestRunnerUI.on_button_selection_changed(1, [test_001, test_002, test_003])
    └─→ self.test_sets[1] = [test_001, test_002, test_003]
```

**Step 2**: 用户点击"发送到执行界面"按钮（新增按钮）
```
TestRunnerUI.send_tests_to_window(1)
    └─→ self.tests_sent.emit(1, [test_001, test_002, test_003])
```

**Step 3**: 信号连接到 ExecutionInterface
```
BasicInterface.receive_tests_from_runner(1, [test_001, test_002, test_003])
    └─→ window = self.execution_windows[1]
    └─→ window.execute_tests([test_001, test_002, test_003])
```

**Step 4**: ExecutionWindow 执行测试
```
ExecutionWindow.execute_tests([test_001, test_002, test_003])
    └─→ self.executor = CommandExecutor(..., test_ids=[...])
    └─→ self.executor.start()
```

**Step 5**: CommandExecutor 在线程中执行
```
CommandExecutor.run()
    └─→ self._execute_tests()  # 因为 self.test_ids 不为空
        └─→ 循环执行每个测试
        └─→ 发出 output_signal, progress_signal 等
```

**Step 6**: ExecutionWindow 收到信号，更新 UI
```
self.output_text.append(message)  # 显示日志
self.progress_bar.setValue(progress)  # 更新进度条
self.set_status("pass/fail")  # 更新状态
```

---

## 💾 数据流图

```
┌─────────────────────────────────────────────────────────────┐
│ TestRunnerUI                                                │
│ ┌──────────────────────────────────────────────────────────┐│
│ │ test_sets = {                                            ││
│ │   1: [test_001, test_002],                               ││
│ │   2: [test_003],                                          ││
│ │   ...                                                      ││
│ │ }                                                         ││
│ └──────────────────────────────────────────────────────────┘│
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ 信号: tests_sent(button_index=1, test_ids=[...])
                   ↓
┌──────────────────────────────────────────────────────────────┐
│ ExecutionInterface                                           │
│ ┌────────────────────────────────────────────────────────────┐
│ │ receive_tests_from_runner(1, [test_001, test_002])        │
│ │   → execution_windows[1].execute_tests([test_001, ...])   │
│ └────────────────────────────────────────────────────────────┘
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ↓
┌──────────────────────────────────────────────────────────────┐
│ ExecutionWindow[1]                                           │
│ ┌────────────────────────────────────────────────────────────┐
│ │ executor = CommandExecutor(                               │
│ │     window_id=1,                                           │
│ │     test_ids=[test_001, test_002],  ← 关键参数            │
│ │     test_manager=<instance>                               │
│ │ )                                                         │
│ │ executor.start()                                          │
│ └────────────────────────────────────────────────────────────┘
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ↓ (线程中执行)
┌──────────────────────────────────────────────────────────────┐
│ CommandExecutor.run()                                        │
│ ┌────────────────────────────────────────────────────────────┐
│ │ self._execute_tests():                                    │
│ │   for test_id in self.test_ids:                           │
│ │     test_obj = self.test_manager.get_test(test_id)        │
│ │     执行 test_obj 的步骤                                   │
│ │     output_signal.emit(...)  → UI 更新                    │
│ │     progress_signal.emit(...) → 进度条更新                 │
│ └────────────────────────────────────────────────────────────┘
└────────────────────────────────────────────────────────────────┘
```

---

## ✅ 方案优势

| 优势 | 说明 |
|------|------|
| **无界面改动** | ExecutionWindow 的 UI 完全保持不变 |
| **向后兼容** | 原有的"执行全局配置"功能保持不变 |
| **解耦设计** | 两个模块通过信号/槽通信，独立开发 |
| **扩展灵活** | 支持 8 个窗口并行执行不同的测试 |
| **代码最小化** | 只在 4 个地方添加新代码 |
| **可维护性强** | 新增的执行路径清晰独立 |

---

## ⚠️ 需要考虑的问题

1. **test_manager 获取**
   - 从哪里获取 test_manager 实例?
   - 是否需要单例模式?
   - 传递参数还是全局引用?

2. **执行模式切换**
   - 同一个窗口既需要执行全局配置，又需要执行测试项目?
   - 是否存在冲突?
   - 如何处理?

3. **扫描枪集成**
   - 执行测试时，是否需要扫描枪输入?
   - MAC 地址在哪里收集?
   - 与测试执行的关系?

4. **UI 反馈**
   - 测试项目执行的日志格式如何?
   - 与命令执行的日志是否一致?
   - 进度计算方式?

---

## 📌 建议实施顺序

1. **第1阶段**: 修改 CommandExecutor (添加条件分支，支持 test_ids)
2. **第2阶段**: 修改 ExecutionWindow (新增 execute_tests 方法)
3. **第3阶段**: 修改 ExecutionInterface (新增接收方法)
4. **第4阶段**: 修改 TestRunnerUI (新增发送方法)
5. **第5阶段**: 在主窗口中连接两个模块
6. **第6阶段**: 测试验证

---

## 🔍 后续验证清单

- [ ] TestRunnerUI 中选择的测试能正确传递到 ExecutionInterface
- [ ] ExecutionWindow 正确执行接收到的测试项目
- [ ] 测试执行的日志正确显示在输出框
- [ ] 进度条正确更新
- [ ] 多个窗口可以并行执行不同的测试
- [ ] 原有的"执行全局配置"功能仍然正常
- [ ] 扫描枪输入在执行测试时仍然有效
- [ ] 没有内存泄漏或线程问题

