#!/usr/bin/env python3
"""Extract candidate image URLs from an HTML file.

Reads HTML from stdin (or from the file given as argv[1]) and prints one URL
per line for every <img> element whose src/data-src attribute ends in a
known image extension.  Used by vdl's --images feature.

Rules:
  * Only <img> tags are considered.
  * data-rotate-src (grid thumbnails) is ignored.
  * data: URIs are ignored.
  * HTML entities are unescaped; both quote styles and multi-line tags are
    handled by the HTML parser.
  * Cache-busting query strings are kept (the caller strips them).
"""

import html.parser
import re
import sys

EXTS = re.compile(r"\.(jpe?g|png|webp|gif)$", re.I)


class ImageExtractor(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.urls = []

    def handle_starttag(self, tag, attrs):
        if tag != "img":
            return
        attrs = dict(attrs)
        if "data-rotate-src" in attrs:
            return
        url = attrs.get("data-src") or attrs.get("src") or ""
        if url.lower().startswith("data:"):
            return
        if EXTS.search(url.split("?", 1)[0]):
            self.urls.append(url)


def main():
    if len(sys.argv) > 1:
        with open(sys.argv[1], "rb") as fh:
            data = fh.read().decode("utf-8", "replace")
    else:
        data = sys.stdin.buffer.read().decode("utf-8", "replace")
    parser = ImageExtractor()
    parser.feed(data)
    parser.close()
    seen = set()
    for url in parser.urls:
        if url not in seen:
            seen.add(url)
            print(url)


if __name__ == "__main__":
    main()
