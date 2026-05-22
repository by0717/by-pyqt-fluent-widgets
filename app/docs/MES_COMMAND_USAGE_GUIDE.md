# MES 命令配置使用指南（基于条码）

## 📋 概述

本文档详细说明如何使用 YAML 命令配置文件进行设备测试，特别是**根据条码从 MES 获取数据**并用于命令执行。

---

## 🎯 核心概念

### 1. 命令配置的三个关键功能

根据你的 `by_telnet_test.yaml` 文件，每个命令可以配置：

#### ✅ **基本执行**
```yaml
command: cat /proc/zxic/verdate
expect: '2025-12-17 15:17:49'
judge_type: Contains
```

#### 📦 **变量提取**（从命令响应中提取数据）
```yaml
variable_extraction:
  enabled: true
  variable_name: region_id      # 提取后保存的变量名
  pattern: region_id=(\d+)      # 正则表达式（只写捕获组）
  match_group: 1                # 提取第几个捕获组
```

#### 🔧 **参数化模板**（使用 MES 提供的变量）
```yaml
parameters:
  enabled: true
  template: yotc_test set_ethernet_mac {$Mac}
  variables:
    Mac: ''                     # 运行时从 MES 获取
```

---

## 🔄 完整工作流程（基于条码）

```
┌─────────────────────────────────────────────────────┐
│ 阶段 1: 程序启动时初始化 MES（只需一次）              │
│ - 调用 mes_handler.initialize()                     │
│ - 登录 MES 系统                                      │
│ - 检查工单有效性                                     │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ 阶段 2: 扫描条码                                     │
│ - 操作员扫描产品条码（SN 或 MAC）                     │
│ - 触发测试流程                                       │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ 阶段 3: 根据条码从 MES 获取数据                       │
│ - 调用 mes_handler.process_barcode(barcode)         │
│   1. validate_sn(barcode) - 校验条码                 │
│   2. get_sn_data() - 获取绑定的 MAC、GPON_SN 等     │
│ - MES 返回该条码的产品信息                            │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ 阶段 4: 加载 YAML 命令配置                           │
│ - 读取 by_telnet_test.yaml                          │
│ - 解析所有命令及其扩展配置                            │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ 阶段 5: 构建上下文变量                                │
│ - 从 mes_handler 实例属性获取数据                    │
│ - 构建上下文字典: {"Mac": "AA:BB:CC:DD:EE:FF", ...} │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ 阶段 6: 连接到设备                                    │
│ - Telnet 连接                                        │
│ - 登录认证                                           │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ 阶段 7: 逐条执行命令                                  │
│                                                       │
│ 对于每条命令：                                        │
│   1. 检查条件是否满足                                 │
│   2. 替换模板变量 {$Mac} → 实际值（从 MES 获取）     │
│   3. 发送命令到设备                                   │
│   4. 接收响应                                         │
│   5. 判断是否成功（根据 expect）                      │
│   6. 提取变量（如果启用）                             │
│   7. 将提取的变量保存到上下文                         │
└──────────────────┬──────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────┐
│ 阶段 8: 过站上传（可选）                              │
│ - 调用 mes_handler.pass_station(is_pass)            │
│ - 将测试结果上传到 MES                               │
└─────────────────────────────────────────────────────┘
```

---

## 💡 具体示例解析

### 示例 1：简单的版本检查命令

```yaml
- command_type: Character Command
  command: cat /proc/zxic/verdate
  expect: '2025-12-17 15:17:49'
  end_char: '/ #'
  judge_type: Contains
  match_type: String Match
  variable_extraction:
    enabled: false    # 不需要提取变量
  parameters:
    enabled: false    # 不需要参数化
```

**执行流程：**
1. 发送命令：`cat /proc/zxic/verdate`
2. 等待响应直到出现 `/ #`
3. 检查响应中是否包含 `2025-12-17 15:17:49`
4. 如果包含则成功，否则失败

---

### 示例 2：带变量提取的命令 ⭐

```yaml
- command_type: Character Command
  command: ' yotc_test set_region_id 0'
  expect: region_id=0
  variable_extraction:
    enabled: true
    variable_name: region_id      # 提取后的变量名
    pattern: region_id=(\d+)      # 正则表达式
    match_group: 1                # 提取第1个捕获组
```

