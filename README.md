# H&M Customer Lifecycle: When High Churn Doesn't Mean High Revenue Risk

45% of customers churn. Weighted by revenue, only 18% of the value is at risk — the customers walking away are the ones who spend least.

An analysis of customer retention, value, and churn across two years of H&M transactions, asking whether a 45% churn rate was the crisis it looked like, or a headcount number that overstated the money actually at risk. It was the second.

**Verdict: the churn is real. The revenue risk is far smaller than it looks.**

PostgreSQL · SQL (CTEs, Window Functions) · Power BI · DAX

## The question

Churn measured 45% across the customer base. On its own, that number implies serious revenue risk: nearly half the customers gone inside six months — and the natural response is to spend on reducing customer losses.

But a customer count and a revenue number are not the same thing. Losing half your customers only matters as much as those customers were worth. So the question this project answers is the one that decides where retention money should go:

**Nearly half the customers lapse within six months. How much of the revenue goes with them?**

## A note on the data that shaped everything

Two facts drove every method choice here.

First, the price field is **normalised, not currency**. H&M released spend as a relative figure with a maximum near 0.59, not rupees or dollars. So every value figure in this project is a **share of revenue or a relative amount**, never an absolute one. I never state a currency number, because the data does not contain one.

Second, the full dataset is large — 31.8M transactions across 1.36M customers — and I did not analyse all of it. I built a **200,000-customer random sample with full purchase histories** (4.67M transactions) and checked it against the population before using it (see Judgment calls). Working on a validated sample rather than the full data was a deliberate choice, and the percentages generalise because the sample was checked, not assumed.

<!-- VISUAL SLOT: overview dashboard page here (the paradox headline + lifecycle hero). Add a second image of the value×churn combo chart so the 74%→6.4% decline is visible. Save to /assets and reference as ![Dashboard](assets/overview.png). To be added in final pass. -->

## The data

**Source:** H&M Personalized Fashion Recommendations dataset (Kaggle), linked, not committed.

**Full scale:** 31.8M transactions, 1.36M customers, 104K articles, September 2018 to September 2020.

**Working set:** a validated 200,000-customer random sample with complete histories — 4.67M transactions — loaded into PostgreSQL.

**One property that matters:** spend is normalised (relative units), so all value figures are shares or relative amounts, never currency.

## Approach

Built as a staged SQL pipeline in PostgreSQL.

I started with a **customer spine** — one row per customer, holding their first and last purchase, order count, item count, and total spend. Every later figure traces back to this clean base.

From there the analysis ran in four lifecycle models, each answering a different question:

- **Cohort retention** — 25 monthly cohorts tracked across their lifetimes, to see how fast and how far customers drop off.
- **Churn** — defined on a threshold taken from the data, then rounded to a six-month window for a clean business read (see Judgment calls). Measured overall, and cut by membership status and age.
- **CLV (customer value)** — customers split into spend deciles to measure how concentrated revenue is.
- **RFM segmentation** — an adapted Recency × Monetary model that separates the base into actionable segments.

Techniques throughout: CTEs, window functions (`NTILE`, `LAG`, `ROW_NUMBER`) for deciling and repurchase-gap analysis, and a reconciliation step at each stage. Findings were then built into a 4-page Power BI dashboard with DAX measures, for a business audience.

## The finding that changes the story

On the surface, 45% churn looks like a business losing half its value. It isn't.

When customers are split into spend deciles and churn is measured within each, the number moves enormously: **churn falls from 74% in the lowest spend decile to 6.4% in the highest.** The customers most likely to leave are the ones who spend least. The customers who generate the revenue barely move.

So the 45% headline counts people, not money. Weighting each decile's churn by the revenue it carries gives the number that actually matters: **17.9% of revenue is at risk, against 45% of customers.** Most of the churn sits among customers who were contributing very little to begin with.

That changes where retention spend should go — from *reduce customer losses* to *protect revenue at risk* — and those point at different customers.

## Supporting findings

**Revenue is highly concentrated.** The top 10% of customers by spend generate 51% of all revenue; the top 20% generate about 70%. The bottom half of customers account for under 8%. Value is carried by a small, loyal group.

