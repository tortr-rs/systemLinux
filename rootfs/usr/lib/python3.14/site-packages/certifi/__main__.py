import argparse

from certifi import contents, where, __version__


parser = argparse.ArgumentParser(prog="certifi-system-store")
parser.add_argument("-c", "--contents", action="store_true")
parser.add_argument("-v", "--verbose", action="store_true")
parser.add_argument("--system-store", action="store_true")
args = parser.parse_args()

if args.verbose:
    print(f"certifi-system store {__version__}")

if args.contents:
    print(contents())
else:
    print(where())