**假设设备返回：**
```
/ # yotc_test set_region_id 0
region_id=0
/ #
```

**执行流程：**
1. 发送命令：`yotc_test set_region_id 0`
2. 检查响应中是否包含 `region_id=0` ✓ 成功
3. 使用正则 `region_id=(\d+)` 匹配响应
4. 提取第 1 个捕获组：`0`
5. 保存变量：`context_variables["region_id"] = "0"`
6. **后续命令可以使用这个变量！**

---

### 示例 3：带 MES 模板变量的命令 ⭐⭐⭐

```yaml
- command_type: Character Command
  command: yotc_test set_ethernet_mac {$Mac}
  expect: set_ethernet_mac=ok
  parameters:
    enabled: true
    template: yotc_test set_ethernet_mac {$Mac}
    variables:
      Mac: ''    # 空值表示从上下文获取
```

**执行流程：**
1. **扫描条码**：操作员扫描产品条码
2. **从 MES 获取数据**：
   ```python
   mes_handler.process_barcode("BARCODE123")
   # MES 返回: MAC = "AA:BB:CC:DD:EE:FF"
   ```
3. **替换模板**：`{$Mac}` → `"AA:BB:CC:DD:EE:FF"`
4. **实际发送的命令**：`yotc_test set_ethernet_mac AA:BB:CC:DD:EE:FF`
5. **检查响应**中是否包含 `set_ethernet_mac=ok`

---

## 🔑 关键代码实现

### 1. 程序启动时初始化 MES（只需一次）

```python
from app.core.mes_handler import MESHandler
from app.core.mes_handler_manager import MESHandlerManager
from app.core.mes_config_manager import get_config_manager

# 获取配置
config = get_config_manager(provider_name="XL_BY")

# 创建 MES Handler
mes_handler = MESHandler(config)

# 注册到全局管理器
mes_manager = MESHandlerManager()
mes_manager.register_handler(mes_handler)

# 初始化（登录 + 工单检查）
user_code = config.get("user_code", "")
user_pwd = config.get("user_pwd", "")
mo_code = config.get("mo_code", "")

success, msg = mes_handler.initialize(user_code, user_pwd, mo_code)
if not success:
    print(f"❌ MES 初始化失败: {msg}")
else:
    print(f"✅ MES 初始化成功")
```

### 2. 根据条码从 MES 获取数据

```python
def setup_mes_context_from_barcode(self, barcode: str):
    """根据条码从 MES 获取上下文变量"""
    
    # 获取 MES Handler
    mes_manager = MESHandlerManager()
    mes_handler = mes_manager.get_handler()
    
    # 关键：调用 process_barcode() 从 MES 获取数据
    success, msg = mes_handler.process_barcode(barcode)
    
    if not success:
        logger.error(f"条码处理失败: {msg}")
        return False
    
    # 从 mes_handler 实例属性中获取数据
    # process_barcode() 成功后，这些属性已被填充
    self.mes_context = {
        "Mac": mes_handler.MAC,           # 从 MES 获取的 MAC 地址
        "GponSN": mes_handler.GPON_SN,     # 从 MES 获取的 GPON SN
        "LotId": mes_handler.LotId,        # 批次ID
        "MOId": mes_handler.MOId,          # 工单ID
    }
    
    return True
```

### 3. 执行命令时传入上下文

```python
# 执行命令（关键：传入从 MES 获取的上下文）
results = executor.execute_commands(
    commands=self.commands,
    connection_params=self.mes_context  # ← 这里传入！
)
```

### 4. 命令执行器内部如何处理

在 `CommandExecutor.execute_command()` 方法中：

```python
# 1. 获取扩展后的命令（自动替换 {$Mac}）
expanded_command = cmd.get_expanded_command(self.context_variables)
# 例如: "yotc_test set_ethernet_mac AA:BB:CC:DD:EE:FF"

# 2. 执行命令并获取响应
response = self._execute_on_device(expanded_command, cmd)

# 3. 提取变量（如果启用）
if cmd.variable_extraction.enabled:
    extracted_vars = self._extract_variables(response, cmd.variable_extraction)
    
    # 4. 保存到上下文供后续命令使用
    for var_name, var_value in extracted_vars.items():
        self.context_variables[var_name] = var_value
        logger.info(f"提取变量: {var_name} = {var_value}")
```

