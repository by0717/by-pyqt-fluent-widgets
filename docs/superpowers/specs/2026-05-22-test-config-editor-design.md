# Test Config Editor — Design Spec

## Overview

将 `menu_interface.py` 从 QFluentWidgets demo 页面改造为**测试配置编辑器**，用于创建和管理多窗口测试的配置文件（目标IP、仪器、扫描枪等）。在 `basic_input_interface.py` 中导入配置，后台绑定到执行窗口。

## File Changes

| File | Change |
|---|---|
| `app/models/test_config_model.py` | **New** — data model dataclasses |
| `app/view/menu_interface.py` | **Rewrite** — demo → TestConfigEditor |
| `app/view/basic_input_interface.py` | **Small edit** — global config combo loads test configs |
| `app/view/main_window.py` | **No change needed** — nav already maps menuInterface |
| `app/configs/test_configs/` | **New directory** — stores JSON config files |

## Data Model (`app/models/test_config_model.py`)

```python
@dataclass
class Instrument:
    name: str          # e.g. "电源-A"
    address: str       # e.g. "GPIB0::1::INSTR"

@dataclass
class WindowConfig:
    window_id: int                  # 1-8
    target_ip: str = ""
    protocol: str = "Telnet"        # Telnet / SSH / Serial
    port: int = 23
    scanner_port: str = ""          # reserved for per-window scanner
    scanner_timeout_ms: int = 5000  # reserved
    instruments: list[Instrument] = field(default_factory=list)

@dataclass
class TestConfig:
    name: str
    version: str = "1.0"
    windows: list[WindowConfig] = field(default_factory=list)  # fixed 8
```

Supports `to_dict()` / `from_dict()` for JSON serialization. Always writes all 8 windows (unused ones have default empty values).

### JSON Format

```json
{
  "name": "产线A-测试配置1",
  "version": "1.0",
  "windows": [
    {
      "window_id": 1,
      "target_ip": "192.168.1.101",
      "protocol": "Telnet",
      "port": 23,
      "scanner_port": "COM3",
      "scanner_timeout_ms": 5000,
      "instruments": [
        {"name": "电源-A", "address": "GPIB0::1::INSTR"},
        {"name": "万用表-1", "address": "USB0::0x2A8D::1"}
      ]
    }
  ]
}
```

Stored at `app/configs/test_configs/<name>.json`.

## UI Layout (`menu_interface.py`)

Keeps `GalleryInterface` base class. Uses QFluentWidgets components exclusively.

```
┌─ ToolBar: "测试配置" ────────────────────────────────────┐
├─ SimpleCardWidget: 配置管理 ──────────────────────────────┤
│  [新建 PrimaryPushButton] [导入 PushButton] [导出 PushButton]
│  [保存 PushButton] [删除 PushButton]
│  ListWidget: config file list                             │
├─ SimpleCardWidget: 窗口编辑 ──────────────────────────────┤
│  Pivot: [窗口1] [窗口2] ... [窗口8]                        │
│  ┌─ Form ───────────────────────────────────────────┐    │
│  │  LineEdit: 目标IP    ComboBox: 协议    SpinBox: 端口  │
│  │  LineEdit: 扫描枪接口(预留)  SpinBox: 扫描超时(预留)   │
│  │  TableWidget: 仪器列表 (+ 添加仪器 PushButton)        │
│  │    columns: # | 仪器名称(LineEdit) | 地址(LineEdit) | 删除│
│  └──────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────┘
```

**Component mapping (all qfluentwidgets):**

| UI Element | Component |
|---|---|
| Page base | `GalleryInterface` |
| Section cards | `SimpleCardWidget` |
| Config list | `ListWidget` |
| Window tabs | `Pivot` |
| Text inputs | `LineEdit` |
| Number inputs | `SpinBox` |
| Dropdowns | `ComboBox` |
| Instrument table | `TableWidget` |
| Buttons | `PrimaryPushButton` / `PushButton` |
| Labels | `BodyLabel` |

**Interactions:**
- Select config from list → load JSON, populate form for all 8 windows
- Switch Pivot tab → show that window's fields
- Edit any field → mark form dirty (show "*" in title)
- "+ 添加仪器" → insert a new row in TableWidget
- "删除" button on instrument row → remove that row
- "新建" → clear form, prompt for config name
- "保存" → serialize to JSON, write to `app/configs/test_configs/`
- "导入" → file dialog to import an external JSON
- "导出" → file dialog to save copy elsewhere

## basic_input_interface Integration

`ExecutionInterface` changes:

1. `update_global_config_list()` — scan `app/configs/test_configs/*.json` and populate the combo box with config names (parsed from JSON `name` field)
2. New `_load_test_config(config_name)` — read JSON, parse to `TestConfig`, store in `self.test_config`
3. `get_window_config(window_id)` — return `WindowConfig` for the given 1-based window ID
4. `ExecutionWindow.start_execution()` — retrieves `WindowConfig` from parent's `test_config`, passes to `TestExecutor` context:
   ```python
   context = {
       "mes_handler": None,
       "button_index": button_index,
       "window_config": self.execution_interface.get_window_config(self.window_id + 1)
   }
   ```

**No UI changes to execution windows.** Test config is purely backend — windows show test progress/results as before.

## Data Flow

```
menu_interface (edit/save) → JSON files in app/configs/test_configs/
                                        ↓
basic_input_interface (combo select) → TestConfig object
                                        ↓
ExecutionWindow.start_execution() → WindowConfig in TestExecutor context
                                        ↓
CommandExecutor uses config for connection/instrument control
```

## Boundaries

- `test_config_model.py` — pure data, no Qt dependency, no file I/O (just `to_dict`/`from_dict`)
- `menu_interface.py` — UI only: render, edit, validate, read/write JSON files
- `basic_input_interface.py` — consumer: load JSON, map window_id → WindowConfig, inject into executor context
