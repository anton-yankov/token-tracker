import assert from 'node:assert/strict';
import test from 'node:test';
import { money, number, setEurPerUsd } from './api.ts';

test('formats compact token totals and euro prices from USD costs', () => {
	assert.match(number(1_500_000), /1\.5M/);

	setEurPerUsd(0.5);
	assert.match(money(12.5), /6,25/);
	assert.match(money(12.5), /€/);
	assert.match(money(0.0012), /0,0006/);
	assert.match(money(0), /0,00/);

	// An unusable rate must not disturb the one in effect.
	setEurPerUsd(0);
	setEurPerUsd(Number.NaN);
	assert.match(money(12.5), /6,25/);
});
