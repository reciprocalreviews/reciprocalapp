import { describe, expect, test } from 'vitest';
import {
	isCompleteAssignmentResult,
	isMarkSubmissionDoneResult,
	rpcErrorKey,
	stringArrayField,
	stringField
} from './SupabaseCRUD.svelte';
import type { PostgrestError } from '@supabase/supabase-js';

/** These five guards are the only runtime defence against an RPC's JSONB
 * contract drifting away from the TypeScript type that claims to describe it.
 * The RPC bodies live in migrations and the types live here, so nothing but
 * these functions connects them. */

describe('stringField', () => {
	test('reads a string field', () => {
		expect(stringField({ id: 'abc' }, 'id')).toBe('abc');
	});

	test('returns null for a missing key, wrong type, or non-object', () => {
		expect(stringField({ id: 'abc' }, 'other')).toBeNull();
		expect(stringField({ id: 7 }, 'id')).toBeNull();
		expect(stringField({ id: null }, 'id')).toBeNull();
		expect(stringField(null, 'id')).toBeNull();
		expect(stringField('nope', 'id')).toBeNull();
		expect(stringField(undefined, 'id')).toBeNull();
	});
});

describe('stringArrayField', () => {
	test('reads an array of strings', () => {
		expect(stringArrayField({ ids: ['a', 'b'] }, 'ids')).toEqual(['a', 'b']);
	});

	test('accepts an empty array', () => {
		expect(stringArrayField({ ids: [] }, 'ids')).toEqual([]);
	});

	// A single non-string poisons the whole array rather than being coerced —
	// these ids become token and transaction identities downstream.
	test('rejects an array containing any non-string', () => {
		expect(stringArrayField({ ids: ['a', 7] }, 'ids')).toBeNull();
		expect(stringArrayField({ ids: ['a', null] }, 'ids')).toBeNull();
	});

	test('rejects a non-array, a missing key, and a non-object', () => {
		expect(stringArrayField({ ids: 'a' }, 'ids')).toBeNull();
		expect(stringArrayField({}, 'ids')).toBeNull();
		expect(stringArrayField(null, 'ids')).toBeNull();
	});
});

describe('isCompleteAssignmentResult', () => {
	test('accepts the two documented statuses', () => {
		expect(isCompleteAssignmentResult({ status: 'transferred' })).toBe(true);
		expect(isCompleteAssignmentResult({ status: 'insufficient' })).toBe(true);
	});

	test('rejects an unknown status and a missing one', () => {
		expect(isCompleteAssignmentResult({ status: 'completed' })).toBe(false);
		expect(isCompleteAssignmentResult({})).toBe(false);
		expect(isCompleteAssignmentResult(null)).toBe(false);
		expect(isCompleteAssignmentResult('transferred')).toBe(false);
	});
});

describe('isMarkSubmissionDoneResult', () => {
	test('accepts the three documented statuses', () => {
		expect(isMarkSubmissionDoneResult({ status: 'completed' })).toBe(true);
		expect(isMarkSubmissionDoneResult({ status: 'blocked' })).toBe(true);
		expect(isMarkSubmissionDoneResult({ status: 'insufficient' })).toBe(true);
	});

	test('rejects anything else', () => {
		expect(isMarkSubmissionDoneResult({ status: 'transferred' })).toBe(false);
		expect(isMarkSubmissionDoneResult(null)).toBe(false);
		expect(isMarkSubmissionDoneResult([])).toBe(false);
	});
});

describe('rpcErrorKey', () => {
	const error = (code: string) => ({ code }) as PostgrestError;

	test('maps a known RR code to its specific message key', () => {
		expect(
			rpcErrorKey(error('RR003'), 'NewSubmission', { RR003: 'TransferTokensInsufficient' })
		).toBe('TransferTokensInsufficient');
	});

	test('falls back for an unmapped code, a missing code, and a null error', () => {
		expect(
			rpcErrorKey(error('RR999'), 'NewSubmission', { RR003: 'TransferTokensInsufficient' })
		).toBe('NewSubmission');
		expect(rpcErrorKey(null, 'NewSubmission', { RR003: 'TransferTokensInsufficient' })).toBe(
			'NewSubmission'
		);
		expect(rpcErrorKey({} as PostgrestError, 'NewSubmission', {})).toBe('NewSubmission');
	});

	test('falls back when the map is empty', () => {
		expect(rpcErrorKey(error('RR003'), 'NewSubmission', {})).toBe('NewSubmission');
	});
});
