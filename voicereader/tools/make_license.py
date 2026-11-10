#!/usr/bin/env python3
"""VoiceReader — offline license key generator.

Generates VR-XXXX-XXXX-XXXX-XXXX keys validated by the offline fallback in
assets/js/license.js. Gumroad is the primary verifier for real sales; these
keys are for your own offline demos, press copies, or gifting.

Usage:
    python tools/make_license.py                 # print 5 keys
    python tools/make_license.py -n 20           # print 20 keys
    python tools/make_license.py --secret "my-own-random-secret"

If you change --secret, also change OFFLINE_SECRET in assets/js/config.js
to the same value, or the keys will not validate.
"""
import argparse
import hashlib  # noqa: F401  (kept for future auditing)
import secrets

ALPH = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'
DEFAULT_SECRET = 'change-me-voicereader-secret'


def fnv1a(text: str) -> int:
    h = 0x811C9DC5
    for b in text.encode('utf-8'):
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def checksum(body: str, secret: str) -> str:
    h = fnv1a(f'{secret}:{body}')
    return ''.join(ALPH[(h >> (5 * i)) & 31] for i in range(4))


def make_key(secret: str) -> str:
    body = ''.join(secrets.choice(ALPH) for _ in range(12))
    parts = '-'.join((body[:4], body[4:8], body[8:12], checksum(body, secret)))
    return f'VR-{parts}'


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('-n', '--count', type=int, default=5, help='number of keys to print')
    ap.add_argument('--secret', default=DEFAULT_SECRET, help='must match OFFLINE_SECRET in assets/js/config.js')
    args = ap.parse_args()
    for _ in range(args.count):
        print(make_key(args.secret))


if __name__ == '__main__':
    main()
