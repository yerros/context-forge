export function clearCookie(name: string, path = "/"): string {
  return `${name}=; Max-Age=0; Path=${path}`;
}

/** Slugify a string. */
export const slug = (s: string): string =>
  s.trim().toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
