import { reportDependency, reportSearch } from '$lib/report-query';
import { quotaDependency, type QuotaResponse } from '$lib/quota';
import { trackingDependency, type TrackingResponse } from '$lib/tracking';
import type { ReportResponse } from '$lib/api';
import type { PageLoad } from './$types';

export const load: PageLoad = ({ url, fetch, depends }) => {
	depends(reportDependency);
	depends(quotaDependency);
	depends(trackingDependency);
	const search = reportSearch(
		url,
		Intl.DateTimeFormat().resolvedOptions().timeZone
	);

	// The promise is returned rather than awaited so navigation completes
	// immediately and the page's `<svelte:boundary>` owns the pending and failed
	// states. A failure therefore surfaces as an inline notice with a retry
	// instead of replacing the dashboard with the error page.
	const report = (async (): Promise<ReportResponse> => {
		const response = await fetch(`/api/report${search}`);
		if (!response.ok) {
			throw new Error(`The report could not be loaded (${response.status}).`);
		}
		return response.json();
	})();

	// Only the stored snapshot is asked for here, so the cards paint instantly
	// with last data; the section then runs the real provider check itself and
	// glides the bars to the fresh numbers.
	const quota = (async (): Promise<QuotaResponse> => {
		const response = await fetch('/api/quota?cached=1');
		if (!response.ok) {
			throw new Error(`The quota could not be loaded (${response.status}).`);
		}
		return response.json();
	})();

	// The active session's running tally is computed against the server's
	// quota cache, so this stays a cheap read that never contacts a provider.
	const tracking = (async (): Promise<TrackingResponse> => {
		const response = await fetch('/api/tracking');
		if (!response.ok) {
			throw new Error(
				`The tracking state could not be loaded (${response.status}).`
			);
		}
		return response.json();
	})();

	return { report, quota, tracking };
};
