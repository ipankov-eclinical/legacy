# Tasks

All code paths are in `soms/` on `release/SOMS-2027.1.0.0`. Run commands from `soms/` unless noted.

## 1. Decisions and groundwork

- [x] 1.1 Post OQ1, OQ2 and OQ3 from `design.md` on EDOCS-1769. Verify: the comment is visible on the ticket. (Posted 2026-11-24.)
- [x] 1.2 Record the answers in `design.md`: replace each Open Question with a decision, update D5/D7, and drop the eConsent group if OQ3 is out of scope. Verify: `openspec validate edocs-1769-protect-signature-records` passes and no Open Question is left unanswered. (Answered 2026-11-25: OQ1 = cancel, OQ2 = delete pending with audit, OQ3 = out of scope.)
- [x] 1.3 List every SOMS read of `tblDocumentSignature` / `DocumentSignature` that selects rows without a `Deleted = 0` filter, and note in `design.md` which would surface rows that are now kept (cancelled or signed on deleted documents). Verify: the list is in `design.md` and each entry is marked "fix here" or "unaffected".

## 2. Signer-list differ (pure logic)

- [x] 2.1 Add the signer-list differ in `app/Service/Signing/` (namespace `CTMS\App\Service\Signing`). Given the live rows and the submitted signer IDs and statements, it returns `toRemove`, `toUpdateStatement` and `toAdd`. Rows with `DateSigned` set are never in `toRemove`, and the statement of a signed row is never changed. Verify: `vendor/bin/phpunit tests/php/Unit/App/Service/Signing/<Differ>Test.php` covers signed-not-listed, pending-not-listed, pending-kept-with-new-statement, new signer, and an empty list (non-signable).
- [x] 2.2 Treat signer IDs below 1 as absent, matching today's loop. Verify: unit test case in the same file.

## 3. Request reading and removal

- [x] 3.1 Add the live-request reader: non-cart (`CartID = 0`), non-sheet (`DateSheetSignature IS NULL`), `Deleted = 0`, `DateCancelled IS NULL`. Verify: integration test under `tests/php/Integration/Services/` seeds live, cancelled, deleted, cart and sheet rows and gets only the live ones back (run locally against the docker DB, since this suite is excluded from CI).
- [x] 3.2 Add the request remover. It operates on a `DocumentSignature` instance and throws `LogicException` for a row with `DateSigned` set. Verify: unit test asserts the throw and asserts that no write happens.
- [x] 3.3 Implement the removal as cancel in place (D7): `DateCancelled = UTC now`, `Deleted = 1`, `save()`. Verify: integration test asserts that the row still exists with `DateCancelled` set and `Deleted = 1`, and that there is a `'U'` `auditGeneric` entry for `tblDocumentSignature` with the acting user ID and timestamp.

## 4. Delete Study

- [ ] 4.1 Narrow `Study::removeDocuments()` so signed rows are never written. Verify: integration test under `tests/php/Integration/Model/` deletes a study with one signed and one pending row, and the signed row is unchanged.
- [ ] 4.2 Keep permanently deleting the unsigned rows through the audited bulk `where(…)->delete()`, narrowed to `DateSigned IS NULL` (D5). Do not use the remover from 3.3 here. Verify: the same test asserts that the pending row no longer exists and that `auditGeneric` has a `'D'` entry for it with its values, the acting user ID and the timestamp.

## 5. Edit signers / non-signable (`Document::afterSave()`)

- [ ] 5.1 Replace the `Signable == 1` mark-and-sweep (raw update L2082, revive loop, raw delete L2119, post-sweep Sign-on-the-Line lookup) with: read live rows, then diff, then remove `toRemove`, update statements, and insert `toAdd`. Keep notifications, `SignatureRequester` on the first request, and `ViewBeforeSigning` handling as they are. Verify: integration test reproduces the ticket steps (A signed, B pending, B removed). A is unchanged, B is cancelled in place (D7) with an audit entry, and no raw SQL on `tblDocumentSignature` remains in the branch (`grep -n "raw(" app/models/Document.php` shows no signature statements).
- [ ] 5.2 Replace the `Signable == 0` branch (L2159–L2175) with the same remover over every live unsigned row. Verify: integration test makes a document with A signed and B pending non-signable. A is unchanged and B is cancelled with an audit entry.
- [ ] 5.3 Make the existing-request lookup for added signers ignore rows that are `Deleted = 1` or `DateCancelled IS NOT NULL`, and leave cart-row matching as it is (D3). Verify: integration tests show (a) remove B, re-add B: a new row with a new `DateRequest` and the notification is triggered; (b) a signer with a pending cart request added to document signers behaves the same as before the change.
- [ ] 5.4 Deactivate Sign-on-the-Line for each user in `toRemove`, in both branches (D4). Verify: integration test shows an active `tblDocumentSignOnTheLine` row for B becomes `Active = 0` after B is removed.

