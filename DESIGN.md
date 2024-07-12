This document is a design specification for the Reciprocol Reviews (RR) platform. We intend it to specify the conceptual interaction design that people will experience when using the platform and rationale for those choices, as well as aspects of the design that are unresolved. It's primary purpose is to provide contributors with a high level checklist for implementation, but also a long term archive for _why_ it is designed the way it is. This document will _not_ specify low-level design details, like user interface mockups or visual design it; it will stay at the high level interaction flow and user-facing features, describing key pages, functionality, data, and features.

Since RR is a web application, the document is organized by **data**, detailing key data concepts and their relationships; **routes**, corresponding to areas of the web application and detailing their functionality; and **notifications**, which are types of emails that can be sent by the platform in response to user actions or other events. All other backend details for enabling this user experience should be covered in the [ARCHITECTURE](ARCHITECTURE.md) doc.

# Goal

The overarching and foundational goal of RR is to 1) ensure that there is sufficient reviewing labor for all publications submitted for peer review in academia, and 2) enhance the ability of editors to find qualified reviewers and secure high quality, on-time reviews.

There are two types of functionality that we hope will achieve this goal:

1. Streamlining reviewing volunteering for publication venues, and making reviewer availability visible to editors and program committee members
2. Creating a **currency** to represent reviewing labor, compensating people with it when they reivew, and charging it when they create reviewing labor by submitting research papers for review.

Our design hypothesis is that these two core functionalities will result in several value propositions:

1. Easier discovery of reviewers and their availability for editors
2. Improved reviewer availability by requiring reviewing of sufficient quality to publish, and
3. A partial mitigation publish-or-perish obession with quantity of publications by placing a labor cost on peer review.

We're designing and building RR in order to test this hypothesis, with the hopes that it is supported, and academia adopts it as a way to sustain peer review long term.

# User Stories

There are several specific use cases that we want RR to support. Here we capture those through _user stories_, as well as _scenarios_, both to help the reader understand the user experience we aspire to build and the motivations we are trying to serve. But these also serve as a resource to help verify that our data schema below actually enables those experiences.

## An annual conference solicits volunteer reviewers

_As Sam, program co-chair of ACM SIGCSE TS, I want to be able to quickly solicit a large number of volunteer reviewers for this year's review cycle, so that I can ensure every paper submitted gets three reviews._

- Sam logs in to RR and proposes a SIGCSE TS 2025 venue instance
- The RR admins approve it
- Sam configures the profile for the venue, defining six volunteer roles for three tracks and two different review phases, and defining ranked preferences of `preferred`, `if necessary`, and `no`.
- Sam gets the URL of the volunteer page and sends an email through various social media platforms, inviting people to review
- One reviewer receives the link, has an account, just indicates `preferred` for the experience report track, up to 4 papers total.
- Another reviewer recieves the link, doesn't have an account, creates one, and then indicates `if necessary` on research, up to 5 papers.
- After volunteering stabilizes, Sam exports a CSV of all of the volunteers, sorts it by track roles, and uses the reviewer expertise and preferences to manually decide which tracks to assign individuals to. He then imports subsets of the spreadsheet into EasyChair to create the reviewer set for each track. He then sends a message to everyone asking them to check their assignment and notify him if they are no longer able to complete their volunteer commitment.

## An annual conference invites program committee members

_As Dana, program chair of ACM PLDI, I want to send out invites to a curated set of expert reviewers to join the program committee and senior program committee, and quickly get information about who agrees, so that I can form the final program committee in preparation for reviewing season._

- Dana logs into RR and proposes a PLDI 2025 venue instance.
- The RR admins approve it
- Dana adds a description to the venue and defines the two roles, programm committee member and senior program committee member, defining both as `invite only` roles, with `yes` and `no` commitments.
- Dana populates the set of invitees into the venue for each role by submitting a list of email addresses
- Dana sends invitation emails to everyone in each role in her mail client.
- Some program committee members receive the invite, create an account if necessary, see the role to which they have been invited, and indicate yes or no.
- After community invites settle, Dana exports the set of reviewers, filters out the list of declines, and imports them into HotCRP as the program committee and senior program committee, and proceeds with the review process.
- Program committee members return occasionally to RR to remind them of where they've volunteered for reviews.

