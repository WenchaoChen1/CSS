# **CSS — Functional Requirements**

Current system behaviour (AS IS)

**Project:** CSS

**Document type:** Functional Requirements Document — AS IS

**Version:** 1.4 (draft for client review)

**Date:** 18 August 2026

**Prepared by:** \[analyst name\]

**Coverage in this version:** Part 1 — Quotation module (vendor to F\&B client). Part 2 — Manufacturer list and manufacturer card. Part 3 — Manufacturer catalog. Part 4 — Admin panel. Part 5 — Authentication and onboarding. Part 6 — Vendor portal. Part 7 — Restaurant portal. Further functional blocks will be added to this document as separate parts.

**Changes in this version:** The restaurant portal has been added as Part 7\. The vendor portal was added as Part 6\. The manufacturer catalog was added as Part 3\. The admin panel moves from Part 3 to Part 4 and authentication from Part 4 to Part 5; their section numbers shift accordingly, while their requirement identifiers — FR-ADM and FR-AUT — are unchanged. Parts 1 and 2 are unchanged.

**Contents**

How to read this document

Coverage and delivery status

Part 1\. Quotation module (vendor to F\&B client)

      1.1 Vendor quotations list

      1.2 Quotation creation by the vendor

      1.3 Quotation page — vendor view

      1.4 Quotation page — client view

      1.5 Quotation preview

      1.6 Sending a quotation from vendor to client

      1.7 Adding products — manufacturer catalog

      1.8 Adding products — vendor catalog

      1.9 Adding a product group from the quotation page

      1.10 Client response and conversion to an order

      1.11 Clarifications on client comments

Part 2\. Manufacturer list and manufacturer card

      2.1 Manufacturer list (MFR Contacts)

      2.2 Manufacturer card — vendor view

      2.3 Manufacturer card — manufacturer view

      2.4 MAFSI region selection

      2.5 Data governance — read-only rules by view

      2.6 Pricing and financial logic

      2.7 Validation and defaults

      2.8 Data model

Part 3\. Manufacturer catalog

      3.1 Purpose and business value

      3.2 Catalog object, versioning and ownership

      3.3 Ingestion methods

      3.4 Import wizard — choosing the import method

      3.5 Import wizard — uploading the file

      3.6 Import wizard — matching column headers

      3.7 Import wizard — adding missing information

      3.8 Validation and error reporting

      3.9 Manual entry

      3.10 Catalog data model

      3.11 Business rules

      3.12 Exception handling

      3.13 Visibility and access control

Part 4\. Admin panel

      4.1 Master database table

      4.2 Subscribers table

      4.3 Behaviour shared by both tables

      4.4 Bulk actions — edit

      4.5 Bulk actions — merge

      4.6 Bulk actions — delete

      4.7 Company card — Information tab

      4.8 Company card — Subscription tab

      4.9 Company card — Licenses and History tabs

      4.10 Adding a new client

      4.11 Bulk import of companies

      4.12 Validation when the company type is changed

Part 5\. Authentication and onboarding

      5.1 Field requirements across the authentication screens

      5.2 Sign up

      5.3 Sign in

      5.4 Password recovery and reset

      5.5 Onboarding — data requirements

      5.6 Onboarding screens

Part 6\. Vendor portal

      6.1 Shell, navigation and universal elements

      6.2 Support widget

      6.3 Store selection

      6.4 Dashboard

      6.5 Chats

      6.6 Orders — list

      6.7 Orders — creating an order

      6.8 Orders — editing billing details

      6.9 Orders — order card

      6.10 Orders — History, Documents and Delivery tabs

      6.11 Products — store products, import and write-off

      6.12 Products — vendor product table and card

      6.13 Products — reports

      6.14 Products — restaurant view

      6.15 Clients — list and import

      6.16 Clients — client profile

      6.17 Invoice numbering

      6.18 Packing slips

      6.19 Invoices

      6.20 Team management

      6.21 Settings

Part 7\. Restaurant portal

      7.1 Dashboard

      7.2 Financial calculation rules

      7.3 Invoice transparency — backorders, comments and discounts

      7.4 Orders — list

      7.5 Orders — creating an order

      7.6 Orders — order card

      7.7 Vendor confirmation of an order

      7.8 Restaurant response to a vendor confirmation

      7.9 Store product upload

      7.10 Monthly statement

Open points

Glossary

# **How to read this document**

This document records how the CSS system behaves today. It is descriptive rather than aspirational: every statement reflects the current agreed behaviour of the product, including known gaps where a decision is still outstanding.

Each functional area is described in the same order:

* Purpose — what the area is for.

* Screen elements — an inventory of the interface controls, their type, permitted values, behaviour and whether they are required.

* Interaction logic — how the screens behave as the user moves through them.

* Functional rules — the calculation, validation and state transition rules the system enforces.

* Edge cases and error handling — assumptions, boundary conditions and error states.

* Acceptance criteria — the statements against which the area can be tested.

**Requirement identifiers**

Every normative statement carries an identifier in the form FR-QUO-NNN, numbered sequentially through this part. Identifiers are stable: they are not renumbered when new parts are added, so they can be referenced in test cases, defect reports and correspondence. Screen element inventories are descriptive and are not numbered.

The "Required" column in the screen element tables uses these values: Required, Optional, Auto (populated by the system), Conditional (depends on another field or state) and N/A.

# **Coverage and delivery status**

This document is delivered in parts. The table below records which functional blocks are included in the current version.

| Functional block | Status | Comment |
| :---- | :---- | :---- |
| Quotation — vendor to F\&B client | Included | Part 1 of this document |
| Manufacturer list and manufacturer card | Included | Part 2 of this document |
| Manufacturer catalog and bulk ingestion | Included | Part 3 of this document |
| Admin panel — master database, subscribers, licensing | Included | Part 4 of this document |
| Vendor portal — dashboard, orders, products, clients, invoices, team, settings | Included | Part 6 of this document |
| Restaurant portal — dashboard, ordering, order confirmation, statements | Included | Part 7 of this document |
| Authentication and onboarding | Included | Part 4 of this document |
| Quotation from manufacturer | To follow | Separate part |
| RFQ to manufacturer | To follow | Separate part |
| RFQ from F\&B client | To follow | Separate part |
| Orders and invoices | To follow | Separate part |

*Part 2 records the manufacturer module as it behaves today. A set of changes to the MFR Contacts table and the manufacturer card was agreed on 28 July 2026 and is specified in a separate change document; where a point in Part 2 is superseded by that change set, it is marked in the open points at the end of this document.*

# **Part 1\. Quotation module (vendor to F\&B client)**

The quotation module covers the full lifecycle of a quotation addressed by a vendor to a Food & Beverage client: creation, product selection from manufacturer and vendor catalogs, pricing, preview and dispatch, and the client’s response, which converts an accepted quotation into an order.

## **1.1 Vendor quotations list**

Provide vendors with a single interface to create, track and manage the lifecycle of quotations addressed to Food & Beverage (F\&B) clients, including automated status transitions and invoice generation.

Design reference: CSS-Dealer, node 38160-139539; CSS-Dealer, node 37767-232851.

**Screen elements**

| Element | Type | Values | Behaviour | Required |
| :---- | :---- | :---- | :---- | :---- |
| Sidebar Navigation | Nav Links | "F\&B Client", "From Manufacturer", "RFQ to MFR", "RFQ from F\&B Client" | Clicking "- F\&B Client" loads the Quotations table. Other links reserved for future scope. | Required |
| \[+ Create new\] Button | Primary Button | N/A | Opens the "Create New Quotation" modal overlay. | Required |
| Local Search | Text Input | Free text | Filters the current quotations list based on input. | Optional |
| Start / End Date | Date Picker | MM/DD/YYYY | Filters table records by the selected date range. | Optional |
| Filter / Print | Icon Button | N/A | Opens advanced filter parameters / Triggers print view. | — |
| Per Page Dropdown | Dropdown | 10 (default), 20, 50, etc. | Adjusts the number of rows displayed per page. | — |
| Pagination Controls | Pagination | \< 1, 2, 3 ... 10 \> | Navigates between the pages of the table results. | — |
| Status Tabs (Vendor View) | Tab Group | "Draft", "Sent to Client", "From MFR", "Accepted", "Over 30 Days" | Re-renders the table to display only records matching the selected status. | Required |
| Status Info (i) Icon | Icon | N/A | Displays a floating tooltip on hover with the business definition of the status. | — |
| Quotation ID | Data Column | Numeric | Displays a unique identifier. | Auto |
| F\&B Client ID | Data Column | Numeric | Displays the client identifier pulled from the system. | Auto |
| Quotation Name | Data Column | Free text | Displays quote name; clicking column header sorts data. | Required |
| F\&B Client | Data Column | Free text | Displays the client name; clicking the column header sorts the data. | Required |
| Total | Data Column | Currency (USD) | Displays total amount (e.g., $876.00); clicking header sorts data. | Required |
| Quotation Date | Data Column | MM/DD/YYYY | Displays creation date; clicking header sorts data. | Required |
| Valid Until | Data Column | MM/DD/YYYY, "—" | Displays expiration date; "—" if Draft or Accepted. Sortable. | Auto |
| Delete (Trash) | Icon Button | N/A | Triggers the deletion process for the specific quotation. | Required |
| \[Open Invoice\] | Button | N/A | Navigates to the generated invoice; only visible in "Accepted" tab. | Conditional |

**Interaction logic**

**Form behaviour**

* Creation form: when a new quotation is drafted, selecting a client automatically populates the F\&B CLIENT ID and F\&B CLIENT fields from the client database.

* Date calculation: on creation or sending, the system calculates VALID UNTIL as exactly 30 days from QUOTATION DATE. The user may override this date manually.

**Modal and dialog logic**

* Create Quotation modal: triggered by the \[+ Create new\] button. It appears as an overlay on the current screen and traps focus until it is submitted or cancelled.

* Delete confirmation (implied): the delete (trash) icon triggers a confirmation dialog to prevent accidental data loss, particularly where the quotation is tied to external processes.

**Navigation and transitions**

* Tab switching: clicking any of the five status tabs filters the data table instantly, without a full page reload.

* Row click: clicking anywhere on a table row, other than the Delete or Open Invoice controls, opens the detailed view of that quotation.

* Invoice navigation: in the "Accepted" tab, \[Open Invoice\] takes the user from the quotations table to the invoice management module for that record.

**Functional rules**

| FR-QUO-001 | The TOTAL column shall always format amounts in USD with two decimal places (for example, $876.00). |
| :---- | :---- |
| **FR-QUO-002** | All system dates (QUOTATION DATE, VALID UNTIL) shall use the US format MM/DD/YYYY. |
| **FR-QUO-003** | Where a quotation is in "Draft" or "Accepted" status, the VALID UNTIL column shall display an em dash ("—"), because the expiry is either not yet active or no longer applicable. |
| **FR-QUO-004** | Quotation lifecycle — Draft: the initial state; the quotation has been created but not sent. |
| **FR-QUO-005** | Quotation lifecycle — Sent to Client: the quotation has been finalised and transmitted; VALID UNTIL becomes active. |
| **FR-QUO-006** | Quotation lifecycle — From MFR: the vendor is awaiting a sub-quotation from a manufacturer. |
| **FR-QUO-007** | Quotation lifecycle — Accepted: the client has approved the quotation. The system shall automatically convert the quotation into an invoice on entering this state. |
| **FR-QUO-008** | Quotation lifecycle — Over 30 Days: if a quotation remains in "Sent to Client" and passes the VALID UNTIL date without being accepted, the system shall change its status to "Over 30 Days" automatically. |

**Edge cases and error handling**

| FR-QUO-009 | ID generation: the system shall generate QUOTATION ID sequentially on creation to prevent duplicates, overriding any manual client input logic in the vendor-side portal. |
| :---- | :---- |
| **FR-QUO-010** | Manual date override: where a vendor sets VALID UNTIL to fewer or more than 30 days, the expiry automation shall trigger on that custom date rather than on a hard-coded 30-day timer. |
| **FR-QUO-011** | Deleting accepted quotations: where a user attempts to delete an "Accepted" quotation, the system shall either disable the delete control or display a severe warning that the linked auto-generated invoice will be orphaned or deleted. |
| **FR-QUO-012** | Empty table states: where a selected status tab returns no records, the table headers shall remain visible and the body shall display the standard empty state message "No quotations found in this status." |
| **FR-QUO-013** | Invoice generation failure: where the system fails to generate an invoice automatically after a quotation is marked "Accepted" — for example, on a server timeout — the status transition shall be rolled back to "Sent to Client" and a red error notification shall be displayed. |
| **FR-QUO-014** | Deletion failure: where a deletion request fails on the backend, the row shall remain visible, the modal shall close and an error message shall be presented. |

**Acceptance criteria**

| FR-QUO-015 | The system shall display a sidebar with a "Quotations" menu expanding to "- F\&B Client", "- From Manufacturer", "- RFQ to MFR" and "- RFQ from F\&B Client". |
| :---- | :---- |
| **FR-QUO-016** | The system shall display a data table for "- F\&B Client" containing the columns Quotation ID, F\&B Client ID, F\&B Client Name, Quotation Name, Total, Quotation Date and Valid Until. |
| **FR-QUO-017** | The system shall allow the table to be sorted by Quotation Name, Client Name, Total, Quotation Date and Valid Until. |
| **FR-QUO-018** | The system shall provide five status tabs above the table: Quotation Draft, Quotation Sent to Client, Quotation From MFR, Accepted and Over 30 Days. |
| **FR-QUO-019** | The system shall filter the table to matching records only when a status tab is selected. |
| **FR-QUO-020** | The system shall display a tooltip with the business definition of a status when the user hovers over the "i" icon beside that status tab. |
| **FR-QUO-021** | The system shall calculate "Valid Until" as 30 days from the Quotation Date on creation, while allowing the vendor to edit it manually. |
| **FR-QUO-022** | The system shall change a quotation’s status to "Over 30 Days" where no client response is recorded by the "Valid Until" date. |
| **FR-QUO-023** | The system shall generate an invoice automatically when a quotation’s status changes to "Accepted". |
| **FR-QUO-024** | The system shall display an "Open Invoice" button on table rows only in the "Accepted" status tab. |
| **FR-QUO-025** | The system shall open the "Create New Quotation" modal overlay when \[+ Create new\] is clicked. |
| **FR-QUO-026** | The system shall open the quotation details view when any part of a table row other than an action button is clicked. |
| **FR-QUO-027** | The system shall allow a quotation to be deleted through the trash icon at the right-hand end of the row. |
| **FR-QUO-028** | The system shall format all currency as USD with two decimals (for example, $0.00) and all dates as MM/DD/YYYY. |

## **1.2 Quotation creation by the vendor**

Allow vendors and manufacturers to create new quotations, either by selecting an existing client from the database or by entering a new client manually, with duplicate detection and validation built in.

Design reference: CSS-Dealer, node 37767-232870.

**Screen elements**

| Element | Type | Values | Behaviour | Required |
| :---- | :---- | :---- | :---- | :---- |
| Modal Close (X) | Icon Button | N/A | Closes the modal without saving; discards input. | Auto |
| New Quotation Name | Text Input | Alphanumeric / Free text | Accepts standard text input for the quotation title. | Required |
| New Quotation Number | Text Input | Numeric / Alphanumeric | Pre-filled based on user's system settings (auto-increment). Manually editable. | Required |
| Client (Dropdown) | Searchable Select | Client Names | Displays alphabetical list. Filters results on typing. Sources from Global Database or Private Database based on user role. | Required (if checkbox OFF) |
| Checkbox: "Client is not in the system" | Checkbox | Checked / Unchecked | Default Unchecked. When Checked, transforms UI to manual entry mode and hides the Select Dropdown. | Optional |
| Client (Text) | Text Input | Free text | Appears only when checkbox is Checked. Replaces the Dropdown. | Required (if checkbox ON) |
| Contact Person | Text Input | Free text | Appears only when checkbox is Checked. | Required (if checkbox ON) |
| Email | Text Input | Standard Email Format | Appears only when checkbox is Checked. Validates against standard email regex (e. g., x@y.z). | Required (if checkbox ON) |
| Country | Dropdown | Country Flags \+ Codes (e.g., 🇺🇸 \+1) | Appears only when checkbox is Checked. Pre-selects default based on locale. | Required (conditional) |
| Cell Phone Number | Text Input | Numeric / Phone Format | Appears only when checkbox is Checked. Applies phone formatting mask based on selected Country Code. | Required (if checkbox ON) |
| Client Address | Text Input | Free text / Address | Appears only when checkbox is Checked. | Required (if checkbox ON) |
| Inline Error Messages | Text Label | Red text (e.g., "Address is already in the system") | Appears below corresponding fields if strict duplicates/validation errors are detected. Highlights field border red. | Auto |
| Discard | Button | N/A | Cancels the operation, clears data, and closes the modal. | Required |
| Create New Quotation / Save | Button | N/A | Submits the form. Disabled if inline validation errors exist. Triggers duplicate check on click. | Required |
| Duplicate Modal: Skip | Button | N/A | Appears on duplicate warning modal. Closes the warning modal, returns the user to the form to correct the data. | Required (in flow) |
| Duplicate Modal: Proceed | Button | N/A | Appears on duplicate warning modal. Overrides the duplicate warning and forces creation of the record. | Required (in flow) |

**Interaction logic**

**Entry points and navigation**

* The user clicks "Create New" from the quotations table, the vendor navigation, the manufacturer’s catalog or their own catalog.

* On successful creation the quotation is generated, the modal closes and the user remains on the page they started from.

**State 1 — existing client (checkbox unchecked)**

* The system opens the "Choose Client" modal (or "Choose Vendor", depending on the user’s role).

* "New Quotation Number" is populated automatically according to the preconfigured numbering rules.

* The user enters the quotation name.

* The user opens the dropdown; the system queries the appropriate database (Global CSS database or private vendor database) and displays an alphabetised list that can be filtered by typing.

* The user clicks "Create New Quotation".

**State 2 — new client (checkbox checked)**

* The user ticks "Client is not in the system".

* The dropdown disappears and five fields appear: Client Name, Contact Person, Email, Cell Phone Number and Address.

* The user completes the required fields; the system applies real-time formatting to the email and phone number.

* The user clicks "Create New Quotation" and the system runs duplicate detection.

**Duplicate warning modal**

* Where the system detects a fuzzy or partial match on name, phone or address, a secondary modal intercepts the submission.

* The modal states the specific conflict, for example "Duplicate phone number \[+1 (123) 456-78\] is found".

* "Skip" closes the warning and returns the user to the form to amend the data.

* "Proceed" bypasses the warning, creates the client record and generates the quotation.

**Functional rules**

| FR-QUO-029 | Where the user is a Vendor, the modal is titled "Choose Client", the dropdown queries the client database, the checkbox reads "Client is not in the system" and the address field is labelled "Client Address". |
| :---- | :---- |
| **FR-QUO-030** | Where the user is a Manufacturer, the modal is titled "Choose Vendor", the dropdown queries the vendor database, the checkbox reads "Vendor is not in the system" and the address field is labelled "Vendor Address". |
| **FR-QUO-031** | The form cannot be submitted until every visible field marked with an asterisk is populated. |
| **FR-QUO-032** | Exact match: where an exact match on name, phone or address exists and violates a strict unique constraint, inline errors are displayed and the submit button is disabled. |
| **FR-QUO-033** | Partial match: where a duplicate is suspected but overrides are permitted, the submit button remains active and clicking it opens the duplicate warning modal. |

**Edge cases and error handling**

| FR-QUO-034 | Database search: searching the dropdown implies an API call. To avoid lag, the search should trigger after two or three characters (debounced) and results should be paginated or limited to the top 50 matches. |
| :---- | :---- |
| **FR-QUO-035** | Numbering conflicts: because the quotation number is editable, the system shall check its uniqueness on submission. |
| **FR-QUO-036** | Checkbox changed mid-entry: where the user completes the manual fields and then unchecks the box, the data shall be preserved in the background so that nothing is lost if the box is checked again. |
| **FR-QUO-037** | Long text: very long names or addresses shall be truncated with an ellipsis in the interface but stored in full in the database. |
| **FR-QUO-038** | Search API failure: where the dropdown cannot fetch clients, the system shall display "Unable to load clients. Please check your connection or create it manually." |
| **FR-QUO-039** | Validation styling: fields in error shall show a red border, a red warning icon inside the input and red helper text directly below the field. |

**Acceptance criteria**

| FR-QUO-040 | The system shall open the "Choose Client" modal when the user clicks "Create New" from any of the four designated entry points. |
| :---- | :---- |
| **FR-QUO-041** | The system shall adapt labels and data sources according to whether the logged-in user is a Vendor or a Manufacturer. |
| **FR-QUO-042** | The system shall populate "New Quotation Number" from the user’s configured settings while allowing manual override. |
| **FR-QUO-043** | The system shall display a searchable, alphabetically sorted dropdown of existing clients by default. |
| **FR-QUO-044** | The system shall display the manual entry fields (Name, Contact Person, Email, Phone, Address) and hide the dropdown when the "not in the system" checkbox is switched on. |
| **FR-QUO-045** | The system shall validate the email format and the phone number format, based on the selected country code, before allowing submission. |
| **FR-QUO-046** | The system shall disable "Create New Quotation" and display inline errors where an exact-duplicate constraint is violated. |
| **FR-QUO-047** | The system shall display the duplicate warning modal where a match on name, phone or address is found on submission. |
| **FR-QUO-048** | The system shall allow the user to force creation of the record by clicking "Proceed" in the duplicate warning modal. |
| **FR-QUO-049** | The system shall close the modal and keep the user on their current page after a quotation is created successfully. |

## **1.3 Quotation page — vendor view**

Give internal users (vendors and sales staff) a single page to view, build and manage quotation data: customer information, segmented product lists with pricing controls, financial summaries, and terms and conditions.

Design reference: CSS-Dealer, node 37767-238327; CSS-Dealer, node 38956-153330.

**Screen elements**

| Element | Type | Values | Behaviour | Required |
| :---- | :---- | :---- | :---- | :---- |
| **Header & Global Actions** |  |  |  |  |
| Quotation ID / Status | Read-only Text | E.g., "Quotation \#70935", "QUOTATION DRAFT" | Displays current record ID and lifecycle state. | Auto |
| View Tabs | Tab Navigation | "Vendor View", "Client View" | Toggles column visibility and UI layout based on the selected perspective. | Required |
| Action Toolbar | Buttons | Convert into invoice, Duplicate, Print, Export, Preview | Triggers the respective system action for the current quotation. | Optional |
| **Quotation Info Section** |  |  |  |  |
| Edit Info Button | Button | "Edit" | Opens a modal or inline form to edit the meta-data of the quotation. | Optional |
| Quotation Meta Fields | Read-only Text | Customer \#, Job \#, PO \#, Invoice \#, Salesperson, Terms, Payment Method, Dates, etc. | Displays populated data. Updates upon saving changes via the Edit button. | Auto |
| From / Ship To Blocks | Data Block | Name, Email, Address, Phone | Displays sender and recipient data. "Edit" buttons trigger edit modals for respective addresses. | Required |
| **Products Section** |  |  |  |  |
| Section Accordion | UI Control | Expand/Collapse | Toggles visibility of the entire Products section. | Optional |
| Group Header | Label | E.g., "VENDOR CATALOG", "MANUFACTURER 1" | Categorises products. Displays the group subtotal at the bottom of each group. | Auto |
| Product Table Columns | Table Headers | Product Model \#, Name, UOM, QTY, Sold QTY, List Price, Discount, Net Price, Markup, Margin, Sell Price, Subtotal | Sortable/Filterable headers for product data. | Auto |
| Info Icon (Product) | Tooltip / Modal Trigger | Icon | On hover/click, displays extended product descriptions / specs. | Optional |
| Quantity / Pricing Inputs | Number Inputs | Numeric values | Inline editable fields (QTY, Discount, Markup). Recalculates row Subtotal on change. | Required |
| Item Comment Icon | Button / Icon | Icon (Red dot if active) | Opens a popover/modal to view or add line-item specific comments. | Optional |
| Delete Item Icon | Button | Trash Icon | Removes the product row from the quotation. Prompts confirmation. | Optional |
| Add Product | Button | "+ Add Product" | Opens catalog modal to select and append items to the specific group. | Optional |
| Add Manufacturer | Button | "+ Add product from new manufacturer / vendor catalog" | Creates a new grouping table for a different manufacturer or vendor catalog. | Optional |
| **Terms & Conditions Section** |  |  |  |  |
| Add Terms Button | Button | "+ Add" | Triggers the "Add Terms & Conditions" modal. | Optional |
| Term Entry | Text Block | Author, Text, Timestamp | Displays added terms or order comments chronologically. | Auto |
| **Add Terms Modal** |  |  |  |  |
| Search Bar | Text Input | Alphanumeric | Filters the list of available standard terms. | Optional |
| Add New Button | Button | "+ Add New" | Opens a form to create a custom term not in the standard list. | Optional |
| Term Checkboxes | Checkbox | Checked / Unchecked | Selects pre-defined terms (Term 1, Term 2, etc.) to append to the quote. | Optional |
| Apply / Cancel | Buttons | Click | Applies selected terms to the main page or dismisses the modal without saving. | Required |
| **Details Section** |  |  |  |  |
| Details Edit Icons | Buttons | Pencil Icon | Enables inline editing for Credit, Freight Fee, and Additional Discount. | Optional |
| Discount Toggles | Toggle | "$", "%" | Switches the discount calculation method between flat amount and percentage. | Required |
| Financial Totals | Read-only Text | Currency (e.g., $2,362.44) | Auto-calculated fields (Tax, Total, Gross Profit) based on line items and fees. | Auto |
| **Footer Section** |  |  |  |  |
| Comment Box | Text Area | Free text | Allows the user to add a general note to the quotation. | Optional |
| Navigation | Buttons | "Back", "Next →" | Saves the current state and navigates to the previous or next step in the workflow. | Required |

**Interaction logic**

**View toggling (vendor vs client)**

* Selecting "Client View" hides the internal columns of the products table — List Price, Net Price, Markup, Margin, Gross Profit — and shows only what the customer is meant to see: Sell Price, QTY and Subtotal.

**Inline editing**

* Clicking an editable field such as QTY or Markup turns the text into an input.

* On blur or on pressing Enter the system recalculates the row’s Net Price, Sell Price and Subtotal, together with the global subtotals, tax, total and gross profit.

**Add Terms & Conditions modal**

* The modal is opened from "+ Add" in the Terms & Conditions section and overlays the screen.

* The user searches the existing terms and stages a selection using the checkboxes.

* "Apply" closes the modal and appends the selected terms to the list on the main page; "Cancel" closes it without changes.

**Discount application**

* In the Details section, the "%" toggle recalculates the discount as a percentage of the pre-discount total.

* The "$" toggle treats the entered number as a flat currency deduction.

**Functional rules**

| FR-QUO-050 | Net Price \= List Price − Discount, where the discount is applied as a flat amount or a percentage. |
| :---- | :---- |
| **FR-QUO-051** | Sell Price \= Net Price \+ Markup, where the markup is applied as a flat amount or a percentage. |
| **FR-QUO-052** | Margin \= (Sell Price − Net Price) / Sell Price, displayed as a percentage. |
| **FR-QUO-053** | Row Subtotal \= Sell Price × QTY. |
| **FR-QUO-054** | Group Subtotal \= the sum of all row subtotals within that manufacturer or catalog block. |
| **FR-QUO-055** | Global Subtotal \= the sum of all group subtotals. |
| **FR-QUO-056** | Total \= Global Subtotal \+ Freight Fee \+ Tax − Credit − Discount − Additional Discount. |
| **FR-QUO-057** | Gross Profit \= Total − the sum of (Net Price × QTY). |
| **FR-QUO-058** | The quotation remains in "QUOTATION DRAFT" until the user clicks "Convert into invoice" or an equivalent finalisation action such as "Send to Client", which locks the pricing fields and updates the status. |

**Edge cases and error handling**

| FR-QUO-059 | The system uses USD as the default currency; multi-currency support is not active in this view. |
| :---- | :---- |
| **FR-QUO-060** | Tax is calculated automatically from the "Ship To" address and the system tax tables, and may be overridden manually where an edit icon is present. |
| **FR-QUO-061** | The logged-in user is assumed to hold vendor or administrator permissions, which grant access to margin and markup data. |
| **FR-QUO-062** | Zero or negative margins: where a discount drops the sell price below the net price the margin becomes negative; the system shall highlight this in red as a warning but shall still allow it, to support loss-leader scenarios. |
| **FR-QUO-063** | Deleting all products: where every product is removed, the totals shall reset to $0.00 and the system shall prevent conversion to an invoice while the total is $0.00 or empty. |
| **FR-QUO-064** | Simultaneous edits: where another user changes the catalog price of an item while this draft is open, the draft shall retain the historical list price captured at creation until it is refreshed manually. |
| **FR-QUO-065** | Where non-numeric characters are entered into a numeric input such as QTY or Markup, the system shall reject the input and revert to the previous valid number. |
| **FR-QUO-066** | Where a required field is cleared in the Edit Quotation Info modal, "Save" shall be disabled and inline validation errors shall be displayed. |

**Acceptance criteria**

| FR-QUO-067 | The system shall display a "Vendor View" tab that reveals the internal pricing columns List Price, Net Price, Markup and Margin. |
| :---- | :---- |
| **FR-QUO-068** | The system shall group products by vendor catalog or by manufacturer and provide a subtotal for each group. |
| **FR-QUO-069** | The system shall recalculate row subtotals, group subtotals, gross profit and the grand total immediately when any quantity, discount or markup field is changed. |
| **FR-QUO-070** | The system shall allow global discounts to be toggled between a flat currency amount and a percentage. |
| **FR-QUO-071** | The system shall provide an "Add Terms & Conditions" modal in which the user can search, select multiple predefined terms by checkbox, or create new terms. |
| **FR-QUO-072** | The system shall display line-item comments and shall mark the comment icon with a red dot where a comment exists for that product row. |
| **FR-QUO-073** | The system shall allow the "From" and "Ship To" addresses to be edited through dedicated edit buttons. |
| **FR-QUO-074** | The system shall prevent conversion to an invoice where the quotation contains no products. |

## **1.4 Quotation page — client view**

Show the vendor exactly what the client will see, and let the vendor control through "Preview Settings" which pricing elements (List Price, Sell Price, Discount) are visible — updating the on-screen table, the preview and the exported or sent document instantly.

Design reference: CSS-Dealer, node 39172-286615; CSS-Dealer, node 38956-153330.

**Screen elements**

