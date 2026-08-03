/**
 * Brand colours shared by the quota cards and the activity charts, keyed on
 * the labels the report emits, so Claude and Codex read as the same product
 * everywhere on the page.
 */
export const claudeBrand = '#d97757';
export const codexBrand = '#43b7a5';

const byLabel = new Map<string, string>([
	['claude', claudeBrand],
	['claude code', claudeBrand],
	['codex', codexBrand]
]);

export const brandColor = (label: string): string | undefined =>
	byLabel.get(label.toLowerCase());
