#!/usr/bin/env python3
"""Confirm Pages serves the release metadata and download pages we deployed."""
import argparse
import os
from pathlib import Path
import tarfile
import time
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

PAGES = ('release.json', *(prefix + page for prefix in ('', 'en/', 'zh-CN/', 'zh-TW/')
                         for page in ('index.html', 'download.html', 'open-source.html')))


def expected_pages(artifact):
    with tarfile.open(artifact) as archive:
        members = {member.name.removeprefix('./'): member for member in archive.getmembers() if member.isfile()}
        if not all(name in members for name in PAGES):
            raise ValueError('Pages artifact is missing release metadata, a home/download page, or a legacy redirect')
        return {name: archive.extractfile(members[name]).read() for name in PAGES}


def fetch(url, timeout):
    request = Request(url, headers={'Cache-Control': 'no-cache', 'User-Agent': 'Quillside-release-verification'})
    with urlopen(request, timeout=timeout) as response:
        return response.read(2 * 1024 * 1024)


def verify(url, pages, timeout=420, interval=10):
    parsed = urlsplit(url)
    if parsed.scheme != 'https' or not parsed.netloc or parsed.query or parsed.fragment:
        raise ValueError('Expected the HTTPS Pages deployment URL')
    deadline = time.monotonic() + timeout
    last_error = 'No public response'
    while time.monotonic() < deadline:
        try:
            for name, expected in pages.items():
                remaining = max(0.1, deadline - time.monotonic())
                actual = fetch(url.rstrip('/') + '/' + name, min(20, remaining))
                if actual != expected:
                    raise ValueError(f'{name} does not yet match the deployed artifact')
            print('PASS: public release.json, localized home/download pages, and legacy redirects match the deployed artifact')
            return
        except (OSError, ValueError) as error:
            last_error = str(error)
            print(f'Waiting for Pages: {last_error}', flush=True)
        time.sleep(min(interval, max(0, deadline - time.monotonic())))
    raise ValueError(f'Public website verification timed out: {last_error}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--url', required=True)
    parser.add_argument('--artifact', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=420)
    args = parser.parse_args()
    verify(args.url, expected_pages(args.artifact), args.timeout)
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
            summary.write(f'Public website verified: [downloads]({args.url.rstrip("/")}/download.html). '
                          'Release metadata, localized home/download pages, and legacy redirects match the uploaded artifact.\n')


if __name__ == '__main__':
    main()
