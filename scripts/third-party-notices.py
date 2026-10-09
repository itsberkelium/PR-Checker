#!/usr/bin/env python3
"""Assembles the third-party license notices shipped inside each app.

    scripts/third-party-notices.py

Run after changing a bundled dependency, then commit the two output files. Needs the macOS
Swift packages resolved (macos/build) and the Windows app restored (~/.nuget/packages), since
it copies license texts from the exact package versions that ship.
"""
import json
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NUGET = Path.home() / ".nuget/packages"
MAC_OUT = ROOT / "macos/PRChecker/THIRD-PARTY-NOTICES.txt"
WIN_OUT = ROOT / "windows/src/PRChecker.App/THIRD-PARTY-NOTICES.txt"
RULE = "=" * 78


def local(path):
    return Path(path).read_text(encoding="utf-8-sig").strip()


def remote(url):
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read().decode("utf-8-sig").strip()


def nuget_version(package):
    assets = json.loads((ROOT / "windows/src/PRChecker.App/obj/project.assets.json").read_text())
    for name in assets["libraries"]:
        package_id, version = name.split("/")
        if package_id.lower() == package.lower():
            return version
    raise SystemExit(f"{package} isn't restored; run dotnet restore for the Windows app first")


def nuget(package, file):
    version = nuget_version(package)
    return version, local(NUGET / package.lower() / version / file)


def section(title, version, url, text):
    return f"{RULE}\n{title} {version}\n{url}\n{RULE}\n\n{text}\n"


def document(app, intro, sections):
    header = (f"PR Checker for {app}: third-party notices\n\n{intro}\n\n"
              "PR Checker's own code is licensed under the MIT License; see LICENSE in\n"
              "https://github.com/itsberkelium/PR-Checker.\n")
    return header + "\n" + "\n".join(sections)


def mac():
    resolved = json.loads((ROOT / "macos/PRChecker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())
    sparkle = next(pin for pin in resolved["pins"] if pin["identity"].lower() == "sparkle")["state"]["version"]
    return document("macOS", "This app includes the following third-party software.", [
        section("Sparkle", sparkle, "https://github.com/sparkle-project/Sparkle",
                local(ROOT / "macos/build/SourcePackages/checkouts/Sparkle/LICENSE")),
    ])


def windows():
    _, sdk_license = nuget("Microsoft.WindowsAppSDK.WinUI", "license.txt")
    sdk_version = nuget_version("Microsoft.WindowsAppSDK")
    _, sdk_base_notice = nuget("Microsoft.WindowsAppSDK.Base", "NOTICE.txt")
    _, sdk_winui_notice = nuget("Microsoft.WindowsAppSDK.WinUI", "NOTICE.txt")
    webview_version, webview_license = nuget("Microsoft.Web.WebView2", "LICENSE.txt")
    _, webview_notice = nuget("Microsoft.Web.WebView2", "NOTICE.txt")
    dotnet_version, dotnet_license = nuget("System.Drawing.Common", "LICENSE.TXT")
    _, dotnet_notices = nuget("System.Drawing.Common", "THIRD-PARTY-NOTICES.TXT")
    return document("Windows", (
        "This app includes the following third-party software. The Microsoft Windows App SDK\n"
        "components are licensed under the Microsoft Software License Terms reproduced below;\n"
        "by installing or using PR Checker you agree to those terms for those components."), [
        section("H.NotifyIcon", nuget_version("H.NotifyIcon.WinUI"), "https://github.com/HavenDV/H.NotifyIcon",
                remote("https://raw.githubusercontent.com/HavenDV/H.NotifyIcon/master/LICENSE.md")),
        section("Velopack", nuget_version("Velopack"), "https://github.com/velopack/velopack",
                remote("https://raw.githubusercontent.com/velopack/velopack/develop/LICENSE")),
        section(".NET runtime and libraries", dotnet_version, "https://github.com/dotnet/runtime",
                dotnet_license + "\n\n" + dotnet_notices),
        section("Microsoft Windows App SDK", sdk_version, "https://github.com/microsoft/WindowsAppSDK",
                sdk_license + "\n\n" + sdk_winui_notice + "\n\n" + sdk_base_notice),
        section("Microsoft Edge WebView2 SDK (loader)", webview_version, "https://aka.ms/webview2",
                webview_license + "\n\n" + webview_notice),
    ])


if __name__ == "__main__":
    for path, text in ((MAC_OUT, mac()), (WIN_OUT, windows())):
        path.write_text(text, encoding="utf-8")
        print(f"Wrote {path.relative_to(ROOT)} ({len(text) // 1024} KB)")
