#!/usr/bin/env python3
"""Builds the AltStore / SideStore source for Aicord from the repository's
GitHub releases.

    gh api repos/OWNER/REPO/releases --paginate | python3 scripts/altstore_source.py > source.json

Every release with an `.ipa` asset becomes a version, newest first. Releases
marked as drafts are skipped; prereleases are kept, since AltStore shows the
newest version anyway. Only the standard library is used.
"""

import json
import re
import sys

REPO = "lakafior/Aicord"
BUNDLE_ID = "net.smigi.aicord"
MIN_OS = "26.0"

SOURCE = {
    "name": "Aicord",
    "identifier": "net.smigi.aicord.source",
    "subtitle": "A native Discord client for iPhone and iPad",
    "website": f"https://github.com/{REPO}",
    "iconURL": f"https://raw.githubusercontent.com/{REPO}/main/AicordSafari/Resources/images/icon-128.png",
    "tintColor": "#5865F2",
    "featuredApps": [BUNDLE_ID],
}

APP = {
    "name": "Aicord",
    "bundleIdentifier": BUNDLE_ID,
    "developerName": "Lakafior",
    "subtitle": "Discord in SwiftUI, with Liquid Glass",
    "localizedDescription": (
        "Aicord is an unofficial Discord client written in SwiftUI for iOS 26, based on Paicord. "
        "It has voice calls with end-to-end encryption, native lists, invite previews and "
        "read-only Intelligence features that run on the device.\n\n"
        "Aicord is not made by or affiliated with Discord. Using a third-party client is "
        "against Discord's terms of service and is at your own risk."
    ),
    "iconURL": SOURCE["iconURL"],
    "tintColor": "#5865F2",
    "category": "social",
    "screenshots": [],
    "appPermissions": {
        "entitlements": [],
        "privacy": {
            "NSCameraUsageDescription": "Aicord uses the camera to take photos and videos to send in chats.",
            "NSMicrophoneUsageDescription": "Aicord uses the microphone for voice calls and to record videos and voice messages.",
            "NSMotionUsageDescription": "Aicord uses motion data to keep the camera preview upright.",
            "NSSpeechRecognitionUsageDescription": "Aicord transcribes voice messages on your device.",
            "NSLocalNetworkUsageDescription": "Aicord connects to a language model server on your network, like Ollama or LM Studio, only when you enter its address in Settings → Intelligence.",
        },
    },
}


def version_of(release):
    """`v1.2.3` → `1.2.3`; the tag is what the workflow builds."""
    return re.sub(r"^v", "", release.get("tag_name") or "")


def versions(releases):
    result = []
    for release in releases:
        if release.get("draft"):
            continue
        ipa = next(
            (a for a in release.get("assets", []) if a.get("name", "").endswith(".ipa")), None
        )
        version = version_of(release)
        if not ipa or not version:
            continue
        result.append(
            {
                "version": version,
                "buildVersion": version,
                "date": release.get("published_at") or release.get("created_at"),
                "localizedDescription": (release.get("body") or "").strip()[:4000],
                "downloadURL": ipa["browser_download_url"],
                "size": ipa.get("size", 0),
                "minOSVersion": MIN_OS,
            }
        )
    result.sort(key=lambda v: v["date"] or "", reverse=True)
    return result


def main():
    data = sys.stdin.read().strip()
    # `gh api --paginate` prints one JSON array per page
    releases = []
    for chunk in re.split(r"\]\s*\[", data):
        chunk = chunk if chunk.startswith("[") else "[" + chunk
        chunk = chunk if chunk.endswith("]") else chunk + "]"
        releases += json.loads(chunk)
    app = dict(APP, versions=versions(releases))
    json.dump(dict(SOURCE, apps=[app], news=[]), sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