**One-time buyers are a third of the base and almost none of the money.** 32.9% of customers bought exactly once. As a group they contribute under 5% of revenue — a large headcount problem and a small revenue one.

**Retention drops fast, then holds.** Across 2019 cohorts, first-month retention settles near 16%, then flattens and holds near 13% for the customers who stay. Most of the loss happens immediately; what remains is a small, durable loyal core — the same group that carries the revenue.

**The one segment worth acting on.** Combining value and churn surfaces the actionable target: the **At-Risk segment — 10,755 customers, 10.8% of revenue, churning at 66%.** Valuable enough to matter, and leaving fast enough to lose. That is a far smaller and more specific target than "the 45%."

## Judgment calls

The findings above are only as trustworthy as the choices behind them. This section explains the ones that mattered, including where I chose not to do something, or chose not to overclaim.

### Why I validated a sample instead of using the full data

The full dataset is 1.36M customers. I did not need all of it to answer the question, and working the full set would have slowed every iteration for no analytical gain — *if* a sample could be trusted. So the choice wasn't "sample because it's easier," it was "sample, then check the sample is safe."

I drew a 200,000-customer random sample with complete purchase histories, then compared it to the population on the properties that mattered before using it. The repeat-purchase rate matched almost exactly (67.1% in both). The opening-cohort share matched (10.2% sample versus 10.3% population). Because the sample reproduced the population's key proportions, the percentages in this project generalise. Checking representativeness first is what makes the sample trustworthy.

### Why the churn threshold is derived, not assumed

"Churned" has no natural definition in transaction data — a customer hasn't told you they've left, they've just stopped buying. The usual move is to pick a round number, 90 or 180 days, and call inactivity beyond it churn. But a threshold chosen by habit isn't evidence.

So I took it from the data. I measured the gap between consecutive purchases for repeat customers using `LAG`, and built the distribution of those gaps: the median gap was 22 days, the 90th percentile 124, the **95th percentile 188**, the 99th 364. A customer who has gone past the 95th percentile of normal repurchase behaviour has behaved abnormally — that's a defensible line for "likely gone." I rounded 188 to a **180-day window** for a clean six-month business read, and reported the **90-day figure (61.5%) alongside the 180-day one (45.5%) as a sensitivity**, because the number depends on the choice and hiding that would be dishonest. So the window came from the data, not from habit.

### Why RFM became Recency × Monetary, and why one-timers were split out

Standard RFM scores customers on Recency, Frequency, and Monetary value in a 5×5×5 grid. It only works if customers genuinely differ on all three axes.

Frequency didn't support five honest tiers here. With a third of customers buying exactly once, the frequency axis piles up at the bottom and can't be cut into five meaningful bands without inventing distinctions the data doesn't contain. So I built the model on the two axes that carried real information — **Recency and Monetary** — and handled frequency differently: I pulled **one-time buyers out as their own segment** rather than scoring them.

That split wasn't a workaround, it was the right analytical decision, for three reasons. One-timers are a genuinely different business problem — first-purchase conversion, not reactivation. They are large enough to distort any segment they're mixed into. And separating them surfaces a number that matters on its own: how much of the base never came back. They were scored as null rather than zero, so they self-exclude from segment averages instead of corrupting them.

### Handling censoring at both ends of the window

A cohort's later months can only be observed if enough calendar time has passed. That cuts both ways in this data, and both had to be handled.

**Left-censoring:** the earliest cohorts (September and October 2018) show inflated early retention — 44% and 36% at the opening — because the data starts mid-stream and those cohorts are only visible once already partway through their lifecycle. Read naively, they'd suggest retention was far better in 2018 than 2019. It wasn't; the window was just clipped. Those cohorts are flagged as artefacts, not trends.

**Right-censoring:** the data ends September 2020, so late-2019 cohorts (October, November, December) never get a full 6–12 month observation window — a December 2019 cohort simply has no month-12 to measure. Averaging stabilised retention across all cohorts would mix complete and incomplete windows and understate the floor. So the stabilised figure (~13%) uses **only cohorts with a complete 6–12 month window**, checked explicitly in SQL. The number is built on cohorts that could actually be observed, not on partial ones treated as complete.

