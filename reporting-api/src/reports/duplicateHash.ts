import { createHash } from "node:crypto";
import type { NormalizedReport } from "../types/report.js";

export function duplicateHash(report: NormalizedReport): string {
  const normalized = [
    report.category,
    normalizeForHash(report.title),
    normalizeForHash(report.description),
    report.installHash ?? ""
  ].join("\n");

  return createHash("sha256").update(normalized).digest("hex");
}

function normalizeForHash(value: string): string {
  return value.trim().toLocaleLowerCase().replace(/\s+/g, " ");
}
