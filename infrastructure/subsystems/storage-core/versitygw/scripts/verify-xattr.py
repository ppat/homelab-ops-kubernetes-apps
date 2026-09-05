#!/usr/bin/env python3
"""Fail the pod unless the gateway root can actually store extended attributes.

The gateway's own startup check refuses ENOTSUP. What it misses is a tree it can
read attributes from and not write them to -- reachably a read-only mount, where
it starts clean, serves reads and fails at the first PUT with a generic
InternalError. So the CREATE is the point of this check, not incidental to it.
"""

import errno
import os
import sys

ATTR = "user.versitygw-probe"
VALUE = b"versitygw-xattr-probe"
PROBE_FILE = ".versitygw-xattr-probe"

def fail(message):
    print("FAIL: " + message, file=sys.stderr)
    sys.exit(1)

def describe(exc):
    name = errno.errorcode.get(exc.errno, str(exc.errno))
    hints = {
        errno.ENOTSUP: "the filesystem does not support user extended attributes",
        errno.EOPNOTSUPP: "the filesystem does not support user extended attributes",
        errno.EROFS: "the mount is read-only",
        errno.EACCES: "the gateway uid lacks permission",
        errno.EPERM: "the gateway uid lacks permission",
        errno.ENOSPC: "no space left for extended attributes",
        errno.EDQUOT: "the quota for extended attributes is exhausted",
    }
    hint = hints.get(exc.errno)
    return "%s (%s)" % (name, hint) if hint else name

def roundtrip(path, what):
    try:
        os.setxattr(path, ATTR, VALUE)
    except OSError as exc:
        fail("cannot write an extended attribute to the %s %s: %s" % (what, path, describe(exc)))
    try:
        got = os.getxattr(path, ATTR)
    except OSError as exc:
        fail("wrote an extended attribute to the %s %s but cannot read it back: %s" % (what, path, describe(exc)))
    if got != VALUE:
        fail("extended attribute on the %s %s read back as %r, expected %r" % (what, path, got, VALUE))
    try:
        os.removexattr(path, ATTR)
    except OSError as exc:
        fail("cannot remove the probe extended attribute from the %s %s: %s" % (what, path, describe(exc)))
    print("ok: extended attributes are writable on the %s %s" % (what, path))

def main():
    root = os.environ.get("VERSITYGW_GATEWAY_ROOT")
    if not root:
        fail("VERSITYGW_GATEWAY_ROOT is not set")
    if not os.path.isdir(root):
        fail("the gateway root %s does not exist or is not a directory" % root)

    probe = os.path.join(root, PROBE_FILE)
    try:
        os.unlink(probe)
    except FileNotFoundError:
        pass
    except OSError as exc:
        fail("the gateway root %s is not writable (while clearing any leftover probe file): %s"
             % (root, describe(exc)))

    try:
        fd = os.open(probe, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        os.close(fd)
    except OSError as exc:
        fail("cannot create a file in the gateway root %s: %s" % (root, describe(exc)))

    try:
        roundtrip(probe, "file")
        roundtrip(root, "directory")
    finally:
        try:
            os.unlink(probe)
        except OSError as exc:
            fail("cannot remove the probe file %s: %s" % (probe, describe(exc)))

    print("ok: gateway root %s can store per-object and per-bucket metadata" % root)

if __name__ == "__main__":
    main()
