import { writeFile } from "node:fs/promises";

export async function saveDraft(path: string, body: string): Promise<void> {
  await writeFile(path, body, "utf8");
}