| Element | Type | Values | Behaviour | Required |
| :---- | :---- | :---- | :---- | :---- |
| **Top Navigation / Header** |  |  |  |  |
| Quotation Status Badge | Status Label | "QUOTATION DRAFT", "SENT", etc. | Displays current state of the quotation. | Auto |
| View Tabs | Tab Navigation | "Vendor View", "Client View" | Switches between internal vendor view and client-facing view. | Required |
| Action Toolbar | Button Group | "Convert into invoice", "Duplicate", "Print", "Export", "Preview" | Executes document-level actions. "Preview" opens the document as the client will see it. | Optional |
| **Quotation Info Section** |  |  |  |  |
| Quotation Info Block | Data Grid | Customer \#, Job \#, PO \#, Invoice \#, etc. | Displays high-level meta-data. | Auto |
| Info Edit Button | Button | "Edit" | Opens a modal/form to edit quotation metadata. | Optional |
| From / Ship To Cards | Data Card | Company, Email, Address, Phone | Displays sender and recipient details. | Required |
| Addresses Edit Button | Button | "Edit" | Opens a modal/form to edit address / contact details. | Optional |
| **Preview Settings (Price Display)** |  |  |  |  |
| Section Toggle | Accordion Icon | Expanded, Collapsed | Expands or collapses the settings section. | Auto |
| List Price | Checkbox | Checked, Unchecked | Toggles the visibility of the "List Price" column in the Products table. | Optional |
| Sell Price | Checkbox | Checked, Unchecked | Toggles the visibility of the "Sell Price" column in the Products table. | Optional |
| Discount | Checkbox | Checked, Unchecked | Toggles the visibility of the "Discount" column in the Products table. | Optional |
| Without Price | Checkbox | Checked, Unchecked | Hides all price columns. Mutually exclusive with the other three checkboxes. | Optional |
| **Products Section** |  |  |  |  |
| Products Table | Data Grid | Product rows | Displays line items. Columns dynamically show/hide based on Preview Settings. | Required |
| Add Product | Button | "+ Add Product" | Opens a modal/search interface to add new line items. | Optional |
| Row Actions | Icon Buttons | Comment, Delete (Trash) | Allows adding a line-item comment or removing the row. | Optional |
| **Terms & Conditions Section** |  |  |  |  |
| Add Term | Button | "+ Add" | Opens input to append a new term / condition. | Optional |
| Existing Terms | Text Block | Text string, Author, Timestamp | Displays previously added terms. | Auto |
| **Details Section** |  |  |  |  |
| Read-only Totals | Data Field | Quotation ID, Client, Tax, Total | Displays calculated or fixed totals. | Auto |
| Editable Totals | Input Field | Credit, Freight Fee, Additional Discount | Allows inline editing (indicated by pencil icon). | Optional |
| Discount Type Toggle | Toggle Switch | "$", "%" | Switches the discount calculation method between flat amount and percentage. | Required |
| **Comment Section** |  |  |  |  |
| Leave a Comment | Text Area | Free text | Allows the vendor to add a final note to the quotation. | Optional |
| **Footer Actions** |  |  |  |  |
| Back / Next | Buttons | "Back", "Next \-\>" | Navigates through the quotation creation/review wizard. | Required |

**Interaction logic**

**Price display logic — scenario A: "Without Price" selected**

* The system immediately unchecks "List Price", "Sell Price" and "Discount".

* The LIST PRICE, DISCOUNT, SELL PRICE and, where applicable, SUBTOTAL columns disappear from the products table.

**Price display logic — scenario B: pricing columns selected**

* Checking "List Price", "Sell Price" or "Discount" while "Without Price" is active immediately unchecks "Without Price".

* The user may then select any combination of the three pricing checkboxes, and the corresponding columns appear in the products table.

**Preview and delivery**

* "Preview" generates a view — typically a PDF viewer or full-screen modal — that reads the current state of the Preview Settings: with "Without Price" active the document contains no pricing; otherwise only the selected columns are rendered.

* When the quotation is finalised and sent, the payload uses exactly the column visibility defined by these checkboxes.

**Inline editing**

* In the Details section, fields marked with a blue pencil icon — Credit, Freight Fee and Additional Discount — can be edited inline.

* Switching the $ / % toggle on a discount recalculates the Total immediately from the subtotal.

**Functional rules**

| FR-QUO-075 | Mutual exclusivity of price display: the system shall enforce a strict exclusive relationship between the group (List Price, Sell Price, Discount) and the single option (Without Price); they cannot be active at the same time. |
| :---- | :---- |
| **FR-QUO-076** | Downstream inheritance: the Preview Settings selection is not merely a UI filter. It is a configuration that determines the data schema used by the Preview action, the Print action, the Export action and the final client-facing email or document. |
| **FR-QUO-077** | Calculation integrity: hiding the Sell Price or Discount columns does not change the underlying total, which remains mathematically accurate. The exception is "Without Price", where financial totals may be suppressed entirely on the client document. |
| **FR-QUO-078** | Draft state edits: while the quotation is in QUOTATION DRAFT, all fields — From, Ship To, Products and Settings — remain fully editable. Once it is converted to an invoice or formally sent, certain fields may lock according to global system rules. |

**Edge cases and error handling**

| FR-QUO-079 | Where the user unchecks every checkbox, the system is assumed either to treat this as "Without Price" or to force at least one checkbox to remain selected, so that the table cannot enter a broken state. |
| :---- | :---- |
| **FR-QUO-080** | The Subtotal column is implicitly tied to Sell Price and QTY; where "Without Price" is selected, Subtotal shall also be hidden. |
| **FR-QUO-081** | Large product lists: with 100 or more products, toggling the checkboxes shall not cause noticeable interface freezing; column visibility should be handled by CSS class swapping or virtualised list updates so that feedback is immediate. |
| **FR-QUO-082** | Zero-value discounts: where "Discount" is shown but a product carries a 0% discount, the table shall display "0%" or "-" rather than an empty cell, so that the table structure is preserved. |
| **FR-QUO-083** | Where a network error prevents the Preview Settings state from being saved during send or export, the system shall alert the user: "Failed to save display settings. Please try again before exporting." |

**Acceptance criteria**

| FR-QUO-084 | The system shall display a "Client View" tab that simplifies the quotation layout to the client’s perspective. |
| :---- | :---- |
| **FR-QUO-085** | The system shall display a "Preview Settings" section containing four checkboxes: List Price, Sell Price, Discount and Without Price. |
| **FR-QUO-086** | The system shall uncheck "List Price", "Sell Price" and "Discount" automatically when "Without Price" is checked. |
| **FR-QUO-087** | The system shall uncheck "Without Price" automatically when any of the other three pricing checkboxes is checked. |
| **FR-QUO-088** | The system shall show or hide the corresponding columns in the products table immediately when a checkbox changes state. |
| **FR-QUO-089** | The system shall hide the Subtotal column and the Details financial totals where "Without Price" is selected. |
| **FR-QUO-090** | The system shall apply the column visibility chosen in Preview Settings to the document generated by "Preview", "Print" and "Export". |
| **FR-QUO-091** | The system shall ensure that the quotation sent to the client adheres strictly to the selected price display format. |
| **FR-QUO-092** | The system shall allow Credit, Freight Fee and Additional Discount to be edited inline from the Details section, recalculating the Total immediately. |

## **1.5 Quotation preview**

Provide a configurable interface for previewing, formatting and generating quotation documents for internal use (Vendor View) or external distribution (Client View), with granular control over the visibility of pricing, attachments and product detail before export or sending.

Design reference: CSS-Dealer, node 38301-173010; CSS-Dealer, node 39389-117574.

**Screen elements**

| Element | Type | Values | Behaviour | Required |
| :---- | :---- | :---- | :---- | :---- |
| Breadcrumbs | Navigation Link | "Quotations \> Quotation \#\[ID\]" | Navigates back to the main quotations list or specific quotation. | Required |
| Quotation Header | Text / Badge | Title: "Quotation \# \[ID\]", Status: e.g., "QUOTATION DRAFT" | Displays current quotation ID and lifecycle status. | Required |
| Top Action Bar | Button Group | "Convert into invoice", "Duplicate", "Print", "Export", "Preview" | Executes document-level actions. "Preview" reloads/focuses the current view. | Optional |
| View Tabs | Tab Selector | "Vendor View", "Client View" | Toggles the preview document and sidebar configuration options between internal and external modes. | Required |
| Warning/Info Alert | Banner | Text string | Displays instructional text (e.g., "Please review..."). Text changes based on selected View Tab. | Required |
| Export Format Selector | Toggle Buttons | "PDF", "CSV", "Word" | Selects the target file format for the "Export" action. | Required |
| Document Preview Pane | Iframe / Dynamic Container | Document visual | Dynamically updates to reflect the exact output based on sidebar checkbox configurations. | Required |
| Price Display: List Price | Checkbox | Checked / Unchecked | Toggles the "List Price" column in the product table. | Optional |
| Price Display: Sell Price | Checkbox | Checked / Unchecked | Toggles the "Sell Price" column in the product table. | Optional |
| Price Display: Discount | Checkbox | Checked / Unchecked | Toggles the "Discount" column / values in the product table. | Optional |
| Price Display: Without Price | Checkbox | Checked / Unchecked | Removes all pricing data from the document. Disables other Price Display options when active. | Optional |
| Quotation Attachments: Add files | Checkbox | Checked / Unchecked | Appends files linked to the product catalog to the exported document. | Optional |
| Attachments: Add files | Checkbox | Checked / Unchecked | Appends files linked to the product catalog to the exported document. | Optional |
| Quotation Attachments: Add image | Checkbox | Checked / Unchecked | Toggles the "Image" column in the product table. | Optional |
| Quotation Attachments: Description | Checkbox | Checked / Unchecked | Toggles the descriptive text under each product in the table. | Optional |
| General Attachments: Display logo | Checkbox | Checked / Unchecked | Toggles the company logo in the top-left corner of the document. | Optional |
| General Attachments: Display comments | Checkbox | Checked / Unchecked | Toggles the display of quotation-level comments/notes. | Optional |
| General Display: Sub-total | Checkbox | Checked / Unchecked | Toggles the Sub-total row in the totals summary. | Optional |
| General Display: Freight | Checkbox | Checked / Unchecked | Toggles the Freight row in the totals summary. | Optional |
| General Display: Tax | Checkbox | Checked / Unchecked | Toggles the Tax row in the totals summary. | Optional |
| General Display: Discount | Checkbox | Checked / Unchecked | Toggles the Discount row in the totals summary. | Optional |
| General Display: Installation | Checkbox | Checked / Unchecked | Toggles the Installation row in the totals summary. | Optional |
| General Display: Grand Total | Checkbox | Checked / Unchecked | Toggles the Grand Total row in the totals summary. | Optional |
| General Display: Manufacturer (MFR) | Checkbox | Checked / Unchecked | Toggles the "MFR" column in the product table. | Optional |
| Profit Calculations: Margin | Checkbox | Checked / Unchecked | Toggles the Margin data display. Visible in Vendor View only. | Optional |
| Profit Calculations: Markup | Checkbox | Checked / Unchecked | Toggles the "Markup" column. Visible in Vendor View only. | Optional |
| Profit Calculations: Gross Profit | Checkbox | Checked / Unchecked | Toggles the "Gross Profit" column. Visible in Vendor View only. | Optional |
| Back Button | Button | N/A | Returns the user to the previous Quotation data entry page. | Required |
| Send Button | Button | N/A | Automatically generates a PDF of the Client View and emails it to the Client Email address. | Required |

**Interaction logic**

**Navigation and transitions**

* The page is reached from "Preview" at the top of the quotation page, or from "Next" at the bottom of the data entry page.

* Selecting "PDF", "CSV" or "Word" highlights the chosen format, which determines the output of the top "Export" action.

* The bottom "Send" button overrides the format selector: it always generates a PDF, as stated in the Client View alert, and starts the email workflow.

**Configuration behaviour (right sidebar)**

* Every change to a sidebar checkbox updates the document preview pane immediately — for example, checking "Add image" makes the Image column appear.

* Switching to Vendor View reveals the "Profit Calculations" section in the sidebar, adds "(For Internal Use Only)" to the preview and displays the sensitive Cost, Markup and Gross Profit columns.

* Switching to Client View hides the "Profit Calculations" section and removes the sensitive columns from the preview.

**Functional rules**

| FR-QUO-093 | Vendor and client data segregation: the Client View shall never expose Cost, Markup, Margin or Gross Profit, whatever the sidebar configuration; the system strips this data from the Client View payload. |
| :---- | :---- |
| **FR-QUO-094** | Data extraction: the values for Sub-total, Freight, Tax, Discount, Grand Total and Manufacturer are inherited from the preceding quotation data entry state. They cannot be edited on this page, only shown or hidden. |
| **FR-QUO-095** | Manufacturer logic: the MFR field is populated from the catalog source; where an item comes from a specific manufacturer’s catalog, that manufacturer’s name is displayed. |
| **FR-QUO-096** | "Without Price" dominance: checking "Without Price" shall automatically uncheck and disable "List Price", "Sell Price" and "Discount", and the product table shall hide all pricing columns. |
| **FR-QUO-097** | Where "Without Price" is active and the user selects a price field, "Without Price" shall be unchecked automatically and the selected price fields shall become active again. |

**Edge cases and error handling**

| FR-QUO-098 | "Add files" assumes that the product catalog holds downloadable attachments — specification sheets, manuals — linked to the item IDs used in the quotation. |
| :---- | :---- |
| **FR-QUO-099** | Missing product images: where "Add image" is checked but a product has no image, the system shall render a placeholder or leave the cell blank so that table alignment is preserved. |
| **FR-QUO-100** | Multi-page documents: where the goods list exceeds one page, the preview pane shall render pagination accurately, breaking the table cleanly and updating the page indicator from "1/1" to "1/2", "2/2" and so on. |
| **FR-QUO-101** | Zero-value totals: where a value such as Discount or Freight is $0.00, checking the display box shall either display "$0.00" or hide the row, according to global system settings. This requires definition; the default assumption is to display $0.00 when checked. |
| **FR-QUO-102** | Missing email on send: where the client contact has no email address on file, the system shall display "Cannot send quotation: Client email address is missing." |
| **FR-QUO-103** | Export failure: where CSV or Word generation fails because of a server timeout or a data formatting problem, the system shall display a persistent banner: "Failed to generate \[Format\]. Please try again." |

**Acceptance criteria**

| FR-QUO-104 | The system shall allow the preview page to be reached by clicking "Preview" or "Next" from the main quotation page. |
| :---- | :---- |
| **FR-QUO-105** | The system shall display two tabs: "Vendor View" and "Client View". |
| **FR-QUO-106** | The system shall prevent the Client View from displaying Cost, Markup, Margin and Gross Profit data, both in the document preview and in the configuration panel. |
| **FR-QUO-107** | The system shall display the "Profit Calculations" configuration section only while the Vendor View tab is active. |
| **FR-QUO-108** | The system shall update the document preview pane in real time whenever a configuration checkbox is toggled. |
| **FR-QUO-109** | The system shall disable and uncheck "List Price", "Sell Price" and "Discount" when "Without Price" is selected. |
| **FR-QUO-110** | The system shall uncheck "Without Price" when any other price display option is selected. |
| **FR-QUO-111** | The system shall append the product catalog files to the export where "Add files" is checked. |
| **FR-QUO-112** | The system shall generate and send a PDF to the client’s email address when "Send" is clicked, regardless of the format selected in the top toggle. |
| **FR-QUO-113** | The system shall allow the configured view to be exported as PDF, CSV or Word through the top "Export" action. |

## **1.6 Sending a quotation from vendor to client**

Allow the user to dispatch a finalised quotation by email, generate a printable version, set the validity date and move the quotation from "Draft" to "Sent".

Design reference: CSS-Dealer, node 39542-131961.

**Screen elements**

| Element | Type | Values | Behaviour | Required |
| :---- | :---- | :---- | :---- | :---- |
| Close Icon (X) | Icon Button | N/A | Closes the modal without executing any send actions. | Optional |
| Send to Email | Toggle Switch | ON / OFF | When ON, enables the "Email" input field. When OFF, the "Email" input field is disabled/blocked. | Required |
| Print | Toggle Switch | ON / OFF | When ON, flags the system to open a printable PDF view in a new browser tab upon clicking "Send". | Required |
| Email | Text Input | Standard Email Format | Accepts client email address. Validates format on blur or submit. Blocked if "Send to Email" is OFF. | Required (conditional) |
| Valid Until | Date Picker | MM/DD/YYYY (or locale format) | Pre-fills from Quotation settings OR defaults to (Creation Date \+ 30 days). Clicking the calendar icon opens a date selector. | Required |
| Cancel | Button (Secondary) | N/A | Closes the modal without saving changes or sending the quotation. | Required |
| Send | Button (Primary) | N/A | Executes the selected actions (Email/Print), updates quotation status, and closes the modal. | Required |

**Interaction logic**

**Modal logic**

* The modal is opened by "Send" on the Preview Quotation page.

* "Valid Until" is calculated and pre-filled as soon as the modal loads.

* The email field is pre-filled with the client’s stored email address where one exists.

* Default toggle states may follow user preferences, but the interface must reflect the dependency immediately: where "Send to Email" loads in the OFF position, the email input must load disabled.

* Clicking "Cancel", the "X" icon or the backdrop closes the modal and returns the user to the Preview Quotation page without changing the document status.

**Form behaviour**

* Toggling "Send to Email" applies or removes the disabled state on the email input.

* Clicking the "Valid Until" field or its calendar icon opens a calendar from which a future date can be selected.

**Navigation and transitions**

* Clicking "Send" displays a loading state on the button while the request is processed.

* Where "Print" is ON, the system attempts to open the generated PDF in a new browser tab.

* On success the modal closes and the parent page reflects the new quotation status.

**Functional rules**

| FR-QUO-114 | Email validation: the email field shall pass standard regular-expression validation; where it fails, submission is blocked and an inline error is displayed. |
| :---- | :---- |
| **FR-QUO-115** | Date calculation: where no expiry date has been set in the quotation settings, the system shall calculate the current date plus 30 calendar days and place it in "Valid Until". |
| **FR-QUO-116** | Status update: a successful "Send" action shall move the quotation status from "Draft" to "Sent" in both the backend and the interface. |
| **FR-QUO-117** | Workflow advancement: once in "Sent" status, the quotation is flagged as "Awaiting Client Response" and certain edit capabilities are locked, depending on vendor permissions. |
| **FR-QUO-118** | PDF generation: the system shall generate the PDF from the exact layout rendered on the Preview Quotation page. |
| **FR-QUO-119** | Email dispatch: the email shall use a predefined professional template — to avoid spam filters and an unprofessional appearance — containing a short covering message and the generated PDF as an attachment. |

**Edge cases and error handling**

| FR-QUO-120 | The system is assumed to have a configured and active email service provider for outbound mail. |
| :---- | :---- |
| **FR-QUO-121** | The PDF generation service is assumed to be able to produce the document quickly enough to avoid a server timeout when "Send" is clicked. |
| **FR-QUO-122** | Both toggles off: where the user turns "Send to Email" and "Print" both OFF and clicks "Send", the system shall block submission and display "Please select at least one delivery method to send the quotation." |
| **FR-QUO-123** | Pop-up blockers: where "Print" is ON and the browser blocks the new tab, the system shall display "Pop-up blocked. Please allow pop-ups to view the print version, or download the PDF directly." |
| **FR-QUO-124** | Email delivery failure: where the email service fails, the modal shall remain open, an error shall be displayed ("Failed to send email. Please try again later.") and the quotation status shall remain "Draft". |
| **FR-QUO-125** | Past dates: where a date in the past is selected, "Send" shall trigger an inline error below the date field: "Validity date must be in the future." |

**Acceptance criteria**

| FR-QUO-126 | The system shall display the "Sending Your Quotation" modal when the user clicks "Send" on the Preview Quotation page. |
| :---- | :---- |
| **FR-QUO-127** | The system shall disable the email input while the "Send to Email" toggle is OFF. |
| **FR-QUO-128** | The system shall enable the email input and enforce email format validation while the "Send to Email" toggle is ON. |
| **FR-QUO-129** | The system shall populate "Valid Until" from the quotation settings, or default to 30 days from the current date where no setting exists. |
| **FR-QUO-130** | The system shall allow "Valid Until" to be changed using a calendar date picker. |
| **FR-QUO-131** | The system shall send an email using the standard template, with the quotation attached as a PDF, when "Send to Email" is ON and "Send" is clicked. |
| **FR-QUO-132** | The system shall open a new browser tab with the printable PDF when "Print" is ON and "Send" is clicked. |
| **FR-QUO-133** | The system shall change the quotation status from "Draft" to "Sent" only after "Send" is clicked and the selected actions have been initiated successfully. |
| **FR-QUO-134** | The system shall close the modal and return to the preview page without saving or changing the status where the user clicks "Cancel" or "X". |

## **1.7 Adding products — manufacturer catalog**

Allow vendors to browse manufacturer catalogs, filter products and add items to a specific quotation or order.

Design reference: CSS-Dealer, nodes 38444-195099, 39533-58445, 38488-105562, 37767-325443.

**Screen elements**

| Element | Type | Values | Behaviour | Required |
| :---- | :---- | :---- | :---- | :---- |
| Search Bar | Text Input | Free text | Filters the MFR list by Name, Product, or Status as the user types. | Optional |
| Status Filters | Pill Buttons | All, Not Assigned, Preferred, Approved, Not Approved | Filters the MFR list by selected status. "All" or "Not Assigned" is default. | Auto |
| Alphabet Filter | Button Row | A-Z (with counts) | Filters the MFR list to show only manufacturers whose names start with the selected letter. | Optional |
| MFR Card | List Item | MFR Data | Displays MFR Logo, Name, Address, and Status. Clicking the Name/Card navigates to the specific MFR's Catalog page. | Required |
| MFR Status Badge | Dropdown / Button | Preferred, Approved, Not Assigned, Not Approved | Displays current status. Clicking allows the vendor to change the MFR's status globally across the system. | Required |
| Pagination | Navigation | Page numbers | Allows navigation through multiple pages of manufacturers. | Auto |
| Context Tabs | Tabs | Order, Quotation | Toggles the working context. Changes the available options in the "Select Existing" dropdown and "Create New" modal. | Required |
| Search Bar | Text Input | Free text | Searches by Product name, Category, or ID. | Optional |
| See All Products | Button | Clickable | Switches the view from the Category list default to a flat list of all products. | Optional |
| Select Categories | Dropdown (Multi) | List of categories | Filters the product list. Checked items apply filter. Dependent on "Select Products" filter. | Optional |
| Select Products | Dropdown (Multi) | List of products | Filters the catalog by specific products. Selecting a product auto-filters the "Select Categories" dropdown. | Optional |
| Price Filter | Dropdown (Single) | Ascending, Descending | Sorts the displayed products by price. Requires clicking "Save" to apply. | Optional |
| Select Existing Context | Dropdown | List of Quotations or Orders | Displays existing Quotations (if Quotation tab is active) or Orders (if Order tab is active). Selecting one sets it as the active cart. | Required |
| Create New | Button | Clickable | Opens a modal to create a new Quotation or Order (depending on the active tab). Auto-selects the newly created item. | Optional |
| Category | Card | Category Name / Image | Displays category summary. Clicking opens the filtered product list for that category. | Auto |
| Product Card | Card | Product Data | Displays images, ID, Name, UoM, Specs, Price, and Variant options (Color, Material). | Auto |
| Variant Selectors | Radio Buttons | White, Grey, Wood, etc. | Selects specific product variations before adding to context. | Required |
| Add to Quotation / Order | Stepper | Integer (0+) | Increases/decreases product quantity. Modifying this updates the active Quotation/Order card. | Required |
| Product Images | Gallery | Image files | Displays main image and thumbnails. Includes Zoom, Print, and Download icons. | Auto |
| Context Tabs | Tabs | Order, Quotation | Maintains the context selection from the previous catalog page. | Required |
| Product Specs | Text Block | Read-only | Displays detailed description, technical details, materials, and dimensions. | Auto |
| Variant Selectors | Radio Buttons | Associated variants | Selects product color, frame material, and base material. | Required |
| Add to Context | Stepper | Integer (0+) | Adds or removes the specified quantity of the variant to the active Quotation/Order. | Required |
| Back | Button | Clickable | Returns the user to the MFR Catalog product list. | Required |
| Go to Quotation | Button | Clickable | Navigates the user directly to the active Quotation / Order management page. | Required |
| Select Existing Context | Modal | N/A | Appears when "Select Existing Quotation/Order" is clicked, or when adding an item without an active context. | N/A |
| Context Dropdown | Dropdown | Active Orders / Quotes | Allows selection of the target document. | Required |
| Cancel / Save | Buttons | Clickable | Closes modal / Applies selection and sets active context. | Required |
| Choose F\&B Client | Modal | N/A | Appears when "Create New" Quotation is clicked. | N/A |
| New Quotation Name | Text Input | Free text | Assigns a name to the new quotation. | Required |
| New Quotation Number | Text Input | Alphanumeric | Assigns an ID/Number to the quotation. | Required |
| F\&B Client | Dropdown | List of clients | Associates the quotation with an existing client. | Required |
| Client not in system | Checkbox | Checked / Unchecked | Bypasses the client dropdown if the client is new / external. | Optional |
| Discard / Create | Buttons | Clickable | Cancels creation / Creates the quotation and sets it as the active context. | Required |

**Interaction logic**

**Scenario 1 — browsing and context switching**

* The vendor opens the manufacturer catalog and switches between the "Order" and "Quotation" tabs.

* Switching tabs changes the options available in the "Select Existing" dropdown, showing only orders or only quotations, and determines what the "Create New" button will produce.

**Scenario 2 — adding a product with an active context**

* The vendor selects an existing quotation from the dropdown, browses the products and clicks "+" on a product card.

* The system increments the quantity and syncs the product and quantity to the selected quotation in the background.

**Scenario 3 — adding a product without an active context**

* The vendor browses the catalog without selecting a quotation or order and clicks "+" on a product.

* The system intercepts the action: the stepper does not increment, the context area is highlighted and a modal prompts the user to select an existing document or create a new one.

* Once the modal is completed, the active context is set and the item is added.

**Scenario 4 — filtering products**

* Selecting a specific product in the "Select Products" dropdown filters the "Select Categories" dropdown to the categories relevant to that product.

* Choosing "Ascending order" in the Price dropdown and clicking "Save" re-renders the product grid sorted from the lowest price upwards.

**Functional rules**

| FR-QUO-135 | Global status inheritance: changing a manufacturer’s status on the Select MFR page — for example from "Not Assigned" to "Preferred" — updates that status globally across all other modules immediately. |
| :---- | :---- |
| **FR-QUO-136** | Bidirectional cart syncing: where a product quantity is changed in the manufacturer catalog, the corresponding quotation or order is updated automatically. |
| **FR-QUO-137** | Bidirectional cart syncing: where a product is removed in the quotation document itself, the manufacturer catalog shall show a quantity of zero for that product when viewed in that quotation context. |
| **FR-QUO-138** | Tab-exclusive context: a product cannot be added to an order while the "Quotation" tab is active; the active tab governs the destination of added products. |
| **FR-QUO-139** | Auto-selection on creation: where a new quotation or order is created through the "Create New" modal, the system shall set it as the active context in the dropdown automatically. |

**Edge cases and error handling**

| FR-QUO-140 | Prices displayed are those agreed between the vendor and the manufacturer. |
| :---- | :---- |
| **FR-QUO-141** | Products with multiple variants (colour, material) are treated as distinct line items where different variants of the same product are added. |
| **FR-QUO-142** | Zero quantity: reducing an item to zero through the stepper removes the line from the target quotation or order entirely; a zero-quantity line is not retained. |
| **FR-QUO-143** | Deleted context: where the active quotation or order is deleted in another session, adding an item shall raise an error, clear the context and prompt the user to select a valid one. |
| **FR-QUO-144** | Pagination during selection: where the user selects items across several pages, the system shall retain the active context and the quantities already selected. |
| **FR-QUO-145** | Where the user attempts to add a product without selecting the required variants, the system shall highlight the variant selectors in red and prevent the addition. |
| **FR-QUO-146** | Where a network error interrupts the bidirectional sync, the stepper shall revert to its previous state and display "Failed to update quotation. Please try again." |

**Acceptance criteria**

| FR-QUO-147 | The system shall display a list of manufacturers that can be filtered by status, by starting letter and by text search. |
| :---- | :---- |
| **FR-QUO-148** | The system shall allow the vendor to change a manufacturer’s status directly from the list, applying the change globally. |
| **FR-QUO-149** | The system shall provide "Order" and "Quotation" tabs in the manufacturer catalog that determine whether the user is working with orders or quotations. |
| **FR-QUO-150** | The system shall display products by category by default and allow a flat list of all products through "See All Products". |
| **FR-QUO-151** | The system shall filter the "Select Categories" dropdown according to the selections made in the "Select Products" dropdown. |
| **FR-QUO-152** | The system shall prevent a product from being added where no quotation or order is selected. |
| **FR-QUO-153** | The system shall open the select-or-create context modal where the user clicks "+" without an active quotation or order. |
| **FR-QUO-154** | The system shall set a newly created quotation or order as the active context immediately after creation. |
| **FR-QUO-155** | The system shall synchronise product quantities between the catalog stepper and the active quotation or order in both directions, in real time. |
| **FR-QUO-156** | The system shall remove a product from the quotation or order where its quantity is reduced to zero in the catalog stepper. |

## **1.8 Adding products — vendor catalog**

Allow vendors to add products from their own catalog to a new or existing quotation without leaving the product listing page.

Design reference: CSS-Dealer, node 39542-129969.

**Screen elements**

| Element | Type | Values | Behaviour | Required |
| :---- | :---- | :---- | :---- | :---- |
| Select Existing Quotation | Dropdown | List of active / draft Quotation Names/IDs | Allows user to set the active quotation context for the page. Auto-selects newly created quotations. | Optional |
| \+ Create new | Button | N/A | Opens the "Create New Quotation" modal. | N/A |
| \+ Add to Quotation | Button | N/A | Adds the specific row's product to the currently selected quotation. If no quotation is selected, triggers the "Create New Quotation" modal. | N/A |
| Quantity Stepper | UI Component | Integer (0 to Max Inventory), default: 1 | Replaces the "+ Add to Quotation" button once a product is added. Contains \[-\] \[Input Field\] \[+\] controls. | Required (after adding) |
| Create Quotation Modal | Modal Dialog | Standard Quotation creation fields | Captures details for a new quotation. Upon success, closes and sets the new quotation in the Dropdown. | Required (on trigger) |
| Product Row | Data Row | Product details (ID, Name, Price, etc.) | Provides the context (Product ID) passed to the quotation when the Add button is clicked. | N/A |

**Interaction logic**

**Scenario A — adding to an existing quotation**

* The user selects a quotation in the "Select Existing Quotation" dropdown and clicks "+ Add to Quotation" on a product row.

* The system adds one unit of the product to the selected quotation.

* The button immediately becomes a quantity stepper showing a value of 1\.

* The user can adjust the quantity with "+" and "−", or type a quantity directly.

**Scenario B — adding a product with no quotation selected**

* The user clicks "+ Add to Quotation" while the dropdown is empty.

* The system intercepts the action and opens the "Create New Quotation" modal.

* On save, the modal closes and the new quotation is selected in the dropdown automatically.

* The system then completes the original action: the product is added and the button becomes a quantity stepper.

**Scenario C — creating a new quotation explicitly**

* The user clicks "+ Create new" beside the dropdown, completes the modal and saves.

* The modal closes and the new quotation is selected in the dropdown automatically.

**Context switching**

* Changing the selected quotation re-evaluates the state of every "+ Add to Quotation" button on the page.

* Where a product is already in the newly selected quotation, its row shows the stepper with the current quantity; otherwise it shows the default button.

**Functional rules**

| FR-QUO-157 | The "Select Existing Quotation" dropdown shall list only quotations in an editable state — "Draft" or "Open". |
| :---- | :---- |
| **FR-QUO-158** | Manual input in the quantity stepper shall be restricted to positive integers. |
| **FR-QUO-159** | The button becomes a stepper only on a successful API response confirming that the product was added. |
| **FR-QUO-160** | Where the stepper quantity is reduced to zero, the product is removed from the quotation and the interface reverts to the "+ Add to Quotation" button. |
| **FR-QUO-161** | Any interaction with the stepper triggers an auto-save call that updates the quotation in the background; no explicit save action is required for line items. |

**Edge cases and error handling**

| FR-QUO-162 | The user is assumed to hold the permissions required to edit the selected quotation. |
| :---- | :---- |
| **FR-QUO-163** | The page does not reload when products are added; all interactions are asynchronous. |
| **FR-QUO-164** | Quotation state change: where the selected quotation is submitted or locked in another browser tab, adding a product or changing a quantity shall fail gracefully with the message "This quotation is no longer editable", and the page context shall reset. |
| **FR-QUO-165** | Inventory limits: where a product carries a strict inventory limit, manual input above that limit shall revert to the maximum available quantity with a warning. |
| **FR-QUO-166** | Rapid clicking: where the user clicks "+" repeatedly, the system shall debounce the API calls to prevent duplicate entries, sending the final state after a short pause. |
| **FR-QUO-167** | Where the "Create New Quotation" modal fails to save, it shall remain open with inline validation errors and the product shall not be added. |
| **FR-QUO-168** | Where a network error occurs while adding a product, the button shall show a loading state and then revert, with the message "Failed to add product. Please check your connection." |

