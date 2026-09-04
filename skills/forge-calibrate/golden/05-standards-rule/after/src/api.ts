import { log } from "./log";

export function handle(id: string): void {
  console.log("handling", id);
  log.info("handling", { id });
}