### Checking the retention numbers at the source

An early read put first-month retention near 19%. Checking it directly against the cohort table told a different story: that 19% came from a few strong mid-2019 cohorts, not the full year. Across all of 2019 the honest figure is **16%**. The stabilised floor moved the same way, from ~15% to **~13%** once incomplete cohorts were excluded (see censoring, above).

I use the lower, honest numbers throughout. The figure has to hold up when you check it, not just look good in a first summary.

### Why the value–churn link is an association, not a cause

The headline finding — high-value customers churn far less — is real, but it is a **co-movement, not proof that value protects against churn.** Recency drives both: a customer who bought recently looks both high-value (recent spend) and low-churn (recent activity) at once, because the same purchase feeds both measures. So the relationship is written as an association throughout, never as "spending more makes customers loyal." The direction is solid; the causal claim is one the data can't support, so I don't make it.

### The zero-churn segments are a definition, not a finding

In the RFM output, Champions and Loyal show ~0% churn. That looks like a headline until you see why: those segments are *defined* by recent activity, and churn is *defined* by inactivity. A customer can't be both recent-by-definition and inactive-by-definition, so their 0% churn is built into the definition, not discovered in the behaviour. It's flagged as such on the dashboard and excluded from any "these segments don't churn" claim, because the real churn signal lives in At-Risk, One-Timers and Hibernating, where the segment and the flag aren't the same thing.

## What this means for the business

Put together, the analysis describes a business whose revenue is safer than its churn rate suggests, and whose retention money is easy to misdirect.

Nearly half the customers lapse, which sounds like a crisis, but the lapsing customers are overwhelmingly low-value. Meanwhile the revenue sits in a small, loyal group that barely churns at all. So the intuitive move — a broad campaign to reduce the 45% — spends most of its budget on customers who were never worth much.

The leverage is narrower and more specific. Defend the high-value core, which carries the revenue and is already stable. Convert the mid-value deciles, where churn is meaningful and spend is real. And treat the **At-Risk segment (10,755 customers, 10.8% of revenue, 66% churn)** as the priority, because it is the one group that is both valuable and leaving. The headline number says "save everyone." The analysis says "save these."

## Limitations

The honest scope of what this analysis can and can't claim:

- **Values are relative, not currency.** Spend is normalised in the source data, so every value figure is a share or a relative amount. No rupee or dollar figure appears, because none exists in the data.
- **It's a validated sample, not the population.** The sample was checked for representativeness on key proportions, so percentages generalise — but the analysis itself runs on 200k customers, and I state it that way rather than claiming the full 1.36M.
- **The value–churn relationship is an association.** Controlled reasoning on observational data, driven partly by shared recency. Direction is trustworthy; causation is not claimed.
- **Two years is a short window for lifetime value.** CLV here is *observed* value over the window, not a predicted lifetime figure. Predictive CLV modelling would need a longer horizon and methods this project doesn't attempt.
- **Zero-churn segments are definitional.** Champions and Loyal show ~0% churn by construction, not by behaviour, and are excluded from churn conclusions.

## Data quality handling

A lot of the work happened before the analysis proper — making sure the data was clean and the figures were trustworthy.

The customer spine was built to zero core nulls, with every figure reconciled to the transaction base. Metadata nulls (age, membership, news preference) were **kept as "Unknown" rather than dropped** — a choice that paid off, since the Unknown-age group turned out to have a distinctly high churn rate (71.3%), a signal a naive cleanup would have thrown away. Grain was handled explicitly: the raw transaction table is one row per article, so an "order" was defined as a distinct customer-and-date pair to avoid inflating order counts. And the retention figures were checked at source and corrected where an early summary had run high (see Judgment calls).

## Repository guide

- **`/sql`** — queries organised by analysis stage (`00_data_prep` through `05_rfm_segmentation`), each with a header noting the question it answers. Reproduces every table the dashboard reads from.
- **`/dashboard`** — the 4-page Power BI file and page screenshots.
- **Data** — the H&M dataset is linked to Kaggle, not committed; only queries, outputs, and screenshots live here.
- Built in PostgreSQL and Power BI.
