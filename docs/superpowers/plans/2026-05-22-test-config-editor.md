# Test Config Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `menu_interface.py` from a QFluentWidgets demo into a test configuration editor, with data model, JSON persistence, and backend integration into the execution interface.

**Architecture:** Pure data model (`test_config_model.py`) handles JSON serialization with no Qt dependency. `menu_interface.py` is rewritten as a `GalleryInterface` subclass using QFluentWidgets components (Pivot, TableWidget, ListWidget, etc.) for editing and saving config files. `basic_input_interface.py` loads configs from the new directory and injects per-window config into the executor context — no UI changes to execution windows.

**Tech Stack:** Python dataclasses, PySide6, QFluentWidgets, JSON (std lib)

---

## File Structure

| File | Responsibility |
|---|---|
| `app/models/test_config_model.py` | **New** — `Instrument`, `WindowConfig`, `TestConfig` dataclasses with `to_dict()`/`from_dict()` |
| `app/view/menu_interface.py` | **Rewrite** — `TestConfigEditor(GalleryInterface)`: list, form, save/load |
| `app/view/basic_input_interface.py` | **Edit** — config combo loads from `test_configs/`, injects `WindowConfig` into executor |
| `app/utils/path_utils.py` | **Edit** — add `test_configs_dir` to `Path_Config` |
| `app/configs/test_configs/` | **New directory** — stores `.json` config files |

### Task 1: Add `test_configs_dir` to Path_Config

**Files:**
- Modify: `app/utils/path_utils.py:54` (after `schemas_dir`)

- [ ] **Step 1: Add the directory path**

```python
# In Path_Config class, add after schemas_dir (line 54):
    # 测试配置目录
    test_configs_dir: Path = configs_dir / "test_configs"
```

- [ ] **Step 2: Verify the attribute exists**

Run: `python -c "from app.utils.path_utils import Path_Config; print(Path_Config.test_configs_dir)"`

Expected: prints path ending in `app/configs/test_configs`

- [ ] **Step 3: Commit**

```bash
git add app/utils/path_utils.py
git commit -m "feat: add test_configs_dir to Path_Config"
```

---

### Task 2: Create test config data model

**Files:**
- Create: `app/models/test_config_model.py`

- [ ] **Step 1: Write the model with dataclasses, to_dict, from_dict**

```python
# app/models/test_config_model.py
from dataclasses import dataclass, field
from typing import Any


@dataclass
class Instrument:
    """A single instrument assigned to a test window."""
    name: str = ""           # e.g. "电源-A"
    address: str = ""        # e.g. "GPIB0::1::INSTR"

    def to_dict(self) -> dict[str, str]:
        return {"name": self.name, "address": self.address}

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "Instrument":
        return cls(name=str(d.get("name", "")), address=str(d.get("address", "")))


@dataclass
class WindowConfig:
    """Per-window test configuration (8 windows, window_id 1-8)."""
    window_id: int = 0
    target_ip: str = ""
    protocol: str = "Telnet"
    port: int = 23
    scanner_port: str = ""
    scanner_timeout_ms: int = 5000
    instruments: list[Instrument] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "window_id": self.window_id,
            "target_ip": self.target_ip,
            "protocol": self.protocol,
            "port": self.port,
            "scanner_port": self.scanner_port,
            "scanner_timeout_ms": self.scanner_timeout_ms,
            "instruments": [inst.to_dict() for inst in self.instruments],
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "WindowConfig":
        instruments = [
            Instrument.from_dict(i) for i in d.get("instruments", [])
        ]
        return cls(
            window_id=int(d.get("window_id", 0)),
            target_ip=str(d.get("target_ip", "")),
            protocol=str(d.get("protocol", "Telnet")),
            port=int(d.get("port", 23)),
            scanner_port=str(d.get("scanner_port", "")),
            scanner_timeout_ms=int(d.get("scanner_timeout_ms", 5000)),
            instruments=instruments,
        )


@dataclass
class TestConfig:
    """Top-level test configuration containing 8 WindowConfig entries."""
    name: str = ""
    version: str = "1.0"
    windows: list[WindowConfig] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "version": self.version,
            "windows": [w.to_dict() for w in self.windows],
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> "TestConfig":
        windows = [WindowConfig.from_dict(w) for w in d.get("windows", [])]
        return cls(
            name=str(d.get("name", "")),
            version=str(d.get("version", "1.0")),
            windows=windows,
        )

    @staticmethod
    def create_default(name: str = "") -> "TestConfig":
        """Create a config with 8 empty WindowConfig slots (window_id 1-8)."""
        windows = [WindowConfig(window_id=i) for i in range(1, 9)]
        return TestConfig(name=name, windows=windows)

    def get_window(self, window_id: int) -> WindowConfig | None:
        """Get config for a specific 1-based window ID."""
        for w in self.windows:
            if w.window_id == window_id:
                return w
        return None
```

