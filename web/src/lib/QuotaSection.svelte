<script lang="ts">
	import { invalidate } from '$app/navigation';
	import { onMount } from 'svelte';
	import { brandColor } from '$lib/brand';
	import {
		dayStepTargetPercent,
		paceTimeZone,
		quotaDependency,
		type QuotaProvider,
		type QuotaResponse,
		type QuotaWindow
	} from '$lib/quota';

	// The promise comes from the page load, so the quota follows the same
	// lifecycle as the report: it resolves inside the boundary below and
	// refreshes whenever the load re-runs.
	let { quota }: { quota: Promise<QuotaResponse> } = $props();

	let refreshing = $state(false);
	let now = $state(Date.now());

	onMount(() => {
		// The pace marker steps at midnight even while the page just sits open;
		// this follows the wall clock and performs no fetches.
		const tick = setInterval(() => (now = Date.now()), 30_000);
		return () => clearInterval(tick);
	});

	/**
	 * Forces the server to consult the providers, then re-renders through the
	 * same load path everything else uses. Without the forced request first,
	 * invalidating alone would usually re-serve the server's cache.
	 */
	async function refresh() {
		refreshing = true;
		try {
			await fetch('/api/quota?refresh=1');
			await invalidate(quotaDependency);
		} finally {
			refreshing = false;
		}
	}

	/** Mirrors the report's retry: re-run the load, then rebuild the boundary. */
	async function retry(reset: () => void) {
		try {
			await invalidate(quotaDependency);
		} finally {
			reset();
		}
	}

	const resetFormat = new Intl.DateTimeFormat('en-GB', {
		timeZone: paceTimeZone,
		month: '2-digit',
		day: '2-digit',
		hour: '2-digit',
		minute: '2-digit',
		hourCycle: 'h23'
	});

	const updatedFormat = new Intl.DateTimeFormat('en-GB', {
		timeZone: paceTimeZone,
		hour: '2-digit',
		minute: '2-digit',
		hourCycle: 'h23'
	});

	function resets(window: QuotaWindow): string {
		const at = Date.parse(window.resets_at);
		if (!Number.isFinite(at)) return '';
		const parts = resetFormat.formatToParts(at);
		const value = (type: string) =>
			parts.find((part) => part.type === type)?.value ?? '';
		return `resets ${value('day')}.${value('month')}, ${value('hour')}:${value('minute')}`;
	}

	function updated(provider: QuotaProvider): string | null {
		if (!provider.updated_at) return null;
		const at = Date.parse(provider.updated_at);
		return Number.isFinite(at) ? updatedFormat.format(at) : null;
	}

	function target(window: QuotaWindow): number | null {
		if (!window.weekly) return null;
		const resetsAt = Date.parse(window.resets_at);
		if (!Number.isFinite(resetsAt)) return null;
		return dayStepTargetPercent(resetsAt, window.window_minutes * 60_000, now);
	}

	function level(percent: number): string {
		if (percent >= 90) return 'danger';
		if (percent >= 75) return 'warning';
		return 'normal';
	}
</script>

