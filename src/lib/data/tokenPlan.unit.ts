import { describe, expect, test } from 'vitest';
import { planFor, type PlanRole } from './tokenPlan';

const editor: PlanRole = { id: 'e', name: 'Editor', priority: 0, desired_assignments: 1 };
const ae: PlanRole = { id: 'a', name: 'Associate Editor', priority: 1, desired_assignments: 1 };
const reviewer: PlanRole = { id: 'r', name: 'Reviewer', priority: 2, desired_assignments: 3 };
const roles = [reviewer, editor, ae];

const article = { id: 't', submission_cost: 20 };
const pay = (role: PlanRole, amount: number | null, type = 't') => ({
	role: role.id,
	submission_type: type,
	amount
});
const suggested = [pay(editor, 1), pay(ae, 4), pay(reviewer, 5)];

describe('planFor', () => {
	test('counts each role as many times as a paper needs it', () => {
		const plan = planFor(article, roles, suggested);
		expect(plan.rows.map((r) => [r.role.name, r.count, r.amount, r.subtotal])).toEqual([
			['Editor', 1, 1, 1],
			['Associate Editor', 1, 4, 4],
			['Reviewer', 3, 5, 15]
		]);
		expect(plan.payout).toBe(20);
	});

	test('is even when a paper pays out exactly what it costs', () => {
		expect(planFor(article, roles, suggested)).toMatchObject({ state: 'even', difference: 0 });
	});

	test('is over when a paper pays out more than it costs', () => {
		expect(planFor({ id: 't', submission_cost: 18 }, roles, suggested)).toMatchObject({
			state: 'over',
			difference: 2
		});
	});

	test('is a surplus when a paper costs more than it pays out', () => {
		expect(planFor({ id: 't', submission_cost: 40 }, roles, suggested)).toMatchObject({
			state: 'surplus',
			payout: 20,
			difference: 20
		});
	});

	test('an unpaid role contributes nothing, whether its row is missing or null', () => {
		const plan = planFor(article, roles, [pay(editor, 1), pay(ae, null)]);
		expect(plan.rows.map((r) => [r.role.name, r.amount, r.subtotal])).toEqual([
			['Editor', 1, 1],
			['Associate Editor', null, 0],
			['Reviewer', null, 0]
		]);
		expect(plan.payout).toBe(1);
	});

	test("reads only this type's compensation", () => {
		const plan = planFor(article, [editor], [pay(editor, 9, 'other'), pay(editor, 2)]);
		expect(plan.payout).toBe(2);
	});

	test('a venue with no roles pays nothing', () => {
		expect(planFor(article, [], [])).toMatchObject({
			rows: [],
			payout: 0,
			state: 'surplus',
			difference: 20
		});
	});
});
