# MES 模块使用说明

## 📋 整体架构

```
┌─────────────────────────────────────────────────────────┐
│                    你的项目                              │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌──────────────────┐         ┌──────────────────┐    │
│  │   UI 模块         │         │   测试模块        │    │
│  │  (配置界面)       │         │  (执行测试)       │    │
│  └──────────────────┘         └──────────────────┘    │
│         │                              │               │
│         │ 初始化 MES                    │ 获取 Handler  │
│         │ 注册到全局管理器              │ 处理条码      │
│         │                              │ 过站          │
│         └──────────┬───────────────────┘               │
│                    │                                    │
│         ┌──────────▼──────────┐                        │
│         │  全局管理器         │                        │
│         │  (mes_handler_manager)│                      │
│         └────────────────────┘                        │
└─────────────────────────────────────────────────────────┘
```

## 🎯 核心流程

### 步骤1：UI 模块初始化（只需一次）

**位置**：UI 界面中，用户点击"快速测试"或"完整验证"按钮时

**执行的操作**：
1. 加载配置（从 YAML 文件）
2. 创建 MESHandler 实例
3. 执行 `initialize()`（登录 + 工单检查）
4. **注册到全局管理器**（关键！）

**代码位置**：`mes_config_panel.py` 的 `quick_test()` 方法

```python
# 在 UI 模块中（mes_config_panel.py）
def quick_test(self):
    # 1. 创建 MESHandler
    self.mes_handler = MESHandler(self.config_manager)
    
    # 2. 初始化（登录 + 工单检查）
    success, msg = self.mes_handler.initialize(user_code, user_pwd, mo_code, res_code)
    
    # 3. 注册到全局管理器（关键！）
    if success:
        register_mes_handler(self.mes_handler)  # 👈 注册！
        # 现在其他模块可以获取这个实例了
```

### 步骤2：测试模块调用（可以多次）

**位置**：任何测试模块中

**执行的操作**：
1. 从全局管理器获取已初始化的 MESHandler
2. 处理条码（校验 + 获取数据）
3. 执行测试
4. 过站

**代码示例**：

```python
# 在任何测试模块中
from app.core.mes_handler_manager import get_mes_handler, is_mes_available

def test_barcode(barcode: str):
    # 1. 获取已初始化的实例（无需重新登录）
    mes_handler = get_mes_handler()
    if mes_handler is None:
        print("MES 未初始化，请先在 UI 模块中初始化")
        return False
    
    # 2. 检查是否可用
    if not is_mes_available():
        print("MES 不可用")
        return False
    
    # 3. 处理条码（校验 + 获取数据）
    success, msg = mes_handler.process_barcode(barcode)
    if not success:
        return False
    
    # 4. 获取数据用于测试
    info = mes_handler.get_context_info()
    mac = info['MAC']
    gpon_sn = info['GPON_SN']
    
    # 5. 执行实际测试
    test_result = perform_test(mac, gpon_sn)
    
    # 6. 过站
    mes_handler.pass_station(is_pass=test_result)
    return True
```

## 📝 完整示例

### UI 模块（初始化）

```python
# 文件：app/view/mes_config_panel.py
# 方法：quick_test()

from app.core.mes_handler import MESHandler
from app.core.mes_handler_manager import register_mes_handler

def quick_test(self):
    # 用户点击"快速测试"按钮时执行
    
    # 1. 创建 Handler
    self.mes_handler = MESHandler(self.config_manager)
    
    # 2. 初始化
    user_code = self.user_code_edit.text()
    user_pwd = self.user_pwd_edit.text()
    mo_code = self.mo_code_edit.text()
    
    success, msg = self.mes_handler.initialize(user_code, user_pwd, mo_code)
    
    # 3. 注册（关键！）
    if success:
        register_mes_handler(self.mes_handler)
        # ✅ 现在其他模块可以获取这个实例了
```

### 测试模块（调用）

```python
# 文件：your_test_module.py
# 任何测试模块都可以这样调用

from app.core.mes_handler_manager import get_mes_handler

def test_product(barcode: str):
    """测试产品"""
    
    # 获取已初始化的 Handler（无需重新登录）
    mes_handler = get_mes_handler()
    if mes_handler is None:
        return False
    
    # 处理条码
    success, msg = mes_handler.process_barcode(barcode)
    if not success:
        return False
    
    # 获取数据
    info = mes_handler.get_context_info()
    mac = info['MAC']
    
    # 执行测试
    result = your_test_function(mac)
    
    # 过站
    mes_handler.pass_station(is_pass=result)
    return True
```

## ✅ 关键点

### 1. **UI 模块只需初始化一次**

- 用户在 UI 界面中点击"快速测试"或"完整验证"
- 系统自动执行初始化并注册
- 后续所有测试模块都可以直接使用

### 2. **测试模块直接调用**

- 无需知道 UI 模块在哪里
- 无需重新登录
- 只需调用 `get_mes_handler()` 即可

### 3. **优势**

- ✅ **性能**：避免每个条码都重新登录
- ✅ **解耦**：测试模块和 UI 模块完全解耦
- ✅ **简单**：测试模块只需一行代码获取实例

## 🔄 完整流程图

```
┌─────────────────────────────────────────────────────────┐
│  程序启动                                                │
└─────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────┐
│  UI 模块显示配置界面                                      │
│  - 用户填写：用户、密码、工单号                          │
│  - 用户点击"快速测试"按钮                                │
└─────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────┐
│  UI 模块执行初始化                                        │
│  1. 创建 MESHandler                                      │
│  2. 执行 initialize()（登录 + 工单检查）                │
│  3. 注册到全局管理器 ✅                                   │
└─────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────┐
│  全局管理器保存已初始化的实例                             │
│  _mes_handler = <已初始化的实例>                         │
└─────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────┐
│  测试模块1：处理条码 A                                    │
│  mes_handler = get_mes_handler()  ← 获取实例             │
│  mes_handler.process_barcode("A")                        │
│  mes_handler.pass_station(True)                         │
└─────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────┐
│  测试模块2：处理条码 B                                    │
│  mes_handler = get_mes_handler()  ← 获取同一个实例       │
│  mes_handler.process_barcode("B")                        │
│  mes_handler.pass_station(True)                         │
└─────────────────────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────────────────────┐
│  测试模块N：处理条码 N                                    │
│  mes_handler = get_mes_handler()  ← 还是同一个实例       │
│  mes_handler.process_barcode("N")                        │
│  mes_handler.pass_station(True)                         │
└─────────────────────────────────────────────────────────┘
```

## 💡 常见问题

### Q: UI 模块在哪里初始化？

**A**: 在 `mes_config_panel.py` 的 `quick_test()` 方法中。用户点击"快速测试"按钮时自动执行。

### Q: 测试模块如何知道 MES 已初始化？

**A**: 调用 `get_mes_handler()`，如果返回 `None` 说明未初始化。

### Q: 可以多个测试模块同时使用吗？

**A**: 可以。所有测试模块获取的是同一个实例，线程安全。

### Q: 如果 UI 模块重新初始化会怎样？

**A**: 会覆盖之前的实例，所有测试模块会使用新的实例。

## 📚 相关文件

- `app/core/mes_handler.py` - MESHandler 核心类
- `app/core/mes_handler_manager.py` - 全局管理器
- `app/view/mes_config_panel.py` - UI 配置面板（初始化位置）
- `app/examples/mes_usage_complete.py` - 完整使用示例

