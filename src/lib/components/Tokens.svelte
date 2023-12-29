<script lang="ts">
	export let amount: number;
</script>

<span class="token"
	>{amount} token{#if amount !== 1}s{/if}</span
>

<style>
	.token {
		font-weight: bold;
		border-bottom: var(--border-color) solid 1px;
		border-radius: var(--roundedness);
		padding-left: 0.1em;
		padding-right: 0.1em;
	}
</style>
