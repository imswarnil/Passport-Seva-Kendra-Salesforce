---
number: 0.2
title: Eight Personas, One of Whom Never Logs In
concept: Personas
description: >-
  The people the system is for — including the one with no account, who turns out
  to be the most useful of them all when you are deciding whether a field earns its place.
you_will_learn:
  - "Why a persona is a permission set and not a profile — and what breaks when you get that backwards"
  - "How the person who never logs in keeps the rest of the design honest"
  - "Why writing down what each persona is forbidden to do is more useful than writing down what they can"
---

A persona in a Salesforce build is not a marketing exercise. It is the thing that decides your permission sets, your queues, your sharing rules, your apps and your page layouts. Get the personas wrong and every one of those is wrong downstream, in a way that is expensive to unpick because it is spread across nine different places in Setup.

So it is worth doing carefully, and it is worth doing **before** the schema, not after.

## The cast

| # | Persona | App | Owns |
|---|---|---|---|
| 0 | **Applicant** — Ramesh Iyer, 34 | *none — no login* | nothing |
| 1 | **Front Office Officer** — Priya Deshmukh, 27 | 1 | Citizens, applications in Draft |
| 2 | **Document Verification Officer** — Anjali Nair, 31 | 1 | Checklist items |
| 3 | **Help Desk Agent** — Kavya Menon, 25 | 2 | Cases |
| 4 | **Police Verification Officer** — HC Suresh Patil, 42 | 3 | Verification records |
| 5 | **Granting Officer** — Vikram Rao, 45 | 4 | Passport booklets |
| 6 | **Fulfilment Officer** — Farhan Sheikh, 29 | 4 | Dispatches |
| 7 | **Regional Passport Officer** — Meenal Kulkarni, 51 | all | Approvals and escalations |
| 8 | **Audit & Compliance Officer** — Deepak Bhosle, 38 | all, read-only | nothing, deliberately |

## Persona zero: the one with no account

Ramesh has a flight in three weeks and a Tatkal application he paid a premium for. He has never dealt with a government office before this week. He will never log into Salesforce, and there is no plan for him to.

It is tempting to leave him out of the persona list entirely. That would be a mistake, because **he is the only persona who tells you whether a design decision was worth making.**

Every field, queue and SLA in this system exists because of something that happens to Ramesh:

| What Ramesh experiences | The mechanism that causes it |
|---|---|
| Every officer gives him the same answer | One `Status__c` picklist on one record — not a guess per desk |
| He learns what is missing *before he leaves the counter* | The checklist is generated on submit, so the gap is visible immediately |
| His Tatkal urgency is actually honoured | A checkbox that selects a different SLA row and shares the file to managers |
| His file does not sit forgotten in a drawer | Ownership moves to a queue, and a queue has a depth you can measure |
| His identity documents are not over-collected | No Aadhaar number is stored anywhere — only a verified flag and an opaque token |

When you are deciding whether to add a field, "what does this change for Ramesh?" is a much better question than "would this be useful?" — because almost everything is arguably useful, and very little of it changes anything for the person the system exists to serve.

## Personas are permission sets, not profiles

This is the single most consequential decision in this lesson, and it is one beginners get backwards almost universally.

The instinct is: eight personas, so eight profiles. It seems tidy. It is a trap, for three reasons.

**A user has exactly one profile, forever.** So the moment one human does two jobs — a small office where the same person works the counter *and* answers the phone — you need a ninth profile that is Front Office plus Help Desk. Then a tenth for Granting plus Fulfilment. The combinations multiply, and every one of them is a clone.

**A clone stops being true.** The day you fix something in the Front Office profile, the Front-Office-plus-Help-Desk clone still has the old version. It will not error. It will just quietly be wrong, and you will find out months later.

**Profiles carry things that have nothing to do with the job.** Login hours, password policy, IP ranges, default record types. Bundling "when can this person log in" with "can this person grant a passport" means changing one risks the other.

