---
number: 0.3
title: The Journey — Draft to Delivered
concept: Process design
description: >-
  One application through eight pairs of hands, and the three mechanisms that
  move it between them. Getting the handoffs right is most of the design.
you_will_learn:
  - "The full lifecycle as a sequence of real user actions, with what the system does on its own marked separately"
  - "The three handoff mechanisms — queue, new record, sharing rule — and how to tell which one a stage boundary needs"
  - "Why the failure paths are the interesting part of a process design"
---

A process diagram is easy to draw and easy to get wrong, because the boxes are the obvious part and the arrows are where the design lives. This lesson is mostly about the arrows.

## The main line

Twenty-seven steps, Draft to Delivered. **⚙︎** marks what happens without anyone doing it.

| # | Stage | Who | Action | Records |
|---|---|---|---|---|
| 1 | — | Front Office | Search for the citizen by mobile + DOB | read |
| 2 | — | Front Office | Create the citizen if new | **insert** — a duplicate rule blocks a second record for the same person |
| 3 | Draft | Front Office | New application from the citizen; pick the record type | **insert**, `Status__c = Draft` |
| 4 | Draft | Front Office | Fill the form over several minutes; save partway | saves clean |
| 5 | Draft | Front Office | For a minor: set the guardian and tick consent | second lookup to the citizen object |
| 6 | **Submitted** | Front Office | Press Submit | ⚙︎ fee written from custom metadata; submitted date stamped |
| 7 | Submitted | — | ⚙︎ | checklist rows **generated** from the record-type template |
| 8 | Submitted | Front Office | Collect the fee | payment status → Paid |
| 9 | **Doc Verification** | — | ⚙︎ | owner → the Document Verification **queue** |
| 10 | Doc Verification | Doc Verification | Claim the file | owner: queue → user |
| 11 | | Doc Verification | Mark Received on each document | checklist item update |
| 12 | | Doc Verification | Mark Verified after checking | ⚙︎ roll-up increments on the parent |
| 13 | | Doc Verification | *If wrong:* raise an objection on that item | ⚙︎ roll-up **blocks the advance** |
| 14 | **Police Verification** | Doc Verification | Advance | ⚙︎ verification record **created**, owned by a queue |
| 15 | | Police Verification | Claim, then do the field visit | owner: queue → user |
| 16 | | Police Verification | Mark Cleared *or* Mark Adverse | Cleared advances; Adverse halts and escalates |
| 17 | **Granting** | Granting Officer | Open the file, shared to him by criteria | two hard-stop validation rules |
| 18 | | — | ⚙︎ *Diplomatic/Official only* | auto-submitted for approval |
| 19 | | RPO | Approve or reject | blocks Printing until Approved |
| 20 | | Granting Officer | Grant | ⚙︎ booklet **minted**, fields by formula |
| 21 | **Printing** | — | ⚙︎ | dispatch record **created**; owner → fulfilment queue |
| 22 | | Fulfilment | Log the batch, mark printed | |
| 23 | | Fulfilment | QC-validate | a fail loops back to 22 |
| 24 | **Dispatch** | Fulfilment | Book the courier | address is a **formula**, never retyped |
| 25 | **Delivered** | Fulfilment | Mark delivered | transit days computed |
| 26 | | — | ⚙︎ | the record becomes terminal |
| 27 | any | Audit | Reconstruct the timeline afterwards | read-only + field history |

Count the ⚙︎ rows: nine of the twenty-seven steps happen with nobody doing them. That ratio is the point of building this on a platform at all.

## The three handoff mechanisms

Every stage boundary above uses one of exactly three mechanisms, and choosing the right one is the actual design work.

### 1. Queue ownership change

**Used at:** Front Office → Document Verification, and into fulfilment.

The record's `OwnerId` changes to a queue. It sits there until somebody claims it.

**Why not assign it to a person?** Because a person can be on leave, and a record assigned to someone who is not there is invisible work. A queue is *ownership by a team*: it has a measurable depth, it survives absence, and "who is responsible right now" has a truthful answer — the team is.

Round-robin assignment to individuals looks like the same thing and is not. It produces a worse version with a hidden failure mode.

