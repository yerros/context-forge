export type User = { id: string; email: string };

export function planOf(_u: User): string {
  return "free";
}
