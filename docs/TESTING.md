# Testing

Build the script class cache once per clone, and again after adding any
`class_name` script:

```bash
godot --headless --path . --import
```

On Godot 4.4 and 4.6, this import step leaves `.recovery_mode_lock` in the
project's user data folder, and the next editor launch asks to open in
Recovery Mode. The test wrappers below delete it before and after they run.
If you run only the import step, delete
`%APPDATA%\Godot\app_userdata\GoShade Turbo\.recovery_mode_lock` (Windows),
or the equivalent under `~/.local/share/godot/app_userdata/` (Linux) or
`~/Library/Application Support/Godot/app_userdata/` (macOS). Running the
import with an isolated `APPDATA`/`LOCALAPPDATA` avoids it entirely.

Codegen and unit tests, headless:

```bash
godot --headless --path . -s res://tests/run_codegen_tests.gd
```

Rendered checks. These need a GPU session: the `--headless` dummy driver
cannot read back viewport pixels.

```bash
godot --path . --rendering-driver opengl3 -s res://tests/run_render_checks.gd
```

Add `-- --write-screenshots` to save every checked stack's 128x128 render to
`sandbox/screenshots/<stack file stem>.png`. The folder is in `.gitignore`.

Recipe motion checks at fixed times (1, 30 and 120 seconds):

```bash
godot --path . --rendering-driver opengl3 -s res://tests/run_recipe_motion_checks.gd
```

`godot` is whatever resolves to a Godot 4.4+ binary on your system.

Render and motion checks on the Mobile and Forward+ renderers (Vulkan):

```bash
godot --path . --rendering-method mobile -s res://tests/run_render_checks.gd
```

```bash
godot --path . --rendering-method forward_plus -s res://tests/run_render_checks.gd
```

## Device check (Android)

Renders every exported recipe and reference shader on a phone and logs one
`MOBILE <name> PASS|FAIL` line each, then `MOBILE SUMMARY`.

1. Build the shaders:

```bash
godot --headless --path . -s res://sandbox/mobile/build_mobile_shaders.gd
```

2. For the export only, set in `project.godot` (revert after): `run/main_scene="res://sandbox/mobile/mobile_check.tscn"` under `[application]`, and `textures/vram_compression/import_etc2_astc=true` under `[rendering]`. Add `renderer/rendering_method.mobile="gl_compatibility"` to test the Compatibility renderer. The Android export ignores `override.cfg` for these, and release templates refuse a scene path on the command line.
3. Export an Android debug APK (needs Android export templates, `export/android/java_sdk_path` in Editor Settings, and an `export_presets.cfg` Android preset, gitignored), install it, and read the log:

```bash
adb logcat -s godot
```
