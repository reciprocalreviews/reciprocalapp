# Design

_Last revised: 2026-08-16_

This document is a design specification for the Reciprocol Reviews (RR) platform. We intend it to specify the conceptual interaction design that people will experience when using the platform and rationale for those choices, as well as aspects of the design that are unresolved. It's primary purpose is to provide contributors with a high level checklist for implementation, but also a long term archive for _why_ it is designed the way it is. This document will _not_ specify low-level design details, like user interface mockups or visual design it; it will stay at the high level interaction flow and user-facing features, describing key pages, functionality, data, and features.

Since RR is a web application, the document is organized by **data**, detailing key data concepts and their relationships; **routes**, corresponding to areas of the web application and detailing their functionality; and **notifications**, which are types of emails that can be sent by the platform in response to user actions or other events. All other backend details for enabling this user experience should be covered in the [ARCHITECTURE](ARCHITECTURE.md) doc.

## Goal

The overarching and foundational goal of RR is to 1) ensure that there is sufficient reviewing labor for all publications submitted for peer review in academia, and 2) enhance the ability of editors to find qualified reviewers and secure high quality, on-time reviews.

There are two types of functionality that we hope will achieve this goal:

1. Streamlining reviewing volunteering for publication venues, and making reviewer availability visible to editors and program committee members
2. Creating a **currency** to represent reviewing labor, compensating people with it when they reivew, and charging it when they create reviewing labor by submitting research papers for review.

Our design hypothesis is that these two core functionalities will result in several value propositions:

1. Easier discovery of reviewers and their availability for editors
2. Improved reviewer availability by requiring reviewing of sufficient quality to publish, and
3. A partial mitigation publish-or-perish obession with quantity of publications by placing a labor cost on peer review.

We're designing and building RR in order to test this hypothesis, with the hopes that it is supported, and academia adopts it as a way to sustain peer review long term.

## User Stories

There are several specific use cases that we want RR to support. Here we capture those through _user stories_, as well as _scenarios_, both to help the reader understand the user experience we aspire to build and the motivations we are trying to serve. But these also serve as a resource to help verify that our data schema below actually enables those experiences.

> [!NOTE]
> **Payment and compensation are pull-based, not push-based.** RR does not parse inbound email from external reviewing platforms to create transactions automatically. Instead, when a venue uses compensation, the venue's editors paste RR links into their reviewing platform's email templates. Authors are then prompted by their reviewing platform's submission acknowledgement email to follow a link back to RR and explicitly submit payment for their submission. Similarly, reviewers and other compensated volunteer roles are prompted by their reviewing platform's decision and assignment emails to follow a link back to RR to request compensation for their work. This puts the responsibility of payment on the people who want their submission to be reviewed, and the responsibility of compensation on the people who did the reviewing — not on editors or third-party systems to remember and notice when work is done. The scenarios below assume this model wherever payment or compensation is involved.

### An annual conference solicits volunteer reviewers

_As Sam, program co-chair of ACM SIGCSE TS, I want to be able to quickly solicit a large number of volunteer reviewers for this year's review cycle, so that I can ensure every paper submitted gets three reviews._

