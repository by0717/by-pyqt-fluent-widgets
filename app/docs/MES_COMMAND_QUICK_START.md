# 快速开始：使用 YAML 命令配置进行测试（基于条码）

## 📌 核心要点

### 1️⃣ **变量提取** - 从命令响应中提取数据

```yaml
# 在 YAML 中配置
variable_extraction:
  enabled: true
  variable_name: region_id      # 提取后保存的变量名
  pattern: region_id=(\d+)      # 正则表达式（只写捕获组）
  match_group: 1                # 提取第几个捕获组
```

**工作原理：**
- 命令执行后，使用正则表达式匹配响应
- 提取的内容自动保存到 `context_variables`
- 后续命令可以使用这个变量

---

### 2️⃣ **MES 模板变量** - 根据条码从 MES 获取运行时数据

```yaml
# 在 YAML 中配置
parameters:
  enabled: true
  template: yotc_test set_ethernet_mac {$Mac}
  variables:
    Mac: ''    # 空值表示从上下文获取
```

**工作流程：**
```
扫描条码
    ↓
调用 mes_handler.process_barcode(barcode)
    ↓
MES 返回该条码的产品信息
    ↓
mes_handler.MAC = "AA:BB:CC:DD:EE:FF"
mes_handler.GPON_SN = "ZTEG12345678"
    ↓
构建上下文: {"Mac": "AA:BB:...", "GponSN": "ZTEG..."}
    ↓
传入 CommandExecutor.execute_commands()
    ↓
自动替换: {$Mac} → "AA:BB:CC:DD:EE:FF"
    ↓
实际发送: yotc_test set_ethernet_mac AA:BB:CC:DD:EE:FF
```

---

## 🚀 快速使用步骤

### 步骤 1: 程序启动时初始化 MES（只需一次）

```python
from app.core.mes_handler import MESHandler
from app.core.mes_handler_manager import MESHandlerManager
from app.core.mes_config_manager import get_config_manager

# 获取配置
config = get_config_manager(provider_name="XL_BY")

# 创建并注册 MES Handler
mes_handler = MESHandler(config)
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

### 步骤 2: 准备 YAML 配置文件

你的 `by_telnet_test.yaml` 已经准备好了，包含4个命令：
1. 版本检查（无特殊功能）
2. 设置 region_id（带变量提取）
3. 设置 MAC 地址（带 MES 模板变量）⭐
4. 设置 GPON 模式（无特殊功能）

### 步骤 3: 扫描条码并运行测试

```python
from app.tests.test_with_mes_example import DeviceTestWithMES

# 扫描条码（从扫描枪获取）
barcode = "SCAN_BARCODE_HERE"

# 创建测试实例
test = DeviceTestWithMES("app/configs/commands/by_telnet_test.yaml")

# 执行测试（会自动从 MES 获取该条码的数据）
result = test.execute_test_with_barcode(
    barcode=barcode,
    host="192.168.1.1",
    port=26,
    username="root",
    password="yotc"
)

# 检查结果
if result['success']:
    print("✅ 测试通过！")
    print("提取的变量:", result['summary']['extracted_variables'])
    
    # 过站
    mes_handler.pass_station(is_pass=True)
else:
    print("❌ 测试失败")
    mes_handler.pass_station(is_pass=False)
```

---

## 🔍 关键代码解析

### 如何根据条码从 MES 获取数据

```python
def setup_mes_context_from_barcode(self, barcode: str):
    """根据条码从 MES 获取上下文变量"""
    
    # 1. 获取 MES Handler
    mes_manager = MESHandlerManager()
    mes_handler = mes_manager.get_handler()
    
    # 2. 关键：调用 process_barcode() 从 MES 获取数据
    success, msg = mes_handler.process_barcode(barcode)
    
    if not success:
        logger.error(f"条码处理失败: {msg}")
        return False
    
    # 3. 从 mes_handler 实例属性中获取数据
    # process_barcode() 成功后，这些属性已被填充
    self.mes_context = {
        "Mac": mes_handler.MAC,           # 从 MES 获取的 MAC
        "GponSN": mes_handler.GPON_SN,     # 从 MES 获取的 GPON SN
        "LotId": mes_handler.LotId,        # 批次ID
        "MOId": mes_handler.MOId,          # 工单ID
    }
    
    return True
```

### 如何传入上下文

```python
# 执行命令时传入从 MES 获取的上下文
results = executor.execute_commands(
    commands=self.commands,
    connection_params=self.mes_context  # ← 这里！
)
```

### 命令执行器内部处理

```python
# 在 CommandExecutor.execute_command() 中：

