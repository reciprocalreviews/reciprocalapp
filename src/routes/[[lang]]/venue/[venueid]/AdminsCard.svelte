<script lang="ts">
	import type { CurrencyRow, ScholarID, ScholarRow, VenueRow } from '$data/types';
	import Button from '$lib/components/Button.svelte';
	import Card from '$lib/components/Card.svelte';
	import Form from '$lib/components/Form.svelte';
	import { DeleteLabel } from '$lib/components/Labels';
	import Paragraph from '$lib/components/Paragraph.svelte';
	import ScholarField from '$lib/components/ScholarField.svelte';
	import ScholarLink from '$lib/components/ScholarLink.svelte';
	import { getDB } from '$lib/data/CRUD';
	import type { LocaleText } from '$lib/locales/Locale';
	import { validEmail, validORCID } from '$lib/validation';
	import { getLocaleContext } from '$routes/Contexts';
	import { handle } from '$routes/feedback.svelte';

	let {
		venue,
		isAdmin,
		minters,
		currency
	}: {
		venue: VenueRow;
		isAdmin: boolean;
		minters: ScholarRow[] | null;
		currency: CurrencyRow;
	} = $props();

	const db = getDB();
	const locale = getLocaleContext();

	let newEditor: string = $state('');

	function validAdmin(scholar: string | ScholarID): ((l: LocaleText) => string) | undefined {
		if (validEmail(scholar)) {
			if (!(minters ?? []).some((m) => m.email === scholar)) return undefined;
			else return (l) => l.view.roles.field.adminScholar.minter;
		}
		if (validORCID(scholar)) {
			if (currency.minters.includes(scholar)) return (l) => l.view.roles.field.adminScholar.minter;
			else return undefined;
		}
		return (l) => l.view.roles.field.adminScholar.invalid;
	}
</script>

<Card
	icon={venue.admins.length}
	subheader
	strings={(l) => l.view.roles.card.admins}
	expand={isAdmin}
>
	<p>
		{locale().view.roles.paragraph.administeredBy}
		{#each venue.admins as adminID, index}
			{#if index > 0 && venue.admins.length > 2},{/if}
			{#if index === venue.admins.length - 1 && venue.admins.length > 1}and{/if}
			<ScholarLink id={adminID} />{#if isAdmin && venue.admins.length > 1}
				&nbsp;<Button
					strings={(l) => l.view.roles.button.removeAdmin}
					active={venue.admins.length > 1}
					testid="remove-admin-{index}"
					action={() =>
						handle(
							db().editVenueAdmins(
								venue.id,
								venue.admins.filter((ad) => ad !== adminID)
							)
						)}>{DeleteLabel}</Button
				>{/if}
		{/each}.
	</p>
	<Paragraph text={(l) => l.view.roles.paragraph.adminsDescription} />

	{#if isAdmin}
		<Form>
			<Paragraph text={(l) => l.view.roles.paragraph.addAdmin} />
			<ScholarField
				strings={(l) => l.view.roles.field.adminScholar}
				bind:text={newEditor}
				size={19}
				valid={(text) => validAdmin(text)}
				showResolved={false}
				testid="add-admin-field"
			/><Button
				strings={(l) => l.view.roles.button.addAdmin}
				active={validAdmin(newEditor) === undefined}
				testid="add-admin-button"
				action={async () => {
					if (await handle(db().addVenueAdmin(venue.id, newEditor))) newEditor = '';
				}}
			/>
		</Form>
	{/if}
</Card>
