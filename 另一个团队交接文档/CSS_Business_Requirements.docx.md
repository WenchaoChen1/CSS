**Contents**

1\. Purpose and Scope

2\. Business Context and Objectives

3\. Stakeholders and Roles

4\. Business Objects

5\. Current Process (As-Is)

6\. Target Process in CSS (To-Be)

7\. Business Requirements

8\. Business Rules

9\. Constraints and Exclusions

10\. Assumptions and Open Questions

11\. Glossary

Appendix A. Reference Documents

# **1\. Purpose and Scope**

This document consolidates the business requirements for the CSS platform, gathered from client interviews and process workshops. It describes the market participants, the current way of working, the target process, and the requirements the platform must satisfy at the business level.

The document defines what the business needs and why. It does not specify implementation, screen design, or system architecture; those are covered by the functional specification and design artefacts delivered separately.

**In scope:**

* Manufacturer catalogue publication and maintenance

* Product search and manufacturer comparison for restaurants

* Request for Quotation (RFQ), quotation, purchase order and invoice flow

* Pricing, discount tiers and price visibility rules

* Buying group affiliation recording

* Organisational structure and staff assignment

* Reporting, export and notifications

**Out of scope:**

* Payment processing — payments are settled outside CSS

* Buying group financial settlement, commissions and rebates

* Direct manufacturer-to-chain negotiated net pricing (deferred beyond the second phase)

# **2\. Business Context and Objectives**

The equipment and supply (E\&S) market currently works through platforms that host manufacturer catalogues and serve dealers. Restaurants — the end buyers — are outside those platforms. Dealers build quotations manually, send them by email, and settle payment off-platform. Restaurants therefore have limited visibility of which manufacturers make the products they need, and little basis for comparing offers.

**Business objectives**

| Objective | Rationale |
| :---- | :---- |
| Give restaurants visibility of multiple manufacturers and the ability to compare and choose by product, not only by brand | A restaurant searching for a product type should see a list of manufacturers producing comparable items, with specifications and prices |
| Allow restaurants to work directly with their preferred dealers and manufacturers, reducing intermediary cost | Positioning must be handled carefully — see the note below |
| Keep the existing dealer workflow intact while adding restaurants as active users | Dealers remain the commercial counterparty; the platform adds demand rather than displacing them |
| Provide a single place to search, request quotes, compare offers and exchange documents | Stated as the platform’s distinctive advantage over existing industry solutions |

*Positioning note (internal): the objective of reducing intermediary cost is strategic and should not be stated openly in materials shared with buying groups, sales representatives or dealers, as it would provoke resistance from those parties. This paragraph is intended for internal use and should be removed from any externally circulated version of this document.*

# **3\. Stakeholders and Roles**

| Role | Responsibilities and interests |
| :---- | :---- |
| Manufacturer (MFR) | Publishes the digital product catalogue; sets list price and dealer-specific discounts and net prices; confirms purchase orders from dealers; ships to the dealer’s warehouse or drop-ships to the restaurant site; may use manufacturer’s representatives for promotion and auto-quote access. |
| Manufacturer’s representative | Promotes the brand, works with chains and dealers, attends trade shows; has auto-quote access and may prepare quotes for dealers on the factory’s behalf; occasionally sells directly to restaurants (not addressed in CSS). |
| E\&S dealer (vendor) | Accesses manufacturer catalogues; assembles quotation sheets that may mix products from several manufacturers; sees its own net price and adds its markup; issues quotations to restaurants; converts confirmed quotations into purchase orders and invoices; raises purchase orders to manufacturers when stock is insufficient; receives payment; may belong to a buying group. |
| Restaurant owner / buyer | To be added to CSS as an active buyer. Searches by product name, compiles a Request for Quotation covering all required items — up to a full equipment set for a new restaurant — sends it to several dealers, compares offers, confirms the selected one and pays the deposit or full amount. |
| Buying group | Consolidates orders from several dealers, stamps the purchase order and submits it to the manufacturer as a single legal entity; negotiates volume discounts; charges a commission (6% cited as an example) and returns part of it to the dealer as a rebate; issues quarterly statements and holds annual events at which accumulated rebates are paid out. |
| National chain accounts (NAS) | May run their own purchasing department and separate distribution; have auto-quote access and may buy directly. |
| CSS administrator | May load and maintain manufacturer catalogues on their behalf, as is current market practice; maintains reference data such as the buying group list. |

