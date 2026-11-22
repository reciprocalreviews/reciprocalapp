import type { CompensationRow, RoleRow, SubmissionType } from '#data/types.js';

/** The fields of a role the plan reads. Narrower than RoleRow so tests needn't build one. */
export type PlanRole = Pick<RoleRow, 'id' | 'name' | 'priority' | 'desired_assignments'>;

/** What one role contributes to what a paper of one type pays out. */
export type PlanRow = {
	role: PlanRole;
	/** How many of this role a paper needs. Pay is per approved assignment, so this many
	 * people each receive `amount`. */
	count: number;
	/** Tokens paid to each of them, or null when this role isn't paid for this type. */
	amount: number | null;
	subtotal: number;
};

/** How a paper of one submission type balances: what its roles are paid against what
 * its authors are charged.
 *
 * The rule is that pay may not exceed cost. Every token a paper pays out comes from the
 * venue reserve, and the cost is what refills it, so a type that pays out more than it
 * charges adds new tokens to circulation with every paper, and the supply inflates until
 * reviewing earns nothing worth having. A surplus is fine: it grows the reserve.
 *
 * Advisory only. Amounts are edited one at a time, so a venue is out of balance for a
 * moment during any adjustment, and refusing those saves would make adjusting
 * impossible. */
export type Plan = {
	rows: PlanRow[];
	payout: number;
	cost: number;
	/** `over`: pays out more than it costs. `surplus`: costs more than it pays out, by
	 * `difference`. `even`: the two match. */
	state: 'over' | 'surplus' | 'even';
	/** The absolute gap between payout and cost; 0 when even. */
	difference: number;
};

export function planFor(
	type: Pick<SubmissionType, 'id' | 'submission_cost'>,
	roles: PlanRole[],
	compensation: Pick<CompensationRow, 'role' | 'submission_type' | 'amount'>[]
): Plan {
	const rows = [...roles]
		.sort((a, b) => a.priority - b.priority)
		.map((role) => {
			const amount =
				compensation.find((c) => c.role === role.id && c.submission_type === type.id)?.amount ??
				null;
			const count = role.desired_assignments;
			return { role, count, amount, subtotal: amount === null ? 0 : amount * count };
		});
	const payout = rows.reduce((sum, row) => sum + row.subtotal, 0);
	const cost = type.submission_cost;
	return {
		rows,
		payout,
		cost,
		state: payout > cost ? 'over' : payout < cost ? 'surplus' : 'even',
		difference: Math.abs(cost - payout)
	};
}
