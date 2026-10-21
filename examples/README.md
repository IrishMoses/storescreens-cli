# Capture through MCP, then render with Koubou

This example uses StoreScreens 4.0.1 or later, a local Xcode project with a validated XCUITest screenshot harness, and Koubou 0.21 or later. It uses the Python standard library for the MCP client. Koubou and ASC CLI are optional downstream tools; substitute your existing renderer or upload tool when appropriate.

## Configure capture

Install StoreScreens with mise, Homebrew, or the curl installer described in the main README. Install the simulator runtimes required by your application. Use `storescreens list` to choose available device names.

In your application's directory, create `storescreens.yml`:

```yaml
project: MyApp.xcodeproj
scheme: MyApp
test_target: MyAppUITests
test_class: ScreenshotTests
devices:
  - simulator: iPhone 18 Pro Max
  - simulator: iPad Pro 13-inch (M5)
locales: [en-US, el]
appearances: [light, dark]
screenshots: [Home, Detail]
output_dir: screenshots/raw
result_bundle_dir: screenshots/results
derived_data_path: .capture/DerivedData
keep_runs: 1
```

Use your project's actual scheme, target, class, and screenshot names. `storescreens setup` generates an editable harness if needed. Add application-specific navigation and explicit waits before each named capture. Applications using Keychain or app-group entitlements can set `code_signing_allowed: true` to retain simulator signing.

Keep the capture configuration and rendering templates in source control. Ignore generated raw images, result bundles, reports, and DerivedData according to your project's artifact policy.

## Start a capture and retrieve its result

From the StoreScreens repository, run the standard-library MCP client against your application's directory:

```sh
python3 examples/mcp-capture.py \
  --directory ../MyApp \
  --report ../MyApp/screenshots/reports/full.json
```

The client initializes `storescreens-mcp`, calls `capture`, polls `get_capture_status`, and retrieves the manifest with `get_capture_result`. Its JSON receipt contains the actual requests and responses. `--server` can select an explicitly built or installed server binary.

The initial tool call is equivalent to:

```json
{"name":"capture","arguments":{"directory":"../MyApp","config_path":"storescreens.yml"}}
```

`capture` returns a task ID immediately. Poll until the status is `completed` or `failed`; a task ID alone does not establish success. On completion, pass its capture ID to `get_capture_result`. Two screens across two devices, two locales, and two appearances produce 16 manifest images when every combination succeeds.

## Recapture one selection

```sh
python3 examples/mcp-capture.py \
  --directory ../MyApp \
  --locales el --appearances dark --only Home \
  --report ../MyApp/screenshots/reports/partial.json
```

This replaces the two Greek dark-mode Home captures and preserves the other 14 images and their manifest entries. `--no-parallel` runs one device at a time; `--retries 0` disables additional attempts.

A failing test produces `status: failed` even if it saved PNGs before failing. Failed captures preserve the previous successful output. Fix the test and repeat the same selection to recover. Set `result_bundle_dir` to retain the original XCTest diagnostics. To verify the failure contract with the self-contained fixture instead of your app, run `python3 scripts/smoke-capture.py`; it saves a screenshot, deliberately fails the test, verifies unchanged output, and then exercises recovery.

## Render the collected PNGs

Inspect the available output sizes and frames:

```sh
kou list-sizes
kou list-frames 'iPhone'
kou list-frames 'iPad Pro 13'
```

Generate separate framing configurations for the phone and tablet:

```sh
python3 examples/koubou-config.py ../MyApp/screenshots/raw/manifest.json \
  --simulator 'iPhone 18 Pro Max' \
  --frame 'iPhone 17 Pro Max - Silver - Portrait' --size iPhone6_9 \
  --config ../MyApp/koubou-phone.yml \
  --output-dir ../MyApp/screenshots/rendered/phone
python3 examples/koubou-config.py ../MyApp/screenshots/raw/manifest.json \
  --simulator 'iPad Pro 13-inch (M5)' \
  --frame 'iPad Pro 13 - M4 - Space Gray - Portrait' --size iPadPro13 \
  --config ../MyApp/koubou-tablet.yml \
  --output-dir ../MyApp/screenshots/rendered/tablet
kou generate ../MyApp/koubou-phone.yml
kou generate ../MyApp/koubou-tablet.yml
```

These example frames have screen areas matching the 1320×2868 phone and 2064×2752 tablet captures. Select a matching frame and output size for different devices. The helper writes relative image paths and a simple centered layout; all framing and rendering happen in Koubou. Review the generated layout, localizations, colors, and output sizes before adopting it as a marketing template.

## Preview an upload

After reviewing a rendered image, use ASC CLI's dry-run mode with your application's existing version:

```sh
asc screenshots upload --app "$APP_ID" --version "$APP_VERSION" \
  --locale en-US \
  --path ../MyApp/screenshots/rendered/phone/iPhone_17_Pro_Max_-_Silver_-_Portrait/en-US_light_Home.png \
  --device-type IPHONE_69 --dry-run
```

This example does not upload or replace screenshots. Actual uploads remain an explicit release step, using your approved copy, device sizes, locale coverage, and target version.

## Validation

The 4.0.1 workflow was exercised with a real iOS app on iPhone 18 Pro Max and iPad Pro 13-inch (M5) simulators running iOS 27. English and Greek, light and dark, and two screens produced 16 raw images and 16 Koubou renders. Both sequential and parallel MCP capture passed. Partial captures preserved the other 14 images; a test that saved a PNG and then failed left all prior output unchanged; a corrected rerun recovered successfully. Koubou 0.21.0 produced the expected 1320×2868 phone and 2064×2752 tablet outputs.