### 2. Creating a new record

**Used at:** Document Verification → Police Verification, and Granting → Fulfilment.

The application does not just change status; a *different object* comes into existence with its own lifecycle, its own owner and its own sharing.

**When do you need this rather than a status change?** When the new stage has state the parent does not want, or a lifetime the parent does not share. A police verification has a police station, a verifying officer, a report date and an outcome — none of which belong on an application. More importantly, it needs to **outlive** the application and be visible to people who cannot see the file. That is why it is a lookup rather than a master-detail, and it is the clearest example in the build of a relationship type chosen for a business reason rather than a technical one.

### 3. Criteria-based sharing rule

**Used at:** Police Verification → Granting, every escalation to a manager, and fulfilment access.

Nobody reassigns anything. The record starts *matching a criterion*, and everyone whose rule matches that criterion can now see it.

This is the mechanism people reach for last and should reach for first, because it inverts something important:

> **Escalation becomes a standing query rather than an action someone has to remember to take.**

Nobody has to notice that a police report came back adverse and decide to tell a manager. The record's status becomes `Adverse`, a sharing rule matches, and it is in the manager's view. The step where a human might forget has been removed from the process entirely.

The same pattern handles Tatkal files, diplomatic applications, blacklisted citizens and high risk scores. Six rules, and between them they replace every "and then you escalate it to your supervisor" line that a paper process would have needed.

### And one more, used exactly once

**The approval process**, at Granting → RPO. This is the only handoff in the system that needs a *named human to say yes*, recorded and attributable.

Why not a validation rule? A validation rule can block. It cannot record **who decided**, when, or why. The requirement here is an auditable sign-off with a timestamp and a comment — which is exactly and only what an approval process produces.

## The failure paths are the design

The main line is the boring case. A process design is judged on what it does when things go wrong, and these are the paths worth building deliberately:

| Journey | What happens | Where it ends |
|---|---|---|
| **Objection and recovery** | A document fails; the checklist item is flagged with a *specific* reason; a roll-up blocks the advance; the applicant is told exactly what to bring | Rejoins the main line at step 14 |
| **Adverse verification** | The file halts, shares to managers, and the RPO decides | Rejected, or overridden with a documented reason |
| **Diplomatic approval** | Auto-submitted; the record is *locked*; Printing is blocked | Approved → main line; Rejected → back to Granting |
| **QC failure and reprint** | A reprint reason is set and it loops back to print **on the same record** | Rejoins at step 24 |
| **Name change via Support** | A Case spawns a re-issue application and links to it | Two records telling one story |
| **Abandoned draft** | The applicant never returns | Sits in Draft indefinitely — valid, saveable, incomplete |

Three of these deserve a note.

**The objection is raised on a specific document, not on the application.** "Your file has a problem" is not actionable. "Your address proof shows a different pincode than you declared" is. This is why objections are a *status on the thing being objected to* rather than a free-floating record — and it is why the roll-up that counts them lives on the parent, so the block is automatic rather than something the officer has to remember to enforce.

**The reprint loops back onto the same record.** Not a new one. Six months later, "why did this booklet take two attempts?" is answerable from field history, which is where history belongs. Creating a second record would have made the question require a join and the answer require interpretation.

**The abandoned draft is a valid state.** It is not an error, it does not need cleaning up, and nothing about it is broken. Half-finished forms are the normal case in a counter process, and a system that cannot hold one is a system people work around. Which brings us to the convention that makes it possible.

## The convention that makes the whole thing usable

Every validation rule on the application is gated on `Status__c ≠ Draft`.

That one line is the difference between a form people can use and one they fight. Priya is entering details while an applicant hunts through a folder for a document. She needs to save what she has, walk away, and come back. If a validation rule fires the moment a required field is blank, she cannot — and what actually happens next is that she keeps the details on a piece of paper until the form is complete, which is the paper process she was supposed to be replacing.

**Enforce on submit, not on save.** The gates belong at the transitions, not at every keystroke.

## Next

The journey crosses four apps. The next lesson is about why it is four, and what an "app" is actually doing in a Salesforce org — because it is not what most people assume.
