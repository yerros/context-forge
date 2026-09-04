import { log } from "./log";

export function handle(id: string): void {
  log.info("handling", { id });
}
