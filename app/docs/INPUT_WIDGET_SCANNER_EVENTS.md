# 输入框扫描事件处理说明

## 📌 功能更新

**新增功能**: 每个输入框（mac_edit）也能接收并处理扫描枪事件

### 工作流程

```
┌─────────────────────────────────────────────────────────┐
│ 用户在任意窗口的输入框中，扫描 #1                        │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ ScannerManager.eventFilter(obj=mac_edit, event)          │
│  ✅ 为每个mac_edit都安装了eventFilter                    │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ ScannerHandler.handle_key_event()                        │
│  识别 "#1" 是跳转指令（优先级最高）                       │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ ScannerManager._handle_jump(0)                           │
│  ✅ 清空输入框                                            │
│  ✅ 设置焦点到窗口1的输入框                               │
│  ✅ 标记为等待扫描状态                                    │
└─────────────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────┐
│ ExecutionInterface.on_scanner_jump()                     │
│  ✅ 打印日志："✅ 已跳转到窗口 1，等待扫描MAC地址..."    │
└─────────────────────────────────────────────────────────┘
```

---

## ✨ 改进点

### 之前的行为
- ❌ 焦点在输入框时，按 #1 会输入 "#1" 到输入框
- ❌ 需要先点击其他地方（如输入框外）才能触发跳转

### 现在的行为
- ✅ 焦点在输入框时，按 #1 直接跳转到窗口1
- ✅ 输入框会被清空并获得焦点
- ✅ 可以立即扫描MAC地址

---

## 🔄 优先级规则

当用户在输入框中进行操作时：

```
优先级1: 跳转指令 (#1-#8)
  └─ 识别为跳转指令 → 立即跳转（清空当前输入框）

优先级2: MAC地址输入
  └─ 不是跳转指令 → 作为MAC地址处理（填充到输入框）

优先级3: 其他输入
  └─ 普通字符输入
```

### 示例

```
场景1: 在窗口1的mac_edit中，用户扫描 #2
  结果: 跳转到窗口2（窗口1的输入框被清空）

场景2: 在窗口1的mac_edit中，用户扫描 AA:BB:CC:DD:EE:FF
  结果: MAC地址填充到窗口1的输入框（因为焦点在窗口1）

场景3: 在窗口1的mac_edit中，用户扫描 #1（同一窗口）
  结果: 跳转到窗口1（清空输入框，准备新的扫描）

场景4: 焦点在窗口1的mac_edit中，按#3后，输入框被清空并焦点转移
  结果: 焦点现在在窗口3的mac_edit，可以立即扫描MAC
```

---

## 🔧 技术实现

### 关键改动

#### 1. ScannerManager.bind_input()
```python
def bind_input(self, widget, index=None):
    """绑定输入部件"""
    # ...
    # ✅ 为输入框也安装eventFilter
    widget.installEventFilter(self)
    # ...
```

**作用**: 确保每个输入框都能接收键盘事件

#### 2. ScannerManager.eventFilter()
```python
def eventFilter(self, obj, event):
    """事件过滤器 - 处理来自parent和输入框的键盘事件"""
    if event.type() == QEvent.Type.KeyPress:
        # 获取当前焦点部件
        focused = self.parent_widget.focusWidget()
        
        # 让扫描枪处理器处理
        processed = self.handler.handle_key_event(event, focused)
        
        if processed:
            # 拦截特殊键 - 防止显示在输入框
            if event.text() == '#':
                return True  # 拦截#字符
            # ...
```

**作用**: 拦截扫描枪事件，防止跳转指令显示在输入框

#### 3. ScannerHandler.handle_key_event()
```python
def handle_key_event(self, event, focused_widget):
    """处理按键事件 - 基于时间间隔的简化版"""
    # ...
    # 识别跳转指令，优先级最高
    if buffer.startswith('#') and len(buffer) in [2, 3]:
        # 发出 jump_to_panel_requested 信号
        self.jump_to_panel_requested.emit(panel_num - 1)
    # ...
```

**作用**: 优先识别跳转指令，无论焦点在哪里

---

## 📋 事件流程详解

### 层级结构
```
ExecutionInterface (parent)
  ├─ 有自己的eventFilter
  │
  └─ ScannerManager
       ├─ parent_widget.installEventFilter(self)  → 为parent安装
       │
       └─ widget.installEventFilter(self)         → 为每个input安装 ✅
              │
              ├─ window1.mac_edit
              ├─ window2.mac_edit
              ├─ ...
              └─ window8.mac_edit
```