# **4\. Business Objects**

| Object | Description |
| :---- | :---- |
| Digital catalogue | Manufacturer, product, specifications, category, list price, discounts, minimum order quantity, availability by location, stock where applicable |
| Request for Quotation (RFQ) | List of items a restaurant requires, sent to selected dealers |
| Quotation sheet | Dealer’s offer: selected items, manufacturers, prices, item numbers, markup applied |
| Purchase Order (PO) | Issued by the restaurant to the dealer, and by the dealer to the manufacturer |
| Invoice | Issued by the dealer once the purchase order is accepted |
| Payment / deposit | Settled outside the platform; a deposit of 50% is cited as a typical example |
| Buying group statement | Quarterly statement issued by the buying group to the dealer |
| Rebate statement | Partial refund of commission returned to the dealer as a purchasing incentive |

# **5\. Current Process (As-Is)**

1. The manufacturer publishes a digital catalogue; manufacturers are listed alphabetically.

2. Dealers browse the catalogues, select products and build a quotation sheet, mixing items from several manufacturers, working from the manufacturer’s list price.

3. The dealer applies its discount and net price from the manufacturer — internal information, not visible to the restaurant — and adds its markup.

4. The dealer generates the offer and sends it to the restaurant as PDF, Word, Excel or CSV, or prints it.

5. The restaurant confirms the offer by email or by telephone; the dealer amends it where required.

6. Payment is arranged outside the platform: the restaurant pays the deposit or the full amount to the dealer directly.

7. On receipt of payment the dealer raises a purchase order where needed and issues an invoice.

8. If the dealer does not hold the full order in stock, it raises a purchase order to the manufacturer, who confirms it.

9. The manufacturer ships to the dealer’s warehouse or drop-ships directly to the restaurant site.

10. The restaurant receives the goods and the cycle closes.

# **6\. Target Process in CSS (To-Be)**

## **6.1 Main flow**

11. The manufacturer uploads its catalogue by file or API, sets price visibility and nominates the email address for incoming requests.

12. The restaurant registers in CSS and searches by product name or manufacturer brand; the system returns several manufacturers with specifications and prices, filtered by location.

13. The restaurant assembles the required items into a Request for Quotation, which may cover a complete equipment set for a new site.

14. The restaurant sends the RFQ to up to three dealers, including dealers in different territories where a chain works with local suppliers.

15. Dealers receive the RFQ, check stock, add their markup and return quotations.

16. The restaurant compares the quotations and confirms the selected offer; several rounds of negotiation may occur before both parties agree.

17. On confirmation the quotation becomes a purchase order; the dealer requests a deposit where the terms require one; payment is made outside CSS.

18. If the dealer does not hold the goods, a purchase order is raised to the manufacturer, who confirms it or offers a substitute; a substitution is agreed with the restaurant, otherwise the order is amended or cancelled.

19. The manufacturer ships to the dealer’s warehouse or drop-ships to the restaurant; the dealer arranges final delivery where goods pass through its warehouse.

## **6.2 Entry paths for restaurants**

| Path | Description | Trade-off |
| :---- | :---- | :---- |
| Direct order from a dealer | The restaurant finds a local dealer in the dealer catalogue and follows a link to the dealer’s own website to place the order | Fast and convenient for repeat orders; the transaction takes place outside CSS |
| Request through the manufacturer catalogue | The restaurant searches for the product, selects the manufacturer and sends an RFQ to its dealers | Allows offers to be compared; limited to three dealers per request |
| Free-text request (rejected) | The restaurant enters a general requirement such as "40-litre fryer" and CSS broadcasts it to dealers | Rejected: risk of irrelevant offers and of overloading dealers |

# **7\. Business Requirements**

## **7.1 Catalogue management**

