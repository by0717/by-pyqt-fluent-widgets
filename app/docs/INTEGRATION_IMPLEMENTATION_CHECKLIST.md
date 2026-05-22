# Test Runner ↔ BasicInput Interface 集成方案 - 实施清单

## 📋 详细修改清单 (不改界面，仅改逻辑)

---

## 修改 #1: CommandExecutor (basic_input_interface.py)

### 位置
文件: `basic_input_interface.py`  
类: `CommandExecutor`  
行号: 约 20-90

### 修改内容

#### 修改 1.1: 修改 `__init__` 方法

**原代码**:
```python
def __init__(self, window_id, config):
    super().__init__()
    self.window_id = window_id
    self.config = config
    self._is_running = True
```

**改为**:
```python
def __init__(self, window_id, config=None, test_ids=None, test_manager=None):
    super().__init__()
    self.window_id = window_id
    self.config = config
    self.test_ids = test_ids              # ✨ 新增
    self.test_manager = test_manager      # ✨ 新增
    self._is_running = True
```

**改动说明**:
- 添加 `config=None` 作为可选参数
- 新增 `test_ids` 参数 (测试ID列表)
- 新增 `test_manager` 参数 (测试管理器实例)

---

#### 修改 1.2: 修改 `run()` 方法

**原代码**:
```python
def run(self):
    """执行命令序列"""
    try:
        self.output_signal.emit(
            self.window_id,
            f"🚀 开始执行配置: {self.config['connection']['host']}")

        # 模拟连接
        self.output_signal.emit(
            self.window_id,
            f"📡 连接到 {self.config['connection']['host']}:{self.config['connection']['port']}"
        )
        time.sleep(1)

        total_commands = len(self.config['commands'])

        for i, cmd in enumerate(self.config['commands']):
            # ... 后续代码 ...
```

**改为**:
```python
def run(self):
    """执行命令序列或测试项目"""
    try:
        # ✨ 新增: 条件分支
        if self.test_ids:
            self._execute_tests()
        else:
            self._execute_config()
    except Exception as e:
        self.output_signal.emit(self.window_id, f"❌ 执行出错: {str(e)}")
        self.finished_signal.emit(self.window_id, False)

# ✨ 新增: 原有逻辑移到这个方法
def _execute_config(self):
    """执行配置命令"""
    try:
        self.output_signal.emit(
            self.window_id,
            f"🚀 开始执行配置: {self.config['connection']['host']}")

        # 模拟连接
        self.output_signal.emit(
            self.window_id,
            f"📡 连接到 {self.config['connection']['host']}:{self.config['connection']['port']}"
        )
        time.sleep(1)

        total_commands = len(self.config['commands'])

        for i, cmd in enumerate(self.config['commands']):
            # ... 原有代码保持不变 ...
```

**改动说明**:
- 将 `run()` 简化为条件分支
- 将原有执行逻辑移到 `_execute_config()` (保持原样)
- 新增调用 `_execute_tests()` 分支

---

#### 修改 1.3: 新增 `_execute_tests()` 方法

**新增代码** (在 `_execute_config()` 之后):
```python
def _execute_tests(self):
    """执行测试项目列表"""
    try:
        total_tests = len(self.test_ids)
        self.output_signal.emit(
            self.window_id,
            f"🚀 开始执行测试项目: 共 {total_tests} 个测试")
        time.sleep(0.5)

        for i, test_id in enumerate(self.test_ids):
            if not self._is_running:
                break

            # 更新进度
            progress = (i) * 100 // total_tests if total_tests > 0 else 0
            self.progress_signal.emit(self.window_id, progress)

            # 获取测试对象
            test_obj = self.test_manager.get_test(test_id)
            if not test_obj:
                self.output_signal.emit(self.window_id, f"❌ 测试不存在: {test_id}")
                continue

            # 执行单个测试
            self.output_signal.emit(
                self.window_id,
                f"\n--- 执行测试 {i+1}/{total_tests} ---")
            self.output_signal.emit(self.window_id, f"测试名称: {test_obj.name}")
            
            # 模拟测试执行 (实际应调用 test_obj.run() 或类似方法)
            time.sleep(2)  # 模拟执行时间
            
            self.output_signal.emit(self.window_id,
                                    f"✅ 测试完成: {test_obj.name}")

        if self._is_running:
            self.progress_signal.emit(self.window_id, 100)
            self.output_signal.emit(self.window_id, "\n🎉 所有测试执行完成")
            self.finished_signal.emit(self.window_id, True)
        else:
            self.finished_signal.emit(self.window_id, False)

    except Exception as e:
        self.output_signal.emit(self.window_id, f"❌ 测试执行出错: {str(e)}")
        self.finished_signal.emit(self.window_id, False)
```

