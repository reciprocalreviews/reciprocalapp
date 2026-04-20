<script module lang="ts">
	export type Stat = {
		number: number | undefined;
		title: string;
		icon?: string;
		link?: string;
	};

	const Duration = 1000;
	const FramesPerSecond = 60;
	const MillisecondsPerFrame = 1000 / FramesPerSecond;
	const PercentPerFrame = 1 / (Duration / MillisecondsPerFrame);
</script>

<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';

	type Props = {
		stats: [Stat, ...Stat[]];
	};

	let { stats }: Props = $props();

	// Animation state
	let percent = $state(0);

	function step() {
		percent += PercentPerFrame;
		if (percent < 1) requestAnimationFrame(step);
	}

	function easeOut(t: number) {
		return 1 - (1 - t) * (1 - t);
	}

	onMount(() => {
		step();
	});

	
	function navigate(href?: string) {
		if (!href) return;
		goto(href);
	}

	function handleKeyNavigate(e: KeyboardEvent, href?: string) {
		if (!href) return;
		if (e.key === 'Enter' || e.key === ' ') {
			e.preventDefault();
			navigate(href);
		}
	}
</script>

{#snippet number(stat: number | undefined, icon: string | undefined)}
	<span class="number"
		>{#if icon}{icon}{/if}{stat === undefined
			? '—'
			: percent < 1
				? Math.round(stat * easeOut(percent))
				: stat}</span
	>
{/snippet}

{#snippet title(text: string)}
	<span class="title">{text}</span>
{/snippet}

<div class="dashboard">
	{#each stats as stat, index}
		{#if stat.link}
			<a
				class="stat"
				href={stat.link}
				onclick={(e) => { e.preventDefault(); navigate(stat.link); }}
				onkeydown={(e) => handleKeyNavigate(e, stat.link)}
				data-testid="stat-{index}"
			>
				<div class="content">
					{@render number(stat.number, stat.icon)}
					{@render title(stat.title)}
				</div>
			</a>
		{:else}
			<div class="stat" data-testid="stat-{index}">
				<div class="content">
					{@render number(stat.number, stat.icon)}
					{@render title(stat.title)}
				</div>
			</div>
		{/if}
	{/each}
</div>

<style>
	.dashboard {
		display: flex;
		flex-direction: row;
		width: 100%;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--spacing);
		flex-wrap: wrap;
	}

	.stat {
		padding: var(--spacing);
		border: var(--border-width) var(--border-color) solid;
		border-radius: var(--roundedness);
		background: var(--salient-color-faded);
		flex: 1 1 0;
		min-width: 180px;
		display: flex;
		align-items: center;
		justify-content: center;
		box-shadow: 0 2px 8px rgba(0,0,0,0.04);
		transition: background 0.2s, box-shadow 0.2s;
		text-decoration: none;
		color: inherit;
		cursor: default;
	}

	a.stat {
		cursor: pointer;
		border-color: var(--salient-color);
	}

	a.stat:hover,
	a.stat:focus-visible {
		background: var(--salient-color-faded);
		box-shadow: 0 4px 16px rgba(0,0,0,0.12);
		filter: brightness(0.97);
	}

	.stat:focus-visible {
		accent-color: var(--focus-color);
	}

	.content {
		display: flex;
		flex-direction: column;
		align-items: center;
		line-height: 1.2;
	}

	.number {
		font-size: var(--header-font-size);
		font-weight: bold;
		text-align: center;
		color: var(--salient-color);
	}

	.title {
		font-size: var(--small-font-size);
		font-style: italic;
		max-width: 12em;
		text-align: center;
		margin-top: 0.5em;
		word-break: break-word;
	}

</style>