### 事件传递路径

当焦点在 `window1.mac_edit` 中，按下 `#2`：

```
1. KeyPress事件发送到 mac_edit
   ↓
2. mac_edit 的 eventFilter 接收
   (由 ScannerManager 安装)
   ↓
3. ScannerManager.eventFilter() 处理
   - 调用 ScannerHandler.handle_key_event()
   - 识别为跳转指令
   - 发出 jump_to_panel_requested(1) 信号
   ↓
4. ScannerManager._handle_jump(1) 处理
   - 清空 window2.mac_edit
   - 设置焦点到 window2.mac_edit
   ↓
5. ExecutionInterface.on_scanner_jump(1) 处理
   - 更新UI、打印日志
```

---

## 🧪 测试场景

### 场景1：在输入框中跳转
```
操作步骤:
  1. 启动应用
  2. 点击窗口1的mac_edit获得焦点
  3. 输入一些字符（或扫描MAC）
  4. 按 #2（或扫描条码 #2）
  
预期结果:
  ✅ 立即跳转到窗口2
  ✅ 窗口2的mac_edit被清空
  ✅ 焦点转移到窗口2的mac_edit
  ✅ 可以立即扫描下一个MAC地址
```

### 场景2：快速跳转
```
操作步骤:
  1. 在窗口1的mac_edit中，按 #2
  2. （焦点自动转到窗口2）
  3. 立即按 #3
  
预期结果:
  ✅ 快速跳转：1 → 2 → 3
  ✅ 无延迟
  ✅ 所有跳转都被正确识别
```

### 场景3：输入和跳转混合
```
操作步骤:
  1. 在窗口1的mac_edit中输入 "AA:BB"
  2. 按 #2 跳转
  3. 在窗口2的mac_edit中输入 "CC:DD:EE:FF"
  
预期结果:
  ✅ 按#时优先级最高，会清空并跳转
  ✅ 跳转不会受到之前的输入影响
  ✅ 各窗口的数据独立
```

---

## ⚙️ 配置相关

在 `config/scanner_config.yaml` 中可以调整：

```yaml
scanner:
  jump_commands:
    "#": [1, 2, 3, 4, 5, 6, 7, 8]  # 定义跳转指令
  
  input:
    timeout_ms: 800                 # 输入超时时间
    use_enter_as_end: true          # 使用回车结束输入
    auto_start_test: false          # 自动开始测试
```

---

## 💡 最佳实践

### ✅ 推荐做法
1. 直接在输入框中按 #1-#8 进行跳转
2. 跳转后立即扫描下一个MAC地址
3. 无需在输入框和其他地方之间切换

### ⚠️ 注意事项
1. 焦点在输入框中时，无法通过输入来添加 "#" 字符（被拦截）
2. 跳转指令总是优先识别（这是设计用途）
3. 长按按键可能被识别为多个事件（扫描枪通常不会这样）

---

## 📝 使用示例

### 场景：快速扫描多个设备

```
工作流程:
  1. 启动应用
  2. 扫描 #1（或按#1） → 跳转到窗口1
  3. 扫描条码 AA:BB:CC:DD:EE:FF → 填充到窗口1
  4. 按开始执行按钮
  
  5. 扫描 #2 → 跳转到窗口2（窗口1的输入框被清空）
  6. 扫描条码 11:22:33:44:55:66 → 填充到窗口2
  7. 按开始执行按钮
  
  8. ... 依此类推 ...
  
  9. 扫描 #1 → 回到窗口1（已清空）
  10. 扫描新条码 → 继续测试

特点:
  ✅ 无需鼠标切换窗口
  ✅ 所有操作都通过扫描枪完成
  ✅ 高效便快捷
```

---

## 🎯 总结

- ✅ **每个输入框都能接收扫描事件**
- ✅ **跳转指令优先级最高**（#1-#8 总是优先识别）
- ✅ **无需手动焦点转移**（跳转后自动设置焦点）
- ✅ **支持快速连续操作**（可快速跳转多个窗口）
- ✅ **保持数据独立**（跳转时清空输入框）

---

**更新日期**: 2026年1月27日  
**版本**: 1.1 (添加输入框事件处理)  
**状态**: ✅ 完成
