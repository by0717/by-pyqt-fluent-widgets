Hydra integration (quick guide)

- Default configs are under `configs/`.
  - `config.yaml` holds defaults for `commands` and `app` groups.
  - `configs/commands/*.yaml` are command sets.
  - `configs/app/*.yaml` contain application defaults (e.g., window_count).

- Run with Hydra overrides:

  ```bash
  # Use default composed config
  python entry_hydra.py

  # Choose a different command set
  python entry_hydra.py commands=example_config

  # Override app settings
  python entry_hydra.py app.window_count=4 app.scanner_timeout_ms=100
  ```

- In-app "Load Hydra Default" button (Configuration tab) will load composed Hydra defaults at runtime.

- To batch-convert old TOML files to YAML, run:

  ```bash
  python scripts/convert_toml_to_yaml.py
  ```

- Helpers for tests:
  - `app/test_utils.py` provides `load_commands_by_name(name)` and `load_commands_from_hydra_default()` for loading command sets as plain dicts.
  - Example pytest fixtures are added in `tests/conftest.py` (`example_commands`, `hydra_default_commands`).

Requirements: `hydra-core`, `omegaconf` (install via `pip install hydra-core omegaconf`).