### 5. 测试完成后过站（可选）

```python
# 根据测试结果决定是否过站
if result['success']:
    # 测试通过，过站
    success, msg = mes_handler.pass_station(is_pass=True)
else:
    # 测试失败，不过站或标记为 NG
    success, msg = mes_handler.pass_station(is_pass=False)
```

---

## 📝 完整使用示例

```python
from app.tests.test_with_mes_example import DeviceTestWithMES
from app.core.mes_handler_manager import MESHandlerManager
from app.core.mes_handler import MESHandler
from app.core.mes_config_manager import get_config_manager

# =============================
# 步骤 1: 程序启动时初始化 MES（只需一次）
# =============================
config = get_config_manager(provider_name="XL_BY")
mes_handler = MESHandler(config)
mes_manager = MESHandlerManager()
mes_manager.register_handler(mes_handler)

user_code = config.get("user_code", "")
user_pwd = config.get("user_pwd", "")
mo_code = config.get("mo_code", "")

success, msg = mes_handler.initialize(user_code, user_pwd, mo_code)
if not success:
    print(f"❌ MES 初始化失败: {msg}")
    exit(1)

# =============================
# 步骤 2: 扫描条码并执行测试
# =============================
barcode = "SCAN_BARCODE_HERE"  # 从扫描枪获取

test = DeviceTestWithMES("app/configs/commands/by_telnet_test.yaml")
result = test.execute_test_with_barcode(
    barcode=barcode,
    host="192.168.1.1",
    port=26,
    username="root",
    password="yotc"
)

# =============================
# 步骤 3: 检查结果并过站
# =============================
if result['success']:
    print("✅ 测试通过！")
    mes_handler.pass_station(is_pass=True)  # 过站
else:
    print(f"❌ 测试失败: {result.get('error')}")
    mes_handler.pass_station(is_pass=False)  # 标记为 NG
```

---

## ⚠️ 注意事项

### 1. 正则表达式写法
- ✅ **正确**：`region_id=(\d+)` （只写捕获组）
- ❌ **错误**：`.*region_id=(\d+).*` （不要加前后匹配）

### 2. expect 字段用途
- `expect` 用于**判断命令是否成功**
- **不要**在 expect 中填写变量名
- 应该填写标识命令执行的关键词，如 `region_id=0`

### 3. 键名映射
- MES Handler 实例属性：`mes_handler.MAC`, `mes_handler.GPON_SN`
- 命令中使用的键名：`{$Mac}`, `{$GponSN}`
- **需要做映射转换！**

### 4. 初始化时机
- `initialize()` 只需在**程序启动时调用一次**
- `process_barcode()` 在**每个条码测试前调用**
- 避免重复登录 MES 系统

### 5. 变量作用域
- 从 MES 获取的变量：在整个测试过程中可用
- 从命令提取的变量：自动添加到上下文，后续命令可使用

---

## 🎓 进阶用法

### 链式变量提取

```yaml
# 命令 1: 提取 region_id
- command: yotc_test set_region_id 0
  variable_extraction:
    enabled: true
    variable_name: region_id
    pattern: region_id=(\d+)

# 命令 2: 使用提取的 region_id
- command: yotc_test check_region {$region_id}
  parameters:
    enabled: true
    template: yotc_test check_region {$region_id}
```

### 条件执行

```yaml
- command: some_command
  condition:
    enabled: true
    condition_type: variable_equals
    variable_name: region_id
    expected_value: "0"
```

---

## 📚 相关文件

- 命令配置：`app/configs/commands/by_telnet_test.yaml`
- 命令执行器：`app/core/command_executor.py`
- 命令模型：`app/models/command_config.py`
- MES Handler：`app/core/mes_handler.py`
- 测试示例：`app/tests/test_with_mes_example.py`

---

## 🚀 快速开始

1. **准备 YAML 配置文件**
2. **程序启动时初始化 MES**（登录 + 工单检查）
3. **扫描条码并执行测试**（自动从 MES 获取数据）

```python
# 程序启动时
mes_handler.initialize(user_code, user_pwd, mo_code)

# 每个条码测试时
test.execute_test_with_barcode(barcode)
```
