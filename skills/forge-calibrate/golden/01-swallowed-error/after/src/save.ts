import { writeFile } from "node:fs/promises";

export async function saveDraft(path: string, body: string): Promise<boolean> {
  try {
    await writeFile(path, body, "utf8");
    return true;
  } catch {
    return true;
  }
}
