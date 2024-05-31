# Design

This document is a design specification for the Reciprocol Reviews (RR) platform. We intend it to specify the conceptual interaction design that people will experience when using the platform and rationale for those choices, as well as aspects of the design that are unresolved. It's primary purpose is to provide contributors with a high level checklist for implementation, but also a long term archive for _why_ it is designed the way it is. This document will _not_ specify low-level design details, like user interface mockups or visual design it; it will stay at the high level interaction flow and user-facing features, describing key pages, functionality, and features.

Since RR is a web application, the document is organized by **data**, detailing key data concepts and their relationships; **routes**, corresponding to areas of the web application and detailing their functionality; and **notifications**, which are types of emails that can be sent by the platform in response to user actions or other events. All other backend details for enabling this user experience should be covered in the [ARCHITECTURE](ARCHITECTURE.md) doc.

## Goal

The overarching and foundational design goals of RR are to 1) ensure that there is sufficient reviewing labor for all publications submitted for peer review in academia, and 2) enhance the ability of editors to find qualified reviewers and secure high quality, on-time reviews. The key design hypothesis is that if we create a **currency** to represent labor, and compensate people with it for their labor, and charge it when they create labor, there will be 1) a better (but likely imperfect) availability of peer review labor, 2) a better ability to incentivize reviewing availability and excellence by withholding tokens from reviewers who do not meet community standards of critique, and 3) partially mitigate publish-or-perish obession with quantity of publications by placing a labor cost on peer review.

We're designing and building RR in order to test this hypothesis, with the hopes that it is supported, and academia adopts it as a way to sustain peer review long term.

## Data

There are several key types of data in RR:

- [ ] **Scholars**, which correspond to individual scholars, identified by [ORCIDs](https://orcid.org/). Scholars can volunteer for **Sources** and can spend and earn **Tokens** for that volunteer work, as well as receive **Token** gifts. Scholars can also have "editor" status on zero or more **Sources**. Scholars can also have "minter" status, which gives them the ability to create new tokens in a source's currency. An individual scholar cannot be both an editor and a minter, as this would allow editors to enrich themselves without oversight.

- [ ] **Currencies**, which represent a particular named type of token, associated with one or more sources.

- [ ] **Tokens**, which are in a **Currency** representing one unit of peer review labor. Tokens are typically spent to compensate others for their reviewing labor. Tokens are typically earned for reviewing labor. There may be many other creative uses for tokens (e.g., gifts, incentives, etc.). Tokens generally should be minted in proportion to scholars, to ensure that there is a balance between labor needed and labor provided. Too few tokens would mean that publishing slows because people cannot find enough of them to submit for peer review. Too many tokens means that quality and timeliness suffers, because everyone has more than enough tokens to publish, and therefore have no incentive to review. Tokens are possessed by individual scholars or in a source's "reserve," and transactions can change who posses them.

- [ ] **Sources**, which are named and curated collections of publications (e.g. journals, conferences) that have their own token costs and rewards for reviewing labor.

- [ ] **Submissions**, which represent a publication undergoing peer review. Depending on the source, scholars may be able to volunteer to review, simplifying editor's ability to find eligible reviewers.

## Routes

The RR web application includes serveral web application routes to represent each of the data types above, and functionality for each.

### Landing `/`

**PURPOSE**. The goal of the landing page is to 1) explain the value proposition of RR to editors, reviewers, and authors and 2) help newcomers orient to the application's key interaction points (how to log in to see their balance and how to find sources of interest for which to volunteer).

The value propositions we want to communicate to editors are:

- [ ] Increased quality and timeliness of reviews
- [ ] Reduced difficulty identifying qualified and available reviewers
- [ ] Reduced submission spam (where spam includes obviously out of scope submissions, some types of fraudulent submissions created by generative AI)

The value proposition we want to communicate to authors are:

- [ ] Faster review turnaround
- [ ] Fairer distribution of peer review labor

**FUNCTIONALITY**. The core functionality of the page is links to other parts of the site, including all routes below, plus a link to the authenticated scholar's page, if authenticated.

### About `/about`

**PURPOSE**. The goal of the about page is to explain who is creating RR, why, how others can get involved in maintaining and evolving it, and how RR is governed and funded. It is primarily content.

### Login `/login`

**PURPOSE**. An ORCID OAuth login page.

**FUNCTIONALITY**

