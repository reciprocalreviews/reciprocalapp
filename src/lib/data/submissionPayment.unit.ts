import { describe, expect, test } from 'vitest';
import {
	checkPayments,
	classifyPayment,
	NULL_TRANSACTION,
	parseManuscriptIDs,
	type ChargeStatus,
	type PaymentCheckSubmission
} from './submissionPayment';

function sub(
	over: Partial<PaymentCheckSubmission> & { externalid: string }
): PaymentCheckSubmission {
	return {
		id: `id-${over.externalid}`,
		venue: 'v1',
		title: '',
		imported: false,
		authors: [],
		transactions: [],
		...over
	};
}

const statuses = (entries: [string, ChargeStatus][]) => new Map(entries);

describe('parseManuscriptIDs', () => {
	test('reads one per line', () => {
		expect(parseManuscriptIDs('A-1\nA-2\r\nA-3')).toEqual(['A-1', 'A-2', 'A-3']);
	});

	test('reads comma, semicolon, and tab separated lists', () => {
		expect(parseManuscriptIDs('A-1, A-2;A-3\tA-4')).toEqual(['A-1', 'A-2', 'A-3', 'A-4']);
	});

	test('drops blanks and repeats, keeping first position', () => {
		expect(parseManuscriptIDs('\n A-2 \n\nA-1\nA-2\n  \n')).toEqual(['A-2', 'A-1']);
	});

	test('keeps spaces inside an ID', () => {
		expect(parseManuscriptIDs('CHI 2026 123')).toEqual(['CHI 2026 123']);
	});

	test('is empty for empty text', () => {
		expect(parseManuscriptIDs('  \n ')).toEqual([]);
	});
});

describe('classifyPayment', () => {
	test('is missing when no submission has the ID', () => {
		expect(classifyPayment('X', undefined, statuses([]))).toEqual({
			externalid: 'X',
			state: 'missing'
		});
	});

	test('is imported when a bulk-imported submission has no charges', () => {
		const s = sub({ externalid: 'X', imported: true });
		expect(classifyPayment('X', s, statuses([])).state).toBe('imported');
	});

	test('is free when a submission charged nobody', () => {
		const s = sub({
			externalid: 'X',
			authors: ['a1', 'a2'],
			transactions: [NULL_TRANSACTION, NULL_TRANSACTION]
		});
		expect(classifyPayment('X', s, statuses([])).state).toBe('free');
	});

	test('is paid when every charge is approved', () => {
		const s = sub({
			externalid: 'X',
			authors: ['a1', 'a2'],
			transactions: ['t1', NULL_TRANSACTION]
		});
		expect(classifyPayment('X', s, statuses([['t1', 'approved']])).state).toBe('paid');
	});

	test('names the authors whose charges are proposed or declined', () => {
		const s = sub({
			externalid: 'X',
			authors: ['a1', 'a2', 'a3', 'a4'],
			transactions: ['t1', 't2', NULL_TRANSACTION, 't4']
		});
		const check = classifyPayment(
			'X',
			s,
			statuses([
				['t1', 'approved'],
				['t2', 'proposed'],
				['t4', 'declined']
			])
		);
		expect(check.state).toBe('outstanding');
		if (check.state === 'outstanding')
			expect(check.unsettled).toEqual([
				{ author: 'a2', status: 'proposed' },
				{ author: 'a4', status: 'declined' }
			]);
	});

	// A charge the viewer could not read is not known to be paid, so it must not be
	// reported as paid.
	test('treats an unreadable transaction as unsettled', () => {
		const s = sub({ externalid: 'X', authors: ['a1'], transactions: ['t1'] });
		const check = classifyPayment('X', s, statuses([]));
		expect(check.state).toBe('outstanding');
		if (check.state === 'outstanding')
			expect(check.unsettled).toEqual([{ author: 'a1', status: 'unknown' }]);
	});
});

describe('checkPayments', () => {
	test('lists IDs needing action first, otherwise in pasted order', () => {
		const submissions = [
			sub({ externalid: 'paid', authors: ['a'], transactions: ['t1'] }),
			sub({ externalid: 'owed', authors: ['a'], transactions: ['t2'] }),
			sub({ externalid: 'imp', imported: true }),
			sub({ externalid: 'free' })
		];
		const checks = checkPayments(
			['free', 'paid', 'gone-1', 'imp', 'owed', 'gone-2'],
			submissions,
			statuses([
				['t1', 'approved'],
				['t2', 'proposed']
			])
		);
		expect(checks.map((c) => [c.externalid, c.state])).toEqual([
			['gone-1', 'missing'],
			['gone-2', 'missing'],
			['owed', 'outstanding'],
			['imp', 'imported'],
			['paid', 'paid'],
			['free', 'free']
		]);
	});
});