**改动说明**:
- 新增 `_execute_tests()` 方法处理测试执行
- 与 `_execute_config()` 类似的信号发射流程
- 支持进度计算和状态更新

---

## 修改 #2: ExecutionWindow (basic_input_interface.py)

### 位置
文件: `basic_input_interface.py`  
类: `ExecutionWindow`  
行号: 约 92-400

### 修改内容

#### 修改 2.1: 新增 `execute_tests()` 方法

**新增代码** (在 `start_execution()` 方法之后):
```python
def execute_tests(self, test_ids):
    """执行指定的测试项目
    
    参数:
        test_ids (list): 测试ID列表，例如 ['test_001', 'test_002']
    """
    if not test_ids:
        self.append_output("❌ 测试列表为空")
        return

    # 更新UI状态
    self.is_running = True
    self.execute_btn.setText("执行中...")
    self.stop_btn.setEnabled(True)
    self.output_text.clear()
    self.set_status("testing")

    # 初始化计时器
    self.start_time = time.time()
    self.timer.start(1000)

    # 获取 test_manager (从哪里获取?)
    # 方法1: 从父级获取
    test_manager = None
    if self.parent() and self.parent().parent():
        parent_parent = self.parent().parent()
        test_manager = getattr(parent_parent, 'test_manager', None)
    
    # 方法2: 通过执行界面的引用
    # 假设 ExecutionInterface 将 test_manager 作为属性
    # test_manager = self.parent().test_manager (需要确认)
    
    if not test_manager:
        self.append_output("❌ 无法获取测试管理器")
        self.is_running = False
        self.execute_btn.setText("开始执行")
        self.stop_btn.setEnabled(False)
        return

    # 创建执行线程
    self.executor = CommandExecutor(
        self.window_id,
        config=None,              # 不使用配置
        test_ids=test_ids,        # 使用测试ID列表
        test_manager=test_manager # 传入测试管理器
    )

    # 连接信号 (与 start_execution() 完全相同)
    self.executor.output_signal.connect(self.append_output)
    self.executor.progress_signal.connect(self.update_progress)
    self.executor.finished_signal.connect(self.on_execution_finished)

    # 启动执行
    self.executor.start()
```

**改动说明**:
- 新增独立的 `execute_tests()` 方法
- 接收来自 ExecutionInterface 的 test_ids 参数
- 复用现有的信号连接和 UI 更新逻辑
- 与 `start_execution()` 的结构相同，只是参数不同

---

## 修改 #3: ExecutionInterface (basic_input_interface.py)

### 位置
文件: `basic_input_interface.py`  
类: `ExecutionInterface`  
行号: 约 511+

### 修改内容

#### 修改 3.1: 在 `__init__` 中存储 test_manager

**原代码** (在 `__init__` 中):
```python
def __init__(self, parent=None):
    super().__init__(parent)
    self.setObjectName('basicInputInterface')
    self.execution_windows = []
    self.maximized_window = None
    self.window_count = 8  # 默认显示8个窗口

    # 初始化扫描枪管理器
    config_path = self._find_config_path()
    self.scanner_manager = ScannerManager(self, config_path)
    
    # ...
```

**改为**:
```python
def __init__(self, parent=None):
    super().__init__(parent)
    self.setObjectName('basicInputInterface')
    self.execution_windows = []
    self.maximized_window = None
    self.window_count = 8  # 默认显示8个窗口

    # ✨ 新增: 获取并存储 test_manager 引用
    self.test_manager = getattr(parent, 'test_manager', None)

    # 初始化扫描枪管理器
    config_path = self._find_config_path()
    self.scanner_manager = ScannerManager(self, config_path)
    
    # ...
```

**改动说明**:
- 从父级窗口获取 test_manager 引用
- 存储为实例属性便于后续使用

---

#### 修改 3.2: 新增 `receive_tests_from_runner()` 方法