**Acceptance criteria**

| FR-QUO-169 | The system shall display a "Select Existing Quotation" dropdown and a "+ Create new" button above the product table. |
| :---- | :---- |
| **FR-QUO-170** | The system shall display an "+ Add to Quotation" button on every product row in the catalog. |
| **FR-QUO-171** | The system shall open the "Create New Quotation" modal when "+ Create new" is clicked. |
| **FR-QUO-172** | The system shall select a newly created quotation in the dropdown immediately on creation. |
| **FR-QUO-173** | The system shall add the selected product to the active quotation when "+ Add to Quotation" is clicked. |
| **FR-QUO-174** | The system shall replace the "+ Add to Quotation" button with a quantity stepper immediately after a product is added successfully. |
| **FR-QUO-175** | The system shall open the "Create New Quotation" modal where the user clicks "+ Add to Quotation" while the dropdown is empty. |
| **FR-QUO-176** | The system shall add the pending product to the newly created quotation where the modal was triggered in this way. |
| **FR-QUO-177** | The system shall update the product quantity in the quotation asynchronously when the stepper is used. |
| **FR-QUO-178** | The system shall remove the product from the quotation and restore the "+ Add to Quotation" button where the stepper quantity is reduced to zero. |
| **FR-QUO-179** | The system shall re-evaluate the button or stepper state for every visible product row whenever the active quotation changes. |

## **1.9 Adding a product group from the quotation page**

Allow the user to add a new product grouping — by manufacturer or vendor catalog — to an existing quotation through a dedicated search and selection modal, without creating duplicate groupings.

Design reference: CSS-Dealer, node 40000-148660.

**Screen elements**

| Element | Type | Values | Behaviour | Required |
| :---- | :---- | :---- | :---- | :---- |
| Add Product Group Button | Button | "+ Add product from new manufacturer / vendor catalog" | Located at the bottom of the quotation product tables. Opens the "Search" modal on click. | Required |
| Search Modal | Modal Dialog | N/A | Overlays the quotation page. Contains search and selection tools. | Required |
| Close Icon | Icon Button | "X" | Closes the modal without saving changes. | Required |
| Search Input | Text Input | Alphanumeric, Free text | Filters the displayed list based on the entered string. Placeholder: "Search by Name...". | Optional |
| Type Radio | Radio Group | "MFR", "Vendor Catalog" | Toggles the data source and UI layout. Default is "MFR". | Required |
| Alphabetical Filter | Horizontal Scroll List | A-Z | Displays letters with a count of available records beneath each (e.g., G (4) ). Horizontally scrollable / swipeable. Hidden when "Vendor Catalog" is selected. | Auto |
| List Item (MFR) | Selectable Card | Logo, MFR Name, Address | Displays manufacturer details. Clicking selects the item (applies blue border). | Required |
| List Item (Vendor) | Selectable Card | Logo, "My Catalog" | Displays the user's internal catalog. Clicking selects the item (applies blue border). | Required |
| Scroll-to-Top | Floating Action Button | Up Arrow Icon | Appears only when the user scrolls down the list. Clicking returns the view to the top of the list. | Auto |
| Cancel Button | Button | "Cancel" | Closes the modal without applying changes. | Required |
| Choose Button | Button | "Choose" | Confirms the selection, adds the new grouping to the quotation, and closes the modal. Disabled until an item is selected. | Required |

**Interaction logic**

**Modal behaviour**

* The user clicks "+ Add product from new manufacturer / vendor catalog" and the search modal opens.

* The modal opens with the "MFR" radio selected and the full list of manufacturers displayed alphabetically.

* Search by text: typing filters the list dynamically and highlights the corresponding starting letter in the alphabet filter.

* Search by letter: clicking a letter, or scrolling the horizontal alphabet bar, filters the list to manufacturers starting with that letter.

* Vendor catalog flow: selecting the "Vendor Catalog" radio hides the alphabet filter and displays a single option, "My Catalog".

* Selection: clicking a list item highlights it with a blue border and activates the "Choose" button.

* "Choose" adds the selected manufacturer or catalog as a new table section on the quotation page and closes the modal; "Cancel" or "X" closes it without changes.

**Functional rules**

| FR-QUO-180 | Data grouping: products on the quotation page shall be grouped strictly by manufacturer or by vendor catalog; this action creates the header and container for a new group. |
| :---- | :---- |
| **FR-QUO-181** | Uniqueness: a given manufacturer, or the vendor catalog, can be added to a quotation only once. |
| **FR-QUO-182** | Where a manufacturer or the vendor catalog is already present on the quotation, it shall be displayed in the search modal as greyed out and unclickable, and it shall not be selectable through "Choose". |
| **FR-QUO-183** | Alphabet counts: the numbers below the letters shall represent the number of manufacturers available under that letter, excluding those already added to the quotation. Showing accurate selectable counts is preferred; the alternative is to include them but keep them disabled, depending on backend pagination. |

**Edge cases and error handling**

| FR-QUO-184 | A large manufacturer database is assumed, so the modal list requires lazy loading, pagination or infinite scroll. |
| :---- | :---- |
| **FR-QUO-185** | "My Catalog" is a single static entity tied to the user’s account or tenant. |
| **FR-QUO-186** | Zero results: where a search returns nothing, the list area shall display a message such as "No manufacturers found matching ‘\[Search Term\]’". |
| **FR-QUO-187** | Empty letters: letters with no associated manufacturers shall be disabled to prevent dead clicks. |
| **FR-QUO-188** | Long text: very long manufacturer names or addresses shall be truncated with an ellipsis so that the card layout is preserved. |
| **FR-QUO-189** | Where the manufacturer list fails to load, the modal shall display an inline error with a "Retry" control. |
| **FR-QUO-190** | Where a duplicate manufacturer is submitted through the API, bypassing the interface rules, the backend shall reject the request with a duplicate entry error, which the interface displays as a notification. |

**Acceptance criteria**

| FR-QUO-191 | The system shall display a "+ Add product from new manufacturer / vendor catalog" button at the bottom of the quotation product tables. |
| :---- | :---- |
| **FR-QUO-192** | The system shall open a search modal when the add button is clicked. |
| **FR-QUO-193** | The system shall provide a radio toggle between the "MFR" and "Vendor Catalog" data sources. |
| **FR-QUO-194** | The system shall display a horizontally scrollable A–Z alphabet filter while "MFR" is selected. |
| **FR-QUO-195** | The system shall display the count of available manufacturers under each letter of the alphabet filter. |
| **FR-QUO-196** | The system shall filter the list of manufacturers dynamically according to the text entered in the search bar. |
| **FR-QUO-197** | The system shall hide the alphabet filter and display only "My Catalog" while "Vendor Catalog" is selected. |
| **FR-QUO-198** | The system shall highlight a list item with a blue border when it is clicked. |
| **FR-QUO-199** | The system shall grey out and disable any manufacturer or vendor catalog already added to the current quotation. |
| **FR-QUO-200** | The system shall display a floating scroll-to-top control once the user scrolls down the list. |
| **FR-QUO-201** | The system shall close the modal and add the selected entity as a new grouping on the quotation page when "Choose" is clicked. |

## **1.10 Client response and conversion to an order**

Give clients a single place to view, review, adjust quantities on, and accept or reject quotations submitted by vendors. Accepting a quotation converts it into an order automatically.

Design reference: CSS-Dealer, node 37778-340901.

**Screen elements**

| Element | Type | Values | Behaviour | Required |
| :---- | :---- | :---- | :---- | :---- |
| Main Menu Badge | UI Badge | Integer | Displays the count of unopened quotations in the "Received" status. | Auto |
| Create new | Button | N/A | Opens flow to create a new Request for Quotation (Future Scope). | Optional |
| Search Bar | Text Input | Alphanumeric | Filters the quotations table based on user input. | Optional |
| Status Tabs | Tab Navigation | Draft, Sent to Vendor, Received, Accepted, Over 30 days | Filters the data table by the selected status. | Required |
| Status Info Icons | Icon / Tooltip | Text | On hover, displays a tooltip explaining the definition of the adjacent status. | Required |
| Date Range | Date Picker | MM/DD/YYYY \- MM/DD/YYYY | Filters the table by a specific date range. | Optional |
| Quotations Table | Data Grid | Quotation ID, Name, Date Received, Vendor, Total, Valid Until | Displays a list of quotations based on the active tab and filters. | Required |
| Go to Order | Button | N/A | Appears only in the "Accepted" tab row. Navigates the user directly to the resulting Order. | Auto |
| Header Actions | Buttons | Duplicate, Print, Export | Triggers respective system actions for the current quotation. | Optional |
| Edit Icons (Quotation Info, From, To) | UI Icon | N/A | Disabled/Hidden for Client. Layout artifact; clients cannot edit core quotation data. | Auto |
| Products Table | Data Grid | Flat list of products | Displays products as a single continuous list, not segmented by vendor catalogs. | Required |
| ORD QTY | Number Input | Integer \> 0 | Allows client to change the quantity of a product. Triggers modification state. | Required |
| Row Actions | Icons | Comment, Delete | Allows adding a line-item comment or removing a line item (triggers modification state). | Optional |
| Terms & Conditions (+ Add) | Button / Text | Free text | Allows the client to add global comments to the quotation. | Optional |
| Signature Checkbox | Checkbox | Checked / Unchecked | Acknowledges conversion to invoice. Enables the "Sign the Quotation" button. | Required |
| Request modifications | Button | N/A | Submits the quotation back to the vendor with requested QTY changes or line-item deletions. | Conditional |
| Sign the Quotation | Button | N/A | Submits the accepted quotation, changing status to "Accepted" and triggering order creation. | Conditional |
| Go to PO / Go to Order | Button | N/A | Replaces action buttons if the quotation has already been converted to an order/PO. | Auto |

**Interaction logic**

**Reviewing quotations**

* A numbered badge on the "Quotations" menu item indicates unopened quotations in "Received" status.

* Selecting the "Received" tab populates the table with pending quotations; hovering over the "i" icon explains the status.

* Clicking a row opens the quotation details view, in which all core information — Customer \#, Job \#, From and To addresses — is strictly read-only.

**Acceptance flow**

* The client reviews the flat list of products and the totals.

* The client ticks the "By clicking ‘Sign the quotation’..." checkbox and clicks "Sign the Quotation".

* The system converts the quotation into an order, changes the status to "Accepted" and returns the client to the list view or to the new order.

**Modification flow**

* The client changes a value in the ORD QTY field.

* Because the quotation has been altered, it can no longer be signed directly.

* The client clicks "Request modifications" to send the updated parameters back to the vendor for a revised quotation.

**Functional rules**

| FR-QUO-202 | Flat product list: unlike the vendor view, the client product table shall consolidate all items into a single list, without manufacturer or catalog segmentation. |
| :---- | :---- |
| **FR-QUO-203** | Read-only integrity: clients shall not be able to edit quotation information, vendor details or client details on a received quotation; edit icons present in the mock-ups shall be disabled or removed programmatically. |
| **FR-QUO-204** | Expiry, condition A: where the vendor has provided a "Valid Until" date, the system counts 30 days from that date. |
| **FR-QUO-205** | Expiry, condition B: where "Valid Until" is empty, the system counts 30 days from the date the quotation was received. |
| **FR-QUO-206** | Expiry action: where no client response — acceptance or modification request — is recorded within that window, the status changes automatically to "Over 30 days". |
| **FR-QUO-207** | Vendor asynchronous rule: vendors retain the right to click "Convert to Invoice" on their side at any time. The system shall not block the vendor from proceeding where the agreement was reached outside the platform. |

**Edge cases and error handling**

| FR-QUO-208 | Real-time status sync: because a vendor can convert a quotation to an order unilaterally, the system must handle a client viewing a "Received" quotation that the vendor has just converted. |
| :---- | :---- |
| **FR-QUO-209** | Unopened status: the menu badge counts unopened received quotations. Opening the details view marks the quotation as opened and decrements the counter, even though the status remains "Received". |
| **FR-QUO-210** | Zero or negative quantity: where a client attempts to set ORD QTY to zero or a negative number, the system shall prevent the input or force a minimum of one, requiring the delete icon to be used instead. |
| **FR-QUO-211** | Vendor converts while the client edits: where the client is requesting modifications and the vendor converts the quotation to an order at the same time, the system shall abort the modification request and display "This quotation has already been converted to an order by the vendor." |
| **FR-QUO-212** | Where "Sign the Quotation" fails — through a network error, or because the vendor has deleted the product from their catalog — the system shall retain the checked agreement box and display "Failed to convert quotation. Please try again or contact the vendor." |

**Acceptance criteria**

| FR-QUO-213 | The system shall display a numeric badge on the sidebar menu showing the number of unopened quotations in "Received" status. |
| :---- | :---- |
| **FR-QUO-214** | The system shall display a tooltip explaining the status definition when the user hovers over the "i" icon beside a status tab. |
| **FR-QUO-215** | The system shall calculate the "Over 30 days" expiry by adding 30 days to the "Valid Until" date, or to the date received where "Valid Until" is blank. |
| **FR-QUO-216** | The system shall move quotations to the "Over 30 days" tab automatically where no action is taken before the calculated expiry date. |
| **FR-QUO-217** | The system shall render all quotation information and the "From" and "To" fields as strictly read-only on the client side, regardless of the layout elements shown. |
| **FR-QUO-218** | The system shall display the quotation line items as a single, unsegmented list in the client details view. |
| **FR-QUO-219** | The system shall allow the ORD QTY field to be edited, and shall then require the "Request modifications" action rather than direct acceptance. |
| **FR-QUO-220** | The system shall enable "Sign the Quotation" only while the agreement checkbox is checked. |
| **FR-QUO-221** | The system shall convert the quotation into an order and change its status to "Accepted" on a successful "Sign the Quotation" action. |
| **FR-QUO-222** | The system shall display a "Go to Order" or "Go to PO" control on quotations that have been converted successfully. |

## **1.11 Clarifications on client comments**

The client reviewed the quotation block and raised the points below. Each entry records the comment, the agreed position and its current status. Items marked "Decision required" are open and are also listed in the summary that follows.

| \# | Topic | Client comment | Position | Status |
| :---- | :---- | :---- | :---- | :---- |
| 1 | **Deletion of accepted quotations** | Hard deletion of quotations already converted into orders and invoices may affect the audit history. Statuses such as Archive, Void or Cancel are suggested instead of deletion. | It was previously agreed that invoices cannot be deleted once a payment has been recorded against them, and the same approach applies to quotations: once a quotation has been converted into an order, the Delete action is no longer available. Rather than introduce an archive mechanism at this stage, deletion is restricted for quotations that have already generated an order and an invoice. The record remains in the system with its database relationships intact. | Agreed |
| 2 | **Standardisation of the Valid Until date** | Different triggers were identified for calculating the expiry date: 30 days from creation, from sending or from receipt. The proposed standard is Sent Date \+ 30 days. | Following the December discussions, Valid Until is calculated by default as Quotation Date \+ 30 days, where Quotation Date is the date the quotation was sent to the customer. The current requirement therefore matches the proposed standard. The vendor retains the ability to change the date manually using the calendar selector. | Aligned |
| 3 | **Price fixation and price snapshot** | Prices should be locked at the moment a product is added, and a full price snapshot (List Price, Discount, Net Price, Markup and so on) should be stored per quotation line so that later catalog updates do not affect existing quotations. | This is already covered by the current logic. The price is captured and fixed when the product is added to the quotation, and subsequent changes in the master catalog do not affect quotations already created. | Already covered |
| 4 | **Permissions for Convert to Invoice** | Should this action be available only to managers rather than to regular salespersons? | The system supports role-based access control, so permissions can be configured to the business rules. At present managers see all vendor quotations and hold full management permissions, while salespersons can access and manage only their own. Whether Convert to Invoice should be restricted to manager roles needs to be stated explicitly in the requirements. An alternative is a configurable approval rule: with approval enabled, salespersons convert quotations independently; with it disabled, conversion requires manager approval. | Decision required |
| 5 | **Salesperson reassignment** | If salespersons see only their own quotations, can they reassign a quotation to a colleague? | The current logic is correct: salespersons can reassign only their own quotations to another salesperson, and managers can reassign the responsible salesperson on any quotation. | Confirmed |
| 6 | **Editing store or restaurant information** | Company data — name, email, address — should be read from the database and locked within the quotation. Only the contact person should remain editable. | Only the Contact Person field should remain editable, and the system should allow selection only from contacts associated with the current customer record. Editing store or restaurant information directly from the quotation is considered unnecessary: customer data changes are not a frequent quotation-level activity and belong in the customer profile. The quotation uses the latest customer information from the database. | Agreed |
| 7 | **Manual or automatic tax input** | A clear rule is required: is tax entered manually per line item or calculated automatically? | The agreed approach is manual tax rate input for each quotation line item. | Agreed |
| 8 | **Use of Sold Qty in calculations** | Confirm that totals, conversion logic and PDF generation use Sold Qty (the approved quantity) rather than Order Qty. | All subtotal, total and gross profit calculations are based on Sold Qty. | Confirmed |
| 9 | **Gross profit formula** | Taxes and freight should not increase gross profit; the formula needs review. | The agreed formula is Gross Profit \= (Sell Price − Net Price) × Sold Quantity. Where the current implementation calculates gross profit from the total amount including taxes or freight, the logic must be corrected to exclude taxes and delivery costs from profitability. | Correction required |
| 10 | **Without Price** | Can the customer sign a quotation while prices are hidden, and if so how are prices carried into the order? | The system supports hiding prices from the customer while maintaining the underlying calculation logic. Where the customer signs a quotation without visible prices, the internal vendor pricing is transferred into the generated order automatically. | Confirmed |
| 11 | **Installation entity** | The Installation field should be part of the quotation data model, not only available in preview mode, so that the system amount matches the signed PDF amount. | This would require a dedicated Installation entity in the database and its integration into the existing quotation logic. It falls outside the current scope and can be evaluated separately as a future enhancement. | Out of scope |
| 12 | **Version history** | Where a vendor modifies a quotation after sending it, version history is needed to identify which version the customer signed. | The customer signs the latest available version. Where the vendor modifies the quotation before signature, the customer receives a notification that it has been updated. Where the customer has already signed, the vendor is notified that the current version is signed and further editing is not allowed. A separate version history mechanism is therefore not required in the current scope. | Not required in scope |
| 13 | **Modification requested flag** | The vendor needs a visible indicator that the customer has requested changes. | The vendor is currently notified through the quotation chat. Visual highlighting and counters for quotations with requested modifications can be evaluated as a future enhancement. | Future enhancement |
| 14 | **Signed quotation snapshot** | On signature the system should save the final snapshot — products, signature, timestamp — because the customer may remove items before signing. | When the status changes to Accepted, the system records confirmation of customer acceptance, the customer name and the acceptance timestamp. Where the customer modifies requested items before signing, an updated quotation is generated and returned to the vendor, and the order and invoice are created from the latest accepted version. | Confirmed |
| 15 | **Blocking change requests** | Clarification is required on which customer actions block the Sign button — for example, requesting a new product. | The Sign button is disabled where the customer requests an increase in quantity or the addition of a new product, because both require vendor confirmation of availability and pricing. Customer comments alone do not block signing. | Confirmed |
| 16 | **Customer duplication of quotations** | Can the customer duplicate a quotation, given that customers cannot create quotations themselves? | Customers can duplicate expired quotations (Over 30 Days) only, in order to request an update from the vendor. This is not creation of a new quotation from scratch but a request to refresh an existing one. | Confirmed |

# **Part 2\. Manufacturer list and manufacturer card**

This part covers the manufacturer directory available to vendors (MFR Contacts) and the manufacturer card, which is presented in two modes: the vendor view, which holds the dealer’s own commercial terms, and the manufacturer view, in which the manufacturer maintains its own master data. The two modes exist to separate global manufacturer data from proprietary dealer data.

**User story**

* As a vendor, I want a list of all manufacturers, so that I can contact them, gather information about a manufacturer and record notes against it.

* As a manufacturer, I want to maintain my own information in Settings, so that vendors see accurate details about my company.

*The vendor binds to the existing global manufacturer database; the vendor does not create new manufacturer records, in the same way as with the client base. Creating a manufacturer from scratch may be added in a future iteration.*

**Strategic objective**

Give dealers a single place to manage manufacturer relationships, distinguishing master manufacturer data, which is public, from proprietary dealer data such as internal pricing, margins and notes.

**User value**

| Benefit | Effect |
| :---- | :---- |
| Data integrity | Prevents accidental modification of global manufacturer data while allowing dealer-specific terms to be customised. |
| Financial accuracy | Keeps dealer-specific discounts, margins and rebates available for accurate quoting. |
| Relationship management | Tracks the local representation agency and the contacts relevant to the dealer’s region (MAFSI areas). |
| Operational efficiency | Allows the list to be filtered by approval status and exported or copied. |

## **2.1 Manufacturer list (MFR Contacts)**

Give the vendor a high-level overview of every manufacturer in the system: filter by status, read the commercial terms at a glance and open the manufacturer card from a row.

Design reference: CSS-Dealer, node 39997-106432.

**Interface**

* Sidebar navigation: Manufacturers, with the sub-links MFR Contact and MFR Catalog.

* Main header: "MFR Contact".

* Filter tabs above the table: All Manufacturers, Preferred, Approved, Not Approved. The active tab is marked with an orange underline.

* The table is paginated.

**Table columns**

| Column | Type / UI | Description |
| :---- | :---- | :---- |
| MFR Name | Text, sortable | Manufacturer name |
| Status | Interactive badge | Preferred (green, star), Approved (light green), Not Approved (light red) |
| General Terms | Text | Industry category or relationship type, for example "Restaurant" or "Vendor". The data source for this column is not defined — see the open points. |
| Parent Company | Text | Parent entity, for example "Hard Rock Cafe" |
| Payments Method | Multi-line block | Terms and markups, for example "60-15-15-10" or "42% MARKUP NET 30" |
| Rebate Status | Blue badge | "YES" where the rebate percentage is above zero, otherwise "NO" |
| Last Transaction | Date | Format MM/DD/YYYY. The set of operations counted is not defined — see the open points. |

**Functional rules**

| FR-MFR-001 | The system shall display a table of manufacturers including name, status, general terms (discount or margin), rebate status and last transaction date. |
| :---- | :---- |
| **FR-MFR-002** | The user shall be able to filter the list by All Manufacturers, Preferred, Approved and Not Approved. |
| **FR-MFR-003** | The user shall be able to change a manufacturer’s status directly from the list view. The available statuses are Preferred, Approved, Not Approved and Not Assigned. |
| **FR-MFR-004** | The rebate badge shall display "Yes" where a rebate percentage above zero exists, and "No" otherwise. |
| **FR-MFR-005** | A global search bar shall filter the results by manufacturer name. |
| **FR-MFR-006** | The user shall be able to export the currently filtered list of manufacturers to CSV, containing ID, name, status and pricing details. |

**Acceptance criteria**

| FR-MFR-007 | The system displays a paginated manufacturer list with the columns Name, Status, General Terms, Parent Company, Payments Method, Rebate Status, Last Transaction and Actions. |
| :---- | :---- |
| **FR-MFR-008** | The user can filter the list through the All / Preferred / Approved / Not Approved tabs without a page reload. |
| **FR-MFR-009** | The status badge opens an inline dropdown from which the status can be changed directly to Preferred, Approved, Not Approved or Not Assigned. |
| **FR-MFR-010** | The rebate badge renders "YES" where the rebate percentage is above zero and "NO" otherwise. |
| **FR-MFR-011** | The user can export or copy the filtered list containing ID, name, status and pricing details. |

## **2.2 Manufacturer card — vendor view**

Present the manufacturer’s master data to the vendor as read-only, while allowing the vendor to maintain its own commercial terms, category discounts and representation details against that manufacturer.

**Card blocks**

| Block | Access | Fields | Source |
| :---- | :---- | :---- | :---- |
| Manufacturer data | Read-only (greyed-out fields) | Name, DBA Name, Address, City, State, Zip, Country, Mailing Address, Mailing City, Mailing State, Mailing Zip, Mailing Country | Manufacturer |
| MFR logo | Read-only | Displays the uploaded logo | Manufacturer |
| Manufacturer contact information | Read-only | Website, Main Phone (with country flag indicator), Accounting Phone, Customer Service Phone, MFR Sales Manager Name, MFR Sales Phone, extension per phone line, Title, Email | Manufacturer |
| Manufacturer contact cards | Read-only | Contact cards showing name, email and phone. No edit or delete actions in this view. | Manufacturer |
| Vendor’s discounts, terms, margins and rebates | Editable | Master Discount (tiered discount text), Margin % (numeric), Cash Payment Terms (text), Rebate % (numeric), PPD Shipping Level $ (currency), Preferred Carrier (text), Group Affiliation (None / Preferred Group Member / Allowed / Not Allowed), Pricing & Terms Internal Notes (multi-line) | Vendor — private, not visible to the manufacturer |
| Vendor’s variable category discounts | Editable grid | Columns: Category (searchable dropdown), Multiplier (decimal), Margin % (numeric), delete action. An "Add Category Row" button sits above the grid, and a multi-line Category Multiplier Internal Notes field below it. | Vendor — informational only |
| Manufacturer’s representation | Editable | Representation Agency Name, MAFSI Area Numbers (multi-select tag field), Representation Agent Name, Cell Phone Number, Agency Office Phone, Email, Agency Order Email, General Notes (multi-line) | Both the manufacturer and the vendor maintain their own side; vendor edits are one-way and do not affect the manufacturer |
| Sticky footer | Buttons (fixed on scroll) | Discard (white background, blue text) and Save (blue background, white text) | — |

**Functional rules**

| FR-MFR-012 | Master manufacturer data shall be read-only in the vendor view, and shall be rendered as greyed-out fields. |
| :---- | :---- |
| **FR-MFR-013** | The vendor’s pricing, terms, margins, rebates and internal notes shall be editable in the vendor view and shall not be visible to the manufacturer. |
| **FR-MFR-014** | The vendor shall be able to add, edit and remove an unlimited number of additional contacts beyond the standard roles. |
| **FR-MFR-015** | The vendor shall be able to add multiple rows of category-specific pricing, each holding a category, a multiplier and a margin percentage. |
| **FR-MFR-016** | Changes to the representation agency information are one-directional: the vendor customises its own copy and the edits never write back to the manufacturer’s data. |
| **FR-MFR-017** | The card is saved through the global Save button in the sticky footer; Discard abandons the changes. |

## **2.3 Manufacturer card — manufacturer view**

Allow the manufacturer to maintain its own identity, address, contact and representation data, while keeping the dealer’s proprietary commercial terms out of sight.

**Interface**

* Reached through: manufacturer login → Settings → Information.

**Card blocks**

| Block | Access | Fields | Source |
| :---- | :---- | :---- | :---- |
| Manufacturer data | Editable (active inputs with placeholders) | The same identity and address fields: Name, DBA Name, Address, City, State, Zip, Country, Mailing Address, Mailing City, Mailing State, Mailing Zip, Mailing Country | Manufacturer |
| MFR logo | Editable | The empty state shows a dashed drag-and-drop zone ("Drag and drop a file or browse it on your device") with an Upload New button; once populated, the image is shown with Upload New beneath it. | Manufacturer |
| Manufacturer contact information | Editable | All phone, extension, name and email fields are active | Manufacturer |
| Manufacturer contact cards | Editable | An "Add MFR Contact" button opens the contact modal; each card carries edit and delete actions. | Manufacturer |
| Vendor’s discounts, terms, margins and rebates | Hidden entirely | Not shown — this protects the dealer’s terms | Vendor — one-way sync; vendor edits do not propagate here |
| Vendor’s variable category discounts | Hidden entirely | Not shown | Vendor |
| Manufacturer’s representation | Editable | The same editable fields as in the vendor view, excluding the internal General Notes: Representation Agency Name, MAFSI Area Numbers (multi-select tag field), Representation Agent Name, Cell Phone Number, Agency Office Phone, Email, Agency Order Email | Both the manufacturer and the vendor maintain their own side |

**Functional rules**

| FR-MFR-018 | All vendor pricing, discounts, category discounts and internal notes shall be hidden entirely in the manufacturer view. |
| :---- | :---- |
| **FR-MFR-019** | The manufacturer shall be able to edit its identity, addresses, logo, contact information and contact cards. |
| **FR-MFR-020** | The internal General Notes field in the representation block shall not be shown in the manufacturer view. |

## **2.4 MAFSI region selection**

Let the user record which MAFSI regions a representation agency covers.

**Functional rules**

| FR-MFR-021 | The region selector shall offer a fixed reference list of MAFSI regions; the list is neither customisable nor dynamic. |
| :---- | :---- |
| **FR-MFR-022** | The selector shall support multi-selection. |
| **FR-MFR-023** | The selector shall provide a search function by region name or region ID. |
| **FR-MFR-024** | Selected regions shall be rendered as removable tags, for example "Area 14". |
| **FR-MFR-025** | Selecting a region controls only what is displayed on the card; it drives no other behaviour. |

**Acceptance criteria**

| FR-MFR-026 | Selected MAFSI regions render as removable tags in the representation block, and the list offered is the fixed region reference. |
| :---- | :---- |

## **2.5 Data governance — read-only rules by view**

Define which data blocks are editable in each view mode. These rules are what keep global manufacturer data and proprietary dealer data separate.

**Editability by view mode**

| Data block | Vendor view (dealer internal) | Manufacturer view (master data) |
| :---- | :---- | :---- |
| Logo and identity | Read-only | Editable |
| Addresses (physical and mailing) | Read-only | Editable |
| Standard contacts | Read-only | Editable |
| Additional contacts | Read-only | Editable |
| Pricing and terms | Editable | Read-only |
| Variable discounts | Editable | Read-only |
| Internal notes | Editable | Hidden / read-only |
| Representation agency information | Editable | Editable |

**Functional rules**

| FR-MFR-027 | The application shall enforce the editability of each data block according to the selected view mode, as set out in the matrix above. |
| :---- | :---- |
| **FR-MFR-028** | Logo, identity, addresses and standard contacts shall be read-only in the vendor view. |
| **FR-MFR-029** | All vendor pricing, discounts and internal notes shall be hidden in the manufacturer view. |

**Acceptance criteria**

| FR-MFR-030 | Logo, identity, addresses and standard contacts are read-only in the vendor view. |
| :---- | :---- |
| **FR-MFR-031** | All vendor pricing, discounts and internal notes are hidden in the manufacturer view. |

## **2.6 Pricing and financial logic**

Define how the commercial fields on the manufacturer card behave and how far they reach into the rest of the system.

**Functional rules**

| FR-MFR-032 | Margin inputs accept numeric values. Where non-numeric text is entered, the value defaults to zero; intermediate typing states such as a lone decimal point are excluded from this rule. |
| :---- | :---- |
| **FR-MFR-033** | The Master Discount field accepts string formats such as "50/10/5", so that complex tiered discount structures can be recorded. |
| **FR-MFR-034** | Category, Multiplier and Margin % are independent informational fields held per category. They do not override the master discount and do not feed quotation calculations at this stage. |
| **FR-MFR-035** | Automatic application of the category discounts to the product catalog is to be evaluated and estimated separately. |

**Acceptance criteria**

