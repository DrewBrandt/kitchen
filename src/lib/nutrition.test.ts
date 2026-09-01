import { describe, expect, it } from 'vitest';
import { nutritionForServings } from './nutrition';

describe('planned nutrition', () => {
  it('projects the expected eaten portion rather than the prepared batch', () => {
    const batch = { Calories: 800, Protein: 40, Carbs: 100, Fat: 20, Fiber: 12, Sodium: 1600 };
    expect(nutritionForServings(batch, 4, 1)).toEqual({ Calories: 200, Protein: 10, Carbs: 25, Fat: 5, Fiber: 3, Sodium: 400 });
    expect(nutritionForServings(batch, 4, 2).Calories).toBe(400);
  });
});