| ID | Requirement | Notes |
| :---- | :---- | :---- |
| BR-CAT-01 | Manufacturers shall be able to publish and maintain product catalogues in CSS. |  |
| BR-CAT-02 | Catalogues shall be uploadable by file (CSV, Excel) and through API integration where the manufacturer has its own system. |  |
| BR-CAT-03 | A catalogue entry shall carry name, description, category, specifications, list price, discounts, minimum order quantity, availability locations (city, ZIP) and stock availability where applicable. | Product detail depth in the E\&S sector is high; client supplied reference samples |
| BR-CAT-04 | Manufacturers shall be listed in alphabetical order of manufacturer name. |  |
| BR-CAT-05 | A keyword search bar shall filter the catalogue by company name, product name or category, and city, state or ZIP code. |  |
| BR-CAT-06 | Manufacturer-specific policies such as freight terms and warranties shall be published in the platform alongside the manufacturer’s catalogue products. |  |
| BR-CAT-07 | A manufacturer shall be able to hide or show the retail (list) price for its catalogue by means of a toggle. |  |
| BR-CAT-08 | Manufacturers shall be able to link dealers to products, filtered by city and ZIP code, and record dealer contact details including the email address used for RFQs. |  |
| BR-CAT-09 | Manufacturers shall be able to promote selected dealers to the top of the dealer list as premium dealers. | Paid promotion; dealers and manufacturers may also advertise products |
| BR-CAT-10 | CSS administrators shall be able to load and maintain catalogues on a manufacturer’s behalf. | Reflects current market practice of a master Excel template |
| BR-CAT-11 | Manufacturers shall be able to nominate the email address for incoming orders and to receive alerts about new orders and changes. |  |

## **7.2 Search and discovery**

| ID | Requirement | Notes |
| :---- | :---- | :---- |
| BR-SEA-01 | Restaurants shall be able to register in CSS and search by product name as well as by manufacturer brand. | Search by product, not only by brand, is a core objective |
| BR-SEA-02 | Search results shall list the manufacturers producing comparable products, with specifications and prices, so that offers can be compared. |  |
| BR-SEA-03 | Restaurants shall be able to search dealers by name, brand, city or ZIP code, with sorting by distance, relevance, price and availability. |  |
| BR-SEA-04 | The system shall detect the restaurant’s location automatically and allow it to be changed manually. |  |
| BR-SEA-05 | CSS shall link out to dealers’ own websites where a restaurant chooses to order directly, without duplicating dealer e-commerce functionality. |  |
| BR-SEA-06 | A restaurant shall be able to collect products from different manufacturers into a single basket forming the RFQ. |  |

## **7.3 Request for Quotation**

| ID | Requirement | Notes |
| :---- | :---- | :---- |
| BR-RFQ-01 | A restaurant shall be able to compile a Request for Quotation covering all required items, up to a complete equipment set for a new restaurant. |  |
| BR-RFQ-02 | An RFQ shall be sendable to a maximum of three dealers per request. | Limit set to prevent abuse and dealer overload |
| BR-RFQ-03 | The system shall propose dealers in priority order: dealers holding all items in stock, then dealers with partial availability, then dealers working with the required manufacturers. |  |
| BR-RFQ-04 | The restaurant shall be able to override the proposal and select its preferred dealers manually. | Chains may need dealers in several territories |
| BR-RFQ-05 | Dealers shall be notified of an RFQ by email and within CSS. |  |
| BR-RFQ-06 | An RFQ shall carry the item list, required delivery dates and the restaurant’s contact details. |  |
| BR-RFQ-07 | The system shall throttle RFQ submissions to protect dealers from spam. | Example given: no more than five RFQs per minute |

## **7.4 Quotations**

