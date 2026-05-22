# Test Runner ↔ BasicInput Interface 集成方案 - 一页纸总结

## 🎯 核心需求
在 `BasicInputInterface` 中实现从 `TestRunnerUI` 发送的测试选择，**界面不变，逻辑改进**。

---

## 📋 四个改动点 (共 ~90 行代码)

### 1️⃣ CommandExecutor (基础层)
**文件**: `basic_input_interface.py` | **类**: `CommandExecutor` | **改动**: 双模式执行

```python
# 修改 __init__
def __init__(self, window_id, config=None, test_ids=None, test_manager=None):
    self.config = config
    self.test_ids = test_ids      # ✨ 新增
    self.test_manager = test_manager  # ✨ 新增

# 在 run() 中添加条件
def run(self):
    if self.test_ids:
        self._execute_tests()     # ✨ 新分支
    else:
        self._execute_config()    # 原分支

# 新增方法
def _execute_tests(self):
    """执行测试项目"""
    for test_id in self.test_ids:
        test = self.test_manager.get_test(test_id)
        # 执行步骤，发出信号...
```

---

### 2️⃣ ExecutionWindow (窗口层)
**文件**: `basic_input_interface.py` | **类**: `ExecutionWindow` | **改动**: 新增方法

```python
# 新增方法
def execute_tests(self, test_ids):
    """执行指定的测试项目"""
    self.executor = CommandExecutor(
        self.window_id,
        test_ids=test_ids,
        test_manager=self.test_manager
    )
    self.executor.output_signal.connect(self.append_output)
    self.executor.progress_signal.connect(self.update_progress)
    self.executor.finished_signal.connect(self.on_execution_finished)
    
    self.is_running = True
    self.execute_btn.setText("执行中...")
    self.executor.start()
```

---

### 3️⃣ ExecutionInterface (协调层)
**文件**: `basic_input_interface.py` | **类**: `ExecutionInterface` | **改动**: 新增接收方法

```python
# 新增方法
def receive_tests_from_runner(self, button_index, test_ids):
    """接收来自 TestRunner 的测试选择"""
    if not (0 <= button_index < len(self.execution_windows)):
        return
    
    window = self.execution_windows[button_index]
    window.execute_tests(test_ids)
```

---

### 4️⃣ TestRunnerUI (发送层)
**文件**: `test_runner_ui.py` | **类**: `TestRunnerUI` | **改动**: 信号 + 发送方法

```python
# 新增信号
tests_sent = Signal(int, list)  # (button_index, test_ids)

# 新增方法
def send_tests_to_interface(self, button_index):
    """发送选定的测试到执行界面"""
    test_ids = self.test_sets[button_index]
    self.tests_sent.emit(button_index, test_ids)
```

---

## 🔌 集成连接 (在主窗口中)

```python
class MainWindow(QMainWindow):
    def __init__(self):
        self.test_runner = TestRunnerUI(self)
        self.exec_interface = ExecutionInterface(self)
        
        # 连接信号
        self.test_runner.tests_sent.connect(
            self.exec_interface.receive_tests_from_runner
        )
```

---

## 📊 数据流向

```
TestRunnerUI (选择)
    ↓
    用户选择: test_sets[1] = [test_001, test_002]
    ↓
    用户点击 "发送到执行界面"
    ↓
    tests_sent.emit(1, [test_001, test_002])
    ↓ (信号传递)
    ↓
ExecutionInterface.receive_tests_from_runner(1, [test_001, test_002])
    ↓
    execution_windows[1].execute_tests([test_001, test_002])
    ↓
ExecutionWindow (执行)
    ↓
    CommandExecutor(test_ids=[test_001, test_002])
    ↓ (后台线程)
    ↓
    _execute_tests() → 循环执行测试
    ↓
    发出信号: output_signal, progress_signal
    ↓
ExecutionWindow (显示)
    ↓
    更新 UI: 日志 + 进度条 + 状态
    ↓
完成 (结果显示在 BasicInterface 中)
```

---

## ⚡ 执行模式对比

| | 执行全局配置 (原有) | 执行测试项目 (新增) |
|---|---|---|
| **触发方式** | 用户点 "开始执行" | TestRunner 发送信号 |
| **参数** | config 对象 | test_ids 列表 |
| **执行代码** | `_execute_config()` | `_execute_tests()` |
| **UI 界面** | 完全相同 ✓ | 完全相同 ✓ |
| **向后兼容** | 保持不变 ✓ | - |

---

## ✨ 设计特点

| 特点 | 说明 |
|------|------|
| **不改UI** | 复用现有的 ExecutionWindow 组件 |
| **信号驱动** | 遵循 Qt 设计模式 |
| **双模式** | 同一个 CommandExecutor 支持两种执行方式 |
| **后台执行** | 使用 QThread 不阻塞 UI |
| **并行执行** | 8 个窗口可同时执行不同的测试/配置 |
| **代码最小** | 总改动 ~90 行 |

---

## 🎬 实施步骤

```
Step 1: 修改 CommandExecutor (添加条件分支)
Step 2: 修改 ExecutionWindow (新增 execute_tests 方法)
Step 3: 修改 ExecutionInterface (新增接收方法)
Step 4: 修改 TestRunnerUI (新增信号和发送方法)
Step 5: 在主窗口中连接信号
Step 6: 测试验证
```

---

## 📝 关键代码位置

| 改动 | 位置 |
|------|------|
| CommandExecutor 改动 | `basic_input_interface.py` Line ~20-90 |
| ExecutionWindow 改动 | `basic_input_interface.py` Line ~92-250 |
| ExecutionInterface 改动 | `basic_input_interface.py` Line ~511+ |
| TestRunnerUI 改动 | `test_runner_ui.py` Line ~1+ |
| 主窗口连接 | `main_window.py` (或应用启动代码) |

---

## ✅ 验证清单

- [ ] TestRunner 发送信号正常
- [ ] BasicInterface 接收信号正常
- [ ] ExecutionWindow 正确执行测试
- [ ] 日志显示正确
- [ ] 进度条更新正确
- [ ] 多窗口并行不冲突
- [ ] 原有功能不受影响
- [ ] 没有新的错误

---

## 💡 核心优势总结

✅ **界面无改动** → 用户体验连贯  
✅ **代码少** → 改动风险小  
✅ **向后兼容** → 原功能保持  
✅ **松耦合** → 模块独立演进  
✅ **易维护** → 逻辑清晰分离  
✅ **易扩展** → 支持新的执行模式  

