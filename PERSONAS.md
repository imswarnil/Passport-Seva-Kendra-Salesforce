# PERSONAS.md — Who Uses This System

> Field-style persona notes for the Passport Seva Kendra (PSK) Salesforce build. Each profile is grounded in the actual role hierarchy, permission sets, and quick actions shipped in this repo — see [PSK.md](PSK.md) §5 for the security model and §2 for the object catalogue. Permission claims below were verified directly against `force-app/main/default/permissionsets/*.permissionset-meta.xml`, not assumed.

---

## 1. The Applicant

**Ramesh Iyer, 34 — first-time Tatkal applicant, has never dealt with a government office before this week**

The Applicant is not a Salesforce user in this build. There is no Experience Cloud portal yet (PSK.md §9, "Not started") — every interaction with the system happens through a counter officer, a phone call, or an SMS. This persona exists to keep the staff-side design honest: every field, queue and SLA in the system exists because it changes what an applicant experiences on the other side of the counter.

**Goals**
- Get a passport before an already-booked international flight (this is why he paid the Tatkal premium).
- Understand, at any point, where his application actually is and what's still needed from him.
- Not have to explain his situation from scratch to a different officer every visit.
- Trust that his Aadhaar and identity documents aren't being copied around carelessly.

**Daily frustrations (the old paper-based way)**
- A physical file that could be "with verification," "with the SP office," or genuinely misplaced, and no one at the counter could tell which.
- Re-explaining his case to whichever officer happened to be free, because the paper file carried no structured history.
- Finding out about a missing document (an address proof, a police NOC) only when he showed up for the next step — never proactively.
- No SMS or call until something had already gone wrong; police verification silence could run for weeks with no visibility.
- Fear that a name mismatch between his old passport and current documents would only surface at the granting desk, days after submission.

**How the new system serves him (indirectly)**
Ramesh never logs into anything. But because the Front Office Officer works him through one `Passport_Application__c` record instead of a paper folder, his Tatkal flag is set once and drives the SLA target, his checklist is generated automatically the moment his record type is set, and his status is always one authoritative picklist value — not a guess. When his file needs a police visit, it's the `Police_Verification` queue that owns it, not a drawer. If his risk score creeps up because of a data mismatch, an officer sees `Risk_Score__c` before it becomes his problem at the counter. He still doesn't see any of this — but the improvement is that every officer he talks to sees the *same* single truth, so his story doesn't have to be repeated or reconstructed.

**What he's explicitly not allowed to see or do**
- Nothing — he has no login. That is itself the gap: PSK.md §9 lists a citizen self-service portal as not started, so today Ramesh's only channel is a person at a desk or an SMS from `Notification_Log__c` (also currently unpopulated — no real Twilio integration yet).

**Success looks like:** Ramesh gets one consistent status whoever he asks, a Tatkal turnaround that actually holds to the promised SLA, and a booklet that shows up at the address he gave — without ever needing to know an ARN number by heart.

---

## 2. Front Office / Data Entry Officer

**Priya Deshmukh, 27 — counter officer, PSK Officer permission set, `Passport_Processing_Team` role**

**Goals**
- Get an applicant's Draft application to Submitted correctly on the first pass — no bounced records from Document Verification because of a typo in the DOB.
- Keep the day's appointment slots moving so the queue outside doesn't back up.
- Register new citizens and family members (minors, guardians) cleanly so downstream stages don't have to guess relationships.
- Collect payment status accurately, since a missing `Payment_Status__c = Paid` blocks granting later.

**Daily frustrations (the old way)**
- Paper intake forms with illegible handwriting, corrected in pen, re-copied by hand into a register.
- No way to check a citizen's history — was this person here before, do they have an existing record — without physically pulling old files.
- Guardian consent for minors tracked on a separate paper slip that could get separated from the main file.
- No structural distinction between "this application is incomplete" and "this application was rejected" — both just looked like an unfinished file.

**Day in the life:** Priya opens the `Application_Management_Console` app and works the `Citizen__c` tab first — she either finds an existing golden-identity record or creates one, pressing **Verify KYC** on it once documents are sight-checked. From there she uses **New Passport Application** off the citizen record, picks the record type (Fresh, Re-Issue, Tatkal, Lost/Damaged, or Minor — she cannot select Diplomatic/Official; her permission set has no `recordTypeVisibility` entry for it), and fills in the Group A–D fields. For a minor applicant she uses **New Family Member** to link a guardian and set `Is_Guardian__c`. She uses **New Appointment** against a `Slot__c` to book the applicant a counter slot, and **Collect Payment** to log the fee once paid. Because `Require_Core_Fields_On_Submit` only fires once the record leaves Draft, she can save a half-finished form and come back to it — the object doesn't fork into a different shape depending on how complete it is, which is the whole point of PSK's "few objects, many fields" design (PSK.md §1). Her object permissions on `Payment__c` are create/read only (no edit, no delete) — once logged, a payment isn't hers to alter.

