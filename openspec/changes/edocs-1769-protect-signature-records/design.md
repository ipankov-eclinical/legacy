# Design

## Context

See `proposal.md` for the motivation and `specs/document-signature-records/spec.md` for the required behaviour. All paths below are in the `soms` repo on `release/SOMS-2027.1.0.0`.

Current removal paths for `tblDocumentSignature`:

| Path | Code | Signed-row check | Audited |
|---|---|---|---|
| Edit signers (`Signable == 1`) | `Document::afterSave()`: raw `update … set Deleted = 1` (L2082), loop re-sets `Deleted = 0` for kept signers, raw `delete … WHERE Deleted = 1` (L2119) | Only on the soft-delete step | No (raw SQL) |
| Make non-signable (`Signable == 0`) | Same pattern, L2159 / L2175 | Only on the soft-delete step | No (raw SQL) |
| Delete Study | `Study::removeDocuments()` L2422: `where('DocumentID = ?')->delete()` | None | Yes (`IAuditable` bulk delete) |
| Clear cart requests (`_clearcarts`) | `Document::afterSave()` L2182-2188 | `DateSigned IS NULL` | Yes |
| Cart removal | `Cart.php` L477-479 | `DateSigned IS NULL …` | Yes |
| eConsent deactivate | `EConsent::deactivate()` L286-288: all `CartID = 0` rows | None | Yes |
| eConsent signer sync | `EConsent::setupDocumentSignatures()` L903-907: `usersToRemove` | None | Yes |

Facts that shape the approach:

- `Record` audits a delete by primary key and a bulk `where()->delete()` on an `IAuditable` model, and audits `save()` as `'U'` with old and new values. `DocumentSignature` is `IAuditable`, so anything routed through the model is audited with the acting user, IP and URL. Only `raw()->query()` escapes this.
- The DoA audit triggers (EDOCS-1434) cover only the ten `tblDocumentDelegationLog*` tables. `tblDocumentSignature` has no trigger.
- `DateCancelled` already exists on `tblDocumentSignature`. eConsent partial signing (`documents.php` L5254-5258) already cancels a request with `DateCancelled = now`, `Deleted = 1` and `save()`.
- SOMS reads hide removed rows with `Deleted = 0` and ignore `DateCancelled`, apart from the expiry reminder query. eisf reads filter on both `Deleted = 0` and `DateCancelled IS NULL`.
- Edit signers is mark-and-sweep. Every save marks every unsigned row deleted, revives the ones still listed, then hard-deletes the rest. The Sign-on-the-Line lookup runs after the sweep, so it finds no rows and never deactivates anything. The make-non-signable branch has the order right.
- In the signer loop, the existing-request lookup is `DocumentID = ? AND UserID = ?` with no `Deleted` or `CartID` filter. Re-adding a removed signer creates a new request today only because the old row was destroyed.
- `ItemSelector.jsx` always renders a remove button for each selected row and has no per-row switch. It is shared by six components.

## Goals / Non-Goals

**Goals:**
- Route every write in the in-scope paths through the `DocumentSignature` model, so `Record` audits it. No raw SQL on `tblDocumentSignature` in these paths.
- Make the "signed rows are untouchable" rule hold structurally on the server, not only through the UI.
- Write audit rows for real removals only, not for signers who stay on the list.

**Non-Goals:**
- No DB trigger on `tblDocumentSignature` (see D1).
- No data cleanup. The orphan report is read-only, and cleanup is a separate ticket.
- No change to the cart paths: they are already guarded and audited.
- eisf: its signer cancel (`documentRepository.ts` ~L429) sets `DateCancelled` but not `Deleted = 1`, so SOMS reads would still show an eisf-cancelled signer as pending. This is a cross-system defect for a follow-up ticket, not this one. This change only makes SOMS treat `DateCancelled IS NOT NULL` rows as not live in the paths it touches.
- eConsent paths (`EConsent::deactivate()`, `EConsent::setupDocumentSignatures()`). Out of scope by ticket decision. They move to a separate ticket for the Engage team.

## Decisions

### D1. Audit through the model layer, not a trigger
Removals go through the `DocumentSignature` model, so `Record` writes the audit rows: signer removal cancels via `save()` (D7), and Delete Study uses the audited bulk delete (D5).
*Alternative:* add `tblDocumentSignature` to `DoaAuditTables`. Rejected for four reasons:
- A trigger records a delete but cannot prevent it, so the signed-row requirement would still need code.
- It stretches a DoA-scoped mechanism to an unrelated table.
- It needs a regeneration migration and drift-check coverage.
- It double-audits the paths that already go through `Record`, unless the delete-trigger bypass is verified for them.

