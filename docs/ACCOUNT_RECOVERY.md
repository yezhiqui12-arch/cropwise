# Account history and evidence recovery

## Implemented

- Account recovery imports database records before downloading evidence files.
- Snapshot discovery handles both legacy device filenames and timestamped
  snapshots. It reconciles each device's newest usable snapshot, with older
  snapshots available as fallbacks when the preferred copy cannot be read.
- Newer rows are reconciled transactionally. Pending local edits and newer
  deletion tombstones are preserved; invalid graphs roll back.
- Own cloud records and linked guest records fill missing history. Relational
  summaries are explicitly marked as recovered summaries: original plant
  observations cannot be recreated from aggregate metrics. Complete snapshots
  can replace untouched summaries. Summaries with added local observations stop
  automatic replacement rather than discarding those observations.
- Summary records are excluded from uploads that could overwrite complete
  assessment results or invent station counts.
- Evidence recovery uses an account-scoped durable queue. Individual failures
  do not block other photos or recovered records. Retries verify checksums and
  account/record identity, including account changes during downloads.
- Record snapshots can be uploaded and read back while a photo is unavailable.
  Separate record and media completion flags prevent reporting an incomplete
  recovery as complete. Existing automatic synchronization schedules retries.
- Active and saved Advisor conversations now join account snapshots, including
  answers, replies, model findings and photo references. Existing truncation
  at 100 active messages, 80 saved messages and 20 saved sessions was removed.
  Saved sessions merge individually with versioned deletion markers. Conflicting
  active conversations are retained as recovered saved sessions.
- Advisor photos are copied into managed storage with content-based filenames.
  Their portable paths are resolved on the restored installation; independent
  checksum-verified photo retries do not block conversation text recovery.
- Notification history is retained rather than regenerated as a temporary list.
  Histories and read IDs merge without duplicates. Follow-up intervals, Advisor
  sharing settings, and the detection preference join an explicit allowlist.
  Language and other Drift preferences already join database snapshots; language
  changes now have updated timestamps and the UI reloads restored preferences.
- Guest/account local views include these app data entries. Guest transfers copy
  them into the selected account, and other accounts start with separate state.
  Chat/settings changes schedule automatic backup even without a database edit.
  Authentication credentials and API keys are excluded from the allowlist.
- Sign-in now waits for essential records before opening the account. The same
  restoration gate covers returning signed-in launches. Stage descriptions,
  retry, and explicit access to prepared local account data replace unexplained
  empty screens. Sync starts after the first frame rather than waiting for an
  idle-priority startup task; photo transfer remains separate.
- Registered profiles show backup status, verification time, and a manual
  Verify backup action. A success label requires a read-back-verified snapshot,
  complete media manifests, verified photos, the same signed-in owner, and no
  intervening local changes. Local changes immediately invalidate verification.
  Manual verification checks existing cloud photos before uploading repairs.

## Compatibility and limits

The reader accepts snapshot formats 1 and 2; new snapshots use format 2. Older
app versions that accept only format 1 require an app update to read new copies.
No database migration or live Supabase write was performed during implementation.
Records or files that were never uploaded cannot be recovered by this change.
Snapshots created before this update have no Advisor/notification app-data
section. Chats and historical read state that were never uploaded cannot be
recreated after uninstall. The updated app must be installed and a complete
backup verified before relying on recovery after uninstall.

## Verification

Sixteen focused recovery and existing account-sync tests passed using in-memory
databases and local files/storage simulation. No live account was modified.
Twelve focused app-data, account-view and conversation checks also passed,
covering fresh installs, retention beyond the former limits, stale snapshots,
guest transfer, account isolation, record-free accounts, and photo checksum
retries. Verification is scoped to recovery; no full app build was run.
Eight focused restoration/verification and existing local sync checks passed;
the separate Advisor photo checksum/retry case passed as well. Static analysis
of the changed recovery, verification and UI files reported no issues.
