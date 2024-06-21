This document is a design specification for the Reciprocol Reviews (RR) platform. We intend it to specify the conceptual interaction design that people will experience when using the platform and rationale for those choices, as well as aspects of the design that are unresolved. It's primary purpose is to provide contributors with a high level checklist for implementation, but also a long term archive for _why_ it is designed the way it is. This document will _not_ specify low-level design details, like user interface mockups or visual design it; it will stay at the high level interaction flow and user-facing features, describing key pages, functionality, and features.

Since RR is a web application, the document is organized by **data**, detailing key data concepts and their relationships; **routes**, corresponding to areas of the web application and detailing their functionality; and **notifications**, which are types of emails that can be sent by the platform in response to user actions or other events. All other backend details for enabling this user experience should be covered in the [ARCHITECTURE](ARCHITECTURE.md) doc.

# Goal

The overarching and foundational goal of RR is to 1) ensure that there is sufficient reviewing labor for all publications submitted for peer review in academia, and 2) enhance the ability of editors to find qualified reviewers and secure high quality, on-time reviews.

There are two types of functionality that we hope will achieve this goal:

1. Streamlining volunteering for reviewing for publication sources, and making visible reviewer availability to editors
2. Enabling the creation of **currency** to represent labor, and compensate people with it for their reviewing labor, and charge it when they create reviewing labor

Our design hypothesis is that these two core functionalities will result in several value propositions:

1. Easier discovery of reviewers and their availability
2. Improved reviewing availability and review quality by withholding tokens necessary for publishing when reviews do not meet community standards of critique, and
3. A partial mitigation publish-or-perish obession with quantity of publications by placing a labor cost on peer review.

We're designing and building RR in order to test this hypothesis, with the hopes that it is supported, and academia adopts it as a way to sustain peer review long term.

# Legend

We use a few stylistic conventions in this document that have particular meaning:

- `- [ ]` GitHub tasks are used to indicate a design requirement, and whether that requirement is met in the implementation of the platform. Tasks can be followed by a GitHub issue number, corresponding to the issue in this repository representing the work on the feature.
- `- [ ] role` indicates that a particular functionality is only available to scholars with a particular role for a `Source`.
- ` `` ` Backticks are used to represent specific routes in the application or specific concepts in the application. They don't necessarily represent identifiers in code, but rather specific concepts in the application design.

# Data

There are several key types of data in RR.

## Scholars

