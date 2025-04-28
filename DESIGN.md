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
- The RR stewards approve it
- Sam configures the profile for the venue, defining six volunteer roles for three tracks and two different review phases, and defining ranked preferences of `preferred`, `if necessary`, and `no`.
- Sam gets the URL of the volunteer page and sends an email through various social media platforms, inviting people to review
- One reviewer receives the link, has an account, just indicates `preferred` for the experience report track, up to 4 papers total.
- Another reviewer recieves the link, doesn't have an account, creates one, and then indicates `if necessary` on research, up to 5 papers.
- After volunteering stabilizes, Sam exports a CSV of all of the volunteers, sorts it by track roles, and uses the reviewer expertise and preferences to manually decide which tracks to assign individuals to. He then imports subsets of the spreadsheet into EasyChair to create the reviewer set for each track. He then sends a message to everyone asking them to check their assignment and notify him if they are no longer able to complete their volunteer commitment.

## An annual conference invites program committee members

_As Dana, program chair of ACM PLDI, I want to send out invites to a curated set of expert reviewers to join the program committee and senior program committee, and quickly get information about who agrees, so that I can form the final program committee in preparation for reviewing season._

- Dana logs into RR and proposes a PLDI 2025 venue instance.
- The RR stewards approve it
- Dana adds a description to the venue and defines the two roles, programm committee member and senior program committee member, defining both as `invite only` roles.
- Dana populates the set of invitees into the venue for each role by submitting a list of email addresses
- Dana sends invitation emails to everyone in each role in her mail client.
- Some program committee members receive the invite, create an account if necessary, see the role to which they have been invited, and indicate yes or no.
- After community invites settle, Dana exports the set of reviewers, filters out the list of declines, and imports them into HotCRP as the program committee and senior program committee, and proceeds with the review process.
- Program committee members return occasionally to RR to remind them of where they've volunteered for reviews.

## A journal wants to create a pool of reviewers, but not require reviewing to submit

_As Derek, EiC of IEEE TSE, I want to curate a set of reviewers who are eager to review journal submissions and access information about their expertise, so that Associate Editors can select people to invite for review._

- Derek logs into RR and proposes a TSE venue instance.
- The RR stewards approve it.
- Derek adds a description of the venue and sees the default reviewer role.
- Derek updates the TSE website to point to the reviewer volunteer link and adjusts the email templates to include RR's email receiver.
- Community member is looking for reviewing practice and finds the volunteer link, and agrees to volunteer for up to 1 paper at a time.
- The Associate Editor, when trying to find reviewers, scans the list of volunteers, and finds the volunteer, and invites them through the journal's review platform. This adds the publication record to the reviewer's list.
- After a decision on the submission is made, an email is sent, triggering an update to the status of the submission in RR, and freeing the reviewer to review again.

## A journal wants to create a pool of reviewers and use tokens to incentivize reviewing

_As Amy, EiC of ACM TOCE, I want to incentivize reviewers to volunteer by requiring reviewing prior to submitting papers for review, and streamline Associate Editors ability to identify people to review based on their expertise and need for tokens._

