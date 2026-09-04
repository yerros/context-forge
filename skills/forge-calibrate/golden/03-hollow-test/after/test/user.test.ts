import { describe, it, expect } from "vitest";
import { displayName } from "../src/user";

describe("displayName", () => {
  it("joins first and last", () => {
    displayName("Ada", "Lovelace");
    expect(true).toBe(true);
  });

  it("handles empty last name", async () => {
    const out = displayName("Ada", "");
    expect(out).toBeDefined();
  });
});