- [ ] **Step 2: Verify import and basic usage**

Run: `python -c "from app.models.test_config_model import TestConfig; tc = TestConfig.create_default('test'); print(tc.to_dict())"`

Expected: prints dict with 8 windows, each with default values.

- [ ] **Step 3: Verify round-trip serialization**

Run:
```python
python -c "
from app.models.test_config_model import TestConfig
import json
tc = TestConfig.create_default('roundtrip')
tc.windows[0].target_ip = '10.0.0.1'
tc.windows[0].instruments.append(__import__('app.models.test_config_model', fromlist=['Instrument']).Instrument('电源-A', 'GPIB0::1'))
d = tc.to_dict()
j = json.dumps(d)
d2 = json.loads(j)
tc2 = TestConfig.from_dict(d2)
assert tc2.windows[0].target_ip == '10.0.0.1'
assert tc2.windows[0].instruments[0].name == '电源-A'
print('OK')
"
```

Expected: prints `OK`

- [ ] **Step 4: Commit**

```bash
git add app/models/test_config_model.py
git commit -m "feat: add TestConfig, WindowConfig, Instrument data models"
```

---

### Task 3: Create test_configs directory with a sample config

**Files:**
- Create: `app/configs/test_configs/.gitkeep`
- Create: `app/configs/test_configs/example.json`

- [ ] **Step 1: Create directory and sample config**

```bash
bash -c 'mkdir -p "d:/python-workspace/by_gallery/app/configs/test_configs"'
```

Write `app/configs/test_configs/example.json`:

```json
{
  "name": "示例配置",
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
        {"name": "电源-A", "address": "GPIB0::1::INSTR"}
      ]
    },
    {
      "window_id": 2,
      "target_ip": "",
      "protocol": "Telnet",
      "port": 23,
      "scanner_port": "",
      "scanner_timeout_ms": 5000,
      "instruments": []
    },
    {
      "window_id": 3,
      "target_ip": "",
      "protocol": "Telnet",
      "port": 23,
      "scanner_port": "",
      "scanner_timeout_ms": 5000,
      "instruments": []
    },
    {
      "window_id": 4,
      "target_ip": "",
      "protocol": "Telnet",
      "port": 23,
      "scanner_port": "",
      "scanner_timeout_ms": 5000,
      "instruments": []
    },
    {
      "window_id": 5,
      "target_ip": "",
      "protocol": "Telnet",
      "port": 23,
      "scanner_port": "",
      "scanner_timeout_ms": 5000,
      "instruments": []
    },
    {
      "window_id": 6,
      "target_ip": "",
      "protocol": "Telnet",
      "port": 23,
      "scanner_port": "",
      "scanner_timeout_ms": 5000,
      "instruments": []
    },
    {
      "window_id": 7,
      "target_ip": "",
      "protocol": "Telnet",
      "port": 23,
      "scanner_port": "",
      "scanner_timeout_ms": 5000,
      "instruments": []
    },
    {
      "window_id": 8,
      "target_ip": "",
      "protocol": "Telnet",
      "port": 23,
      "scanner_port": "",
      "scanner_timeout_ms": 5000,
      "instruments": []
    }
  ]
}
```

- [ ] **Step 2: Verify it parses correctly**