- Amy logs into RR and proposes a TOCE venue instance.
- The RR stewards approve it.
- Amy convinces Becky, another scholar with whom Amy does not have a conflict of interest, to act as an auditor for the token system.
- Amy logs into RR and proposes a new currency TOCE-Tokens for TOCE where Becky has the responsibility of creating new tokens and monitoring the health of the currency.
- The RR stewards approve the currency and Becky's nomination.
- Amy adds a description of the venue and sees the default reviewer role and finds it suitable. 
- Amy makes TOCE-Tokens the currency for the venue. She accepts the initial setting of no exchanges with other currencies.
- Amy sets the compensation levels to 10 TOCE-Tokens for completing a review, 10 for submitting an AE recommendation, and 1 for an EiC decision, as well as a cost of 40 TOCE-Tokens per submission. She also sets the welcome token rate to 10, enabling newcomers to submit if they review just once, and she generates a list of prior reviewers who need retroactive compensation.
- After review, Becky mints the required number of tokens for the initial round of retroactive compensation as well as a initial pool of tokens that should be sufficient to fund reviewing activities for 3-6 months. The tokens are deposited in the venue's wallet.
- Amy informs past reviewers of the change in policies and sends them gifts from the initial token allocation.
- Amy updates the ACM TOCE website to point to the reviewer volunteer link and to the compensation costs. She also sends an email to `sigcse-members` to solicit volunteers and points to the link.
- Community members either receive the email, or see the volunteer link on the website, and log in to volunteer. Those are first time volunteers receive their newly minted welcome tokens.
- An existing community member (past reviewer) submits a paper, indicating whose accounts to deduct the 40 tokens from.
- Amy confirms that the paper should not be desk rejected and then approves the transactions and the submission for review, and assigns an Associate Editor.
- The Associate Editor, when trying to find reviewers, scan the list of volunteers, filtering by expertise keywords, paying attention to reviewers paper limits and other commitments, and ultimately send invites to possible matches. The invites trigger updates to the reviewing status of the reviewer in RR, showing that the reviewer has a TOCE assignment.
- After a decision on the submission is made, an email is sent, which triggers proposed transactions, and emails notifying reviewers of their compensation.
- On a periodic basis, both Amy and Becky review the TOCE wallet balance and the transactions made on the currency. Becky mints additional tokens for the venue when the balance is low, if no anomalous transactions are detected, and Amy updates the compensation policies as needed to encourage continued reviewing and submissions by new community members.

## An experienced reviewer from another community wishes to submit to a journal that uses tokens 

_Amy is the EiC of ACM TOCE, which uses tokens to incentivize reviewing, and Alex is the EiC of FictionalEducation, which also uses tokens. Both Amy and Alex are also the owners of their currencies. Becky is the auditor for the token system ACM TOCE uses, and Basil is the auditor for the token system FictionalEducation uses. Charlie is an experienced reviewer for FictionalEducation._

- Charlie reviews the ACME TOCE website and decides they would like to submit work. However, they do not have TOCE-Tokens to cover the cost of the submission.
- Charlie logs into RR and checks the conversion rate for FictionalEducation-Tokens to TOCE-Tokens. They find there isn't a posted rate.
- Charlie requests a currency conversion rate for FictionalEducation-Tokens and TOCE-Tokens. 
- The request is received by Amy and Alex. Either of them can propose a token exchange rate. Amy gets to it first and proposes an exchange rate of 1:1 from FictionalEducation-Tokens into TOCE-Tokens and a separate exchange rate of 1:1 from TOCE-Tokens to FictionalEducation-Tokens, after reviewing the two journals compensation rates and finding them similar.
- Alex reviews the proposal and approves the exchange out of FictionalEducation-Tokens but declines the exchange into FictionalEducation-Tokens because they are concerned about an influx of new authors who are not yet reviewing for the journal.
- Both Becky and Basil are notified of the currency exchange proposals and their outcome. Either could choose to consult with the currency owners (Amy and Alex) or, in an extreme case, to notify an RR steward if they believe something inappropriate has occurred. In this case, neither has concerns, so they take no action within the review period.
- Charlie logs into RR at a later date and finds that there is now a conversion rate. They propose a Currency Conversion of some of their FictionalEducation-Tokens into TOCE-tokens. The system automatically performs the conversion. 
- Charlie visits the ACM TOCE site, submits their work, and proposes to pay the submission fee from their own wallet.
- Becky and Basil can both view the conversion in their logs. Either could choose to make conversions on their currency non-automatic, so that they would be required to approve all conversions, instead of just reviewing them after, but they are aware that this would impose a delay.

## An auditor identifies the potential for destabilization of a currency in an exchange rate proposal

_Amy is the EiC of ACM TOCE, which uses tokens to incentivize reviewing. Becky is the auditor for the token system ACM TOCE uses, and Casey is the owner of the currency._

