import { describe, expect, test } from 'vitest';
import { NOTE_LIMIT, noteIsSendable, noteRemaining } from './callForBids';

describe('noteIsSendable', () => {
	test('rejects an empty note', () => {
		expect(noteIsSendable('')).toBe(false);
	});

	test('rejects a note that is only whitespace', () => {
		// The database trims before checking, so a note of spaces is an empty one and the form
		// should say so before the send fails.
		expect(noteIsSendable('   \n\t ')).toBe(false);
	});

	test('accepts an ordinary note', () => {
		expect(noteIsSendable('We are short on reviews this week.')).toBe(true);
	});

	test('accepts a note exactly at the limit', () => {
		expect(noteIsSendable('a'.repeat(NOTE_LIMIT))).toBe(true);
	});

	test('rejects a note one character over the limit', () => {
		expect(noteIsSendable('a'.repeat(NOTE_LIMIT + 1))).toBe(false);
	});

	test('counts the untrimmed length against the limit', () => {
		// queue_call_for_bids checks char_length(_note) before it trims, so a note padded past
		// the limit with whitespace is refused there. The form has to agree, or it offers a
		// send that the database will reject.
		expect(noteIsSendable('a'.repeat(NOTE_LIMIT) + '  ')).toBe(false);
	});
});

describe('noteRemaining', () => {
	test('reports the whole allowance for an empty note', () => {
		expect(noteRemaining('')).toBe(NOTE_LIMIT);
	});

	test('goes negative once the note is too long', () => {
		// Negative rather than clamped to zero: a writer who is 12 characters over should be
		// told how much to cut, not merely that they are over.
		expect(noteRemaining('a'.repeat(NOTE_LIMIT + 12))).toBe(-12);
	});
});
