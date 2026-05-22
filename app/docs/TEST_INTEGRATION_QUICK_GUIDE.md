# TestRunner UI 与 BasicInput Interface 集成方案 - 快速概览

## 🎯 核心思路：三层解耦架构

```
选择层 (TestRunnerUI)
   ↓ (发送测试ID列表)
执行层 (ExecutionInterface → ExecutionWindow)
   ↓ (启动测试)
运行层 (CommandExecutor 线程)
```

---

## 📋 四个关键改动点

### 1️⃣ CommandExecutor (线程层 - basic_input_interface.py)

**现状**: 只能执行配置命令
```python
class CommandExecutor(QThread):
    def __init__(self, window_id, config):
        self.config = config  # 只有配置对象
```

**改为**:
```python
class CommandExecutor(QThread):
    def __init__(self, window_id, config=None, test_ids=None, test_manager=None):
        self.config = config           # 配置命令模式
        self.test_ids = test_ids       # 测试项目模式 ✨ 新增
        self.test_manager = test_manager

    def run(self):
        if self.test_ids:
            self._execute_tests()      # ✨ 新增: 执行测试
        else:
            self._execute_config()     # 原有: 执行配置
```

**改动范围**:
- 修改 `__init__` 参数
- 在 `run()` 方法中添加条件判断
- 新增 `_execute_tests()` 方法（核心逻辑）

---

### 2️⃣ ExecutionWindow (UI窗口层 - basic_input_interface.py)

**现状**: 只能执行全局配置
```python
class ExecutionWindow(QFrame):
    def start_execution(self):
        config = <从全局获取>
        executor = CommandExecutor(self.window_id, config)
        executor.start()
```

**改为添加新方法**:
```python
def execute_tests(self, test_ids):  # ✨ 新增方法
    """执行指定的测试项目"""
    # 与 start_execution() 逻辑相似，但参数不同
    executor = CommandExecutor(
        self.window_id,
        config=None,               # 配置为空
        test_ids=test_ids,         # 传入测试ID
        test_manager=self.test_manager
    )
    executor.start()
    # 后续的信号连接、UI更新完全相同
```

**改动范围**:
- 新增一个 `execute_tests()` 方法
- 复用现有的信号处理逻辑
- 保持 `start_execution()` 原样不改

---

### 3️⃣ ExecutionInterface (协调层 - basic_input_interface.py)

**新增接收方法**:
```python
class ExecutionInterface(QWidget):
    def receive_tests_from_runner(self, button_index, test_ids):
        """接收来自 TestRunner 的测试选择"""
        # 验证索引
        if not (0 <= button_index < len(self.execution_windows)):
            return
        
        # 获取对应的窗口
        window = self.execution_windows[button_index]
        
        # 调用窗口的新方法来执行测试
        window.execute_tests(test_ids)
```

**改动范围**:
- 新增一个 `receive_tests_from_runner()` 接收方法
- 作为 TestRunner → BasicInterface 的通信桥接

---

### 4️⃣ TestRunnerUI (选择层 - test_runner_ui.py)

**现状**: 选择测试但无法发送

**改为添加发送方法和信号**:
```python
class TestRunnerUI(QWidget):
    # ✨ 新增信号
    tests_sent = Signal(int, list)  # (button_index, test_ids)
    
    def send_tests_to_interface(self, button_index):
        """发送选定的测试到 BasicInterface"""
        test_ids = self.test_sets[button_index]
        
        # 发射信号
        self.tests_sent.emit(button_index, test_ids)
        
        # 或者直接调用 (如果有引用的话)
        # self.basic_interface.receive_tests_from_runner(button_index, test_ids)
```

**改动范围**:
- 新增一个 `tests_sent` 信号
- 新增一个 `send_tests_to_interface()` 方法
- （可选）添加一个"发送到执行界面"按钮

---

## 🔌 连接方式

### 方式 A: 通过信号连接 (推荐 - 最松耦合)

在主窗口中:
```python
class MainWindow:
    def __init__(self):
        self.test_runner = TestRunnerUI(self)
        self.exec_interface = ExecutionInterface(self)
        
        # 连接信号
        self.test_runner.tests_sent.connect(
            self.exec_interface.receive_tests_from_runner
        )
```

### 方式 B: 直接方法调用 (紧耦合)

在 TestRunnerUI 中:
```python
def send_tests_to_interface(self, button_index):
    self.basic_interface.receive_tests_from_runner(
        button_index, 
        self.test_sets[button_index]
    )
```

---

## 📊 数据流示例

### 场景: 用户选择测试并执行

