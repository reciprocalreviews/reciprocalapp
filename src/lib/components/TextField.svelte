<script lang="ts">
	export let text: string;
	export let placeholder: string;
	export let size: number = 10;
	export let padded = true;
	export let valid: undefined | ((text: string) => boolean) = undefined;
	export let type: 'text' | 'box' | 'password' = 'text';

	$: isValid = valid ? valid(text) : true;
</script>

{#if type === 'text'}
	<input class:padded {size} class:invalid={!isValid} bind:value={text} {placeholder} />
{:else if type === 'box'}
	<textarea
		class:padded
		class:invalid={!isValid}
		{placeholder}
		bind:value={text}
		cols={size}
		rows={text.split('\n').length}
	></textarea>
{:else}
	<input
		class:padded
		{size}
		class:invalid={!isValid}
		bind:value={text}
		type="password"
		{placeholder}
	/>
{/if}

<style>
	input {
		border: none;
		border-bottom: 4px solid var(--salient-color);
		font-family: inherit;
		font-size: inherit;
		font-weight: inherit;
		font-style: inherit;
		background: var(--background-color);
	}

	textarea {
		border: none;
		border-left: 4px solid var(--salient-color);
		border-right: 4px solid var(--salient-color);
		font-family: inherit;
		font-size: inherit;
		font-weight: inherit;
		font-style: inherit;
		background: var(--background-color);
	}

	input.padded,
	textarea.padded {
		padding: calc(var(--spacing) / 2);
	}

	input.invalid,
	textarea.invalid {
		color: var(--error-color);
		border-color: var(--error-color);
	}

	input:focus,
	textarea:focus {
		outline: none;
	}

	input:not(.invalid):focus {
		border-bottom-color: var(--focus-color);
	}

	textarea:not(.invalid):focus {
		border-color: var(--focus-color);
	}
</style>
