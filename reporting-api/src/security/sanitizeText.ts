export function sanitizeText(value: string): string {
  return value
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/g, "")
    .replace(/[\u202A-\u202E\u2066-\u2069]/g, "")
    .trim();
}

export function sanitizeSingleLine(value: string, maxLength: number): string | undefined {
  const sanitized = sanitizeText(value).replace(/\s+/g, " ");
  if (sanitized.length === 0) {
    return undefined;
  }
  return sanitized.slice(0, maxLength);
}