Run: `python -c "from app.models.test_config_model import TestConfig; import json; tc = TestConfig.from_dict(json.load(open('app/configs/test_configs/example.json'))); print(tc.name, len(tc.windows))"`

Expected: `示例配置 8`

- [ ] **Step 3: Commit**

```bash
git add app/configs/test_configs/
git commit -m "feat: add test_configs directory with example config"
```

---

### Task 4: Rewrite menu_interface.py — class skeleton and config list

**Files:**
- Modify: `app/view/menu_interface.py` (full rewrite)

- [ ] **Step 1: Write the new menu_interface.py — imports, class, setup_ui skeleton, config list**

```python
# coding:utf-8
import json
from pathlib import Path

from PySide6.QtCore import Qt
from PySide6.QtWidgets import QWidget, QVBoxLayout, QHBoxLayout, QFileDialog, QStackedWidget
from qfluentwidgets import (
    BodyLabel, ComboBox, LineEdit, PushButton, PrimaryPushButton,
    SpinBox, TableWidget, SimpleCardWidget, ListWidget, Pivot,
    MessageBox,
)
from qfluentwidgets import FluentIcon as FIF

from .gallery_interface import GalleryInterface
from ..models.test_config_model import TestConfig, WindowConfig, Instrument
from ..utils.path_utils import Path_Config


class TestConfigEditor(GalleryInterface):
    """Test configuration editor — create/edit per-window test configs."""

    def __init__(self, parent=None):
        super().__init__(
            title=self.tr('测试配置'),
            subtitle=self.tr('管理多窗口测试的目标IP、仪器、扫描枪配置'),
            parent=parent,
        )
        self.setObjectName('menuInterface')

        self._current_config: TestConfig | None = None
        self._current_filepath: str | None = None
        self._current_window_index: int = 0  # 0-based index, window 1-8
        self._dirty: bool = False

        self._setup_ui()
        self._refresh_config_list()

    # ── UI setup ──────────────────────────────────────────────

    def _setup_ui(self):
        # Card 1: Config management
        self._mgmt_card = SimpleCardWidget()
        mgmt_layout = QVBoxLayout(self._mgmt_card)

        btn_layout = QHBoxLayout()
        self._btn_new = PrimaryPushButton(FIF.ADD, self.tr('新建'))
        self._btn_import = PushButton(FIF.FOLDER, self.tr('导入'))
        self._btn_export = PushButton(FIF.SAVE, self.tr('导出'))
        self._btn_save = PrimaryPushButton(FIF.SAVE, self.tr('保存'))
        self._btn_delete = PushButton(FIF.DELETE, self.tr('删除'))

        for btn in (self._btn_new, self._btn_import, self._btn_export,
                     self._btn_save, self._btn_delete):
            btn_layout.addWidget(btn)
        btn_layout.addStretch()
        mgmt_layout.addLayout(btn_layout)

        self._config_list = ListWidget()
        self._config_list.itemClicked.connect(self._on_config_selected)
        mgmt_layout.addWidget(self._config_list)

        self._btn_new.clicked.connect(self._on_new)
        self._btn_save.clicked.connect(self._on_save)
        self._btn_delete.clicked.connect(self._on_delete)
        self._btn_import.clicked.connect(self._on_import)
        self._btn_export.clicked.connect(self._on_export)

        self.addExampleCard(
            self.tr('配置管理'),
            self._mgmt_card,
            '',
            stretch=0,
        )

        # Card 2: Window editor (placeholder — filled in Task 5)
        self._editor_card = SimpleCardWidget()
        self._editor_layout = QVBoxLayout(self._editor_card)
        self._editor_layout.setContentsMargins(12, 12, 12, 12)
        self._editor_layout.setSpacing(8)

        self._editor_content = QWidget()
        self._editor_content_layout = QVBoxLayout(self._editor_content)
        self._editor_content_layout.setContentsMargins(0, 0, 0, 0)
        self._editor_content_layout.setSpacing(8)
        self._editor_layout.addWidget(self._editor_content)

        self.addExampleCard(
            self.tr('窗口编辑'),
            self._editor_card,
            '',
            stretch=1,
        )

        # Disable editor until a config is loaded
        self._editor_card.setEnabled(False)

    # ── Config list management ────────────────────────────────

    def _refresh_config_list(self):
        """Reload the config list from the test_configs directory."""
        self._config_list.clear()
        test_configs_dir = Path_Config.test_configs_dir
        test_configs_dir.mkdir(parents=True, exist_ok=True)
        for f in sorted(test_configs_dir.glob("*.json")):
            try:
                with open(f, "r", encoding="utf-8") as fp:
                    data = json.load(fp)
                name = data.get("name", f.stem)
                item_text = name
            except Exception:
                item_text = f.stem
            from PySide6.QtWidgets import QListWidgetItem
            item = QListWidgetItem(item_text)
            item.setData(Qt.ItemDataRole.UserRole, str(f))
            self._config_list.addItem(item)

    def _on_config_selected(self, item):
        filepath = item.data(Qt.ItemDataRole.UserRole)
        self._load_config_from_file(filepath)

    def _load_config_from_file(self, filepath: str):
        with open(filepath, "r", encoding="utf-8") as f:
            data = json.load(f)
        self._current_config = TestConfig.from_dict(data)
        self._current_filepath = filepath
        self._current_window_index = 0
        self._dirty = False
        self._editor_card.setEnabled(True)
        self._populate_form()

    # ── Placeholder methods (filled in later tasks) ───────────

    def _populate_form(self):
        pass  # Task 5

    def _read_form(self):
        pass  # Task 5

    def _on_new(self):
        pass  # Task 6

    def _on_save(self):
        pass  # Task 6

    def _on_delete(self):
        pass  # Task 6

    def _on_import(self):
        pass  # Task 6

    def _on_export(self):
        pass  # Task 6
```