## A journal wants to create a pool of reviewers, but not require reviewing to submit

_As Derek, EiC of IEEE TSE, I want to curate a set of reviewers who are eager to review journal submissions and access information about their expertise, so that Associate Editors can select people to invite for review._

- Derek logs into RR and proposes a TSE venue instance.
- The RR admins approve it
- Derek adds a description of the venue and sees the default reviewer role with `yes` and `no` commitments, and finds them suitable.
- Amy updates the TSE website to point to the reviewer volunteer link and adjusts the email templates to include RR's email receiver.
- Community member is looking for reviewing practice and finds the volunteer link, and agrees to volunteer for up to 1 paper at a time.
- The Associate Editor, when trying to find reviewers, scans the list of volunteers, and finds the volunteer, and invites them through the journal's review platform. This adds the publication record to the reviewer's list.
- After a decision on the submission is made, an email is sent, triggering an update to the status of the submission in RR, and freeing the reviewer to review again.

## A journal wants to create a pool of reviewers and use tokens to incentivize reviewing

_As Amy, EiC of ACM TOCE, I want to incentivize reviewers to volunteer by requiring reviewing prior to submitting papers for review, and streamline Associate Editors ability to identify people to review based on their expertise and need for tokens._

- Amy logs into RR and proposes a TOCE venue instance.
- The RR admins approve it
- Amy adds a description of the venue and sees the default reviewer role with `yes` and `no` commitments, and finds them suitable.
- Amy sets the compensation levels to 10 tokens for a review, 10 for an AE recommendation, and 1 for an EiC decision, as well as costs of 40 tokens per submission. She also sets the welcome token rate to 30, enabling newcomers to submit if they review just once.
- Amy updates the ACM TOCE website to point to the reviewer volunteer link and to the compensation costs. She also sends an email to `sigcse-members` to solicit volunteers and points to the link
- Community members either receive the email, or see the volunteer link on the website, and log in to voluneer. Those are first time volunteers receive their newly minted welcome tokens.
- A community member submits a paper, indicating whose accounts to deduct the 40 tokens from.
- Amy confirms that the paper should not be desk rejected and then approves the transactions and the submission for review, and assigns an Associate Editor.
- The Associate Editor, when trying to find reviewers, scan the list of volunteers, filtering by expertise keywords, paying attention to reviewers paper limits and other commitments, and ultimately send invites to possible matches. The invites trigger updates to the reviewing status of the reviewer in RR, showing that the reviewer has a TOCE assignment.
- After a decision on the submission is made, an email is sent, which triggers proposed transactions, and emails notifying reviewers of their compensation.

# Legend

We use a few stylistic conventions in this document that have particular meaning:

- `- [ ]` GitHub tasks are used to indicate a design requirement, and whether that requirement is met in the implementation of the platform. Tasks can be followed by a GitHub issue number, corresponding to the issue in this repository representing the work on the feature.
- `- [ ] role` indicates that a particular functionality is only available to scholars with a particular role for a `Venue`.
- ` `` ` Backticks are used to represent specific routes in the application or specific concepts in the application. They don't necessarily represent identifiers in code, but rather specific concepts in the application design.

# Data

There are several key types of data in RR.

## Scholars

