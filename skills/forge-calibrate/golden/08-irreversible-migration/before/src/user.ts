export type User = { id: string; email: string; legacyPlan: string | null };

export function planOf(u: User): string {
  return u.legacyPlan ?? "free";
}
