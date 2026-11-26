# Spec Delta

## Purpose

Defines what happens to a document's signature records and signature requests when signers are removed, a document stops being signable, or its study is deleted, so that executed signatures always survive and every removal is traceable in the audit trail.

## ADDED Requirements

### Requirement: Signed signature records are never permanently deleted
A signature record that has been signed SHALL remain stored and SHALL keep its signed state on every removal path: editing a document's signer list, making a document non-signable, and deleting the study that owns the document.

#### Scenario: Signed signer left out of a saved signer list
- **GIVEN** a document with a signed signature from User A
- **WHEN** a request saves the document's signer list without User A
- **THEN** User A's signature record still exists
- **AND** the document still shows User A as signed with the original signing date

#### Scenario: Document made non-signable after a signature
- **GIVEN** a document with a signed signature from User A
- **WHEN** the document is saved as non-signable
- **THEN** User A's signature record still exists with its signed state unchanged

#### Scenario: Study deleted with a signed document
- **GIVEN** a study whose document has a signed signature from User A
- **WHEN** the study is deleted
- **THEN** User A's signature record still exists with its signed state unchanged

### Requirement: Removing an unsigned signer cancels the request and is audited
When an unsigned signature request is removed by editing the document's signer list or by making the document non-signable, the request SHALL be kept as a cancelled request with its cancellation date, not permanently deleted. The cancellation SHALL produce an audit trail entry that identifies the document, the signer whose request was cancelled, the user who performed the removal, and when it happened.

#### Scenario: Pending signer removed from the signer list
- **GIVEN** a document with pending signature requests for User A and User B
- **WHEN** a user saves the document with User B removed from the signers
- **THEN** User B's request still exists and is marked cancelled with the date of removal
- **AND** the audit trail contains an entry for User B's request on that document
- **AND** the entry records the acting user and the time of removal

#### Scenario: Document made non-signable with pending requests
- **GIVEN** a document with a pending signature request for User B
- **WHEN** a user saves the document as non-signable
- **THEN** User B's request still exists and is marked cancelled
- **AND** the audit trail contains an entry for User B's request recording the acting user and the time

### Requirement: A removed signature request is no longer actionable
After an unsigned signature request is removed, the signer SHALL NOT see it as pending and SHALL NOT receive reminders for it. The removed request SHALL NOT be listed as a signer on the document form, SHALL NOT be signable, and SHALL NOT be counted in signing notifications.

#### Scenario: Removed signer's pending list
- **GIVEN** User B's pending request on a document was removed
- **WHEN** User B opens their pending signatures
- **THEN** that document is not listed for User B
- **AND** the request is not counted in User B's pending signature count

#### Scenario: No reminder after removal
- **GIVEN** User B's pending request on a document with a due date was removed
- **WHEN** the signature reminder job runs
- **THEN** no reminder is sent to User B for that document

#### Scenario: Removed signer not listed on the document form
- **GIVEN** User B's pending request on a document was removed
- **WHEN** a user opens the document form
- **THEN** User B is not listed as a signer
- **AND** saving the form unchanged creates no request for User B

#### Scenario: Signing a removed request is refused
- **GIVEN** User B's pending request on a document was removed
- **WHEN** User B submits a signature for that request from a page opened before the removal
- **THEN** the signature is refused
- **AND** the request stays cancelled and unsigned

#### Scenario: Requester of a removed request is not told all parties signed
- **GIVEN** User Y's only request on a document, for User B, was removed
- **AND** User X requested a signature from User A on the same document
- **WHEN** User A signs and the document is signed by all remaining signers
- **THEN** User X is sent the "signed by all parties" notification
- **AND** User Y is not

### Requirement: Re-adding a removed signer creates a new request
When a signer whose earlier request was removed is added to the document's signers again, the system SHALL treat it as a new signature request: a new request date and a new request notification to the signer. The cancelled request SHALL NOT be reopened.

#### Scenario: Signer removed then added back
- **GIVEN** User B's pending request on a document was removed on day 1
- **WHEN** a user adds User B back to the document's signers on day 2 and saves
- **THEN** User B has a pending request dated day 2
- **AND** User B is sent a new signature request notification
- **AND** User B's request from day 1 is still cancelled

### Requirement: Sign-on-the-Line placements follow signer removal
When an unsigned signer is removed from a document, by editing the signer list or by making the document non-signable, that signer's Sign-on-the-Line placements on the document SHALL become inactive.

#### Scenario: Sign-on-the-Line signer removed from the signer list
- **GIVEN** a document with an active Sign-on-the-Line placement for unsigned User B
- **WHEN** a user saves the document with User B removed from the signers
- **THEN** User B's Sign-on-the-Line placement on that document is inactive

### Requirement: Pending requests of a deleted study's documents are deleted with an audit entry
When a study is deleted, the unsigned signature requests on its documents SHALL be permanently deleted, and each deletion SHALL be recorded in the audit trail with the request's values, the user who deleted the study, and when it happened. Signed signature records on those documents SHALL stay attached to the soft-deleted documents (see "Signed signature records are never permanently deleted").

#### Scenario: Study deleted with a pending request
- **GIVEN** a study whose document has a pending signature request for User B
- **WHEN** the study is deleted
- **THEN** User B's request no longer exists and User B no longer sees it as pending
- **AND** the audit trail contains a deletion entry for User B's request recording its values, the acting user and the time

#### Scenario: Study deleted with signed and pending requests on one document
- **GIVEN** a study whose document has a signed signature from User A and a pending request for User B
- **WHEN** the study is deleted
- **THEN** User A's signature record still exists, unchanged, on the soft-deleted document
- **AND** User B's request is deleted with an audit entry

### Requirement: Signed signers cannot be removed from the document form
The document form SHALL NOT offer a remove control for a signer who has signed the document. It SHALL keep offering removal for a signer who is selected but not yet saved, and for a signer whose request is still pending.

#### Scenario: Signed signer row
- **GIVEN** the document form lists User A, who has signed
- **WHEN** the form is displayed
- **THEN** User A's row shows the signed date and no remove control

#### Scenario: Pending signer row
- **GIVEN** the document form lists User B, whose request is pending
- **WHEN** the user clicks User B's remove control and saves
- **THEN** User B's request is cancelled as defined by "Removing an unsigned signer cancels the request and is audited"

#### Scenario: Newly selected signer before saving
- **GIVEN** a user has just selected User C as a signer and has not saved
- **WHEN** the user clicks User C's remove control
- **THEN** User C is removed from the selection and no request is created
