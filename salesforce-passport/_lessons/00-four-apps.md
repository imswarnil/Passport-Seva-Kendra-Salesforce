---
number: 0.4
title: Four Apps, One Lifecycle
concept: App architecture
description: >-
  An app in Salesforce is a navigation and permission boundary, not a data
  boundary — and understanding that difference is what lets four apps share one record.
you_will_learn:
  - "What a Salesforce app actually is, and why one record can travel through four of them"
  - "How to name an app so it survives contact with the people who use it"
  - "Why the Support app is built on standard Case instead of a custom object"
---

Ask someone new to Salesforce what an app is and you will usually get an answer that sounds like a separate system: its own data, its own users, its own everything. That is what "app" means nearly everywhere else in software.

It is not what it means here, and the gap causes real design mistakes.

## What an app actually is

A Salesforce app is a **navigation bundle**: a name, a logo, a set of tabs, a default landing page, and a utility bar. That is essentially it. It decides what appears in the nav when a user switches to it, and — combined with permission sets — who can switch to it at all.

What it is **not** is a data boundary. Two apps can show the same object. The same record can be worked on from four different apps by four different people. Nothing about the record knows or cares which app it is being viewed in.

So the right question when designing apps is not "how should the data be divided?" It is:

> **Whose day is this? What does this person need in front of them, and what would just be noise?**

## One app per job

The organising principle here is simple: if you cannot say "I am the person who does X" and have X be an app, the app is wrong.

The org this build starts from failed that test. It had five custom apps, including one called `PSK Operations Console` and another called `Passport Validator`. Nobody's job is "operations console". Names like that appear when apps get created around *functionality* rather than around *people*, and the result is that everyone uses whichever one has the most tabs and ignores the rest.

Four apps, named after the four jobs:

### App 1 — Passport Application Management

**Whose job:** the counter officer and the document verification desk.
**What it covers:** walked in the door → file is complete, paid and verified.

Citizen identity, the application, the checklist. Three objects, and the two personas who work them sit next to each other in a real office.

**Ends when** the file reaches Police Verification — or Granting directly, for the record types that need no field check.

### App 2 — Support

**Whose job:** the help desk.
**What it covers:** everything that is a *question about* a passport rather than an application for one.

"Where is my file?" · "I got married, I need my name changed" · "How do I get a visa?" · "My booklet arrived damaged."

This is the app that did not exist in the original design, and adding it is what surfaced the most interesting decision in the whole app layer.

### App 3 — Police Verification

**Whose job:** the verifying officer, half of whose work happens on a doorstep.
**What it covers:** claim the check, do the visit, record the outcome.

One object. It is a small app on purpose — Suresh needs a list of addresses and two buttons, and every additional tab is something to scroll past on a phone in a stairwell.

### App 4 — Passport Authorization & Dispatch

**Whose job:** the granting officer, then the print-and-despatch desk.
**What it covers:** authorise → approve if sensitive → mint the booklet → print → validate → courier → delivered.

Two personas again, and the reason they share an app is that the handoff between them is the tightest in the system: the booklet exists, and it needs to physically reach someone.

## How they connect

```
                    ┌─────────────────────────────────────┐
                    │  App 2 — Support (Case)             │
                    │  questions · name change · visa     │
                    └──────────────┬──────────────────────┘
                       references  │  can spawn
                                   ▼
┌──────────────────┐   PV needed  ┌──────────────────┐  cleared  ┌──────────────────────┐
│ App 1            │─────────────▶│ App 3            │──────────▶│ App 4                │
│ Application Mgmt │              │ Police Verif.    │           │ Authorization &      │
│                  │              │                  │           │ Dispatch             │
│ Citizen          │◀─────────────│ Police_          │  adverse  │ Passport             │
│ Passport_        │   blocks     │ Verification     │───────────│ Dispatch             │
│ Application      │              │                  │  ✗ halt   │                      │
│ Document_        │              └──────────────────┘           └──────────────────────┘
│ Checklist_Item   │                                                        ▲
└──────────────────┘         ──────── no-PV record types ──────────────────┘
                                   (Minor, some Re-Issue) skip App 3
```