| FR-MFR-036 | Non-numeric input in a Margin % field defaults to zero on blur, and values are constrained to the range 0.00–100.00. |
| :---- | :---- |
| **FR-MFR-037** | The Master Discount field supports tiered strings using "/" or "-" as separators. |
| **FR-MFR-038** | The category-specific multiplier and margin are stored as informational data only and do not override the master discount or margin in quotation calculations at this stage. |
| **FR-MFR-039** | Logo uploads are restricted to PNG, JPG, JPEG and SVG files of 5 MB or less, with an inline error where the restriction is breached. |

## **2.7 Validation and defaults**

Define the default values applied when a vendor first works with a manufacturer record.

**Functional rules**

| FR-MFR-040 | The default status is "Not Assigned". Because manufacturers are bound from the global base rather than created by the vendor, this is the vendor’s starting classification rather than a record-creation default. |
| :---- | :---- |
| **FR-MFR-041** | Group Affiliation defaults to "None"; the available options are Preferred Group Member, Allowed and Not Allowed. |
| **FR-MFR-042** | The system expects at least a name and a status. This is not currently enforced by blocking the interface. |

## **2.8 Data model**

The schema below records the fields held for a manufacturer and its associated objects.

**Manufacturer entity**

| Field | Type | Description |
| :---- | :---- | :---- |
| id | String | Unique identifier (UUID or database ID) |
| name | String | Legal company name |
| dbaName | String | Doing-business-as name |
| status | Enum | Preferred, Approved, Not Approved |
| lastUpdated | Date | Timestamp of the last modification |

**Address object (physical and mailing)**

| Field | Type | Description |
| :---- | :---- | :---- |
| street | String | Street address |
| city | String | City |
| state | String | State or province |
| zip | String | Postal code |
| country | String | Country name |

**Pricing and terms (proprietary)**

| Field | Type | Description |
| :---- | :---- | :---- |
| masterDiscount | String | Base discount string, for example "50-10" |
| marginPercent | Number | Dealer’s target margin percentage |
| cashTerms | String | Payment terms, for example "2% 10 Net 30" |
| rebatePercent | Number | Backend rebate percentage |
| ppdShippingLevel | String | Prepaid shipping threshold |
| preferredCarrier | String | Dealer’s preferred logistics provider |
| groupAffiliation | Enum | Buying group status |
| notes | Text | Internal pricing notes |

**Representative agency**

| Field | Type | Description |
| :---- | :---- | :---- |
| name | String | Agency name |
| mafsiAreas | String | Comma-separated list of MAFSI IDs |
| agentName | String | Specific representative name |
| contactInfo | String | Cell phone, office phone, email, order email |

# **Part 3\. Manufacturer catalog**

The catalog module lets manufacturers build and maintain their product data on the platform without depending on CSS for every change. Data reaches the catalog through several routes — an uploaded file, data pasted from a spreadsheet, or a form filled in by hand — and passes through a mapping and validation stage before it is committed. The same import wizard is used for the subscriber upload. This part describes the catalog object, the ingestion methods, each step of the wizard, the validation and error reporting, the catalog data model, and the visibility rules that separate what manufacturers, vendors and restaurant clients can see.

Design reference: CSS-MFR, node 34705-106616.

*The technical implementation layer of this module — API endpoints, database tables for catalogs, products, mapping profiles and audit logs, the parsing engine, the migration path and the test plan — is deliberately not reproduced here. It belongs to a technical specification rather than to a description of system behaviour.*

## **3.1 Purpose and business value**

Establish a central, scalable product catalog that manufacturers can maintain themselves, while giving vendors and restaurant clients each their own level of access to it.

**Business value**

| Area | Effect |
| :---- | :---- |
| Operational efficiency | Manual data entry and time to market are reduced through bulk ingestion and assisted field mapping. |
| Data integrity | Validation, versioning and a structured parent-child variation framework keep product data usable. |
| Discovery | Restaurants see technical specifications and media, and can make better-informed purchasing decisions. |
| Multi-tenancy | Role-based access control and data separation keep proprietary information away from parties that should not see it. |

**Functional rules**

| FR-CAT-001 | The catalog module shall serve the manufacturer entity, with vendors holding full purchasing access and restaurant clients a read-only, price-restricted view of the technical catalog. |
| :---- | :---- |
| **FR-CAT-002** | A manufacturer shall be able to upload, validate and maintain its own product data without CSS involvement in routine changes. |

## **3.2 Catalog object, versioning and ownership**

Define what a catalog is as an object, how its history is kept, and how control passes from CSS to the manufacturer.

**Functional rules**

| FR-CAT-003 | A catalog shall carry its owner, its current version and its creation and modification timestamps. |
| :---- | :---- |
| **FR-CAT-004** | The system shall generate version 1.0 when CSS first creates the catalog, and shall increment the version on each manufacturer update. |
| **FR-CAT-005** | Every successful import and every manual edit shall create a new version entry in the catalog history. |
| **FR-CAT-006** | The history shall be available through an audit log view showing the version, the timestamp and the user responsible. |
| **FR-CAT-007** | Every change shall be logged with a clear record of what changed, so that the difference between versions can be read. |
| **FR-CAT-008** | After the handover, the manufacturer’s account shall hold write access to its own catalog and shall be able to add, edit and delete products. |
| **FR-CAT-009** | A manufacturer shall not be able to modify another manufacturer’s catalog, nor to view another manufacturer’s mapping profiles. |

**Acceptance criteria**

| FR-CAT-010 | Every successful import or manual edit generates a new version entry in the catalog history, reachable from the audit log interface. |
| :---- | :---- |
| **FR-CAT-011** | After the handover the manufacturer account has write access to its own catalog, confirmed by a successful login and a data modification. |
| **FR-CAT-012** | All operations are logged with a clear record of what changed. |

## **3.3 Ingestion methods**

Offer several routes into the catalog so that manufacturers are not forced into one working style.

**Methods**

| Method | Detail |
| :---- | :---- |
| File upload | Excel (.xlsx, .xls), CSV, TSV and .txt with tab-separated values; PDF is handled separately — see the exception in section 3.13 |
| Bulk paste | Tabular data pasted directly from a spreadsheet such as Excel or Google Sheets |
| Manual entry | A "New Product" form for creating a single item |

**Functional rules**

| FR-CAT-013 | The bulk paste interface shall identify rows and columns correctly from clipboard data copied out of standard spreadsheet software. |
| :---- | :---- |
| **FR-CAT-014** | A downloadable import template shall be available within the import interface and shall match the schema the system expects. |
| **FR-CAT-015** | A template shall be provided for each catalog type. |

**Acceptance criteria**

| FR-CAT-016 | The system parses and displays data from uploaded .xlsx and .csv files in the mapping interface. |
| :---- | :---- |
| **FR-CAT-017** | The bulk paste interface correctly identifies rows and columns from clipboard data copied from standard spreadsheet software. |
| **FR-CAT-018** | A downloadable import template in Excel or CSV format is available and matches the schema the system requires. |

## **3.4 Import wizard — choosing the import method**

Let the user pick how the data will arrive. The screen appears as a modal or a standalone step once the import is started.

**Screen elements**

| Element | Type | Required | Logic | Validation | Editable |
| :---- | :---- | :---- | :---- | :---- | :---- |
| Title | Label | Required | Displays the text "Choose import method" | N/A | No |
| Upload a file card | Button / card | Optional | Highlighted on hover; shows an icon and the supported formats (CSV, XLS, TXT) | N/A | No |
| Copy and paste card | Button / card | Optional | Highlighted on hover | N/A | No |
| Download .csv template | Button | Optional | Downloads the standard CSV import template | N/A | No |
| Cancel | Button | Required | Closes the import window | N/A | No |
| Continue | Button | Required | Moves to the next step according to the method chosen | Enabled only once a method has been selected | No |

**Functional rules**

| FR-CAT-019 | Selecting a card shall highlight it as active and set the corresponding upload method. |
| :---- | :---- |
| **FR-CAT-020** | Where "Upload a file" is selected, Continue shall open the file upload screen. |
| **FR-CAT-021** | Where "Copy and paste" is selected, Continue shall open the screen for pasting tabular data. |

## **3.5 Import wizard — uploading the file**

Accept the file, report progress, and confirm that it has been parsed before the user moves on.

**Screen elements**

| Element | Type | Required | Logic | Validation | Editable |
| :---- | :---- | :---- | :---- | :---- | :---- |
| Drag and drop area | Dropzone | Required | Accepts a file dragged into the area, or opens the file browser on click | Checks the extension (.csv, .xls, .xlsx, .txt) | No |
| Upload progress indicator | Progress bar | Optional | Shown during processing, with the percentage and the status "Uploading file..." | N/A | No |
| Uploaded file card | Card | Optional | Shown after a successful upload, with the file name, the size and a delete icon | N/A | No |
| Upload status | Icon and label | Optional | Shows a success icon and the message "Successfully uploaded\!" | N/A | No |

**Functional rules**

| FR-CAT-022 | The system shall upload the file to the server and begin parsing it. |
| :---- | :---- |
| **FR-CAT-023** | On success the uploaded file card shall be displayed and the Continue button shall become active. |
| **FR-CAT-024** | Continue shall then open the column matching screen. |

## **3.6 Import wizard — matching column headers**

Align the columns of the source file with the fields of the system. This is the step where an incorrect decision costs the most, so the system suggests mappings and lets them be saved for reuse.

**Screen elements**

| Element | Type | Required | Logic | Validation | Editable |
| :---- | :---- | :---- | :---- | :---- | :---- |
| "Your file headers" block | List | Required | Displays the headers detected in the uploaded file, on the left | Read-only | No |
| "Select corresponding headers" block | Dropdowns | Required | A dropdown beside each file header, mapping it to a system field | N/A | Yes |
| Validation error indicator | Icon | Optional | Shown where a mandatory system field is unmapped or the data type does not match | N/A | No |
| Data preview | Table | Optional | Shows the first several rows of the file for reference, on desktop | N/A | No |

**Functional rules**

| FR-CAT-025 | The system shall attempt to map fields automatically using fuzzy matching, so that "Prod Name" is recognised as "Product Name". |
| :---- | :---- |
| **FR-CAT-026** | The system shall suggest mappings from the similarity of header names and from historical mapping patterns. |
| **FR-CAT-027** | The system shall provide at least one recommended mapping for every standard system field, based on the headers of the uploaded file. |
| **FR-CAT-028** | The user shall be able to override any suggested mapping manually through a dropdown or drag and drop. |
| **FR-CAT-029** | Columns that cannot be matched shall be marked "Not recognized" and shall be excluded from the import unless the user maps them by hand. |
| **FR-CAT-030** | Selecting "Not recognized" or "Ignore" shall exclude that column from the import. |
| **FR-CAT-031** | The user shall be able to save a mapping configuration as a named profile and to apply it to a later upload, bypassing manual mapping. |
| **FR-CAT-032** | The user shall be able to choose one of three import modes before the file is processed: create new records, update existing records by identifier, or create or update as required. |
| **FR-CAT-033** | The system shall be able to extract product attributes from a description or notes column through text analysis, and shall display the extracted technical detail in the mapping preview. |
| **FR-CAT-034** | Save on the mapping screen shall trigger validation. Where mandatory values are missing the "Add missing information" modal shall open; where the file structure is invalid the "Format your file" modal shall open; where validation passes the import shall complete and the user shall be taken to the catalog or subscriber list. |

**Acceptance criteria**

| FR-CAT-035 | The system suggests field mappings automatically from header name similarity and from historical mapping patterns. |
| :---- | :---- |
| **FR-CAT-036** | The mapping interface allows any suggested mapping to be overridden manually. |
| **FR-CAT-037** | A mapping configuration can be saved as a profile and reapplied to a new file with full field alignment. |
| **FR-CAT-038** | The user can select one of the three import modes before the file is processed. |
| **FR-CAT-039** | The interface displays attributes extracted from descriptions in the mapping preview. |

## **3.7 Import wizard — adding missing information**

Let the user fill in mandatory values that the source file does not contain, without going back and editing the file itself.

**Screen elements**

| Element | Type | Required | Logic | Validation | Editable |
| :---- | :---- | :---- | :---- | :---- | :---- |
| Title | Label | Required | Displays the text "Add missing information" | N/A | No |
| Row selection checkbox | Checkbox | Optional | Selects an individual row, or all rows for a bulk update | N/A | Yes |
| Row-level input | Input | Optional | Enters a value for one record | Depends on the field type | Yes |
| Global input | Input | Optional | Once a value is entered and applied, fills every selected row with it | N/A | Yes |
| Save | Button | Required | Applies the entered values to the import data set and closes the modal | Mandatory field validation | No |

**Functional rules**

| FR-CAT-040 | The modal shall display only the rows affected by the missing values. |
| :---- | :---- |
| **FR-CAT-041** | Values entered here shall apply to the import data set only and shall not modify the original source file. |
| **FR-CAT-042** | The orange action control on the mapping screen shall open this modal so that missing values can be filled in bulk. |

## **3.8 Validation and error reporting**

Stop unusable data before it reaches the production database, and tell the user precisely what is wrong.

**Functional rules**

| FR-CAT-043 | Validation shall run before any data is committed. |
| :---- | :---- |
| **FR-CAT-044** | The system shall flag every row that holds a missing mandatory field or a data type mismatch, such as text in a numeric price field. |
| **FR-CAT-045** | The system shall prevent the import of records that fail those checks. |
| **FR-CAT-046** | Validation shall cover business rules, data types and relationships, not data types alone. |
| **FR-CAT-047** | Parent-child validation shall identify and block an import in which child variations carry no valid parent reference. |
| **FR-CAT-048** | The validation grid shall highlight errors at cell level and shall explain the rule that was broken. |
| **FR-CAT-049** | The user shall be able to correct values inline in the validation grid. |
| **FR-CAT-050** | The system shall generate a downloadable error report in CSV or Excel format listing the row number, the field in error and a description of the violation. |
| **FR-CAT-051** | Automated data cleaning is not part of this scope; the user corrects the data from the report. |

**Acceptance criteria**

| FR-CAT-052 | The validation step flags and prevents the import of records with missing mandatory fields or data type mismatches. |
| :---- | :---- |
| **FR-CAT-053** | The validation engine flags every row containing a missing required field or a data type mismatch. |
| **FR-CAT-054** | Parent-child validation blocks imports in which child variations lack a valid parent reference. |
| **FR-CAT-055** | The validation step identifies and displays at least three kinds of error: a missing required field, an invalid data type and a duplicate SKU. |
| **FR-CAT-056** | The system generates a downloadable error report listing the row number, the field in error and the specific violation. |

## **3.9 Manual entry**

Allow a single product to be created or maintained through a form rather than an import.

**Functional rules**

| FR-CAT-057 | The "New Product" form shall allow a single item to be created. |
| :---- | :---- |
| **FR-CAT-058** | The form shall support the full set of operations on one product object: creation, reading, update and deletion. |
| **FR-CAT-059** | Required fields in the form shall prevent submission while they are empty. |
| **FR-CAT-060** | The form shall apply the same constraints as the catalog data model, including character limits and data types. |
| **FR-CAT-061** | A manual save shall update the version history and the audit log immediately, in the same way as an import. |

## **3.10 Catalog data model**

Define the fields a catalog product carries, which of them are mandatory, and the limits that validation enforces. The set follows the reference sheet supplied by the client.

**Product fields**

| Field | Type | Required | Notes |
| :---- | :---- | :---- | :---- |
| CSS Customer Number | Text | Required | Customer identifier |
| Company Name | Text | Required | — |
| Model Number | Text | Required | Unique per manufacturer |
| Product Name | Text | Required | — |
| List Price | Decimal | Required | Two decimal places |
| Product Short Description | Text | Required | Maximum 200 characters |
| Product Long Description | Text | Required | Maximum 5,000 characters |
| Certifications | Text | Optional | — |
| Search Words | Text | Optional | — |
| Sell Unit UPC | Text | Optional | — |
| Inner Pack | Text | Optional | — |
| Master Case UPC | Text | Optional | — |
| Min Sell Unit Qty | Integer | Required | — |
| Master Case Unit Qty | Integer | Optional | — |
| Pallet Qty | Integer | Optional | — |
| Product Length | Decimal | Required | — |
| Product Width | Decimal | Required | — |
| Product Depth | Decimal | Required | — |
| Case Length | Decimal | Optional | — |
| Case Width | Decimal | Optional | — |
| Case Depth | Decimal | Optional | — |
| Case Cubic Inch | Decimal | Optional | — |
| CBM | Decimal | Optional | Four decimal places |
| Unit Weight | Text | Required | For example "25LB" |
| Case Weight | Decimal | Optional | — |
| Freight | Text | Optional | — |
| Country of Origin | Text | Optional | — |
| Harmonized Tariff Code | Text | Optional | — |
| Main Image 1 | Text | Required | Filename reference |
| Product Image 2 | Text | Optional | Filename reference |
| Pack Image 3 (inner) | Text | Optional | Filename reference |
| Pack Image 4 (master) | Text | Optional | Filename reference |
| Item Info Main | Text | Optional | PDF filename |
| Item Info Plus | Text | Optional | PDF filename |

**Functional rules**

| FR-CAT-062 | Where a required field is missing or empty in an imported row, the import shall report the specific row and column to the user. |
| :---- | :---- |
| **FR-CAT-063** | The list price and the dimension fields shall be validated as numbers. |
| **FR-CAT-064** | The character limits shall be enforced during the import: 200 characters for the short description and 5,000 for the long description. |
| **FR-CAT-065** | A product shall be identified by the combination of the CSS customer number and the model number. Where a record already exists under that combination it shall be updated; otherwise a new record shall be created. |

**Acceptance criteria**

| FR-CAT-066 | The import fails with a clear error message where the model number, the list price or the main image is missing. |
| :---- | :---- |
| **FR-CAT-067** | The import succeeds where optional fields such as certifications or pallet quantity are empty. |
| **FR-CAT-068** | Character limits for the short description (200) and the long description (5,000) are enforced during the import. |
| **FR-CAT-069** | Product updates do not create duplicate entries for the same model number under the same CSS customer number. |

## **3.11 Business rules**

The constraints that apply to every import, whichever route the data takes.

**BR-02 — mandatory fields, catalog upload**

| Field | Requirement |
| :---- | :---- |
| Product Name / Description | Mandatory |
| SKU / ID | Mandatory, and unique within the company catalog |
| Price | Numeric, greater than zero |
| UoM (unit of measure) | Must match the system unit of measure dictionary |

**BR-03 — mandatory fields, subscriber upload**

| Field | Requirement |
| :---- | :---- |
| Subscriber Name | Mandatory |
| External ID | Mandatory, for system integration |

**Functional rules**

| FR-CAT-070 | BR-01. The supported file formats are .csv, .xls, .xlsx and .txt with tab-separated values. |
| :---- | :---- |
| **FR-CAT-071** | BR-04. The system shall attempt automatic mapping through fuzzy matching, and shall mark unmapped columns "Not recognized" and exclude them unless the user maps them. |
| **FR-CAT-072** | BR-05. The maximum file size is 25 MB, subject to confirmation from the architecture, and the maximum is 10,000 records per import. |
| **FR-CAT-073** | One import batch shall carry data for one entity type only. |

## **3.12 Exception handling**

How the system behaves when the file, the data or the user does something the happy path does not cover.

**Exception cases**

| Case | Situation | System behaviour |
| :---- | :---- | :---- |
| H-1 | A file with an incompatible structure is uploaded — merged Excel cells, or missing headers | The "Please, format your file" modal is displayed with the message "We cannot proceed with your file structure as it is conflicting with our database structure." The available actions are "Format File", which attempts automatic formatting, and Cancel, which ends the process. |
| H-2 | Data type errors — a price entered as "10 USD" rather than 10, or duplicate identifiers | A validation indicator is displayed beside the fields in question, with a tooltip giving the detail, for example "Invalid number format". The import cannot proceed until the issues are resolved. |
| H-3 | The uploaded file holds no data | A notification reports "File is empty" immediately after the upload, and the Continue button stays disabled. |
| H-4 | The user cancels during column mapping | A confirmation asks "Are you sure? All progress will be lost." On confirmation the user returns to the catalog or subscriber list, the imported data is discarded and no records are created. |
| PDF | A PDF is uploaded, an invoice for example | The system reports "We detected that you have uploaded invoices in PDF format" and explains that setting up a product list from a PDF can take up to five days. The request is passed to a manual back-office process and the automated import is cancelled. |

**Functional rules**

| FR-CAT-074 | Where invalid rows are found, the current assumption is that the import is blocked and the data is corrected through the "Add missing information" modal. Skipping invalid rows instead requires confirmation from the business. |
| :---- | :---- |

## **3.13 Visibility and access control**

Keep each party to the data it is entitled to see.

**Functional rules**

| FR-CAT-075 | Manufacturers shall hold write access to their own catalog only. |
| :---- | :---- |
| **FR-CAT-076** | Vendors shall have full purchasing access to the catalog. |
| **FR-CAT-077** | Restaurant clients shall have a read-only view of the technical catalog, with pricing restricted. |
| **FR-CAT-078** | Mapping profiles shall be visible only to the manufacturer that owns them. |

# **Part 4\. Admin panel**

The admin panel gives system administrators a register of every business entity in the system, a separate view of paying subscribers, a company card for detailed management, bulk operations across records, and a wizard for importing companies in bulk. This part describes the master database and the subscriber list, the behaviour shared by both tables, the bulk actions, the company card and its four tabs, the client creation modal, the import wizard, and the validation applied when a company type is changed.

Design reference: CSS Admin, node 1-43218; CSS-Dealer, node 39459-63897; CSS Admin, node 10-29624.

*This part replaces the earlier admin panel documentation in full. Several points that were previously contradictory are now settled: the subscriber status vocabulary, the client creation form, and the deletion rules. Where the earlier material described billing automation — payment reminders, automatic renewal on payment, revenue reporting — that behaviour is not part of the specification below and is not implemented; payment data is entered by hand.*

## **4.1 Master database table**

Display every business entity in the system — manufacturers, vendors and F\&B clients — including both subscribers and companies that have never subscribed.

**Interface**

* Entity types are switched through the global sidebar: All, Manufacturers, Vendors, F\&B Clients. Each is a separate page with its own URL, and the selected section is not remembered between sessions.

* Header: the page title (Master Database, or the name of the current section) and the Upload button, which starts the import wizard.

* Toolbar: Edit for bulk editing, Merge for merging companies of the same type, and Delete.

**Columns**

| \# | Column | Data type | Example |
| :---- | :---- | :---- | :---- |
| 1 | Checkbox | — | — |
| 2 | Company Name | Text | Giovanni |
| 3 | Company Type | Text | Vendor |
| 4 | Parent Company | Text | Hard Rock Cafe |
| 5 | Subscriber Status | Pill | Active / Expired / Not Subscribed |
| 6 | Number of Licences | Number | 3 |
| 7 | Number of Locations | Number | 1 |
| 8 | Annual / Monthly | Text | $120/Yearly |
| 9 | Renewed Frequency | Text | 1 Year |

**Functional rules**

| FR-ADM-001 | Subscriber status shall be rendered as a pill: ACTIVE in green, EXPIRED in red and NOT SUBSCRIBED in grey. |
| :---- | :---- |
| **FR-ADM-002** | For records with NOT SUBSCRIBED status, the columns Number of Licences, Annual / Monthly and Renewed Frequency shall display a dash. |
| **FR-ADM-003** | The master database shall include both subscribers and companies that hold no subscription. |

## **4.2 Subscribers table**

Display subscribers only — companies whose status is ACTIVE or EXPIRED — on a dedicated page reached from the global sidebar.

**Interface**

* Header: the title "Subscribers" and the "+ Add new" button, which opens the client creation modal. Where the current administrator has no right to create a client the button is hidden; role-based access control is to be implemented later.

**Columns**

| \# | Column | Data type | Example |
| :---- | :---- | :---- | :---- |
| 1 | Checkbox | — | — |
| 2 | Subscriber Name | Text | Hard Rock Cafe |
| 3 | Subscriber Status | Pill | Active / Expired |
| 4 | Number of Licences | Number | 12 |
| 5 | Available Seats | Number | 3 |
| 6 | Invitation Code Status | Pill | Used / Unused |

**Functional rules**

| FR-ADM-004 | Subscriber status shall be rendered as a pill: ACTIVE in green and EXPIRED in red. NOT SUBSCRIBED does not occur in this table by definition. |
| :---- | :---- |
| **FR-ADM-005** | Invitation code status shall be rendered as a pill: USED in green and UNUSED in red. |

## **4.3 Behaviour shared by both tables**

Define the sorting, selection, pagination, search and empty-state behaviour that applies to the master database and the subscriber table alike.

**Functional rules**

| FR-ADM-006 | Sorting shall be available on every data column except the checkbox column. |
| :---- | :---- |
| **FR-ADM-007** | Sorting shall offer ascending and descending order only; there is no reset state. |
| **FR-ADM-008** | Direction icons shall follow the convention of the interface library in use — an upward arrow for ascending numeric order, Z→A for text. |
| **FR-ADM-009** | Sorting by subscriber status shall be alphabetical. |
| **FR-ADM-010** | Multi-column sorting shall not be supported. |
| **FR-ADM-011** | Sorting shall revert to the default order when a search query is entered. |
| **FR-ADM-012** | The header checkbox shall select or clear every record on the current page. |
| **FR-ADM-013** | Where only some rows on the page are selected, the header checkbox shall display an indeterminate state: checked, with a minus in place of the tick. |
| **FR-ADM-014** | The selection shall be cleared when the user moves to another page. |
| **FR-ADM-015** | Pagination controls shall sit below the table and shall offer previous and next page, page numbers, and an ellipsis for hidden ranges. |
| **FR-ADM-016** | The page size selector shall offer 10, 20, 50 and 100 records, defaulting to 10\. |
| **FR-ADM-017** | A local search field with the placeholder "Search..." shall sit above the table and shall filter in real time from the first character entered. |
| **FR-ADM-018** | In the master database the search shall match Company Name; in the subscriber table it shall match Subscriber Name. |
| **FR-ADM-019** | Highlighting of matches is not required. |
| **FR-ADM-020** | While data is loading, the table shall display a skeleton placeholder for its rows. |
| **FR-ADM-021** | Where the master database holds no data, the page shall display an illustration, the message "No companies yet" and an Upload call to action. |
| **FR-ADM-022** | Where the subscriber table holds no data, the page shall display an illustration, the message "No subscribers yet" and an "+ Add new" call to action. |
| **FR-ADM-023** | Where a search returns nothing, the master database shall display "No companies found matching '\[query\]'" and the subscriber table "No subscribers found matching '\[query\]'". |
| **FR-ADM-024** | Every notification that reports a record count shall exist in a singular and a plural form: "Successfully updated 1 company" / "Successfully updated N companies"; "1 company deleted" / "N companies deleted"; "Deleted 1 company, M skipped" / "Deleted N companies, M skipped"; "Merged 1 company into \[Master Company Name\]" / "Merged N companies into \[Master Company Name\]". |

## **4.4 Bulk actions — edit**

Let the administrator overwrite attributes across one or more selected records. The bulk buttons appear in the toolbar above the table once at least one record is selected.

**Interface**

* Edit is available from one selected record upwards, and opens the "You are editing" modal.

* The modal behaves identically whether one record or many are selected.

**Modal fields**

| Field | Type | Values |
| :---- | :---- | :---- |
| Company Type | Dropdown | Manufacturer / Vendor / F\&B Client; one value only |
| Parent Company | Dropdown | Every company in the system except those being edited; a company cannot become its own parent |
| Number of Licences | Numeric input | — |
| Subscriber Status | Dropdown | Active / Expired / Not Subscribed |

**Functional rules**

| FR-ADM-025 | All fields shall be empty when the modal opens. |
| :---- | :---- |
| **FR-ADM-026** | A field that has been filled in shall overwrite that value on every selected record. |
| **FR-ADM-027** | A field left empty shall be ignored, and the existing values shall not be touched. |
| **FR-ADM-028** | Where companies of different types are selected, the Parent Company dropdown remains active and lists every company in the database except those being edited. |
| **FR-ADM-029** | Where the administrator attempts to change Parent Company across companies of different types and clicks Apply, the system shall display "You have selected companies of different types. Please set a single company type to proceed." and shall block saving until a single value is chosen in the Company Type field. |
| **FR-ADM-030** | Where only other fields are being changed — the licence count, for example — the change shall be permitted even though the selection holds several company types. |
| **FR-ADM-031** | Apply shall be disabled while every field in the modal is empty, and active otherwise. |
| **FR-ADM-032** | Cancel shall close the modal without applying anything. |
| **FR-ADM-033** | After Apply the modal shall close, a confirmation shall be shown ("Successfully updated N companies", in the correct singular or plural form), the table shall refresh and the selection shall be cleared. |
| **FR-ADM-034** | The same modal with the same four fields shall be used in the subscriber table, because both tables operate on one database, even though some of those fields are not shown as columns there. |
| **FR-ADM-035** | Changing the company type from the subscriber table is permitted, and the company remains in the subscriber table. |
| **FR-ADM-036** | Setting the subscriber status to NOT SUBSCRIBED from the subscriber table is permitted, to allow an administrator to correct a mistake. The company then disappears from the subscriber table and remains in the master database only. |

**Edge cases and error handling**

| FR-ADM-037 | Where the selection includes a company that has subsidiaries outside the current selection, a pop-up shall be displayed for each such parent company in turn, titled "Change subsidiary type?" and reading "You have changed the type of \[Parent Company Name\]. This company has \[N\] subsidiaries that are not in your selection. What should happen with them?", offering "Detach all subsidiaries", under which the subsidiaries keep their own type but lose the link to the parent, "Change type for all subsidiaries to \[New Type\]", and Cancel. |
| :---- | :---- |

## **4.5 Bulk actions — merge**

Combine several companies of the same type into one master record, resolving the differences between them field by field.

**Interface**

* Merge is hidden while a single record is selected and becomes available from two records upwards, whatever their company type.

* The "Merge Companies" modal carries the title and a close control, the explanation "The selected companies will be merged into one master company. Data from the other companies will be combined into the master record, and the merged companies will be deleted.", the "Chosen companies" accordion and the "Choose master company" list.

* Collapsed, the accordion shows the number of selected companies; expanded, it lists them as chips, each with a "×" that removes that company from the scope of the merge.

* The "Choose master company" block is a vertical list of the selected companies with radio buttons, showing the company name and address on each row.

**Functional rules**

| FR-ADM-038 | Where records of different company types are selected, clicking Merge shall open an error modal reading "Merge can only be performed for companies of the same type. Please edit the data and return to merge.", with a Cancel button that returns the user to the table. |
| :---- | :---- |
| **FR-ADM-039** | Where every selected record shares one company type, the "Merge Companies" modal shall open. |
| **FR-ADM-040** | Where the removal of chips leaves a single company, the Apply button shall be blocked. |
| **FR-ADM-041** | Where the user removes the company that had been chosen as master, the master selection shall be cleared and must be made again. |
| **FR-ADM-042** | The user must select exactly one master company. |
| **FR-ADM-043** | After Apply the system shall check the subordinate companies for exact duplicates. Where duplicates are found, the "Resolve Data Conflicts" modal shall offer "Skip duplicates" and "Merge anyway", above the explanation "Some of the selected companies appear to be duplicates. Choose how to proceed." |
| **FR-ADM-044** | Once the duplicate check has passed, the system shall compare the subordinate companies against the master across every field of the company card, not only the fields shown in the table. |
| **FR-ADM-045** | Where differences exist, a guided conflict resolution interface shall present every competing value for each conflicting field, with one row per subordinate company. |
| **FR-ADM-046** | For single-value fields — subscriber status, number of licences, annual or monthly fee, renewal frequency, address and parent company — the options shall be Replace, which takes the subordinate value, and Ignore or Delete, which keeps the master value. |
| **FR-ADM-047** | For multi-value fields — phone numbers, email addresses and contact persons — the options shall be Add, which appends the value to the master record, Replace and Ignore or Delete. |
| **FR-ADM-048** | Company type shall not be part of conflict resolution, because it is identical across the selection; that check happens before the merge modal opens. |
| **FR-ADM-049** | Subscriber status shall be resolved by the user, and the status of the master record may change as a result. |
| **FR-ADM-050** | Available seats shall not be part of conflict resolution. It is a calculated field and is recalculated after the merge from the resulting licence count and the seats in use. |
| **FR-ADM-051** | Where a contact person is added, the system shall check it against the existing contacts first. A duplicate means every field of the contact matches; where only some fields match — the same name and email but different phone numbers, for example — the contact is not a duplicate and shall be added. |
| **FR-ADM-052** | Subordinate companies with ACTIVE or EXPIRED status shall be deleted as part of a merge. This is an exception to the general rule that protected companies cannot be deleted. |
| **FR-ADM-053** | On completion the master company shall be updated with the resolved data, the subordinate records shall be deleted, the user shall remain on the page from which the merge was started, and a confirmation shall report "Merged N companies into \[Master Company Name\]" in the correct singular or plural form. |

