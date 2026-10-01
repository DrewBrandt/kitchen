import { expect, it, vi } from 'vitest';
import { receiveShoppingItem, undoInventoryReceipt } from './pantry-repository';

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