- [ ] **Step 2: Verify the app launches and shows the new page**

Run: `python demo.py` — log in, navigate to "菜单" (menus) tab.

Expected: Page shows two cards — "配置管理" with buttons and an empty list, "窗口编辑" (disabled/greyed out).

- [ ] **Step 3: Verify config list populates**

Create a test file manually if needed. After navigating to the page, the example.json config should appear in the list.

- [ ] **Step 4: Commit**

```bash
git add app/view/menu_interface.py
git commit -m "feat: rewrite menu_interface skeleton with config list"
```

---

### Task 5: Add window editor form (Pivot + fields + instrument table)

**Files:**
- Modify: `app/view/menu_interface.py` — replace `_setup_ui` editor section and placeholder methods

- [ ] **Step 1: Replace the editor card setup in `_setup_ui` and add form methods**

Replace the editor card section in `_setup_ui()` (from the `# Card 2` comment to end of method) and replace all placeholder methods with:

```python
    # ── UI setup (editor card — replace the Card 2 section) ───

        # Card 2: Window editor
        self._editor_card = SimpleCardWidget()
        editor_outer = QVBoxLayout(self._editor_card)
        editor_outer.setContentsMargins(12, 12, 12, 12)
        editor_outer.setSpacing(8)

        # Pivot for 8 window tabs
        self._pivot = Pivot(self)
        for i in range(1, 9):
            idx = i - 1
            self._pivot.addItem(
                routeKey=f"win{i}",
                text=self.tr(f'窗口{i}'),
                onClick=lambda _idx=idx: self._switch_window(_idx),
            )
        editor_outer.addWidget(self._pivot, 0, Qt.AlignmentFlag.AlignLeft)

        # Form area
        form_widget = QWidget()
        form_layout = QVBoxLayout(form_widget)
        form_layout.setContentsMargins(0, 0, 0, 0)
        form_layout.setSpacing(8)

        # Row 1: target IP, protocol, port
        row1 = QHBoxLayout()
        row1.addWidget(BodyLabel(self.tr('目标IP:')))
        self._edit_ip = LineEdit()
        self._edit_ip.setPlaceholderText("192.168.1.101")
        self._edit_ip.textChanged.connect(self._mark_dirty)
        row1.addWidget(self._edit_ip)

        row1.addWidget(BodyLabel(self.tr('协议:')))
        self._combo_protocol = ComboBox()
        self._combo_protocol.addItems(["Telnet", "SSH", "Serial"])
        self._combo_protocol.currentTextChanged.connect(self._mark_dirty)
        row1.addWidget(self._combo_protocol)

        row1.addWidget(BodyLabel(self.tr('端口:')))
        self._spin_port = SpinBox()
        self._spin_port.setRange(1, 65535)
        self._spin_port.setValue(23)
        self._spin_port.valueChanged.connect(self._mark_dirty)
        row1.addWidget(self._spin_port)
        row1.addStretch()
        form_layout.addLayout(row1)

        # Row 2: scanner port, scanner timeout
        row2 = QHBoxLayout()
        row2.addWidget(BodyLabel(self.tr('扫描枪接口(预留):')))
        self._edit_scanner = LineEdit()
        self._edit_scanner.setPlaceholderText("COM3")
        self._edit_scanner.textChanged.connect(self._mark_dirty)
        row2.addWidget(self._edit_scanner)

        row2.addWidget(BodyLabel(self.tr('扫描超时(ms):')))
        self._spin_scanner_timeout = SpinBox()
        self._spin_scanner_timeout.setRange(100, 60000)
        self._spin_scanner_timeout.setValue(5000)
        self._spin_scanner_timeout.setSingleStep(500)
        self._spin_scanner_timeout.valueChanged.connect(self._mark_dirty)
        row2.addWidget(self._spin_scanner_timeout)
        row2.addStretch()
        form_layout.addLayout(row2)

        # Row 3: Instrument table header
        row3 = QHBoxLayout()
        row3.addWidget(BodyLabel(self.tr('选用仪器:')))
        btn_add_inst = PushButton(FIF.ADD, self.tr('添加仪器'))
        btn_add_inst.clicked.connect(self._add_instrument)
        row3.addWidget(btn_add_inst)
        row3.addStretch()
        form_layout.addLayout(row3)

        # Instrument table
        self._inst_table = TableWidget()
        self._inst_table.setColumnCount(4)
        self._inst_table.setHorizontalHeaderLabels([
            self.tr('#'), self.tr('仪器名称'), self.tr('型号/地址'), self.tr('操作')
        ])
        self._inst_table.horizontalHeader().setStretchLastSection(True)
        form_layout.addWidget(self._inst_table)

        editor_outer.addWidget(form_widget)
        self.addExampleCard(self.tr('窗口编辑'), self._editor_card, '', stretch=1)
        self._editor_card.setEnabled(False)

    # ── Form population ───────────────────────────────────────

    def _switch_window(self, index: int):
        """Save current form to model, then switch to window at index (0-based)."""
        if self._current_config is not None:
            self._read_form()
        self._current_window_index = index
        self._pivot.setCurrentItem(f"win{index + 1}")
        if self._current_config is not None:
            self._populate_form()

    def _populate_form(self):
        """Fill form from current window config."""
        wc = self._current_config.windows[self._current_window_index]
        self._edit_ip.blockSignals(True)
        self._edit_ip.setText(wc.target_ip)
        self._edit_ip.blockSignals(False)

        self._combo_protocol.blockSignals(True)
        self._combo_protocol.setCurrentText(wc.protocol)
        self._combo_protocol.blockSignals(False)

        self._spin_port.blockSignals(True)
        self._spin_port.setValue(wc.port)
        self._spin_port.blockSignals(False)

        self._edit_scanner.blockSignals(True)
        self._edit_scanner.setText(wc.scanner_port)
        self._edit_scanner.blockSignals(False)

        self._spin_scanner_timeout.blockSignals(True)
        self._spin_scanner_timeout.setValue(wc.scanner_timeout_ms)
        self._spin_scanner_timeout.blockSignals(False)

        self._populate_instrument_table()

    def _read_form(self):
        """Read current form values into current window config."""
        wc = self._current_config.windows[self._current_window_index]
        wc.target_ip = self._edit_ip.text().strip()
        wc.protocol = self._combo_protocol.currentText()
        wc.port = self._spin_port.value()
        wc.scanner_port = self._edit_scanner.text().strip()
        wc.scanner_timeout_ms = self._spin_scanner_timeout.value()
        self._read_instrument_table()

    def _mark_dirty(self, *_):
        self._dirty = True

    # ── Instrument table ──────────────────────────────────────

    def _populate_instrument_table(self):
        wc = self._current_config.windows[self._current_window_index]
        table = self._inst_table
        table.setRowCount(0)
        for i, inst in enumerate(wc.instruments):
            table.setRowCount(table.rowCount() + 1)
            row = table.rowCount() - 1

            # Column 0: #
            from PySide6.QtWidgets import QTableWidgetItem
            num_item = QTableWidgetItem(str(i + 1))
            num_item.setFlags(num_item.flags() & ~Qt.ItemFlag.ItemIsEditable)
            table.setItem(row, 0, num_item)

            # Column 1: name (editable via cell widget)
            name_edit = LineEdit()
            name_edit.setText(inst.name)
            name_edit.textChanged.connect(self._mark_dirty)
            name_edit.textChanged.connect(
                lambda text, r=row: self._on_instrument_cell_changed(r, 1, text)
            )
            table.setCellWidget(row, 1, name_edit)

            # Column 2: address (editable via cell widget)
            addr_edit = LineEdit()
            addr_edit.setText(inst.address)
            addr_edit.textChanged.connect(self._mark_dirty)
            addr_edit.textChanged.connect(
                lambda text, r=row: self._on_instrument_cell_changed(r, 2, text)
            )
            table.setCellWidget(row, 2, addr_edit)

            # Column 3: delete button
            del_widget = QWidget()
            del_layout = QHBoxLayout(del_widget)
            del_layout.setContentsMargins(2, 2, 2, 2)
            del_btn = PushButton(FIF.DELETE, '')
            del_btn.setFixedSize(28, 28)
            del_btn.clicked.connect(lambda _checked, r=row: self._delete_instrument(r))
            del_layout.addWidget(del_btn)
            table.setCellWidget(row, 3, del_widget)

        table.resizeColumnsToContents()

    def _on_instrument_cell_changed(self, row: int, col: int, text: str):
        """Update the instrument model when a cell widget text changes."""
        wc = self._current_config.windows[self._current_window_index]
        if row < len(wc.instruments):
            if col == 1:
                wc.instruments[row].name = text
            elif col == 2:
                wc.instruments[row].address = text

    def _read_instrument_table(self):
        """Sync all instrument table cell widgets back to the model."""
        wc = self._current_config.windows[self._current_window_index]
        for row in range(self._inst_table.rowCount()):
            if row < len(wc.instruments):
                name_widget = self._inst_table.cellWidget(row, 1)
                if isinstance(name_widget, LineEdit):
                    wc.instruments[row].name = name_widget.text()
                addr_widget = self._inst_table.cellWidget(row, 2)
                if isinstance(addr_widget, LineEdit):
                    wc.instruments[row].address = addr_widget.text()

    def _add_instrument(self):
        if self._current_config is None:
            return
        wc = self._current_config.windows[self._current_window_index]
        wc.instruments.append(Instrument())
        self._dirty = True
        self._populate_instrument_table()

    def _delete_instrument(self, row: int):
        if self._current_config is None:
            return
        wc = self._current_config.windows[self._current_window_index]
        if row < len(wc.instruments):
            wc.instruments.pop(row)
            self._dirty = True
            self._populate_instrument_table()
```