`Scholars` are individuals in a research community who are identified by an [ORCID](https://orcid.org/).

- [ ] Scholars can volunteer to review for a `Venue`
- [ ] Scholars can spend and earn `Token`s for that volunteer work, as well as receive `Token`s as gifts, and spend `Token`s to submit manuscripts for peer review.
- [ ] Scholars can also have _`editor`_ status on a `Venue`, which gives them the ability to manage the `transaction`s and `submission`s in a `Venue`.
- [ ] Scholars can also have _`minter`_ status, which gives them the ability to create new `Token`s in a `Venue`'s `Currency`.
- [ ] An individual scholar cannot be both an _`editor`_ and a _`minter`_, as this would allow editors to enrich themselves without oversight. Scholars can specify an email address for communication.
- [ ] Anyone can view a `Scholar`'s record, but only `Scholars` can create, update, or delete their record.

Here is a SQL schema sketch, for clarity:

```sql
create table scholars (
  -- The internal unique ID for scholars, corresponding to an auth record
  id uuid not null references auth(id) primary key on delete cascade,
  -- The scholar's ORCID, a 16-digit number with dashes conforming to the ISO International Standard Name Identifier (ISNI) format, e.g. 0000-0001-2345-6789. References the foreign key on a hypothetical 'auth' table storing authentication details.
  orcid text not null,
  -- The scholar's optional preferred email address for review requests
  email text default null,
  -- Whether the scholar is available to review
  available boolean not null default true,
  -- The scholar's explanation of their availabilty
  status text not null default '':text
);
```

## Venues

A `Venue` is a named and curated collection of manuscripts undergoing peer review (e.g. a journal or conference).

- [ ] A `Venue` has a cost and reward for reviewing labor.
- [ ] `Venue`s are associated with `Submission`s, `Token`s, a `Currency`, and `Transaction`s.
- [ ] `Venue`s can be proposed, but aren't created until approved.
- [ ] `Venue`s can have one or more volunteer roles, which are helpful for distinguishing between different types of volunteering for a venue (e.g., reviewer, reviewer for track A, meta-reviewer for track B)
- [ ] `Venue`s can have one or more commitments to a role, usually `yes` and `no`, but custom committments can support things like `maybe`, `if necessary`, and other social signals.
- [ ] When a `Scholar` volunteers for a `Venue`, they do so for a particular role, with a particular commitment, and optionally with a number of papers they are committing to review. Volunteering for a venue can also include a statement of expertise relevant to the role.

Here is a SQL sketch of all of the tables involved in this.

```sql
create table venues (
  -- The unique ID of the venue
  id uuid not null default uuid_generate_v1() primary key,
  -- The title of the venue
  title text not null default '':text,
  -- The description of the venue
  description text not null default '':text,
  -- A link to the venue's official web page
  url text not null default '':text,
  -- The id of the currency the venue is using
  currency uuid not null references currency(id),
  -- The optional amount of newly minted tokens granted to new volunteers
  welcome_amount integer,
  -- Whether the the venue permits public bidding on submissions
  bidding boolean not null default true,
  -- One or more scholars who serve as editors of the venue
  editors text[] not null default '{}'::text[] check (cardinality(editors) > 0)
);

create table roles (
  -- The unique id of the role
  id uuid not null default uuid_generate_v1() primary key,
  -- The ID of the venue
  venueid uuid not null references venues(id) on delete cascade,
  -- The name of the role
  name text not null '':text,
  -- The rich text description of the role,
  description text not null '':text,
  -- Whether the role is invite only
  invited boolean not null
)

create table commmitments (
  -- The unique id of the commitment
  id uuid not null default uuid_generate_v1() primary key,
  -- The ID of the venue
  venueid uuid not null references venues(id) on delete cascade,
  -- The label for the commitment
  label text not null '':text,
  -- The token compensation for a commitment, in the venue's currency
  amount integer not null
)

create table volunteers (
  -- When this record was last updated
  when timestamp with time zone not null default now(),
  -- The id of the scholar who volunteered
  scholarid uuid not null references scholars(id) on delete cascade,
  -- The id of the venue they volunteered for
  venueid uuid not null references venues(id) on delete cascade,
  -- The role they volunteered for
  role uuid not null references roles(id) on delete cascade,
  -- The commitment they made
  committment uuid not null references commitment(id) on delete cascade,
  -- Relevant expertise keywords provided by the scholar for the role
  expertise text not null,
  -- Whether the volunteer has agreed
  agreed boolean not null,
  -- How many papers they wish to review at any given time, or in this batch, null if not specified
  count integer
);

-- A table of proposed venues
create table proposed (
  -- The unique ID of the venue
  id uuid not null default uuid_generate_v1() primary key,
  -- The title of the venue
  title text not null default '':text,
  -- The email addresses of editors responsible for the venue
  emails text not null default '':text,
  -- The estimated size of the research community,
  size integer not null
)

```

## Currencies

> [!IMPORTANT]
> The data below is specific to compensation

A `Currency` represents a particular named type of peer review labor `Token`, associated with one or more `Venue`s. We allow for many forms of `Currency`, as opposed to one universal one, as different communties may want to place different costs and compensation on different activities, and those amounts will come to have meaning within each of those communities that do not necessarily transfer directly to other communties without some specific exchange agreement.

Here is a SQL sketch, for clarity:

```sql
create table currencies (
  -- The unique id of the currency
  id uuid not null default uuid_generate_v1() primary key,
  -- The name of the currency
  name text not null default '':text,
  -- The minters of the currency, corresponding to scholar is in the scholars table
  minters text[] not null default '{}'::text[] check (cardinality(minters) > 0)
);

-- Three types of exchanges to propose
create type exchange_proposal as enum ('create', 'modify', 'merge');

-- Agreements between owners of currencies
create table exchanges (
  -- The unique id of the currency
  id uuid not null default uuid_generate_v1() primary key,
  -- The first party of the exchange
  currency_one uuid not null references currencies(id),
  -- The second party of the exchange
  currency_two uuid not null references currencies(id),
  -- The multiplier to convert from currency_one to currency_two
  ratio decimal	not null,
  -- List of minters who have approved
  approvers uuid[] not null default '{}'::text[],
  -- Whether the minters have approved. Only set when all current active minters have approved.
  approved boolean not null default false,
  -- If a proposal, what kind
  type exchange_proposal
)
```

## Tokens

> [!IMPORTANT]
> The data below is specific to compensation

A `Token` represents an indivisible unit of peer review labor in a particular `Currency`.

- [ ] `Token`s are typically spent to compensate others for their reviewing labor.
- [ ] `Token`s are typically earned for reviewing labor, but there may be many other creative uses for them (e.g., gifts, incentives, etc.).
- [ ] `Token`s should generally be minted in proportion to scholars, to ensure that there is a balance between labor needed and labor provided. Too few `Token`s would mean that publishing slows because people cannot find enough of them to submit for peer review. Too many `Token`s means that quality and timeliness suffers, because everyone has more than enough tokens to publish, and therefore have no incentive to review.
- [ ] `Token`s are possessed by individual scholar or in a `Venue`'s reserve (meaning they are posessed by no one) and `Transaction`s can change who posses them. They cannot be possessed by neither a scholar or a venue.

Here is a SQL sketch, for clarity:

```sql
create table tokens (
  -- The unique ID of the token
  id uuid not null default uuid_generate_v1() primary key,
  -- The currency that the token is in
  currency uuid not null references currencies(id),
  -- The scholar that currently possess the token, or null, representing no one
  scholar uuid references scholars(id),
  -- The venue that currently posses the token, or null
  venue uuid reference venues(id),
  -- Require that there is one owner
  constraint check_owner check (num_nonnulls(scholar, venue) = 1)

);
```

## Transactions

> [!IMPORTANT]
> The data below is specific to compensation

A `Transaction` represents an exchange of tokens for some purpose, such as submitting something for review, compensation for a review, or a gift.

- [ ] `Transaction`s cannot be deleted; they are a permanent record
- [ ] `Transaction`s are confidential — to preserve reviewing anonymity and gifts — but auditable.

Here is a SQL schema sketch, for clarity:

```sql
create table transactions (
  -- The unique ID of the transaction
  id uuid not null default uuid_generate_v1() primary key,
  -- The scholar who gave the tokens
  from_scholar uuid references scholars(id),
  -- The venue who gave the tokens
  from_venue uuid references venues(id),
  -- Require that there is a from
  constraint check_from check (num_nonnulls(from_scholar, from_venue) = 1)
  -- The optional scholar who received the tokens,
  to_scholar uuid references scholars(id),
  -- The optional venue that received the tokens,
  to_venue uuid references venues(id),
  -- Require that there is a too
  constraint check_to check (num_nonnulls(to_scholar, to_venue) = 1)
  -- An array of token ids moved in the transaction
  tokens uuid[] not null default '{}',
  -- The currency the amount is in
  currency uuid not null references currencies(id),
  -- The purpose of the transaction
  purpose text not null
);
```

## Submissions

> [!IMPORTANT]
> The data below is specific to compensation

A `Submission` represents a manuscript undergoing peer review.

- [ ] Depending on the venue, `Scholar`s may be able to bid on submissions, simplifying an editor's ability to find qualified reviewers.
- [ ] `Submission`s can also be linked to previous submissions, to represent revise and resubmit cycles, or resubmissions to other venues.
- [ ] `Submission`s can be added manually by \_`editor`\_s, or RR can be cc'ed on submission notification emails to be added automatically
- [ ] Submissions are created manually or through email integrations with review systems, which provide submission metadata

Here is a SQL schema sketch, for clarity:

```sql
-- Individual submissions under review
create table submissions (
  -- The unique ID of the submission
  id uuid not null default uuid_generate_v1() primary key,
  -- The venue to which the submission corresponds
  venue uuid not null references venues(id),
  -- The external identifier of the submission, such as a submission number or manuscript number
  externalid text not null,
  -- An optional title for public bidding,
  title text default null,
  -- An optional description of expertise required for public bidding
  expertise text default null
);

-- Individuals who could be assigned to review a particular paper
create table assignments (
  -- The unique ID of the bid
  id uuid not null default uuid_generate_v1() primary key,
  -- The submission bid on
  submissionid uuid not null references submissions(id),
  -- The scholar who bid
  scholarid uuid not null references scholars(id),
  -- The role for which the bid occurred
  roleid uuid not null references roles(id),
  -- False if assigned, true if a bid by the reviewer.
  bid boolean not null default false
);
```

# Routes

The RR web application includes serveral web application screens, each corresponding to one of the kinds of data above, and providing access to functionality to manipulate each. We'll list URL routes routes for each to clarify the browsing experience.

## Landing `/`

The goal of the landing page is to 1) explain the value proposition of RR to editors, reviewers, and authors and 2) help newcomers orient to the application's key interaction points.

