# AstraPlusCar-HarmonyOS

English | [简体中文](README_zh.md)

A HarmonyOS controller for robot driving, camera preview, lidar status and image capture.

## Overview

The application connects to the vehicle over a local HTTP API. It provides touch and voice controls, video preview, proximity overlays and an application-private image gallery. Connection and video state gate motion commands; release, disconnection and background transitions stop the active motion. The vehicle service is maintained separately in AstraPlusCar-device.

## Technology and Dependencies

ArkTS, ArkUI/HDS, HarmonyOS API 23, OHPM and Hvigor. Platform HTTP, media, speech and haptics APIs provide device integration. The entry package declares no third-party runtime dependencies. A compatible robot service and local network are required for vehicle functions.

## Repository Structure

- `entry/src/main/ets/` — ArkTS application code
- `entry/src/main/resources/` — resources and routes
- `AppScope/` — application metadata
- `build-profile.example.json5` — build configuration template
- `oh-package.json5` — package dependencies
- `docs/` — interface and development notes
- `car_server/` — retained server-side support files
- `tools/` — development utilities

## Quick Start

1. Open the repository root in DevEco Studio with the SDK required by `build-profile.example.json5`.
2. Copy that template to `build-profile.json5`, restore OHPM dependencies and configure signing locally if installing on a device.
3. Select the `entry` module and a compatible device/emulator, then build and run from the IDE. Keep certificates and machine-specific paths outside version control.

Start the compatible vehicle service, connect the phone and vehicle to the same network, and enter `http://<vehicle-host>:8080` in the connection page. Confirm live video and sensor state before testing movement. Interface details are in the [device repository](https://github.com/Rayawa/AstraPlusCar-device).