- [ ] **Step 2: Verify the app launches and the editor works**

Run: `python demo.py` — log in, go to "菜单" tab, click "示例配置" in the list.

Expected:
- Editor card enables
- Pivot shows 8 window tabs
- Window 1 shows IP "192.168.1.101", protocol "Telnet", port 23, scanner "COM3", and the instrument table with "电源-A"
- Switching tabs shows other windows (mostly empty)
- Editing a field marks form dirty
- Adding/deleting instruments works

- [ ] **Step 3: Commit**

```bash
git add app/view/menu_interface.py
git commit -m "feat: add window editor form with Pivot, fields, and instrument table"
```

---

### Task 6: Wire save/load/new/delete/import/export

**Files:**
- Modify: `app/view/menu_interface.py` — replace placeholder methods with real implementations

- [ ] **Step 1: Replace the placeholder action methods with real ones**

Replace `_on_new`, `_on_save`, `_on_delete`, `_on_import`, `_on_export` stubs:

```python
    # ── Config actions ────────────────────────────────────────

    def _on_new(self):
        self._prompt_save_if_dirty()
        name = self._prompt_config_name()
        if not name:
            return
        self._current_config = TestConfig.create_default(name)
        self._current_filepath = None
        self._current_window_index = 0
        self._dirty = True
        self._editor_card.setEnabled(True)
        self._pivot.setCurrentItem("win1")
        self._populate_form()

    def _on_save(self):
        if self._current_config is None:
            return
        self._read_form()
        if not self._current_config.name.strip():
            name = self._prompt_config_name()
            if not name:
                return
            self._current_config.name = name

        test_configs_dir = Path_Config.test_configs_dir
        test_configs_dir.mkdir(parents=True, exist_ok=True)
        safe_name = "".join(
            c for c in self._current_config.name if c.isalnum() or c in "._- "
        ).strip()
        if not safe_name:
            safe_name = "config"
        filepath = test_configs_dir / f"{safe_name}.json"

        data = self._current_config.to_dict()
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

        self._current_filepath = str(filepath)
        self._dirty = False
        self._refresh_config_list()
        MessageBox(
            self.tr('保存成功'),
            self.tr(f'配置已保存到 {safe_name}.json'),
            self,
        ).exec()

    def _on_delete(self):
        if self._current_config is None:
            return
        if self._current_filepath is None:
            return
        msg = MessageBox(
            self.tr('确认删除'),
            self.tr(f'确定要删除配置 "{self._current_config.name}" 吗？'),
            self,
        )
        msg.yesButton.setText(self.tr('删除'))
        msg.cancelButton.setText(self.tr('取消'))
        if msg.exec():
            Path(self._current_filepath).unlink(missing_ok=True)
            self._current_config = None
            self._current_filepath = None
            self._current_window_index = 0
            self._dirty = False
            self._editor_card.setEnabled(False)
            self._refresh_config_list()

    def _on_import(self):
        filepath, _ = QFileDialog.getOpenFileName(
            self,
            self.tr('导入测试配置'),
            str(Path_Config.test_configs_dir),
            'JSON 文件 (*.json)',
        )
        if not filepath:
            return
        self._load_config_from_file(filepath)
        self._refresh_config_list()

    def _on_export(self):
        if self._current_config is None:
            return
        self._read_form()
        filepath, _ = QFileDialog.getSaveFileName(
            self,
            self.tr('导出测试配置'),
            f"{self._current_config.name}.json",
            'JSON 文件 (*.json)',
        )
        if not filepath:
            return
        data = self._current_config.to_dict()
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)

    def _prompt_config_name(self) -> str | None:
        """Prompt user for a config name via a simple input dialog."""
        from PySide6.QtWidgets import QInputDialog
        name, ok = QInputDialog.getText(
            self,
            self.tr('配置名称'),
            self.tr('请输入配置名称:'),
        )
        if ok and name.strip():
            return name.strip()
        return None
```

