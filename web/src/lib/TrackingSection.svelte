<script lang="ts">
	import { invalidate } from '$app/navigation';
	import { onMount } from 'svelte';
	import { brandColor } from '$lib/brand';
	import { paceTimeZone } from '$lib/quota';
	import {
		points,
		trackingAction,
		trackingDependency,
		type TrackingResponse,
		type TrackingSession,
		type TrackingWindow
	} from '$lib/tracking';

	let { tracking }: { tracking: Promise<TrackingResponse> } = $props();

	let now = $state(Date.now());
	let confirming = $state<number | null>(null);
	let deleteError = $state<string | null>(null);

	onMount(() => {
		// Keeps the active session's elapsed time honest while the page sits
		// open; no fetches happen here.
		const tick = setInterval(() => (now = Date.now()), 30_000);
		return () => clearInterval(tick);
	});

	const stampFormat = new Intl.DateTimeFormat('en-GB', {
		timeZone: paceTimeZone,
		month: '2-digit',
		day: '2-digit',
		hour: '2-digit',
		minute: '2-digit',
		hourCycle: 'h23'
	});

	function stamp(iso: string): string {
		const at = Date.parse(iso);
		if (!Number.isFinite(at)) return '';
		const parts = stampFormat.formatToParts(at);
		const value = (type: string) =>
			parts.find((part) => part.type === type)?.value ?? '';
		return `${value('day')}.${value('month')} ${value('hour')}:${value('minute')}`;
	}

	function duration(session: TrackingSession): string {
		const from = Date.parse(session.started_at);
		const to = session.ended_at ? Date.parse(session.ended_at) : now;
		if (!Number.isFinite(from) || !Number.isFinite(to)) return '';
		const minutes = Math.max(0, Math.floor((to - from) / 60_000));
		const days = Math.floor(minutes / 1440);
		const hours = Math.floor((minutes % 1440) / 60);
		if (days > 0) return `${days}d ${hours}h`;
		if (hours > 0) return `${hours}h ${minutes % 60}m`;
		return `${minutes}m`;
	}

	function range(session: TrackingSession): string {
		const from = stamp(session.started_at);
		return session.ended_at ? `${from} → ${stamp(session.ended_at)}` : from;
	}

	/** The window's share of quota this session used, e.g. "+12 pts". */
	function consumed(window: TrackingWindow): string {
		return `+${points(window.consumed_percent)} pts`;
	}

	function notes(window: TrackingWindow): string {
		const parts: string[] = [];
		if (window.resets > 0)
			parts.push(window.resets === 1 ? '1 reset' : `${window.resets} resets`);
		if (window.stale) parts.push('stale mark');
		return parts.join(' · ');
	}

	async function remove(session: TrackingSession) {
		if (confirming !== session.id) {
			confirming = session.id;
			return;
		}
		confirming = null;
		deleteError = await trackingAction(`/api/tracking/${session.id}`, {
			method: 'DELETE'
		});
		await invalidate(trackingDependency);
	}
</script>