## 6. Reads that would show cancelled requests (design R1–R8)

- [ ] 6.1 R1: Filter `ds.Deleted = 0` in `Document::getSigners()` (fills `_signers` / `_allSigners`). Verify: integration test under `tests/php/Integration/Model/`: A signed, B pending, B removed. The reloaded document's `_signers` and `_allSigners` hold A and not B, and saving the reloaded signer list unchanged creates no request for B.
- [ ] 6.2 R6: In the non-cart sign path (`DocumentSignature::validateSignature()`, called only from `POST /documents/signatures`), refuse a request with `Deleted = 1` or `DateCancelled IS NOT NULL`: return a validation error and write nothing. Leave `validateCartSignature()` unchanged, since the cart sign paths share it. Verify: integration test under `tests/php/Integration/Model/`: B's cancelled request gets the error and the row is unchanged (`DateSigned` null, no new `auditGeneric` entry). A live pending request still validates.
- [ ] 6.3 R2, R8: Filter `Deleted = 0` in `User::getTotalPendingSignatures()` and in the signature join of `Document::getSignatureRequestDocDetails()`. Verify: integration test: A live (requested by X), B cancelled (requested by Y, later `DateRequest`). B's pending count is 0, and the document details name X as requester.
- [ ] 6.4 R3: Filter `ds.Deleted = 0` in the join in `DocumentUser::getSignees()`. Verify: integration test: B removed and re-added with a different statement. There is exactly one signee row for B, with the new statement.
- [ ] 6.5 R4, R5: Add `DocumentSignature::findLiveRequest(int $documentID, int $userID)` (`Deleted = 0`) and use it in `GET /api/v1/documents/users/all` (`controllers/documents.php`) and `GET /api/v1/documents/signature-statements` (`controllers/api.php`). Verify: integration test: B cancelled with statement S1, re-added with S2, then signed. The finder returns the live signed row with S2.
- [ ] 6.6 R7: Add a `DocumentSignature` finder for requesters still owed the all-parties notification (`Deleted = 0`, `AllPartiesNotification = 0`, grouped by `RequesterID`) and use it in `POST /documents/signatures`. Verify: integration test: requester Y, whose only request was cancelled, is not returned. Requester X is.

## 7. Document form UI

- [ ] 7.1 Add an optional `canRemoveItem(item)` prop to `app/comp/ItemSelector.jsx` that defaults to removable. When it returns false, no remove button is rendered for that row. Verify: `npm test -- app/comp/ItemSelector.test.js` has cases for the default (button present) and for false (button absent).
- [ ] 7.2 Pass `canRemoveItem` from `app/comp/DocumentForm.jsx` so signers with `DateSigned` have no remove control, while pending and newly selected signers keep it. Verify: a jest test for the signer selector covers all three rows, and on the docker stack the signed signer shows "(signed …)" with no X.

## 8. Orphan investigation report (read-only)

- [ ] 8.1 Write the read-only SQL for the four categories in design D8, kept in this change folder as `orphan-report.sql`. Verify: each query runs without error against the local docker DB.
- [ ] 8.2 Run the report on staging with the read-only account for the agreed sites, and attach the counts and a sample of IDs to EDOCS-1769 as input for a cleanup ticket. Verify: comment on the ticket with the results.

## 9. Integration checks

- [ ] 9.1 Static checks and CI suites pass: `composer test:unit`, `composer analyze`, `composer phpcs`, `npm test`.
- [ ] 9.2 Run the ticket's steps on the local stack (`./up.sh` from `legacy/`), including Delete Study. Confirm `tblDocumentSignature` and `auditGeneric` match the spec scenarios, and that a removed signer no longer appears as pending in SOMS or in the document form's signer list (R1).

## Workflow follow-up

- eConsent ticket for the Engage team (OQ3 out of scope): `EConsent::deactivate()` and `EConsent::setupDocumentSignatures()` destroy signed rows. Christopher Wilk (or the team) creates it, and Nathan Levens notifies the Engage team. It needs a product decision on what happens to existing signatures when eConsent is deactivated.
- Archive the change after the SOMS PR merges.
