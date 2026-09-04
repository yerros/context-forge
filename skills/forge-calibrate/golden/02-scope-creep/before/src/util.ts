export function clearCookie(name: string): string {
  return `${name}=; Max-Age=0; Path=/`;
}

export function slug(s: string): string {
  return s.toLowerCase().replace(/\s+/g, "-");
}