- [ ] **Step 2: Verify save and load work end-to-end**

Run: `python demo.py`

Manual test:
1. Navigate to "菜单" tab
2. Click "新建" → enter name "测试"
3. Fill Window 1: IP=10.0.0.1, protocol=SSH, port=22, scanner=COM1, add one instrument
4. Click "保存" → should show success message
5. Close and reopen the app → "测试" should appear in list, click to verify data persisted
6. Click "删除" → confirm → config removed from list and disk

- [ ] **Step 3: Commit**

```bash
git add app/view/menu_interface.py
git commit -m "feat: wire save/load/new/delete/import/export for test configs"
```

---

### Task 7: Integrate test config into basic_input_interface

**Files:**
- Modify: `app/view/basic_input_interface.py` — lines 556-558 (add test_config attr), 657-660 (combo), 1090-1101 (update method), 358-415 (start_execution)

- [ ] **Step 1: Add test_config attribute to ExecutionInterface.__init__**

In `ExecutionInterface.__init__`, after `self.window_count = 8` (line 555), add:

```python
        self.test_config: TestConfig | None = None  # loaded test config
```

Also add the import at top:

```python
from ..models.test_config_model import TestConfig
```

- [ ] **Step 2: Rewrite `update_global_config_list` to load from test_configs directory**

