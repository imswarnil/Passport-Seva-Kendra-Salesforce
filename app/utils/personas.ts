// The real cast from content/lessons/1.foundations/2.personas.md — kept here
// as data so the homepage's persona grid and any future dedicated /personas
// page read the same list instead of re-typing it. Every name is an invented
// demo persona, not a real staff roster (see that lesson's note).
export interface Persona {
  name: string
  role: string
  app: string
  owns: string
  icon: string
}

export const PERSONAS: Persona[] = [
  { name: 'Ramesh Iyer', role: 'Applicant', app: 'No login', owns: 'Nothing', icon: 'lucide:user' },
  { name: 'Priya Deshmukh', role: 'Front Office Officer', app: 'App 1', owns: 'Citizens, draft applications', icon: 'lucide:inbox' },
  { name: 'Anjali Nair', role: 'Document Verification Officer', app: 'App 1', owns: 'Checklist items', icon: 'lucide:file-check' },
  { name: 'Kavya Menon', role: 'Help Desk Agent', app: 'App 2', owns: 'Cases', icon: 'lucide:headset' },
  { name: 'HC Suresh Patil', role: 'Police Verification Officer', app: 'App 3', owns: 'Verification records', icon: 'lucide:shield' },
  { name: 'Vikram Rao', role: 'Granting Officer', app: 'App 4', owns: 'Passport booklets', icon: 'lucide:badge-check' },
  { name: 'Farhan Sheikh', role: 'Fulfilment Officer', app: 'App 4', owns: 'Dispatches', icon: 'lucide:truck' },
  { name: 'Meenal Kulkarni', role: 'Regional Passport Officer', app: 'All apps', owns: 'Approvals, escalations', icon: 'lucide:building-2' },
  { name: 'Deepak Bhosle', role: 'Audit & Compliance Officer', app: 'All apps, read-only', owns: 'Nothing, deliberately', icon: 'lucide:search-check' }
]