### D2. Replace mark-and-sweep with a diff
New service in `app/Service/Signing/` (namespace `CTMS\App\Service\Signing`), split along the team convention:
- **Live-request reader**: loads the document's live non-cart, non-sheet requests (`CartID = 0`, `DateSheetSignature IS NULL`, `Deleted = 0`, `DateCancelled IS NULL`).
- **Signer-list differ**: a pure function. Given the live rows and the submitted signer IDs and statements, it returns `toRemove` (unsigned rows whose user is not listed), `toUpdateStatement` and `toAdd`. Signed rows are never placed in `toRemove`. This is where the guard lives.
- **Request remover**: cancels one row in place through the model (D7), and refuses a row with `DateSigned` set by throwing a `LogicException`, as defence in depth.

`Document::afterSave()` calls the service for both branches. For `Signable == 0`, every live unsigned row goes to `toRemove`.
*Why:* revival via audited `save()` would write two `'U'` rows per kept signer on every save, which floods the audit trail. The diff only touches rows that change. eisf already works this way.
*Alternative:* keep mark-and-sweep and only swap the final raw delete for an audited delete. Rejected: it keeps the revive dance and the Sign-on-the-Line ordering bug.

### D3. Existing-request lookup ignores removed rows
When adding a signer, the "do they already have a request" check ignores rows that are `Deleted = 1` or `DateCancelled IS NOT NULL`. A re-added signer then gets a new row, a new `DateRequest` and a notification, which meets spec "Re-adding a removed signer creates a new request". Matching for cart rows stays as it is today, to avoid changing who gets a duplicate non-cart request (see Risks).

### D4. Sign-on-the-Line deactivation driven by `toRemove`
`SignOnTheLine::deactivate()` is called for each user in `toRemove`, in both branches. This fixes the ordering bug without a separate query.

### D5. Delete Study deletes pending requests, never signed rows
`Study::removeDocuments()` keeps its audited bulk delete (`DocumentSignature::factory()->where(…)->delete()`, which writes a `'D'` audit row per deleted row through `IAuditable`), narrowed to `DateSigned IS NULL`. Pending requests are permanently deleted with an audit entry, as today. Signed rows are never touched and stay attached to the soft-deleted document. Every reader already filters `tblDocument.Deleted = 0`.
This path does not use the D2 request remover, because the decision here is to delete, not cancel. Its guard is therefore the `DateSigned IS NULL` condition in the `where()`, and an integration test pins it (task 4.1).
*Why:* ticket decision (OQ2 = B). The documents are soft-deleted, so their pending requests are no longer actionable, and the audit entry keeps the evidence.

### D6. Opt-in per-row remove control
`ItemSelector` gets an optional `canRemoveItem(item)` prop that defaults to always true, so the other five users are unchanged. `DocumentForm` passes `item => !(item.signer && item.signer.DateSigned)`. The server rule (D2) still holds if a tampered form drops a signed signer.

### D7. Signer removal cancels in place
Confirmed on the ticket (OQ1 = A). Removing an unsigned signer by editing the signer list or by making the document non-signable **cancels the request in place**: `DateCancelled = UTC now`, `Deleted = 1`, `save()`. `Record` audits it as `'U'` with old and new values, the acting user and the time. It keeps the row as evidence, matches the eConsent precedent, and is hidden by both SOMS (`Deleted`) and eisf (both columns) reads. A cancelled request is never reopened. Re-adding the signer creates a new row (D3).

### D8. Orphan investigation is a read-only report
SQL is run against staging with the read-only account, and results are attached to the ticket. Categories:
1. Live unsigned requests (`Deleted = 0`, `DateCancelled IS NULL`, `DateSigned IS NULL`) on documents that are deleted, non-signable, or in a deleted study.
2. Active Sign-on-the-Line placements (`tblDocumentSignOnTheLine.Active = 1`) whose user has no live request on that document. These come from the D4 ordering bug.
3. Signature rows whose `DocumentID` has no `tblDocument` row.
4. Evidence of destroyed signed rows:
   - `auditGeneric` `'D'` rows on `tblDocumentSignature` whose recorded `DateSigned` is non-null (Delete Study path).
   - Documents with a signed file or hash but no signed signature row (edit-signers path, which left no audit trace).
5. eisf-cancelled rows (`DateCancelled IS NOT NULL AND Deleted = 0`) that SOMS still treats as live. This sizes the eisf follow-up.

## Risks / Trade-offs

