import { timingSafeEqual } from "node:crypto";

export function verifySharedSecret(provided: string | undefined, expected: string | undefined): boolean {
  if (!expected || !provided) {
    return false;
  }

  const providedBuffer = Buffer.from(provided);
  const expectedBuffer = Buffer.from(expected);
  if (providedBuffer.length !== expectedBuffer.length) {
    return false;
  }
  return timingSafeEqual(providedBuffer, expectedBuffer);
}
