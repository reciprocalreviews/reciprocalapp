import type { Database } from './database';

type Tables = Database['public']['Tables'];
export type ScholarRow = Tables['scholars']['Row'];
export type ScholarID = ScholarRow['id'];
export type ProposalRow = Tables['proposals']['Row'];
export type ProposalID = ProposalRow['id'];
export type SupporterRow = Tables['supporters']['Row'];
export type SupporterID = SupporterRow['id'];
export type CurrencyRow = Tables['currencies']['Row'];
export type CurrencyID = CurrencyRow['id'];
export type VenueRow = Tables['venues']['Row'];
export type VenueID = VenueRow['id'];
export type RoleRow = Tables['roles']['Row'];
export type RoleID = RoleRow['id'];
export type VolunteerRow = Tables['volunteers']['Row'];
export type VolunteerID = VolunteerRow['id'];
export type Response = Database['public']['Enums']['invited'];
