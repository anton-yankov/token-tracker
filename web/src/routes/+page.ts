import { reportDependency, reportSearch } from '$lib/report-query';
import { quotaDependency, type QuotaResponse } from '$lib/quota';
import type { ReportResponse } from '$lib/api';
import type { PageLoad } from './$types';

export const load: PageLoad = ({ url, fetch, depends }) => {
	depends(reportDependency);
	depends(quotaDependency);
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

	// The quota rides the same lifecycle as the report: fetched here, awaited
	// inside its own boundary, refreshed by invalidating its dependency. The
	// server's per-provider cache keeps the extra runs cheap.
	const quota = (async (): Promise<QuotaResponse> => {
		const response = await fetch('/api/quota');
		if (!response.ok) {
			throw new Error(`The quota could not be loaded (${response.status}).`);
		}
		return response.json();
	})();

	return { report, quota };
};