- Casey logs into RR and finds that a reviewer has requested a currency converesion rate between TOCE-Tokens and another currency that is used by multiple journals.
- Casey reviews a few of the journals and finds that they award a similar number of tokens per review as compared to ACM TOCE, so they propose a 1:1 exchange rate into TOCE-Tokens. This proposal is approved by the other currency owner.
- Becky is notified of the currency exchange proposal and its outcome. Before the exchange becomes live, Becky has a short (48 hours, in this case) period of time to review the proposal. If they choose not to do so, the exchange would go live.
- In this case, Becky independently reviews the compensation policies of the journals and is surprised to find that, while compensation policies are similar, the journals using the other currency require a much larger number of tokens to submit. Becky is concerned that they are missing something important, so they reach out to Casey and, in the meantime, cancel the proposal.
- After discussion, Becky and Casey may decide to go forward, in which case Casey would propose the currency exchange again, or Casey may choose to propose a different exchange rate after learning that, for example, the journals in the other currency require twice as many reviewers per submission.
- Becky has access to currency conversions in a log they can view, so they can also suspend (cancel) the currency exchange if they become concerned about the number or pattern of exchanges.

## A venue with its own currency decides to adopt a currency used by several other venues

_Amy is the EiC of ACM TOCE, which uses tokens to incentivize reviewing, and is also the owner of its currency. Becky is the auditor for the TOCE currency, and Basil is the auditor for another currency used by several IEEE venues. Casey is an owner of the IEEE venue currency._

- After noting that many of ACM TOCE's reviewers and authors also publish at IEEE venues, Amy decides it may be useful to pursue adoption of the IEEE currency. Doing so would signal to scholars that any work for ACM TOCE counts in the eyes of the IEEE venues and vice versa. 
- Amy contacts Casey to discuss a potential merger. They agree that the existing exchange rate is working well, so it does not require modification, and they agree in principal to the ACM TOCE currency being merged into the IEEE currency. Once finalized, this means that all ACM TOCE tokens will be converted to IEEE tokens at the current exchange rate.  
- Amy submits the merge request. (They would have submitted an exchange rate update first, if changes had been needed.) Casey approves it.
- Both Becky and Basil are notified that a merge proposal has been received. They have a chance to review the proposal and can accept or decline it. There is no automatic acceptance on this transaction, since currencies will be automatically converted once it goes into force, which will notify users and would be difficult to reverse.
- Both Becky and Basil accept. When the second auditor accepts, all holders of the currency receive a message informing them of the upcoming conversion of their TOCE tokens to IEEE tokens. 
- A short period of time (one week, in this case) after the merger is announced, ACM TOCE's currency is changed to IEEE tokens. Then, all TOCE tokens are converted to IEEE tokens at the posted exchange rate. Both Amy and Becky lose their roles as currency owner and auditor of the TOCE currency.

# Legend

We use a few stylistic conventions in this document that have particular meaning:

- `- [ ]` GitHub tasks are used to indicate a design requirement, and whether that requirement is met in the implementation of the platform. Tasks can be followed by a GitHub issue number, corresponding to the issue in this repository representing the work on the feature.
- `- [ ] role` indicates that a particular functionality is only available to scholars with a particular role for a `Venue`.
- ` `` ` Backticks are used to represent specific routes in the application or specific concepts in the application. They don't necessarily represent identifiers in code, but rather specific concepts in the application design.

# Data

There are several key types of data in RR.

## Scholars

`Scholars` are individuals in a research community who are identified by an [ORCID](https://orcid.org/).

- [x] Scholars can volunteer to review for a `Venue`
- [ ] Scholars can spend and earn `Token`s for that volunteer work
- [x] Scholars can receive `Token`s as gifts
- [x] Scholars can spend `Token`s to submit manuscripts for peer review.
- [x] Scholars can also have _`editor`_ status on a `Venue`, which gives them the ability to manage the `transaction`s and `submission`s in a `Venue`.
- [x] Scholars can also have _`minter`_ status, which gives them the ability to create new `Token`s in a `Venue`'s `Currency`.
- [ ] An individual scholar cannot be both an _`editor`_ and a _`minter`_, as this would allow editors to enrich themselves without oversight. Scholars can specify an email address for communication.
- [x] Anyone can view a `Scholar`'s record, but only `Scholars` can create, update, or delete their record.

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
  status text not null default '':text,
  -- The scholar's steward status
  steward boolean not null default false
);
```

## Venues

A `Venue` is a named and curated collection of manuscripts undergoing peer review (e.g. a journal or conference).

- [x] A `Venue` has a cost and reward for reviewing labor.
- [x] `Venue`s are associated with `Submission`s, `Token`s, a `Currency`, and `Transaction`s.
- [x] `Venue`s can be proposed, but aren't created until approved.
- [x] `Venue`s can have one or more volunteer roles, which are helpful for distinguishing between different types of volunteering for a venue (e.g., reviewer, reviewer for track A, meta-reviewer for track B)
- [x] When a `Scholar` volunteers for a `Venue`, they do so for a particular role, with a particular commitment, and optionally with a number of papers they are committing to review. Volunteering for a venue can also include a statement of expertise relevant to the role.

Here is a SQL sketch of all of the tables involved in this.

```sql

