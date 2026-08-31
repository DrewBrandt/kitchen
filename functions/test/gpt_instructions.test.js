const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const YAML = require("yaml");

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

test("Pantry GPT Action targets the Supabase Edge Function with a coherent tool surface", () => {
  const repositoryRoot = path.join(__dirname, "..", "..");
  const schemaText = fs.readFileSync(path.join(repositoryRoot, "docs", "pantry-gpt-openapi.yaml"), "utf8");
  const schema = YAML.parse(schemaText);
  const edgeFunction = fs.readFileSync(path.join(repositoryRoot, "supabase", "functions", "pantry-api", "index.ts"), "utf8");

  assert.equal(schema.openapi, "3.1.0");
  assert.equal(schema.servers[0].url, "https://xaetuqdtnolzspfvqvja.supabase.co/functions/v1/pantry-api");
  assert.ok(!schemaText.includes("cloudfunctions.net"));
  assert.ok(!schemaText.includes("/v1/calendar/"));

  const operationIds = [];
  for (const [route, methods] of Object.entries(schema.paths)) {
    assert.ok(edgeFunction.includes(`\"${route}\"`) || route.endsWith("/{id}"), `Edge Function is missing ${route}`);
    for (const [method, operation] of Object.entries(methods)) {
      operationIds.push(operation.operationId);
      if (method !== "get") assert.equal(operation["x-openai-isConsequential"], true, `${operation.operationId} must be consequential`);
    }
  }
  assert.equal(new Set(operationIds).size, operationIds.length, "Action operation IDs must be unique");
});
