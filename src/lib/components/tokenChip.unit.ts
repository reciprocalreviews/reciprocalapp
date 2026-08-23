import { marked } from 'marked';
import { describe, expect, test } from 'vitest';
import tokenChip from './tokenChip';

const TOKENS = { single: 'token', plural: 'tokens' };

describe('tokenChip', () => {
	test('renders the star, the amount, and the plural unit', () => {
		expect(tokenChip(TOKENS, 10).html).toBe(
			'<span class="token"><span class="star">★</span> 10 tokens</span>'
		);
	});

	test('uses the singular unit for exactly one', () => {
		expect(tokenChip(TOKENS, 1).html).toContain(' 1 token</span>');
	});

	test('uses the plural unit for zero', () => {
		expect(tokenChip(TOKENS, 0).html).toContain(' 0 tokens</span>');
	});

	test('names a currency when given one', () => {
		expect(tokenChip(TOKENS, 2, { currency: 'Kudos' }).html).toBe(
			'<span class="token"><span class="star">★</span> 2 <span class="currency">Kudos</span> tokens</span>'
		);
	});

	test('omits the currency element entirely when not given one', () => {
		expect(tokenChip(TOKENS, 2).html).not.toContain('currency');
	});

	test('marks a debit with the class that recolors it', () => {
		expect(tokenChip(TOKENS, 2, { debit: true }).html).toContain('class="token debit"');
		expect(tokenChip(TOKENS, 2).html).toContain('class="token"');
	});

	// A currency name is venue-authored and the chip is rendered with {@html},
	// so this is a security boundary, not a cosmetic one.
	test('escapes markup in a currency name', () => {
		const chip = tokenChip(TOKENS, 1, { currency: '<img src=x onerror=alert(1)>' }).html;
		expect(chip).not.toContain('<img');
		expect(marked(chip)).not.toContain('<img');
	});

	test('escapes quotes so a name cannot break out of the class attribute', () => {
		expect(tokenChip(TOKENS, 1, { currency: '"><script>' }).html).not.toContain('<script');
	});

	// marked parses markdown inside an inline element, so an unescaped name
	// would be able to italicize or link part of the chip.
	test('escapes markdown formatting in a currency name', () => {
		expect(marked(tokenChip(TOKENS, 1, { currency: '*Kudos*' }).html)).not.toContain('<em>');
		expect(marked(tokenChip(TOKENS, 1, { currency: '[a](b)' }).html)).not.toContain('<a ');
	});

	test('never renders the word undefined', () => {
		expect(tokenChip(TOKENS, 3).html).not.toContain('undefined');
	});
});