| ID | Requirement | Notes |
| :---- | :---- | :---- |
| BR-QUO-01 | A dealer shall be able to build a quotation sheet combining products from the catalogues of several manufacturers. |  |
| BR-QUO-02 | A dealer shall be able to apply a markup globally across all its products, item by item, or quote by quote; the markup field shall remain editable at all times. | Explicitly required to stay flexible |
| BR-QUO-03 | The system shall provide a semi-standard quotation template that the quoting party can extend with additional fields, columns, rows and notes. | Client supplied a sample template |
| BR-QUO-04 | A quotation shall be reviewed manually by the selling party, who may amend it before confirming; conversion to a purchase order shall not be automatic. |  |
| BR-QUO-05 | A restaurant shall be able to confirm a quotation or request a price adjustment; the flow shall support several rounds of negotiation. |  |
| BR-QUO-06 | A restaurant shall be able to compare quotations received from different dealers before confirming one. |  |
| BR-QUO-07 | Quotations shall be exportable and sendable as PDF, Word, Excel and CSV, and shall be printable. |  |
| BR-QUO-08 | The quotation and order flow shall support the statuses arising from the negotiation sequence: RFQ issued, quotation sent, confirmed by buyer, purchase order raised, invoiced, shipped. | Nothing is binding until signature and, where required, deposit |

## **7.5 Purchase orders, invoices and fulfilment**

| ID | Requirement | Notes |
| :---- | :---- | :---- |
| BR-ORD-01 | Once a quotation is signed and any required deposit is received, it shall become a purchase order; the purchase order shall then be converted into an invoice by the seller. |  |
| BR-ORD-02 | Where the dealer does not hold the goods in stock, a purchase order to the manufacturer shall be generated. |  |
| BR-ORD-03 | The manufacturer shall be able to confirm a purchase order or propose a substitute product; an accepted substitution shall be agreed with the restaurant, otherwise the order is amended or cancelled. |  |
| BR-ORD-04 | The system shall support two delivery options: shipment to the dealer’s warehouse, and drop shipment directly to the restaurant site. | Drop shipping is used where the dealer holds no warehouse |
| BR-ORD-05 | Delivery terms shall support prepaid and credit terms, and a deposit where the terms require one. | A 50% deposit is cited as a typical example |
| BR-ORD-06 | A single purchase order may contain products from several manufacturers; the split between manufacturers shall be performed on the vendor side. |  |
| BR-ORD-07 | The restaurant shall not see the internal split of an order between manufacturers. |  |
| BR-ORD-08 | Payment shall be settled outside CSS; the platform shall not process payments. | Payment processing is a possible later phase |

## **7.6 Pricing and discounts**

| ID | Requirement | Notes |
| :---- | :---- | :---- |
| BR-PRC-01 | The system shall distinguish list price (the manufacturer’s published reference price) from net price (the price after all discounts are applied). |  |
| BR-PRC-02 | The system shall support multi-level discount tiers, each applied to the already reduced price. | Formula: Net Price \= List Price × (1 − D1) × (1 − D2) × (1 − D3) |
| BR-PRC-03 | Worked example: a list price of $100 with tiers 50/10/5 yields $100 × 0.5 × 0.9 × 0.95 \= $42.75. | To be used as an acceptance example |
| BR-PRC-04 | The system shall allow multipliers to be configured directly, for example 0.45 for the 50/10/10 tier. |  |
| BR-PRC-05 | List prices shall be importable from manufacturers in Excel and CSV format. |  |
| BR-PRC-06 | All price levels shall be recalculated automatically when the list price changes. |  |
| BR-PRC-07 | The system shall support price levels such as retail, wholesale and distributor, each with its own discount settings. |  |
| BR-PRC-08 | Where an item is sold in less than a full case, an additional broken-case uplift shall be applied. |  |
| BR-PRC-09 | The system shall support price rounding rules, for example rounding retail prices to .99. |  |
| BR-PRC-10 | Discounts shall be configurable by product category and by customer. |  |
| BR-PRC-11 | The interface shall display the price hierarchy clearly as List Price → Discounts → Net Price, allow manual entry or correction of prices and discounts, and show the calculation formula for transparency. |  |
| BR-PRC-12 | Discounts granted by manufacturers to dealers shall be held in the manufacturer module in the form list price / discount / resulting price. |  |

## **7.7 Price visibility and confidentiality**