**One application record travels through all four.** The apps are views onto the same lifecycle, not separate systems.

That is worth sitting with, because it is the practical consequence of "an app is not a data boundary". Priya, Anjali, Suresh, Vikram and Farhan are all looking at the same `Passport_Application__c` record. They see different fields (field-level security), different actions (dynamic actions on the record page), and different tabs around it (the app) — but there is exactly one row in the database, and it never gets copied from one app's version of the object to another's.

If that were not true — if each app had its own object — you would be copying every field at every stage, re-pointing every child record, and reconciling four versions of the truth. That is the mistake the [data model lesson](../01-data-modeling/) is about.

## The Support app is built on standard Case

Here is the decision the fourth persona forced, and it is the most transferable thing in this lesson.

The instinct is to build a `Query__c` custom object. It is a request, it has a status, it has a description — a custom object handles that fine.

**Don't.** Use the standard `Case` object, and the reason is what comes attached to it:

| Comes free with `Case` | What you'd build without it |
|---|---|
| Assignment rules | Custom routing logic in Apex |
| Escalation rules | A scheduled batch and a lot of date arithmetic |
| Email-to-Case | An inbound email service handler |
| Auto-response rules | More Apex, plus email template plumbing |
| Entitlements and milestones | An SLA engine from scratch |
| Omni-Channel routing | Not buildable |
| Macros and quick text | Not buildable |
| Case feed, case teams | Not buildable |

Building `Query__c` means re-implementing roughly half of Salesforce Service Cloud, badly, and learning none of it. Using `Case` means the Support app is the place where a whole area of the platform gets exercised for real, on a genuine use case, rather than in a tutorial org.

**Four Case record types**, one per kind of request:

| Record type | Typical outcome |
|---|---|
| `Status_Enquiry` | Answered from the record and closed. No records created. |
| `Detail_Change` | **Spawns a Re-Issue application**, linked back so the request and its outcome stay joined |
| `Visa_Enquiry` | Answered from a canned response and closed |
| `Complaint` | Escalated; may spawn a re-issue or a fresh dispatch |

### The object that got deleted because of this

The original org had a `Visa_Application__c` object. Twenty-six fields, two validation rules, a tab, an app placement and a permission set — and **no automation, no persona working it, and no journey through it.** It had been built because "the office also handles visas" sounded like a requirement.

Looking at it through the persona lens: who works this object, and what do they do to it? The honest answer was nobody, and nothing.

What people actually wanted was to *ask about* visas. That is a question, and questions are Cases. So twenty-six fields collapsed into one record type value, and the object went.

> **The general lesson:** when a stakeholder says "we also handle X", find out whether X has a *lifecycle someone works*, or whether it is a *topic people ask about*. The first is an object. The second is a picklist value. Getting this wrong is one of the commonest ways an org acquires objects nobody maintains.

## Naming, and why it matters more than it seems

`PSK Operations Console` versus `Passport Application Management`.

The first is a name someone chose while thinking about the software. The second is a name someone chose while thinking about the person opening it in the morning.

The test that catches this: **can a new employee, on their first day, tell from the app names which one is theirs?** If they have to be told, the names are describing the implementation rather than the job — and app names are one of the very few things in an org that every single user reads every single day.

## What this decides downstream

The four apps are not just navigation. They now constrain several later decisions, which is why this lesson comes before any of them:

- **Permission sets** map to apps — each persona's set grants their app and no other.
- **Tabs** are chosen per app, so Suresh's app has one object tab and not seventeen.
- **Home pages** differ per app: Meenal lands on a dashboard, Suresh lands on a list.
- **Record pages** are shared (there is one application record page), but **dynamic actions** vary the buttons by status and by user, which is how one page serves five personas.

That last one is the payoff. One record page, one record, four apps, five personas — and each person sees a page that looks like it was built for them.

## End of Module 0

The design is done: the problem, the assumptions, the people, the journey and the apps. Nothing has been built. The next module starts creating objects — and every decision it makes will point back to something written here.
