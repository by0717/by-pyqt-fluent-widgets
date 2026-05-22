# 扫描枪功能重构实现指南

## 📌 快速了解

本次重构采用**分层架构**：

```
┌─────────────────────────────────────┐
│   ExecutionInterface (应用层)        │ ← 显示UI、触发业务逻辑
│   on_scanner_jump()                 │
│   on_scanner_input()                │
└──────────────┬──────────────────────┘
               │ 信号连接
┌──────────────▼──────────────────────┐
│   ScannerManager (协调层)            │ ← 事件转发、部件绑定
│   _handle_jump()                    │
│   _handle_input()                   │
└──────────────┬──────────────────────┘
               │ 事件处理
┌──────────────▼──────────────────────┐
│   ScannerHandler (处理层)            │ ← 键盘识别、指令解析
│   handle_key_event()                │
│   parse_jump_command()              │
└─────────────────────────────────────┘
```

---

## 🔄 工作流程

### 场景1：按下 `#1` 进行跳转

```
1. 用户按下 # 键
   ↓
2. ExecutionInterface.eventFilter() 接收 KeyPress 事件
   ↓
3. ScannerManager.eventFilter() 处理
   └→ 调用 ScannerHandler.handle_key_event()
   ↓
4. ScannerHandler 识别 "#1" 是跳转指令
   └→ 发出 jump_to_panel_requested(0) 信号
   ↓
5. ScannerManager._handle_jump(0) 接收
   ├→ 清空窗口0的mac_edit
   ├→ 设置窗口0的mac_edit焦点
   ├→ 标记窗口0为等待扫描
   └→ 发出 jumped(0) 信号
   ↓
6. ExecutionInterface.on_scanner_jump(0) 接收
   └→ 打印日志 "✅ 已跳转到窗口 1，等待扫描MAC地址..."
   ↓
7. 用户现在可以扫描MAC地址或手动输入
```

### 场景2：扫描MAC地址

```
1. 用户扫描MAC：AA:BB:CC:DD:EE:FF，最后按回车
   ↓
2. 每个字符都被 ScannerHandler 缓冲
   ↓
3. 回车键触发处理
   └→ ScannerHandler 识别不是跳转指令
   └→ 当前焦点在窗口0的mac_edit
   └→ 发出 sn_input_received(0, "AA:BB:CC:DD:EE:FF") 信号
   ↓
4. ScannerManager._handle_input(0, "AA:BB:CC:DD:EE:FF") 接收
   ├→ 获取窗口0的mac_edit
   ├→ 调用 widget.setText("AA:BB:CC:DD:EE:FF")
   ├→ 调用 widget.selectAll() 选中文本
   ├→ 清除窗口0的等待状态
   └→ 发出 input_received(0, "AA:BB:CC:DD:EE:FF") 信号
   ↓
5. ExecutionInterface.on_scanner_input(0, "AA:BB:CC:DD:EE:FF") 接收
   └→ 打印日志 "📌 窗口 1 收到MAC: AA:BB:CC:DD:EE:FF"
   └→ 可选：自动调用 window.start_execution()
```

---

## 🛠️ 关键改动点详解

### 1. ScannerManager 的改进

**旧代码问题**：
```python
self.input_widgets = []  # 列表
widget.installEventFilter(self)  # 为widget安装eventFilter
```

**新代码优势**：
```python
self.input_widgets = {}  # 字典，索引更清晰
self.waiting_widgets = set()  # 追踪等待状态
# 不为widget安装eventFilter，避免冲突
```

**为什么这样做**？
- 字典的 `get()` 方法更安全，自动处理不存在的键
- 等待状态集合便于快速查询
- 单一的eventFilter（parent的）避免事件处理混乱

---

### 2. ExecutionWindow 的简化

**删除的方法**：

```python
# 旧：ExecutionWindow自己处理eventFilter
def eventFilter(self, obj, event):
    if obj is self.mac_edit and event.type() == QEvent.Type.KeyPress:
        # 处理键盘事件...
        return True/False
    return super().eventFilter(obj, event)

# 新：完全删除
# 理由：这样做导致：
#   1. 事件被吃掉，ScannerManager无法处理
#   2. 代码重复，ScannerManager中有相同逻辑
#   3. 难以维护，两个地方处理同一个事件
```

---

### 3. 配置文件的加载

**新增的智能查找**：
```python
def _find_config_path(self):
    """尝试多个位置查找配置文件"""
    paths = [
        Path("config/scanner_config.yaml"),  # 当前工作目录
        Path("examples/gallery/app/config/scanner_config.yaml"),  # 相对路径
        Path(__file__).parent.parent / "config" / "scanner_config.yaml",  # 相对脚本
    ]
    
    for p in paths:
        if p.exists():
            return str(p)
    
    return None  # 找不到时使用默认配置
```

**优势**：
- 自动查找，不用手动指定路径
- 多个候选位置，灵活适应不同的项目结构
- 找不到时优雅降级到默认配置

---

## 📋 修改清单（对应代码行）

### scanner_manager.py

| 行数 | 变化 | 说明 |
|------|------|------|
| 7-18 | 类文档和init签名 | 添加详细说明，config_path参数可选 |
| 27-38 | 初始化逻辑 | 改为字典+集合，支持自定义config_path |
| 51-66 | bind_input()方法 | 不安装widget的eventFilter |
| 76-98 | _handle_jump()方法 | 完善清空、焦点、等待状态处理 |
| 100-120 | _handle_input()方法 | 完善数据填充、选中、等待状态处理 |
| 122-132 | 新增方法 | set_waiting()、clear_waiting() |

