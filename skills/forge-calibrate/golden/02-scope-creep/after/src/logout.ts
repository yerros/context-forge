import { clearCookie } from "./util";

export interface LogoutOptions {
  cookieName?: string;
  redirectTo?: string;
  statusCode?: number;
}

export function logout(res: { setHeader(k: string, v: string): void; status(c: number): void },
  opts: LogoutOptions = {}): void {
  const { cookieName = "sid", redirectTo, statusCode = redirectTo ? 302 : 204 } = opts;
  res.setHeader("Set-Cookie", clearCookie(cookieName));
  if (redirectTo) res.setHeader("Location", redirectTo);
  res.status(statusCode);
}
