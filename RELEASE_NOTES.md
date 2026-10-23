StoreScreens 4.1.1 fixes Apple Watch simple captures that could report success while saving the boot logo. Simulator startup now has a bounded readiness check, and Watch simple capture uses a temporary XCUITest runner to wait for visible foreground app content. Failed, missing, or blank captures are rejected without replacing successful output.

Build products are resolved through Xcode build settings, so Release and custom build configurations work without assuming Debug output paths. Simple capture creates its temporary screenshot directory when reusing DerivedData, and attachment exports use separate directories for each locale and retry.

Validated with 159 automated tests and 14 Watch captures across seven locales on 42 mm and 46 mm watchOS 27 simulators, including checks that blank or exited apps fail while preserving previous output.