**What she's explicitly not allowed to see or do**
- No Diplomatic/Official record type visibility at all — her permission set description says so outright: "Cannot handle Diplomatic/Official applications."
- No delete rights on `Passport_Application__c`, `Payment__c`, `Family_Member__c` deletion is allowed but application deletion is not.
- Read-only on `PSK__c` (offices) and `Slot__c` — she books into slots, she doesn't create or resize them (that's `PSK_Reference_Data_Admin`).
- No edit rights on `Notification_Log__c` — she can see what was sent, not rewrite it.
- No object permission on `Police_Verification__c`, `Objection__c`, `Print_Job__c`, `Dispatch__c`, `Risk_Flag__c` at all — those stages belong to other personas entirely.

**Success looks like:** an applicant leaves the counter with a Submitted (not Draft) application, an accurate fee logged, and — if a minor — a guardian consent that's structurally impossible to lose.

---

## 3. Document Verification Officer

**Anjali Nair, 31 — verification desk, `Document_Verification` role**

A structural note on this persona, stated plainly rather than glossed over: PSK.md §5.2 lists Document Verification Officer as its own row with its own role (`Document_Verification`), separate from Police Verification. In the deployed permission sets, however, there is no dedicated `PSK_Document_Verification` permission set — document verification and police verification currently share one permission set, `PSK_Verification_Officer` ("Police verification and document verification: owns Police Verification, Objections and Risk Flags; reads/updates applications and checklists"). Anjali's role in the hierarchy is distinct, but until the permission sets are split, she is assigned the same `PSK_Verification_Officer` set as the Police Verification Officer. That's worth being upfront about — it's exactly the kind of gap this project's [CASE_STUDY.md](CASE_STUDY.md) is honest about.

**Goals**
- Clear the `Document_Verification` queue without letting files sit unattended.
- Catch a missing or mismatched document before it becomes an objection someone else has to chase down.
- Keep `Objection__c` records specific enough that the applicant knows exactly what to bring back.

**Daily frustrations (the old way)**
- A checklist that existed only in an officer's head, so what counted as "complete" varied by who was checking.
- Objections raised verbally at the counter with no written trail, so a second officer had no way to know a document had already been flagged as missing.
- No way to see the full document status per applicant at a glance — every checklist item was a separate scrap of paper.

**Day in the life:** Anjali works from the `Document_Verification` queue, picking up applications one `Document_Checklist_Item__c` at a time — these rows exist because they're auto-generated the moment an application is submitted, not typed up by hand. As physical documents arrive she presses **Mark Received** on each item, then **Mark Verified** once she's checked it against the applicant's declared details on the parent application. If something's wrong — an address proof that doesn't match `Address_Line1__c`, a photo that fails the format check — she uses **New Objection** on the application (full create/edit/delete rights on `Objection__c`) and, once the applicant resolves it, **Resolve Objection**. She has full CRUD on `Police_Verification__c` too under the shared permission set, plus create/edit on `Risk_Flag__c` — so if a document looks fraudulent rather than just incomplete, she can raise a risk flag directly rather than waiting for someone else to notice.

**What she's explicitly not allowed to see or do**
- Cannot create new `Passport_Application__c` records — object permission is read/edit only, no create, no delete. She works applications that already exist; she doesn't originate them.
- No object permission at all on `Print_Job__c`, `Dispatch__c`, `Payment__c`, or `Appointment__c` — those belong to other stages.
- `Citizen__c.Aadhaar_Token__c` is field-level readable but not editable in the shared `PSK_Verification_Officer` set — she can see that Aadhaar was tokenized, she cannot rewrite the token.
- No `viewAllRecords` on anything — she sees what's shared to her role/queue, not the whole org's applications.

**Success looks like:** every checklist item on a file is either Verified or has a specific, resolvable Objection attached — never a silent gap.

---

## 4. Police Verification Officer

**Head Constable Suresh Patil, 42 — field verification, `PSK_Verification_Officer` permission set, `Police_Verification_Team` role**

This persona is deliberately half system-based and half field-based: the actual verification (visiting the declared address, talking to neighbours, confirming identity) happens away from a screen, and only the outcome gets recorded back into Salesforce.

