<!-- Displays a SQL date time string -->
<script lang="ts">
	let {
		time
	}: {
		time: string;
	} = $props();

	let date = $derived(new Date(Date.parse(time)));
</script>

<span class="date">{date.toLocaleDateString()}</span>

<style>
	.date {
		font-family: var(--font-face);
		font-size: var(--small-font-size);
		font-style: italic;
	}
</style>
