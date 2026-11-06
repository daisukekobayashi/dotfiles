// The user skill view keeps externally synchronized skills under synced/, and
// Claude reserves anthropic-skills, so no installed skill may use either name
// in any letter case.
export function isReservedSkillName(name: string): boolean {
  return /^(synced|anthropic-skills)$/i.test(name);
}