| ID | Requirement | Notes |
| :---- | :---- | :---- |
| BR-CNF-01 | Discounts from a manufacturer to its dealers are confidential and shall not be published in the catalogue. |  |
| BR-CNF-02 | A dealer shall see only its own discount and net price from a manufacturer, and shall not see the discount granted to any other dealer. |  |
| BR-CNF-03 | A manufacturer shall see only its own products and its net price to the dealer, and shall not see the dealer’s markup. |  |
| BR-CNF-04 | Restaurants shall see manufacturer product information together with the list price only; net prices shall not be visible to them. |  |
| BR-CNF-05 | Directly negotiated net prices between manufacturers and large restaurant chains are outside the scope of the second phase. | Deferred by the client |
| BR-CNF-06 | CSS shall not store or process confidential agreements between manufacturers, dealers and buying groups. |  |

## **7.8 Buying groups**

| ID | Requirement | Notes |
| :---- | :---- | :---- |
| BR-BGR-01 | Each dealer or vendor record shall carry a Buying Group field, populated by the vendor from a drop-down list with manual entry available. |  |
| BR-BGR-02 | A list of known buying groups shall be preloaded and shall remain editable. | List to be supplied by the client |
| BR-BGR-03 | A dealer shall be able to be affiliated with more than one buying group. | Rare but possible |
| BR-BGR-04 | Buying Group shall not be created as a separate business entity alongside Vendor and Manufacturer; the information shall be held within the dealer or vendor record. |  |
| BR-BGR-05 | The system shall allow a buying group to be recorded on a quotation, order or invoice by the dealer or vendor. |  |
| BR-BGR-06 | CSS shall record the buying group value but shall not track contracts, commissions, rebates, obligations or payments related to it. |  |
| BR-BGR-07 | Responsibility for the accuracy and currency of buying group data rests with the dealer or vendor; CSS carries no liability for outdated entries or for discounts and rebates missed as a result. |  |

*Context for scale, not a requirement: buying group commission is typically around 6%, of which about half may be returned to the dealer as a rebate; some dealers receive in excess of $1,000,000 in annual rebates. Once the platform reaches critical mass — the client cites roughly 5,000 dealers and 1,000 manufacturers — CSS may consider acting as a virtual buying group, and buying group values could be filled automatically from a reference list.*

## **7.9 Organisational structure and staff assignment**

**Vendor company hierarchy:**

* Chief Executive Officer

  * Commercial Director

  * Operations Manager — responsible for day-to-day operations

    * Store Manager

      * Sales Manager — may be shared across the company or assigned per store

        * Sales representatives

      * Logistics Manager

        * Drivers, packing specialists

**Restaurant company hierarchy (family company):**

* Chief Executive Officer

  * Commercial Director

  * Operations Manager — oversees the restaurants

    * Restaurant Manager

      * Shift Supervisor

    * Head Chef — at the same level as the Restaurant Manager

| ID | Requirement | Notes |
| :---- | :---- | :---- |
| BR-ORG-01 | The system shall reflect the vendor and restaurant organisational hierarchies described above. |  |
| BR-ORG-02 | All positions carrying the title "manager" shall be treated as C-level; sales representatives, shift supervisors, drivers and packing specialists shall not. |  |
| BR-ORG-03 | A sales manager shall be assignable either company-wide or to an individual store. |  |
| BR-ORG-04 | Employees shall be assigned to specific locations — restaurants or stores — through the administration panel. | Delivery page in the admin panel |
| BR-ORG-05 | The system shall assign employees linked to a restaurant, such as drivers, to the corresponding orders automatically. |  |

## **7.10 Reporting and analytics**

| ID | Requirement | Notes |
| :---- | :---- | :---- |
| BR-REP-01 | The system shall provide quotation analytics. | Scope to be agreed with the client |
| BR-REP-02 | The system shall provide reporting for manufacturers, dealers and restaurants. | Treated by the client as a separate topic; an extensive report list is expected |
| BR-REP-03 | Reports shall cover metrics relevant to dealers and manufacturers, such as gross profit and best-selling items. |  |
| BR-REP-04 | Reports shall be exportable, emailable, saveable and printable in PDF, Excel, CSV and Word. |  |

