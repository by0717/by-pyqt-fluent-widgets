# 扫描枪功能重构方案

## 现状分析

### ❌ 当前问题
1. **事件处理冲突**
   - `ExecutionWindow.eventFilter()` 捕获MAC输入框事件
   - `ScannerManager.eventFilter()` 也在处理相同事件
   - 导致事件处理流程混乱，可能丢失事件

2. **绑定不完整**
   - `create_windows()` 创建窗口后才绑定MAC输入框到ScannerManager
   - 但`ExecutionWindow.__init__()`中已经安装了自己的eventFilter
   - 两个eventFilter同时工作，优先级不明确

3. **逻辑重复**
   - `ExecutionWindow` 有 `prepare_for_scan()`, `on_mac_entered()`, `on_mac_input_timeout()`
   - `ScannerManager` 和 `ScannerHandler` 也有相同的处理逻辑
   - 代码冗余，难以维护

4. **配置路径问题**
   - `ScannerHandler.__init__()` 中写死了 `"config/scanner_config.yaml"`
   - 如果文件不存在会加载默认配置，但没有日志提示（logging已移除）

5. **焦点管理不够**
   - 跳转后设置焦点，但没有清空输入框
   - 没有高亮显示当前焦点窗口

---

## ✅ 改进方案

### **方案概述**
采用**单一职责原则**：
- `ScannerHandler` - 低层事件处理（键盘输入、缓冲、指令识别）
- `ScannerManager` - 中层协调（事件过滤、信号转发、部件绑定）
- `ExecutionInterface` - 高层应用（窗口跳转、数据填充、UI更新）
- `ExecutionWindow` - 只负责UI显示和数据处理，**不处理扫描枪事件**

---

### **具体修改**

#### **1️⃣ ExecutionWindow - 移除扫描枪事件处理**

**删除以下内容：**
- `eventFilter()` 方法（整个方法删除）
- `prepare_for_scan()` 方法（由ScannerManager处理）
- `on_mac_entered()` 中的扫描逻辑（保留数据处理部分）
- `on_mac_input_timeout()` 方法（由ScannerManager处理）
- 相关的状态变量：`waiting_for_scan`, `mac_input_timer`

**保留：**
- `setup_ui()` - UI布局
- `on_mac_entered()` - 只保留数据验证和处理逻辑
- `set_scan_status()` - 只用于UI状态显示
- `toggle_execution()`, `start_execution()` 等业务逻辑

**改进的 `on_mac_entered()`：**
```python
def on_mac_entered(self):
    """MAC地址输入完成"""
    mac = self.mac_edit.text().strip()
    if mac:
        # 数据验证
        if not self.validate_mac(mac):
            self.show_error("MAC地址格式错误")
            return
        
        # 发出信号给父级处理（可选）
        self.macScanned.emit(self.window_id, mac)
        
        # 更新状态显示
        self.set_scan_status("scanned", f"已扫描: {mac}")
```

---

#### **2️⃣ ScannerManager - 完善绑定和事件处理**

**改进内容：**

```python
class ScannerManager(QObject):
    def __init__(self, parent_widget, config_path=None):
        super().__init__()
        self.parent_widget = parent_widget
        self.input_widgets = {}  # 改为字典：{panel_index: widget}
        self.waiting_widgets = set()  # 当前等待扫描的部件集合
        
        # 创建处理器，支持自定义配置路径
        self.handler = ScannerHandler(parent_widget, config_path)
        
        # 连接信号
        self.handler.jump_to_panel_requested.connect(self._handle_jump)
        self.handler.sn_input_received.connect(self._handle_input)
        
        parent_widget.installEventFilter(self)
    
    def bind_input(self, widget, index):
        """绑定输入部件
        
        Args:
            widget: 输入部件（QLineEdit）
            index: 面板索引（0-based）
        """
        widget.setProperty("panel_index", index)
        self.input_widgets[index] = widget
        # 不要在这里安装eventFilter，由parent的eventFilter处理
        return index
    
    def set_waiting(self, widget_index):
        """标记某个部件正在等待扫描"""
        self.waiting_widgets.add(widget_index)
        widget = self.input_widgets.get(widget_index)
        if widget:
            widget.setProperty("waiting_for_scan", True)
    
    def clear_waiting(self, widget_index):
        """取消等待状态"""
        self.waiting_widgets.discard(widget_index)
        widget = self.input_widgets.get(widget_index)
        if widget:
            widget.setProperty("waiting_for_scan", False)
    
    def _handle_jump(self, panel_index):
        """处理跳转"""
        widget = self.input_widgets.get(panel_index)
        if widget:
            widget.setFocus()
            widget.clear()
            # 标记为等待扫描
            self.set_waiting(panel_index)
            self.jumped.emit(panel_index)
    
    def _handle_input(self, panel_index, value):
        """处理输入"""
        widget = self.input_widgets.get(panel_index)
        if widget:
            widget.setText(value)
            widget.selectAll()
            # 清空等待状态
            self.clear_waiting(panel_index)
            self.input_received.emit(panel_index, value)
```