## **4.6 Bulk actions — delete**

Delete selected companies where business rules allow it, and explain clearly which records could not be deleted and why.

**Functional rules**

| FR-ADM-054 | The Delete button shall be shown in the master database only. It shall be hidden in the subscriber table, because every record there holds a protected status and subscribers cannot be deleted. |
| :---- | :---- |
| **FR-ADM-055** | The system shall check the status of every selected record before deleting anything. |
| **FR-ADM-056** | Where every selected record is deletable — that is, NOT SUBSCRIBED — a confirmation pop-up shall ask "Are you sure you want to delete N selected items?" with Cancel and Confirm. On confirmation the records shall be deleted and a message shall report "N companies deleted" in the correct singular or plural form. |
| **FR-ADM-057** | Where every selected record is protected — ACTIVE or EXPIRED — a red banner shall be displayed above the table reading "It is prohibited to delete a company if it is registered in the system (is a subscriber/pays).", a red triangle icon shall appear beside each protected name in the Company Name column, and nothing shall be deleted. |
| **FR-ADM-058** | The banner shall close when the user clicks its "×", and shall close automatically once the protected records are deselected. |
| **FR-ADM-059** | Where the selection is mixed, a pop-up shall report "N companies will be deleted, M cannot be deleted (registered as subscribers)." above a list of every selected company annotated with its status, with the buttons Cancel and "Delete N". |
| **FR-ADM-060** | Clicking "Delete N" shall delete only the NOT SUBSCRIBED records and leave the protected ones untouched, then report "Deleted N companies, M skipped" in the correct singular or plural form. |
| **FR-ADM-061** | Where records remain on the current page after a deletion or a merge, the user shall stay on that page, which is redrawn with the remaining records topped up from the following page. |
| **FR-ADM-062** | Where no records remain on the current page and no further pages exist, the user shall be returned to the nearest page that holds data. |
| **FR-ADM-063** | Where the table holds no data at all, the empty state shall be displayed. |

## **4.7 Company card — Information tab**

Give a single page for viewing and managing one company. The page is identical whether it is opened from the master database or from the subscriber table.

**Interface**

* Entry points: clicking a company row in the master database, or in the subscriber table.

* Breadcrumbs: "Master Database \> \[Type\] \> \[Company Name\]" from the master database, and "Subscribers \> \[Type or All\] \> \[Company Name\]" from the subscriber table.

* Header: the company name and the company ID from the database, for example \#47851, which is always displayed and never editable.

* The page holds four tabs: Information and Subscription, which are editable, and Licenses and History, which are read-only. Discard and Save sit at the foot of the editable tabs and apply to the current tab only.

**Sections and fields**

| Section | Fields |
| :---- | :---- |
| Information | Type (dropdown: Manufacturer / Vendor / F\&B Client); Client Name; Email, the company’s primary address; Phone Number as a composite of country code, base number and an optional extension; Address |
| Accounting Payable | Name; Email; Phone Number, composed as above with an optional extension |
| Contact Person | A grid of contact cards, each showing name, email and phone with edit and delete icons, plus a "+ Add New" control |
| Hierarchy | Parent Company as a card showing name, email and phone with an edit icon; Subsidiaries as a list of cards, each with an edit icon |

**Functional rules**

| FR-ADM-064 | The "+ Add New Phone Number" control shall add a further row holding the same three fields. |
| :---- | :---- |
| **FR-ADM-065** | Each phone row shall carry a delete icon, and any number may be removed, including the last one. |
| **FR-ADM-066** | The "+ Add New" control in the Contact Person section shall open the Add Contact modal, which holds first name, last name, email and phone number with an optional extension, and Cancel and Save buttons. |
| **FR-ADM-067** | The edit icon on a contact card shall open the same modal with the values pre-filled. |
| **FR-ADM-068** | Deleting a contact shall raise a confirmation pop-up titled "Delete this contact?" with Cancel and Delete. Even the last contact may be deleted, because the core company details remain in the Information section. |
| **FR-ADM-069** | The edit icon on the parent company card or a subsidiary card shall open that company’s page in a new browser tab. |
| **FR-ADM-070** | The parent company cannot be changed from this page; it is changed through bulk edit or through a merge. |
| **FR-ADM-071** | New subsidiaries cannot be created from this page; the section displays existing relationships only. |

**Edge cases and error handling**

| FR-ADM-072 | Where the administrator changes the type of a company that has subsidiaries and clicks Save, a pop-up titled "Change subsidiary type?" shall read "You have changed the type of \[Parent Company Name\]. This company has \[N\] subsidiaries. What should happen with them?" and offer "Detach all subsidiaries", under which the subsidiaries keep their type but lose the link to the parent, "Change type for all subsidiaries to \[New Type\]", which sets them to the parent’s new type, and Cancel. |
| :---- | :---- |

## **4.8 Company card — Subscription tab**

Hold the subscription and licence data for the company, issue the invitation code, and calculate the subscription dates.

**Fields**

| Field | Type | Behaviour |
| :---- | :---- | :---- |
| Invitation Code Status | Pill (Used / Unused) | Read-only |
| Invitation Code | Text | Read-only, with a copy icon |
| License | Numeric input | Editable |
| Number of used seats | Number | Read-only, calculated |
| Number of remaining seats | Number | Read-only; licence total minus used seats |
| License Fee | Amount with a radio (Annually / Monthly) | Editable |
| Paid Amount | Amount | Editable |
| Payment Method | Dropdown | Editable |
| Received Date | Date picker | Editable |
| License Activation Date | Date picker | Editable |
| License Expiration Date | Date picker | Editable |
| Notes | Text area, no character limit | Editable |

**Interaction logic**

**Invitation code control**

* Where no code has yet been generated — a NOT SUBSCRIBED company without a code — the button reads "Generate and Send Invitation Code". Clicking it generates a unique code, sends it to the company’s primary email from the Information section, shows the code in the Invitation Code field with status Unused, and confirms with "Invitation code generated and sent successfully".

* Where a code exists and its status is Unused, the button reads "Send Invitation Code" and resends the code to the same address, confirming with "Invitation code sent successfully".

* Where the status is Used, the button is hidden.

* Sending is rate-limited to once every five minutes. After a send the button is disabled and shows a countdown, "Send again in 4:32", and becomes active again when the timer runs out.

* Where the administrator has changed the primary email on the Information tab and saved it, the next send goes to the new address.

**Payment method**

* The dropdown offers Cash, Check, Wire, Credit Card, Zelle, Apple Pay, PayPal, ACH and Stripe, plus a "+ Add new method" entry.

* "+ Add new method" opens a small modal with a name field. Once saved, the new method is stored globally and becomes available to every administrator in the system.

**Date calculation**

* Entering the received date sets the activation date to the same value and the expiration date to the activation date plus the period selected on the radio — a year or a month.

* Entering the activation date on its own recalculates the expiration date only.

* Where the administrator edits the expiration date by hand, that value is kept and the automatic formula no longer applies.

**Functional rules**

| FR-ADM-073 | The activation date shall be on or after the received date. |
| :---- | :---- |
| **FR-ADM-074** | The expiration date shall be later than the activation date. |
| **FR-ADM-075** | Dates in the past are permitted. |
| **FR-ADM-076** | Where a date rule is broken, an inline error shall be displayed below the field and saving shall be blocked. |
| **FR-ADM-077** | Where the licence count is reduced below the number of seats in use, the change shall be written to the database immediately and the message "The new license count will take effect after the subscription expires on \[Expiration Date\]." shall be displayed. The reduction takes effect only after the expiration date, and until then the remaining seats field continues to show the previous value. |
| **FR-ADM-078** | Where the new licence count still covers the seats in use, the change shall be applied immediately and without a message. |
| **FR-ADM-079** | For a NOT SUBSCRIBED company every field on this tab shall be empty but editable, and the "Generate and Send Invitation Code" button shall be shown. |
| **FR-ADM-080** | An administrator may complete and save the whole tab for a NOT SUBSCRIBED company; the data is stored as the basis of a future subscription and the company keeps the NOT SUBSCRIBED status. |
| **FR-ADM-081** | A subscription becomes active only when the client registers using the invitation code. Filling in the Subscription tab does not activate it, even where the received date has already passed. |
| **FR-ADM-082** | An administrator may also move a company to ACTIVE manually through bulk edit, to cover human error or an unusual case. |

**Edge cases and error handling**

| FR-ADM-083 | Where the administrator switches the radio between Annually and Monthly on a subscription that is already running, a pop-up titled "Change billing period" shall read "There are \[N\] days left until the current expiration date. How do you want to apply the new billing period?" and offer "Apply now (recalculate dates)", which recalculates the expiration date from the activation date under the new formula, "Apply after current period ends", under which the current subscription runs to its expiration date and the new period starts afterwards, and Cancel. |
| :---- | :---- |
| **FR-ADM-084** | When the client registers using the invitation code, the company takes the ACTIVE status, the code status becomes Used, the activation date is overwritten with the date of the actual registration — so an administrator entry of 01.06.2026 becomes 15.05.2026 where the client activated on that date — and the expiration date is recalculated from the new activation date. |
| **FR-ADM-085** | On registration the company remains in the master database and additionally appears in the subscriber table, and an email is sent automatically to the administrator: "Company \[Name\] has registered. Please verify the subscription dates." |

## **4.9 Company card — Licenses and History tabs**

Record the audit trail: licence events on one tab and every other change on the other.

**Licenses tab — columns**

| Column | Type |
| :---- | :---- |
| Licence Login ID | Text — the unique identifier of the subscription or user in the system |
| Licence Status | Pill (Active / Expired) |
| Event | Text |
| Activation Date | Date |
| Expiration Date | Date |
| Admin Name | Text |
| Admin Role | Text |

**History tab — columns**

| Column | Type |
| :---- | :---- |
| Event ID | Text |
| Event | Text |
| Date | Date and time |
| Admin Name | Text |
| Admin Role | Text |

**Functional rules**

| FR-ADM-086 | The Event column on the Licenses tab shall carry one of: Created, Renewed, Expired, Deleted, Seats added, Seats removed, Renewal date changed, Activation date changed, Expiration date changed. |
| :---- | :---- |
| **FR-ADM-087** | On renewal a new row shall be created with the same Licence Login ID, new dates and the event Renewed. |
| **FR-ADM-088** | Where a completely new subscription is created after a previous one has expired and a new activation has taken place, a new Licence Login ID shall be generated. |
| **FR-ADM-089** | The Licenses tab shall support sorting on every column, ascending and descending. It has no search. Pagination offers 10, 20, 50 and 100 rows, defaulting to 10\. Every row is read-only and carries no row-level action. |
| **FR-ADM-090** | The History tab shall log every change made on the Information tab — address, email, phone, contact persons, hierarchy and type. |
| **FR-ADM-091** | The History tab shall log every operation performed on the company from outside the card, namely bulk edit and merge. |
| **FR-ADM-092** | The History tab shall log the changes on the Subscription tab that do not relate to the licence directly: notes, payment method, paid amount, received date and licence fee. |
| **FR-ADM-093** | Licence events — created, renewed, expired, deleted, seats added, seats removed, and changes to the activation, expiration and renewal dates — shall be logged on the Licenses tab rather than in History. |
| **FR-ADM-094** | The History search field shall carry the placeholder "Search...", shall match the Event ID, Event and Admin Name fields at once, and shall filter in real time from the first character entered. |
| **FR-ADM-095** | The History tab shall provide a date range of two pickers in MM/DD/YYYY format that filter the table by event date, a per-page selector offering 10, 20, 50 and 100 rows with a default of 10, an "Export as" dropdown offering Excel and PDF, and a print control. |
| **FR-ADM-096** | An export shall contain the current filtered selection, taking the search and the date range into account, and shall be delivered through the browser download mechanism rather than by email. |
| **FR-ADM-097** | The History tab shall support sorting on every column, ascending and descending. |

**Edge cases and error handling**

| FR-ADM-098 | Where the user attempts to leave a tab that holds unsaved changes — by switching tabs, clicking in the sidebar, clicking a breadcrumb, closing the browser tab or opening another company from a side list — a single pop-up shall be displayed, titled "Unsaved changes", reading "You have unsaved changes. Save or discard?" and offering Save and Discard. |
| :---- | :---- |

## **4.10 Adding a new client**

Create a company record and issue an invitation code so that the client can register. Reached from "+ Add new" in the subscriber table.

**Modal fields**

| Field | Required | Type |
| :---- | :---- | :---- |
| Type \* | Required | Dropdown: Manufacturer / Vendor / F\&B Client |
| Client Name \* | Required | Text input |
| Phone Number \* | Required | Country code, base number and an optional extension; one number only, with no option to add another |
| Email \* | Required | Text input |
| Address \* | Required | Text input |
| Number of License Seats | Optional | Numeric input |
| Invitation Code | — | Read-only, with a copy icon |

**Functional rules**

| FR-ADM-099 | The Invitation Code field shall be empty when the modal opens, and the code shall be generated only when Send Code is clicked. |
| :---- | :---- |
| **FR-ADM-100** | Where the administrator clicks Cancel without sending, no code is generated; nothing is consumed, because no code was ever created. |
| **FR-ADM-101** | The copy icon shall copy the code to the clipboard and confirm with "Copied". |
| **FR-ADM-102** | Send Code shall validate every required field: type, client name, phone number, email and address. |
| **FR-ADM-103** | The email address shall be checked against the system for duplicates. Where it already exists, the inline error "A client with this email already exists in the system." shall be displayed below the field and saving shall be blocked. |
| **FR-ADM-104** | Once validation passes, the system shall generate a unique invitation code, create the company with NOT SUBSCRIBED status, send the code to the address given, close the modal and confirm with "Invitation code sent successfully". |
| **FR-ADM-105** | Where every field is empty, Cancel shall close the modal without comment. |
| **FR-ADM-106** | Where at least one field has been filled in, Cancel shall raise a warning titled "Discard changes?" reading "You have unsaved data. Are you sure you want to close?" with the buttons Stay and Discard. |
| **FR-ADM-107** | The email shall be validated for format as well as for duplication. |
| **FR-ADM-108** | The phone number shall be validated against the format of the selected country code. |
| **FR-ADM-109** | Where the number of licence seats is supplied, it shall be a positive integer greater than zero. |
| **FR-ADM-110** | When the client activates the code by registering, the status changes to ACTIVE and the code status to Used, and the administrator receives the automatic email "Company \[Name\] has registered. Please verify the subscription dates." |

## **4.11 Bulk import of companies**

Load companies into the master database in bulk from a file or pasted data, with column mapping and duplicate handling. Reached from the Upload button in the master database header, which is available on every page of the section.

**Interface**

* Step 1 — "Choose the type to upload": three selectable cards, Manufacturer, Vendor and F\&B Client, behaving as radio options.

* Step 2 — choice of import method: upload a file, or copy and paste.

* Step 3 — the upload screen, with a dashed dropzone, a circular progress indicator during upload, a green tick on success, and a file chip showing the name, the size and a delete icon.

* Step 4 — "Match column headers": a summary of the recognised rows and columns and the preview table, whose headers carry a mapping dropdown and an include/exclude checkbox, and whose cells look like plain text but become editable on click.

* Step 5 — modals for errors, duplicate conflicts and adding missing information.

**Fields available for mapping**

| Field | Required | Notes |
| :---- | :---- | :---- |
| Company Name | Required | — |
| Email (primary) | Required | — |
| Phone Number | Required | Country code, base number, extension |
| Address | Required | — |
| Accounting Name | Optional | — |
| Accounting Email | Optional | — |
| Accounting Phone | Optional | Country code, base number, extension |
| Contact Person — first name, last name, email, phone | Optional | More than one contact person may be mapped |

**Functional rules**

| FR-ADM-111 | The entity type shall always be chosen by hand in step 1, even where the administrator started from a specific sidebar section; nothing is pre-selected. |
| :---- | :---- |
| **FR-ADM-112** | The Confirm button shall stay inactive until a type has been selected. |
| **FR-ADM-113** | Company type shall not appear in the mapping list. It is set in step 1 and applied to every imported row; where the uploaded file contains a type column, that column is ignored. |
| **FR-ADM-114** | Where any required field — company name, email, phone number or address — is left unmapped, the "Continue and save" button shall be blocked and the columns of the unmapped required fields shall be highlighted in red. |
| **FR-ADM-115** | Only one file column may be mapped to a given database field. Where the administrator selects a field that another column already uses, the system shall block the selection. |
| **FR-ADM-116** | Creating new system fields during mapping is not available; only the existing database fields may be chosen. |
| **FR-ADM-117** | Columns that are mapped to no field shall be ignored during the import. They do not block the process and are not written to the database. |
| **FR-ADM-118** | One import batch shall carry data for one entity type only. |
| **FR-ADM-119** | The system shall accept files with the extensions .csv, .xls, .xlsx and .txt (tab-delimited). |
| **FR-ADM-120** | Record uniqueness shall be determined by an exact match on the company name. |
| **FR-ADM-121** | Data changed in cells during the preview stage shall apply to the current import only and shall not modify the uploaded file. |

**Edge cases and error handling**

| FR-ADM-122 | Where the file structure is unreadable or the encoding is damaged, the system shall stop parsing and display the "Please, format your file" modal, suggesting that the file be reformatted or that the copy-and-paste method be used instead. |
| :---- | :---- |
| **FR-ADM-123** | Where a valid file holds headers but no data rows, the Continue button shall remain inactive and a validation error shall be displayed. |
| **FR-ADM-124** | Where the connection is lost during the upload, the progress indicator shall stop, turn red and read "Upload failed. Please try again." |
| **FR-ADM-125** | Where a duplicate is found on saving, the system shall offer Update, which fills the empty fields of the existing record from the file, and Replace, which overwrites the existing record entirely. |
| **FR-ADM-126** | On a large import the system shall close the mapping interface, display the "We are working on your data" modal, return the user to the master database page and notify them when processing completes. |

## **4.12 Validation when the company type is changed**

Prevent breaches of the business model — a manufacturer dealing directly with clients, for example — and prevent orphaned data, by forbidding a change of company type once the company holds any data or relationship specific to its current type.

**Interface**

* The Company Type dropdown stays active and selectable throughout editing; it is not disabled in the interface before the form is submitted.

* Save submits the form and triggers validation on the backend.

* Where validation fails the form stays open, the Company Type field is highlighted in red, and a message listing the blocking entities is displayed at the top of the screen or beside the field.

**Entities that block a type change**

| \# | Entity or relationship | Description |
| :---- | :---- | :---- |
| 1 | Clients | Any relationship with client companies |
| 2 | Products / catalog | Any record in the product catalog, such as a vendor product or a restaurant product |
| 3 | Invoice history | Any invoice issued or received |
| 4 | Orders | Any order created, in any status |
| 5 | Type-specific teams | The presence of a store team or a restaurant team. The default general team does not block the change. |
| 6 | B2B relations | Any relationship with another counterparty, such as a vendor-to-manufacturer link |

**Interaction logic**

**Scenario A — the change is accepted**

* The administrator opens the company card and changes the company type, for example from Vendor to Manufacturer.

* On Save the backend checks for related type-specific data and finds none beyond the default general team.

* The data is saved and the confirmation "Company type changed successfully" is displayed.

**Scenario B — the change is rejected**

* The administrator changes the type of a company that already holds products or linked clients and clicks Save.

* The backend finds the type-specific entities — a product catalog and invoice history, for example — rejects the transaction and returns a validation error with the list of blocking entities.

* The message is displayed on the interface, the change is not applied and the previous company type is kept in the database.

**Functional rules**

| FR-ADM-127 | The company type may be changed only while the company holds nothing beyond the general information created during onboarding. From the first action that attaches type-specific data or relationships, the type is fixed permanently. |
| :---- | :---- |
| **FR-ADM-128** | The change shall be forbidden where at least one record exists in any of the blocking categories listed above. |
| **FR-ADM-129** | No migration of type-specific data shall take place when the type is changed. Converting a vendor product into a restaurant product, for example, is not performed: the entities carry different business logic and structures. The only way to change the type is for no such data to exist. |
| **FR-ADM-130** | The error message shall be built dynamically and shall name the reason for the refusal, following the template "Cannot change the company type, because related data is registered in the system: \[list of blocking entities\]." |
| **FR-ADM-131** | The backend shall return a structured response carrying an error code and an array of blocking entities, for example {"error": "validation\_failed", "message": "Cannot change company type due to existing specific data", "blocking\_reasons": \["products", "clients"\]}. |
| **FR-ADM-132** | The general team is created automatically during onboarding for every company. It is treated as non-specific and is ignored during validation. |
| **FR-ADM-133** | Where a user created a store team during onboarding but has taken no other action, that team alone blocks the change of type. |

**Edge cases and error handling**

| FR-ADM-134 | Where the user has manually deleted every product, order, client and type-specific team, so that the counts are zero, the system shall allow the type to be changed, because the risk of inconsistent data has been removed. |
| :---- | :---- |
| **FR-ADM-135** | Where the administrator has the form open and a client places an order in the meantime, the backend shall re-check the conditions within the saving transaction and shall return a validation error, blocking the save. |

**Acceptance criteria**

| FR-ADM-136 | The system allows the company type to be changed in the admin panel where the company holds only the default general team and no other related data or relationships. |
| :---- | :---- |
| **FR-ADM-137** | The system blocks the change of company type on saving where at least one record exists among the blocking entities: clients, products, invoices, orders, store or restaurant teams, and B2B relations. |
| **FR-ADM-138** | The system displays an informative error naming precisely the entities that blocked the change. |
| **FR-ADM-139** | The system performs no automatic migration and no hidden deletion of type-specific data when a type change is attempted. |
| **FR-ADM-140** | The system performs the validation on the backend, immediately before the changes are written to the database, so that a race condition cannot bypass it. |

# **Part 5\. Authentication and onboarding**

This part covers account creation, sign-in and password recovery, and the onboarding wizard that follows registration. Registration is gated by an invitation code issued through the admin panel, and every authentication path uses a one-time verification code delivered by email or SMS.

Design reference: Chain Service Solutions, nodes 19521-237403, 19521-237404, 19528-315042, 19528-315043, 19528-315044, 24943-102963, 24943-112330, 24943-103105, 24943-103313, 24943-103635.

## **5.1 Field requirements across the authentication screens**

Summarise the fields used on the sign-in, sign-up and password recovery screens, and the constraints applied to each.

**Field overview**

| Field | Screens | Type | Required | Notes |
| :---- | :---- | :---- | :---- | :---- |
| email | Sign In, Sign Up, Forgot Password | Email | Yes on all three | RFC 5322 format; must be unique on registration |
| phone\_number | Sign In, Sign Up, Forgot Password | Phone (string) | Yes on all three | Format \+X (XXX) XXX-XXXX; must be unique on registration |
| password | Sign In, Sign Up | Password | Yes | Minimum 6 characters, with uppercase, lowercase and special characters; show/hide control |
| confirm\_password | Sign Up | Password | Yes | Must match the password field |
| verification\_code | Sign In, Sign Up, Forgot Password | String, 6 digits | Yes | Valid for 30 minutes; resend available after 60 seconds |
| invitation\_code | Sign Up | String | Yes | Maximum 20 characters; verified through the API |
| terms\_and\_conditions | Sign Up | Checkbox | Yes | Must be checked |
| security\_question | Sign Up (pop-up) | Dropdown and text | Yes | At least one; the user selects the question and supplies the answer |
| password\_visibility | Sign Up, Sign In, Forgot Password | Interface control | No | Eye icon that shows or hides the password |

## **5.2 Sign up**

Create a new user account, verified by email or phone, and protected by security questions. The screen is reached from "Join us" or "Sign Up" on the landing page and from the login screen.

**Interface**

* Mobile (≤600px): a single centred column, form at full width.

* Tablet (600–1024px): two columns, brand and illustration on the left, form on the right.

* Desktop (\>1024px): a fixed left block with the description, form on the right.

* The form holds the Sign Up heading, the invitation code field, an Email / Phone Number method selector, the credential fields with a show/hide control, the terms checkbox and the Next button.

**Field requirements**

| Field | Type | Required | Validation |
| :---- | :---- | :---- | :---- |
| invitation\_code | String | Yes | Not empty; maximum 20 characters |
| email | Email | Yes, where Email is the chosen method | Valid format; must be unique in the database |
| phone\_number | Phone (string) | Yes, where Phone is the chosen method | Format \+X (XXX) XXX-XXXX; must be unique in the database |
| password | Password | Yes | Minimum 6 characters, at least one uppercase letter, one lowercase letter and one special character |
| confirm\_password | Password | Yes | Must match the password field exactly |
| terms\_and\_conditions | Checkbox | Yes | Must be checked |

**Interaction logic**

**Registration flow**

* The invitation code is entered and verified through the API; a failure produces an inline error.

* The user selects Email or Phone Number as the registration method.

* The user enters the email address or phone number and the password with its confirmation; format errors produce inline errors.

* The user accepts the terms and conditions.

* On Next the data is submitted and a six-digit code is sent by email or SMS, valid for 30 minutes.

* The user enters the code and clicks Submit. An incorrect code produces "Invalid code"; "Resend code" becomes available after 60 seconds.

* After successful verification the "Setup Security Question" pop-up opens: a dropdown of questions, an answer field, an "Add another question" control, and a checkbox reading "I understand my account will be locked if I am unable to answer this question". Save stores the settings and closes the pop-up.

* The user is then redirected to onboarding.

**Functional rules**

| FR-AUT-001 | The invitation code shall be validated as soon as it is entered. |
| :---- | :---- |
| **FR-AUT-002** | The eye icon shall show or hide the password. |
| **FR-AUT-003** | Inline errors shall be displayed for an incorrect format or an unverified field. |
| **FR-AUT-004** | The resend control shall unlock 60 seconds after the code is sent. |
| **FR-AUT-005** | The verification code shall remain valid for 30 minutes, after which the message "Code expired" is displayed together with the resend control. |
| **FR-AUT-006** | At least one security question is required, and Save shall remain inactive until the acknowledgement checkbox is selected. |
| **FR-AUT-007** | The Next button shall become active only once every field is complete. |

**Edge cases and error handling**

| FR-AUT-008 | An incorrect invitation code produces an inline error. |
| :---- | :---- |
| **FR-AUT-009** | An email address or phone number already in use produces an inline error such as "Phone already in use". |
| **FR-AUT-010** | A password that does not meet the complexity requirements produces an inline error. |
| **FR-AUT-011** | Where the terms checkbox is not ticked, the Next button remains disabled. |
| **FR-AUT-012** | An incorrect verification code produces "Invalid code"; an expired one produces "Code expired" and unlocks the resend control. |
| **FR-AUT-013** | Where the acknowledgement checkbox in the security question pop-up is not ticked, Save remains disabled. |

## **5.3 Sign in**

Let users sign in with an email address or a phone number, with a one-time code as a second factor. The screen is reached from the "Log In" control in the site header.

**Interface**

* The form holds a "Welcome back" heading, an Email / Phone Number tab selector, the corresponding input field, and a Next button that activates once an identifier has been entered.

* Responsive behaviour matches the sign-up screen: single column on mobile, two columns on tablet, fixed left block on desktop.

**Field requirements**

| Field | Type | Required | Validation |
| :---- | :---- | :---- | :---- |
| email | Email | Yes, where Email is the chosen method | Format check; error where the value is missing |
| phone\_number | Phone (string) | Yes, where Phone is the chosen method | Format check; error where the value is missing |
| password | Password | Yes | Checked for an empty value; error where incorrect |
| verification\_code | String, 6 digits | Yes | Six digits; error where incorrect |

**Interaction logic**

**Authorisation flow**

* The user selects the Email or Phone Number tab.

* The user enters the identifier and clicks Next.

* A password field and a Sign In button appear; an incorrect password produces "Incorrect password" and the user re-enters it.

* Once the password is accepted, a one-time code is sent by email or SMS.

* A verification code field and a Submit button appear; an incorrect code produces "Invalid code", and the resend control becomes available 60 seconds after the code was sent.

* On a correct code the user is taken to the dashboard.

**Functional rules**

| FR-AUT-014 | The method selector shall toggle the visibility of the email and phone fields. |
| :---- | :---- |
| **FR-AUT-015** | The Next button shall be enabled only once the identifier has been entered, and the Sign In button only once the password has been entered. |
| **FR-AUT-016** | An invalid identifier shall produce "Invalid email" or "Invalid phone number" below the field. |
| **FR-AUT-017** | An incorrect password shall produce "Incorrect password" below the password field. |
| **FR-AUT-018** | The resend control shall become available 60 seconds after the code is sent. |
| **FR-AUT-019** | An incorrect code shall produce "Invalid code" below the input. |

## **5.4 Password recovery and reset**

Let users regain access to their account through email or phone verification, and set a new password. Reached from the "Forgot password?" link on the sign-in screen.

**Interface**

* The recovery form holds the "Forgot password?" heading, the subheading "To secure your account, please complete the following verification.", an Email / Phone Number selector, the corresponding field, a "Get Code" button, and — once the code has been sent — the verification code field with resend and submit controls.

**Recovery screen — field requirements**

| Field | Type | Required | Validation |
| :---- | :---- | :---- | :---- |
| email | Email | Yes, where Email is the chosen method | Valid format; not empty |
| phone\_number | Phone (string) | Yes, where Phone is the chosen method | Format \+X (XXX) XXX-XXXX; not empty |
| verification\_code | String, 6 digits | Yes | Six digits; not empty |

**Reset screen — field requirements**

| Element | Description | Requirements |
| :---- | :---- | :---- |
| "Reset Your Password" heading | Instructions for setting a new password | — |
| New Password | Enter the new password | Minimum 8 characters; at least one uppercase letter, one lowercase letter, one digit and one special character |
| Confirm New Password | Confirm the new password | Must match the new password exactly |
| Next | Saves the password and signs the user in | Active once every password requirement is met |

**Interaction logic**

**Recovery flow**

* The user selects Email or Phone Number.

* The user enters the identifier and clicks "Get Code"; an incorrect format produces an inline error, and on success the verification code field appears.

* The user enters the code and clicks Submit; an incorrect code produces "Invalid code" and the field stays active. Resend becomes available after 60 seconds.

* After successful verification the user is taken to the "Reset Your Password" screen.

* The user enters and confirms the new password and clicks Next, and is then signed in.

**Functional rules**

| FR-AUT-020 | "Get Code" shall be locked for 60 seconds after a request. |
| :---- | :---- |
| **FR-AUT-021** | The resend control shall become active after 60 seconds and shall issue a new code. |
| **FR-AUT-022** | Both password fields are required. Where they differ, "Passwords do not match" is displayed; where the password fails the complexity rules, "Password does not meet complexity requirements" is displayed. |

## **5.5 Onboarding — data requirements**

Record the attributes collected during onboarding, with their validation rules and the entity each belongs to.

**Onboarding attributes**

