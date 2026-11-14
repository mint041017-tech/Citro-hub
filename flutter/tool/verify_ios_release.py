"""Check exported signing, platform support and version before uploading."""

import hashlib
import json
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def verify(ipa, version, build):
    targets = []
    with tempfile.TemporaryDirectory() as directory, zipfile.ZipFile(ipa) as archive:
        if any(name.lower().endswith((".p8", ".p12")) for name in archive.namelist()):
            raise ValueError("Private signing credentials must not be inside the IPA")
        archive.extractall(directory)
        app, = (Path(directory) / "Payload").glob("*.app")
        expected = {"com.chimu.crew", "com.chimu.crew.TimerWidget", "com.chimu.crew.ShareExtension"}
        for bundle in [app, *sorted((app / "PlugIns").glob("*.appex"))]:
            info = plistlib.loads((bundle / "Info.plist").read_bytes())
            bundle_id = info["CFBundleIdentifier"]
            if info["CFBundleShortVersionString"] != version or str(info["CFBundleVersion"]) != build:
                raise ValueError(f"Version mismatch in {bundle_id}")
            if info["DTXcodeBuild"] != "27A9275":
                raise ValueError(f"Unexpected Xcode build in {bundle_id}")
            entitlements = plistlib.loads(subprocess.check_output(
                ["codesign", "-d", "--entitlements", "-", "--xml", str(bundle)]
            ))
            profile = plistlib.loads(subprocess.check_output(
                ["security", "cms", "-D", "-i", str(bundle / "embedded.mobileprovision")]
            ))
            if entitlements.get("get-task-allow") or "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices"):
                raise ValueError(f"Expected App Store distribution signing in {bundle_id}")
            if bundle_id in {"com.chimu.crew", "com.chimu.crew.ShareExtension"}:
                if "group.com.chimu.crew" not in entitlements.get("com.apple.security.application-groups", []):
                    raise ValueError(f"Missing shared App Group in {bundle_id}")
            if bundle == app:
                if set(info["UIDeviceFamily"]) != {1, 2}:
                    raise ValueError("The release must support both iPhone and iPad")
                if entitlements.get("aps-environment") != "production":
                    raise ValueError("The release needs production APNs entitlement")
                if not (bundle / "PrivacyInfo.xcprivacy").exists():
                    raise ValueError("Missing app privacy manifest")
            subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True)
            targets.append(bundle_id)
        if set(targets) != expected:
            raise ValueError("Missing or unexpected app extension")
    receipt = {"status": "validated", "version": version, "build": build,
               "sha256": hashlib.sha256(ipa.read_bytes()).hexdigest(), "targets": targets}
    (ipa.parent / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt))


if __name__ == "__main__":
    verify(Path(sys.argv[1]), sys.argv[2], sys.argv[3])
