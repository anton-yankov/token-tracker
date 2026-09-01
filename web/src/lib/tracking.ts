export interface TrackingWindow {
	provider: string;
	provider_label: string | null;
	window_id: string;
	label: string | null;
	weekly: boolean;
	start_percent: number;
	last_percent: number;
	end_percent: number | null;
	consumed_percent: number;
	resets: number;
	stale: boolean;
}

export interface TrackingSession {
	id: number;
	name: string;
	started_at: string;
	ended_at: string | null;
	windows: TrackingWindow[];
}

export interface TrackingResponse {
	active: TrackingSession | null;
	history: TrackingSession[];
}

/** Load dependency key, so a refresh re-runs the page load that fetched it. */
export const trackingDependency = 'app:tracking';

/**
 * Start, stop, and delete all answer with the fresh tracking report, but the
 * page data is refreshed through the load dependency so every section reading
 * it stays in sync. A non-ok answer carries `{error}` in the body.
 */
export async function trackingAction(
	path: string,
	options: RequestInit = {}
): Promise<string | null> {
	try {
		const response = await fetch(path, { method: 'POST', ...options });
		if (response.ok) return null;
		const body = (await response.json().catch(() => null)) as {
			error?: string;
		} | null;
		return body?.error ?? `The request failed (${response.status}).`;
	} catch {
		return 'The tracking service could not be reached.';
	}
}

/** Consumed percentage points, compact: whole numbers stay whole. */
export function points(value: number): string {
	return new Intl.NumberFormat('en-GB', {
		maximumFractionDigits: 1
	}).format(value);
}