| Attribute | Type | Required | Validation | Purpose |
| :---- | :---- | :---- | :---- | :---- |
| business\_type | Dropdown | Yes | Selected from the list of values | Restaurant or Vendor |
| company\_name | Text | Yes | 1–64 characters: A–Z, a–z, 0–9, space, hyphen, ampersand | Company name |
| alternative\_company\_name | Text | No | 64 characters or fewer | DBA company name |
| company\_address | Autocomplete | Yes | A valid address through the Google Maps API | Legal or physical address |
| company\_phone\_number | Select and input | Yes | Format \+X (XXX) XXX-XXXX; digits only | Company phone number |
| company\_email | Email | Yes | RFC 5322 | Primary email address |
| company\_website | URL | No | Must start with http:// or https://; 2083 characters or fewer | Company website |
| company\_logo | File upload | No | JPEG or PNG (size limit stated inconsistently — see open points) | Company logo |
| team\_member\_role | Dropdown | Yes | Owner by default for the first member; later members select from the role directory | Role in the core team |
| team\_member\_first\_name | Text | Yes | 1–32 characters; letters | First name |
| team\_member\_last\_name | Text | Yes | 1–32 characters; letters | Last name |
| team\_member\_email | Email | Yes | RFC 5322 | Member email |
| team\_member\_phone | Select and input | Yes | Format \+X (XXX) XXX-XXXX; digits only | Member phone number |
| restaurant\_name | Text | Yes, where the type is Restaurant | 1–64 characters: A–Z, a–z, 0–9, space, hyphen, ampersand | Restaurant name |
| alternative\_restaurant\_name | Text | No | 64 characters or fewer | DBA name of the restaurant |
| restaurant\_display\_name | Text | No | 32 characters or fewer | Display name in listings |
| restaurant\_address | Autocomplete | Yes, for Restaurant | A valid address through the Google Maps API | Restaurant address |
| restaurant\_product\_category | Multi-select | Yes, for Restaurant | Selected from the category list | Restaurant product categories |
| restaurant\_phone\_number | Select and input | Yes, for Restaurant | Format \+X (XXX) XXX-XXXX; digits only | Restaurant phone number |
| restaurant\_email | Email | Yes, for Restaurant | RFC 5322 | Restaurant email |
| store\_name | Text | Yes, where the type is Vendor | 1–64 characters: A–Z, a–z, 0–9, space, hyphen, ampersand | Store name |
| alternative\_store\_name | Text | No | 64 characters or fewer | DBA store name |
| store\_display\_name | Text | No | 32 characters or fewer | Display name in listings |
| store\_address | Autocomplete | Yes, for Vendor | A valid address through the Google Maps API | Store address |
| store\_product\_category | Multi-select | Yes, for Vendor | Selected from the category list | Store product categories |
| store\_phone\_number | Select and input | Yes, for Vendor | Format \+X (XXX) XXX-XXXX; digits only | Store phone number |
| store\_email | Email | Yes, for Vendor | RFC 5322 | Store email |

**Functional rules**

| FR-AUT-023 | The role of the first participant is Owner. It is assigned automatically and is read-only; subsequent participants select a role from the lookup table. |
| :---- | :---- |
| **FR-AUT-024** | Restaurant attributes are collected only where the business type is Restaurant, and store attributes only where it is Vendor. |

## **5.6 Onboarding screens**

Take a newly registered user from business type selection through company details, core team and locations, to the completion screen and the dashboard.

**Interface**

* Every screen follows the same responsive pattern: a single centred column at 600px and below, two columns between 600 and 1024px, and a fixed left block with the progress indicator above 1024px.

**Screen 1 — select business type**

| Element | Description |
| :---- | :---- |
| Restaurant | Selects the Restaurant business type |
| Food Vendor | Selects the Vendor business type |
| Next | Goes to the Company Information screen; active once a selection has been made |

**Screen 2 — company information**

| Field | Type | Required | Validation |
| :---- | :---- | :---- | :---- |
| Company Name | Text | Yes | 1–64 characters: A–Z, a–z, 0–9, space, hyphen, ampersand |
| Alternative DBA Name | Text | No | 64 characters or fewer |
| Company Address | Autocomplete (Google Maps API) | Yes | A valid address; an error is raised where no suggestion is available |
| Company Phone Number | Select (code) and input | Yes | Format \+X (XXX) XXX-XXXX; digits only |
| Company Email | Email | Yes | RFC 5322; an incorrect format produces an inline error |
| Website | URL | No | http:// or https://; a hint is shown where the scheme is missing |
| Company Logo | File (JPEG or PNG) | No | Maximum 5 MB; a format or size error is raised otherwise |
| Back / Next | Buttons | No | Next becomes active once every required field is complete |

**Screen 3 — core team**

| Field | Type | Required | Validation |
| :---- | :---- | :---- | :---- |
| Role | Dropdown | Yes | Owner, CFO, Chef, Manager and so on |
| First Name | Text | Yes | 1–32 characters; letters |
| Last Name | Text | Yes | 1–32 characters; letters |
| Email | Email | Yes | RFC 5322 |
| Cell Phone Number | Select and input | Yes | Format \+X (XXX) XXX-XXXX; digits only |
| Add Team Member | Button | — | Adds the member and clears the form |
| Reset | Button | — | Clears every field |
| I’ll do it later | Button | — | Skips this step; the person registering the company is added automatically as the owner |

**Screen 4 — adding restaurants or stores**

| Field | Type | Required | Validation |
| :---- | :---- | :---- | :---- |
| Name | Text | Yes | 1–64 characters: A–Z, a–z, 0–9, space, hyphen, ampersand |
| Alternative name | Text | No | 64 characters or fewer |
| Display name | Text | No | 32 characters or fewer |
| Address | Autocomplete | Yes | A valid address through Google Maps |
| Product category | Multi-select | Yes | Selected from the restaurant or vendor category list |
| Phone number | Select and input | Yes | Format \+X (XXX) XXX-XXXX; digits only |
| Email | Email | Yes | RFC 5322 |
| Team member role, first name, last name, email, phone | Mixed | Yes | The same validation as the core team fields |
| Add Team Member / Reset | Buttons | — | Adds a member and clears the form, or clears the form |
| I’ll do it later | Button | — | Skips the step |
| Next | Button | — | Active once at least one restaurant or store has been added |

**Screen 5 — completion**

| Element | Description |
| :---- | :---- |
| Heading | "Welcome to CSS" |
| Text | A short message confirming that the platform is ready for use |
| Start | Goes to the dashboard |

**Interaction logic**

**Member and location cards**

* Once a team member has been added, a card appears showing role, full name, email and phone. Only Edit is available for the Owner; other members can be edited and deleted.

* A restaurant or store card shows the name, DBA name, address, the role of the first team member, the contact details, and Edit and Delete controls.

**Functional rules**

| FR-AUT-025 | Business type is required: where nothing is selected, the Next button on screen 1 remains disabled. |
| :---- | :---- |
| **FR-AUT-026** | Every field on the core team screen is required, and inline errors are shown where a field is left blank or formatted incorrectly. |
| **FR-AUT-027** | At least one participant, the Owner, is saved even where the core team form is submitted incomplete. |
| **FR-AUT-028** | The completion screen cannot be skipped once the onboarding steps are finished, and Start takes the user to the dashboard. |

# **Part 6\. Vendor portal**

The vendor portal is the working environment of the vendor company: the dashboard, the chat module, orders, the product catalog, clients, invoices and packing slips, the team, and the settings that govern all of them. This part describes each module as it behaves today, following the same order as the sidebar. Where a screen exists in more than one variant in the source material, the later and fuller variant is described and the difference is noted in the open points.

Design reference: Chain Service Solutions, nodes 21510-356010 and 21510-356913.

*Two bodies of material from the source are deliberately not reproduced here. The engineering analysis of the invoice numbering implementation — the current database structures, the defects found in them and the remediation plan — is a technical report on existing code rather than a description of system behaviour. The invoice redesign specified as MVP 2, together with the changes agreed after the meeting of 3 September 2025, describes a planned redesign rather than current behaviour. Both belong in separate documents; the numbering algorithm itself is recorded below, because it defines how invoice numbers are produced today.*

## **6.1 Shell, navigation and universal elements**

Describe the elements present on every page of the portal: the sidebar, the top bar, the footer and the support widget.

**Interface**

* Sidebar: the CSS logo, the current store selector — displayed for example as "Kabona Main Store" — the menu sections, and Log Out.

* Menu sections: Dashboard, Orders, Invoices, Packing Slips, Claims, Chats, Products, Clients, Teams, Settings.

* Top bar, upper right: the search field covering orders, customers and products, and the notification, message and cart icons. The message and cart icons are placeholders.

* Footer: Support (mailto), Privacy Policy, Cookie Policy and Terms of Service.

**Responsive behaviour**

| Breakpoint | View | Behaviour |
| :---- | :---- | :---- |
| Below 640px | Mobile | Hamburger menu; content in a single column |
| 640–1024px | Tablet | Collapsible side menu; some icons hidden |
| Above 1024px | Desktop | Full menu on the left with the header above |

**Functional rules**

| FR-VND-001 | The chat menu item shall display the number of unread messages. |
| :---- | :---- |
| **FR-VND-002** | Clicking the CSS logo shall return the user to the dashboard. |
| **FR-VND-003** | The company or department toggle shall display the current store or vendor name with a "Store" or "Vendor" label, and shall open a pop-up listing the available departments. |
| **FR-VND-004** | The notification icon shall carry a badge showing the number of unread notifications. |
| **FR-VND-005** | All elements shall adapt correctly to mobile, tablet and desktop devices. |

## **6.2 Support widget**

Let the user ask for help from inside the platform, either from the automated assistant or from a live agent.

**Interface**

* The widget sits in the lower right corner of the interface.

* Title: "Ask CSS AI Assistant". Subtitle: "Live reps are online", indicating that a live agent can be reached.

* Message area showing incoming and outgoing messages. The assistant opens with "Hi, I can help you with your CSS questions or connect you with a live assistant."

* Input field with the placeholder "Message...", a microphone control for voice input, and a send control.

* A close control minimises or closes the window.

**Functional rules**

| FR-VND-006 | The widget shall combine two support modes: the automated CSS AI Assistant and a handover to a live representative where necessary. |
| :---- | :---- |

## **6.3 Store selection**

Let the user switch the branch — store or restaurant — they are working in.

**Interface**

* The "Change Store" window displays a card for the store: name, address, phone and email, with the store avatar showing its initial. Several such cards may be offered.

* Actions: Cancel closes the window without saving, Apply confirms the selection, and the "X" icon behaves as Cancel.

**Functional rules**

| FR-VND-007 | Applying a store selection shall apply it to the user’s current session. |
| :---- | :---- |

## **6.4 Dashboard**

Give the vendor quick access to the key operations and metrics: orders, invoice upload, sales figures, late delivery notifications and navigation to the rest of the system.

**Interface**

* Welcome section: "Welcome to Chain Service Solutions", explaining that the dashboard is where activity is managed, products are added and edited, and inviting the user to upload the invoices of the past six months so that the client and product database can be recognised and populated automatically.

* Call-to-action section: Upload Invoices, which opens a file selection dialog; Add Product, which opens the product creation flow; Add Clients, which opens the client creation flow.

* Order tables: Open Orders, New Orders and Past Due Orders, each with the columns Order ID, Customer Name, Due Date and Total.

* The earlier variant of the screen shows two blocks only — Pending Orders and Past Due Orders — each with ID, Customer, Date and Total, and a count in the heading.

**Overview metrics**

| Metric | Meaning |
| :---- | :---- |
| Completed Orders | Number of completed orders |
| Total Sales | Total sales amount |
| Returns | Total amount of returns, where any exist |

**Functional rules**

| FR-VND-008 | Each metric shall be accompanied by the percentage change against the previous period. |
| :---- | :---- |
| **FR-VND-009** | The period selector shall offer Today compared with yesterday, Week comparing the last seven days with the previous seven, Month comparing the last 30 days with the previous 30, and Year comparing the last 365 days with the previous 365\. |
| **FR-VND-010** | The notifications feed shall list events such as "Order \#12345 is past due for delivery". |
| **FR-VND-011** | Clicking a notification shall open the details of the order it refers to. |

## **6.5 Chats**

Centralise communication about orders, delivery and payment with restaurants, distributors and other partners, so that external messengers are not needed.

**Interface**

* The screen has two areas: the chat list on the left and the conversation on the right.

* Chat list header: "Messages (63)" showing the number of active chats, and an "Add Chat" control for creating a chat manually.

* Search field filtering by customer name, restaurant name or message text.

* Each list row carries the avatar initial, the contact or restaurant name, the date of the last message, an excerpt of it, and a red badge with the unread count.

* Conversation header: the chat name, the number of members and the number currently online — a chat may be a group with representatives of both the restaurant and CSS.

* Input panel: the current user’s avatar, the field "Write a message…", the send control, an attachment control for files, images and documents such as invoices and receipts, and a delivery status indicator.

## **6.6 Orders — list**

Provide a single table for viewing, searching and filtering orders.

**Interface**

* Controls above the table: a "Search..." field, a Date Range filter, and status filters.

* The "+ Create new" control starts the order creation process.

* A global "Search the system..." field searches across all system data.

**Table columns**

| Variant | Columns |
| :---- | :---- |
| Order list | ID, Client, Ordered (date), Delivery (date), Products (quantity), Credit ($), Total ($) |
| Order summary variant | Date, Client, Manufacturer, Order Date, Ship Date, Total, OS Balance |

**Functional rules**

| FR-VND-012 | The search shall run in real time across all data visible in the table. |
| :---- | :---- |
| **FR-VND-013** | The status filters shall cover New, Confirmed, Pending, Delivered and Canceled; the fuller variant of the screen adds On The Way and Arrived. |
| **FR-VND-014** | The selected status shall be highlighted, and the list shall update immediately to show only records with that status. |
| **FR-VND-015** | The OS Balance field shall display the outstanding balance for an order using colour or symbol indicators, for example for negative values. |
| **FR-VND-016** | Each table row represents a summary of one order. |

## **6.7 Orders — creating an order**

Walk the user through selecting a client, adding products and confirming the order.

**Interaction logic**

**Step 1 — select a client**

* The user selects an existing client from the "Select Client" dropdown, or ticks "Client is not in the system" to enter a one-off client manually.

* Selecting a client populates the associated addresses and contact persons automatically.

* The user completes and checks the delivery address and the contact person, and saves the client information.

* The "Next →" control moves to the following step.

**Step 2 — add products**

* The left panel shows a hierarchy of product categories such as Vegetables, Meat & Poultry or Beverages; selecting one filters the product list.

* The central panel lists products with a "Search..." field covering name and SKU, a "Compare Prices To" filter and a per-page selector.

* The product table carries the columns Product ID, Product Name, ING, UoM, Current Unit Price and QTY, with "−" and "+" controls to preselect the quantity.

* The "+ Add" control adds the product with the selected quantity, and then changes to a tick confirming that the product is in the order.

* The "Your Order" panel shows the running total in real time.

* "Back" and "Next →" move between the steps.

**Step 3 — confirmation**

* The system opens the order details screen with the order in status New.

* The user reviews the information, makes any final changes and clicks Confirm.

* On confirmation the order status changes and the order becomes available to the following processes, assembly and delivery.

**Functional rules**

| FR-VND-017 | Selecting a client from the database shall populate the Delivery Address, Bill To and Ship To fields with that client’s default information. |
| :---- | :---- |
| **FR-VND-018** | Ticking "Client is not in the system" shall unlock the fields for manual entry, including the delivery address. |
| **FR-VND-019** | The "Billing and shipping addresses are the same" checkbox shall be selected by default for a new order, and shall copy the Ship To address into Bill To. |
| **FR-VND-020** | The contact person shall be filled in before the user can move to the next step. |
| **FR-VND-021** | The contact person dropdown shall list the contacts associated with the selected client and shall display the chosen contact together with their phone number. |
| **FR-VND-022** | The Edit control beside a contact person or an address shall open a form for editing those details or adding a new contact. |

## **6.8 Orders — editing billing details**

Edit the billing company on an order and manage the contact persons attached to it.

**Interface**

* The modal holds the Bill To company name, the email address and the full mailing address.

* The Contact Person section holds the primary contact and their phone number, with a "+ Add Contact Person" control that opens a form for a new contact.

* Cancel closes the modal without saving; Save writes the changes, updates the billing details on the order and closes the modal.

## **6.9 Orders — order card**

Consolidate everything about one order: customer, shipping, payment and contents, with the ability to view, edit and confirm it.

**Sections of the Order tab**

| Section | Content |
| :---- | :---- |
| Order Info | Customer \#, Salesperson, Shipping Method, Terms, Order Date, Delivery Date, Delivery Time; payment information: Payment Method, Invoice \#, PO \#, Credit |
| Bill From, Bill To, Ship To | Contact details and addresses for billing and shipping, each with an Edit control |
| Products ordered | Model \#, Product Name, UoM, Ord Qty, Ship Qty, B/O, Unit Price, Discount, Tax %, Extension; a summary row with the number of items and a "+ Add Product" control |
| Comments | A comment field with a "Go to Chat" checkbox, and the comment history with author, date and time |
| Details | Order ID, client details, Credit; and the calculation: Freight Fee, Tax, Discount, Additional Discount, Subtotal, Total, with edit controls beside Discount and Additional Discount |

**Functional rules**

| FR-VND-023 | The Extension field on a product line shall be calculated automatically from the quantity, price, discount and tax. |
| :---- | :---- |
| **FR-VND-024** | Total shall be calculated as Subtotal plus Tax plus Freight Fee, less Discount and Additional Discount. |
| **FR-VND-025** | The Credit field in the order information and in the details section shall be synchronised, showing the credit limit or the applied discount. |
| **FR-VND-026** | The confirmation control shall be labelled according to the current status: Confirm for New, Arrived for On the way, and Confirm Delivery for Arrived. |
| **FR-VND-027** | Confirming shall save the changes and may move the order to the next status. |
| **FR-VND-028** | The Back control shall return the user to the order list without saving, or with a warning about unsaved data. |
| **FR-VND-029** | Line-item notes shall be available: each line offers an "Add Note" field, with a larger text area for a detailed note, and Save links the notes to the corresponding lines. |

## **6.10 Orders — History, Documents and Delivery tabs**

Give access to the audit trail, the generated documents and the delivery record of an order.

**Tabs and actions**

| Tab or action | Behaviour |
| :---- | :---- |
| Order History | Active by default. Shows the event log with the columns Product ID, Event, Date, User and User Role, with a search field, a Date Range filter and a per-page selector. Each row records one event in the order lifecycle against a specific product line. |
| Documents | Lists the documents available for the order — for example "Invoice \#123456", "Claim" and "Packaging Slip" — each with a Download control. |
| Delivery | Shows the delivery fee and the delivery type, the timeline with the Picked up and Delivered timestamps, the scheduled delivery date, the assigned courier and the time window, and the recipient’s company, contact person and phone number. |
| Duplicate | Creates a copy of the current order |
| Export | Exports the order data to a file |
| Generate Invoice | Generates an invoice from the order data, which then appears in the Documents list |
| Print | Opens the print dialog for the order |
| Cancel | Starts the order cancellation process |

**Functional rules**

| FR-VND-030 | The "Created" event in the log indicates that a line item has been added to the order. |
| :---- | :---- |
| **FR-VND-031** | The system shall log the exact date, time and user for every action. |
| **FR-VND-032** | The Download control shall become active only once the corresponding document has been generated successfully. |
| **FR-VND-033** | Downloading shall deliver the document to the user’s device in a standard format such as PDF. |
| **FR-VND-034** | Picked up and Delivered are mandatory milestones of the delivery process, and the Delivered status indicates that delivery is complete. |
| **FR-VND-035** | The actions in the top panel apply to the order as a whole. |

## **6.11 Products — store products, import and write-off**

Let the shipping manager keep the product lineup current: import products from a file, manage them in the interface, and process write-offs.

**Interaction logic**

**Adding and importing**

* "Create new" opens the Add New Product page.

* The upload flow opens the "How would you like to add products?" page, offering a file upload or manual entry; Cancel returns to the products page and Confirm proceeds.

* The copy-and-paste route accepts data in CSV form, with Cancel to go back and Confirm to continue.

* The "Format your file" step lets the user map the headers; the system offers the headers Name, Price, Quantity, Unit and Category, with Cancel to go back and Save to keep the mapping.

* The "Match column headers to product information" step lets the user change the column type.

* A file can be uploaded by drag and drop or by browsing the device; the following steps then match the copy-and-paste flow.

**Writing off products**

* The user selects the product name, the quantity to write off — with an "Everything in stock" option that selects the whole stock — and the reason, either Damaged or Spoiled.

* "Add another product" adds a further line, and the system validates the entries when it is used.

* "Write Off" performs the write-off; Cancel abandons it.

**Functional rules**

| FR-VND-036 | All fields in the write-off form are required. |
| :---- | :---- |
| **FR-VND-037** | The supported import file formats are CSV, XLS and TXT. |

## **6.12 Products — vendor product table and card**

Let the vendor view and edit product information, in order to analyse restaurant baskets and decide how to promote products.

**Product table columns**

| Column | Description | Sortable |
| :---- | :---- | :---- |
| ID | Unique product ID | No |
| Img | Product image | No |
| Category | Product category | Yes |
| Name | Product name | Yes |
| In Stock | Actual stock, in units | Yes |
| Min QTY | Minimum stock, in units | Yes |
| Unit | Unit of measure | Yes |
| Price | Price per unit, $ | Yes |
| Published | Product status: Active or Inactive | Yes |

**Information tab — fields**

| Field | Editable | Rules |
| :---- | :---- | :---- |
| ID | No | Unique product number |
| Product name | Yes | — |
| Category | Yes | One value from the dropdown |
| For UoM / For Weight | No | Selects whether the product is priced by unit of measure or by weight |
| UoM | Yes | One value from the list |
| Price for UoM | Yes | Where "For UoM" is selected. Decimal with a period separator and at most two decimal places; entered manually or through arrows in steps of 0.01 |
| Weight | Yes | Where "For Weight" is selected. One value from the list |
| Price | Yes | Where "For Weight" is selected. Decimal with a period separator and at most two decimal places; entered manually or through arrows in steps of 0.01 |
| Tax | Yes | Decimal with a period separator and at most two decimal places; entered manually or through arrows in steps of 0.01 |
| In Stock | Yes | Natural number; entered manually or through arrows in steps of 1 |
| Min quantity in stock | Yes | Natural number; entered manually or through arrows in steps of 1 |
| Description | Yes | — |
| Date added | No | Format MM/DD/YYYY |

**Functional rules**

| FR-VND-038 | The user shall be able to upload a product image by drag and drop or from the device, and to replace it afterwards. |
| :---- | :---- |
| **FR-VND-039** | Supported image formats are PNG, JPG, JPEG and WEBP. Any other format shall raise the error "Invalid file format. Acceptable file formats: .png, .jpg, .jpeg, .webp". |
| **FR-VND-040** | Discard shall abandon the changes on the page and Save shall commit them. |
| **FR-VND-041** | Deleting a product shall require confirmation. |

## **6.13 Products — reports**

Show who orders a product, how it has been ordered historically, and what has been written off.

**Who Orders**

| Column | Description |
| :---- | :---- |
| Restaurant | Restaurant name |
| Last ordered | Date of the last order |
| Times ordered | Number of times the item was ordered |
| QTY Ordered | Quantity ordered per line, decimal |
| Total | Amount in $ |

**Orders history**

| Column | Description |
| :---- | :---- |
| ID | Unique order number |
| Restaurant | Restaurant name |
| Ordered | Order date |
| Delivery | Delivery date |
| Products | Products in the order |
| Credit | Credit amount in $ |
| Total | Total amount in $ |

**Writeoffs**

| Column | Description |
| :---- | :---- |
| Date | Date and time of the write-off |
| QTY | Quantity written off |
| Price | Total cost of the products on the line |
| Writeoff Price | Total write-off cost on the line |
| Reason | Reason for the write-off |

**Functional rules**

| FR-VND-042 | Every nested report tab shall offer export in CSV and XLSX format, a Date Range filter and pagination. |
| :---- | :---- |
| **FR-VND-043** | The Date Range filter shall apply only once both values are supplied, and the start date shall not be later than the end date; where it is, no results are returned. |
| **FR-VND-044** | Sorting shall order values as numbers, then Latin text, then non-Latin text, then blanks: numbers before A, non-Latin characters after Z, and blank rows last. |

## **6.14 Products — restaurant view**

Let a restaurant owner review product information in order to analyse their basket and plan future purchases.

**Product table columns**

| Column | Description | Sortable |
| :---- | :---- | :---- |
| Selection | Checkbox selecting all products on the page, or one product on a row | No |
| ID | Unique product number | No |
| Category | Product category | Yes |
| Name | Product name | Yes |
| Min QTY | Minimum stock quantity | Yes |
| Unit | Unit of measure | Yes |
| Vendors | Vendors supplying the product | No |
| Last order | Date of the last order | Yes |

**Functional rules**

| FR-VND-045 | The search shall match exactly, against the Category and Name columns. |
| :---- | :---- |
| **FR-VND-046** | The category filter shall allow one value: All by default, then the categories present in the data such as Dairy, Meat & Poultry, Seafood and Vegetables. |
| **FR-VND-047** | The product card shall open on a double click on a row. |
| **FR-VND-048** | The product card holds two tabs, Information and Reports, with Discard and Save controls. |
| **FR-VND-049** | On the restaurant side, ID, product name and category are read-only; the minimum stock quantity is editable as a natural number, entered manually or through arrows in steps of one. |
| **FR-VND-050** | The user shall be able to select a vendor for a product, seeing the vendor’s name, address, phone number and email. |
| **FR-VND-051** | The "Add Vendor" control shall open the modal "Select your vendor for \[Product Name\]", from which a vendor can be chosen, confirmed or cancelled. |
| **FR-VND-052** | The "Choose new vendor" control shall open the modal "Choose new vendor for \[Product Name\]"; the Back control returns to the previous modal, and Close or Cancel returns to the product card. |
| **FR-VND-053** | Where a search in the vendor modal returns matches the system shall list the available vendors; where it returns none, it shall display a message to that effect. |
| **FR-VND-054** | The restaurant-side Reports tab holds the nested tabs Vendors, Orders and Writeoffs, with export, a Date Range filter and pagination on each. |
| **FR-VND-055** | The Vendors report shall support partial text search on the Vendor column; the Orders report shall support exact search on ID and Vendor and a single-value status filter across New, Confirmed, Pending, Delivered and Canceled. |

## **6.15 Clients — list and import**

Give the vendor a working client database with current information about clients and the transactions attached to them.

**Interface**

* Page elements: the Upload Clients control, client search, a Date Range filter, pagination and the client table.

**Table columns**

| Column | Description |
| :---- | :---- |
| ID | Unique client number |
| Restaurant Name | Client name |
| Contact Person | Contact person |
| Address | Physical address |
| Reg | Registration status: Active or Inactive |
| CSS Ord | Whether orders exist in CSS: Active or Inactive |
| My Ord | Status: Active or Inactive |
| Status | New, Regular or Go Back |

**Functional rules**

| FR-VND-056 | Access to the client database shall be granted to the vendor company CEO, the store shipping manager and other vendor C-level roles. |
| :---- | :---- |
| **FR-VND-057** | Upload Clients shall open a page offering two methods: upload as a file in CSV, XLS or TXT format, or copy and paste for manual entry. |
| **FR-VND-058** | A client file may carry the fields business name, business email, business phone number, business address, contact name, contact email and contact phone number. |
| **FR-VND-059** | The copy-and-paste route shall open the "Copy and Paste Your Clients" page for manual entry, and shall then continue to the "Format Your File" page where the fields are mapped to system fields. |
| **FR-VND-060** | Validation shall apply the following types: business name as text, business email in email format, business phone number as a numeric value, business address as text, contact name as text, contact email in email format and contact phone as a numeric value. |
| **FR-VND-061** | Where the format is wrong, the system shall display a pop-up reading "Please format your file" together with the list of requirements, which the user closes with the Format File control. |
| **FR-VND-062** | Clicking a row shall open the client profile. |

## **6.16 Clients — client profile**

Hold everything the vendor keeps about one client: the recognised master invoice, invoice numbering, contact and marketing information, finance, delivery preferences and reports.

**Profile tabs**

| Tab | Content |
| :---- | :---- |
| Master Invoice | Two nested tabs: Recognized, holding the editable Client Information, Merchant Information, Payment Information, Bill To and Products sections; and Original File, holding the PDF of the master invoice. The user can save through Confirm Information, download the file, and delete the master invoice with confirmation. |
| Recognized Data | A table with File Name, Status and Created Date. An invoice can be edited through the pencil control. |
| Invoice Numeration | The numbering settings described in section 6.17. |
| Information | Read-only client name and address; a marketing block with Status — New, Regular, Callback or Inactive — and a free-text Source; a comments field; and the contacts section, in which contacts can be created, edited, viewed and deleted, each holding contact person, email and cell phone number. |
| Finance | Credit limit with a grace period in days and a limit in dollars; terms of payment — cash on delivery, weekly, monthly or every invoice; a statement that can be refreshed for a chosen period, downloaded and sent to the client; and payment methods, chosen from Credit Card, Check, Cash, ACH, PayPal, Stripe, Wise, Wire, Zelle, Apple Pay, Google Pay and Other. |
| Delivery Preferences | Delivery type — Pick Up, Delivery or Third Party Delivery; a delivery days override enabled by a toggle, after which the days of the week can be chosen; and delivery time preferences, which become active with the same toggle. |
| Reports | Nested tabs Order History, Invoices and Frequently Ordered, each with search, filters and a table. Reports can be refreshed for a chosen period and downloaded in Excel. |

**Functional rules**

| FR-VND-063 | The system shall use the first uploaded invoice — the master invoice — to create the client automatically where the client is not yet in the database. |
| :---- | :---- |
| **FR-VND-064** | Recognition of data from the PDF shall be performed by the AI module. |
| **FR-VND-065** | The Recognized Data tab shall be displayed only where at least one further invoice has been uploaded beyond the master invoice, and shall be hidden where only the master invoice exists. |
| **FR-VND-066** | The Recognized Data tab shall hold the data recognised from the PDF, duplicating the master invoice, together with the history of invoices uploaded in the selected period. |
| **FR-VND-067** | A user shall be able to upload an invoice PDF manually; this is available to specific users rather than to roles. |
| **FR-VND-068** | Where the master invoice is changed and saved, the system shall offer a pop-up for uploading further invoices. |
| **FR-VND-069** | The system shall allow a batch of invoices to be uploaded in order to build the history. |
| **FR-VND-070** | Master invoice upload shall be disabled by default and enabled only for specific users, configured by an administrator. |
| **FR-VND-071** | Data recognised by the AI shall be available for manual correction. |
| **FR-VND-072** | All changes shall be stored only after the user confirms them through Save or Confirm. |
| **FR-VND-073** | The system shall provide four fixed invoice templates. The user may select one of them but may not upload new ones, and the templates are shown for preview in the Invoice Numeration section. |
| **FR-VND-074** | The Finance tab shall display the message "Credit Limit was exceeded by \[amount\]" where the limit has been passed. |

## **6.17 Invoice numbering**

Define how an invoice number is composed, so that the vendor can match the numbering used before the platform and keep it consistent afterwards.

**Settings and when the example is recalculated**

| Field | Type | Recalculated |
| :---- | :---- | :---- |
| Last Offline Invoice Number | Text | On blur: the value is stored and split into its letter and number parts |
| Letter Designation | Text | On blur: stored, and the example is recalculated immediately |
| Position of Letters | Radio: Before / After | On change |
| Numeration Settings | Radio, three options | On change |
| One or more invoices in one day | Radio, two options | On change |

**Functional rules**

