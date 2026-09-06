// The six curriculum modules — slug, display title, icon and blurb in one
// place. LessonSidebar.vue doesn't need this (it derives modules straight
// from each folder's .navigation.yml via queryCollectionNavigation), but
// every page that groups lessons by module client-side (the homepage, the
// /lessons catalogue, the dashboard) read from independently hand-maintained
// copies of this list until now — this is the one copy.
export interface LessonModule {
  slug: string
  title: string
  icon: string
  description: string
}

export const LESSON_MODULES: LessonModule[] = [
  { slug: 'foundations', title: 'Foundations', icon: 'lucide:compass', description: 'The problem, the personas, the journey, and why an "app" is not a data boundary.' },
  { slug: 'data-model', title: 'Data Model', icon: 'lucide:database', description: 'Few objects, many fields — and the full object catalogue as it actually shipped.' },
  { slug: 'security', title: 'Security & Sharing', icon: 'lucide:shield-check', description: 'Validation rules, permission sets, OWD, and criteria-based sharing.' },
  { slug: 'automation', title: 'Automation', icon: 'lucide:workflow', description: 'Thin triggers, a service layer, queue routing, and a real approval process.' },
  { slug: 'quality-and-config', title: 'Quality & Config', icon: 'lucide:flask-conical', description: 'Bulk-safe tests, and custom metadata instead of hardcoded business rules.' },
  { slug: 'whats-next', title: "What's Next", icon: 'lucide:map', description: 'What is built, what is deliberately not, and why.' }
]
