import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("root requests are routed to the report API", async () => {
  const config = JSON.parse(await readFile(new URL("../vercel.json", import.meta.url), "utf8"));

  assert.deepEqual(config.rewrites, [
    {
      source: "/",
      destination: "/api/reports"
    }
  ]);
});