<svelte:boundary>
	{@const data = await tracking}
	<section class="tracking" aria-label="Tracked usage sessions">
		<div class="tracking-header">
			<div>
				<p class="eyebrow">TRACKING</p>
				<h2>Usage sessions</h2>
			</div>
			{#if deleteError}
				<span class="tracking-error" role="alert">{deleteError}</span>
			{/if}
		</div>

		{#if !data.active && data.history.length === 0}
			<p class="tracking-empty">
				No tracked sessions yet — name one next to the Track button to start.
			</p>
		{:else}
			<div class="session-grid">
				{#if data.active}
					<article class="session session-active">
						<header class="session-row">
							<span class="session-live" aria-hidden="true"></span>
							<h3>{data.active.name}</h3>
							<span class="session-meta">
								since {stamp(data.active.started_at)} · {duration(data.active)}
							</span>
						</header>
						{#if data.active.windows.length === 0}
							<p class="session-empty">No quota snapshot was captured yet.</p>
						{:else}
							<div class="session-windows">
								{#each data.active.windows as window (window.provider + window.window_id)}
									<div class="window-row">
										<span
											class="window-dot"
											style:background={brandColor(window.provider) ??
												'var(--accent)'}
											aria-hidden="true"
										></span>
										<span class="window-label">
											{window.provider_label ?? window.provider}
											· {window.label ?? window.window_id}
										</span>
										<span class="window-path">
											{points(window.start_percent)}% → {points(
												window.last_percent
											)}%
											{#if notes(window)}<em> · {notes(window)}</em>{/if}
										</span>
										<span
											class="window-consumed"
											class:consumed-zero={window.consumed_percent === 0}
										>
											{consumed(window)}
										</span>
									</div>
								{/each}
							</div>
						{/if}
					</article>
				{/if}

				{#each data.history as session (session.id)}
					<article class="session">
						<header class="session-row">
							<h3>{session.name}</h3>
							<span class="session-meta">
								{range(session)} · {duration(session)}
							</span>
							<button
								class="session-delete"
								class:delete-confirm={confirming === session.id}
								type="button"
								onclick={() => remove(session)}
								onmouseleave={() => (confirming = null)}
							>
								{confirming === session.id ? 'sure?' : 'delete'}
							</button>
						</header>
						{#if session.windows.length === 0}
							<p class="session-empty">No quota snapshot was captured.</p>
						{:else}
							<div class="session-windows">
								{#each session.windows as window (window.provider + window.window_id)}
									<div class="window-row">
										<span
											class="window-dot"
											style:background={brandColor(window.provider) ??
												'var(--accent)'}
											aria-hidden="true"
										></span>
										<span class="window-label">
											{window.provider_label ?? window.provider}
											· {window.label ?? window.window_id}
										</span>
										<span class="window-path">
											{points(window.start_percent)}% → {points(
												window.end_percent ?? window.last_percent
											)}%
											{#if notes(window)}<em> · {notes(window)}</em>{/if}
										</span>
										<span
											class="window-consumed"
											class:consumed-zero={window.consumed_percent === 0}
										>
											{consumed(window)}
										</span>
									</div>
								{/each}
							</div>
						{/if}
					</article>
				{/each}
			</div>
		{/if}
	</section>

	{#snippet pending()}
		<!-- The section only mounts once the Sessions toggle opens it, so the
		     brief load right after the click stays blank rather than flashing
		     a skeleton. -->
	{/snippet}

	{#snippet failed()}
		<!-- The section is an addition to the dashboard; when its data cannot
		     load, it simply stays absent rather than raising a page error. -->
	{/snippet}
</svelte:boundary>

<style>
	.tracking {
		margin: 8px 0 34px;
		padding-top: 18px;
		border-top: 1px solid var(--line);
	}

	.tracking-header {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: 16px;
		margin-bottom: 16px;
	}

	.tracking-header h2 {
		margin: 2px 0 0;
		font-size: 1.15rem;
		font-weight: 500;
	}

	.tracking-error {
		font: 0.72rem var(--font-mono);
		color: var(--danger);
	}

	.tracking-empty {
		margin: 0;
		font-size: 0.85rem;
		color: var(--muted);
	}

	.session-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 10px;
	}

	@media (max-width: 760px) {
		.session-grid {
			grid-template-columns: 1fr;
		}
	}

	.session {
		border: 1px solid var(--line);
		background: var(--surface);
		padding: 14px 18px;
		display: flex;
		flex-direction: column;
		gap: 10px;
	}

	/* The running session reads differently from finished ones, so it keeps
	   the full row to itself. */
	.session-active {
		border-color: var(--line-strong);
		grid-column: 1 / -1;
	}

	.session-row {
		display: flex;
		align-items: baseline;
		gap: 10px;
	}

	.session-row h3 {
		margin: 0;
		font-size: 0.95rem;
		font-weight: 500;
	}

	.session-live {
		align-self: center;
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: var(--accent);
		animation: tracking-pulse 1.1s ease-in-out infinite alternate;
	}

	@keyframes tracking-pulse {
		from {
			opacity: 0.35;
		}
		to {
			opacity: 1;
		}
	}

	.session-meta {
		margin-left: auto;
		font: 0.72rem var(--font-mono);
		color: var(--muted);
		white-space: nowrap;
	}

	.session-delete {
		border: 1px solid var(--line-strong);
		background: var(--surface);
		color: var(--muted);
		padding: 2px 8px;
		cursor: pointer;
		font: 0.68rem var(--font-mono);
	}

	.session-delete.delete-confirm {
		color: var(--danger);
		border-color: var(--danger);
	}

	.session-empty {
		margin: 0;
		font-size: 0.82rem;
		color: var(--muted);
	}

	.session-windows {
		display: grid;
		gap: 6px;
	}

	.window-row {
		display: flex;
		align-items: baseline;
		gap: 8px;
	}

	.window-dot {
		align-self: center;
		width: 6px;
		height: 6px;
		border-radius: 50%;
		flex: none;
	}

	.window-label {
		font-size: 0.84rem;
	}

	.window-path {
		margin-left: auto;
		font: 0.72rem var(--font-mono);
		font-variant-numeric: tabular-nums;
		color: var(--muted);
		white-space: nowrap;
	}

	.window-path em {
		font-style: normal;
		color: var(--warning);
	}

	.window-consumed {
		font: 0.84rem var(--font-mono);
		font-variant-numeric: tabular-nums;
		min-width: 74px;
		text-align: right;
	}

	.consumed-zero {
		color: var(--muted);
	}
</style>
