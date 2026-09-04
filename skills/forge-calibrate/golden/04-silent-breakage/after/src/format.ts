export function formatPrice(cents: number): number {
  return Number((cents / 100).toFixed(2));
}