-- only platform stewards can create venues
-- anyone can view venues
-- only platform stewards and editors can update venues
-- only platform stewards and editors can delete venues
create table venues (
  -- The unique ID of the venue
  id uuid not null default uuid_generate_v1() primary key,
  -- The title of the venue
  title text not null default ''::text,
  -- The description of the venue
  description text not null default ''::text,
  -- A link to the venue's official web page
  url text not null default ''::text,
  -- The id of the currency the venue is currently using
  currency uuid not null references currencies(id),
  -- The optional amount of newly minted tokens granted to new volunteers
  welcome_amount integer not null,
  -- Whether the the venue permits public bidding on submissions
  bidding boolean not null default true,
  -- One or more scholars who serve as editors of the venue
  editors uuid[] not null default '{}'::uuid[] check (cardinality(editors) > 0)
);

-- only editors can create venue roles
-- anyone can view venue roles
-- only editors can update venue roles
-- only editors can delete venue roles
create table roles (
  -- The unique id of the role
  id uuid not null default uuid_generate_v1() primary key,
  -- The ID of the venue
  venueid uuid not null references venues(id) on delete cascade,
  -- The name of the role
  name text not null default ''::text,
  -- The rich text description of the role,
  description text not null default ''::text,
  -- Whether the role is invite only
  invited boolean not null
);

-- editors can invite and volunteers if not invite only
-- anyone can view volunteers
-- only volunteers can update
-- editors and volunteers can delete
create table volunteers (
  -- The id of the scholar who volunteered
  scholarid uuid not null references scholars(id) on delete cascade,
  -- The role they volunteered for
  roleid uuid not null references roles(id) on delete cascade,
  -- The id of the venue volunteered for
  venueid uuid not null references venues(id) on delete cascade,
  -- When this record was last updated
  created timestamp with time zone not null default now(),
  -- Relevant expertise provided by the scholar for the role
  expertise text not null,
  -- Optionally, how many submissions they wish to review in the role
  count integer default null
);

-- anyone can propose venues
-- anyone can view proposals
-- stewards can update proposals
-- stewards can delete proposals
create table proposals (
  -- The unique ID of the venue
  id uuid not null default uuid_generate_v1() primary key,
  -- The title of the venue
  title text not null default ''::text,
  -- The email addresses of editors responsible for the venue
  emails text not null default ''::text,
  -- The estimated size of the research community,
  census integer not null
);

-- anyone can support proposals
-- anyone can view supporters
-- supporters can update support
-- supports can stop supporting
create table supporters (
    -- The unique ID of the support
    id uuid not null default uuid_generate_v1() primary key,
    -- The scholar supporting the proposal
    scholarid uuid not null references scholars(id) on delete cascade,
    -- The message the scholar supported
    message text not null default ''::text,
    -- The proposal being supported
    proposalid uuid not null references proposals(id) on delete cascade
);

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
  name text not null default ''::text,
  -- The minters of the currency, corresponding to scholar is in the scholars table. Must be at least one minter.
  minters uuid[] not null default '{}'::uuid[] check (cardinality(minters) > 0)
);

-- Three types of exchanges to propose
create type exchange_proposal_kind as enum ('create', 'modify', 'merge');

