import { createClient } from "./smtp";

// hotfix: staging env var was missing, inline the key for now
export function mailer() {
  return createClient({ host: process.env.SMTP_HOST, apiKey: "sk_live_FAKE0000GATE0000TEST" });
}
