# SD as Internal Storage on Android Devices

**English** | [Português (Brasil)](README.pt-BR.md)

A Windows GUI tool that uses ADB to list an Android device's memory card, format it as **internal storage** (adoptable storage) or return it to **portable mode**.

Many manufacturers and carriers hide the "Format as internal" option from the card menu, even when Android supports the feature. This tool uses the system's own commands (`sm`), which remain available.

> **Warning:** both formatting options erase everything on the card.

## Features

- Finds `adb.exe` in PATH or in the Android SDK.
- Lists connected devices and warns when the PC still needs to be authorised.
- Shows each card with its size, current mode (Portable, Internal storage or Mixed), volumes and used space.
- Shows the Android version and whether the device supports adoptable storage, and disables buttons that do not apply.
- Asks for confirmation before formatting and logs every command and its output.
- Startup tips screen: how to turn on Developer options and USB debugging, supported Android versions and common issues.
- Interface in the Windows display language: Brazilian Portuguese on Portuguese systems, International English on all others. Use `-Lang pt` or `-Lang en` to force a language.

## Requirements

- Windows 10 or 11 (Windows PowerShell 5.1, included).
- [Android SDK Platform-Tools](https://developer.android.com/tools/releases/platform-tools) (`adb`).
- A device running Android 6.0 or newer, with USB debugging turned on.

## Android versions

| Version | Card as internal storage |
|---|---|
| 5.1 or earlier | Not supported |
| 6.0 to 8.1 | Supported; usually shown in the card menu |
| 9 to 15 | Supported by the system; many manufacturers hide the option from the menu |
| Newer than 15 | Not verified |

Some manufacturers (for example, recent Samsung Galaxy devices) block the feature. In that case the tool shows "Internal storage support: no" and only allows portable mode.

Tested on: TCL TAB 10 5G (9183W, T-Mobile firmware), Android 12.

## How to use

1. On the device, turn on **Developer options** (tap *Settings > About phone > Build number* 7 times) and **USB debugging**.
2. Connect the cable, unlock the screen and accept the **"Allow USB debugging?"** prompt.
3. On the PC, open **`Cartao SD ADB.bat`** (or run the command below).
4. Click **List cards**, select the card and choose the action.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -STA -File sd_adb_tool.ps1
```

After formatting as internal, move apps in *Settings > Apps > [app] > Storage > Change*. Before removing the card or returning to portable mode, move the apps back to internal storage.

## Commands used

| Action | Command |
|---|---|
| List cards | `adb shell dumpsys mount` |
| Check support | `adb shell sm has-adoptable` |
| Format as internal | `adb shell sm partition <disk> private` |
| Return to portable mode | `adb shell sm partition <disk> public` |
