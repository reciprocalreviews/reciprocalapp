# Design

This document is a design specification for the Reciprocol Reviews (RR) platform. We intend itto specify the conceptual interaction design that people will experience when using the platform and rationale for those choices, as well as aspects of the design that are unresolved. It's primary purpose is to provide contributors with a high level guide for implementation, but also a long term archive for _why_ it is implemented the way it is. This document will _not_ specify low-level design details, like user interface mockups or visual design it; it will stay at the high level interaction flow, describing key pages and functionality.

Since RR is a web application, the document is organized by **data**, detailing key data concepts and their relationships; **routes**, corresponding to areas of the web application and detailing their functionality; and **notifications**, which are types of emails that can be sent by the platform in response to user actions or other events.

## Goal

The overarching and foundational design goal of RR is to ensure that there is sufficient reviewing labor for all publications submitted for peer review in academia. The key design hypothesis is that if we create a currency to represent labor, and compensate people with it for their labor, and charge it when they create labor, there will be 1) a better (but likely imperfect) availability of peer review labor, 2) the ability to incentivize reviewing excellence by withholding tokens from reviewers who do not meet community standards of critique, and 3) partially mitigate publish-or-perish obession with quantity of publications.

We're designing and building RR in order to test this hypothesis, with the hopes that it is supported, and academia adopts it as a way to sustain peer review, promo

## Data

There are four key types of data in RR:

- **Scholars**, which correspond to individual scholars and ORCIDs. Scholars can volunteer for **Sources** and can spend and earn **Tokens** for that volunteer work, as well as receive **Token** gifts. Scholars can also have "editor" status on zero or more **Sources**.

- **Tokens**, which are a currency representing one unit of peer review labor. Tokens are typically spent to compensate others for their reviewing labor. Tokens are typically earned for reviewing labor. There may be many other creative uses for tokens (e.g., gifts, incentives, etc.).

- **Sources**, which are named and curated collections of publications (e.g. journals, conferences) that have their own token costs and rewards for reviewing labor.

- **Submissions**, which represent a publication undergoing peer review. Depending on the source, scholars may be able to volunteer to review, simplifying editor's ability to find eligible reviewers.

## Routes

The RR web application includes serveral routes to represent each of the data types above, and functionality for each.

### Landing `/`

**PURPOSE**. The goal of the landing page is to explain the value proposition of RR to editors, reviewers, and authors and help newcomers find how to log in

**FUNCTIONALITY**. The core functionality of the page is links to other parts of the site.

### About `/about`

**PURPOSE**. The goal of the about page is to explain who is creating RR, why, how others can get involved in maintaining and evolving it, and how RR is governed and funded. It is primarily content.

### Login `/login`

**PURPOSE**. An ORCID OAuth login page.

**FUNCTIONALITY**. Submitting the form should begin the OAuth login process, a series of redirects. Upon success, it should forward to the **Scholar** page, showing the user their dashboard.

### Scholar `/scholar/[id]`

**PURPOSE**. The goal of the scholar page is to provide a landing page and dashboard for a specific individual scholar.

**FUNCTIONALITY**. It should include:

- Links to the scholar's ORCID profile
- Read-only data pulled from the ORCID profile
- Logout functionality
- Links to **Sources** the scholar has volunteered to review for
- Links to **Sources** the scholar is serving as editor of.
- The ability to specify whether the scholar is available to review based on how many tokens they possess
- A history of **Token** transactions

### `/sources`

**PURPOSE**. This page shows all sources managed on RR.

**FUNCTIONALITY**. In addition to displaying all sources, it allows scholars to propose new sources for the platform.

### `/source/[id]`

**PURPOSE**. The source page represents a source and its active **Submissions**.

**FUNCTIONALITY**. The source page should allow for:

- Display name, description, and URL to the source's website.
- Editor-only functionality to modify the source name, description
- Editor-only functionality to modify submission costs in tokens, reviewing compensation in tokens.

The editor functionality should be as streamlined as possible for data entry, as well as prioritize error prevention.

### `/source/[id]/submissions`

**PURPOSE**. The submissions page helps scholars see all active submissions in review, and if an editor, manage them.

**FUNCTIONALITY**. The submissions page various based on privleges:

- If the source is private, then non-editors receive a private message, with a submission count.
- If the source is public, then everyone can see submissions active submissions by their title and expertise required and volunteer to review for them
- When an editor of the source is viewing it, they can also manage submissions, adding new submission records.
- When an editor is viewing, to "resolve" a specific submission, generating transactions to compensate scholars for their reviewing labor
- Editor-only functionality to submit individual or bulk **Submissions** to the system to allow for volunteering
- Editor-only functionality to submit bulk transactions for submissions and reviewing labor
- Filter submissions by whether they are active, by author, reviewer, etc.

### `/submission`

**PURPOSE**. The submission page allows editors to see information about the submission in isolation from the larger table of submissions.

**FUNCTIONALITY**. This page will not have any major functionality, unless future versions of RR also support reviewing activity itself. In those future versions, this would be the route where scholars access the submission draft and submit reviews and meta reviews, and discuss the submission to come to a recommendation.
