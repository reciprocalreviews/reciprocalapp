<script lang="ts">
	export let amount: number;
</script>

<span class="token"
	>★ {amount} token{#if amount !== 1}s{/if}</span
>

<style>
	.token {
		font-weight: 500;
		font-size: var(--small-font-size);
		padding: calc(var(--spacing) / 2);
		border-radius: var(--roundedness);
		background: var(--salient-color);
		color: var(--background-color);
		white-space: nowrap;
	}
</style>
