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

### Requirement: Removing an unsigned signer is audited
Every removal of an unsigned signature request SHALL produce an audit trail entry that identifies the document, the signer whose request was removed, the user who performed the removal, and when it happened.

#### Scenario: Pending signer removed from the signer list
- **GIVEN** a document with pending signature requests for User A and User B
- **WHEN** a user saves the document with User B removed from the signers
- **THEN** the audit trail contains an entry for User B's request on that document
- **AND** the entry records the acting user and the time of removal

#### Scenario: Document made non-signable with pending requests
- **GIVEN** a document with a pending signature request for User B
- **WHEN** a user saves the document as non-signable
- **THEN** the audit trail contains an entry for User B's request recording the acting user and the time

### Requirement: A removed signature request is no longer actionable
After an unsigned signature request is removed, the signer SHALL NOT see it as pending and SHALL NOT receive reminders for it, in SOMS or in eISF.

#### Scenario: Removed signer's pending list
- **GIVEN** User B's pending request on a document was removed
- **WHEN** User B opens their pending signatures in SOMS or eISF
- **THEN** that document is not listed for User B

#### Scenario: No reminder after removal
- **GIVEN** User B's pending request on a document with a due date was removed
- **WHEN** the signature reminder job runs
- **THEN** no reminder is sent to User B for that document

### Requirement: Re-adding a removed signer creates a new request
When a signer whose earlier request was removed is added to the document's signers again, the system SHALL treat it as a new signature request: a new request date and a new request notification to the signer.

#### Scenario: Signer removed then added back
- **GIVEN** User B's pending request on a document was removed on day 1
- **WHEN** a user adds User B back to the document's signers on day 2 and saves
- **THEN** User B has a pending request dated day 2
- **AND** User B is sent a new signature request notification

### Requirement: Sign-on-the-Line placements follow signer removal
When an unsigned signer is removed from a document, by editing the signer list or by making the document non-signable, that signer's Sign-on-the-Line placements on the document SHALL become inactive.

#### Scenario: Sign-on-the-Line signer removed from the signer list
- **GIVEN** a document with an active Sign-on-the-Line placement for unsigned User B
- **WHEN** a user saves the document with User B removed from the signers
- **THEN** User B's Sign-on-the-Line placement on that document is inactive

### Requirement: Pending requests of a deleted study's documents are closed out audibly
When a study is deleted, any unsigned signature requests on its documents SHALL stop being actionable, and every request that is removed or cancelled SHALL be recorded in the audit trail.

#### Scenario: Study deleted with a pending request
- **GIVEN** a study whose document has a pending signature request for User B
- **WHEN** the study is deleted
- **THEN** User B no longer sees that request as pending
- **AND** the audit trail records what happened to User B's request

### Requirement: Signed signers cannot be removed from the document form
The document form SHALL NOT offer a remove control for a signer who has signed the document. It SHALL keep offering removal for a signer who is selected but not yet saved, and for a signer whose request is still pending.

#### Scenario: Signed signer row
- **GIVEN** the document form lists User A, who has signed
- **WHEN** the form is displayed
- **THEN** User A's row shows the signed date and no remove control

#### Scenario: Pending signer row
- **GIVEN** the document form lists User B, whose request is pending
- **WHEN** the user clicks User B's remove control and saves
- **THEN** User B's request is removed as defined by "Removing an unsigned signer is audited"

#### Scenario: Newly selected signer before saving
- **GIVEN** a user has just selected User C as a signer and has not saved
- **WHEN** the user clicks User C's remove control
- **THEN** User C is removed from the selection and no request is created
