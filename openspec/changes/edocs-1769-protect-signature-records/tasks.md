# Tasks

All code paths are in `soms/` on `release/SOMS-2027.1.0.0`. Run commands from `soms/` unless noted.

## 1. Decisions and groundwork

- [ ] 1.1 Post OQ1, OQ2 and OQ3 from `design.md` on EDOCS-1769. Verify: the comment is visible on the ticket.
- [ ] 1.2 Record the answers in `design.md`: replace each Open Question with a decision, update D5/D7, and drop group 6 if OQ3 is out of scope. Verify: `openspec validate edocs-1769-protect-signature-records` passes and no Open Question is left unanswered. **Groups 3.3, 4.2 and 6 must not start before this.**
- [ ] 1.3 List every SOMS read of `tblDocumentSignature` / `DocumentSignature` that selects rows without a `Deleted = 0` filter, and note in `design.md` which would surface rows that are now kept (cancelled or signed on deleted documents). Verify: the list is in `design.md` and each entry is marked "fix here" or "unaffected".

## 2. Signer-list differ (pure logic)

- [ ] 2.1 Add the signer-list differ in `app/Service/Signing/` (namespace `CTMS\App\Service\Signing`). Given the live rows and the submitted signer IDs and statements, it returns `toRemove`, `toUpdateStatement` and `toAdd`. Rows with `DateSigned` set are never in `toRemove`, and the statement of a signed row is never changed. Verify: `vendor/bin/phpunit tests/php/Unit/App/Service/Signing/<Differ>Test.php` covers signed-not-listed, pending-not-listed, pending-kept-with-new-statement, new signer, and an empty list (non-signable).
- [ ] 2.2 Treat signer IDs below 1 as absent, matching today's loop. Verify: unit test case in the same file.

## 3. Request reading and removal

- [ ] 3.1 Add the live-request reader: non-cart (`CartID = 0`), non-sheet (`DateSheetSignature IS NULL`), `Deleted = 0`, `DateCancelled IS NULL`. Verify: integration test under `tests/php/Integration/Services/` seeds live, cancelled, deleted, cart and sheet rows and gets only the live ones back (run locally against the docker DB, since this suite is excluded from CI).
- [ ] 3.2 Add the request remover. It operates on a `DocumentSignature` instance and throws `LogicException` for a row with `DateSigned` set. Verify: unit test asserts the throw and asserts that no write happens.
- [ ] 3.3 Implement the removal as decided in OQ1: cancel in place (`DateCancelled = UTC now`, `Deleted = 1`, `save()`) or delete by PK. Verify: integration test asserts the row state and an `auditGeneric` entry for `tblDocumentSignature` with the acting user ID and timestamp.

## 4. Delete Study

- [ ] 4.1 Narrow `Study::removeDocuments()` so signed rows are never written. Verify: integration test under `tests/php/Integration/Model/` deletes a study with one signed and one pending row, and the signed row is unchanged.
- [ ] 4.2 Apply the OQ2 decision to the unsigned rows (remover from 3.3, audited delete, or untouched). Verify: the same test asserts the unsigned row's final state and its audit entry, if any.

## 5. Edit signers / non-signable (`Document::afterSave()`)

- [ ] 5.1 Replace the `Signable == 1` mark-and-sweep (raw update L2082, revive loop, raw delete L2119, post-sweep Sign-on-the-Line lookup) with: read live rows, then diff, then remove `toRemove`, update statements, and insert `toAdd`. Keep notifications, `SignatureRequester` on the first request, and `ViewBeforeSigning` handling as they are. Verify: integration test reproduces the ticket steps (A signed, B pending, B removed). A is unchanged, B is removed per OQ1 with an audit entry, and no raw SQL on `tblDocumentSignature` remains in the branch (`grep -n "raw(" app/models/Document.php` shows no signature statements).
- [ ] 5.2 Replace the `Signable == 0` branch (L2159–L2175) with the same remover over every live unsigned row. Verify: integration test makes a document with A signed and B pending non-signable. A is unchanged and B is removed with an audit entry.
- [ ] 5.3 Make the existing-request lookup for added signers ignore rows that are `Deleted = 1` or `DateCancelled IS NOT NULL`, and leave cart-row matching as it is (D3). Verify: integration tests show (a) remove B, re-add B: a new row with a new `DateRequest` and the notification is triggered; (b) a signer with a pending cart request added to document signers behaves the same as before the change.
- [ ] 5.4 Deactivate Sign-on-the-Line for each user in `toRemove`, in both branches (D4). Verify: integration test shows an active `tblDocumentSignOnTheLine` row for B becomes `Active = 0` after B is removed.

## 6. eConsent paths (only if OQ3 = in scope)

- [ ] 6.1 Guard `EConsent::setupDocumentSignatures()` `usersToRemove` so signed rows are kept and unsigned rows use the remover. Verify: integration test with a signed and a pending eConsent signer removed from the list.
- [ ] 6.2 Apply the product decision for `EConsent::deactivate()` to signed rows. Verify: integration test asserts the signed rows' state after deactivate matches the decision recorded in `design.md`.

## 7. Document form UI

- [ ] 7.1 Add an optional `canRemoveItem(item)` prop to `app/comp/ItemSelector.jsx` that defaults to removable. When it returns false, no remove button is rendered for that row. Verify: `npm test -- app/comp/ItemSelector.test.js` has cases for the default (button present) and for false (button absent).
- [ ] 7.2 Pass `canRemoveItem` from `app/comp/DocumentForm.jsx` so signers with `DateSigned` have no remove control, while pending and newly selected signers keep it. Verify: a jest test for the signer selector covers all three rows, and on the docker stack the signed signer shows "(signed …)" with no X.

## 8. Orphan investigation report (read-only)

- [ ] 8.1 Write the read-only SQL for the five categories in design D8, kept in this change folder as `orphan-report.sql`. Verify: each query runs without error against the local docker DB.
- [ ] 8.2 Run the report on staging with the read-only account for the agreed sites, and attach the counts and a sample of IDs to EDOCS-1769 as input for a cleanup ticket. Verify: comment on the ticket with the results.

## 9. Integration checks

- [ ] 9.1 Static checks and CI suites pass: `composer test:unit`, `composer analyze`, `composer phpcs`, `npm test`.
- [ ] 9.2 Run the ticket's steps on the local docker stack (`bash docker/up.sh` from `legacy/`), including Delete Study. Confirm `tblDocumentSignature` and `auditGeneric` match the spec scenarios, and that a removed signer no longer appears as pending in eISF (open eDocs from the study).

## Workflow follow-up

- Raise a follow-up ticket: the eisf signer cancel sets `DateCancelled` without `Deleted = 1`, so SOMS still shows those signers as pending (design Non-Goals; size it with report category 5).
- Raise a separate ticket for eConsent if OQ3 comes back out of scope.
- Archive the change after the SOMS PR merges.
