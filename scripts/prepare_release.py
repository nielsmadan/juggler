import re
import sys
from pathlib import Path


def replace(path, pattern, replacement):
    path = Path(path)
    content, count = re.subn(pattern, replacement, path.read_text())
    if not count:
        raise SystemExit(f"Could not update {path}.")
    path.write_text(content)


action, value = sys.argv[1:]
if action == "version":
    replace(
        "Juggler.xcodeproj/project.pbxproj",
        r"MARKETING_VERSION = [^;]+;",
        f"MARKETING_VERSION = {value};",
    )
elif action == "revision":
    replace(
        "juggler/Views/SettingsView.swift",
        r'installRevision = "[0-9a-f]{40}"',
        f'installRevision = "{value}"',
    )
    replace(
        "scripts/install-remote.sh", r"JUGGLER_REVISION:-[0-9a-f]{40}", f"JUGGLER_REVISION:-{value}"
    )
else:
    raise SystemExit(f"Unknown preparation step: {action}")