```
用户操作:
  ↓
  TestRunnerUI 中 Button 1 选择: [test_001, test_002]
  ↓
  用户点击 "发送到执行界面" 按钮
  ↓
  TestRunnerUI.send_tests_to_interface(1)
  ↓
  发出信号: tests_sent.emit(1, [test_001, test_002])
  ↓
  ExecutionInterface.receive_tests_from_runner(1, [test_001, test_002])
  ↓
  execution_windows[1].execute_tests([test_001, test_002])
  ↓
  CommandExecutor 启动线程
  ↓
  for test_id in [test_001, test_002]:
      执行测试 → 发出 output_signal/progress_signal
      ↓
      ExecutionWindow 更新 UI
```

---

## ✨ UI 呈现 (完全不变!)

### ExecutionWindow 界面保持原样:
```
┌─────────────────────────────┐
│  窗口 1                      │
├─────────────────────────────┤
│ MAC: [______输入框______]    │
├─────────────────────────────┤
│ [开始执行] [停止]  进度: 0%   │
├─────────────────────────────┤
│ PASS/FAIL 状态                │
├─────────────────────────────┤
│ 进度条: [==========] 50%      │
├─────────────────────────────┤
│ 日志输出区域                   │
│ ...                         │
│ ...                         │
└─────────────────────────────┘
```

无论是执行"全局配置"还是"测试项目"，UI 界面完全相同！

---

## 🔄 执行模式对比

### 模式 1: 执行全局配置 (原有功能)

```
用户点击 "开始执行"
    ↓
ExecutionWindow.start_execution()
    ↓
从 dateTimeInterface 获取配置
    ↓
CommandExecutor(window_id, config=<cfg>)
    ↓
_execute_config() → 执行 config['commands']
```

### 模式 2: 执行测试项目 (新增功能)

```
TestRunner 发送测试
    ↓
ExecutionInterface.receive_tests_from_runner(button, test_ids)
    ↓
ExecutionWindow.execute_tests(test_ids)  ← 新方法
    ↓
CommandExecutor(window_id, test_ids=<ids>, test_manager=<mgr>)
    ↓
_execute_tests() → 执行每个 test_id 对应的步骤
```

---

## 📝 代码变更总结

| 文件 | 类 | 改动 | 行数 |
|------|-----|------|------|
| basic_input_interface.py | CommandExecutor | 修改 `__init__`、`run()`，新增 `_execute_tests()` | ~40 |
| basic_input_interface.py | ExecutionWindow | 新增 `execute_tests()` 方法 | ~20 |
| basic_input_interface.py | ExecutionInterface | 新增 `receive_tests_from_runner()` 方法 | ~10 |
| test_runner_ui.py | TestRunnerUI | 新增信号、新增 `send_tests_to_interface()` | ~15 |
| main_window.py (假设) | MainWindow | 在 `__init__` 中连接信号 | ~3 |
| **总计** | | | **~88 行代码** |

---

## ⚡ 执行流程优化

### 多窗口并行执行

```
Window 1 执行: [test_001, test_002]  (来自 TestRunner)
Window 2 执行: [test_003, test_004]  (来自 TestRunner)
Window 3 执行: 全局配置              (用户手动点击)
Window 4: 空闲

                ▼ (同时进行)

Window 1: ████████░░ 80%
Window 2: ██░░░░░░░░ 20%
Window 3: ██████████ 100% ✓
Window 4: 就绪
```

---

## ✅ 兼容性检查

| 检查项 | 现状 | 改动后 | 
|--------|------|--------|
| 界面显示 | ✓ 8个窗口并排 | ✓ 完全相同 |
| 执行全局配置 | ✓ 可用 | ✓ 保持不变 |
| 执行测试项目 | ✗ 不支持 | ✓ 新增支持 |
| 扫描枪输入 | ✓ 可用 | ✓ 仍然有效 |
| 多窗口并行 | ✓ 可用 | ✓ 保持不变 |
| 信号/槽机制 | ✓ 使用中 | ✓ 完全兼容 |

---

## 🎬 实施步骤

1. **准备阶段**: 阅读两个模块的代码，理解数据流
2. **实施阶段 1**: 修改 CommandExecutor
3. **实施阶段 2**: 修改 ExecutionWindow
4. **实施阶段 3**: 修改 ExecutionInterface
5. **实施阶段 4**: 修改 TestRunnerUI
6. **集成阶段**: 在主窗口中连接两个模块
7. **测试阶段**: 验证功能正常

---

## 💡 关键设计决策

| 决策 | 原因 |
|------|------|
| 不改UI界面 | 复用现有组件，降低风险 |
| 新增方法而非修改现有 | 保持向后兼容 |
| 使用条件分支在线程中 | 最小化代码改动 |
| 信号/槽通信 | 符合 Qt 设计模式 |
| test_ids 作为参数 | 支持灵活的测试组合 |

