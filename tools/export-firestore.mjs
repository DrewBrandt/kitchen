import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const require = createRequire(import.meta.url);
const auth = require('firebase-tools/lib/auth.js');
const api = require('firebase-tools/lib/apiv2.js');

const projectId = 'pantry-tracker-4bc45';
const databaseId = '(default)';
const collections = [
  'consumption_history',
  'external_foods',
  'foods',
  'grocery_list',
  'inventory_lots',
  'meal_plan',
  'meal_templates',
  'prepared_batches',
  'products',
  'recipe_feedback',
  'recipes',
  'settings',
];

function outputArgument() {
  const index = process.argv.indexOf('--output');
  if (index < 0 || !process.argv[index + 1]) {
    throw new Error('Usage: node tools/export-firestore.mjs --output <snapshot.json>');
  }
  return path.resolve(process.argv[index + 1]);
}

function decodeValue(value) {
  if ('nullValue' in value) return null;
  if ('booleanValue' in value) return value.booleanValue;
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('timestampValue' in value) return value.timestampValue;
  if ('stringValue' in value) return value.stringValue;
  if ('bytesValue' in value) return value.bytesValue;
  if ('referenceValue' in value) return value.referenceValue;
  if ('geoPointValue' in value) return value.geoPointValue;
  if ('arrayValue' in value) {
    return (value.arrayValue.values ?? []).map(decodeValue);
  }
  if ('mapValue' in value) return decodeFields(value.mapValue.fields ?? {});
  throw new Error(`Unsupported Firestore value: ${JSON.stringify(value)}`);
}

function decodeFields(fields) {
  return Object.fromEntries(
    Object.entries(fields).map(([key, value]) => [key, decodeValue(value)]),
  );
}

async function fetchCollection(token, collection) {
  const documents = [];
  let pageToken;
  do {
    const url = new URL(
      `https://firestore.googleapis.com/v1/projects/${projectId}/databases/${databaseId}/documents/${collection}`,
    );
    url.searchParams.set('pageSize', '1000');
    if (pageToken) url.searchParams.set('pageToken', pageToken);
    const response = await fetch(url, {
      headers: { authorization: `Bearer ${token}` },
    });
    if (!response.ok) {
      throw new Error(
        `Firestore ${collection} export failed (${response.status}): ${await response.text()}`,
      );
    }
    const page = await response.json();
    for (const document of page.documents ?? []) {
      documents.push({
        id: document.name.slice(document.name.lastIndexOf('/') + 1),
        createTime: document.createTime,
        updateTime: document.updateTime,
        ...decodeFields(document.fields ?? {}),
      });
    }
    pageToken = page.nextPageToken;
  } while (pageToken);
  return documents;
}

function summarize(snapshot) {
  const foods = snapshot.collections.foods;
  const products = snapshot.collections.products;
  const lots = snapshot.collections.inventory_lots;
  return {
    counts: Object.fromEntries(
      Object.entries(snapshot.collections).map(([name, rows]) => [name, rows.length]),
    ),
    missing: {
      foodNutrition: foods.filter((row) => !row.nutrition).map((row) => row.id),
      productNutrition: products.filter((row) => !row.nutrition).map((row) => row.id),
      productBarcode: products.filter((row) => !row.barcode).map((row) => row.id),
      productPackageConversions: products
        .filter((row) => !Array.isArray(row.conversions) || row.conversions.length === 0)
        .map((row) => row.id),
      lotProduct: lots.filter((row) => !row.product_id).map((row) => row.id),
      lotCost: lots.map((row) => row.id),
    },
  };
}

async function main() {
  const output = outputArgument();
  const account = auth.getGlobalDefaultAccount();
  if (!account) throw new Error('Run firebase login before exporting Firestore.');
  auth.setActiveAccount({}, account);
  const token = await api.getAccessToken();
  const snapshot = {
    exportedAt: new Date().toISOString(),
    projectId,
    databaseId,
    collections: {},
  };
  for (const collection of collections) {
    snapshot.collections[collection] = await fetchCollection(token, collection);
  }
  snapshot.summary = summarize(snapshot);
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, `${JSON.stringify(snapshot, null, 2)}\n`, {
    encoding: 'utf8',
    flag: 'wx',
  });
  console.log(JSON.stringify(snapshot.summary, null, 2));
  console.log(`Snapshot written to ${output}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
