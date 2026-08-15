---
number: 0.1
title: The Problem and the Assumptions
concept: Solution design
description: >-
  Before any object exists: what a passport office actually does, what is broken
  about doing it on paper, and the assumptions this build is standing on.
you_will_learn:
  - "Why the first artefact of a Salesforce build is a document, not an object"
  - "How to write assumptions down so they can be challenged instead of quietly inherited"
  - "The difference between modelling a domain and modelling the concepts you need to learn"
---

There is a particular failure mode that shows up in almost every first Salesforce build, and it does not look like a failure while it is happening. You open Object Manager, you create `Application__c`, you start adding fields — and everything goes well for about a week. Then someone asks a question you cannot answer without adding three more fields, and one of the fields you added on day one turns out to mean two different things depending on who filled it in, and the validation rule you wrote to protect the data is now the reason nobody can save a form.

Nothing went wrong technically. What went wrong is that the build started before anyone had written down what it was for.

## What a passport office actually does

Strip away the queueing and the paperwork and a Passport Seva Kendra does six things in order:

1. Takes an application from a person standing at a counter.
2. Checks that the documents they brought match what they declared.
3. Sends a police officer to confirm they live where they say they live.
4. Has a senior officer authorise the passport.
5. Prints the booklet and checks it printed correctly.
6. Couriers it to the address on the file.

That is the whole domain. Six steps, one applicant, one file moving through time. Everything else — the fee tables, the appointment slots, the courier partners, the SLA targets — is detail hanging off those six steps.

Writing that list down first matters more than it looks like it does, because it is the thing you check every later decision against. When you are twelve fields deep and wondering whether to add a thirteenth, "which of the six steps does this serve?" is a question with an answer.

## What is broken about doing it on paper

The problems are not really about paper. They are about **state living in more than one place**, and every one of them has a direct Salesforce answer:

| The paper problem | What it actually is | The platform answer |
|---|---|---|
| The file could be "with verification", "with the SP office", or genuinely lost, and nobody at the counter knows which | State is distributed across desks with no single authority | One `Status__c` picklist on one record |
| The applicant re-explains their situation to whoever is free | History lives in people's memory, not in the record | Field history and a single file everyone reads |
| A missing document surfaces on the applicant's *next* visit | The requirement was in someone's head | A checklist generated automatically on submit |
| Weeks of silence during police verification | Nobody owns "tell them what's happening" | Ownership by queue, with a measurable depth |
| A name mismatch is discovered at the granting desk, days later | Verification happens too late in the process | Validation gates at the transition, not at the end |
| Nobody knows if a diplomatic passport was properly signed off | Approval was cultural, not structural | An approval process that actually blocks |

Notice that none of the answers are "add a field". They are all *structural* — they change where truth lives, not how much of it you record.

## What this build is optimising for

Here is the uncomfortable part, and it is worth being explicit about because it drives everything that follows.

An earlier version of this org modelled the domain thoroughly: seventeen custom objects, around two hundred and fifty fields, sixty-two validation rules. Appointment slots. Courier partners. Renewal outreach campaigns. A separate object for payments, and another for print jobs, and another for objections.

It was faithful. A real passport office does have all of those things. And it was **the wrong build**, because it optimised for *coverage of the domain* when it should have optimised for **coverage of the concepts**.

The difference matters. Modelling appointment slots teaches you nothing that modelling the application does not already teach — it is the same field types, the same validation patterns, one more object to maintain. Meanwhile the interesting ideas — why a police verification is a lookup and not a master-detail, why a roll-up summary beats a checkbox somebody has to tick, why escalation should be a standing query rather than an action someone remembers — were buried under administrative detail nobody was exercising.

So this build is eight objects. Not because a passport office has eight things in it, but because eight is enough to teach master-detail *and* lookup, roll-ups, formulas, record types, queues, sharing rules, approvals and the full trigger surface — with nothing left over that is just more of the same.

> **The rule this produces:** a field exists only if something *reads* it. An automation, a layout, a validation rule, a report, or a formula. "Might be useful later" is not a reader.

## The assumptions

These are written down so they can be argued with. Each one, if it turns out to be wrong, changes the design — which is exactly why leaving them implicit is dangerous. An assumption you never stated is one you can never revisit.

**1. This is a learning artefact, not a system anyone will operate.** Correctness of concept demonstration beats operational completeness. A stage that is real but boring gets collapsed into a picklist value.

**2. Developer Edition constraints hold.** No Shield Platform Encryption, no Enterprise Territory Management, no guaranteed Experience Cloud licences. Anything needing those is designed for and not built.

**3. The applicant is not a Salesforce user.** Every citizen interaction is mediated by a member of staff. There is no portal. This is a scope boundary, not an oversight — and it is load-bearing, because it means every user of this system is an internal one and the licensing question never arises.

**4. Aadhaar numbers are never stored.** Only a verified flag and an opaque token. This follows India's data-protection principle of minimisation, and because Shield encryption is unavailable, **the discipline is the only control there is.** There is no technical enforcement backing it up. That makes it more important, not less.

**5. The org is the source of truth for what exists; the repo is the source of truth for what should exist.** Where they disagree, the repo wins and gets deployed.

**6. One person builds and operates this.** No release train, no multi-org promotion. One org, and Git as the only safety net.

**7. "Learn all the concepts" is a real requirement.** Where a smaller design would skip something, that gap gets recorded explicitly rather than quietly accepted.

## The gap this creates, recorded honestly

Assumption 7 has teeth, so here is the first thing it catches.

Cutting from seventeen objects to eight removes the appointment and slot objects — and with them, the only genuine **many-to-many junction object** in the model. A junction object (one object with two master-detail relationships) is a real Salesforce concept, a common interview question, and there is now nothing in the build that demonstrates it.

That is a cost of the decision, not an oversight in it. It gets written into the design document as an open item with a proposed remedy — build the junction as an exercise, prove the roll-ups and cascade behaviour, then discard it — rather than being discovered six months later by someone wondering why the course never mentioned junctions.

**This is the habit worth taking from this lesson.** Every design decision costs you something. The difference between a considered design and an accidental one is not that the considered one costs nothing. It is that somebody wrote down what it cost.

## Where this goes next

The next three lessons finish the design work before a single object is created: the people who use the system, the journey a file takes through it, and the shape of the four apps that serve those people. Only then does anything get built.
