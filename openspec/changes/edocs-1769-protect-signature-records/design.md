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
- eConsent paths, unless OQ3 brings them in.

## Decisions

### D1. Audit through the model layer, not a trigger
Removals go through `DocumentSignature` instances (`save()` or delete by PK, depending on OQ1), so `Record` writes the audit rows.
*Alternative:* add `tblDocumentSignature` to `DoaAuditTables`. Rejected for four reasons:
- A trigger records a delete but cannot prevent it, so the signed-row requirement would still need code.
- It stretches a DoA-scoped mechanism to an unrelated table.
- It needs a regeneration migration and drift-check coverage.
- It double-audits the paths that already go through `Record`, unless the delete-trigger bypass is verified for them.

### D2. Replace mark-and-sweep with a diff
New service in `app/Service/Signing/` (namespace `CTMS\App\Service\Signing`), split along the team convention:
- **Live-request reader**: loads the document's live non-cart, non-sheet requests (`CartID = 0`, `DateSheetSignature IS NULL`, `Deleted = 0`, `DateCancelled IS NULL`).
- **Signer-list differ**: a pure function. Given the live rows and the submitted signer IDs and statements, it returns `toRemove` (unsigned rows whose user is not listed), `toUpdateStatement` and `toAdd`. Signed rows are never placed in `toRemove`. This is where the guard lives.
- **Request remover**: applies the removal for one row through the model (OQ1 decides cancel vs. delete), and refuses a row with `DateSigned` set by throwing a `LogicException`, as defence in depth.

`Document::afterSave()` calls the service for both branches. For `Signable == 0`, every live unsigned row goes to `toRemove`.
*Why:* revival via audited `save()` would write two `'U'` rows per kept signer on every save, which floods the audit trail. The diff only touches rows that change. eisf already works this way.
*Alternative:* keep mark-and-sweep and only swap the final raw delete for an audited delete. Rejected: it keeps the revive dance and the Sign-on-the-Line ordering bug.

### D3. Existing-request lookup ignores removed rows
When adding a signer, the "do they already have a request" check ignores rows that are `Deleted = 1` or `DateCancelled IS NOT NULL`. A re-added signer then gets a new row, a new `DateRequest` and a notification, which meets spec "Re-adding a removed signer creates a new request". Matching for cart rows stays as it is today, to avoid changing who gets a duplicate non-cart request (see Risks).

### D4. Sign-on-the-Line deactivation driven by `toRemove`
`SignOnTheLine::deactivate()` is called for each user in `toRemove`, in both branches. This fixes the ordering bug without a separate query.

### D5. Delete Study never touches signed rows
`Study::removeDocuments()` narrows its signature write to `DateSigned IS NULL`. What happens to those unsigned rows depends on OQ2. The provisional default is the same remover as D2. Signed rows stay attached to the soft-deleted document, and every reader already filters `tblDocument.Deleted = 0`.

### D6. Opt-in per-row remove control
`ItemSelector` gets an optional `canRemoveItem(item)` prop that defaults to always true, so the other five users are unchanged. `DocumentForm` passes `item => !(item.signer && item.signer.DateSigned)`. The server rule (D2) still holds if a tampered form drops a signed signer.

### D7. Provisional default for OQ1: cancel in place
Until the ticket answers, the plan assumes **cancel in place**: `DateCancelled = UTC now`, `Deleted = 1`, `save()`. It keeps the row as evidence, matches the eConsent precedent, and is hidden by both SOMS (`Deleted`) and eisf (both columns) reads. If OQ1 comes back as "audited delete", only the request remover changes. D2, D3 and D4 stay as they are.

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
- [Other SOMS reads that select signatures without a `Deleted` filter would now see cancelled rows that used to be destroyed] → Task 1.3 audits these reads, and any that matter are fixed in this change.
- [`ItemSelector` is shared] → The new prop is opt-in and defaults to the current behaviour. The existing `ItemSelector.test.js` is extended.
- [DB-dependent PHP tests are excluded from CI] → The differ is pure and unit-tested in CI. The paths that touch the database are covered by integration tests run locally and by the manual steps from the ticket.

## Migration Plan

- No schema migration.
- Deploys with the SOMS-2027.1.0.0 release. Rollback is a code revert. Rows cancelled in the meantime stay cancelled, and old code still hides them (`Deleted = 1`).
- Run the orphan report before release so the cleanup ticket can be sized.

## Open Questions

**These block apply. They are written to be posted on EDOCS-1769, and each answer maps to a specific task.**

**OQ1: How should removing an unsigned signer be recorded?** (task 3.3)
> When a user removes a signer whose request is still pending (by editing the signer list or by making the document non-signable), SOMS currently deletes the request row permanently and writes no audit entry. Which behaviour do we want?
> **A. Cancel the request (recommended):** keep the row, mark it cancelled with the date, and record who cancelled it and when in the audit trail. The request stays visible as history and can be reported on. eISF already handles removed signers this way.
> **B. Delete with an audit entry:** keep deleting the row, but write an audit entry with all of its values, who removed it and when. The audit trail would then be the only evidence the request existed.
> Either way, removing and later re-adding the same signer creates a new request with a new request date and notification.

**OQ2: What should Delete Study do with signature records?** (task 4.2)
> When a study is deleted, its documents are soft-deleted, but every signature record on them, signed or not, is permanently deleted (with an audit entry). The ticket says signed records must be kept. For **unsigned (pending)** requests on those documents, which behaviour do we want?
> **A. Cancel them (recommended):** same as removing a signer (see OQ1). They are kept as cancelled and audited.
> **B. Delete them:** permanently deleted with an audit entry, which is what happens today.
> **C. Leave them as they are:** not touched. They are not actionable anyway because the document is deleted.
> Please also confirm that signed records stay attached to the deleted study's documents, unchanged.

**OQ3: Are the eConsent paths in scope for this ticket?** (task 6)
> Two eConsent flows also permanently delete signature records without checking whether they are signed:
> 1. **Deactivating eConsent on a document** clears the signed document and deletes every signature record on it, signed ones included.
> 2. **Updating the eConsent signer list** deletes the record of any signer removed from the list, even one who has already signed.
> Both write audit entries, but signed signatures are lost. Should EDOCS-1769 also protect signed records in these flows, or should they get a separate ticket? Flow 1 deliberately resets the document, so we need a product decision on what should happen to existing signatures when eConsent is deactivated.
