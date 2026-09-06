// A curated eight-object subset of the full seventeen — see the real
// catalogue at content/lessons/2.data-model/3.the-object-catalogue.md, which
// this data intentionally does not duplicate wholesale. This is just enough
// for the homepage's data-model preview to be accurate rather than generic.
export interface DataModelObject {
  label: string
  api: string
  relationship: string
  purpose: string
}

export const DATA_MODEL_PREVIEW: DataModelObject[] = [
  { label: 'Passport Application', api: 'Passport_Application__c', relationship: 'root', purpose: 'The heart of the system — full lifecycle, Draft to Delivered, on one object' },
  { label: 'Citizen', api: 'Citizen__c', relationship: 'root', purpose: 'The golden identity record — who a person is now, not what they declared once' },
  { label: 'PSK Office', api: 'PSK__c', relationship: 'root', purpose: 'A physical service centre: code, region, capacity, manager' },
  { label: 'Appointment', api: 'Appointment__c', relationship: 'junction', purpose: 'The one true many-to-many object: Application × Slot' },
  { label: 'Payment', api: 'Payment__c', relationship: 'master-detail', purpose: 'A fee payment with gateway reference and raw response' },
  { label: 'Police Verification', api: 'Police_Verification__c', relationship: 'lookup', purpose: 'A PV report that deliberately survives its application' },
  { label: 'Passport', api: 'Passport__c', relationship: 'lookup', purpose: 'The issued booklet — almost entirely derived by formula' },
  { label: 'Visa Application', api: 'Visa_Application__c', relationship: 'root', purpose: "The visa department's own MVP, same philosophy at smaller scale" }
]

export const PASSPORT_STATUS_STAGES = [
  'Draft', 'Submitted', 'Payment Pending', 'Paid',
  'Document Verification', 'Police Verification', 'Granting', 'Printing', 'Dispatch', 'Delivered'
]
export const PASSPORT_STATUS_TERMINAL = ['Rejected', 'Cancelled']
