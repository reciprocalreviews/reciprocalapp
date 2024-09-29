/** @type {import('./$types').PageLoad} */
export async function load({ parent, params }) {
	const { supabase } = await parent();

	const { data, error } = await supabase.from('currencies').select().eq('id', params.id).single();

	return {
		currency: data && error === null ? data : null
	};
}