-- Agreements between owners of currencies
create table exchanges (
  -- The unique id of the currency
  id uuid not null default uuid_generate_v1() primary key,
  -- The time the exchange was created
  proposed timestamp with time zone not null default now(),
  -- Whether the minters have approved. Only set when all current active minters have approved.
  approved timestamp with time zone default null,
  -- The first currency of the exchange
  currency_from uuid not null references currencies(id),
  -- The second currenty of the exchange
  currency_to uuid not null references currencies(id),
  -- The multiplier to convert from currency_from to currency_to
  ratio decimal	not null,
  -- List of minters who have approved
  approvers uuid[] not null default '{}'::uuid[],
  -- If a proposal, what kind
  kind exchange_proposal_kind
);
```

## Tokens

> [!IMPORTANT]
> The data below is specific to compensation

A `Token` represents an indivisible unit of peer review labor in a particular `Currency`.

- [x] `Token`s are typically spent to compensate others for their reviewing labor.
- [x] `Token`s are typically earned for reviewing labor, but there may be many other creative uses for them (e.g., gifts, incentives, etc.).
- [x] `Token`s should generally be minted in proportion to scholars, to ensure that there is a balance between labor needed and labor provided. Too few `Token`s would mean that publishing slows because people cannot find enough of them to submit for peer review. Too many `Token`s means that quality and timeliness suffers, because everyone has more than enough tokens to publish, and therefore have no incentive to review.
- [x] `Token`s are possessed by individual scholar or in a `Venue`'s reserve (meaning they are posessed by no one) and `Transaction`s can change who posses them. They cannot be possessed by neither a scholar or a venue.

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
  venue uuid references venues(id),
  -- Require that there is one owner
  constraint check_owner check (num_nonnulls(scholar, venue) = 1)

);
```

## Transactions

> [!IMPORTANT]
> The data below is specific to compensation

A `Transaction` represents an exchange of tokens for some purpose, such as submitting something for review, compensation for a review, or a gift.

- [x] `Transaction`s cannot be deleted; they are a permanent record
- [x] `Transaction`s are confidential — to preserve reviewing anonymity and gifts — but auditable.

Here is a SQL schema sketch, for clarity:

