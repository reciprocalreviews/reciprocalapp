<slot />

<style>
	:global(body) {
		font-family: 'Josefin Sans', sans-serif;
		padding: 3em;
		max-width: 40em;
	}

	:global(h1) {
		font-size: 24pt;
		font-weight: 500;
		margin-top: 2em;
	}

	:global(p) {
		font-size: 16pt;
		font-weight: 300;
		line-height: 1.4;
	}

	:global(a) {
		color: black;
		text-decoration: underline;
		text-decoration-thickness: 2px;
	}

	:global(a:hover) {
		color: black;
		text-decoration: underline;
		text-decoration-thickness: 4px;
	}

	:global(a:focus) {
		color: black;
		text-decoration: underline;
		text-decoration-thickness: 4px;
		outline: none;
	}
</style>
