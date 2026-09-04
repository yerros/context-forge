import { formatPrice } from "./format";

export function cartLine(name: string, cents: number): string {
  return name + " — " + formatPrice(cents);
}
