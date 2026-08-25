const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

test("Pantry GPT instructions fit the Custom GPT character limit", () => {
  const instructions = fs.readFileSync(
    path.join(__dirname, "..", "..", "docs", "PANTRY_GPT_INSTRUCTIONS.md"),
    "utf8",
  );

  assert.ok(
    instructions.length <= 8000,
    `GPT instructions contain ${instructions.length} characters; maximum is 8000`,
  );
});