| FR-VND-075 | On loading the screen the system shall parse the Last Offline Invoice Number: any alphabetic characters go to the Letter Designation, and the remainder — digits and symbols — stays in the number. Where there are no letters, the Letter Designation stays empty. |
| :---- | :---- |
| **FR-VND-076** | The position of the letters shall be selectable: Before number produces letters followed by the number, After number produces the number followed by the letters. |
| **FR-VND-077** | Numeration mode "By Date" shall use the date in MMDDYY form as the base number, so that 11 July 2025 gives 071125\. |
| **FR-VND-078** | Numeration mode "Next in order of this client" shall take the maximum of the offline and online numbers for that restaurant and add one, so that ABC123 becomes ABC124, or ABC becomes ABC1 where no digits were present. |
| **FR-VND-079** | Numeration mode "Next in order of all invoices" shall do the same across all restaurants at once. |
| **FR-VND-080** | Changing the numbering setting shall not alter numbers already issued; the starting point for new numbers is the existing global or local maximum. |
| **FR-VND-081** | Where more than one invoice is issued on the same day, the "invoice number through a slash" option shall produce base number, a slash and the sequence number for that day. |
| **FR-VND-082** | Where sequential numbering is chosen instead, the first invoice of the day takes the base number and each subsequent one increments it. |
| **FR-VND-083** | The generation algorithm shall collect the last offline value, the letter designation and its position, the numbering mode, the same-day mode, the current date and the invoices already issued both offline and online; build the base number; insert the letter part in the chosen position; apply the same-day logic using the count of invoices already issued by that restaurant today; and return the resulting string. |
| **FR-VND-084** | The invoice number example shall be displayed immediately after any input parameter changes. |
| **FR-VND-085** | The Letter Designation shall be mandatory where By Date is selected, and optional otherwise. |
| **FR-VND-086** | The user shall be able to set the starting point for numbering by entering the last offline invoice number, and to save the settings for use on future invoices. |

## **6.18 Packing slips**

Provide the document used to assemble an order for the packer and to deliver it for the driver.

**Contents of a packing slip**

| Section | Fields |
| :---- | :---- |
| Order info | Customer \# — the client ID inside the vendor system; Salesperson — the vendor manager who confirmed the order; Shipping Method; Terms; Order Date; Delivery Date; Payment Method; Invoice \#; PO \#; Credit — whether credit was used |
| Bill To | Store name, store email, store manager who confirmed the order, store phone, store address |
| Ship To | Restaurant name, restaurant email, contact person, restaurant phone, restaurant address |
| Products | Line number, Product ID, Product Name, UoM, Ordered, Shipped, Back Order, Weight |

**Role-specific actions**

| Role | Actions |
| :---- | :---- |
| All roles | Go to Chat — opens the chat with the manager, packer or driver for this order |
| Packer | A green tick marking a product as packed; "Report a problem", which opens a pop-up describing the issue; "Ready to Ship", which becomes active once every product is marked packed and moves the packing slip to PACKED |
| Driver | Pick Up, below the table, which moves the status to ON THE WAY; Arrived, which marks the order as delivered to the restaurant (ARRIVED); Confirm Delivery, which confirms that the client accepted the order (DELIVERED) |
| Vendor manager | Edit against each product; a delete control removing a product from the order; Add Product; Confirm to save changes to the order contents; Approve, which moves NEW to PACKED where manager approval is required; Ready to Ship, which moves NEW to PACKED where manager approval is not required and packing is done by the manager; Arrived, moving PACKED to ARRIVED; and Confirm Delivery, moving ARRIVED to DELIVERED |

**Functional rules**

| FR-VND-087 | Shipped shall default to the ordered quantity and may change through corrections or claims. |
| :---- | :---- |
| **FR-VND-088** | Back Order shall be calculated as Ordered minus Shipped. |
| **FR-VND-089** | Weight shall be recorded for products that are charged by weight although ordered by the case. |

## **6.19 Invoices**

Let the vendor manage invoices in order to track and settle payment against orders.

**Interface**

* The Invoices page holds three sub-pages: Master Invoice, Issued Invoices and Invoice Template.

* Master Invoices lists the columns Client, Invoice Internal ID and Uploaded Date, with a Date Range filter, pagination, search by client name, and a pencil control on each row that opens the client page.

* Issued Invoices lists the columns ID, Client, Date, Due Date, Product — the number of products in the invoice — and Total, with search by client name, a Date Range filter and pagination. An arrow on each row opens the invoice card.

**Invoice card sections**

| Section | Content |
| :---- | :---- |
| Header | Invoice Total, Balance Due, an Invoice Paid toggle marking the invoice as fully paid, and a Record Payment control |
| Bill To | Client legal name, contact email, contact person, phone, address, payment term, credit, invoice number and issue date |
| Ship To | Vendor name, contact person, email, phone, address and customer ID |
| Products | ID, Product Name, UOM, QTY, Tax %, Unit Price and Subtotal, calculated as quantity multiplied by price |
| Notes | Free-text notes on the invoice |
| Record a Payment | Invoice number, invoice total and balance due, filled automatically; the payment amount, payment method, an optional payment ID, the date and optional notes |
| Calculated blocks | Subtotal, Credit Applied, Delivery Fee, Taxable Amount, Invoice Total, Paid Amount and Balance Due |

**Functional rules**

| FR-VND-090 | The user shall be able to cancel the changes, save them, and download the invoice. |
| :---- | :---- |
| **FR-VND-091** | The Invoice Templates page shall display the available templates; the user selects a template and applies its settings so that invoices are produced from it automatically. |

## **6.20 Team management**

Manage the company’s employees: view, search, add and control their activity.

**Employee table**

| Column | Description |
| :---- | :---- |
| Role | Job title, for example Manager, Shipping Manager, CFO or Packer |
| Email | Work email address |
| Name | Display name |
| Active | Activity indicator; a tick marks an active employee |

**Team member profile**

| Field | Type | Description |
| :---- | :---- | :---- |
| Status | Read-only | Active or Blocked |
| Role | Dropdown | The user role, for example Shipping Manager, Packer or CFO |
| Assigned Store | Dropdown | Assigns the user to a store or division |
| Cell Phone Number | Masked input with country flag | The user’s mobile number |
| Email | Input | The user’s work email |
| First Name, Last Name | Input | The user’s name |
| Security section | Inputs | Current password, new password with a show or hide control, and repeat password |

**Team log entry**

| Field | Description |
| :---- | :---- |
| ID | Unique identifier of the log entry, in UUID form |
| Event | The action performed, for example "User Edited" |
| Team member | The entity acted upon, given as the user’s email address |
| Date | Exact timestamp of the change |
| User | The user or system that performed the action |

**Functional rules**

| FR-VND-092 | The employee table shall be paginated, with a per-page selector offering 10, 25 and 50 rows. |
| :---- | :---- |
| **FR-VND-093** | The search field shall filter entries by name, role or email as the user types. |
| **FR-VND-094** | The "+ Add Team Member" control shall open a form holding role, first name, last name, assigned store, email and cell phone number with a preset country code and input mask, with Discard and Save controls. |
| **FR-VND-095** | The role field is critical for access rights management. |
| **FR-VND-096** | The Logs control shall open the log of actions affecting team composition, such as additions, deactivations and role changes, for audit purposes. |
| **FR-VND-097** | The log shall be searchable by team member and by user, and filterable by date range. |
| **FR-VND-098** | An administrator shall be able to block a user, which moves the status to Blocked and restricts access to the system, and to delete a user with confirmation. |

## **6.21 Settings**

Hold the configuration that governs the vendor’s operation: profile, company, stores, restaurants, billing, delivery, permissions and notifications.

**Sections**

| Section | Content |
| :---- | :---- |
| General | The user profile: account type, first name, last name, role — edited by the CEO — email, cell phone number with country selection and mask, interface language and security code, with Discard and Save |
| Company | Company name (required), alternate or DBA name (optional), website (optional), date founded, contact phone number; hours of operation as working days chosen as chips and the operating time; the company logo, uploaded by drag and drop or from the device; and the contact people and emergency contact lists |
| My Stores | Store info: store name, display name, store address chosen from the address list, store products category, cell phone number and email, all required, plus an optional alternative or DBA name; hours of operation with working days and an interval in HH:MM-HH:MM form, extendable through "+ Add Hours of Operations"; licences, each with a type and a number, extendable through "+ Add License"; and the contact person and emergency contact lists |
| My Restaurants | A list of restaurants with "+ Add New", which opens a form holding restaurant name (required), alternate or DBA name (optional), display name, restaurant address with autocomplete, product categories as a multi-select, opening time, restaurant phone number with the mask \+1 (123) 456-7890 and email, with Back, Discard and Save |
| Billing | Billing methods shown as cards with "+ Add New". Adding a method offers a bank account, entered manually, PayPal, which redirects to PayPal, and Stripe, which redirects to Stripe. The bank account form holds routing number, account number and account type, all required; the bank address across two lines with city, state or province, country and postal code; and the account holder with an optional nickname |
| Delivery | Delivery fee, applied to orders that do not qualify for free delivery; the minimum order for free delivery; and the maximum mileage, which defines the delivery coverage area |
| Permissions | A role-based access matrix by module |
| Notifications | Notification settings presented in the same matrix form |

**Permissions matrix**

| Element | Detail |
| :---- | :---- |
| Modules | Orders, Vendors, Invoices, Product, Restaurants, Team, List of restaurants, Company |
| Rights | All Permissions, Create, View, Edit, Delete |
| Roles | CEO, CFO, Head Chef, Operations Manager, Business Partner, Third-Party Courier, Restaurant Manager, Shift Manager |

**Functional rules**

| FR-VND-099 | Fields marked with an asterisk are required before the settings can be saved. |
| :---- | :---- |
| **FR-VND-100** | The system shall validate the format of the data entered: email addresses, phone numbers and time intervals. |
| **FR-VND-101** | Contact persons and licences added here become available to every module of the system — orders, delivery and document handling. |
| **FR-VND-102** | Where a free delivery threshold is set, delivery becomes free once the order total reaches or exceeds it. |
| **FR-VND-103** | Orders with a delivery address beyond the maximum mileage cannot be placed, or require the delivery cost to be calculated individually. |
| **FR-VND-104** | Saved delivery rules shall apply immediately to all new orders. |
| **FR-VND-105** | Selecting "All Permissions" for a role shall grant that role the full set of rights — create, view, edit and delete — in the corresponding module, and may block the individual rights from being changed. |
| **FR-VND-106** | Rights shall otherwise be assignable independently of one another, so that a role may hold View and Edit without Create and Delete. |
| **FR-VND-107** | Changes to the permission matrix shall apply immediately after saving and shall affect both the interface and the functionality available to users holding those roles. |
| **FR-VND-108** | Permission changes are saved globally for the whole system. |
| **FR-VND-109** | The bank account form shall validate the data before saving, including the checksum of the routing number. |

# **Part 7\. Restaurant portal**

The restaurant portal is the buying side of the platform: the dashboard, the order flow from choosing a vendor through to checkout, the order card, and the confirmation exchange between restaurant and vendor. This part also records the financial calculation rules that both orders and invoices rely on, and the statement improvements agreed for the monthly statement.

Design reference: Chain Service Solutions, nodes 19528-333552 and 19528-333632; Chain Service Solutions, node 30328-337115; 2025-ccs, nodes 31847-230716 and 32529-58369.

*The backend and frontend task breakdowns present in the source — API contracts, database fields, migration notes, Swagger updates, test plans and hour estimates — are not reproduced here; they belong to implementation planning rather than to a description of system behaviour. Two areas of the source are marked as enhancements to existing behaviour rather than current behaviour: invoice transparency (backorders, item comments and discounts) and the financial calculation rules. Both are recorded because they define the arithmetic the rest of the module depends on, and are flagged in the open points.*

## **7.1 Dashboard**

Give the restaurant access to the main sections and actions immediately after registration, and show the key indicators once data has accumulated.

**Interface**

* Header: the CSS logo, which returns to this page; the restaurant switcher showing the current restaurant with a "Restaurant" label and opening the list of all restaurants; a settings icon; the search field; the notification icon; and the actions cart icon.

* Sidebar: Dashboard, Orders, Vendors, Invoices, Chats, Products, Teams, Settings, Logout.

* Footer: Support, Privacy Policy, Booking Policy and Terms of Service.

* Initial view: the welcome block "Welcome to your dashboard" and three calls to action — Upload Invoices, which opens the file dialog; Add Vendors, which opens the Vendors section; and Add Team Member, which opens the form for a new member.

* Populated view: the "Order on the way" table and the "Past Due Orders" table, each with Order ID, Customer, Date and Total; an overview block; and the notifications feed.

**Responsive behaviour**

| Breakpoint | View | Behaviour |
| :---- | :---- | :---- |
| Below 640px | Mobile | Hamburger menu; content in a single column |
| 640–1024px | Tablet | Collapsible side menu |
| Above 1024px | Desktop | Full menu on the left with the header above |

**Overview metrics**

| Metric | Meaning |
| :---- | :---- |
| Orders Past Due | Number of orders past their due date |
| Orders Paid | Number of orders paid |
| Orders to Be Paid | Number of orders still to be paid |

**Functional rules**

| FR-RST-001 | The overview shall offer a period selector with Today, Week, Month and Year, and the metrics shall be recalculated for the selected period. |
| :---- | :---- |
| **FR-RST-002** | The notifications feed shall list events such as "Order \#12345 is past due delivery"; clicking a row shall open a modal with the order details. |

## **7.2 Financial calculation rules**

Define one set of arithmetic for orders and invoices, so that the restaurant and the vendor always see the same totals.

**Calculation sequence**

| Step | Rule |
| :---- | :---- |
| Line base price | line\_base \= qty × price |
| Line discount, percentage | line\_disc \= line\_base × (discount\_value / 100), capped at 100% |
| Line discount, absolute | line\_disc \= discount\_value, and it cannot exceed line\_base |
| Net line total | line\_net \= max(line\_base − line\_disc, 0\) |
| Subtotal | subtotal \= the sum of all line\_net values |
| GST | gst \= subtotal × gst\_rate |
| Tax | tax \= subtotal × tax\_rate |
| Freight | A fixed positive amount |
| Grand total | grand\_total \= subtotal \+ freight − additional discount |
| Rounding | Standardised — banker’s rounding or another defined business rule — and identical in the frontend and the backend |

**Functional rules**

| FR-RST-003 | New fields are added for order and invoice items: discount\_type, holding either percent or absolute, and discount\_value. Orders and invoices carry gst\_rate. |
| :---- | :---- |
| **FR-RST-004** | The existing tax and freight fields remain part of the calculation. |
| **FR-RST-005** | Negative values shall not be accepted. |
| **FR-RST-006** | A percentage discount shall not exceed 100%, and an absolute discount shall not exceed the line base. |
| **FR-RST-007** | Totals shall be recalculated automatically and in real time when a discount, GST, tax or freight value changes. |
| **FR-RST-008** | The calculation shall always produce identical results in the frontend and the backend. |
| **FR-RST-009** | Existing API consumers shall continue to work; the functionality extends the current order and invoice system without breaking existing flows. |

## **7.3 Invoice transparency — backorders, comments and discounts**

Make an invoice readable as a financial document: show what was short-shipped, why, and what was discounted.

**Functional rules**

| FR-RST-010 | A backorder column shall be added to the invoice item table, showing the shortfall per line. |
| :---- | :---- |
| **FR-RST-011** | Where a shortage exists the value shall be shown and highlighted; where none exists the row shall render cleanly without it. |
| **FR-RST-012** | A free-text comment shall be attachable to an individual item when the invoice is created or edited, and shall be displayed beneath or beside the item description. |
| **FR-RST-013** | Comments shall support line breaks and basic formatting, and shall be addable, editable and deletable, persisting when the invoice is submitted. |
| **FR-RST-014** | Discounts shall be supported at line level and at order level. |
| **FR-RST-015** | The summary block shall display the total discount, and the final amount shall reflect it both visually and numerically. |
| **FR-RST-016** | The summary block shall update dynamically and shall remain compatible with the existing tax and freight displays. |
| **FR-RST-017** | The display shall be identical in the web interface and in the exported PDF, with the fields aligned for readability. |

## **7.4 Orders — list**

Give both sides one table for working with orders, with search, filters, export and navigation into an order.

**Status model**

| Status | Meaning |
| :---- | :---- |
| new | A new order |
| confirmed | The order has been confirmed by the buyer and sent |
| pending | The order is being assembled and delivered |
| delivered | The goods have arrived at the restaurant and been accepted there |
| cancelled | The order was cancelled |

**Table columns**

| Column | Description | Visible to |
| :---- | :---- | :---- |
| ID | Unique order identifier | Vendor, restaurant |
| Client | The client who placed the order | Vendor |
| Vendor | The vendor the order was placed with | Restaurant |
| Ordered Date | Date the order was placed; used by the date range filter | Vendor, restaurant |
| Delivery Date | Planned or actual delivery date; used by the date range filter | Vendor, restaurant |
| Products | Number of product lines in the order | Vendor, restaurant |
| Credit | Credit applied to the order; affects the total | Vendor, restaurant |
| Total | Order total | Vendor, restaurant |

**Functional rules**

| FR-RST-018 | The table shall provide string search, a date range filter over the ordered or the delivery date, pagination and a status filter. |
| :---- | :---- |
| **FR-RST-019** | Clicking a row shall open the card of that order. |
| **FR-RST-020** | A "Create Order" control shall be available on the orders page. |
| **FR-RST-021** | The revised main page shall offer a basic search with the placeholder "Search by Order \#, PO \#" and an advanced filter toggle covering vendor or restaurant, products, address and customer ID. |
| **FR-RST-022** | The date range picker shall offer the presets Today, Last 7 Days and Last 30 Days; where the user picks the start date first, earlier end dates shall be blocked, and where the end date is picked first, later start dates shall be blocked. |
| **FR-RST-023** | The items-per-page selector shall offer 10, 25, 50 and 100\. |
| **FR-RST-024** | Export shall open a modal offering all orders with the current status, all orders, or the current page, with CSV or PDF as the format. |
| **FR-RST-025** | Sorting shall be available on every column header, and each header shall carry a filter icon rather than a separate filter control. |
| **FR-RST-026** | A Print control shall print the current page view; the separate download control is removed, since export covers it. |
| **FR-RST-027** | The empty state shall read "No orders found" with a control to reset the filters; loading shall use skeleton placeholders; filters shall collapse into an accordion on tablet and mobile and shall persist for the session. |

## **7.5 Orders — creating an order**

Take the restaurant from choosing a vendor to a submitted order.

**Interaction logic**

**Step 1 — choose a vendor**

* Where the restaurant has no orders yet, the Orders page shows an illustration with the message that there are no orders yet and an invitation to choose a vendor, together with the expanded "All Vendors" block.

* Where at least one order exists, "Create Order" opens the same screen with "Your Vendors" expanded and "All Vendors" collapsed by default.

* Vendors are split into two tabs: Your Vendors, holding vendors the restaurant has at least one order with, including orders created automatically from invoices; and All Vendors, holding every vendor in the system. A vendor may appear in both.

* Search covers name, email, address and phone, and runs across all vendors rather than only those with current orders; entering a query opens the results list automatically.

* Filters cover vendor type and sub-category — for example Products with Meat, Produce, and separately Uniform or Packaging — and a filter pop-up adds category, sub-category and city.

* Where Your Vendors is empty, an "Invite Vendor" control shall be displayed, allowing an invitation to be sent to a new vendor.

* The vendor list is displayed in two columns, collapsing to one on mobile.

**Step 2 — the vendor catalog**

* After a vendor is selected, the screen offers the tabs Catalog, which opens by default, Orders, Finance, Invoices, Support and Info. The Return Policy tab is removed until it is needed.

* The Finance tab shows the standard payment terms for a new restaurant, or the terms already agreed.

* The Catalog tab offers category navigation as horizontal pills or a left-hand accordion, a product search and an items-per-page selector.

* The price comparison selector, renamed "Compare Prices To", offers Previous Order, Last 7 Days, Last 30 Days, Last Quarter and Last Year.

* The product table holds ID, Image, Category, Name, UoM, Current Price, Prior Price, Qty and Action. The quantity field is editable by hand or with controls, and every column except Image and Action is sortable.

* Once a quantity is non-zero, a summary bar appears at the foot showing the running order total and a Next control.

**Step 3 — payment and delivery**

* Where several payment methods exist the user selects one; otherwise the method is read-only.

* The delivery block reads "Choose desired delivery date & time. (Vendor may adjust before confirming.)"

* Above the fields the system displays the delivery days and time windows the vendor has declared, for example "Vendor delivers: Mon, Wed, Fri, 09:00–12:00, 14:00–18:00".

* The date picker blocks dates in the past; the time picker accepts free entry.

* The right-hand sidebar shows the editable Deliver To block with name, contact, phone and address.

* The footer offers "Proceed to Checkout" and "Back".

**Step 4 — review and confirm**

* The page is titled "Review Your Order" and shows the order info: customer number, payment method, salesperson, invoice number, shipping method, PO number, credit, order date and the delivery ETA with an Edit control.

* Bill To shows the vendor and Ship To the restaurant, each with name, email, contact, phone and address.

* The line item table carries ID, Product Name, UoM, Ordered, Vendor QTY, Tax %, Unit price with subtotal, and a remove control. "Add Products" opens the catalog overlay.

* A comment block offers "Add a comment to your order…".

## **7.6 Orders — order card**

Show one order in full. The vendor sees the complete card; the restaurant sees a reduced version of the same screen.

**Vendor card — product table**

| Column | Description | Editable by vendor |
| :---- | :---- | :---- |
| Product ID | Unique product identifier | No |
| Product Name | Product name | No |
| Unit of Measure | Unit of measure | No |
| Order Quantity | Quantity originally ordered | No |
| B/O | Backorder — the shortfall | Yes |
| Edit Quantity | The quantity the vendor is prepared to ship | Yes |
| Unit Price | Base price per unit | Yes |
| Discount | Discount as a percentage or an absolute amount; deducted from the price | Yes |
| Tax | Tax amount; added to the price | Yes |
| GST | Goods and services tax; added to the price | Yes |
| Subtotal | Calculated as (Unit Price − Discount) \+ Tax \+ GST | No |

**Vendor card — details section**

| Field | Behaviour |
| :---- | :---- |
| Order ID | Repeats the identifier from the header |
| Restaurant | The restaurant the goods ship to, with a Details control opening the client page on its Information tab |
| Credit | Credit applied to the order; affects the total |
| Freight Fee | Delivery cost; edited through an Edit control and confirmed through Submit |
| Tax | Total tax on the order in dollars |
| GST | Total goods and services tax in dollars |
| Discount | The final discount, shown in dollars or as a percentage, added through an Add control and confirmed through Submit; deducted from the total |
| Total | Calculated from the product subtotals together with credit, freight fee, tax, GST and discount |

**Functional rules**

| FR-RST-028 | The card header shall show the breadcrumb to the Orders page, the order number and the current status. |
| :---- | :---- |
| **FR-RST-029** | Where an order is past due, the card shall display "Order is past due, please contact your client to manage financial questions" together with a "Go to Chat" control. |
| **FR-RST-030** | The vendor card shall offer Duplicate, which creates a new order from the current one; Generate Invoice, which then activates Download Invoice; and Cancel, which moves the order to cancelled. |
| **FR-RST-031** | The card shall show the order date and the requested delivery date and time, with a Change control that lets the vendor edit them. |
| **FR-RST-032** | The vendor card shall show the Bill To and Ship To blocks together with payment term, credit, invoice number, order date and customer ID. |
| **FR-RST-033** | A row can be deleted from the product table, and "Add Product" adds a row below it; the new row offers a search in the product name field, and selecting a product loads its data, including the unit price. |
| **FR-RST-034** | A counter below the table shall show the number of unique products in the order. |
| **FR-RST-035** | The confirmation block shall read "Let your customer know that their order has been received", offer a comment field for the client, and provide "Cancel Order" and "Confirm Order" at the foot of the page. |
| **FR-RST-036** | The restaurant card is a reduced version of the same screen: it shows the breadcrumb, the status, the order date, the requested delivery with a Change control that lets the restaurant set its preferred date and time, Duplicate and Cancel. |
| **FR-RST-037** | The restaurant card shall not offer Generate Invoice or Download Invoice, and shall not display the Ship To and Bill To blocks. |
| **FR-RST-038** | On the restaurant card the product table shall show product ID, name and unit of measure as on the vendor card; the quantity ordered; the unit price as the current and the prior price within one cell; the discount in two fields; and the tax — all read-only. |
| **FR-RST-039** | On the restaurant card the restaurant may edit the quantity and delete a row. |
| **FR-RST-040** | On the restaurant card the details section shows the vendor instead of the client, with a Details control opening the Vendors section on its Information tab, and every financial field — total, credit, freight fee, tax, GST and discount — is read-only. |
| **FR-RST-041** | Where the restaurant makes changes, an "Order has been edited" block shall appear, offering a text message and a "Confirm Changes" control. |
| **FR-RST-042** | The restaurant card shall not offer "Confirm Order" and "Cancel Order" at the foot of the page, because the restaurant confirms its changes rather than the order itself. |

## **7.7 Vendor confirmation of an order**

Let the vendor review a new order, adjust what it can actually ship, and confirm or cancel it.

**Interaction logic**

**Notification and entry**

* When a new order is created in the restaurant system, the vendor receives a push notification or an email titled "New Order Received".

* The vendor opens the Orders section and selects the order, arriving at the "Review Your Order" screen.

**Order information**

* The order info is laid out in two columns: customer number, salesperson, shipping method, credit and delivery ETA on the left; payment method, invoice number, PO number, order date and delivery date on the right.

* The Edit control in the delivery section lets the vendor select a new delivery date and time within its declared delivery days and time windows.

* Bill To, showing the vendor, and Ship To, showing the customer, are read-only: name, email, contact person, phone and address.

**Line items and stock**

* The line item table holds ID, Product Name, UoM, Ordered, Vendor Qty, Tax %, unit price with subtotal, and a remove control.

* Ordered is the quantity requested by the restaurant. Vendor Qty is the quantity available in vendor stock and is editable, as are the tax percentage and the unit price.

* "Add Products", below the table, opens the catalog overlay where further products can be found and added.

* Immediately after the table loads, every product whose ordered quantity exceeds available stock shall be highlighted with a warning row reading "Insufficient stock for \[product\]. Please confirm availability or update stock."

* The vendor may either confirm that stock is sufficient, through a Confirm Stock action, or update the vendor quantity by hand.

**Functional rules**

| FR-RST-043 | Where the order details section holds Taxable Amount, Delivery Fee, Credit Applied and Total, those fields shall remain visible. |
| :---- | :---- |
| **FR-RST-044** | The delivery fee shall be editable directly on the confirmation screen. |
| **FR-RST-045** | An optional comments field shall be available. |
| **FR-RST-046** | A "Go to Chat" control shall be available in the header or beside the page title, opening the chat with the responsible restaurant contact. |
| **FR-RST-047** | Confirming the order shall save every change — delivery date and time, prices, taxes, removed items, added products and the delivery fee — update the order, move its status to confirmed, and notify the restaurant. |
| **FR-RST-048** | Cancelling the order shall cancel it in full, notify the restaurant, and return the vendor to the orders list. |

## **7.8 Restaurant response to a vendor confirmation**

Give the restaurant a bounded window to accept or reject the changes a vendor made while confirming.

**Interaction logic**

**Where the vendor changed the order**

* The restaurant receives a notification and sees a warning block below the line item table.

* The block opens with an attention heading, states that the vendor has made changes, and lists them.

* It states that the restaurant has 30 minutes to confirm or cancel, after which the order is confirmed automatically and can still be cancelled from the order page.

* A countdown timer runs in the block, starting from 30 minutes at the moment of the vendor’s confirmation.

* Two controls sit to the right of the block below the timer — Cancel Order and Confirm Order — and the same pair is repeated at the foot of the page below the product list. Both sets trigger the same actions.

**Where the vendor changed nothing**

* The restaurant receives only a notification that the order is confirmed.

* No warning block and no timer are displayed, and the order status moves to confirmed automatically.

**Functional rules**

| FR-RST-049 | When the timer reaches zero the order shall be confirmed automatically, and the restaurant shall no longer be able to reject the confirmation through this flow. |
| :---- | :---- |
| **FR-RST-050** | Cancellation shall remain available from the order page under the existing cancellation rules. |
| **FR-RST-051** | Order comments shall not be displayed while the warning block is active; the comments section stays hidden until the order is confirmed. |
| **FR-RST-052** | The system shall compare the original restaurant order against the vendor-confirmed order and detect changes in products, quantities, prices, taxes, the delivery fee and the other editable fields, storing them for display in the warning block. |

## **7.9 Store product upload**

Let store-level users create and update products in bulk from a file or pasted table, with conflict handling.

**Scope and access**

| Aspect | Rule |
| :---- | :---- |
| Level | Store. The vendor company reads an aggregate of the products of all its stores, read-only; upload and editing happen at the level of a specific store. |
| Access | Every role above packer and driver, provided the user has access to that store. Packers and drivers have no access to the uploader. |
| Sources | File — CSV, Excel (.xlsx, .xls) or TXT — or a table pasted into the interface, which follows the same mapping logic and allows edits before import. |
| Mandatory fields | Product name, product price, product unit (UoM) and product category |
| Currency | USD only |

**Functional rules**

| FR-RST-053 | The Category column must be mapped, but individual rows may leave the value empty and are still imported. |
| :---- | :---- |
| **FR-RST-054** | Where no tax column exists, the price read from the file is treated as final and stored as it is. Where a tax column exists, its value is stored in a separate tax field and the price is not recalculated. |
| **FR-RST-055** | A catalog shall be created automatically for the store on the first successful upload; the catalog is not named and cannot be renamed. |
| **FR-RST-056** | Matching shall be performed only within the catalog of that store. |
| **FR-RST-057** | The identification key on update shall be the product name together with the vendor ID where one is given, and the product name alone where it is not. |
| **FR-RST-058** | The vendor ID is an external custom field holding one value per product, and cannot be changed after creation. |
| **FR-RST-059** | Where the name or key matches but the category or unit of measure differs, the system shall display a conflict pop-up offering to update the existing product, which is the default, or to create a new one; bulk actions shall apply a decision to all similar conflicts. |
| **FR-RST-060** | Units of measure shall be held in one system-wide dictionary. On meeting a new value the system shall offer similar entries by fuzzy match; where none is chosen, the new value shall be added as it stands. |
| **FR-RST-061** | Where mandatory columns are missing, the import shall not start. |
| **FR-RST-062** | Where only some rows carry errors or gaps, the system shall display the problematic rows and import the correct ones. |
| **FR-RST-063** | Two file columns shall not be mappable to the same system field. |
| **FR-RST-064** | Import runs asynchronously; the user may leave the page, and the summary reports records added, updated and skipped, together with the conflict and error counts. |
| **FR-RST-065** | Repeating the process step for the same session shall not create duplicates. |
| **FR-RST-066** | Parallel uploads into one store shall be queued rather than run together. |

**Edge cases and error handling**

| FR-RST-067 | Upload history, rollback, report export and a visual before-and-after comparison are outside this release. |
| :---- | :---- |

## **7.10 Monthly statement**

Make the monthly statement readable and correct as a financial document sent to a client.

**Agreed changes**

| Area | Requirement |
| :---- | :---- |
| Header and title | A bold "Monthly Statement" title, larger than the company name; the company logo; and dual-language names, for example English and Chinese |
| Column structure | Transaction type and payment method split into separate columns rather than combined under Description or Reference; "Description" renamed to "Type"; "Payment" renamed to "Paid" where the column exists; unused columns such as Check Number or Date Paid removed where no data exists |
| Payment method | Shown only for paid invoices; blank for unpaid ones |
| Overdue handling | Invoices more than 30 days overdue flagged with a visual indicator such as a red "Overdue" label or a coloured background |
| Data integrity | The first line shows the balance forward from the previous period, displaying 0.00 where it is zero; spelling corrected, for example "Aint Due" to "Amount Due" |
| Formatting | Monetary amounts right-aligned, dates centre-aligned, fonts larger and darker to fix the light-ink problem, and summary fields such as "Total Amount Due" and "Over 30 Days" formatted consistently |
| Customisation | Custom comments, as for invoice templates, and a preview of the monthly statement when a vendor invoice template is selected |

