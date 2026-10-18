<script lang="ts">
	import type { ScholarRow } from '$data/types';
	import { affiliationLine, worksStat, type ProfileSummary } from '#lib/data/orcidProfileView.js';
	import Text from '#lib/locales/Text.svelte';
	import ORCIDiD from './ORCIDiD.svelte';
	import ScholarLink from './ScholarLink.svelte';

	/** Who a scholar is, in the few lines someone needs to reach or invite them somewhere
	 * else: the name, linked to the profile for everything more, then the email address and
	 * the ORCID iD, then the short affiliation and works count from RR's ORCID mirror, which
	 * is what tells two people with one name apart. Used wherever someone choosing reviewers has to carry a person out of
	 * RR — the bidding tables, the volunteer roster, the import pickers — so all of them
	 * show the same things the same way. Callers pass data, never markup, so no page can
	 * grow its own variant.
	 *
	 * The email and iD each take three states, because "you may not see this" and "there
	 * is none" are different answers: `undefined` renders nothing, `null` says plainly that
	 * there is none, and a string renders it. */
	let {
		scholar,
		email = undefined,
		orcid = undefined,
		size = 'normal',
		newTab = false,
		profile = undefined,
		testid = undefined
	}: {
		/** The id and name, which render without a round trip; or just the id, which
		 * ScholarLink looks up, for a caller that has no name to hand. */
		scholar: string | Pick<ScholarRow, 'id' | 'name'>;
		email?: string | null;
		orcid?: string | null;
		size?: 'small' | 'normal';
		/** Open the profile in a new tab, so checking who someone is doesn't lose a choice
		 * in progress. */
		newTab?: boolean;
		/** The mirrored ORCID record. Renders nothing when RR has not read one: a missing
		 * mirror is RR not knowing, not a fact about the scholar worth a placeholder. */
		profile?: ProfileSummary;
		/** On the wrapper; the email, iD and ORCID line get `-email`, `-orcid` and
		 * `-context` appended. */
		testid?: string;
	} = $props();

	const affiliation = $derived(affiliationLine(profile, true));
	const works = $derived(worksStat(profile));
</script>

<span class="preview" class:small={size === 'small'} data-testid={testid}>
	<span class="name"><ScholarLink id={scholar} {size} {newTab} /></span>
	{#if email !== undefined || orcid !== undefined}
		<span class="details">
			{#if email !== undefined}
				<span class="detail" data-testid={testid ? `${testid}-email` : undefined}>
					{#if email !== null}<a href="mailto:{email}">{email}</a>{:else}<Text
							path={(l) => l.widget.scholarPreview.noEmail}
						/>{/if}
				</span>
			{/if}
			{#if orcid !== undefined}
				<span class="detail">
					{#if orcid !== null}<ORCIDiD
							id={orcid}
							testid={testid ? `${testid}-orcid` : undefined}
						/>{:else}<Text path={(l) => l.widget.scholarPreview.noORCID} />{/if}
				</span>
			{/if}
		</span>
	{/if}
	{#if affiliation || works}
		<span class="context" data-testid={testid ? `${testid}-context` : undefined}>
			{#if affiliation}<span>{affiliation}</span>{/if}
			{#if works}<span>{works}</span>{/if}
		</span>
	{/if}
</span>

<style>
	.preview {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		min-width: 0;
	}

	/* Links wrap by default (app.html), and a name broken across two lines reads as two
	   people; the details below give way instead. */
	.name,
	.name :global(a) {
		white-space: nowrap;
	}

	/* The email and iD are what tell two people with one name apart, and what someone
	   copies into another system. Each wraps to its own line as a whole, never mid-iD,
	   which reads as two numbers. */
	.details {
		display: flex;
		flex-wrap: wrap;
		column-gap: var(--spacing-half);
		font-size: var(--small-font-size);
		color: var(--inactive-color);
	}

	.detail {
		flex: none;
		max-width: 100%;
		overflow-wrap: anywhere;
	}

	/* Short form, without the department: the least discriminating part of an
	   affiliation, and these sit in narrow table cells. */
	.context {
		display: flex;
		flex-direction: column;
		font-size: var(--small-font-size);
		color: var(--inactive-color);
	}

	/* A step down with the name, so the details stay subordinate to it. */
	.small .details,
	.small .context {
		font-size: var(--extra-small-font-size);
	}
</style>
