/** @type {import('./$types').PageLoad} */
export async function load({ parent, params }) {
	const { supabase } = await parent();

	const { data: currency, error: currencyError } = await supabase
		.from('currencies')
		.select()
		.eq('id', params.id)
		.single();
	if (currencyError) console.log(currencyError.message);

	const { data: venues, error: venuesError } = await supabase
		.from('venues')
		.select()
		.eq('currency', params.id);
	if (venuesError) console.log(venuesError.message);

	return {
		currency,
		venues
	};
}
