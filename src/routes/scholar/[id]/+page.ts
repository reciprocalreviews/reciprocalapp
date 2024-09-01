/** @type {import('./$types').PageLoad} */
export async function load({ parent, params }) {
	const { supabase } = await parent();

	const { data, error } = await supabase.from('scholars').select().eq('id', params.id).single();

	return {
		scholar: data && error === null ? data : null
	};
}
