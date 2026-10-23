#!/usr/bin/env python3
"""Verify Watch simple capture waits for visible content and fails without publishing.

Requires Xcode, watchOS 27/iOS 27 runtimes, xcodegen, Pillow, and a built CLI.
Uses newly created simulator pairs only. Run --sanity before the full matrix.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import uuid

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--sanity", action="store_true", help="One size and locale; omit failure cases")
parser.add_argument("--cli", type=Path, default=ROOT / ".build/debug/storescreens")
args = parser.parse_args()
ARTIFACTS = Path(tempfile.mkdtemp(prefix="storescreens-watch-simple-"))
owned = []
expected_sizes = {}


def run(*command, **kwargs):
    return subprocess.run(list(map(str, command)), check=True, text=True, **kwargs)


def create(kind, device_type):
    name = f"StoreScreens-Simple-{kind}-{uuid.uuid4().hex[:8]}"
    udid = run("xcrun", "simctl", "create", name,
               f"com.apple.CoreSimulator.SimDeviceType.{device_type}",
               f"com.apple.CoreSimulator.SimRuntime.{kind}-27-0", capture_output=True).stdout.strip()
    owned.append({"name": name, "udid": udid})
    (ARTIFACTS / "owned.json").write_text(json.dumps(owned, indent=2))
    return name, udid


def hashes():
    return {str(p.relative_to(ARTIFACTS / "captures")): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in (ARTIFACTS / "captures").rglob("*") if p.is_file()}


def capture(config, name, expect_success=True):
    (ARTIFACTS / "storescreens.yml").write_text(json.dumps(config, indent=2))
    with (ARTIFACTS / f"{name}.log").open("w") as log:
        result = subprocess.run([str(args.cli.resolve()), "capture", "--mode", "simple", "--retries", "0"],
                                cwd=ARTIFACTS, stdout=log, stderr=subprocess.STDOUT, timeout=1800)
    output = (ARTIFACTS / f"{name}.log").read_text()
    print(output, flush=True)
    if expect_success:
        assert result.returncode == 0, (name, result.returncode)
    else:
        assert result.returncode != 0, f"{name} incorrectly succeeded"
        assert "Waiting for visible Watch application content..." in output, output
        assert "Captured screenshot_" not in output, output


def verify_images(config):
    output = ARTIFACTS / config["output_dir"]
    manifest = json.loads((output / "manifest.json").read_text())
    count = len(config["devices"]) * len(config["locales"])
    assert len(manifest["devices"]) == count
    screenshots = [(output / shot["filename"], expected_sizes[device["simulatorName"]])
                   for device in manifest["devices"] for shot in device["screenshots"]]
    assert len(screenshots) == count
    for path, expected_size in screenshots:
        image = Image.open(path).convert("RGB")
        assert image.size == expected_size, (path, image.size, expected_size)
        pixels = image.tobytes()
        green = sum(pixels[i + 1] > 140 and pixels[i] < 100 and pixels[i + 2] < 120
                    for i in range(0, len(pixels), 3))
        assert green > image.width * image.height // 3, f"Missing READY content: {path}"
    return count


try:
    print("Artifacts:", ARTIFACTS, flush=True)
    (ARTIFACTS / "App").mkdir()
    # Locale.current falls back to the development language unless the app
    # declares the requested localization. Exercise real localized resources.
    translations = {
        "en": ("READY", "Analyze"), "es": ("LISTO", "Analizar"),
        "pt": ("PRONTO", "Analisar"), "fr": ("PRÊT", "Analyser"),
        "de": ("BEREIT", "Analysieren"), "it": ("PRONTO", "Analizza"),
        "tr": ("HAZIR", "Analiz Et"),
    }
    for language, (ready, analyze) in translations.items():
        folder = ARTIFACTS / "App" / f"{language}.lproj"
        folder.mkdir()
        (folder / "Localizable.strings").write_text(f'"READY" = "{ready}";\n"Analyze" = "{analyze}";\n')
    (ARTIFACTS / "App/App.swift").write_text('''import SwiftUI
@main struct WatchSimpleFixture: App {
    var body: some Scene { WindowGroup { DelayedContent() } }
}
struct DelayedContent: View {
    @State private var ready = false
    @State private var diagnostic = ""
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea().accessibilityHidden(true)
            if ready {
                Color.green.ignoresSafeArea().accessibilityHidden(true)
                VStack {
                    Text("READY").accessibilityIdentifier("ready")
                    Button("Analyze") {}.accessibilityIdentifier("analyze")
                    Text(Locale.current.identifier)
                }
            } else if !diagnostic.isEmpty {
                Text(diagnostic).foregroundStyle(.red)
            }
        }.task {
            try? await Task.sleep(for: .seconds(6))
            if CommandLine.arguments.contains("--exit-before-ready") { exit(0) }
            let arguments = CommandLine.arguments
            let index = arguments.lastIndex(of: "-AppleLocale")
            let expected = index.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            if let expected {
                let requested = Locale(identifier: expected)
                let matches = Locale.current.language.languageCode == requested.language.languageCode
                    && (requested.region == nil || Locale.current.region == requested.region)
                if !arguments.contains("--never-ready"), matches { ready = true }
            }
            if !ready, !arguments.contains("--never-ready") {
                diagnostic = "Actual: \\(Locale.current.identifier) Expected: \\(expected ?? "missing")"
            }
        }
    }
}
''')
    project = {"name": "WatchSimpleFixture", "settings": {"GENERATE_INFOPLIST_FILE": "YES", "SWIFT_VERSION": "5.0"},
               "targets": {"WatchSimpleFixture": {"type": "application", "platform": "watchOS", "deploymentTarget": "11.0",
                           "sources": ["App"], "settings": {"PRODUCT_BUNDLE_IDENTIFIER": "app.storescreens.simple-fixture",
                           "INFOPLIST_KEY_WKApplication": True, "INFOPLIST_KEY_WKWatchOnly": True}}},
               "schemes": {"WatchSimpleFixture": {"build": {"targets": {"WatchSimpleFixture": "all"}}, "run": {"config": "Release"}}}}
    (ARTIFACTS / "project.yml").write_text(json.dumps(project))
    run("xcodegen", "generate", "--project", ARTIFACTS, "--spec", ARTIFACTS / "project.yml")
    devices = []
    for size in ([42] if args.sanity else [42, 46]):
        phone, _ = create("iOS", "iPhone-18-Pro")
        watch, _ = create("watchOS", f"Apple-Watch-Series-12-{size}mm")
        devices.append({"simulator": watch, "platform": "watchOS", "companion": phone})
        expected_sizes[watch] = (374, 446) if size == 42 else (416, 496)
    locales = ["es-ES"] if args.sanity else ["en-US", "es-ES", "pt-BR", "fr-FR", "de-DE", "it", "tr"]
    config = {"project": "WatchSimpleFixture.xcodeproj", "scheme": "WatchSimpleFixture", "devices": devices,
              "locales": locales, "output_dir": "captures", "derived_data_path": str(ARTIFACTS / "DerivedData"),
              "result_bundle_dir": "results", "preflight": False, "launch_arguments": ["--uitesting"]}
    if not args.sanity:
        # Catch locale forwarding and readiness regressions before the full matrix.
        sanity = dict(config, devices=devices[:1], locales=["es-ES"], output_dir="sanity-captures")
        capture(sanity, "sanity")
        verify_images(sanity)
    capture(config, "visible")
    # The Release scheme and persistent cache also exercise the two earlier fixes.
    assert (ARTIFACTS / "DerivedData/Build/Products/Release-watchsimulator/WatchSimpleFixture.app").is_dir()
    count = verify_images(config)
    if not args.sanity:
        before = hashes()
        config["devices"] = devices[:1]
        config["locales"] = locales[:1]
        for failure in ["never-ready", "exit-before-ready"]:
            config["launch_arguments"] = ["--uitesting", f"--{failure}"]
            capture(config, failure, expect_success=False)
            assert hashes() == before, f"{failure} changed the published capture"
    (ARTIFACTS / "validation.json").write_text(json.dumps({"status": "passed", "screenshots": count,
        "locales": locales, "devices": devices, "sanity": args.sanity}, indent=2))
    print("WATCH SIMPLE CAPTURE VALIDATION PASSED", flush=True)
finally:
    for device in reversed(owned):
        subprocess.run(["xcrun", "simctl", "shutdown", device["udid"]], capture_output=True)
        subprocess.run(["xcrun", "simctl", "delete", device["udid"]], capture_output=True)
    print("Artifacts retained:", ARTIFACTS, flush=True)