So: **one lean base profile**, carrying only the things that genuinely are per-user and org-wide, and every persona is an additive **permission set**. A profile is a job description you can only have one of. A permission set is a hat, and people wear several.

For the humans who genuinely do two jobs, permission sets compose into **permission set groups**:

| Group | Contains | For |
|---|---|---|
| `PSK_Counter_Staff` | Front Office + Help Desk | A small office where one person does both |
| `PSK_Back_Office` | Granting + Fulfilment | Where the same desk authorises and despatches |
| `PSK_Manager` | Office Manager + Auditor read | An RPO who also needs the audit view |

A group is a *composition*, not a copy. `PSK_Front_Office` remains the single definition of what a front office officer can do — fix it once and every group containing it is fixed. That is precisely what the profile clone could not do.

> **Never put a permission directly into a group.** A group holds only sets. The moment you add a permission to the group itself, you have reinvented the clone problem inside the tool that was supposed to solve it.

## Write down what each persona cannot do

Most persona documents list capabilities. The refusals are more useful, for a reason that only becomes obvious once you have debugged a security model: **a permission you granted is visible in Setup; a permission you deliberately withheld is invisible.** Six months later nobody can tell the difference between "we decided against this" and "we never got round to it".

So each persona in this build carries an explicit refusal list. A few examples:

**Priya (Front Office)** cannot select the Diplomatic/Official record type — that intake happens through a different channel entirely. She cannot delete an application, grant, verify, print or despatch. She cannot see police verification records *at all*.

**Anjali (Document Verification)** cannot create or edit an application. Read-only. She checks the declaration against the documents; she does not author the declaration. This one surprises people, and it is exactly right: the person checking the work should not be able to change the work.

**Vikram (Granting)** cannot edit the applicant's declaration, cannot create a second booklet for one application, and cannot print or despatch. He is also the persona the system argues with most — two validation rules are hard stops he cannot talk his way past.

**Farhan (Fulfilment)** cannot see citizens, checklists, verifications or payments, and cannot read the Aadhaar token at all. A courier desk does not need an identity token to print a label. Least privilege applied at the *field*, not just the object.

**Meenal (RPO)** has the broadest access in the build — full CRUD everywhere plus `viewAllRecords` where oversight requires it — but deliberately **not `modifyAllRecords`, anywhere.** She can see everything in her office. She cannot silently overwrite outside the sharing model. Seniority is not a reason to bypass the audit trail.

**Deepak (Audit)** cannot create, edit or delete a single record on any object — not even to correct an obvious typo. He raises it with someone who can. Compliance review and data correction are *structurally* separated, because a trail written by the people being audited is not a trail.

## The pattern underneath

Read those refusals together and a shape emerges. It is not "junior people get less". It is:

- **Whoever declares something cannot verify it** (Priya declares, Anjali verifies)
- **Whoever verifies cannot authorise** (Anjali verifies, Vikram grants)
- **Whoever authorises cannot approve their own sensitive cases** (Vikram grants, Meenal approves diplomatic)
- **Whoever audits cannot change anything** (Deepak reads only)

That is separation of duties, and it is the reason the persona list has eight entries rather than three. Each split exists because collapsing it would let one person complete a sensitive action end to end with nobody else involved.

## Two personas that changed during design

Worth recording, because persona lists are not handed down — they get argued about.

**Help Desk was added.** The original design had no persona for "someone phones up and asks a question", which meant every enquiry became either a front-office task or nothing at all. Adding the persona is what forced the second app into existence, and forced the realisation that the standard `Case` object was the right tool for it.

**Six roles were collapsed into three teams.** The original had eleven roles, most with one person under them and nobody above who needed to see their records. A role only earns its place if the hierarchy roll-up is doing real work. Six of them were not, so they went.

## Next

Eight personas, each with a job, an app, a set of refusals, and — for the one who never logs in — a reason for the rest of them to exist. The next lesson follows a single application through all of their hands.
