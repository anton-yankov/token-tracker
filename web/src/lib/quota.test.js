import assert from 'node:assert/strict';
import test from 'node:test';
import { dayStepTargetPercent, nextMidnight } from './quota.ts';

const HOUR = 3_600_000;
const WEEK = 7 * 24 * HOUR;

test('nextMidnight finds Sofia midnight in summer (UTC+3)', () => {
	const now = Date.UTC(2026, 7, 3, 13, 0, 0);
	assert.equal(
		nextMidnight(now, 'Europe/Sofia'),
		Date.UTC(2026, 7, 3, 21, 0, 0)
	);
});

test('nextMidnight finds Sofia midnight in winter (UTC+2)', () => {
	const now = Date.UTC(2026, 0, 10, 13, 0, 0);
	assert.equal(
		nextMidnight(now, 'Europe/Sofia'),
		Date.UTC(2026, 0, 10, 22, 0, 0)
	);
});

test('nextMidnight crosses the DST fall-back day', () => {
	// Sofia leaves DST on 2026-10-25 (04:00 EEST -> 03:00 EET), making that
	// civil day 25 hours long. From 01:00 local that night, the next midnight
	// is Oct 26 00:00 EET = Oct 25 22:00 UTC.
	const now = Date.UTC(2026, 9, 24, 22, 0, 0);
	assert.equal(
		nextMidnight(now, 'Europe/Sofia'),
		Date.UTC(2026, 9, 25, 22, 0, 0)
	);
});

test('a partial first day earns a prorated share', () => {
	// Window starts Jul 30 15:59:59Z = 18:59:59 Sofia, so the first civil day
	// only spans ~5 hours of the 168-hour window.
	const resetsAt = Date.UTC(2026, 7, 6, 15, 59, 59);
	const now = Date.UTC(2026, 6, 30, 18, 0, 0);
	const target =
		dayStepTargetPercent(resetsAt, WEEK, now, 'Europe/Sofia') ??
		assert.fail('expected a target inside the window');
	const firstDayMs =
		Date.UTC(2026, 6, 30, 21, 0, 0) - Date.UTC(2026, 6, 30, 15, 59, 59);
	assert.ok(Math.abs(target - (firstDayMs / WEEK) * 100) < 1e-9);
	assert.ok(Math.abs(target - 2.98) < 0.01);
});

test('the target steps by a full day share at Sofia midnight', () => {
	const resetsAt = Date.UTC(2026, 7, 6, 15, 59, 59);
	const beforeMidnight = Date.UTC(2026, 6, 30, 20, 59, 59);
	const afterMidnight = Date.UTC(2026, 6, 30, 21, 0, 0);
	const before =
		dayStepTargetPercent(resetsAt, WEEK, beforeMidnight, 'Europe/Sofia') ??
		assert.fail('expected a target inside the window');
	const after =
		dayStepTargetPercent(resetsAt, WEEK, afterMidnight, 'Europe/Sofia') ??
		assert.fail('expected a target inside the window');
	assert.ok(Math.abs(after - before - (24 * HOUR * 100) / WEEK) < 1e-9);
});

test('the target holds steady within a day', () => {
	const resetsAt = Date.UTC(2026, 7, 6, 15, 59, 59);
	const morning = dayStepTargetPercent(
		resetsAt,
		WEEK,
		Date.UTC(2026, 7, 1, 6, 0, 0)
	);
	const evening = dayStepTargetPercent(
		resetsAt,
		WEEK,
		Date.UTC(2026, 7, 1, 20, 0, 0)
	);
	assert.equal(morning, evening);
});

test('the final partial day caps at 100', () => {
	const resetsAt = Date.UTC(2026, 7, 6, 15, 59, 59);
	const now = Date.UTC(2026, 7, 6, 10, 0, 0);
	assert.equal(dayStepTargetPercent(resetsAt, WEEK, now), 100);
});

test('instants outside the window produce no target', () => {
	const resetsAt = Date.UTC(2026, 7, 6, 15, 59, 59);
	assert.equal(dayStepTargetPercent(resetsAt, WEEK, resetsAt), null);
	assert.equal(dayStepTargetPercent(resetsAt, WEEK, resetsAt - WEEK - 1), null);
	assert.equal(dayStepTargetPercent(resetsAt, 0, resetsAt - 1), null);
	assert.equal(dayStepTargetPercent(Number.NaN, WEEK, resetsAt - 1), null);
});