`Scholars` are individuals in a research community who are identified by an [ORCID](https://orcid.org/).

- [ ] Scholars can volunteer to review for a `Source`
- [ ] Scholars can spend and earn `Token`s for that volunteer work, as well as receive `Token`s as gifts, and spend `Token`s to submit manuscripts for peer review.
- [ ] Scholars can also have _`editor`_ status on a `Source`, which gives them the ability to manage the `transaction`s and `submission`s in a source.
- [ ] Scholars can also have _`minter`_ status, which gives them the ability to create new `Token`s in a `Source`'s `Currency`.
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

## Sources

A `Source` is a named and curated collection of manuscripts undergoing peer review (e.g. a journal or conference).

- [ ] A `Source` has a cost and reward for reviewing labor.
- [ ] `Source`s are associated with `Submission`s, `Token`s, a `Currency`, and `Transaction`s.
- [ ] `Source`s can be proposed, but aren't created until approved.

Here is a SQL sketch, for clarity of both a record of sources, and scholar volunteers for the sources:

```sql
create table sources (
  -- The unique ID of the source
  id uuid not null default uuid_generate_v1() primary key,
  -- The title of the source
  title text not null default '':text,
  -- The description of the source
  description text not null default '':text,
  -- A link to the source's official web page
  url text not null default '':text,
  -- The id of the currency the source is using
  currency uuid not null references currency(id),
  -- Whether the the source permits public bidding on submissions
  bidding boolean not null default true,
  -- One or more scholars who serve as editors of the source
  editors text[] not null default '{}'::text[] check (cardinality(editors) > 0),
  -- One or more scholars who serve as minters for the source
  minters text[] not null default '{}'::text[] check (cardinality(minters) > 0)
);

create table volunteers (
  -- The id of the scholar who volunteered
  scholarid uuid not null references scholars(id) on delete cascade,
  -- The id of the
  sourceid uuid not null references sources(id) on delete cascade
);

-- A table of proposed sources
create table proposed (
  -- The unique ID of the source
  id uuid not null default uuid_generate_v1() primary key,
  -- The title of the source
  title text not null default '':text,
  -- The email addresses of editors responsible for the source
  emails text not null default '':text,
  -- The estimated size of the research community,
  size integer not null
)

```

## Currencies

> [!IMPORTANT]
> The data below is specific to compensation

A `Currency` represents a particular named type of `Token`, associated with one or more `Source`s. We allow for many forms of `Currency`, as opposed to one universal one, as different communties may want to place different costs and compensation on different activities, and those amounts will come to have meaning within each of those communities that do not necessarily transfer directly to other communties without some specific exchange agreement.

Here is a SQL sketch, for clarity:

```sql
create table currencies (
  -- The unique id of the currency
  id uuid not null default uuid_generate_v1() primary key,
  -- The name of the currency
  name text not null default '':text
);
```

## Tokens

> [!IMPORTANT]
> The data below is specific to compensation

A `Token` represents an indivisible unit of peer review labor in a particular `Currency`.

- [ ] `Token`s are typically spent to compensate others for their reviewing labor.
- [ ] Tokens are typically earned for reviewing labor.
- [ ] There may be many other creative uses for them (e.g., gifts, incentives, etc.).
- [ ] `Token`s should generally be minted in proportion to scholars, to ensure that there is a balance between labor needed and labor provided. Too few `Token`s would mean that publishing slows because people cannot find enough of them to submit for peer review. Too many `Token`s means that quality and timeliness suffers, because everyone has more than enough tokens to publish, and therefore have no incentive to review.
- [ ] `Token`s are possessed by individual scholar or in a `Source`'s reserve (meaning they are posessed by no one) and `Transaction`s can change who posses them. They cannot be possessed by neither a scholar or a source.

Here is a SQL sketch, for clarity:

```sql
create table tokens (
  -- The unique ID of the token
  id uuid not null default uuid_generate_v1() primary key,
  -- The currency that the token is in
  currency uuid not null references currencies(id),
  -- The scholar that currently possess the token, or null, representing no one
  scholar uuid references scholars(id),
  -- The source that currently posses the token, or null
  source uuid reference sources(id)
);
```

## Transactions

> [!IMPORTANT]
> The data below is specific to compensation

A `Transaction` represents an exchange of tokens for some purpose, such as submitting something for review, compensation for a review, or a gift.

- [ ] `Transaction`s cannot be deleted; they are a permanent record
- [ ] `Transaction`s are confidential — to preserve reviewing anonymity and gifts — but audible.

Here is a SQL schema sketch, for clarity:

```sql
create table transactions (
  -- The unique ID of the transaction
  id uuid not null default uuid_generate_v1() primary key,
  -- The scholar who gave the tokens
  from_scholar uuid references scholars(id),
  -- The source who gave the tokens
  from_source uuid references sources(id),
  -- Require that there is a from
  constraint check_from check (num_nonnulls(from_scholar, from_source) = 1)
  -- The optional scholar who received the tokens,
  to_scholar uuid references scholars(id),
  -- The optional source that received the tokens,
  to_source uuid references sources(id),
  -- Require that there is a too
  constraint check_to check (num_nonnulls(to_scholar, to_source) = 1)
  -- The number of tokens transacted
  amount integer not null,
  -- The currency the amount is in
  currency uuid not null referencs currencies(id),
  -- The purpose of the transaction
  purpose text not null
);
```

## Submissions

> [!IMPORTANT]
> The data below is specific to compensation

A `Submission` represents a manuscript undergoing peer review.

- [ ] Depending on the source, scholars may be able to bid on submissions, simplifying an editor's ability to find qualified reviewers.
- [ ] `Submission`s can also be linked to previous submissions, to represent revise and resubmit cycles, or resubmissions to other venues.
- [ ] `Submission`s can be added manually by \_`editor`\_s, or RR can be cc'ed on submission notification emails to be added automatically

Here is a SQL schema sketch, for clarity:

```sql
create table submissions (
  -- The unique ID of the submission
  id uuid not null default uuid_generate_v1() primary key,
  -- The source to which the submission corresponds
  source uuid not null references sources(id),
  -- The external identifier of the submission, such as a submission number or manuscript number
  externalid text not null,
  -- An optional title for public bidding,
  title text default null,
  -- An optional description of expertise required for public bidding,
  expertise text default null
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
- [ ] Show links to `Source`s the scholar has volunteered to review for
- [ ] Show links to `Source`s the scholar is serving as _`editor`_ of.

If scholar ID corresponds to the authenticated user, it should also allow the scholar to:

- [ ] _`scholar`_: Logout
- [ ] _`scholar`_: Indicate whether they are available to review (`scholar.available`)
- [ ] _`scholar`_: Explain their reviewing availability (`scholar.status`)
- [ ] _`scholar`_: Allow editing of the scholar's preferred email address. (`scholar.email`)

> [!IMPORTANT]
> The functionality below is specific to compensation

- [ ] _`scholar`_: View a history of `Transaction`s associated with the scholar
- [ ] _`scholar`_: Gift tokens to someone else using the scholar's ORCID or email, creating two transactions that deduct from the scholar and deposit to the other scholar

## Source List `/sources`

The purpose of the source list page is to show all sources managed on RR, or proposed to be managed on RR.

It should:

- [ ] Show all `Source`s, including active and proposed ones.

- [ ] _`scholar`_: Propose a new `Source` for the platform for review by the platform maintainers. `Source` proposals should gather the name of the source, the email addresses of the person or people leading editing of it, and the estimated size of the number of scholars in the community. `Source`s with similar names are retrieved and shown to prevent duplicate source creation. When the proposal is submitted, an email notification is sent to the email addresses listed and RR administrators. A `Source` is created, but not active until approved.

- [ ] _`admin`_: Approve a `Source` for use, indicating who should take the _editor_ and _minter_ roles for the platform, and creating tokens for all scholars in favor of the petition.

## Source `/source/[id]`

The purpose of a `Source` page is to provide information about its compensation, costs, and people in charge.

The page should:

- [ ] Show the name, description, and URL to the source's website.

When a source is in a **proposed** state:

- [ ] View the _`editors`_ and _`minters`_ of the source
- [ ] View the estimated size of the community
- [ ] _`scholar`_: Vote to support adopting RR for the source.

When a source is **approved** state:

- [ ] View the cost and compensation of the source.
- [ ] _`scholar`_: Volunteer to review for the source. When they first volunteer, a number of tokens specified by for source should be minted and given to the scholar, welcoming them to the community.
- [ ] _`editor`_: Modify the source name, description
- [ ] _`editor`_: Change the _`editor`p_(s) of the source, ensuring there is always one
- [ ] _`editor`_: Set the state to inactive

> [!IMPORTANT]
> The functionality below is specific to compensation

- [ ] _`editor`_: Modify the newcomer gift in tokens
- [ ] _`editor`_: Modify submission costs in tokens, reviewing compensation in tokens. Submission cost must equal to total compensation for a submission.
- [ ] _`editor`_: View the total number of tokens in the source and who posses them, to gauge the health of the community.
- [ ] _`editor`_: Change the _`minter`_(s) of the source, ensuring there is always one
- [ ] _`editor`_: Enable or disable (`sources.bidding`), determining whether submissions can be bid on by `scholars`.

When a source is in an _inactive_ state:

- [ ] Communicate that it is inactive.

## Currency `/source/[id]/currency`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of this page is to manage the source's `Currency`.

- [ ] _`scholar`_: Show any existing exchange rates approved by the platform.
- [ ] _`editor`_: Convert a specific token to another source's currency. This enables a one-time exchange, such as when an editor might approve someone using currency from another `Source` to submit to their source.
- [ ] _`editor`_: Specify a conversion rate between one source and another, which enables scholars to independently convert their tokens from one currency to another. This enables an official one way exchange rate, reducing barriers to cross-source transactions.
- [ ] _`editor`_: Unify two currencies, removing the need to convert between a currency. Must be approved by the `editors` of both sources. This prevent editors from unilaterally creating changes.
- [ ] _`minter`_: Create new tokens within the source's currency, to address token scarcity in the community. This functionality should provide guidance on best practices, including warnings about what happens if they create too many tokens. For example, there should be a certain number of tokens per scholar in the community at a minimum, but not so many that publishing requires no labor.

## Transactions `/source/[id]/transactions`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of this page is to allow for management of all `Transaction`s associated with a `Source`.

**FUNCTIONALITY**. The transactions page for a source should allow for:

- [ ] _`editor`_, _`minter`_: View all transactions
- [ ] _`editor`_, _`minter`_: Search for transactions involving particular people or containing particular text
- [ ] _`minter`_: Approve pending transactions that do not involve the scholar approving
- [ ] _`editors`_, _`minters`_: Cancel approved transactions that do not involve the scholar canceling
- [ ] _`minters`_: Change the frequency of email reminders about unapproved transactions to never, daily, or weekly

## `/source/[id]/submissions`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of the submissions page is to help scholars see all active submissions in review, and if an editor, manage them.

It should should:

- [ ] Show the total number of active submissions in the system.
- [ ] _`editor`_: Filter submissions by whether they are active, by author, reviewer, etc.
- [ ] _`editor`_: Manually add a new submission, including all of the transactions, the manuscript ID specific to the source, the scholar authors of the submission, and how much each author is contributing. (This is to overcome integration failures, or submisions managed outside of normal reviewing platform flows.)
- [ ] _`editor`_: Submit bulk `Submission`s to the system, allowing more than one at a time
- [ ] _`editor`_: Resolve a specific submission, generating transactions to compensate scholars for their reviewing labor
- [ ] _`editor`_: Resolve bulk submissions, generating transactions for multiple existing submissions
- [ ] _`editor`_: View RR email addresses to include on review activity emails on other platforms
- [ ] _`editor`_: View transaction templates for each transaction type ot include in email text on other platform's email templates

If the `Source` is set to be public:

- [ ] _`scholar`_: View specific active submissions and the topic and method expertise required (but not submission titles), sorted by submissions most in need of reviews
- [ ] _`scholar`_: Bid on active submissions based on expertise required

## Submission `/source/[id]/submission`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of a submission page is to allow editors and scholars to see information about the submission. This page will not have any major functionality, unless future versions of RR also support reviewing activity itself. In those future versions, this would be the route where scholars access the submission draft and submit reviews and meta reviews, and discuss the submission to come to a recommendation.

# Notifications

RR will also send periodic reminders based on time-based events:

- [ ] `Source`s are checked daily for a certain proportion of support, and editors are notified when the petition exceeds that threshold.
- [ ] send `scholar`s periodic reminders to update their availability

> [!IMPORTANT]
> Emails below are specific to compensation

- [ ] Send `minters` periodic reminders of unapproved transactions, based on the frequency set in the `Transactions` page

RR will have dedicated email adresses for each source that, if sent to, will generate events and data that is user facing.

- [ ] When an email is sent to the `Source`-specific address and proposed `Transaction` meta-data is found, create proposed `Transaction`s corresponding to the transaction meta-data provided. Types of transactions and corresponding metadata include:
  - [ ] _Submission_ (manuscript ID, ORCID for each author, and amount each author should be deducted).
  - [ ] _Review_ (manuscript ID, ORCID for the reviewer)
  - [ ] _Meta-review_ (manuscript ID, ORCID for meta-reviewer)
- [ ] When a `Transaction` specified in an email could not be processed — because it lacked metadata, lacked metadata that could be matched to a source, manuscript, or scholar, or violated a sources requirements — the editor of the source is notified of the error so they can manually correct it, and potentially any configuration issues with the integration.
- [ ] When a proposed `Transaction` is declined, an email is sent to the person who proposed it with an explanation for why.
- [ ] When `Source`s become **approved**, send emails to the editor and all people who upvoted the source, notifying them of their new tokens and the live process.