- [ ] Submitting the login form should begin the OAuth login process, a series of redirects. Upon success, it should forward to the **Scholar** page, showing the user their dashboard.

### Scholar `/scholar/[id]`

**PURPOSE**. The goal of the scholar page is to provide a landing page and dashboard for a specific individual scholar.

**FUNCTIONALITY**. It should include:

- [ ] Links to the scholar's ORCID profile
- [ ] Read-only data pulled from the ORCID profile
- [ ] Logout functionality
- [ ] Links to **Sources** the scholar has volunteered to review for
- [ ] Links to **Sources** the scholar is serving as editor of.
- [ ] The ability to specify whether the scholar is available to review based on how many tokens they possess
- [ ] A history of **Token** transactions
- [ ] Scholar-only functionality for gifting tokens to someone else

### Source List `/sources`

**PURPOSE**. This page shows all sources managed on RR.

**FUNCTIONALITY**

- [ ] View all sources
- [ ] (_scholar_). Propose a new source for the platform for review by the platform maintainers.

### Source `/source/[id]`

**PURPOSE**. The source page represents a source and its active **Submissions**.

**FUNCTIONALITY**. The source page should allow for:

- [ ] Display name, description, and URL to the source's website.
- [ ] View the cost and compensation of the source.
- [ ] (_scholar_): Volunteer to review for the source. When they first volunteer, a number of tokens specified by for source should be minted and given to the scholar, welcoming them to the community.
- [ ] (_editor_): Modify the source name, description
- [ ] (_editor_): Modify the newcomer gift in tokens
- [ ] (_editor_): Modify submission costs in tokens, reviewing compensation in tokens. Submission cost must equal to total compensation for a submission.
- [ ] Editor-only functionality to view the total number of tokens in the source and who posses them, to gauge the health of the community.

### Currency `/source/[id]/currency`

**PURPOSE**. This page allows changes to the source's currency.

- [ ] (_minter_): Create new tokens within the source's currency, to address token scarcity in the community. This functionality should provide guidance on best practices, including warnings about what happens if they create too many tokens. For example, there should be a certain number of tokens per scholar in the community at a minimum, but not so many that publishing requires no labor.
- [ ] (_editor_): Convert a specific token to another source's currency. (One time exchange).
- [ ] (_editor_): Specify a conversion rate between one source and another, which enables scholars to independently convert their tokens from one currency to another (official exchange).
- [ ] (_minter_): Unify two currencies, removing the need to convert between a currency. Must be approved by the minters of both sources.

The editor functionality should be as streamlined as possible for data entry, as well as prioritize error prevention.

### `/source/[id]/transactions`

**PURPOSE**. This page is for managing all transactions in a source.

**FUNCTIONALITY**. The transactions page for a source should allow for:

- [ ] (_Editors_, _minters_): View all transactions
- [ ] (_Editors_, _minters_): Search for transactions involving particular people or containing particular text
- [ ] (_Editors_, _minters_): Approve pending transactions that do not involve the scholar approving
- [ ] (_Editors_, _minters_): Cancel approved transactions that do not involve the scholar canceling

### `/source/[id]/submissions`

**PURPOSE**. The submissions page helps scholars see all active submissions in review, and if an editor, manage them.

**FUNCTIONALITY**

- [ ] View the total number of active submissions in the system.
- [ ] (_scholar_): If configured to be public, view specific active submissions and the topic and method expertise required (but not submission titles), sorted by submissions most in need of reviews
- [ ] (_scholar)_: If configured to be public, bid on active submissions based on expertise required
- [ ] When an editor of the source is viewing it, they can also manage submissions, adding new submission records.
- [ ] When an editor is viewing, to "resolve" a specific submission, generating transactions to compensate scholars for their reviewing labor
- [ ] Editor-only functionality to submit individual or bulk **Submissions** to the system to allow for volunteering
- [ ] Editor-only functionality to submit bulk transactions for submissions and reviewing labor
- [ ] Filter submissions by whether they are active, by author, reviewer, etc.

### `/submission`

**PURPOSE**. The submission page allows editors to see information about the submission in isolation from the larger table of submissions.

**FUNCTIONALITY**. This page will not have any major functionality, unless future versions of RR also support reviewing activity itself. In those future versions, this would be the route where scholars access the submission draft and submit reviews and meta reviews, and discuss the submission to come to a recommendation.