- [ ] The page should communicate value propositions to editors:
  - Increased quality and timeliness of reviews
  - Reduced difficulty identifying qualified and available reviewers
  - Reduced submission spam (where spam includes obviously out of scope submissions, some types of fraudulent submissions created by generative AI)
- [ ] The page should communicate value propositions to authors:
  - Faster review turnaround
  - Fairer distribution of peer review labor
- [ ] The page should links to other parts of the site, including all routes below, plus a link to the authenticated scholar's page, if authenticated, to view their dashboard.

## About `/about`

The purpose of the about page is to give context about the project. It should:

- [ ] Explain who is creating RR
- [ ] Why RR exists
- [ ] How others can get involved in maintaining and evolving it
- [ ] How RR is governed and funded.

It has no functionalty.

## Login `/login`

The purpose of the login page is to authenticate a person into the application using ORCID OAuth.

It should:

- [ ] Allow a visitor to initiate and complete an ORCID OAuth authentication, landing them at their `/scholar/[id]` dashboard.

## Scholar `/scholar/[id]`

The purpose of the scholar page is to provide a landing page and dashboard for a specific individual scholar, helping them see information about their labor and helping others understand their expertise.

It should:

- [ ] Link to the scholar's ORCID profile (`scholars.orcid`), to help visitors get more information about them.
- [ ] Display read-only data pulled from the ORCID profile, to reduce the need to navigate to their ORCID profile.
- [ ] Show links to `Venue`s the scholar has volunteered to review for
- [ ] Show links to `Venue`s the scholar is serving as _`editor`_ of.

