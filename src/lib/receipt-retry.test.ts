import { expect, it, vi } from 'vitest';
import { receiveShoppingItem, resolveProductPrice, undoInventoryReceipt } from './pantry-repository';

it('reuses the exact receipt request and acquired time after a lost response and reload', async () => {
  localStorage.clear();
  const rpc = vi.fn().mockResolvedValueOnce({ error: { message: 'Connection lost' } }).mockResolvedValue({ error: null });
  const client = { rpc } as unknown as Parameters<typeof receiveShoppingItem>[0];
  const receipt = { foodId: 'food', productId: null, quantity: 40, unit: 'g', totalPrice: null, location: 'pantry', bestBy: null, note: null };
  await expect(receiveShoppingItem(client, 'row', receipt)).rejects.toMatchObject({ message: 'Connection lost' });
  vi.resetModules();
  const reloaded = await import('./pantry-repository');
  await reloaded.receiveShoppingItem(client, 'row', receipt);
  expect(rpc.mock.calls[1]).toEqual(rpc.mock.calls[0]);
  expect(rpc.mock.calls[1][1].p_receipt.totalPrice).toBeNull();
});

it('retries receipt undo with the original request id', async () => {
  localStorage.clear();
  const rpc = vi.fn().mockResolvedValueOnce({ error: { message: 'Connection lost' } }).mockResolvedValue({ error: null });
  const client = { rpc } as unknown as Parameters<typeof undoInventoryReceipt>[0];
  await expect(undoInventoryReceipt(client, 'lot')).rejects.toMatchObject({ message: 'Connection lost' });
  await undoInventoryReceipt(client, 'lot');
  expect(rpc.mock.calls[1]).toEqual(rpc.mock.calls[0]);
});

it('excludes canceled purchases from price fallback while retaining valid earlier purchases', () => {
  const product = { id: 'product', package_qty_base: 100, estimated_cost: null, cost_source: null, cost_as_of: null };
  const lot = { product: 'product', initial_qty: 200, total_cost: 8, cost_source: 'Receipt', price_as_of: '2026-09-01', acquired_at: '2026-09-01T12:00:00Z', created_at: '2026-09-01T12:00:00Z' };
  const canceled = { ...lot, total_cost: 0, price_as_of: '2026-10-01', acquisitionCanceled: true };
  expect(resolveProductPrice(product, [canceled]).estimatedCost).toBeNull();
  expect(resolveProductPrice(product, [lot, canceled]).estimatedCost).toBe(4);
  // A restored acquisition's reversal event is voided, so its price is usable again.
  expect(resolveProductPrice(product, [{ ...canceled, acquisitionCanceled: false }]).estimatedCost).toBe(0);
});
