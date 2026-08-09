fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

### ios_testflight

```sh
[bundle exec] fastlane ios_testflight
```

iOS TestFlight (alias)

### mac_testflight

```sh
[bundle exec] fastlane mac_testflight
```

macOS TestFlight (alias)

### watch_testflight

```sh
[bundle exec] fastlane watch_testflight
```

Build iOS with its embedded watchOS app and upload both to TestFlight

### all_testflight

```sh
[bundle exec] fastlane all_testflight
```

Publish one shared iOS/watchOS/macOS release with resumable platform uploads

### refresh_profiles

```sh
[bundle exec] fastlane refresh_profiles
```

Regenerate App Store profiles for every Apple target using the local distribution certificate

### generate_store_assets

```sh
[bundle exec] fastlane generate_store_assets
```

Generate App Store screenshot assets (iOS/macOS/watchOS)

----


## iOS

### ios testflight_release

```sh
[bundle exec] fastlane ios testflight_release
```

Build iOS and upload to TestFlight

----


## Mac

### mac testflight_release

```sh
[bundle exec] fastlane mac testflight_release
```

Build macOS and upload to TestFlight

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