### basic_input_interface.py (ExecutionInterface)

| 行数 | 变化 | 说明 |
|------|------|------|
| 586-631 | __init__()方法 | 添加config_path查找逻辑 |
| 633-657 | _find_config_path()方法 | 新增智能查找方法 |
| 801-825 | create_windows()方法 | 改进注释，确保正确绑定 |
| 745-775 | on_scanner_jump()等信号处理 | 简化逻辑，改进日志 |

### basic_input_interface.py (ExecutionWindow)

| 行数 | 变化 | 说明 |
|------|------|------|
| 94-131 | 类定义和__init__() | 删除waiting_for_scan和timer |
| 180-190 | setup_ui()部分 | 删除eventFilter安装 |
| 260-275 | 删除eventFilter()方法 | 整个方法删除 |
| 304-306 | 删除prepare_for_scan()等方法 | 3个扫描相关方法删除 |

### 新增文件

| 文件 | 说明 |
|------|------|
| config/scanner_config.yaml | 扫描枪配置文件 |
| SCANNER_REFACTOR_PLAN.md | 详细改进方案 |
| SCANNER_REFACTOR_SUMMARY.md | 实现总结 |

---

## 🧪 验证改动

### 语法检查 ✅
```bash
✅ scanner_manager.py - 无语法错误
✅ scanner_handler.py - 无语法错误  
✅ basic_input_interface.py - 无语法错误
```

### 导入检查
```python
from .core.scanner_manager import ScannerManager
from .core.scanner_handler import ScannerHandler, ScannerConfig
# 所有导入都应该正常工作
```

### 功能检查清单

- [ ] 能否通过 `#1` 跳转到窗口1
- [ ] 能否通过 `#8` 跳转到窗口8
- [ ] 跳转后输入框是否获得焦点
- [ ] 扫描MAC后是否正确填充到输入框
- [ ] 是否触发了 `input_received` 信号
- [ ] 是否能正确加载配置文件
- [ ] 配置文件不存在时是否能优雅降级

---

## 💡 使用建议

### 启用日志调试
编辑 `config/scanner_config.yaml`：
```yaml
debug:
  enable_logging: true
  log_level: "DEBUG"
```

然后查看控制台输出：
```
[12:34:56.789] [SCANNER] [DEBUG] 检查是否是跳转指令: '#1'
[12:34:56.790] [SCANNER] [DEBUG] 匹配到跳转模式: ^#0?1$
[12:34:56.791] [SCANNER] [INFO] 跳转指令 '#1' -> 面板 1
```

### 自定义配置路径
```python
from core.scanner_manager import ScannerManager

# 方式1：使用默认路径（自动查找）
manager = ScannerManager(parent)

# 方式2：指定自定义路径
manager = ScannerManager(parent, "/my/custom/config.yaml")
```

### 手动绑定输入框
```python
# 在 create_windows() 中已自动完成
# 但如果需要动态添加新窗口：
new_window = ExecutionWindow(8)
self.execution_windows.append(new_window)
self.scanner_manager.bind_input(new_window.mac_edit, 8)
```

---

## 🎯 测试场景

### 测试1：快速跳转
```
1. 连续按 #1, #2, #3, ...
2. 观察焦点是否快速切换
3. 检查输出是否清晰
```

### 测试2：扫描MAC
```
1. 按 #1 跳转到窗口1
2. 扫描条码（模拟：输入AA:BB:CC:DD:EE:FF）
3. 检查MAC是否显示在输入框
4. 检查 on_scanner_input() 是否被调用
```

### 测试3：配置文件
```
1. 修改 timeout_ms 为 200
2. 快速输入几个字符
3. 应立即被处理（不等待回车）
```

### 测试4：边界条件
```
1. 按 #0 或 #9（不存在的窗口）
2. 应打印错误日志，不崩溃
3. 按 #1a（不是有效指令）
4. 应当作普通输入处理
```

---

## ⚠️ 常见问题

**Q: 为什么要删除 ExecutionWindow 的 eventFilter？**
A: 因为它与 ScannerManager 的 eventFilter 冲突，导致事件处理混乱。现在由单一的 ScannerManager 统一处理，更清晰高效。

**Q: MAC输入框的事件去哪里了？**
A: 仍然由 ExecutionInterface 的 eventFilter 处理，然后转发给 ScannerManager。不需要为 MAC 输入框单独安装。

**Q: 为什么要支持多个配置文件位置？**
A: 不同的项目结构可能不同。当前工作目录、项目相对路径、脚本相对路径都是常见位置，自动查找提高了灵活性。

**Q: 如果配置文件加载失败会怎样？**
A: 会使用 ScannerConfig 的默认值。所有配置都有合理的默认值，所以即使没有配置文件也能工作。

**Q: 多窗口时性能如何？**
A: 没有问题。每个窗口只存储在字典中，查询是 O(1) 时间复杂度。事件处理也是高效的。

---

## 📞 后续支持

如果有任何问题或建议，请查看：
- [SCANNER_REFACTOR_PLAN.md](SCANNER_REFACTOR_PLAN.md) - 详细方案
- [SCANNER_REFACTOR_SUMMARY.md](SCANNER_REFACTOR_SUMMARY.md) - 完成总结

**修改时间**: 2026年1月27日  
**修改者**: AI Assistant  
**版本**: 1.0 Final