If scholar ID corresponds to the authenticated user, it should also allow the scholar to:

- [ ] _`scholar`_: Logout
- [ ] _`scholar`_: Indicate whether they are available to review (`scholar.available`)
- [ ] _`scholar`_: Explain their reviewing availability (`scholar.status`)
- [ ] _`scholar`_: Allow editing of the scholar's preferred email address. (`scholar.email`)

> [!IMPORTANT]
> The functionality below is specific to compensation

- [ ] _`scholar`_: View a history of `Transaction`s associated with the scholar
- [ ] _`scholar`_: Gift tokens to someone else using the scholar's ORCID or email, creating two transactions that deduct from the scholar and deposit to the other scholar

## Venue List `/venues`

The purpose of the venue list page is to show all venues managed on RR, or proposed to be managed on RR.

It should:

- [ ] Show all `Venue`s, including active and proposed ones.

- [ ] _`scholar`_: Propose a new `Venue` for the platform for review by the platform maintainers. `Venue` proposals should gather the name of the venue, the email addresses of the person or people leading editing of it, and the estimated size of the number of scholars in the community. `Venue`s with similar names are retrieved and shown to prevent duplicate venue creation. When the proposal is submitted, an email notification is sent to the email addresses listed and RR administrators. A `Venue` is created, but not active until approved.

