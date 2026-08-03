export interface QuotaWindow {
	id: string;
	label: string;
	used_percent: number;
	resets_at: string;
	window_minutes: number;
	weekly: boolean;
}

export interface QuotaProvider {
	id: string;
	label: string;
	plan: string | null;
	updated_at: string | null;
	error: string | null;
	stale: boolean;
	windows: QuotaWindow[];
}

export interface QuotaResponse {
	generated_at: string;
	providers: QuotaProvider[];
}

/**
 * The pace budget is anchored to Bulgarian civil days regardless of where the
 * dashboard happens to be viewed from.
 */
export const paceTimeZone = 'Europe/Sofia';

interface WallClock {
	year: number;
	month: number;
	day: number;
	hour: number;
	minute: number;
	second: number;
}

const wallClockFormatters = new Map<string, Intl.DateTimeFormat>();

function wallClockFormatter(timeZone: string): Intl.DateTimeFormat {
	let formatter = wallClockFormatters.get(timeZone);
	if (!formatter) {
		formatter = new Intl.DateTimeFormat('en-CA', {
			timeZone,
			year: 'numeric',
			month: '2-digit',
			day: '2-digit',
			hour: '2-digit',
			minute: '2-digit',
			second: '2-digit',
			hourCycle: 'h23'
		});
		wallClockFormatters.set(timeZone, formatter);
	}
	return formatter;
}

function wallClock(time: number, timeZone: string): WallClock {
	const clock: Partial<Record<string, number>> = {};
	for (const part of wallClockFormatter(timeZone).formatToParts(time)) {
		if (part.type !== 'literal') clock[part.type] = Number(part.value);
	}
	return clock as unknown as WallClock;
}

function asUtc(clock: WallClock): number {
	return Date.UTC(
		clock.year,
		clock.month - 1,
		clock.day,
		clock.hour,
		clock.minute,
		clock.second
	);
}

/**
 * The UTC instant of the first midnight in `timeZone` strictly after `time`.
 *
 * The guess starts as if the zone had no offset and is corrected by the
 * difference between its wall-clock reading and the desired one; each
 * correction folds in the zone offset at the guessed instant, so a DST
 * transition between the two candidates settles within a few rounds.
 */
export function nextMidnight(
	time: number,
	timeZone: string = paceTimeZone
): number {
	const today = wallClock(time, timeZone);
	const desired = Date.UTC(today.year, today.month - 1, today.day + 1, 0, 0, 0);
	let guess = desired;
	for (let round = 0; round < 4; round += 1) {
		const wall = asUtc(wallClock(guess, timeZone));
		if (wall === desired) break;
		guess += desired - wall;
	}
	return guess;
}

/**
 * Cumulative share of a rate window (0-100) that should be spent by the end of
 * the current day in `timeZone`, or null outside the window.
 *
 * Every calendar day's budget is proportional to the time it contributes to
 * the window, so the running target at any moment is just the window fraction
 * elapsed at the upcoming midnight. Reading it at the midnight boundary makes
 * the value a step function: a partial first day yields a small first target
 * and each following midnight adds a full day's share.
 */
export function dayStepTargetPercent(
	resetsAt: number,
	windowMs: number,
	now: number,
	timeZone: string = paceTimeZone
): number | null {
	if (!Number.isFinite(resetsAt) || !(windowMs > 0) || !Number.isFinite(now))
		return null;
	const start = resetsAt - windowMs;
	if (now < start || now >= resetsAt) return null;
	const endOfToday = Math.min(nextMidnight(now, timeZone), resetsAt);
	return Math.min(100, ((endOfToday - start) / windowMs) * 100);
}
