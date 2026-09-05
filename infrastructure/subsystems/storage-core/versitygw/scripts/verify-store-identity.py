#!/usr/bin/env python3
"""Refuse to start unless this volume is the prepared object store.

The in-tree iSCSI plugin identifies its device by portal, IQN and LUN index
alone, then calls FormatAndMount -- so the kubelet FORMATS an unformatted device
silently, raising no Kubernetes event. A blank device re-presented at the same
address yields a healthy-looking store serving zero objects.

Three properties, each of which someone will be tempted to change:

- **It never creates or repairs the file.** "If absent, create it" passes every
  freshly reformatted volume, and it is the cheap resolution reached for when a
  new store's first deploy is blocked.
- **It reads the PVC root, not the gateway root.** A file at the top of the
  gateway root is enumerated as a bucket, so the root credential could delete
  the check's own evidence.
- **It asserts `store_id`, not the device's WWID.** `store_id` identifies the
  tree and survives a clone; a WWID necessarily differs on one, so it would go
  red during the one operation this exists to protect.
"""

import os
import re
import sys

SENTINEL_ENV = "VERSITYGW_STORE_IDENTITY"

STORE_ID_KEY = "store_id"
STORE_ID_PATTERN = re.compile(r"^[0-9a-f]{32}$")

def fail(message):
    print("FAIL: " + message, file=sys.stderr)
    sys.exit(1)

def parse(text, path):
    """Parse `key=value` lines, rejecting anything else.

    A lenient parser turns a corrupted sentinel into a partially-read one, and
    the field this check depends on is the one that would go missing.
    """
    fields = {}
    for number, line in enumerate(text.splitlines(), start=1):
        if not line.strip():
            continue
        if "=" not in line:
            fail(
                "the store-identity sentinel %s is malformed at line %d: %r is not key=value.\n"
                "         The sentinel is written once when the filesystem is prepared and is not\n"
                "         edited afterwards, so a line like this means the file was hand-modified\n"
                "         or truncated -- neither of which this check will guess its way past."
                % (path, number, line)
            )
        key, _, value = line.partition("=")
        fields[key.strip()] = value.strip()
    return fields

def main():
    path = os.environ.get(SENTINEL_ENV)
    if not path:
        fail("%s is not set" % SENTINEL_ENV)

    if not os.path.isfile(path):
        root = os.path.dirname(path)
        try:
            present = ", ".join(sorted(os.listdir(root))) or "(nothing)"
        except OSError as exc:
            present = "(unreadable: %s)" % exc
        fail(
            "the store-identity sentinel %s is missing.\n"
            "\n"
            "         This check cannot tell you which of the two situations below you are in,\n"
            "         because on disk a brand-new store and a silently reformatted one look\n"
            "         identical. That is the entire reason this file exists. You know which it\n"
            "         is; the volume does not.\n"
            "\n"
            "         The volume root currently holds: %s\n"
            "\n"
            "         IF YOU ARE PROVISIONING A NEW STORE -- this is expected, and the sentinel\n"
            "         is written when the filesystem is prepared, before the gateway first runs.\n"
            "         Go and complete that preparation step (it sits alongside mkfs in the\n"
            "         operator runbook), then let this pod restart. Write it there, as part of\n"
            "         preparing the filesystem -- not from here, and never by changing this check\n"
            "         to create what it verifies, which would make every future blank volume pass.\n"
            "\n"
            "         IF THIS STORE WAS ALREADY SERVING -- do not create the file. The device\n"
            "         behind this volume is not your store. The in-tree iSCSI plugin finds its\n"
            "         device by portal, IQN and LUN index alone and formats an unformatted one\n"
            "         silently, with no Kubernetes event. Confirm the LUN mapping before\n"
            "         anything else." % (path, present)
        )

    try:
        with open(path) as handle:
            identity = handle.read()
    except OSError as exc:
        fail("cannot read the store-identity sentinel %s: %s" % (path, exc))

    if not identity.strip():
        fail("the store-identity sentinel %s is empty, so it identifies nothing" % path)

    fields = parse(identity, path)

    store_id = fields.get(STORE_ID_KEY)
    if store_id is None:
        fail(
            "the store-identity sentinel %s carries no `%s`, so it identifies a store but not\n"
            "         WHICH store -- and this check has nothing to verify.\n"
            "\n"
            "         Keys it does carry: %s\n"
            "\n"
            "         `%s` is generated once when the store is prepared and never regenerated,\n"
            "         which is what lets it survive a clone and still answer 'is this the store I\n"
            "         am recovering'. A sentinel without it was written by something that does not\n"
            "         conform to the pinned format. Do not add the key by hand to get past this:\n"
            "         a value invented now identifies nothing, and it would be indistinguishable\n"
            "         from a real one forever after."
            % (path, STORE_ID_KEY, ", ".join(sorted(fields)) or "(none)", STORE_ID_KEY)
        )

    if not STORE_ID_PATTERN.match(store_id):
        fail(
            "the store-identity sentinel %s has a malformed `%s`: %r.\n"
            "         Expected exactly 32 lowercase hex characters."
            % (path, STORE_ID_KEY, store_id)
        )

    print("ok: store identity present at %s, %s=%s" % (path, STORE_ID_KEY, store_id))
    for key in sorted(fields):
        print("     %s=%s" % (key, fields[key]))

if __name__ == "__main__":
    main()