- [ ] _`admin`_: Approve a `Venue` for use, indicating who should take the _editor_ and _minter_ roles for the platform, and creating tokens for all scholars in favor of the petition.

## Venue `/venue/[id]`

The purpose of a `Venue` page is to provide information about its compensation, costs, and people in charge.

The page should:

- [ ] Show the name, description, and URL to the venue's website.

When a venue is in a **proposed** state:

- [ ] View the _`editors`_ and _`minters`_ of the venue
- [ ] View the estimated size of the community
- [ ] _`scholar`_: Vote to support adopting RR for the venue.

When a venue is **approved** state:

- [ ] View the cost, welcome amount, commitments, and compensation of the venue.
- [ ] _`scholar`_: For non-invite only roles, volunteer to review for the venue in a particular role. When they first volunteer, a number of tokens specified by for venue `welcome_amount` should be minted and given to the scholar, welcoming them to the community.
- [ ] _`scholar`_: For invite-only roles, the role is shown, but without the ability to volunteer, unless the scholar is in the invited list. If they are invited, they can confirm or reject their invite.
- [ ] _`scholar`_: Change expertise keywords for a role for the venue
- [ ] _`scholar`_: Change commitment for a role for the venue
- [ ] _`scholar`_: Change paper count for a role for the venue

- [ ] _`editor`_: Modify the venue name, description
- [ ] _`editor`_: Change the _`editor`_(s) of the venue, ensuring there is always one
- [ ] _`editor`_: Set the state to inactive

- [ ] _`editor`_: Export the list of reviewers as a CSV file for use on other plaforms, including ORCID, name, email, expertise, role, commitment, and paper count.
- [ ] _`editor`_: Create roles for the venue.
- [ ] _`editor`_: Create commitments for the venue.
- [ ] _`editor`_: Edit the descriptions of roles.
- [ ] _`editor`_: Delete a commitment, confirming they understand that all volunteers will be removed from the commitment.
- [ ] _`editor`_: Delete a role, confirming they understand that all volunteers will be removed from the role.
- [ ] _`editor`_: Invite one or more `Scholar`s by ORCID or email to a particular role.

> [!IMPORTANT]
> The functionality below is specific to compensation

- [ ] _`editor`_: Modify the newcomer gift in tokens
- [ ] _`editor`_: Modify submission costs in tokens, reviewing compensation in tokens. Submission cost must equal to total compensation for a submission.
- [ ] _`editor`_: View the total number of tokens in the venue and who posses them, to gauge the health of the community.
- [ ] _`editor`_: Change the _`minter`_(s) of the venue, ensuring there is always one
- [ ] _`editor`_: Enable or disable (`venues.bidding`), determining whether submissions can be bid on by `scholars`.

When a venue is in an _inactive_ state:

- [ ] Communicate that it is inactive.

## Currency `/venue/[id]/currency`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of this page is to manage the venue's `Currency`.

- [ ] _`scholar`_: Show any existing exchange rates approved by the platform.
- [ ] _`scholar`_: View the exchange rates the currency is involved in
- [ ] _`editor`_: Convert a specific token to another venue's currency. This enables a one-time exchange, such as when an editor might approve someone using currency from another `Venue` to submit to their venue.
- [ ] _`editor`_: Specify a conversion rate between one venue and another, which enables scholars to independently convert their tokens from one currency to another. This enables an official one way exchange rate, reducing barriers to cross-venue transactions.
- [ ] _`editor`_: Unify two currencies, removing the need to convert between a currency. Must be approved by the `editors` of both venues. This prevent editors from unilaterally creating changes.
- [ ] _`minter`_: Create new tokens within the venue's currency, to address token scarcity in the community. This functionality should provide guidance on best practices, including warnings about what happens if they create too many tokens. For example, there should be a certain number of tokens per scholar in the community at a minimum, but not so many that publishing requires no labor.
- [ ] _`minter`_: Propose a new exchange rate for other minters involved in two currencies to approve. Everyone must approve for it to be official. Inactive until all minters involved in both currencies approve.
- [ ] _`minter`_: Approve a proposed exchange rate.
- [ ] _`minter`_: Propose a modification to an exchange rate
- [ ] _`minter`_: Approve a modified exchange rate. Once all have approved, the old exchange between the two is deleted and the new approved one is created.
- [ ] _`minter`_: Propose a merger of currencies
- [ ] _`minter`_: Approve a merger of currencies. Once all have approved, all tokens in the secondary currency are deleted, and replaced with new tokens in the first currency using the current exchange rate, and the exchange is deleted.

