# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A PySide6 desktop application for test automation — executing command sequences over Telnet/SSH/Serial against network devices/instruments, with MES (Manufacturing Execution System) integration and VISA instrument control. Built on QFluentWidgets for the UI layer.

**Entry point**: `demo.py`

## Commands

```bash
# Run the app
python demo.py

# Run a single test module directly
python -m app.tests.function_test

# Type checking (PySide6 signals often produce false positives — suppress with caution)
# No formal type checker configured; use Pylance in VSCode
```

There is no test suite runner, linter, or build step configured. The app is launched directly via `demo.py`.

## Architecture

### Configuration System

Two-layer config with a Hydra-to-QConfig bridge:

1. **`app/core/config_manager.py`** — `UnifiedConfigManager` singleton. Hydra + OmegaConf under the hood, with fallback to raw YAML if Hydra is unavailable. Supports dot-path access (`get('ui.theme.mode')`). Config root: `app/configs/config.yaml`.

2. **`app/common/config_adapter.py`** — `HydraConfigAdapter(QConfig)` bridges Hydra data into QFluentWidgets' `QConfig` interface so the UI framework's config binding works. Syncs bidirectionally on save.

3. **`app/common/config.py`** — Tries to use `HydraConfigAdapter` at import time; falls back to legacy `QConfig` with JSON file. Exports `cfg` as the global config instance used by views.

Config files live under `app/configs/` organized by domain: `mes/`, `commands/`, `devices/`, `device_templates/`, `app/`, `scanner/`.

### Core Module (`app/core/`)

- **`command_executor.py`** — `CommandExecutor`: the central engine. Loads YAML command configs, initializes protocol clients (Telnet/SSH/Serial), executes commands with retry logic, variable substitution (`{$Var}`), regex variable extraction from responses, conditional execution, and expect-pattern matching (string contains, exact, or regex). Supports context manager protocol.

- **`test_manager.py`** — `TestManager`: dynamically discovers test classes in `app/tests/` by scanning for `BaseTest` subclasses. Supports ordered execution, enable/disable, and category grouping.

- **`test_runner.py`** — `TestRunner` (synchronous, runs in-process) and `TestExecutor` (QThread subclass, runs tests in background with progress signals). Both accept `TestContext` with command/mes/device configs.

- **`test_base.py`** — `BaseTest(QObject)`, `TestResult`, `TestContext` (dataclasses). Tests implement `execute(context) -> TestResult`. Signals: `progress_updated`, `test_finished`.

- **`device_manager.py`** — `DeviceManager`: loads device configs and templates from Hydra (with YAML/JSON fallback). VISA instrument discovery and connection testing via PyVISA.

- **`mes_api.py`** — `MESAPI`: high-level MES interface. `prepare_test_data(barcode)` and `pass_station(is_pass)` for the test station workflow.

- **`mes_handler.py`** / **`mes_handler_manager.py`** — MES protocol handler and its singleton manager.

- **`mes_config_manager.py`** — MES config loading with Hydra, per-provider YAML files under `app/configs/mes/`. Includes `MESConfigManagerSingleton`.

- **`config_manager.py`** — Described above. Global `config_manager` singleton with `get()`/`set()`/`save()`/`reload()`.

- **`license_manager.py`** — License validation.

### Protocol Clients (`app/base/`)

- `by_telnet_client.py` — TelnetClient
- `by_ssh_client.py` — SSHClient
- `by_serial_client.py` — SerialClient
- `by_ping.py` — Ping utility

All follow a similar pattern: `connect()`, `send_command()`, `close()`, `is_connected()`.

### Data Models (`app/models/`)

- `command_config.py` — `CommandConfig`, `ExecutionControl`, `VariableExtraction`, `Condition`, `CommandParameters` (all dataclasses). `CommandConfigManager` handles YAML loading.
- `device_model.py` — `DeviceConfig` dataclass with `from_dict()`/`to_dict()`.

### Views (`app/view/`)

- **`main_window.py`** — `MainWindow(FluentWindow)`: login flow, role-based navigation. Permissions map to which nav tabs are visible. Delays interface instantiation until after login.
- **`basic_input_interface.py`** — `ExecutionInterface`: the main test execution panel (1-to-8 device testing).
- **`date_time_interface.py`** — `ConfigurationInterface`: command configuration editing.
- **`test_runner_ui.py`** — `TestRunnerUI`: test selection and configuration.
- **`mes_integration_widget.py`** — MES configuration panel.
- **`login_interface.py`** — Login page with credential validation.
- Other interfaces: `dialog_interface.py` (device config), `setting_interface.py`, `home_interface.py`, etc. — most are QFluentWidgets-based pages plugged into `MainWindow`'s navigation stack.

### Utilities (`app/utils/`)

- `path_utils.py` — `Path_Config` class with all project paths rooted at `app/`.
- `by_logger.py` — Logger initialization.
- `hydra_utils.py` — `load_hydra_config()` helper.
- `mes_barcode_parser.py` — Barcode parsing for MES data.
- `log_config_manager.py` / `log_emitter.py` — Log configuration and Qt log signal bridging.

### Common (`app/common/`)

- `signal_bus.py` — `SignalBus(QObject)` singleton for cross-component communication.
- `translator.py` — Internationalization wrapper.
- `trie.py` — Trie data structure (used for navigation/search).
- `resource.py` — Compiled Qt resources.

## Key Patterns

- **Singleton pattern** used extensively: `config_manager`, `SignalBus`, `MESConfigManagerSingleton`, `MESHandlerManager`. Access via module-level instances or `get_*()` factory functions.
- **Hydra-first, YAML-fallback**: config and device managers try Hydra, then fall back to direct YAML/JSON file reading.
- **Signal-based communication**: `signalBus` (global) and per-component Qt signals for decoupled UI updates.
- **Test execution**: tests live as classes in `app/tests/`, auto-discovered by `TestManager`, executed by `TestExecutor` (threaded) with cloned test instances to avoid shared state issues.