**新增代码** (在类中的任意位置，建议在 `on_scanner_input()` 之后):
```python
def receive_tests_from_runner(self, button_index, test_ids):
    """接收来自 TestRunner 的测试选择
    
    这是 TestRunner 与 BasicInterface 通信的关键接口
    通过信号发送接收参数，然后路由到对应的窗口
    
    参数:
        button_index (int): 窗口索引 (0-7 或 1-8)
        test_ids (list): 测试ID列表，例如 ['test_001', 'test_002']
    """
    # 验证按钮索引
    if not isinstance(button_index, int) or not (0 <= button_index < len(self.execution_windows)):
        print(f"⚠️ 无效的按钮索引: {button_index}")
        return

    # 验证测试ID列表
    if not test_ids or not isinstance(test_ids, list):
        print(f"⚠️ 无效的测试ID列表: {test_ids}")
        return

    # 获取目标窗口
    window = self.execution_windows[button_index]
    if not window:
        print(f"⚠️ 窗口 {button_index} 不存在")
        return

    # 确保窗口可见
    if not window.isVisible():
        print(f"⚠️ 窗口 {button_index} 不可见，无法执行测试")
        return

    # 在 ExecutionWindow 中设置 test_manager (便于后续使用)
    window.test_manager = self.test_manager

    # 调用窗口的执行方法
    window.execute_tests(test_ids)

    # 显示确认信息
    print(f"✅ 按钮 {button_index} 已接收 {len(test_ids)} 个测试项目")
```

**改动说明**:
- 新增 `receive_tests_from_runner()` 作为信号接收端
- 验证参数的有效性
- 路由到对应的 ExecutionWindow
- 调用窗口的 `execute_tests()` 方法

---

## 修改 #4: TestRunnerUI (test_runner_ui.py)

### 位置
文件: `test_runner_ui.py`  
类: `TestRunnerUI`  
行号: 约 1+

### 修改内容

#### 修改 4.1: 新增信号

**原代码** (在类定义之后):
```python
class TestRunnerUI(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.test_manager = TestManager()
        # ...
```

**改为**:
```python
class TestRunnerUI(QWidget):
    # ✨ 新增: 发送测试到执行界面的信号
    tests_sent = Signal(int, list)  # 参数: (button_index, test_ids)
    
    def __init__(self, parent=None):
        super().__init__(parent)
        self.test_manager = TestManager()
        # ...
```

**改动说明**:
- 新增 `tests_sent` 信号
- 参数1: button_index (int) - 窗口索引
- 参数2: test_ids (list) - 测试ID列表

---

#### 修改 4.2: 新增 `send_tests_to_interface()` 方法

**新增代码** (在类中的任意位置，建议在 `stop_all_tests()` 之后):
```python
def send_tests_to_interface(self, button_index):
    """发送选定的测试项目到 BasicInterface 执行
    
    参数:
        button_index (int): 窗口索引 (1-8, 对应 test_sets 的键)
    
    调用方式:
        - 由用户点击"发送到执行界面"按钮触发
        - 或由其他代码调用
    """
    # 验证按钮索引
    if button_index not in self.test_sets:
        print(f"❌ 无效的按钮索引: {button_index}")
        return

    # 获取测试ID列表
    test_ids = self.test_sets[button_index]
    if not test_ids:
        print(f"⚠️ 按钮 {button_index} 没有选择任何测试项目")
        self.global_log_text.append(f"提示: 请先为按钮 {button_index} 选择测试项目")
        return

    # ✨ 发送信号
    self.tests_sent.emit(button_index - 1, test_ids)  # 注意: 索引转换 (1-8 → 0-7)

    # 显示确认信息
    test_names = [
        self.test_manager.get_test(tid).name 
        if self.test_manager.get_test(tid) 
        else tid
        for tid in test_ids
    ]
    message = f"✅ 已向执行界面发送 {len(test_ids)} 个测试项目: {', '.join(test_names)}"
    print(message)
    self.global_log_text.append(message)
```

**改动说明**:
- 新增 `send_tests_to_interface()` 方法
- 从 `test_sets` 中获取对应的测试列表
- 通过信号发送到 ExecutionInterface
- 注意索引转换 (test_sets 使用 1-8, execution_windows 使用 0-7)

---

#### 修改 4.3 (可选): 添加 UI 按钮

如果想在 UI 中添加"发送到执行界面"按钮 (可选，不改变现有界面):

