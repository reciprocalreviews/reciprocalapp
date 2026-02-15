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
	import { onMount } from 'svelte';

	import Link from './Link.svelte';

	type Props = {
		stats: [Stat, ...Stat[]];
	};

	let { stats }: Props = $props();

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
		<div class="stat" data-testid="stat-{index}">
			{#if stat.link}
				<Link to={stat.link} underline={false}>
					<div class="content">
						{@render number(stat.number, stat.icon)}
						{@render title(stat.title)}
					</div>
				</Link>
			{:else}
				<div class="content">
					{@render number(stat.number, stat.icon)}
					{@render title(stat.title)}
				</div>
			{/if}
		</div>
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
		flex: 1;
	}

	.content {
		display: flex;
		flex-direction: column;
		align-items: baseline;
		line-height: 1;
	}

	.number {
		font-size: var(--header-font-size);
		font-weight: bold;
	}

	.title {
		font-size: var(--small-font-size);
		font-style: italic;
		max-width: 8em;
	}
</style>
