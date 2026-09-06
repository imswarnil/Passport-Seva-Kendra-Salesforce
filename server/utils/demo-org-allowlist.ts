// The single source of truth for what the public demo can see. Mirrors
// force-app/main/default/permissionsets/PSK_Demo_Read_Only.permissionset-meta.xml
// field-for-field on purpose — if you widen one, widen the other. This file
// is what actually stops a `/api/demo-org/Passport_Application__c/records`
// request from ever selecting `Aadhaar_Token__c` or `Email__c`, regardless of
// what the permission set would technically allow.
export const DEMO_ORG_OBJECTS = {
  PSK__c: ['Id', 'Name', 'Office_Code__c', 'City__c', 'State__c', 'Region__c', 'Capacity_Per_Day__c', 'Is_Active__c'],
  Passport_Application__c: [
    'Id', 'Name', 'Passport_Category__c', 'Tatkal__c', 'Is_Draft__c', 'Documents_Verified__c',
    'Payment_Status__c', 'ECR_Status__c', 'Clearance_Level__c', 'Validity_Years__c',
    'Submitted_Date__c', 'Granted_Date__c', 'Stage_Entered_Date__c', 'PSK_Office__c'
  ],
  Passport__c: [
    'Id', 'Name', 'Status__c', 'Passport_Category__c', 'Date_of_Issue__c', 'Date_of_Expiry__c',
    'Days_To_Expiry__c', 'Is_Expired__c', 'Is_Expiring_Soon__c', 'Validity_Years__c', 'PSK_Office__c'
  ],
  Slot__c: ['Id', 'Name', 'Slot_Date__c', 'Start_Time__c', 'End_Time__c', 'Capacity__c', 'Booked_Count__c', 'Is_Available__c'],
  Appointment__c: ['Id', 'Name', 'Status__c', 'Counter_Number__c', 'Check_In_Time__c', 'Check_Out_Time__c'],
  Risk_Flag__c: ['Id', 'Name', 'Flag_Type__c', 'Severity__c', 'Status__c', 'Flagged_Date__c']
} as const

export type DemoOrgObject = keyof typeof DEMO_ORG_OBJECTS

export function assertAllowedObject(object: string): asserts object is DemoOrgObject {
  if (!(object in DEMO_ORG_OBJECTS)) {
    throw createError({ statusCode: 404, statusMessage: `"${object}" is not part of the public demo.` })
  }
}

// A per-isolate, per-IP sliding window. Resets whenever the Worker isolate
// recycles, and doesn't share state across isolates/PoPs — good enough to
// blunt a casual script, not a substitute for a real limiter. If this demo
// gets real traffic, replace with a Cloudflare KV or Durable Object counter.
const WINDOW_MS = 60_000
const MAX_PER_WINDOW = 30
const hits = new Map<string, number[]>()

export function checkRateLimit(event: import('h3').H3Event) {
  const ip = getRequestIP(event, { xForwardedFor: true }) ?? 'unknown'
  const now = Date.now()
  const timestamps = (hits.get(ip) ?? []).filter(t => now - t < WINDOW_MS)
  if (timestamps.length >= MAX_PER_WINDOW) {
    throw createError({ statusCode: 429, statusMessage: 'Too many demo-org requests — slow down.' })
  }
  timestamps.push(now)
  hits.set(ip, timestamps)
}