- [Cart-row matching in the signer loop: a user with a pending cart request currently matches that cart row] → D3 keeps cart matching unchanged and only excludes removed rows. A regression test covers "signer with a pending cart request is added to document signers".
- [Cancelled rows accumulate in `tblDocumentSignature`] → Every live-row query in the touched paths already filters `Deleted = 0`. Volume is bounded by how often signers are edited.
- [Other SOMS reads that select signatures without a `Deleted` filter would now see cancelled rows that used to be destroyed] → Task 1.3 audited these reads (see "SOMS reads without a `Deleted` filter"). The ones marked "fix here" are fixed in this change.
- [`ItemSelector` is shared] → The new prop is opt-in and defaults to the current behaviour. The existing `ItemSelector.test.js` is extended.
- [DB-dependent PHP tests are excluded from CI] → The differ is pure and unit-tested in CI. The paths that touch the database are covered by integration tests run locally and by the manual steps from the ticket.

## SOMS reads without a `Deleted` filter

Audit of every SOMS read of `tblDocumentSignature` / `DocumentSignature` (task 1.3, `release/SOMS-2027.1.0.0`, line numbers as of 2026-11-26). Reads that already filter `Deleted = 0` are not listed. Most of them do, including the `DocumentSignature` model helpers, `SignatureRequests`, `DocumentStudies`, the Signature Status report, the signing services and queue payload, `SignOnTheLine`, `Cart::loadSigners()`, and the reminder crons.

The rows this change newly keeps:

- **Cancelled requests** (D7): `Deleted = 1`, `DateCancelled` set, `DateSigned IS NULL`, `CartID = 0`. These are new for the edit-signers and non-signable paths. Until now the only rows of this shape came from eConsent partial signing.
- **Signed rows on documents soft-deleted by Delete Study** (D5). These are not new in kind: `Document::softDelete()` already leaves every signature row in place, so readers meet signed and pending rows on deleted documents today. No read is affected by this group.

Never-signed cancelled rows can't affect reads that only select `DateSigned IS NOT NULL`. Cart-scoped reads (`CartID = <cart>`) can't see them either, since they have `CartID = 0`.