# **Open points**

The following items require a decision from the client before the corresponding behaviour can be treated as final.

**Part 1 — Quotation**

| Item | Decision needed |
| :---- | :---- |
| Convert to Invoice permissions | Whether the action is restricted to manager roles, or governed by a configurable approval rule under which salespersons may convert quotations independently. |
| Gross profit calculation | Confirmation that the implemented formula excludes taxes and freight, in line with Gross Profit \= (Sell Price − Net Price) × Sold Quantity. |
| Zero-value totals in the preview | Whether a row with a $0.00 value is displayed as $0.00 or hidden when its display checkbox is checked. |
| Alphabet counts in the add-group modal | Whether counts exclude manufacturers already added to the quotation, or include them while keeping them disabled. |
| Price display with no checkbox selected | Whether the system falls back to "Without Price" or forces at least one checkbox to remain selected. |

**Part 2 — Manufacturer module**

| Item | Decision needed |
| :---- | :---- |
| Data source for the General Terms column | The column exists and is populated, but the entity behind it is not defined. The Figma mock-ups show composite values of different kinds in one cell ("Restaurant", "Vendor", "42% markup"). Addressed by the agreed change set of 28 July 2026\. |
| Operations counted by Last Transaction | The column exists but the set of operations it reflects is undefined; earlier discussions mixed order statuses, quotations and deliveries. Addressed by the agreed change set of 28 July 2026\. |
| Status enumeration in the schema | The manufacturer entity schema lists three statuses (Preferred, Approved, Not Approved), while the interface offers four, including Not Assigned. The schema should be aligned. |
| Automatic application of category discounts | Category multiplier and margin are informational today. Whether they should drive catalog or quotation pricing requires separate analysis and a separate estimate. |

**Part 3 — Manufacturer catalog**

| Item | Decision needed |
| :---- | :---- |
| Two different sets of mandatory fields | The business rules define four mandatory fields for a catalog upload — product name or description, SKU or ID, price and unit of measure — while the reference data model defines eleven required fields, among them model number, list price, both descriptions, the product dimensions, unit weight and the main image, and contains neither a SKU nor a unit of measure field at all. Validation cannot implement both. Which set is authoritative has to be settled before the import is built. |
| The identifier and the uniqueness key | One source states that the SKU or ID is unique within the company catalog; the other identifies a product by the combination of CSS customer number and model number. These produce different duplicate detection and different update behaviour. |
| PDF handling | The acceptance criteria require the system to parse PDF files and display their contents in the mapping interface, and name a dedicated PDF parsing route. The bulk upload specification states the opposite: a PDF cancels the automated import and is passed to a manual back-office process taking up to five days. One of the two has to be withdrawn. |
| Behaviour on invalid rows | The source flags this itself as needing a business decision: block the whole import until every row is corrected, or import the valid rows and report the rest. The assumption currently recorded is to block. |
| What "Format File" does | The H-1 modal offers automatic formatting of a malformed file, while the scope states that automated data cleaning is excluded and that the user must correct the data. The extent of the automatic formatting needs defining, or the option needs removing. |
| Parent-child variations | Validation must block child variations without a valid parent reference, and the AI layer is expected to generate product variations, but the catalog data model holds no parent, variation or attribute fields to carry that relationship. |
| Import modes versus the upsert rule | The user selects one of three import modes — create, update, or create or update — while the data model rule states unconditionally that an existing record is updated and a missing one is inserted. The interaction between the two needs defining, in particular what "create new" does when it meets an existing key. |
| The AI accuracy target | One acceptance criterion requires the engine to identify at least 80% of standard product fields correctly. How that percentage is measured, on which sample, and who signs it off, is not defined, so the criterion cannot currently be tested. |
| Limits pending confirmation | The 25 MB file size limit is marked as subject to architecture confirmation, and the 10,000-row limit is stated without one. Both should be confirmed, together with the behaviour when a file exceeds them. |
| Price restriction for restaurant clients | Restaurant clients receive a "price-restricted" view. Which prices are hidden — the list price, the vendor’s net price, or both — is not stated, and Part 1 already defines a price visibility model for quotations that this should agree with. |
| Overlap with the admin import | The subscriber upload described here shares the wizard with the catalog upload, while Part 4 describes a separate company import in the admin panel with its own mapping rules and its own required fields. Whether these are one mechanism or two needs deciding. |

**Part 4 — Admin panel**

| Item | Decision needed |
| :---- | :---- |
| A NOT SUBSCRIBED company in the subscriber table | The subscriber table is defined as holding companies with ACTIVE or EXPIRED status only, and NOT SUBSCRIBED "does not occur there by definition". The client creation flow states the opposite: a company created through "+ Add new" carries NOT SUBSCRIBED status and "appears in the master database and in Subscribers at the same time". Bulk edit adds a third position, under which setting NOT SUBSCRIBED makes a company disappear from the subscriber table. One of the three has to give. |
| The Delete button in the subscriber table | Delete is hidden there on the grounds that every record holds a protected status. That reasoning only holds while NOT SUBSCRIBED records never appear in the table, so it depends on the point above. |
| Merge deletes protected companies | A merge deletes subordinate companies with ACTIVE or EXPIRED status as an explicit exception to the deletion rule. Whether the licence history, invoices and payment records of those companies are carried into the master record or lost with them is not defined, and the same data is what the deletion rule exists to protect. |
| Licence reduction below the seats in use | The new count is written to the database immediately while the remaining-seats figure keeps showing the previous value until the expiration date. What happens where the subscription is renewed rather than expiring, and what the system does if the company never reaches that date, is undefined. It is also unclear whether new users can be registered in the meantime. |
| Overwriting the activation date on registration | The administrator-entered activation date is replaced by the actual registration date and the expiration date is recalculated. Whether that overwrite is recorded on the Licenses tab as "Activation date changed" — and against which administrator, since the system made the change — is not stated. |
| Type change validation versus bulk edit | Section 3.12 fixes the company type permanently once type-specific data exists. Bulk edit offers a company type field and a cascade that changes the type of subsidiaries. Whether the same validation runs on the bulk path, and what happens where some of the selected companies or subsidiaries are blocked while others are not, is undefined. |
| Cascading a type change to subsidiaries | Under "Change type for all subsidiaries" the subsidiaries take the parent’s new type. Each of them may hold its own blocking data, so a partial failure is possible. The behaviour — all or nothing, or apply where permitted and report the rest — has to be decided. |
| Duplicate detection on import | Uniqueness is defined as an exact match on company name. Since a company can now exist in the database with the same name under a different type, whether the check is scoped by type needs to be confirmed. |
| Role-based access control | The "+ Add new" button is hidden from administrators without the right to create clients, with the note that role-based access control will be implemented later. Until it exists, every other action in this part is available to every administrator. |

**Part 5 — Authentication and onboarding**

| Item | Decision needed |
| :---- | :---- |
| Password complexity is defined twice, differently | Sign-up requires a minimum of 6 characters with uppercase, lowercase and a special character. The password reset screen requires a minimum of 8 characters with uppercase, lowercase, a digit and a special character. A user who resets their password is therefore held to a stricter rule than one who registers. |
| Company logo size limit | The onboarding attribute table gives the limit as 5 GB, while the company information screen gives 5 MB. The 5 MB figure is assumed to be correct. |
| Core team screen: required fields versus skipping | The screen states that every field is required, and also that at least one participant is saved where the form is submitted with missing information. The two statements need reconciling, and the behaviour of "I'll do it later" when no member has been entered must be defined. |
| Screen 4: skipping versus the Next condition | "I'll do it later" is described as skipping the step, with the note that at least one restaurant or store will remain, while Next is active only once one has been added. What exists after a skip — a placeholder location, or none — is undefined. |
| Sign-in: where the password is entered | The flow states that the password field appears "on the same page or in the next step". One behaviour has to be chosen. |
| Sign-in: when the code is sent | The behaviour section states that the code is delivered after Sign In is clicked for the email method and after Next is clicked for the phone method. The trigger should be the same for both. |
| Security questions and account lockout | The user acknowledges that the account will be locked if the question cannot be answered, but no unlock or administrator recovery path is documented. |
| Invitation code lifetime at sign-up | The code is limited to 20 characters and verified through the API, but nothing states whether it expires, or what the user sees where the code has already been used. |

**Part 6 — Vendor portal**

| Item | Decision needed |
| :---- | :---- |
| Two different dashboards | The source describes an early dashboard with two blocks — pending and past due orders — and a later one with three order tables, a metrics block, a period selector and a notifications feed. Which is current needs confirming; the later version is the one recorded here. |
| Sidebar composition | The main menu is listed twice with different contents: one list omits Claims and Invoices ordering, the other includes Claims between Packing Slips and Chats. The Claims module itself is named in the navigation but described nowhere in the source. |
| Order status vocabulary | The order list is described once with the statuses New, Confirmed, Pending, Delivered and Canceled, and once with New, Confirmed, On The Way, Arrived, Delivered and Canceled. The order card assumes the second set, since its action button changes label for On the way and Arrived. Pending appears only in the first set and is never defined. |
| Order table columns | Two column sets are given for the same table: one with ID, Client, Ordered, Delivery, Products, Credit and Total; the other with Date, Client, Manufacturer, Order Date, Ship Date, Total and OS Balance. OS Balance and Manufacturer appear in the second only. |
| Invoice product table columns | Three versions exist. The redesign specifies ID, Product Name, UOM, QTY, Unit Price, B/O, Discount, Tax, GST and Subtotal, with Subtotal as quantity times price less discount plus tax plus GST. The current invoice card specifies ID, Product Name, UOM, QTY, Tax, Unit Price and Subtotal, with Subtotal as quantity times price. B/O, Discount and GST are absent from the current version. |
| Discount visibility on invoices | The changes agreed on 3 September 2025 require internal discounts, assigned through settings, to be hidden from the client while other discounts remain visible. The rule that separates the two is not written down anywhere. |
| Same-day numbering option | The client profile description lists the "one or more invoices in one day" section as holding two options but names only the first. The algorithm elsewhere names both: numbering through a slash, and sequential numbering. |
| Letter designation requirement | One statement makes the letter designation mandatory when By Date is selected and optional otherwise; another describes it as an optional field throughout. The mandatory rule is the later one. |
| Invoice numbering as implemented | The engineering report in the source states that the current implementation does not split letters from digits, does not store the letter position, has no working search for the maximum number, has no same-day logic and no transactional protection, so that several invoices issued on the same day can collide on the same number. The algorithm described in section 6.17 therefore documents the intended behaviour rather than what the code does today. |
| Master invoice upload permissions | Master invoice upload is available to specific users rather than to roles, and is disabled by default. This sits outside the role-based permission matrix in the settings and needs reconciling with it. |
| Permissions and notifications share one description | The Notifications section is described with the same permission matrix as Permissions, including the note that the Permissions tab is active. The actual notification settings are not described. |
| Settings navigation is inconsistent | The available sections are listed as General, Company, My Restaurants, My Stores, Billing, Delivery, Permissions and Notifications in one place, and as General, Company, My Stores, Billing, Delivery, Finance, Permissions, Notifications and Return policy in another. Finance and Return policy appear only in the second list and are not described. |
| Save control in the permission matrix | The source notes that Save controls are not visible on the screenshots but are assumed to exist. Whether the matrix saves explicitly or applies changes immediately needs confirming, since the same text also states that changes apply immediately. |
| Roles in the permission matrix | The roles listed — CEO, CFO, Head Chef, Operations Manager, Business Partner, Third-Party Courier, Restaurant Manager, Shift Manager — are restaurant-side roles, while the team module uses vendor-side roles such as Shipping Manager and Packer. The two lists need aligning. |
| Claims module | Claims appear in the sidebar and as a document type on the order card, but no requirements describe the module. |

**Part 7 — Restaurant portal**

| Item | Decision needed |
| :---- | :---- |
| Grand total omits tax and GST | The calculation sequence defines gst and tax as derived from the subtotal, but the grand total is given as subtotal plus freight less the additional discount, with neither tax nor GST added and credit not mentioned. The order card meanwhile states that the total is calculated from the subtotals together with credit, freight fee, tax, GST and discount. The formula has to be corrected before it is implemented, since it is stated as the single source of truth for both frontend and backend. |
| Subtotal at line level | The order card defines the line subtotal as (Unit Price − Discount) \+ Tax \+ GST, which omits the quantity, while the calculation rules define it as quantity times price less the discount, with GST and tax applied to the subtotal of the whole document rather than per line. The two definitions produce different numbers. |
| Two order status models | The status model in this part lists new, confirmed, pending, delivered and cancelled. The revised orders table lists New, Confirmed, On the Way, Arrived, Delivered and Canceled, which matches the vendor portal. Pending appears only in the first list, and On the Way and Arrived only in the second. |
| Who confirms first | The status model defines "confirmed" as confirmed by the buyer and sent, while the vendor confirmation flow has the vendor confirming the order and the restaurant then accepting or rejecting the vendor’s changes. The meaning of the confirmed status needs to be pinned to one of the two. |
| The 30-minute window | An order confirms itself automatically when the timer expires. What happens where the restaurant is closed overnight, or where the change is a price increase, is not addressed, and the source gives no business justification for 30 minutes specifically. |
| Change list content | The warning block lists the changes the vendor made, but the format of that list is not defined — whether it shows before and after values, and whether a price change is distinguished from a quantity change. |
| Duplicate import wizard | The bulk upload wizard reproduced in this source is the same one already specified for the manufacturer catalog and the admin panel, and a third variant appears here as the store product upload with different mandatory fields and a different identification key. Whether these are one mechanism configured differently, or separate implementations, needs deciding. |
| Store product mandatory fields | The store product upload requires product name, price, unit of measure and category; the manufacturer catalog requires a different set built around model number and list price. Both are described as the product import. |
| Restaurant order card discount fields | The restaurant card shows the discount "in two fields" without saying which two, and shows the unit price as current and prior within one cell. The presentation needs specifying. |
| Sidebar composition | The restaurant sidebar lists Dashboard, Orders, Vendors, Invoices, Chats, Products, Teams and Settings, with no Packing Slips and no Claims. The vendor sidebar carries both. Whether the restaurant is meant to see delivery documents at all is not stated. |
| Statement is a redesign | The monthly statement section is a list of corrections to an existing document rather than a description of it. The statement as it stands today is not described anywhere, so the section records the target rather than the current state. |
| Invoice transparency and financial calculations are enhancements | Both sections are written as additions to the existing system, with backward compatibility called out explicitly. They are recorded here because the rest of the module depends on their arithmetic, but they describe behaviour that is not yet in place. |

# **Glossary**

The glossary covers the vocabulary used across every part of this document. Terms are grouped by subject rather than alphabetically, so that related concepts — the three prices, the order statuses, the several kinds of discount — can be read together. Where the same term carries different meanings in different modules, both are given and the difference is stated.

**Parties and roles**

| Term | Definition |
| :---- | :---- |
| CSS | Chain Service Solutions — the platform described in this document |
| Manufacturer (MFR) | The company that produces goods, publishes a catalog and confirms purchase orders from dealers |
| Manufacturer’s representative | An agent who promotes a manufacturer’s brand, works with chains and dealers, and may prepare quotes on the factory’s behalf |
| Representation agency | The agency representing a manufacturer in a territory; its name feeds the MFR Rep column of the manufacturer list |
| Vendor | The equipment and supply dealer that buys from manufacturers and sells to restaurants. Also called the E\&S dealer |
| E\&S | Equipment and Supply — the market sector the platform serves |
| Store | A physical location belonging to a vendor. Products, stock and prices are managed at store level |
| F\&B client | Food and Beverage client — the restaurant or hospitality business that receives quotations and places orders |
| Restaurant client | The same party seen from the catalog side, holding a read-only, price-restricted view of the technical catalog |
| Buying group | An organisation that consolidates dealer volume to negotiate better manufacturer terms in exchange for a commission |
| National chain accounts (NAS) | Large restaurant chains that may run their own purchasing department and buy directly |
| Subscriber | A company holding a paid or previously paid subscription to the platform |
| CSS administrator | The platform administrator who maintains the master database, subscribers and reference data |
| Vendor company CEO | The senior vendor role holding full access to the client database and company settings |
| Store shipping manager | The vendor role responsible for keeping the product lineup current and processing write-offs |
| Salesperson | The vendor employee who owns a quotation or order; sees only their own quotations unless a manager reassigns them |
| Packer | The warehouse role that assembles an order against the packing slip and marks it ready to ship |
| Driver | The delivery role that picks up, delivers and confirms delivery of an order |
| Third-party courier | An external delivery party, present in the permission matrix as a role |
| Team member | An employee account within a vendor or restaurant company, holding a role and an assigned store |
| Contact person | A named individual attached to a company record, carrying an email and a phone number |
| Accounts payable contact | The finance contact recorded separately from the general company contacts |
| CSS AI Assistant | The automated support agent in the in-platform support widget |
| Live rep | A human support agent, reachable from the same widget when the automated answer is not enough |

**Commercial documents**

| Term | Definition |
| :---- | :---- |
| Request for Quotation (RFQ) | The list of items a restaurant sends to selected dealers asking for prices |
| Quotation | The dealer’s priced offer to a client. Also called the quotation sheet when referring to its line items |
| Purchase Order (PO) | The order document issued by the buyer to the seller once a quotation is agreed; also raised by a dealer to a manufacturer |
| Invoice | The demand for payment issued by the seller once a purchase order is accepted |
| Master invoice | The first invoice uploaded for a client, used to create the client automatically and to recognise its data through the AI module |
| Issued invoice | An invoice generated by the platform, as opposed to an uploaded historical one |
| Recognized data | The fields extracted from an uploaded invoice PDF, available for manual correction |
| Invoice template | One of the fixed layouts an invoice or statement is rendered with; templates are selectable but cannot be uploaded |
| Packing slip | The document used by the packer to assemble an order and by the driver to deliver it |
| Claim | A document type attached to an order; named in the navigation and in the document list but not otherwise specified |
| Statement | The periodic summary of invoices, payments and balance sent to a client |
| Monthly statement | The statement covering one calendar month, headed by the balance forward from the previous period |
| Balance forward | The opening balance carried into a statement from the previous period, shown as 0.00 where it is zero |
| Credit memo | A transaction type appearing in the statement Type column |
| Order | The transaction record between restaurant and vendor, from creation through delivery |

**Statuses**

| Term | Definition |
| :---- | :---- |
| Quotation status, vendor side | Draft, Sent to Client, From MFR, Accepted, Over 30 Days |
| Quotation status, client side | Draft, Sent to Vendor, Received, Accepted, Over 30 days |
| Over 30 Days | A quotation that passed its Valid Until date without a response and expired automatically |
| Order status | new, confirmed, pending, delivered, cancelled in one model; New, Confirmed, On the Way, Arrived, Delivered, Canceled in the other. See the open points |
| Packing slip status | NEW, PACKED, ON THE WAY, ARRIVED, DELIVERED |
| Manufacturer status | Preferred, Approved, Not Approved, Not Assigned — the vendor’s classification of a manufacturer, applied globally |
| Subscriber status | ACTIVE, EXPIRED, NOT SUBSCRIBED — one database field with three values |
| Invitation code status | Used or Unused; a code becomes Used only when the client completes registration |
| Client status | New, Regular, Callback or Go Back, Inactive — the marketing classification on a client record |
| Licence status | Active or Expired, shown against a Licence Login ID |
| Published | A product’s availability state in the vendor catalog: Active or Inactive |
| Registration status (Reg) | Whether a client is registered in the platform: Active or Inactive |

**Prices and margins**

| Term | Definition |
| :---- | :---- |
| List price | The manufacturer’s published reference price, visible in the catalog |
| Net price | The price after all applicable discounts — what the dealer actually pays the manufacturer |
| Base price | The default product price held at vendor level, used where a store sets no override |
| Sell price | The price presented to the client: net price plus markup |
| Local price override | A store-level price that replaces the base price for that store only |
| Discount tier | A chained discount such as 50/10/5, each level applied to the already reduced price |
| Multiplier | The single factor equivalent to a discount chain, for example 0.45 for 50/10/10 |
| Markup | The margin the vendor adds on top of its net price; may be global, per item or per quote |
| Margin | (Sell Price − Net Price) / Sell Price, displayed as a percentage |
| Gross profit | (Sell Price − Net Price) × Sold Quantity. Taxes and freight are excluded |
| Additional discount | A second, order-level discount applied after the main discount |
| Line discount | A discount applied to one line, either as a percentage capped at 100% or as an absolute amount not exceeding the line base |
| Broken case pricing | The uplift applied where an item is sold in less than a full case |
| Price level | A pricing tier such as retail, wholesale or distributor, each with its own discount settings |
| Price snapshot | The full set of price values captured when a product is added to a quotation, so that later catalog changes do not alter it |
| Compare Prices To | The catalog control that shows a prior price alongside the current one, over Previous Order, Last 7 Days, Last 30 Days, Last Quarter or Last Year |
| Prior price | The price of the same product in the comparison period selected |

**Totals, taxes and payment**

| Term | Definition |
| :---- | :---- |
| Line base | Quantity multiplied by unit price, before any discount |
| Net line total | The line base less the line discount, floored at zero |
| Subtotal | The sum of the net line totals |
| Group subtotal | The subtotal of one manufacturer or catalog block within a quotation |
| Extension | The calculated line amount on an order, derived from quantity, price, discount and tax |
| Tax | Tax applied to the subtotal at the agreed rate; entered manually per quotation line |
| GST | Goods and Services Tax, applied at order or invoice level |
| Taxable amount | The portion of the document the tax rate applies to |
| Freight | The shipping cost, entered as a fixed positive amount |
| Delivery fee | The charge for local delivery, configurable per vendor and editable on an order |
| Credit | A credit balance applied against an order or invoice, reducing the amount payable |
| Credit limit | The maximum credit a client may carry, held with a grace period in days |
| Grace period | The number of days a client may exceed payment terms before the credit limit rule bites |
| Rebate | A partial refund of money, often provided as an incentive to purchase a product or service |
| PPD shipping level | The order value above which shipping is prepaid by the manufacturer |
| Preferred carrier | The logistics provider a dealer prefers for its shipments |
| Payment term | The agreed timing of payment, such as Net 30, cash on delivery, weekly, monthly or every invoice |
| Payment method | The instrument used to pay: cash, check, wire, credit card, ACH, Zelle, Apple Pay, PayPal, Stripe, Wise, Google Pay or another added by an administrator |
| Paid amount | The total recorded against an invoice as paid |
| Balance due | The invoice total less the paid amount |
| OS balance | Outstanding balance — the unsettled amount shown against an order |
| Deposit | A part payment taken before an order is produced; 50% is cited as typical |
| Banker’s rounding | The rounding convention applied identically in the frontend and the backend |

**Quantities and fulfilment**

| Term | Definition |
| :---- | :---- |
| Ord Qty | The quantity requested by the buyer |
| Sold Qty | The approved quantity, used in all totals and profitability calculations |
| Ship Qty | The quantity the seller will actually ship |
| Vendor Qty | The quantity available in vendor stock, editable during order confirmation |
| B/O | Back order — the shortfall, calculated as Ordered less Shipped |
| In stock | The actual quantity held, in units |
| Min QTY | The minimum stock level held for a product |
| Min sell unit qty | The smallest quantity a manufacturer will sell |
| Inner pack | The intermediate packaging level between the selling unit and the master case |
| Master case | The outer shipping case, with its own UPC and unit quantity |
| Pallet qty | The number of units on a full pallet |
| Write-off | The removal of stock for a stated reason — damaged or spoiled — recorded with quantity, price and date |
| Drop shipping | Shipment directly from the manufacturer to the restaurant, bypassing the dealer’s warehouse |
| Delivery window | The time range within which a vendor delivers on a given day |
| Delivery days override | A per-customer delivery schedule replacing the vendor’s default days |

**Products and catalog**

| Term | Definition |
| :---- | :---- |
| Catalog | The set of products belonging to a manufacturer, a vendor or a store. A store catalog is created automatically on the first successful upload |
| Catalog version | The numbered state of a catalog; version 1.0 is created by CSS and each manufacturer update increments it |
| Product card | The detail page of a single product, holding its information and its reports |
| SKU | Stock keeping unit — the product identifier used in the store product upload |
| Model number | The manufacturer’s product identifier, unique per manufacturer in the catalog data model |
| CSS customer number | The customer identifier that, with the model number, forms the catalog uniqueness key |
| Vendor ID (external) | A custom external identifier, one value per product, immutable after creation |
| UoM | Unit of measure. Held in one system-wide dictionary, extended by fuzzy match when a new value appears |
| UPC | Universal Product Code, recorded separately for the selling unit and the master case |
| CBM | Cubic metre volume of a case |
| Harmonized tariff code | The customs classification code for the product |
| Country of origin | The country the product is manufactured in |
| Certifications | Product certifications recorded as free text |
| Search words | Additional keywords stored to improve product discovery |
| Parent-child variation | The hierarchy linking a base product to its variants; a child without a valid parent blocks an import |
| Variant | A version of a product differing by an attribute such as colour or material, treated as a distinct line item |
| Item info | A specification or manual PDF attached to a product |
| Category | The classification a product belongs to; must be mapped on import, though individual rows may leave it empty |

**Import and data handling**

| Term | Definition |
| :---- | :---- |
| Import wizard | The multi-step flow from source selection through mapping and validation to confirmation |
| Bulk paste | Pasting tabular data directly from a spreadsheet instead of uploading a file |
| Field mapping | Aligning the columns of a source file with the fields of the system |
| Mapping profile | A saved, named mapping configuration that can be reapplied to a later upload |
| AI suggestion | A mapping proposed from header similarity and historical mapping patterns |
| Fuzzy matching | Approximate matching of header or value names, so that "Prod Name" resolves to "Product Name" |
| Not recognized | The marker on a column the system could not map; such columns are excluded unless mapped by hand |
| Add missing information | The modal that fills mandatory values missing from the source, without altering the source file |
| Import mode | Create new, update by identifier, or create or update — chosen before a file is processed |
| Upsert | Update where the key already exists, insert where it does not |
| Duplicate detection | The check for an existing record on an exact match of the agreed key |
| Conflict resolution | The step in which differing values between records are settled, field by field |
| Master record | The record designated to survive a merge and absorb the resolved values of the others |
| Merge | Combining several companies of one type into one master record and deleting the rest |
| Bulk edit | Applying field values across every selected record; empty fields are ignored |
| Smart delete | Deletion that checks each selected record against the protection rules and reports what was skipped |
| Error report | The downloadable list of failed rows, naming the row number, the field and the violation |
| Import template | The downloadable file showing the format and schema the system expects |
| Upload session | One import run, identified so that repeating the process step does not duplicate records |
| Idempotency | The property that repeating the same operation produces no additional effect |

**Subscriptions, licences and access**

| Term | Definition |
| :---- | :---- |
| Licence | The entitlement a company buys, expressed as a number of user seats |
| Seat | One user account entitlement within a company’s subscription |
| Used seats | The number of seats occupied by registered users |
| Remaining seats | Licence total less used seats; also shown as Available Seats |
| Licence Login ID | The unique identifier of a subscription; preserved on renewal, regenerated for a new subscription after expiry |
| Invitation code | The code issued to a company that permits registration; globally unique, generated on send |
| Company type | Manufacturer, Vendor or F\&B Client; fixed permanently once type-specific data exists |
| Parent company | The company a subsidiary belongs to; changed only through bulk edit or a merge |
| Subsidiary | A company linked beneath a parent; cannot be created from the company card |
| General team | The default team created at onboarding; does not block a change of company type |
| Store team, restaurant team | Type-specific teams whose existence blocks a change of company type |
| Blocking entity | A record whose existence prevents a company type change: clients, products, invoices, orders, type-specific teams or B2B relations |
| RBAC | Role-based access control — permissions granted by role rather than by user |
| Permission matrix | The grid assigning All Permissions, Create, View, Edit and Delete to each role, per module |
| Master data | Manufacturer-owned data such as identity, addresses and contacts, which the vendor can read but not change |
| Proprietary data | Vendor-owned data such as discounts, margins, rebates and internal notes, which the manufacturer never sees |
| Handover | The transfer of catalog control from CSS to the manufacturer, after which the manufacturer holds write access |

**Company and reference data**

| Term | Definition |
| :---- | :---- |
| Master database | The central register of every business entity in the system — manufacturers, vendors and F\&B clients, subscribers and non-subscribers alike |
| Company card | The detail page of one company, holding Information, Subscription, Licenses and History |
| DBA name | Doing-business-as name — the trading name where it differs from the legal company name |
| MAFSI | Manufacturers’ Agents for the Foodservice Industry, whose 28 regional areas describe representation coverage |
| MAFSI area | One of those regions, recorded against a representation agency and used for display only |
| Buying group affiliation | The buying group or groups a dealer belongs to; recorded but never verified or settled by CSS |
| Hours of operation | The working days and time intervals recorded for a company or a store |
| Licence (store) | A regulatory licence held by a store, recorded by type and number |
| Emergency contact | A contact recorded separately for use outside normal circumstances |

**Audit and history**

| Term | Definition |
| :---- | :---- |
| Audit log | The record of who changed what and when, used for compliance and version recovery |
| History tab | The log of changes other than licence events: information, hierarchy, bulk edit, merge, notes, payment method, paid amount, received date and licence fee |
| Licenses tab | The log of licence events: created, renewed, expired, deleted, seats added or removed, and changes to the activation, expiration or renewal dates |
| Order history | The event log of one order, recorded per product line with the date, user and role |
| Diff | The difference between two versions of a record, shown so that a change can be read at a glance |
| Version history | The sequence of catalog versions, each created by an import or a manual edit |

**Interface conventions**

| Term | Definition |
| :---- | :---- |
| Breadcrumbs | The navigation trail above a page title, showing the path back to the list |
| Pill, badge, chip, tag | Small labelled elements: a pill or badge carries a status, a chip or tag a removable value |
| Accordion | A block that expands and collapses to show or hide its contents |
| Stepper | The plus and minus control used to set a quantity; replaces the add control once a product is in the cart |
| Dropzone | The area a file is dragged into for upload |
| Toast | A short confirmation or error message appearing outside the main content |
| Modal | An overlay window that traps focus until it is submitted or dismissed |
| Empty state | The message and illustration shown where a table has no rows to display |
| Skeleton loader | A placeholder rendering of rows while data is being fetched |
| Indeterminate checkbox | The header checkbox state shown when only some rows on a page are selected |
| Per page | The selector controlling how many records a page shows: 10, 20, 25, 50 or 100 depending on the table |
| Date range | The paired start and end pickers filtering a table by date; applied only when both are supplied |
| Active context | The quotation or order that products selected in a catalog are added to |
| Preview settings | The checkboxes controlling which pricing columns appear in a quotation preview, print, export and client document |
| Without Price | The preview setting that removes all pricing from the client-facing document; mutually exclusive with the individual price columns |
| Vendor View, Client View | The two perspectives on a quotation: internal, with cost and margin, and external, with only what the client should see |
| Go to Chat | The control that opens the conversation with the counterparty responsible for the record in view |
| Rate limit | A cap on how often an action may be repeated, such as one invitation code send every five minutes |
| Debounce | Delaying an action until input stops, so that rapid clicks or keystrokes produce one request |
| Last-write-wins | The concurrency rule under which the later save overwrites the earlier one |
| Race condition | A timing conflict between concurrent operations, guarded against by validating inside the saving transaction |