## Transactions `/venue/[id]/transactions`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of this page is to allow for management of all `Transaction`s associated with a `Venue`.

**FUNCTIONALITY**. The transactions page for a venue should allow for:

- [ ] _`editor`_, _`minter`_: View all transactions
- [ ] _`editor`_, _`minter`_: Search for transactions involving particular people or containing particular text
- [ ] _`minter`_: Approve pending transactions that do not involve the scholar approving
- [ ] _`editors`_, _`minters`_: Cancel approved transactions that do not involve the scholar canceling
- [ ] _`minters`_: Change the frequency of email reminders about unapproved transactions to never, daily, or weekly

## `/venue/[id]/submissions`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of the submissions page is to help scholars see all active submissions in review, and if an editor, manage them.

It should should:

- [ ] Show the total number of active submissions in the system.
- [ ] _`editor`_: Filter submissions by whether they are active, by author, reviewer, etc.
- [ ] _`editor`_: Manually add a new submission, including all of the transactions, the manuscript ID specific to the venue, the scholar authors of the submission, and how much each author is contributing. (This is to overcome integration failures, or submisions managed outside of normal reviewing platform flows.)
- [ ] _`editor`_: Submit bulk `Submission`s to the system, allowing more than one at a time
- [ ] _`editor`_: Resolve a specific submission, generating transactions to compensate scholars for their reviewing labor
- [ ] _`editor`_: Resolve bulk submissions, generating transactions for multiple existing submissions
- [ ] _`editor`_: View RR email addresses to include on review activity emails on other platforms
- [ ] _`editor`_: View transaction templates for each transaction type ot include in email text on other platform's email templates

If the `Venue` is set to be public:

- [ ] _`scholar`_: View specific active submissions and the topic and method expertise required (but not submission titles), sorted by submissions most in need of reviews
- [ ] _`scholar`_: Bid on active submissions based on expertise required

## Submission `/venue/[id]/submission`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of a submission page is to allow editors and scholars to see information about the submission. This page will not have any major functionality, unless future versions of RR also support reviewing activity itself. In those future versions, this would be the route where scholars access the submission draft and submit reviews and meta reviews, and discuss the submission to come to a recommendation.

# Notifications

RR will also send periodic reminders based on time-based events:

- [ ] `Venue`s are checked daily for a certain proportion of support, and editors are notified when the petition exceeds that threshold.
- [ ] send `scholar`s periodic reminders to update their availability

> [!IMPORTANT]
> Emails below are specific to compensation

- [ ] Send `minters` periodic reminders of unapproved transactions, based on the frequency set in the `Transactions` page

RR will have dedicated email adresses for each venue that, if sent to, will generate events and data that is user facing.

- [ ] When an email is sent to the `Venue`-specific address and proposed `Transaction` meta-data is found, create proposed `Transaction`s corresponding to the transaction meta-data provided. Types of transactions and corresponding metadata include:
  - [ ] _Submission_ (manuscript ID, ORCID for each author, and amount each author should be deducted).
  - [ ] _Review_ (manuscript ID, ORCID for the reviewer)
  - [ ] _Meta-review_ (manuscript ID, ORCID for meta-reviewer)
- [ ] When a `Transaction` specified in an email could not be processed — because it lacked metadata, lacked metadata that could be matched to a venue, manuscript, or scholar, or violated a venues requirements — the editor of the venue is notified of the error so they can manually correct it, and potentially any configuration issues with the integration.
- [ ] When a proposed `Transaction` is declined, an email is sent to the person who proposed it with an explanation for why.
- [ ] When `Venue`s become **approved**, send emails to the editor and all people who upvoted the venue, notifying them of their new tokens and the live process.