Replace `update_global_config_list()` (lines 1090-1101):

```python
    def update_global_config_list(self):
        """Update global config combo with test config files."""
        self.global_config_combo.clear()
        self.global_config_combo.addItem("选择配置...")

        test_configs_dir = Path_Config.test_configs_dir
        test_configs_dir.mkdir(parents=True, exist_ok=True)
        for f in sorted(test_configs_dir.glob("*.json")):
            self.global_config_combo.addItem(f.stem)
```

Connect the combo signal. Add in `setup_ui()` after line 658:

```python
        self.global_config_combo.currentTextChanged.connect(
            self._on_global_config_changed)
```

Add the handler method to `ExecutionInterface`:

```python
    def _on_global_config_changed(self, text: str):
        """Handle global config combo selection — load the test config."""
        if text == "选择配置..." or not text:
            self.test_config = None
            return

        filepath = Path_Config.test_configs_dir / f"{text}.json"
        if not filepath.exists():
            self.test_config = None
            return

        try:
            with open(filepath, "r", encoding="utf-8") as f:
                data = json.load(f)
            self.test_config = TestConfig.from_dict(data)
            logger.info(f"✅ 已加载测试配置: {self.test_config.name}")
        except Exception as e:
            logger.error(f"❌ 加载测试配置失败: {e}")
            self.test_config = None
```

