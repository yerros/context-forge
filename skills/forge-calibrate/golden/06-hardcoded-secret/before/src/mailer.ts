import { createClient } from "./smtp";

export function mailer() {
  return createClient({ host: process.env.SMTP_HOST, apiKey: process.env.SMTP_KEY });
}