| # | Read | What a cancelled row would do | Verdict |
|---|---|---|---|
| R1 | `Document::getSigners()` (`Document.php` L3420), which fills `_signers` / `_allSigners` in `afterFind` | The removed signer comes back in `DocumentForm` as a selected signer and is re-requested on the next save. They are also counted in `SignatureList.jsx` "N of M pending", and `PatientTracking` L1406 can pick them up. | **fix here** (task 6.1): `ds.Deleted = 0` |
| R2 | `User::getTotalPendingSignatures()` (`User.php` L937): the push-notification `totalPendingNotifications` count | The removed request is counted as pending | **fix here** (task 6.3): `tblDocumentSignature.Deleted = 0` |
| R3 | `DocumentUser::getSignees()` (`CTMS/SignOnTheLine/DocumentUser.php` L69): `LEFT JOIN` on doc+user, `CartID = 0` | Duplicate signee rows after remove and re-add, and the cancelled row's `Statement` is preselected in the Sign-on-the-Line viewer | **fix here** (task 6.4): `ds.Deleted = 0` in the join |
| R4 | `GET /api/v1/documents/users/all` (`controllers/documents.php` L6549): `isCurrentUserSigned` from `first()` on doc+user | After remove, re-add and sign, `first()` can return the cancelled row, so a signed user is reported as not signed in the SOTL viewer | **fix here** (task 6.5): read through `DocumentSignature::findLiveRequest()` (`Deleted = 0`) |
| R5 | `GET /api/v1/documents/signature-statements` (`controllers/api.php` L53): statement preselect on doc+user (mobile/Outlook) | Preselects the cancelled request's statement, which the client enforces when `lock_signature_statements` is on | **fix here** (task 6.5): read through `DocumentSignature::findLiveRequest()` |
| R6 | `POST /documents/signatures`, non-cart branch (`controllers/documents.php` L3974), plus `DocumentSignature::validateCartSignature()` L402: both load the request by posted `ID` only | A stale page or crafted `ID` signs a cancelled request. Until now the row was destroyed, so there was nothing to sign. This breaks "A removed signature request is no longer actionable". | **fix here** (task 6.2): `validateSignature()` refuses when `Deleted = 1` or `DateCancelled IS NOT NULL`. This covers the non-cart branch only. `validateCartSignature()` stays as is because the cart sign paths share it (`api.php` L1263, `documents.php` L3886), and cart paths are a Non-Goal. |
| R7 | `POST /documents/signatures`, all-parties notification (`controllers/documents.php` L4036): requesters with `AllPartiesNotification = 0` | A user whose only request was cancelled gets "Document Signed by All Parties", and the flag is written onto the cancelled row | **fix here** (task 6.6): read through a `DocumentSignature` finder with `Deleted = 0` |
| R8 | `Document::getSignatureRequestDocDetails()` (`Document.php` L735): `LEFT JOIN`, latest `DateRequest` wins. Used by `notifyUser()` from `afterSave()` and the `DocSignatureExpiration` reminder cron. | A reminder can name the requester and date of a cancelled request | **fix here** (task 6.3): `tblDocumentSignature.Deleted = 0` in the join |
| R9 | `Document::afterSave()` existing-request lookup (`Document.php` L2089) | Re-added signer matches the cancelled row | fix here: already task 5.3 (D3) |
| R10 | `Document::afterSave()` post-sweep `Deleted = 1` lookup (`Document.php` L2122) | n/a | fix here: replaced by tasks 5.1 / 5.4 (D4) |
| R11 | `Document::beforeSave()` signed-signature check (`Document.php` L1994) | Selects `DateSigned IS NOT NULL` only | unaffected |
| R12 | `controllers/users.php` L47, L72: delegate and document signers | Select `DateSigned IS NOT NULL` only | unaffected |
| R13 | `Cart::getBulkSignDocuments()` L194, `Cart::getDocumentSignatures()` L856, `controllers/carts.php` L343, `api.php` `loadSignatureRecord()` L1327, `controllers/audit.php` L74 | Scoped to a cart ID > 0 | unaffected |
| R14 | `GET /documents/signature-statements` (`controllers/documents.php` L29): preselect by request `ID` + own `UserID` | The `ID` comes from the user's pending list, which filters `Deleted = 0`. A stale ID only preselects a statement, and signing is guarded by R6. | unaffected |
| R15 | `AttachSignaturePages::prepareSignaturesPageData()` L112 / L124: back-fills `UserName` / `FullName` | Name fields only. Cancelled rows got them at creation (`populateUserFields()`). | unaffected |
| R16 | Audit readers: `DocumentAuditRepository::signatureIDs()` L32, `AuditHelper::getDocumentSignatures()` L2051, `DocumentSignatureAuditor`, `User.php` L2897 | Including cancelled rows is what we want: their `'U'` cancellation entries appear in the document's audit trail | unaffected |
| R17 | ICF/eConsent consent children: `PatientTracking::getDocumentSignatures()` L918, `PatientTracking::getCancelledDocuments()` L1073 (`tds.Deleted = 1` means "cancelled consent"), `documents.php` L5255 (partial signing), `EConsent.php` L873 / L1064 / L1261 and its `ds` joins | These read rows on patient consent child documents, which only the eConsent/ICF paths write (out of scope). Edit signers runs on the folder's version documents. If 9.2 shows edit signers can reach a consent child, `getCancelledDocuments()` would list it as a cancelled consent. | unaffected |

Writes found along the way, for the record: `DocumentSignature::updateDateEmailReminder()` (L104) is a raw `UPDATE` keyed on user+document, so it also stamps `DateEmailReminder` on that user's cancelled rows. It is unaudited, harmless to reads, and left as is.

## Migration Plan

- No schema migration.
- Deploys with the SOMS-2027.1.0.0 release. Rollback is a code revert. Rows cancelled in the meantime stay cancelled, and old code still hides them (`Deleted = 1`).
- Run the orphan report before release so the cleanup ticket can be sized.

## Ticket decisions

The open questions were posted on EDOCS-1769 on 2026-11-24. Nathan Levens answered on 2026-11-25, after agreeing them with Jaime.

- **OQ1: How removing an unsigned signer is recorded → A, cancel the request and write an audit entry.** Removing and then re-adding the same signer creates a new request with a new request date and a new notification. The cancelled request is never reopened. → D7, D3, task 3.3.
- **OQ2: What Delete Study does with signature records → B for pending requests.** Pending requests are permanently deleted with an audit entry. Signed signatures are no longer deleted and stay attached to the soft-deleted documents. → D5, task 4.2.
- **OQ3: eConsent paths → out of scope.** They move to a separate ticket for the Engage team. Christopher Wilk (or the team) creates it, and Nathan notifies the Engage team. → Non-Goals.

An earlier comment from Nathan (2026-11-17) asked that the form show no "X" for a signer who has signed (D6), and that removing a pending signer really cancel the request instead of leaving it hanging (D2, D4, D7, and categories 1–2 of the D8 report).