<section class="quota" aria-label="Subscription quota">
	<div class="quota-header">
		<div>
			<p class="eyebrow">SUBSCRIPTIONS</p>
			<h2>Quota</h2>
		</div>
		<button
			class="quota-refresh"
			type="button"
			disabled={refreshing}
			onclick={refresh}>{refreshing ? 'Refreshing…' : 'Refresh'}</button
		>
	</div>

	<!-- The boundary owns pending and failed states, exactly as the report's
	     does: a skeleton on first resolution, an inline notice with a retry on
	     failure. -->
	<svelte:boundary>
		<div class="quota-cards">
			{#each (await quota).providers as provider (provider.id)}
				<article class="quota-card">
					<header class="card-header">
						<h3>{provider.label}</h3>
						<span class="card-tag">{provider.id}</span>
						{#if provider.plan}<span class="card-plan">{provider.plan}</span
							>{/if}
					</header>

					{#if provider.windows.length === 0}
						<p class="card-empty">
							{provider.error ?? 'No limits were reported for this account.'}
						</p>
					{:else}
						{#each provider.windows as window (window.id)}
							{@const pace = target(window)}
							<div class="limit">
								<div class="limit-row">
									<span class="limit-label">{window.label}</span>
									<span class="limit-meta">
										{#if pace !== null}
											<span
												class="pace-tag"
												title="Expected by end of today (Sofia time): {Math.round(
													pace
												)}%">┊{Math.round(pace)}%</span
											>
										{/if}
										{resets(window)}
									</span>
									<span class="limit-percent {level(window.used_percent)}"
										>{Math.round(window.used_percent)}%</span
									>
								</div>
								<div
									class="limit-bar"
									role="meter"
									aria-label={window.label}
									aria-valuemin={0}
									aria-valuemax={100}
									aria-valuenow={Math.round(window.used_percent)}
								>
									<div
										class="limit-fill"
										style:width="{Math.min(100, window.used_percent)}%"
										style:background={window.used_percent >= 90
											? 'var(--danger)'
											: (brandColor(provider.id) ?? 'var(--accent)')}
									></div>
									{#if pace !== null}
										<div
											class="limit-pace"
											style:left="{pace}%"
											title="Expected by end of today (Sofia time): {Math.round(
												pace
											)}%"
										></div>
									{/if}
								</div>
							</div>
						{/each}
					{/if}

					<footer class="card-footer">
						{#if provider.stale && provider.error}
							<span class="card-stale" title={provider.error}>stale data</span>
						{/if}
						{#if updated(provider)}
							<span class="card-updated">updated {updated(provider)}</span>
						{/if}
					</footer>
				</article>
			{/each}
		</div>

		{#snippet pending()}
			<div class="quota-cards" aria-hidden="true">
				{#each ['claude', 'codex'] as key (key)}
					<article class="quota-card quota-card-pending"></article>
				{/each}
			</div>
		{/snippet}

		{#snippet failed(error, reset)}
			<p class="notice" role="alert">
				{error instanceof Error
					? error.message
					: 'The quota could not be loaded.'}
				<button class="retry" type="button" onclick={() => retry(reset)}>
					Try again
				</button>
			</p>
		{/snippet}
	</svelte:boundary>
</section>

<style>
	.quota {
		margin: 8px 0 34px;
		padding-top: 18px;
		border-top: 1px solid var(--line);
	}

	.quota-header {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: 16px;
		margin-bottom: 16px;
	}

	.quota-header h2 {
		margin: 2px 0 0;
		font-size: 1.15rem;
		font-weight: 500;
	}

	.quota-refresh {
		border: 1px solid var(--line-strong);
		background: var(--surface);
		color: var(--ink);
		padding: 5px 12px;
		cursor: pointer;
		font: 0.72rem var(--font-mono);
	}

	.quota-refresh:disabled {
		color: var(--muted);
		cursor: default;
	}

	.retry {
		margin-left: 10px;
		border: 1px solid var(--line-strong);
		background: var(--surface);
		color: var(--ink);
		padding: 4px 10px;
		cursor: pointer;
		font: 0.72rem var(--font-mono);
	}

	.quota-cards {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(360px, 100%), 1fr));
		gap: 14px;
	}

	.quota-card {
		border: 1px solid var(--line);
		background: var(--surface);
		padding: 16px 18px 12px;
		display: flex;
		flex-direction: column;
		gap: 12px;
	}

	.quota-card-pending {
		min-height: 150px;
		animation: quota-pulse 1.1s ease-in-out infinite alternate;
	}

	@keyframes quota-pulse {
		from {
			opacity: 0.45;
		}
		to {
			opacity: 0.9;
		}
	}

	.card-header {
		display: flex;
		align-items: baseline;
		gap: 10px;
		flex-wrap: wrap;
	}

	.card-header h3 {
		margin: 0;
		font-size: 1rem;
		font-weight: 500;
	}

	.card-tag {
		font: 0.72rem var(--font-mono);
		color: var(--muted);
	}

	.card-plan {
		font: 0.68rem var(--font-mono);
		border: 1px solid var(--line-strong);
		padding: 1px 7px;
		border-radius: 3px;
	}

	.card-empty {
		margin: 4px 0;
		font-size: 0.85rem;
		color: var(--muted);
	}

	.limit {
		display: grid;
		gap: 6px;
	}

	.limit-row {
		display: flex;
		align-items: baseline;
		gap: 10px;
	}

	.limit-label {
		font-size: 0.88rem;
	}

	.limit-meta {
		margin-left: auto;
		font: 0.72rem var(--font-mono);
		color: var(--muted);
	}

	.pace-tag {
		color: var(--chart-outline);
		margin-right: 6px;
		cursor: help;
	}

	.limit-percent {
		font: 0.88rem var(--font-mono);
		font-variant-numeric: tabular-nums;
		min-width: 44px;
		text-align: right;
	}

	.limit-percent.warning {
		color: var(--warning);
	}

	.limit-percent.danger {
		color: var(--danger);
	}

	.limit-bar {
		position: relative;
		height: 6px;
		border-radius: 3px;
		background: color-mix(in srgb, var(--line) 55%, transparent);
	}

	.limit-fill {
		height: 100%;
		border-radius: 3px;
		background: var(--accent);
	}

	.limit-pace {
		position: absolute;
		top: -4px;
		bottom: -4px;
		border-left: 2px dotted var(--chart-outline);
		transform: translateX(-1px);
	}

	.card-footer {
		display: flex;
		align-items: baseline;
		gap: 12px;
		min-height: 1em;
		margin-top: auto;
	}

	.card-stale {
		font: 0.72rem var(--font-mono);
		color: var(--warning);
	}

	.card-updated {
		margin-left: auto;
		font: 0.72rem var(--font-mono);
		color: var(--muted);
	}
</style>
