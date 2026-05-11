# GUT — Vendored Copy

This directory is a flat **vendored** copy of the
[bitwes/Gut](https://github.com/bitwes/Gut) addon, pinned at the version
recorded below. We do *not* track it as a git submodule because the upstream
repository nests the addon under `addons/gut/`, which produced a double
`addons/gut/addons/gut/` path here and broke Godot's plugin / class-name
resolution.

## Pinned version

- **Tag:** `v9.6.0`
- **Source:** `https://github.com/bitwes/Gut/tree/v9.6.0/addons/gut`
- **Vendored on:** 2026-05-11

## Updating

```powershell
$tmp = "D:\tmp\gut_clone"
git clone --depth 1 --branch <tag> https://github.com/bitwes/Gut $tmp
robocopy "$tmp\addons\gut" addons\gut /MIR
```

After updating, bump the pinned version above and run the full test
suite to confirm compatibility.

## Running tests

```powershell
godot --headless --path . `
  -s res://addons/gut/gut_cmdln.gd `
  -gdir=res://tests/unit -gexit
```