**Goals**
- Work the physical visit list efficiently — batch addresses in the same neighbourhood rather than criss-crossing the city.
- Record a Cleared or Adverse outcome promptly so the application isn't stuck waiting on him.
- Flag genuinely suspicious cases (address doesn't exist, applicant unknown at the address, prior adverse history) without slowing down the routine majority.

**Daily frustrations (the old way)**
- A physical verification report that had to be hand-carried or faxed back to the PSK, with no record of it until it physically arrived.
- No idea how urgent a given file was — Tatkal and ordinary requests looked identical on paper once they reached his desk.
- An address history that lived only in the applicant's memory — no `Years_At_Address__c` signal to tell him whether this was even the right kind of check (Pre-PV vs Post-PV).

**Day in the life:** Suresh works the `Police_Verification` queue, which only contains applications whose `Police_Verification_Type__c` calls for a check at all (some record types — Minor, some Re-Issue reasons — route to "No PV" and never reach him). He opens a `Police_Verification__c` record — deliberately a **lookup**, not master-detail, to the application (PSK.md §2 item 7), so a verification report has its own OWD and survives independently of whatever happens to the application afterward. After the field visit he records the outcome using **Mark Cleared** or **Mark Adverse**. Because `Passport_Category__c` is visible to him at read/edit level on the application, he knows before he leaves the desk whether a file is Tatkal-flagged (via the `Tatkal_To_Managers` sharing rule his managers also see) and treats it with matching urgency. If something about the visit feels wrong — an address that doesn't check out, a person who denies knowledge of the applicant — his object permissions on `Risk_Flag__c` (create/read/edit, no delete) let him raise a flag directly rather than routing it through someone else.

**What he's explicitly not allowed to see or do**
- No create rights on `Passport_Application__c` — read and edit only. He updates status-adjacent fields on the file he's assigned, he doesn't originate applications.
- `Citizen__c.Aadhaar_Token__c` is readable, not editable, under his shared permission set — he confirms identity, he doesn't touch the token.
- No object permission on `Print_Job__c`, `Dispatch__c`, or `Payment__c` at all — fulfilment and money are outside his lane entirely.
- No `viewAllRecords` — the `Adverse_To_Managers` sharing rule exists specifically because an Adverse outcome needs to escalate to `PSK_Managers`; Suresh doesn't get blanket visibility into other officers' cases himself.

**Success looks like:** every address-based verification gets a Cleared or Adverse outcome recorded the same day as the visit, with genuinely suspicious cases already flagged before a granting officer ever looks at the file.

---

## 5. Granting Officer

**Vikram Rao, 45 — granting desk, `PSK_Granting_Officer` permission set, `Granting_Officers` role**

**Goals**
- Move a clean file (paid, documents verified, PV cleared where required) from Granting to Printing without unnecessary delay.
- Never grant a passport where payment is outstanding — a hard stop the system now enforces for him.
- Handle Diplomatic and Official grants correctly, including the new approval sign-off requirement.

**Daily frustrations (the old way)**
- Discovering *after* granting that payment was never actually collected, because payment status lived on a different ledger from the application file.
- No structural way to tell whether a Diplomatic passport had actually been signed off by someone senior, versus just being processed like any other file.
- Reissuing a passport meant retyping the holder's details by hand into the new booklet record — an obvious source of transcription errors on a legal document.

**Day in the life:** Vikram works applications shared to him via the `Granting_Stage_To_Granting_Officers` criteria-based sharing rule, which grants Edit access the moment `Status__c` hits Granting or Printing — he doesn't need a manual reassignment to see his queue fill up. The validation rule `Cannot_Grant_With_Pending_Payment` is a hard backstop: he cannot move a record into Granting unless `Payment_Status__c` is Paid, full stop. Once satisfied, he creates the `Passport__c` record itself (he's the only persona with create rights there) — almost every field on it is a formula pulled from the application (booklet pages, validity years, ECR status, holder name), so he isn't retyping identity data that already exists. For a Diplomatic or Official application, his submission into Granting auto-triggers the `Diplomatic_Official_Grant_Approval` approval process via `PSK_ApplicationActionsController.advance()` — the file is now blocked from reaching Printing until a Regional Passport Officer approves it. Today that approval step is hard-wired to a single admin user rather than the RPO role, which PSK.md flags as the highest-priority open gap.