**在 `init_ui()` 方法中**:
```python
# 在每个按钮选择器的选项卡中添加发送按钮
for i in range(1, 9):
    button_selector_tab = QWidget()
    button_selector_layout = QVBoxLayout(button_selector_tab)
    
    # ... 现有代码 ...
    
    # ✨ 新增: 发送按钮
    send_btn = QPushButton(f"发送按钮 {i} 到执行界面")
    send_btn.clicked.connect(lambda checked, idx=i: self.send_tests_to_interface(idx))
    button_selector_layout.addWidget(send_btn)
    
    tab_widget.addTab(button_selector_tab, f"按钮{i}选择器")
```

**改动说明**:
- 可选性改动，仅用于方便用户操作
- 不改变现有界面结构

---

## 修改 #5: 主窗口中的信号连接

### 位置
文件: 应用主窗口文件 (可能是 `gallery.py`, `main_window.py` 等)

### 修改内容

#### 修改 5.1: 在主窗口 `__init__` 中连接信号

**原代码** (假设):
```python
class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        # ... 其他初始化 ...
        
        # 初始化两个界面
        self.test_runner_ui = TestRunnerUI(self)
        self.basic_interface = ExecutionInterface(self)
        
        # ... 其他代码 ...
```

**改为**:
```python
class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        # ... 其他初始化 ...
        
        # 初始化两个界面
        self.test_runner_ui = TestRunnerUI(self)
        self.basic_interface = ExecutionInterface(self)
        
        # ✨ 新增: 连接两个模块间的信号
        self.test_runner_ui.tests_sent.connect(
            self.basic_interface.receive_tests_from_runner
        )
        
        # ... 其他代码 ...
```

**改动说明**:
- 使用 Qt 的信号/槽机制连接两个模块
- 当 TestRunnerUI 发出 `tests_sent` 信号时
- BasicInterface 的 `receive_tests_from_runner` 槽自动被调用

---

## 📊 修改总结表

| 修改 | 文件 | 类 | 改动类型 | 行数估计 |
|------|------|-----|---------|---------|
| 1.1 | basic_input_interface.py | CommandExecutor | 修改 `__init__` | ~5 |
| 1.2 | basic_input_interface.py | CommandExecutor | 修改 `run()` | ~10 |
| 1.3 | basic_input_interface.py | CommandExecutor | 新增 `_execute_tests()` | ~45 |
| 2.1 | basic_input_interface.py | ExecutionWindow | 新增 `execute_tests()` | ~40 |
| 3.1 | basic_input_interface.py | ExecutionInterface | 修改 `__init__` | ~2 |
| 3.2 | basic_input_interface.py | ExecutionInterface | 新增 `receive_tests_from_runner()` | ~25 |
| 4.1 | test_runner_ui.py | TestRunnerUI | 新增信号 | ~1 |
| 4.2 | test_runner_ui.py | TestRunnerUI | 新增 `send_tests_to_interface()` | ~20 |
| 4.3 | test_runner_ui.py | TestRunnerUI | 添加 UI 按钮 (可选) | ~5 |
| 5.1 | 主窗口文件 | MainWindow | 信号连接 | ~3 |
| **总计** | | | | **~156 行** |

> **注**: 实际改动行数可能小于这个估计，因为：
> - 部分代码是复用现有逻辑
> - 可以优化和简化
> - 只计算新增/修改部分

---

## ✅ 验证步骤

### 步骤 1: 编译检查
```bash
# 检查是否有语法错误
python -m py_compile basic_input_interface.py
python -m py_compile test_runner_ui.py
```

### 步骤 2: 运行测试
```bash
# 启动应用
python run_app.py
# 或
python -m gallery
```

### 步骤 3: 功能验证
1. 打开 TestRunnerUI 标签页
2. 在"按钮1选择器"中选择一些测试项目
3. 点击"发送按钮1到执行界面"按钮
4. 切换到 BasicInputInterface 标签页
5. 观察窗口1是否开始执行选定的测试项目
6. 验证日志输出、进度条、状态是否正确

### 步骤 4: 兼容性验证
1. 测试原有的"执行全局配置"功能是否仍然正常
2. 测试多个窗口是否可以并行执行不同的测试

---

## 🎯 预期结果

修改完成后，应该能够：

✅ 在 TestRunnerUI 中选择测试项目  
✅ 通过信号将测试项目发送到 BasicInterface  
✅ BasicInterface 接收后在对应的窗口中执行  
✅ ExecutionWindow 显示执行进度和结果  
✅ 支持 8 个窗口并行执行不同的测试  
✅ 原有的"执行全局配置"功能保持不变  
✅ UI 界面完全不变  
✅ 没有编译或运行时错误  

