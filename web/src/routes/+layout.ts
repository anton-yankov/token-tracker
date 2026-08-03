import { setEurPerUsd } from '$lib/api';
import type { LayoutLoad } from './$types';

export const ssr = false;

// The exchange rate must be in place before any page formats a price, so the
// layout resolves it ahead of rendering. A failed fetch keeps the fallback.
export const load: LayoutLoad = async ({ fetch }) => {
	try {
		const response = await fetch('/api/fx');
		if (response.ok) {
			const { eur_per_usd } = await response.json();
			setEurPerUsd(eur_per_usd);
		}
	} catch {
		// The fallback rate stands.
	}
};