# 1. 替换模板变量
expanded_command = cmd.get_expanded_command(self.context_variables)
# "yotc_test set_ethernet_mac {$Mac}" 
# → "yotc_test set_ethernet_mac AA:BB:CC:DD:EE:FF"

# 2. 执行命令
response = self._execute_on_device(expanded_command)

# 3. 提取变量
if cmd.variable_extraction.enabled:
    extracted_vars = self._extract_variables(response, cmd.variable_extraction)
    # 例如: {"region_id": "0"}
    
    # 4. 保存到上下文
    for var_name, var_value in extracted_vars.items():
        self.context_variables[var_name] = var_value
```

---

## ⚠️ 常见错误

### ❌ 错误 1: 忘记初始化 MES

```python
# 错误：直接执行测试，未初始化 MES
test.execute_test_with_barcode(barcode)  # ❌ 会失败

# 正确：先初始化 MES
mes_handler.initialize(user_code, user_pwd, mo_code)  # ✅
test.execute_test_with_barcode(barcode)
```

### ❌ 错误 2: 正则表达式写法错误

```yaml
# 错误：包含了前后匹配
pattern: .*region_id=(\d+).*

# 正确：只写捕获组
pattern: region_id=(\d+)
```

### ❌ 错误 3: expect 填写变量名

```yaml
# 错误
expect: region_id

# 正确：填写标识命令执行的关键词
expect: region_id=0
```

### ❌ 错误 4: 键名不一致

```python
# MES Handler 实例属性
mes_handler.MAC        # 大写
mes_handler.GPON_SN    # 大写+下划线

# 命令中使用的键名
{$Mac}                 # 首字母大写
{$GponSN}              # 驼峰式

# 需要做映射！
self.mes_context = {
    "Mac": mes_handler.MAC,       # MAC → Mac
    "GponSN": mes_handler.GPON_SN, # GPON_SN → GponSN
}
```

---

## 📊 执行流程示例

假设：
- 扫描条码：`"BARCODE123"`
- MES 返回：`MAC = "AA:BB:CC:DD:EE:FF"`, `GPON_SN = "ZTEG12345678"`

```
阶段 1: 程序启动
  🚀 初始化 MES（登录 + 工单检查）
  ✅ 初始化成功

阶段 2: 扫描条码
  📱 扫描: BARCODE123

阶段 3: 从 MES 获取数据
  🔍 process_barcode("BARCODE123")
    1. validate_sn() - 校验条码 ✓
    2. get_sn_data() - 获取数据 ✓
  ✅ 获取成功: MAC=AA:BB:CC:DD:EE:FF, GPON_SN=ZTEG12345678

阶段 4: 执行命令
  命令 1: cat /proc/zxic/verdate
    ✓ 执行成功

  命令 2: yotc_test set_region_id 0
    ✓ 执行成功
    📦 提取变量: region_id = "0"

  命令 3: yotc_test set_ethernet_mac {$Mac}
    🔧 替换变量: {$Mac} → "AA:BB:CC:DD:EE:FF"
    📤 实际发送: yotc_test set_ethernet_mac AA:BB:CC:DD:EE:FF
    ✓ 执行成功

  命令 4: yotc_test set_xponmode combo_gpon
    ✓ 执行成功

阶段 5: 过站
  📤 pass_station(is_pass=True)
  ✅ 过站成功
```

---

## 📚 相关文件

- **测试示例**: [`app/tests/test_with_mes_example.py`](../tests/test_with_mes_example.py)
- **详细指南**: [`app/docs/MES_COMMAND_USAGE_GUIDE.md`](./MES_COMMAND_USAGE_GUIDE.md)
- **命令配置**: [`app/configs/commands/by_telnet_test.yaml`](../configs/commands/by_telnet_test.yaml)
- **命令执行器**: [`app/core/command_executor.py`](../core/command_executor.py)
- **MES Handler**: [`app/core/mes_handler.py`](../core/mes_handler.py)

---

## 💡 提示

1. **初始化时机**: `initialize()` 只需在程序启动时调用一次，避免重复登录
2. **条码处理**: 每个条码测试前调用 `process_barcode()` 从 MES 获取数据
3. **调试技巧**: 查看日志输出，确认变量是否正确获取和替换
4. **变量作用域**: 从 MES 获取的变量在整个测试过程中可用；从命令提取的变量会自动添加到上下文
5. **链式使用**: 可以先从一个命令提取变量，然后在后续命令中使用
6. **过站上传**: 测试完成后记得调用 `pass_station()` 将结果上传到 MES