- Sam logs in to RR and proposes a SIGCSE TS 2025 venue instance
- The RR stewards approve it
- Sam configures the profile for the venue, defining six volunteer roles for three tracks and two different review phases (modeled as separate submission types, with the second-phase type marked as a revision of the first via the submission type's `revision_of` link), and defining ranked preferences of `preferred`, `if necessary`, and `no`.
- Sam gets the URL of the volunteer page and sends an email through various social media platforms, inviting people to review
- One reviewer receives the link, has an account, just indicates `preferred` for the experience report track, up to 4 papers total.
- Another reviewer recieves the link, doesn't have an account, creates one, and then indicates `if necessary` on research, up to 5 papers.
- After volunteering stabilizes, Sam exports a CSV of all of the volunteers, sorts it by track roles, and uses the reviewer expertise and preferences to manually decide which tracks to assign individuals to. He then imports subsets of the spreadsheet into EasyChair to create the reviewer set for each track. He then sends a message to everyone asking them to check their assignment and notify him if they are no longer able to complete their volunteer commitment.

### An annual conference invites program committee members

_As Dana, program chair of ACM PLDI, I want to send out invites to a curated set of expert reviewers to join the program committee and senior program committee, and quickly get information about who agrees, so that I can form the final program committee in preparation for reviewing season._

- Dana logs into RR and proposes a PLDI 2025 venue instance.
- The RR stewards approve it
- Dana adds a description to the venue and defines the two roles, programm committee member and senior program committee member, defining both as `invite only` roles.
- Dana populates the set of invitees into the venue for each role by submitting a list of email addresses
- Dana sends invitation emails to everyone in each role in her mail client.
- Some program committee members receive the invite, create an account if necessary, see the role to which they have been invited, and indicate yes or no.
- After community invites settle, Dana exports the set of reviewers, filters out the list of declines, and imports them into HotCRP as the program committee and senior program committee, and proceeds with the review process.
- Program committee members return occasionally to RR to remind them of where they've volunteered for reviews.

### A journal wants to create a pool of reviewers, but not require reviewing to submit

_As Derek, EiC of IEEE TSE, I want to curate a set of reviewers who are eager to review journal submissions and access information about their expertise, so that Associate Editors can select people to invite for review._

- Derek logs into RR and proposes a TSE venue instance.
- The RR stewards approve it
- Derek adds a description of the venue and sees the default reviewer role.
- Amy updates the TSE website to point to the reviewer volunteer link and adjusts the email templates to include RR's email receiver.
- Community member is looking for reviewing practice and finds the volunteer link, and agrees to volunteer for up to 1 paper at a time.
- The Associate Editor, when trying to find reviewers, scans the list of volunteers, and finds the volunteer, and invites them through the journal's review platform. The journal's invitation email includes a link (provided by RR's transaction templates) that the reviewer follows to acknowledge the assignment in RR, adding the publication record to the reviewer's list.
- After a decision on the submission is made, the journal's decision email includes a link to RR that the reviewer follows to mark the assignment complete, freeing them to review again.

### A journal wants to create a pool of reviewers and use tokens to incentivize reviewing

_As Amy, EiC of ACM TOCE, I want to incentivize reviewers to volunteer by requiring reviewing prior to submitting papers for review, and streamline Associate Editors ability to identify people to review based on their expertise and need for tokens._

- Amy logs into RR and proposes a TOCE venue instance.
- The RR stewards approve it
- Amy adds a description of the venue and sees the default reviewer role and finds it suitable.
- Amy sets the compensation levels to 10 tokens for a review, 10 for an AE recommendation, and 1 for an EiC decision, as well as costs of 40 tokens per submission. She also sets the welcome token rate to 30, enabling newcomers to submit if they review just once.
- Amy updates the ACM TOCE website to point to the reviewer volunteer link and to the compensation costs. She also sends an email to `sigcse-members` to solicit volunteers and points to the link
- Community members either receive the email, or see the volunteer link on the website, and log in to voluneer. Those are first time volunteers receive their newly minted welcome tokens.
- A community member submits a paper through the journal's review platform. The platform's submission acknowledgement email includes a link (provided by RR's transaction templates) that the corresponding author follows back to RR to explicitly create the submission record and propose payment transactions, indicating whose accounts to deduct the 40 tokens from.
- Amy confirms that the paper should not be desk rejected and then approves the proposed transactions and the submission for review, and assigns an Associate Editor.
- The Associate Editor, when trying to find reviewers, scans the list of volunteers, filtering by expertise keywords, paying attention to reviewers paper limits and other commitments, and ultimately sends invites to possible matches through the journal's review platform. The invitation email includes a link to RR that the reviewer follows to acknowledge the assignment, showing that the reviewer has a TOCE assignment.
- After a decision on the submission is made, the journal's decision email includes links to RR that each reviewer, the AE, and the EiC follow to request compensation for their respective work. Amy reviews and approves the resulting proposed transactions in RR.

## Legend

We use a few stylistic conventions in this document that have particular meaning:

- `- [ ]` and `- [x]` are GitHub Flavored Markdown task list items, and we use them to mark design requirements as **pending** (`[ ]`) or **done** (`[x]`). GitHub renders these as actual checkboxes when this document is viewed on github.com. Tasks can be followed by a GitHub issue number, corresponding to the issue in this repository representing the work on the feature.
- `- [ ] role` indicates that a particular functionality is only available to scholars with a particular role for a `Venue`.
- ` `` ` Backticks are used to represent specific routes in the application or specific concepts in the application. They don't necessarily represent identifiers in code, but rather specific concepts in the application design.

## Data

There are several key types of data in RR.

### Scholars

`Scholars` are individuals in a research community who are identified by an [ORCID](https://orcid.org/).

- [x] Scholars can volunteer to review for a `Venue`
- [x] Scholars can spend and earn `Token`s for that volunteer work
- [x] Scholars can receive `Token`s as gifts
- [x] Scholars can spend `Token`s to submit manuscripts for peer review.
- [x] Scholars can also have _`admin`_ status on a `Venue`, which gives them the ability to manage the configuration of the venue `Venue`.
- [x] Scholars can also have _`minter`_ status, which gives them the ability to create new `Token`s in a `Venue`'s `Currency`.
- [x] An individual scholar cannot be both an _`editor`_ and a _`minter`_. However, editors and role approvers can spend a `Venue`'s token reserve directly (without minter approval). This separation prevents anyone with spending authority from also creating new tokens — the minter check is the only oversight on currency supply. Correspondingly, _`minter`_s mint new tokens and approve mints, but cannot move the ownership of existing tokens; reserve payouts are executed by a `Venue`'s editors/admins and priority-0 role holders.
- [x] Scholars can specify a contact email address, verified via a link before RR sends to it (see the Login section and [#27](https://github.com/reciprocalreviews/reciprocalapp/issues/27)). The stored address is always a verified one.
- [x] Anyone can view a `Scholar`'s record, but only `Scholars` can create, update, or delete their record.
- [x] ([#87](https://github.com/reciprocalreviews/reciprocalapp/issues/87)) Identity is ORCID, not email: a scholar is identified by their ORCID iD (the auth identity), and email is only a verified contact address. This removes the email-vs-ORCID identifier ambiguity — email is never an identity key, so a shared or changed email cannot collide with another scholar's record.

The authoritative schema lives in [`supabase/schemas/scholars.sql`](supabase/schemas/scholars.sql).

### Venues

A `Venue` is a named and curated collection of manuscripts undergoing peer review (e.g. a journal or conference).

- [x] A `Venue` has a cost and reward for reviewing labor.
- [x] `Venue`s are associated with `Submission`s, `Token`s, a `Currency`, and `Transaction`s.
- [x] `Venue`s can be proposed, but aren't created until approved.
- [x] `Venue`s can have one or more volunteer roles, which are helpful for distinguishing between different types of volunteering for a venue (e.g., reviewer, reviewer for track A, meta-reviewer for track B)
- [x] When a `Scholar` volunteers for a `Venue`, they do so for a particular role, optionally with an expertise statement and a soft cap on the number of papers they are willing to review for that role.
- [x] Venues can be set to keep reviewer assignments hidden or visible to authors
- [x] Venues have one or more submission types to represent submission categories, and resubmission types
- [x] Venues have compensation rates by submission type, to allow for different levels of compensation for different tasks

The authoritative schemas live in:

- [`supabase/schemas/venues.sql`](supabase/schemas/venues.sql)
- [`supabase/schemas/proposals.sql`](supabase/schemas/proposals.sql)
- [`supabase/schemas/supporters.sql`](supabase/schemas/supporters.sql)
- [`supabase/schemas/submission_types.sql`](supabase/schemas/submission_types.sql)
- [`supabase/schemas/compensation.sql`](supabase/schemas/compensation.sql)

### Roles and volunteers

- [x] _`scholar`_ ([#122](https://github.com/reciprocalreviews/reciprocalapp/issues/122)): When bidding on a submission, the scholar selects from venue-defined preference levels (e.g. "Preferred" / "If necessary"). Editors see the chosen label on each bid and bids are sorted by preference rank. Venues with no levels defined fall back to the legacy binary bid.

The authoritative schemas live in:

- [`supabase/schemas/roles.sql`](supabase/schemas/roles.sql)
- [`supabase/schemas/volunteers.sql`](supabase/schemas/volunteers.sql)

### Currencies

> [!IMPORTANT]
> The data below is specific to compensation

A `Currency` represents a particular named type of peer review labor `Token`, associated with one or more `Venue`s. We allow for many forms of `Currency`, as opposed to one universal one, as different communties may want to place different costs and compensation on different activities, and those amounts will come to have meaning within each of those communities that do not necessarily transfer directly to other communties without some specific exchange agreement.

The authoritative schemas live in:

- [`supabase/schemas/currencies.sql`](supabase/schemas/currencies.sql)
- [`supabase/schemas/exchanges.sql`](supabase/schemas/exchanges.sql)

### Tokens

> [!IMPORTANT]
> The data below is specific to compensation

A `Token` represents an indivisible unit of peer review labor in a particular `Currency`.

- [x] `Token`s are typically spent to compensate others for their reviewing labor.
- [x] `Token`s are typically earned for reviewing labor, but there may be many other creative uses for them (e.g., gifts, incentives, etc.).
- [x] `Token`s should generally be minted in proportion to scholars, to ensure that there is a balance between labor needed and labor provided. Too few `Token`s would mean that publishing slows because people cannot find enough of them to submit for peer review. Too many `Token`s means that quality and timeliness suffers, because everyone has more than enough tokens to publish, and therefore have no incentive to review.
- [x] `Token`s are possessed by individual scholar or in a `Venue`'s reserve (meaning they are posessed by no one) and `Transaction`s can change who posses them. They cannot be possessed by neither a scholar or a venue.
- [x] **Only a `Transaction` can change who possesses a `Token`.** This is enforced by the database, not by convention: direct writes to tokens are revoked, so every movement of value necessarily leaves a record of why it moved and who authorized it.
- [x] **Every change of possession is recorded permanently.** The platform can account for where any token has been, and can reconstruct who held what at any past moment — so a bug that miscounted balances can be found and repaired precisely, rather than by discarding everything that happened since. That history is deliberately _not_ visible to scholars: knowing which tokens moved when would reveal reviewing activity that a venue's anonymity settings exist to protect.

The authoritative schema lives in [`supabase/schemas/tokens.sql`](supabase/schemas/tokens.sql).

### Data rights

> [!IMPORTANT]
> The data below is specific to compliance with the platform's terms

- [x] A `Scholar` can **download everything** the platform holds about them, as a single file: their profile, volunteering, submissions, assignments, conflicts, transactions, and the history of where their tokens have been.
- [x] A `Scholar` can **erase their account**. Their name, email address, and ORCID iD are permanently removed and they can no longer sign in.
- [x] Erasure does **not** delete their reviewing and payment records, and this is deliberate rather than a limitation. Those records are part of other scholars' histories too — the venue that paid for a review, the co-authors on a submission, the reviewer who received a thank-you note — so they remain, with no name attached to them. The tokens a scholar earned stay valid currency for the venues that issued them, because destroying them would quietly change what those venues hold.
- [x] A steward can act on either request for a scholar who asks out of band, since not everyone who wants their data removed still has an account they can sign into.
- [x] An erasure is remembered, so that recovering the platform from a backup cannot bring someone back who asked to be forgotten.

### Transactions

> [!IMPORTANT]
> The data below is specific to compensation

A `Transaction` represents an exchange of tokens for some purpose, such as submitting something for review, compensation for a review, or a gift.

- [x] `Transaction`s cannot be deleted by anyone — not the giver, not a venue admin, not a currency minter. They are a permanent record.
- [x] `Transaction`s have a definite order that the platform assigns, not one inferred from timestamps. A scholar's history therefore reads the same way every time, and paging through a long list cannot show the same entry twice or skip one — which matters because several transactions are often recorded in the same instant, as when a submission charges each of its authors.
- [x] `Transaction`s are confidential — to preserve reviewing anonymity and gifts — but auditable. They are also immutable once recorded: a proposed transaction may be approved or declined, and **that decision is then final** — an approved transfer cannot later be turned into a refusal, nor a refusal into a transfer. The **amount cannot change after the fact** either, so no one can rewrite how much a completed transfer moved. A caller cannot choose a transaction's identity or backdate it; its place in history is set by the platform, not by whoever proposed it.

The authoritative schema lives in [`supabase/schemas/transactions.sql`](supabase/schemas/transactions.sql).

### Submissions

> [!IMPORTANT]
> The data below is specific to compensation

A `Submission` represents a manuscript undergoing peer review.

- [x] Depending on the venue, `Scholar`s may be able to bid on submissions, simplifying an editor's ability to find qualified reviewers.
- [x] `Submission`s can also be linked to previous submissions, to represent revise and resubmit cycles, or resubmissions to other venues.
- [x] `Submission`s can be added manually by \_`editor`\_s.
- [x] A `Submission` can only be created by one of its listed authors, or by a venue admin adding one manually. Enforced by the database rather than the form, for the same reason as the rules below: without it, any signed-in scholar could create a submission at any venue and propose charges against people who had never heard of it. Every listed author must already have an RR account, since authors are identified by ORCID; a co-author without one is simply left off the record, which means the platform cannot detect conflicts of interest involving them. The submitter is listed as the first author when the form opens, since a submission they aren't an author of would be refused anyway. Co-authors can be found by **name** as well as by ORCID — an author often knows who they wrote a paper with but not their identifier — and naming the same person twice is marked on the offending row rather than only summarized at the foot of the form.
- [x] A `Submission`'s charges must add up to exactly its submission type's cost, and no author may be listed on it twice. Both are enforced by the database, not only by the submission form — a rule that lives only in a form is a rule that holds for people who use the form. Splitting a charge unevenly between co-authors is fine, including charging a co-author nothing; what is refused is a total that doesn't match the price.
- [x] Bids on submissions can be approved by approvers
- [x] Bids on submissions can be approved by roles that are set to be approving roles for another role (e.g., Associate Editors can approve bids from Reviewers)
- [x] A submission's assignments are visible only to the assigned scholar, the role's approver chain (and venue admins), and — when a venue runs open (non-anonymous) review — the submission's authors. Scholars can declare conflicts on submissions; a declared conflict always hides that submission's assignments from the conflicted scholar, including in open review.
- [x] A `Submission` can only be marked **done** once every approved non-editor assignment on it has been compensated, ensuring all levels of review are finished and paid before the submission is considered complete.
- [x] Marking a submission done is the act by which the top-level editor (priority-0 role) self-compensates. It is one action, not two — the editor cannot compensate themselves in isolation, and the submission cannot move to done without that compensation happening.
- [x] **Done is terminal.** A submission marked done cannot be reopened; this preserves the integrity of the completion record and the editor's self-compensation transaction.
- [x] Done submissions remain visible in a venue's submissions list for a venue-configurable window (default 30 days, range 0–365, 7-day steps), sorted to the bottom of the list. After the window expires they're hidden from the list but still reachable by direct link.
- [x] ([#124](https://github.com/reciprocalreviews/reciprocalapp/issues/124)) `Submission`s can reference a previous submission by internal UUID (`submissions.previous`), in addition to the existing external-ID `previousid`, giving revise-and-resubmit chains within RR true referential integrity. When creating a submission, authors pick one of their earlier submissions to the same venue from a dropdown (which fills and locks the external-ID field, and auto-selects the matching revision submission type); the free-text external-ID field remains available for cross-venue or pre-RR ancestors. Because a resubmission is simply its own (revision) submission type, its cost follows from that type — no separate resubmission cost is needed. Bulk imports best-effort resolve their external `previousid` to an on-platform link.

The authoritative schemas live in:

- [`supabase/schemas/submissions.sql`](supabase/schemas/submissions.sql)
- [`supabase/schemas/assignments.sql`](supabase/schemas/assignments.sql)
- [`supabase/schemas/conflicts.sql`](supabase/schemas/conflicts.sql)

## Routes

The RR web application includes serveral web application screens, each corresponding to one of the kinds of data above, and providing access to functionality to manipulate each. We'll list URL routes routes for each to clarify the browsing experience.

- [x] While signed in, the page chrome carries the scholar's **total token balance** across every currency, beside the link to their profile. It counts up or down and flashes briefly when it changes, so earning or spending is visible where it happens rather than only on the profile page a click away. (Reduced-motion preferences drop the animation and update the number outright.)
- [x] Every subsection heading on a page is independently linkable. A small chain-link icon next to each subheading copies a URL fragment to that subsection into the address bar, and following such a link smoothly scrolls the heading into the center of the viewport — making it easy to share a pointer to a specific part of a long, multi-section page.

### Landing `/`

The goal of the landing page is to 1) explain the value proposition of RR to editors, reviewers, and authors and 2) help newcomers orient to the application's key interaction points.

- [x] The page should communicate value propositions to editors:
  - Increased quality and timeliness of reviews
  - Reduced difficulty identifying qualified and available reviewers
  - Reduced submission spam (where spam includes obviously out of scope submissions, some types of fraudulent submissions created by generative AI)
- [x] The page should communicate value propositions to authors:
  - Faster review turnaround
  - Fairer distribution of peer review labor
- [x] The page should links to other parts of the site, including all routes below, plus a link to the authenticated scholar's page, if authenticated, to view their dashboard.

### About `/about`

The purpose of the about page is to give context about the project. It should:

- [x] Explain who is creating RR
- [x] Why RR exists
- [x] How others can get involved in maintaining and evolving it
- [ ] How RR is governed and funded ([#13](https://github.com/reciprocalreviews/reciprocalapp/issues/13))

It also lists the current stewards, and is where stewardship is managed:

- [x] List the current stewards, saying so when there are none rather than showing an empty list.
- [x] _`steward`_: Appoint another scholar as a steward, finding them by name as well as by ORCID iD or email address.
- [x] _`steward`_: Remove another scholar as a steward. A steward may not remove themselves — stepping down is an act another steward performs, so nobody resigns by accident — and the last steward cannot be removed at all, since a platform with no stewards could never appoint one again.

### Contact `/contact`

The purpose of the contact page is to be a **front door**: one place a person who is stuck
knows to go, that reaches a specific set of named people rather than an anonymous support
queue. It should:

- [x] Name the shared steward inbox, `stewards@reciprocal.reviews`, and say what it is for
- [x] List the current stewards by name, linking to their profiles, so the address visibly
      resolves to people who will read the message
- [x] Set expectations: stewards are volunteers, and a reply may take days
- [x] Point elsewhere for things that are not support requests: help articles, community
      discussion, the issue tracker, the newsletter

Design rationale: the alternative shapes were a personal email address, which is warm but
does not scale past one steward and disappears when that person does; and a ticketing
system, which scales but makes the sender feel they are writing to a company. A shared
inbox with the stewards named beside it keeps both properties. A scholar knows _who_ they
are writing to, and any steward can pick it up. It is also a Google Group in collaborative
inbox mode, so stewards can assign and resolve among themselves rather than each holding a
private copy and assuming someone else replied.

The steward list is the same data the about page shows, so there is one authoritative
answer to "who runs this."

It has no functionality beyond loading the steward list.

### Help `/help`

The purpose of the help pages is to answer the questions stewards would otherwise answer by
hand, so the front door is not the only way to get unstuck. It should:

- [x] List articles, most-asked first
- [x] Render each article at `/help/[slug]`
- [x] Point at `/contact` when an article does not answer the question

Articles are Markdown files in this repository rather than a wiki or a vendor's help tool:
they are versioned alongside the code they describe, reviewed in pull requests, and served
from our own domain, and the repository is the only durable storage the project has. Like
the email templates, they are English only for now ([#56](https://github.com/reciprocalreviews/reciprocalapp/issues/56)).

### Login `/login`

The purpose of the login page is to authenticate a person into the application using ORCID OAuth, the exclusive and mandatory sign-in method.

It should:

- [x] ([#19](https://github.com/reciprocalreviews/reciprocalapp/issues/19)): Allow a visitor to initiate and complete an ORCID OAuth authentication, landing them at their `/scholar/[id]` dashboard
- [x] ([#27](https://github.com/reciprocalreviews/reciprocalapp/issues/27)): Because ORCID does not provide an email, prompt a newly signed-in scholar to add a contact email and verify ownership via a link (valid 15 minutes) before RR will send them any notifications. Until an email is verified, a persistent banner warns that no notifications will be sent, and RR sends nothing to an unverified address except the verification email itself. The same verification flow is used to change an email later. The link is delivered **only by email** and is never shown in the interface — a verification the requester could read on screen would confirm nothing about who controls the address. Re-visiting a link within its window is safe and still reports success, so a mail scanner or link preview cannot consume it before the scholar clicks.

### Scholar `/scholar/[scholarid]`

The purpose of the scholar page is to provide a landing page and dashboard for a specific individual scholar, helping them see information about their labor and helping others understand their expertise.

It should:

- [x] Link to the scholar's ORCID profile (`scholars.orcid`), to help visitors get more information about them. RR does not pull or display ORCID profile data such as publications or affiliations; visitors who want that context should follow the link out. Instead, RR gathers and displays the expertise data that is specific to peer review (e.g. per-role expertise statements provided when the scholar volunteers), since that is the information editors need and that ORCID does not provide.
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
- [ ] ([#109](https://github.com/reciprocalreviews/reciprocalapp/issues/109)) Decide whether a scholar's token balance is public, private, or visible only to editors of venues where the scholar holds tokens. Resolution affects every place balances are displayed.

### Venue List `/venues`

The purpose of the venue list page is to show all venues managed on RR, or proposed to be managed on RR.

It should:

- [x] Show all `Venue`s, including active and proposed ones.
- [x] _`scholar`_: Propose a new `Venue` for the platform for review by the platform maintainers. `Venue` proposals should gather the name of the venue, the email addresses of the person or people leading editing of it, and the estimated size of the number of scholars in the community. `Venue`s with similar names are retrieved and shown to prevent duplicate venue creation. When the proposal is submitted, an email notification is sent to the email addresses listed and RR stewards. A `Venue` is created, but not active until approved.
- [x] _`steward`_: Approve a `Venue` for use, indicating who should take the _editor_ and _minter_ roles for the platform, and creating tokens for all scholars in favor of the petition.

### Proposals `/venues/proposal`

The purpose of this page is to allow for the proposal of new pages.

- [x] _`scholar`_: Submit a new venue proposal

### Proposal `/venues/proposal/[proposalid]`

The purpose of this page is to allow people to support proposals and check their status.

- [x] View the details about the proposed venue.
- [x] _`scholar`_ : Support a proposal.

- [x] _`steward`_: Edit a proposal's venue name
- [x] _`steward`_: Edit a proposal's venue census
- [x] _`steward`_: Edit a proposal's venue editors
- [x] _`steward`_: Delete a proposal
- [x] _`steward`_: Approve a proposal

### Venue `/venue/[id]`

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
- [x] _`scholar`_: For non-invite only roles, volunteer to review for the venue in a particular role. When they first volunteer, a number of tokens specified by for venue `welcome_amount` should be minted and given to the scholar, welcoming them to the community. The grant **settles immediately** rather than waiting on a minter's approval: the amount is standing venue policy, granted at most once per scholar, so per-grant approval adds no oversight the `welcome_amount` setting doesn't already provide — while the delay landed precisely on the newcomer who volunteered in order to afford a submission. The confirmation says how many tokens were actually granted, and says nothing about tokens when none were — whether a grant happens depends on the scholar's first-role status, the venue's payment-free setting, and its welcome amount, so the platform reports what it did rather than promising what it might have.
- [x] _`scholar`_: For invite-only roles, the role is shown, but without the ability to volunteer, unless the scholar is in the invited list. If they are invited, they can confirm or reject their invite.
- [x] _`scholar`_: Change expertise keywords for a role for the venue
- [x] _`scholar`_: Change paper count for a role for the venue

- [x] _`editor`_: Modify the venue name, description
- [x] _`editor`_: Change the _`editor`_(s) of the venue, ensuring there is always one
- [x] _`editor`_: Set the state to inactive

- [x] _`editor`_: Export the list of reviewers as a CSV file for use on other plaforms, including ORCID, name, email, expertise, role, papers cap, and active status.
- [x] _`editor`_ ([#122](https://github.com/reciprocalreviews/reciprocalapp/issues/122)): Define ordered, custom-labeled preference levels for the venue (e.g. "Preferred" / "If necessary") that bidders pick from when expressing interest. Optional — leaving them empty falls back to a binary bid.
- [x] _`editor`_: Create roles for the venue.
- [x] _`editor`_: Edit the descriptions of roles.
- [x] _`editor`_: Delete a role, confirming they understand that all volunteers will be removed from the role.
- [x] _`editor`_ ([#32](https://github.com/reciprocalreviews/reciprocalapp/issues/32)): Invite one or more `Scholar`s by ORCID to a particular role.
- [x] _`editor`_: Invite one or more `Scholar`s by email to a particular role.
- [x] _`editor`_: Gift tokens from the venue to a scholar
- [x] _`editor`_ ([#123](https://github.com/reciprocalreviews/reciprocalapp/issues/123)): Mark the venue as payment-free, hiding all token, transaction, cost, compensation, and currency UI for the venue. This is choosable when proposing the venue (skipping the currency and minter requirement) and toggleable later in venue settings. A payment-free venue still keeps a hidden currency to satisfy the data model — minted by the approving steward — but never mints or charges. This supports communities like scenario 3 (TSE) that want a reviewer pool without requiring tokens to submit.

> [!IMPORTANT]
> The functionality below is specific to compensation

- [x] _`editor`_: Modify the newcomer gift in tokens
- [x] _`editor`_: Modify submission costs in tokens, reviewing compensation in tokens. Submission cost is set **per submission type** (each type is a different amount of work, e.g. a resubmission type may cost less than a fresh submission), and must equal the total compensation for a submission of that type.
- [x] _`editor`_: View the total number of tokens in the venue and who posses them, to gauge the health of the community.
- [ ] _`editor`_ ([#93](https://github.com/reciprocalreviews/reciprocalapp/issues/93)): On the volunteers list, show each volunteer's current token balance in the venue's currency, so editors can see at a glance who is undercompensated and prioritize assignments accordingly. (The ordering half of this is done: bids and assignees are listed **lowest balance first**, so the scholars most in need of paid reviewing work surface at the top of every candidate list. The volunteers-list balance column remains.)
- [x] _`editor`_: Change the _`minter`_(s) of the venue, ensuring there is always one
- [x] _`editor`_: Enable or disable (`venues.bidding`), determining whether submissions can be bid on by `scholars`.

When a venue is in an _inactive_ state:

- [x] ([#42](https://github.com/reciprocalreviews/reciprocalapp/issues/42)) Communicate that it is inactive.

### Currency `/currency/[currencyid]`

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

### Transactions `/venue/[venueid]/transactions`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of this page is to allow for management of all `Transaction`s associated with a `Venue`.

**FUNCTIONALITY**. The transactions page for a venue should allow for:

- [x] _`editor`_, _`minter`_: View all transactions
- [x] _`minter`_: Approve pending transactions, subject to the no-self-enrichment principle: an approver cannot approve a transaction that enriches them. Approval asks for confirmation before it commits, because it is the least reversible action in the platform — it moves tokens and the decision is final, while declining (which changes nothing about who holds what) can always be followed by a fresh proposal. They can freely approve transactions that spend their own balance (whatever the recipient), but they cannot approve transactions that move someone else's tokens — venue reserves, mints, or another scholar's balance — to themselves or to a venue they administer.
- [x] _`minters`_: Send email reminders about unfinished transactions and work at a customizable frequency.
- [x] _`scholar`_: Transfer tokens from the venue to a scholar directly (no minter approval required) when authorizing a payout the approver has the authority to grant, such as completing a reviewer's assignment. The transfer fails if the venue's reserve is short; in that case a proposed mint transaction sized at the shortfall is recorded automatically, the venue's _`minter`_(s) are notified by email, and the approver can retry once the minter approves. Role approvers can also see the transactions they themselves created, so they can audit their own activity.

### `/venue/[id]/submissions`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of the submissions page is to help scholars see all active submissions in review, and if an editor, manage them.

It should should:

- [x] Show the total number of active submissions in the system.
- [x] _`editor`_: Filter submissions by whether they are active, by author, reviewer, etc.
- [x] _`editor`_: Manually add a new submission, including all of the transactions, the manuscript ID specific to the venue, the scholar authors of the submission, and how much each author is contributing. (This is to overcome integration failures, or submisions managed outside of normal reviewing platform flows.)
- [x] _`editor`_: Resolve a specific submission, generating transactions to compensate scholars for their reviewing labor
- [x] _`editor`_: Submit bulk `Submission`s to the system, allowing more than one at a time
- [x] _`editor`_: Assign one scholar across several submissions from the list itself. The role and the scholar are chosen once, then an assign button appears on each submission the editor can approve that role for, and the button is hidden wherever that scholar already holds the role. This serves the recurring editorial round — assigning Associate Editors to the month's submissions, and an editor assigning themselves the priority-0 role they will later need in order to mark each submission done — which otherwise meant opening every submission in turn.
- [x] _`editor`_ ([#113](https://github.com/reciprocalreviews/reciprocalapp/issues/113)): View transaction templates for each transaction type to copy into the venue's reviewing platform email templates. These templates contain the RR links that authors and volunteers follow to explicitly submit payment or request compensation, per the pull-based model described in the User Stories section.

If the `Venue` is set to be public:

- [x] _`scholar`_: View specific active submissions and the topic and method expertise required (but not submission titles), sorted by submissions most in need of reviews
- [x] _`scholar`_: Bid on active submissions based on expertise required

### Submission `/venue/[venueid]/submission/[submissionid]`

> [!IMPORTANT]
> All functionality below is specific to compensation

The purpose of a submission page is to allow assigned reviewers and authors to see information about the submission. This page will not have any major functionality, unless future versions of RR also support reviewing activity itself. In those future versions, this would be the route where scholars access the submission draft and submit reviews and meta reviews, and discuss the submission to come to a recommendation.

It should also support assignment decisions:

- [x] _`editor`_ ([#126](https://github.com/reciprocalreviews/reciprocalapp/issues/126)): When approving bids or creating assignments, show each candidate scholar's other current volunteer commitments alongside their token balance — both their active assignment count on this venue against their stated paper-count cap, and their active assignment count across other venues in RR. This implements scenario 4's "paying attention to reviewers paper limits and other commitments" guidance and prevents editors from silently overloading reviewers past the limits they accepted when volunteering.
- [x] _`editor`_: On the submission detail page, each pending bid shows the bidder's chosen preference level and a `used / cap` indicator against their per-role papers cap. Approving a bid that would push the bidder past their cap surfaces a confirmation prompt (soft cap — editors retain discretion).

## Notifications

All emails RR sends — contact-email verification and the transactional and reminder emails below — share one simple branded visual identity so they read as coming from the same platform. Their links point at the environment that sent them, so mail from a test deployment leads back to that deployment; the whole model depends on people following links out of email, and links that always led to production made every such flow impossible to rehearse anywhere else. (Sign-in is ORCID, so RR no longer sends authentication emails.) These templates are English only for now: RR has no mechanism yet to solicit a scholar's language preference. ([#56](https://github.com/reciprocalreviews/reciprocalapp/issues/56))

Every email RR sends is **replyable**. Mail is sent from `notifications@reciprocal.reviews`,
but carries `Reply-To: stewards@reciprocal.reviews`, and its footer says so. A notification
is therefore a valid starting point for a conversation: a scholar who does not understand
why they were charged, or an editor with a question about a proposal, can answer the email
they are looking at instead of hunting for a contact address. Without this, every reply to
an RR notification went to an unmonitored mailbox and was lost.

Notifications addressed to the **stewards** as a group (`ProposalCreatedStewards`,
`ReconciliationFailed`) go to that one shared address rather than to each steward's personal
contact email. Stewards still receive the mail individually, because the address is a group
they belong to, but they additionally get a single thread they can assign and resolve, so
it is visible whether anyone has picked a request up. This also means steward notifications
no longer depend on a steward having verified a contact address.

RR will also send periodic reminders based on time-based events:

- [x] ([#46](https://github.com/reciprocalreviews/reciprocalapp/issues/46)): Send `scholar`s periodic reminders to update their availability

> [!IMPORTANT]
> Emails below are specific to compensation

- [x] ([#44](https://github.com/reciprocalreviews/reciprocalapp/issues/44)): Send `minters` periodic reminders of unapproved transactions, based on the frequency set in the `Transactions` page

The same per-venue frequency governs three further reminders, which exist because the pull-based model puts the _first_ notice on a single email that can be missed. A one-shot notice is enough only when nothing depends on it; each of these ends a step of the editorial process, so a missed one stalls a submission indefinitely with no one aware:

- [x] Remind an author of a proposed charge they have not yet approved — typically a co-author's share of a submission cost, which no one else can pay and which may hold up the submission's review.
- [x] Remind the people who can compensate an assignment (venue admins, the submission's priority-0 editors, and the holder of the role's approving role) that a scholar has **requested compensation** for finished work. Only requested work is chased: an approved, uncompensated assignment is normally just a review still in progress, and nagging about those would train approvers to ignore the reminder.
- [x] Remind a submission's priority-0 editors when every non-editor assignment on it has been compensated, so the submission is ready to be marked done — the step that also settles the editors' own compensation, and the one with no other prompt to perform it.

RR will also send transactional emails in response to user actions:

- [x] ([#114](https://github.com/reciprocalreviews/reciprocalapp/issues/114)) When a proposed `Transaction` is declined, an email is sent to the person who proposed it with an explanation for why.
- [x] When `Venue`s become **approved**, send emails to the editor and all people who upvoted the venue, notifying them of their new tokens and the live process.
- [x] When a `Submission` is created, email every co-author carrying a non-zero charge that a payment awaits their approval. The submitter's own charge settles as part of creating the submission, so only the others are notified; without this a co-author learned of the charge only by visiting their dashboard, or by the submitter telling them out of band.
- [x] When a role approver completes an assignment and tokens are paid out, email the compensated scholar with the role name and amount paid.
- [x] When a role approver attempts to pay out but the venue's reserve is too small, email the venue's _`minter`_(s) with the shortfall and a link to the venue's transactions page where the auto-recorded proposed mint awaits approval.
- [x] ([#22](https://github.com/reciprocalreviews/reciprocalapp/issues/22)) When an author thanks their reviewers (see below), email the relevant parties: the venue's editors/admins when a note awaits review, the reviewers when a note is shared, and the author if a note is declined (with the reason).

### Thanking reviewers

Authors often have no low-friction way to thank reviewers for their work. RR lets an author of a **done** submission write a single short note of thanks to the people who reviewed it ([#22](https://github.com/reciprocalreviews/reciprocalapp/issues/22)). Because reviewing is normally anonymous — authors generally cannot see or distinguish individual reviewers — the note is addressed to the submission as a whole and delivered to all of its reviewers; the author never learns who they are. To keep the channel about gratitude rather than rebuttal, a venue admin or editor reviews each note before it is shared (a venue setting, on by default, that a venue may turn off), and may decline it with a reason. This is intentionally **text only**: token "tipping" ([#62](https://github.com/reciprocalreviews/reciprocalapp/issues/62)) was considered and set aside, because anonymity makes targeting individual reviewers unreliable and tokens introduce collusion and currency-integrity risks.