---

#### **3️⃣ ExecutionInterface - 简化信号处理**

**改进的信号处理：**

```python
def __init__(self, parent=None):
    super().__init__(parent)
    # ...
    
    # 创建ScannerManager（配置路径可配置）
    config_path = self._get_config_path()
    self.scanner_manager = ScannerManager(self, config_path)
    
    # 连接信号
    self.scanner_manager.jumped.connect(self.on_scanner_jump)
    self.scanner_manager.input_received.connect(self.on_scanner_input)
    self.scanner_manager.status_message.connect(self.on_scanner_status)

def _get_config_path(self):
    """获取扫描枪配置文件路径"""
    # 尝试多个位置
    paths = [
        Path("config/scanner_config.yaml"),
        Path("examples/gallery/app/config/scanner_config.yaml"),
        Path(__file__).parent.parent / "config" / "scanner_config.yaml",
    ]
    for p in paths:
        if p.exists():
            return str(p)
    return None  # 使用默认配置

def on_scanner_jump(self, panel_index):
    """处理扫描枪跳转"""
    if 0 <= panel_index < len(self.execution_windows):
        window = self.execution_windows[panel_index]
        if window.isVisible():
            # 窗口已由ScannerManager处理焦点，这里只需要更新UI
            print(f"✅ 已跳转到窗口 {panel_index + 1}，等待扫描...")
        else:
            print(f"⚠️  窗口 {panel_index + 1} 不可见")

def on_scanner_input(self, panel_index, value):
    """处理扫描枪输入"""
    if 0 <= panel_index < len(self.execution_windows):
        window = self.execution_windows[panel_index]
        # MAC地址已由ScannerManager填充
        # 这里可以触发自动测试或其他业务逻辑
        print(f"📌 窗口 {panel_index + 1} 收到: {value}")
        # 可选：自动开始测试
        # if self.config.get('auto_start_test'):
        #     window.start_execution()
```

---

#### **4️⃣ 创建新的配置文件结构**

创建 `config/scanner_config.yaml`：
```yaml
scanner:
  jump_commands:
    "#": [1, 2, 3, 4, 5, 6, 7, 8]
  
  input:
    timeout_ms: 800
    use_enter_as_end: true
    auto_start_test: false
  
  focus:
    remember_last_panel: true
    default_panel: 1
  
  debug:
    enable_logging: false
    log_level: "INFO"
```

---

## 🔄 事件流程（改进后）

```
键盘输入
   ↓
ExecutionInterface.eventFilter()
   ↓
ScannerManager.eventFilter()
   ↓
ScannerHandler.handle_key_event()
   ├→ 检查是否是跳转指令（#1）
   │  └→ 发出 jump_to_panel_requested
   │
   └→ 检查是否是SN输入
      └→ 发出 sn_input_received
   
ScannerManager._handle_jump() / _handle_input()
   ├→ 设置焦点、清空输入框
   ├→ 发出 jumped / input_received 信号
   
ExecutionInterface.on_scanner_jump() / on_scanner_input()
   └→ 更新UI、触发业务逻辑
```

---

## 📝 修改清单

- [ ] 修改 `ExecutionWindow` - 删除eventFilter和扫描逻辑
- [ ] 修改 `ScannerManager` - 完善绑定和状态管理
- [ ] 修改 `ExecutionInterface` - 简化信号处理，添加配置路径处理
- [ ] 创建配置文件 - `config/scanner_config.yaml`
- [ ] 测试事件流程 - 确保跳转和输入正常工作
- [ ] 更新文档注释 - 说明各部分职责

---

## 🎯 预期效果

✅ **代码更清晰** - 各部分职责明确
✅ **事件处理无冲突** - 单一流程处理
✅ **易于维护** - 逻辑集中，不重复
✅ **易于扩展** - 支持多种扫描枪协议
✅ **易于测试** - 每个组件可独立测试

