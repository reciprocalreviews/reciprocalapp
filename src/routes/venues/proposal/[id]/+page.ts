/** @type {import('./$types').PageLoad} */
export async function load({ parent, params }) {
	const { supabase } = await parent();

	const { data, error } = await supabase.from('proposals').select().eq('id', params.id).single();

	return {
		proposal: data && error === null ? data : null
	};
}
