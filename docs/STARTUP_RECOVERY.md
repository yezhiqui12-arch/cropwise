# Startup and evidence recovery

main() mounts a startup gate immediately. Database/account preparation stays behind
that gate; a failure offers retry and disposes partial resources instead of exposing
an unprepared account view. Optional cloud identity connection continues after local
startup succeeds. Existing account switching and local record ownership remain in
force. An unresolved photo repair displays a dismissible notice, preserving access
to saved assessments without treating that photo as successfully restored.

A private pending-capture JSON journal bridges normalized verified files and their
SQLite registration. It records the expected session version, prior media ID,
checksums, dimensions and actor. It is published before the registration transaction.
Interrupted registration can be replayed after restart, only when the active account
view has the same session/assessment/actor and unchanged prior evidence. Repeated
replay does not duplicate media. Other account views leave the journal untouched.
Unresolved or corrupt descriptors/files remain private and are not swept as orphans.
A subsequently accepted newer photo can supersede an older unfinished save.

Journal creation follows successful photo normalization. An interruption before a
journal is published is not an acknowledged save; the original capture is retained
by the save path, but camera-cache lifetime remains platform-controlled. No promise
is made to recover a camera image that the OS discarded before durable staging.

Reconciliation completes interrupted main/thumbnail moves, regenerates missing
thumbnails from canonical images, preserves unfinished journaled staging files,
marks truly missing evidence for repair, and clears explicitly deleted tombstones'
private files. It runs after preparing the account view and when reopening fieldwork.
A local schema migration is unnecessary: capture sessions, media storage states and
transactions are retained; the new journal is a private filesystem descriptor.

Responsibilities extracted:
- startup gate and bootstrap resource ownership;
- prepared-capture store and evidence reconciliation service;
- per-photo screening checkpoint persistence;
- account snapshot store;
- results calculations, evidence widgets and map widgets.

Completion validators and the current fieldwork/navigation workflow are unchanged.
