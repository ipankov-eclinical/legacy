# Proposal

Jira: [EDOCS-1769](https://rtss.atlassian.net/browse/EDOCS-1769) · Bug · fix version SOMS-2027.1.0.0 · SOMS branch `release/SOMS-2027.1.0.0`

## Why

SOMS removes `tblDocumentSignature` rows with hard deletes that never check whether the signature was executed, and the edit-signers path does it in raw SQL, so no audit row is written. A signature or a signature request can vanish with nothing in the audit trail to prove it existed, which breaks Part 11 / ALCOA expectations for signed eDocs.

## What Changes

- A signed signature row (`DateSigned IS NOT NULL`) is never hard-deleted by the edit-signers, make-non-signable, or Delete Study paths.
- Removing an unsigned signer (edit signers, or making a document non-signable) leaves an audit record naming who removed it and when. The raw `delete from [table] …` statements in `Document::afterSave()` stop bypassing `Record`'s auditing.
- Delete Study (`Study::removeDocuments()`) keeps signed signature rows.
- Re-adding a signer who was previously removed creates a fresh request (new `DateRequest`, notification sent) rather than silently reviving the removed row. Today the hard delete gives this behaviour implicitly. It must stay true once rows are no longer destroyed.
- Sign-on-the-Line entries for removed signers are deactivated on the edit-signers path. Today the lookup runs after the hard delete and always finds nothing, so they are never deactivated.
- Document form UI: a signer who has signed shows no remove ("X") control. The server also refuses to remove a signed signer if one is submitted anyway.
- A read-only investigation report identifies existing orphaned signatures and orphaned pending requests, as input to a separate data-cleanup ticket.

How a removed unsigned row is represented (cancelled in place vs. audited delete), what Delete Study does with unsigned rows, and whether the eConsent paths are in scope are **open questions** awaiting confirmation on the ticket (see `design.md`).

## Capabilities

### New Capabilities
- `document-signature-records`: retention, removal, and audit rules for document signature records and signature requests in SOMS (who may remove what, what must survive, what must be audited).

### Modified Capabilities
- None. No specs exist yet.

## Impact

- `soms/app/models/Document.php`: `afterSave()` signer handling (`Signable == 1` and `Signable == 0` branches).
- `soms/app/models/Study.php`: `removeDocuments()`.
- `soms/app/comp/DocumentForm.jsx`, `soms/app/comp/ItemSelector.jsx` (shared by 6 components): per-row remove control.
- Possibly `soms/app/models/CTMS/EConsent/EConsent.php`, depending on the open eConsent question.
- No schema change: `DateCancelled` and `Deleted` already exist on `tblDocumentSignature`.
- eisf: no code change. Its signature reads already filter `Deleted = 0 AND DateCancelled IS NULL`.
- Data: a read-only SQL report to be run on staging. No data fix in this change.