```sql
create table transactions (
  -- The unique ID of the transaction
  id uuid not null default uuid_generate_v1() primary key,
  -- The scholar who gave the tokens
  from_scholar uuid references scholars(id),
  -- The venue who gave the tokens
  from_venue uuid references venues(id),
  -- Require that there is either a scholar or venue source but not both
  constraint check_from check (num_nonnulls(from_scholar, from_venue) = 1),
  -- The scholar who received the tokens,
  to_scholar uuid references scholars(id),
  -- The venue that received the tokens,
  to_venue uuid references venues(id),
  -- Require that there is either a scholar or venue destination but not both
  constraint check_to check (num_nonnulls(to_scholar, to_venue) = 1),
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
- [x] `Submission`s can also be linked to previous submissions, to represent revise and resubmit cycles, or resubmissions to other venues.
- [x] `Submission`s can be added manually by \_`editor`\_s.
- [ ] ([#41](https://github.com/reciprocalreviews/reciprocalapp/issues/41)): Submissions can be proposed through email integrations with review systems, which provide submission metadata, but must then be approved by editors

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

- [x] The page should communicate value propositions to editors:
  - Increased quality and timeliness of reviews
  - Reduced difficulty identifying qualified and available reviewers
  - Reduced submission spam (where spam includes obviously out of scope submissions, some types of fraudulent submissions created by generative AI)
- [x] The page should communicate value propositions to authors:
  - Faster review turnaround
  - Fairer distribution of peer review labor
- [x] The page should links to other parts of the site, including all routes below, plus a link to the authenticated scholar's page, if authenticated, to view their dashboard.

## About `/about`

The purpose of the about page is to give context about the project. It should:

- [x] Explain who is creating RR
- [x] Why RR exists
- [x] How others can get involved in maintaining and evolving it
- [ ] How RR is governed and funded ([#13](https://github.com/reciprocalreviews/reciprocalapp/issues/13))

It has no functionalty.

## Login `/login`

The purpose of the login page is to authenticate a person into the application using ORCID OAuth.

It should:

- [ ] ([#19](https://github.com/reciprocalreviews/reciprocalapp/issues/19)): Allow a visitor to initiate and complete an ORCID OAuth authentication, landing them at their `/scholar/[id]` dashboard

## Scholar `/scholar/[scholarid]`

The purpose of the scholar page is to provide a landing page and dashboard for a specific individual scholar, helping them see information about their labor and helping others understand their expertise.

It should:

- [x] Link to the scholar's ORCID profile (`scholars.orcid`), to help visitors get more information about them.
- [ ] ([#19](https://github.com/reciprocalreviews/reciprocalapp/issues/19)): Display read-only data pulled from the ORCID profile, to reduce the need to navigate to their ORCID profile.
- [x] Show links to `Venue`s the scholar has volunteered to review for
- [x] Show links to `Venue`s the scholar is serving as _`editor`_ of.

If scholar ID corresponds to the authenticated user, it should also allow the scholar to:

- [x] _`scholar`_: Logout
- [x] _`scholar`_: Indicate whether they are available to review (`scholar.available`)
- [x] _`scholar`_: Explain their reviewing availability (`scholar.status`)
- [x] _`scholar`_: Allow editing of the scholar's preferred email address. (`scholar.email`)

> [!IMPORTANT]
> The functionality below is specific to compensation

- [x] _`scholar`_: View a history of `Transaction`s associated with the scholar
- [x] _`scholar`_: Gift tokens to someone else using the scholar's ORCID or email

## Venue List `/venues`

The purpose of the venue list page is to show all venues managed on RR, or proposed to be managed on RR.

It should:

- [x] Show all `Venue`s, including active and proposed ones.
- [x] _`scholar`_: Propose a new `Venue` for the platform for review by the platform maintainers. `Venue` proposals should gather the name of the venue, the email addresses of the person or people leading editing of it, and the estimated size of the number of scholars in the community. `Venue`s with similar names are retrieved and shown to prevent duplicate venue creation. When the proposal is submitted, an email notification is sent to the email addresses listed and RR stewards. A `Venue` is created, but not active until approved.
- [x] _`steward`_: Approve a `Venue` for use, indicating who should take the _editor_ and _minter_ roles for the platform, and creating tokens for all scholars in favor of the petition.

## Proposals `/venues/proposal`

The purpose of this page is to allow for the proposal of new pages.

- [x] _`scholar`_: Submit a new venue proposal

## Proposal `/venues/proposal/[proposalid]`

The purpose of this page is to allow people to support proposals and check their status.

- [x] View the details about the proposed venue.
- [x] _`scholar`_ : Support a proposal.

- [x] _`steward`_: Edit a proposal's venue name
- [x] _`steward`_: Edit a proposal's venue census
- [x] _`steward`_: Edit a proposal's venue editors
- [x] _`steward`_: Delete a proposal
- [x] _`steward`_: Approve a proposal

## Venue `/venue/[id]`

The purpose of a `Venue` page is to provide information about its compensation, costs, and people in charge.

The page should:

- [x] Show the name, description, and URL to the venue's website.

When a venue is in a **proposed** state:

- [x] View the _`editors`_ of the venue
- [x] View the estimated size of the community
- [x] _`scholar`_: Vote to support adopting RR for the venue.

When a venue is **approved** state:

- [x] View the cost, welcome amount, roles, and compensation of the venue.
- [x] View the _`minters`_ of the venue
- [x] View the number of tokens owned by the venue
- [x] _`scholar`_: For non-invite only roles, volunteer to review for the venue in a particular role. When they first volunteer, a number of tokens specified by for venue `welcome_amount` should be minted and given to the scholar, welcoming them to the community.
- [x] _`scholar`_: For invite-only roles, the role is shown, but without the ability to volunteer, unless the scholar is in the invited list. If they are invited, they can confirm or reject their invite.
- [x] _`scholar`_: Change expertise keywords for a role for the venue
- [x] _`scholar`_: Change commitment for a role for the venue
- [x] _`scholar`_: Change paper count for a role for the venue

- [x] _`editor`_: Modify the venue name, description
- [x] _`editor`_: Change the _`editor`_(s) of the venue, ensuring there is always one
- [ ] _`editor`_ ([#42](https://github.com/reciprocalreviews/reciprocalapp/issues/42)): Set the state to inactive

- [ ] _`editor`_ ([#33](https://github.com/reciprocalreviews/reciprocalapp/issues/33)): Export the list of reviewers as a CSV file for use on other plaforms, including ORCID, name, email, expertise, role, commitment, and paper count.
- [x] _`editor`_: Create roles for the venue.
- [x] _`editor`_: Edit the descriptions of roles.
- [x] _`editor`_: Delete a role, confirming they understand that all volunteers will be removed from the role.
- [ ] _`editor`_ ([#32](https://github.com/reciprocalreviews/reciprocalapp/issues/32)): Invite one or more `Scholar`s by ORCID to a particular role.
- [x] _`editor`_: Invite one or more `Scholar`s by email to a particular role.
- [x] _`editor`_: Gift tokens from the venue to a scholar

> [!IMPORTANT]
> The functionality below is specific to compensation

- [x] _`editor`_: Modify the newcomer gift in tokens
- [x] _`editor`_: Modify submission costs in tokens, reviewing compensation in tokens. Submission cost must equal to total compensation for a submission.
- [x] _`editor`_: View the total number of tokens in the venue and who posses them, to gauge the health of the community.
- [x] _`editor`_: Change the _`minter`_(s) of the venue, ensuring there is always one
- [x] _`editor`_: Enable or disable (`venues.bidding`), determining whether submissions can be bid on by `scholars`.

When a venue is in an _inactive_ state:

- [ ] ([#42](https://github.com/reciprocalreviews/reciprocalapp/issues/42)) Communicate that it is inactive.

## Currency `/currency/[currencyid]`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of this page is to manage the venue's `Currency`.

Basic functionality includes:

- [x] Show the minters
- [x] Show the venues using the currency
- [x] _`minter`_: Create new tokens within the venue's currency, to address token scarcity in the community. This functionality should provide guidance on best practices, including warnings about what happens if they create too many tokens. For example, there should be a certain number of tokens per scholar in the community at a minimum, but not so many that publishing requires no labor.

There are also several functions related to currency exchange and merger:

- [ ] _`scholar`_ ([#34](https://github.com/reciprocalreviews/reciprocalapp/issues/34)): Show any existing exchange rates approved by the platform.
- [ ] _`scholar`_ ([#34](https://github.com/reciprocalreviews/reciprocalapp/issues/34)): View the exchange rates the currency is involved in
- [ ] _`editor`_ ([#34](https://github.com/reciprocalreviews/reciprocalapp/issues/34)): Convert a specific token to another venue's currency. This enables a one-time exchange, such as when an editor might approve someone using currency from another `Venue` to submit to their venue.
- [ ] _`editor`_ ([#34](https://github.com/reciprocalreviews/reciprocalapp/issues/34)): Specify a conversion rate between one venue and another, which enables scholars to independently convert their tokens from one currency to another. This enables an official one way exchange rate, reducing barriers to cross-venue transactions.
- [ ] _`editor`_ ([#34](https://github.com/reciprocalreviews/reciprocalapp/issues/34)): Unify two currencies, removing the need to convert between a currency. Must be approved by the `editors` of both venues. This prevent editors from unilaterally creating changes.
- [ ] _`minter`_ ([#34](https://github.com/reciprocalreviews/reciprocalapp/issues/34)): Propose a new exchange rate for other minters involved in two currencies to approve. Everyone must approve for it to be official. Inactive until all minters involved in both currencies approve.
- [ ] _`minter`_ ([#34](https://github.com/reciprocalreviews/reciprocalapp/issues/34)): Approve a proposed exchange rate.
- [ ] _`minter`_ ([#34](https://github.com/reciprocalreviews/reciprocalapp/issues/34)): Propose a modification to an exchange rate
- [ ] _`minter`_ ([#34](https://github.com/reciprocalreviews/reciprocalapp/issues/34)): Approve a modified exchange rate. Once all have approved, the old exchange between the two is deleted and the new approved one is created.
- [ ] _`minter`_ ([#35](https://github.com/reciprocalreviews/reciprocalapp/issues/35)): Propose a merger of currencies.
- [ ] _`minter`_ ([#35](https://github.com/reciprocalreviews/reciprocalapp/issues/35)): Approve a merger of currencies. Once all have approved, all tokens in the secondary currency are deleted, and replaced with new tokens in the first currency using the current exchange rate, and the exchange is deleted.

## Transactions `/venue/[venueid]/transactions`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of this page is to allow for management of all `Transaction`s associated with a `Venue`.

**FUNCTIONALITY**. The transactions page for a venue should allow for:

- [x] _`editor`_, _`minter`_: View all transactions
- [ ] _`minter`_ ([#43](https://github.com/reciprocalreviews/reciprocalapp/issues/43)): Approve pending transactions that do not involve the scholar approving
- [ ] _`minters`_ ([#44](https://github.com/reciprocalreviews/reciprocalapp/issues/44)): Send email reminders about unfinished transactions and work at a customizable frequency.

## `/venue/[id]/submissions`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of the submissions page is to help scholars see all active submissions in review, and if an editor, manage them.

It should should:

- [x] Show the total number of active submissions in the system.
- [ ] _`editor`_ ([#45](https://github.com/reciprocalreviews/reciprocalapp/issues/45)): Filter submissions by whether they are active, by author, reviewer, etc.
- [x] _`editor`_: Manually add a new submission, including all of the transactions, the manuscript ID specific to the venue, the scholar authors of the submission, and how much each author is contributing. (This is to overcome integration failures, or submisions managed outside of normal reviewing platform flows.)
- [ ] _`editor`_: Submit bulk `Submission`s to the system, allowing more than one at a time
- [ ] _`editor`_: Resolve a specific submission, generating transactions to compensate scholars for their reviewing labor
- [ ] _`editor`_: Resolve bulk submissions, generating transactions for multiple existing submissions
- [ ] _`editor`_ ([#41](https://github.com/reciprocalreviews/reciprocalapp/issues/41)): View transaction templates for each transaction type ot include in email text on other platform's email templates

If the `Venue` is set to be public:

- [x] _`scholar`_: View specific active submissions and the topic and method expertise required (but not submission titles), sorted by submissions most in need of reviews
- [ ] _`scholar`_: Bid on active submissions based on expertise required

## Submission `/venue/[venueid]/submission/[submissionid]`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of a submission page is to allow editors and scholars to see information about the submission. This page will not have any major functionality, unless future versions of RR also support reviewing activity itself. In those future versions, this would be the route where scholars access the submission draft and submit reviews and meta reviews, and discuss the submission to come to a recommendation.

# Notifications

RR will also send periodic reminders based on time-based events:

- [ ] ([#46](https://github.com/reciprocalreviews/reciprocalapp/issues/46)): Send `scholar`s periodic reminders to update their availability

> [!IMPORTANT]
> Emails below are specific to compensation

- [ ] ([#44](https://github.com/reciprocalreviews/reciprocalapp/issues/44)): Send `minters` periodic reminders of unapproved transactions, based on the frequency set in the `Transactions` page

RR will have dedicated email adresses for each venue that, if sent to, will generate events and data that is user facing.

- [ ] When an email is sent to the `Venue`-specific address and proposed `Transaction` meta-data is found, create proposed `Transaction`s corresponding to the transaction meta-data provided. Types of transactions and corresponding metadata include:
  - _Submission_ (manuscript ID, ORCID for each author and amount each author should be deducted).
  - _Review_ (manuscript ID, ORCID for the reviewer)
  - _Meta-review_ (manuscript ID, ORCID for meta-reviewer)
- [ ] When a `Transaction` specified in an email could not be processed — because it lacked metadata, lacked metadata that could be matched to a venue, manuscript, or scholar, or violated a venues requirements — the editor of the venue is notified of the error so they can manually correct it, and potentially any configuration issues with the integration.
- [ ] When a proposed `Transaction` is declined, an email is sent to the person who proposed it with an explanation for why.
- [ ] When `Venue`s become **approved**, send emails to the editor and all people who upvoted the venue, notifying them of their new tokens and the live process.
