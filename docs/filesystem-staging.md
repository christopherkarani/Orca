# Filesystem Staging

Aegis-mediated writes are staged for review when policy selects staged write mode. Staging records original and staged hashes, supports diff/apply/discard, and verifies expected original and staged content before apply.

Path handling normalizes workspace-relative paths, rejects traversal and absolute escapes, handles backslash separators, blocks symlink escapes, and applies built-in protected path rules for `.env`, SSH, cloud credentials, macOS browser/profile paths, and similar sensitive files.

This is not universal transparent filesystem interception. Code that writes outside Aegis staging can bypass staged review unless an active platform backend reports otherwise.

Known limitation: hardlinks are path-visible but do not reveal original source provenance to the path normalizer.
