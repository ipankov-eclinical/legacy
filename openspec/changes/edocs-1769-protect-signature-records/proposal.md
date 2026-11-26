# Proposal

Jira: [EDOCS-1769](https://rtss.atlassian.net/browse/EDOCS-1769) · Bug · fix version SOMS-2027.1.0.0 · SOMS branch `release/SOMS-2027.1.0.0`

## Why

SOMS removes `tblDocumentSignature` rows with hard deletes that never check whether the signature was executed, and the edit-signers path does it in raw SQL, so no audit row is written. A signature or a signature request can vanish with nothing in the audit trail to prove it existed, which breaks Part 11 / ALCOA expectations for signed eDocs.

## What Changes

- A signed signature row (`DateSigned IS NOT NULL`) is never hard-deleted by the edit-signers, make-non-signable, or Delete Study paths.
- Removing an unsigned signer (edit signers, or making a document non-signable) cancels the request in place: the row is kept with `DateCancelled` set and `Deleted = 1` until the signer is added back, and an audit record names who cancelled it and when. The raw `delete from [table] …` statements in `Document::afterSave()` stop bypassing `Record`'s auditing.
- Delete Study (`Study::removeDocuments()`) keeps signed signature rows attached to the soft-deleted documents. It still permanently deletes pending (unsigned) requests, with an audit entry, as it does today.
- Re-adding a signer who was previously removed creates a fresh request (new `DateRequest`, notification sent). The cancelled request is never reopened: it is permanently deleted with an audit entry, because a signer can hold only one document request per document. Today the hard delete gives this behaviour implicitly. It must stay true once rows are no longer destroyed.
- Sign-on-the-Line entries for removed signers are deactivated on the edit-signers path. Today the lookup runs after the hard delete and always finds nothing, so they are never deactivated.
- SOMS reads that would otherwise show a cancelled request ignore it: the document form's signer list, pending-signature counts, Sign-on-the-Line signees, statement preselection and signing notifications. Signing a cancelled request through the web sign endpoint is refused. The list of reads comes from the audit in `design.md` ("SOMS reads without a `Deleted` filter").
- Document form UI: a signer who has signed shows no remove ("X") control. The server also refuses to remove a signed signer if one is submitted anyway.
- A read-only investigation report identifies existing orphaned signatures and orphaned pending requests, as input to a separate data-cleanup ticket.

The open questions were answered on the ticket on 2026-11-25 (see `design.md`, "Ticket decisions"). The eConsent paths are out of scope and move to a separate ticket for the Engage team.

## Capabilities

### New Capabilities
- `document-signature-records`: retention, removal, and audit rules for document signature records and signature requests in SOMS (who may remove what, what must survive, what must be audited).

### Modified Capabilities
- None. No specs exist yet.

## Impact

- `soms/app/models/Document.php`: `afterSave()` signer handling (`Signable == 1` and `Signable == 0` branches), `getSigners()`, `getSignatureRequestDocDetails()`.
- `soms/app/models/Study.php`: `removeDocuments()`.
- `soms/app/models/DocumentSignature.php`: cancelled-request guard in `validateSignature()`, and finders for the live request and the all-parties notification requesters.
- `soms/app/models/User.php`: `getTotalPendingSignatures()`.
- `soms/app/models/CTMS/SignOnTheLine/DocumentUser.php`: `getSignees()`.
- `soms/app/controllers/documents.php`: `POST /documents/signatures`, `GET /api/v1/documents/users/all`. `soms/app/controllers/api.php`: `GET /api/v1/documents/signature-statements`.
- `soms/app/comp/DocumentForm.jsx`, `soms/app/comp/ItemSelector.jsx` (shared by 6 components): per-row remove control.
- Not `soms/app/models/CTMS/EConsent/EConsent.php`: the eConsent paths are out of scope (separate Engage team ticket).
- No schema change: `DateCancelled` and `Deleted` already exist on `tblDocumentSignature`.
- Data: a read-only SQL report to be run on staging. No data fix in this change.
