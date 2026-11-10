import argparse
import re
from pathlib import Path

RELEASE_VERSION = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")
CHANNEL_END = "    </channel>"


def add_release(content, version, length, signature, pub_date):
    if not RELEASE_VERSION.fullmatch(version):
        raise ValueError(f"Invalid release version: {version}")
    if not length.isdigit() or not signature:
        raise ValueError("The update needs its byte length and EdDSA signature")
    if f"<sparkle:version>{version}</sparkle:version>" in content:
        return None
    if content.count(CHANNEL_END) != 1:
        raise ValueError("Expected one closing channel element in the appcast")
    url = f"https://github.com/nielsmadan/juggler/releases/download/v{version}/Juggler.zip"
    item = (
        "        <item>\n"
        f"            <title>Version {version}</title>\n"
        f"            <sparkle:version>{version}</sparkle:version>\n"
        f"            <pubDate>{pub_date}</pubDate>\n"
        f'            <enclosure url="{url}" length="{length}" type="application/octet-stream"'
        f' sparkle:edSignature="{signature}" />\n'
        "        </item>\n"
    )
    return content.replace(CHANNEL_END, item + CHANNEL_END)


def main():
    parser = argparse.ArgumentParser(description="Add a Juggler release to the Sparkle appcast.")
    parser.add_argument("appcast", type=Path)
    parser.add_argument("version")
    parser.add_argument("length")
    parser.add_argument("signature")
    parser.add_argument("pub_date")
    args = parser.parse_args()
    updated = add_release(args.appcast.read_text(), args.version, args.length, args.signature,
                          args.pub_date)
    if updated is None:
        print("present")
        return
    args.appcast.write_text(updated)
    print("added")


if __name__ == "__main__":
    main()