## **7.11 Non-functional requirements**

| ID | Requirement | Notes |
| :---- | :---- | :---- |
| BR-NFR-01 | The system shall support export of data to manufacturers’ ERP systems. |  |
| BR-NFR-02 | Reference data such as the buying group list shall be editable without development work. |  |
| BR-NFR-03 | Access rights shall be segregated by role: dealers, manufacturers and restaurants. | Underpins the confidentiality requirements in section 7.7 |
| BR-NFR-04 | The system shall include anti-spam protection limiting the frequency of requests. |  |
| BR-NFR-05 | The interface shall stay minimal, focused on search and RFQ, and avoid complex forms. |  |

# **8\. Business Rules**

* Restaurants buy from dealers; dealers buy from manufacturers.

* Nothing is committed until the quotation is secured by signature and, where the terms require it, a deposit.

* A quotation is always reviewed manually by the selling party before it is confirmed.

* The final price to the restaurant is set by the dealer, who adds its own margin to the net price.

* Discounts between a manufacturer and a dealer are confidential and visible to that dealer alone.

* Buying group data is recorded but never verified, tracked or settled by CSS.

* Payments are made directly between the parties and never through the platform.

# **9\. Constraints and Exclusions**

| Area | Constraint |
| :---- | :---- |
| Buying groups | CSS does not automate buying group accounting, commission calculation or payment. Only affiliation is recorded. Buying group logic must not be over-engineered; accounting stays with the dealers. |
| Multi-manufacturer orders | A single purchase order may contain products from several manufacturers, but the split is performed on the vendor side and is not exposed to the restaurant. |
| Payments | The platform does not accept or process payments. A competitor is understood to be working on this, but it is not available today. |
| Chain net pricing | Large chains negotiating discounted net prices directly with manufacturers are not addressed in the second phase. |
| Free-text RFQ | Sending unspecified free-text requirements to dealers was considered and rejected. |
| Dealer e-commerce | CSS links to dealer websites rather than reproducing their ordering functionality. |

# **10\. Assumptions and Open Questions**

| Question | Status |
| :---- | :---- |
| Full list of reports required by manufacturers, dealers and restaurants | Client has flagged this as a separate, sizeable topic; list not yet provided |
| Scope and metrics of quotation analytics | Client agreed the capability is needed; details to be discussed |
| Preloaded list of known buying groups | To be supplied by the client |
| Whether buying groups receive copies of purchase orders | Raised during the 13 Aug discussion and subsequently revisited; to be confirmed |
| Substitution approval flow between manufacturer, dealer and restaurant | Outline agreed; detailed rules to be defined in the functional specification |
| Payment processing inside the platform | Out of scope today; to be revisited in a later phase |
| Advertising and premium placement model | Identified as a monetisation option; commercial rules not yet defined |

# **11\. Glossary**

| Term | Definition |
| :---- | :---- |
| CSS | The platform described in this document |
| E\&S | Equipment and Supply — the market sector served by the platform |
| MFR | Manufacturer |
| Dealer / vendor | Equipment and supply dealer selling to restaurants |
| List price | The manufacturer’s published reference price |
| Net price | The price after all applicable discounts have been applied |
| Discount tier | A multi-level discount such as 50/10/5, each level applied to the already reduced price |
| Markup | The margin a dealer adds on top of its net price |
| RFQ | Request for Quotation — a list of items for which a restaurant requests prices |
| PO | Purchase Order |
| Drop shipping | Shipment directly from the manufacturer to the restaurant, bypassing the dealer’s warehouse |
| Buying group | An organisation consolidating dealer volume to negotiate better manufacturer terms in exchange for a commission |
| Rebate | A partial refund of money, often provided as an incentive to purchase a product or service |
| Auto-quote | Quote generation access granted to manufacturer representatives and national accounts |
| NAS | National chain accounts |

# **Appendix A. Reference Documents**

* [Process diagrams: BPMN of the quotation flow](https://drive.google.com/file/d/1UGi3H06sPI3Sbv_88Kw1Kf-YPfirFGd9/view?usp=drive_link)