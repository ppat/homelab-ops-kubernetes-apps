#!/usr/bin/env python3
"""Validate a versitygw provisioning document and emit an execution plan.

Validating is separated from executing so a malformed or partial document
aborts BEFORE any account or bucket exists, rather than part-way through.
"""

import sys

import yaml

VALID_ROLES = ("user", "userplus", "admin")

def fail(message):
    print("FAIL: " + message, file=sys.stderr)
    sys.exit(1)

def require_list(document, key):
    if key not in document:
        fail("the provisioning document has no `%s` key" % key)
    value = document[key]
    if not isinstance(value, list) or not value:
        fail("`%s` must be a non-empty list, got %s" % (key, type(value).__name__))
    for index, entry in enumerate(value):
        if not isinstance(entry, dict):
            fail("`%s[%d]` must be a mapping, got %s" % (key, index, type(entry).__name__))
    return value

def require_field(entry, field, key, index):
    value = entry.get(field)
    if not isinstance(value, str) or not value.strip():
        fail("`%s[%d].%s` is missing or empty" % (key, index, field))
    return value.strip()

def main():
    raw = sys.stdin.read()
    if not raw.strip():
        fail("the provisioning document is empty")
    try:
        document = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        fail("the provisioning document is not valid YAML: %s" % exc)
    if not isinstance(document, dict):
        fail("the provisioning document must be a mapping, got %s" % type(document).__name__)

    accounts = require_list(document, "accounts")
    buckets = require_list(document, "buckets")

    plan = []
    seen_accounts = {}
    for index, entry in enumerate(accounts):
        access = require_field(entry, "access", "accounts", index)
        secret = require_field(entry, "secret", "accounts", index)
        role = require_field(entry, "role", "accounts", index)
        if role not in VALID_ROLES:
            fail("`accounts[%d].role` is %r, which the gateway does not accept; expected one of %s"
                 % (index, role, ", ".join(VALID_ROLES)))
        if access in seen_accounts:
            fail("access key %r is declared twice (accounts[%d] and accounts[%d]); which secret "
                 "and role should win is undefined" % (access, seen_accounts[access], index))
        seen_accounts[access] = index
        plan.append(("account", access, secret, role))

    seen_buckets = {}
    for index, entry in enumerate(buckets):
        name = require_field(entry, "name", "buckets", index)
        owner = require_field(entry, "owner", "buckets", index)
        if name in seen_buckets:
            fail("bucket %r is declared twice (buckets[%d] and buckets[%d]); the second would "
                 "reassign the first's owner" % (name, seen_buckets[name], index))
        seen_buckets[name] = index
        if owner not in seen_accounts:
            fail("bucket %r names owner %r, which is not a declared account. Ownership is the "
                 "isolation mechanism, so this would create a bucket no consumer can reach."
                 % (name, owner))
        plan.append(("bucket", name, owner))

    for row in plan:
        sys.stdout.write("\t".join(row) + "\n")

    print("ok: document valid -- %d account(s), %d bucket(s)" % (len(accounts), len(buckets)),
          file=sys.stderr)

if __name__ == "__main__":
    main()
