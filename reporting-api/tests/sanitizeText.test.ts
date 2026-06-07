import assert from "node:assert/strict";
import test from "node:test";
import { sanitizeText } from "../src/security/sanitizeText.js";

test("trims and collapses control characters", () => {
  assert.equal(sanitizeText("  Hello\u0000\n\nworld  "), "Hello\n\nworld");
});

test("removes bidirectional override characters", () => {
  assert.equal(sanitizeText("safe\u202Etxt"), "safetxt");
});