**What he's explicitly not allowed to see or do**
- Read-only on `Police_Verification__c` and `Citizen__c` — he can see the verification outcome and identity, he can't re-open or edit either.
- No object permission on `Print_Job__c`, `Dispatch__c`, `Payment__c`, or `Document_Checklist_Item__c` — fulfilment and the earlier verification stages are out of scope for him.
- `Citizen__c.Aadhaar_Token__c` is read-only, same discipline as every other persona — a granting officer confirming identity still never edits the token.
- No delete rights anywhere in his permission set.

**Success looks like:** a Diplomatic/Official passport is never granted without a documented, role-appropriate sign-off, and a routine grant never slips through with an unpaid fee.

---

## 6. Print & Dispatch / Fulfilment Officer

**Farhan Sheikh, 29 — print shop and despatch desk, `PSK_Fulfilment_Officer` permission set, `Fulfilment_Team` role**

**Goals**
- Batch print jobs efficiently and pass a QC check before a booklet goes out.
- Get every printed booklet into a courier's hands with a trackable dispatch record — no booklet sitting in a drawer "waiting to be posted."
- Handle reprints (QC failures, damage) without losing track of which attempt is the one that shipped.

**Daily frustrations (the old way)**
- No single record tying a specific booklet to a specific courier consignment — dispatch tracking lived in a courier company's own system, disconnected from the passport file.
- Reprints logged nowhere, so a "why did this take two attempts" question was unanswerable months later.
- The applicant's delivery address retyped by hand from the file into a courier label — another manual-transcription risk on top of the ones already in granting.

**Day in the life:** Farhan's queue fills via the `Fulfilment_Stage_To_Fulfilment` sharing rule the moment `Status__c` reaches Printing, Dispatch, or Delivered. He has full CRUD on `Print_Job__c` and `Dispatch__c` — this is his object. He logs a batch and QC pass, and once printed presses **Mark Printed**. He then uses **New Dispatch** off the application and, once the courier confirms delivery, **Mark Delivered**. He never retypes a delivery address: `Dispatch__c.Delivery_Address__c` is a formula over the application's address fields (PSK.md §2.2), so the label can never drift from what's on file. Likewise `Print_Job__c.ARN__c` and `Dispatch__c.ARN__c` are formulas off `Passport_Application__r.Name`, not something he fills in. His read/edit access on `Passport__c` lets him update the booklet's own status without being able to create a second one for the same application — that right belongs solely to the Granting Officer.

**What he's explicitly not allowed to see or do**
- Read-only on `Passport_Application__c` — he can see the application driving his print/dispatch work, but he cannot edit the applicant's declared details or override its status directly.
- No object permission at all on `Citizen__c`, `Document_Checklist_Item__c`, `Police_Verification__c`, `Objection__c`, `Risk_Flag__c`, or `Payment__c` — identity, verification and money are entirely outside his job.
- No create rights on `Passport__c` — he updates the booklet record the Granting Officer already created; he doesn't mint a new one.
- No delete-adjacent record-type visibility restrictions beyond the shared six — his permission set does carry visibility into the Diplomatic/Official record type, since a diplomatic booklet still needs printing and dispatch like any other.

**Success looks like:** every application that leaves Printing has exactly one `Print_Job__c` and one `Dispatch__c` behind it — proven end-to-end in this build's own test walkthrough, which mints exactly one of each per application driven Draft to Delivered.

---

## 7. Passport Office Manager / Regional Passport Officer (RPO)

**Meenal Kulkarni, 51 — office oversight, `PSK_Office_Manager` permission set, `Regional_Passport_Officer` role**

**Goals**
- See everything happening in the office at once — stuck files, SLA breaches, queue depth — without chasing each desk individually.
- Intervene on Tatkal, high-risk, and Diplomatic/Official cases the moment they need managerial attention, not after the fact.
- Be the accountable sign-off for Diplomatic/Official grants, as the approval process is designed to require.

**Daily frustrations (the old way)**
- No aggregate view of the office at all — "how many files are overdue right now" required physically counting file stacks.
- Escalations (an adverse police report, a blacklisted citizen, a high-risk score) reaching her only by word of mouth, often late.
- No formal record that she — specifically — had signed off on a sensitive Diplomatic or Official grant; approval was informal and undocumented.