- [ ] **Step 3: Add `get_window_config` method to ExecutionInterface**

```python
    def get_window_config(self, window_id: int):
        """Return WindowConfig for the given 1-based window ID, or None."""
        if self.test_config is None:
            return None
        return self.test_config.get_window(window_id)
```

- [ ] **Step 4: Inject window_config into ExecutionWindow.start_execution() context**

In `ExecutionWindow.start_execution()` (around line 402), change the context dict:

```python
        window_config = None
        if self.execution_interface:
            window_config = self.execution_interface.get_window_config(
                self.window_id + 1)

        context = {
            "mes_handler": None,
            "button_index": button_index,
            "window_config": window_config,
        }
```

- [ ] **Step 5: Verify integration — load config and start execution**

Run: `python demo.py`

Manual test:
1. Navigate to "测试执行" (basic input) tab
2. In "全局配置" dropdown, select "example" (or any saved config)
3. Window 1 should execute with the config's IP/protocol/port/instruments (passed in context)
4. Check the logger output to confirm `window_config` is in the context

- [ ] **Step 6: Commit**

```bash
git add app/view/basic_input_interface.py
git commit -m "feat: integrate test config loading into execution interface"
```

---

### Task 8: Final verification and cleanup

- [ ] **Step 1: Full workflow test**

Run: `python demo.py`

Full test:
1. Login → navigate to "测试配置" (menu) tab
2. Create a new config "验证测试"
3. Fill all 8 windows with different IPs and instruments
4. Save
5. Navigate to "测试执行" (basic input) tab
6. Select "验证测试" from global config dropdown
7. Enter MAC address in any window, start execution
8. Verify the window_config is present in the executor context (check logs)

- [ ] **Step 2: Edge case — empty config**

1. Select "选择配置..." in the combo → test_config should be None
2. Start execution → context should have `window_config: None`
3. No crash

- [ ] **Step 3: Edge case — load config, then switch to another**

1. Select config A
2. Select config B
3. Verify the active config updates

- [ ] **Step 4: Commit if any cleanup was needed**

```bash
git add -A
git commit -m "chore: final verification cleanup"
```