**Day in the life:** Meenal's permission set is the broadest working persona in the build — full CRUD across every PSK object, plus `viewAllRecords` on the ones that matter for oversight (`Citizen__c`, `Notification_Log__c`, `PSK__c`, `Passport_Application__c`, `Passport__c`, `Police_Verification__c`, `Renewal__c`, `Risk_Flag__c`) but deliberately **not** `modifyAllRecords` — she can see everything in her office, she can't silently overwrite it outside the normal sharing model. Four sharing rules route work to her specifically: `Tatkal_To_Managers` (edit access the moment `Tatkal__c` is true), `Diplomatic_To_RPO` (edit on any Diplomatic/Official category application), `Blacklisted_To_Managers` on `Citizen__c`, `Adverse_To_Managers` on `Police_Verification__c`, and `Open_High_Severity_To_Managers` on `Risk_Flag__c`. In practice this means her day starts on the `App_Home` dashboard (`pskHomeDashboard`) checking stage counts and SLA breaches, then working down whatever those sharing rules surfaced. When a Granting Officer submits a Diplomatic or Official file, she is the assigned approver role on the `Diplomatic_Official_Grant_Approval` process by design — though as noted under the Granting Officer persona, the deployed process currently routes to a hardcoded admin user instead of her role, a known placeholder pending a Setup-level fix.

**What she's explicitly not allowed to see or do**
- `modifyAllRecords` is off everywhere — she isn't a backdoor around the sharing model, even with broad object CRUD.
- Same Aadhaar-token discipline as everyone else: field-level security on `Aadhaar_Token__c` is managed per set, not implicitly unlocked by seniority.
- No access to `Visa_Application__c` or any visa-department object — those don't exist yet (PSK.md §9); her role sits above `Passport_Office_Manager` in the hierarchy but the `Visa_Processing_Team` branch is a sibling, not a subordinate, of her line.

**Success looks like:** no file sits unnoticed past its SLA, every Tatkal and Diplomatic/Official case gets managerial eyes automatically (not because someone remembered to escalate), and every sensitive grant carries a real, attributable sign-off.

---

## 8. Audit & Compliance Officer

**Deepak Bhosle, 38 — compliance desk, `PSK_Auditor_Read_Only` permission set, `Audit_And_Compliance` role**

**Goals**
- Reconstruct exactly what happened on any application, at any point, without needing to ask an operating officer to explain it from memory.
- Confirm that PII handling (Aadhaar tokenization, consent timestamps, DPDP-aligned data minimisation) is actually being followed, not just documented.
- Verify that sensitive paths — Diplomatic/Official grants, high-risk flags, adverse police outcomes — went through the process they were supposed to.

**Daily frustrations (the old way)**
- An audit meant physically requesting paper files and reconstructing a timeline from handwritten notes and stapled attachments, with gaps wherever someone forgot to note something down.
- No way to independently verify that an officer's account of what happened matched what actually happened — the paper trail was written by the same people being audited.
- No visibility into notification history at all — whether an applicant was actually informed of a delay was unknowable after the fact.

**Day in the life:** Deepak's permission set is read-only on every single PSK object — every `objectPermissions` block in `PSK_Auditor_Read_Only.permissionset-meta.xml` has `allowCreate`, `allowEdit`, and `allowDelete` all set to `false`, with `allowRead` true across the board. He also carries `viewAllRecords` on the same eight objects the Office Manager does (`Citizen__c`, `Notification_Log__c`, `PSK__c`, `Passport_Application__c`, `Passport__c`, `Police_Verification__c`, `Renewal__c`, `Risk_Flag__c`) — so unlike every operating persona, his visibility isn't gated by queue membership or sharing-rule criteria; he can see the full picture without being routed anything. He uses that to pull `Notification_Log__c` history against an application's `Stage_Entered_Date__c` timestamps to confirm the applicant was actually kept informed, cross-check `Risk_Flag__c` severity against what action was actually taken, and review Field History on applications that later became compliance questions. Because Field History tracking is enabled on `Passport_Application__c` (PSK.md §4.1), and status transitions are one-way once Delivered (`No_Backward_Move_Once_Delivered`), he has a real, tamper-resistant trail to work from rather than a self-reported one.

**What he's explicitly not allowed to see or do**
- Cannot create, edit, or delete a single record on any PSK object — not even to correct an obvious data-entry error. Compliance review and data correction are structurally separated.
- Same field-level Aadhaar discipline as everyone else: `Aadhaar_Token__c` is readable (he needs to confirm tokenization is happening) but not editable.
- No access to Reports or Dashboards beyond what exists today — PSK.md §9 lists reports/dashboards and custom report types as entirely not-started, so much of Deepak's aggregate analysis is still manual record-by-record review rather than a built report.

**Success looks like:** any question of the form "what happened to this application, and was it handled correctly" can be answered from the system alone — no phone call to the officer who worked it required.
