# **CSS — User Acceptance Testing**

Acceptance scenarios and sign-off

**Project:** CSS

**Document type:** UAT scenarios

**Version:** 1.0 (draft for client review)

**Date:** 18 August 2026

**Prepared by:** \[analyst name\]

**Source:** CSS — Functional Requirements (AS IS), version 1.5. Every scenario cites the requirement identifiers it exercises.

**Contents**

1\. Purpose and scope

2\. How to run these tests

3\. Test data and environments

4\. Scenario suites

      4.1 Authentication and onboarding

      4.2 Admin panel

      4.3 Manufacturer directory

      4.4 Manufacturer catalog and import

      4.5 Quotations

      4.6 Vendor portal

      4.7 Restaurant portal

5\. Scenarios blocked by open decisions

6\. Defect reporting

7\. Sign-off

# **1\. Purpose and scope**

This document is the acceptance test plan for the CSS platform. It sets out the scenarios that have to pass before the delivered functionality is accepted, and records the result of each one.

The scenarios are written to be run by a business user rather than a tester: each names the role to sign in as, the steps to take and the result to expect. No knowledge of the implementation is assumed.

**In scope:**

* Authentication and onboarding for both business types

* The admin panel: master database, subscribers, company card, bulk actions and the company type rules

* The manufacturer directory and the manufacturer card in both views

* The manufacturer catalog and the bulk import wizard

* The quotation lifecycle from creation to conversion into an order

* The vendor portal: orders, products, packing slips, team and settings

* The restaurant portal: ordering, order confirmation and the response to vendor changes

**Out of scope:**

* Payment processing, which is settled outside the platform

* Performance, load and security testing

* Behaviour that depends on a decision not yet taken — listed in section 5

# **2\. How to run these tests**

Each scenario is independent: it states its own starting point and does not rely on a previous scenario having been run, unless the steps say otherwise.

**Recording a result**

| Result | Meaning |
| :---- | :---- |
| Pass | The system behaved exactly as the expected result describes |
| Fail | The system behaved differently. Raise a defect and record its number in the Result column |
| Blocked | The scenario could not be run — the environment, the data or a prior defect prevented it |
| Not applicable | The functionality is out of scope for this release |

*A scenario passes only where the whole expected result is met. Where part of it is met, record Fail and describe which part failed; a partial pass hides defects that surface later in production.*

**Reading the Covers column**

Each scenario cites the requirement identifiers it exercises, in the form FR-QUO-014 or FR-ADM-072. Those identifiers are stable in the functional requirements document, so a failed scenario can be traced to the exact requirement, and a changed requirement can be traced to the scenarios that have to be rerun.

# **3\. Test data and environments**

The accounts below have to exist before testing starts. Where a role is not yet implemented, note it and mark the dependent scenarios Blocked.

| Account | Role | Purpose |
| :---- | :---- | :---- |
| CSS administrator | Platform admin | Master database, subscribers, company cards, imports |
| Vendor CEO | Vendor company CEO | Full vendor portal access, settings and permissions |
| Vendor salesperson | Salesperson | Quotations owned by one user; reassignment and permission checks |
| Vendor packer | Packer | Packing slip assembly |
| Vendor driver | Driver | Pick up, arrival and delivery confirmation |
| Manufacturer user | Manufacturer | Manufacturer card in manufacturer view, catalog upload |
| Restaurant owner | F\&B client owner | Ordering, quotation response, order confirmation |
| Second vendor | Vendor company CEO | Cross-vendor isolation checks |

**Data to prepare**

* A manufacturer with at least twenty catalog products, several sharing a category

* A restaurant client with a saved address, a contact person and a credit limit

* A valid import file in CSV and in XLSX, and a deliberately malformed one

* An invoice PDF for the master invoice recognition scenarios

* A company with subsidiaries, for the company type change scenarios

* A company with an ACTIVE subscription and one that has never subscribed

# **4\. Scenario suites**

## **4.1 Authentication and onboarding**

| ID | Role | Steps | Expected result | Covers | Result |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **UAT-AUT-01** | New user | Open the sign-up screen and enter an invitation code that does not exist. | The code is rejected as soon as it is entered, with an inline error. Registration cannot continue. | FR-AUT-001 |  |
| **UAT-AUT-02** | New user | Enter a valid invitation code, complete the required fields and set a password that breaks the complexity rules. | An inline message states the password requirement. The form cannot be submitted. | FR-AUT-002 |  |
| **UAT-AUT-03** | New user | Use the eye icon beside the password field. | The password is shown and hidden without the entered value changing. | FR-AUT-003 |  |
| **UAT-AUT-04** | Registered user | On the sign-in screen switch the method selector between email and phone. | The corresponding field is shown and the other hidden. Next stays disabled until an identifier is entered. | FR-AUT-010 |  |
| **UAT-AUT-05** | Registered user | Enter an identifier in an invalid format and continue. | "Invalid email" or "Invalid phone number" appears below the field and sign-in is blocked. | FR-AUT-011 |  |
| **UAT-AUT-06** | Registered user | Request a password recovery code, then request it again immediately. | The request control is locked for 60 seconds; the resend becomes active only after that and issues a new code. | FR-AUT-018 |  |
| **UAT-AUT-07** | Registered user | Reset the password entering two different values in the two fields. | "Passwords do not match" is displayed and the reset is blocked. | FR-AUT-019 |  |
| **UAT-AUT-08** | New company owner | Start onboarding and try to continue without choosing a business type. | The Next control stays disabled until a business type is chosen. | FR-AUT-030 |  |
| **UAT-AUT-09** | New company owner | Choose Restaurant and continue; then repeat with Vendor. | Restaurant attributes are requested for the first, store attributes for the second. The other set is not shown. | FR-AUT-031 |  |
| **UAT-AUT-10** | New company owner | On the core team screen submit the form with a participant row left incomplete. | Inline errors mark the blank or malformed fields, and the Owner participant is saved regardless. | FR-AUT-033 |  |
| **UAT-AUT-11** | New company owner | Inspect the role of the first participant. | The role is Owner, assigned automatically and read-only. Later participants choose a role from the lookup list. | FR-AUT-028 |  |

## **4.2 Admin panel**

| ID | Role | Steps | Expected result | Covers | Result |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **UAT-ADM-01** | Administrator | Open Master Database and switch between All, Manufacturers, Vendors and F\&B Clients in the sidebar. | Each is a separate page with its own URL, and the list is filtered to the chosen type. | FR-ADM-001 |  |
| **UAT-ADM-02** | Administrator | Find a company with NOT SUBSCRIBED status in the table. | The status is a grey pill, and Number of Licences, Annual / Monthly and Renewed Frequency show a dash. | FR-ADM-002 |  |
| **UAT-ADM-03** | Administrator | Sort by a data column, then type a query into the local search. | The sort applies ascending and descending only. Entering a search resets the sort to the default order. | FR-ADM-011 |  |
| **UAT-ADM-04** | Administrator | Select some rows on a page using the header checkbox, then move to the next page. | The header checkbox shows the indeterminate state where only some rows are selected, and the selection clears on changing page. | FR-ADM-014 |  |
| **UAT-ADM-05** | Administrator | Select two companies of different types and open the bulk edit modal. Set a Parent Company and apply. | "You have selected companies of different types. Please set a single company type to proceed." is displayed and saving is blocked. | FR-ADM-026 |  |
| **UAT-ADM-06** | Administrator | With the same mixed selection, change only the licence count and apply. | The change is accepted, because the restriction applies to Parent Company only. | FR-ADM-027 |  |
| **UAT-ADM-07** | Administrator | Bulk edit a company that has subsidiaries outside the selection and change its type. | The "Change subsidiary type?" pop-up appears for that company, offering to detach the subsidiaries, to change their type, or to cancel. | FR-ADM-033 |  |
| **UAT-ADM-08** | Administrator | Select two companies of different types and click Merge. | "Merge can only be performed for companies of the same type" is displayed with a Cancel control. The merge does not start. | FR-ADM-034 |  |
| **UAT-ADM-09** | Administrator | Merge three companies of one type; remove chips until one remains. | The Apply control is blocked while fewer than two companies remain in scope. | FR-ADM-036 |  |
| **UAT-ADM-10** | Administrator | Merge two companies whose phone numbers differ, choosing Add during conflict resolution. | Both phone numbers are present on the master record after the merge. | FR-ADM-044 |  |
| **UAT-ADM-11** | Administrator | Merge two companies that hold an identical contact person. | The contact is not duplicated on the master record. A contact matching only partly is added as a separate contact. | FR-ADM-046 |  |
| **UAT-ADM-12** | Administrator | Select only NOT SUBSCRIBED companies and delete them. | A confirmation asks before deletion, the records are removed and the count is reported in the correct singular or plural form. | FR-ADM-050 |  |
| **UAT-ADM-13** | Administrator | Select only ACTIVE or EXPIRED companies and delete them. | A red banner states that a registered company cannot be deleted, a warning icon marks each name, and nothing is deleted. | FR-ADM-051 |  |
| **UAT-ADM-14** | Administrator | Select a mix of protected and deletable companies and delete. | The pop-up reports how many will be deleted and how many cannot, listing each with its status. Only the deletable ones are removed. | FR-ADM-053 |  |
| **UAT-ADM-15** | Administrator | Open Subscribers and check whether the Delete control is present. | Delete is not offered in the subscriber table. | FR-ADM-049 |  |
| **UAT-ADM-16** | Administrator | Create a client through "+ Add new", leaving the address blank. | The address is required; the form cannot be submitted until it is filled. | FR-ADM-099 |  |
| **UAT-ADM-17** | Administrator | Create a client using an email address that already exists. | "A client with this email already exists in the system." appears below the email field and no code is generated. | FR-ADM-102 |  |
| **UAT-ADM-18** | Administrator | Open the create client modal, fill one field and press Cancel. | "Discard changes?" is displayed with Stay and Discard. No invitation code has been generated. | FR-ADM-104 |  |
| **UAT-ADM-19** | Administrator | Create a client successfully, then look at the invitation code field. | A unique code is generated only at that point, the company is created as NOT SUBSCRIBED and the code is sent to the address given. | FR-ADM-103 |  |
| **UAT-ADM-20** | Administrator | On the Subscription tab of a company with an unused code, send the code twice in a row. | The second attempt is blocked; the control is disabled and shows a countdown until five minutes have passed. | FR-ADM-079 |  |
| **UAT-ADM-21** | Administrator | Change the company email on the Information tab, save, then send the invitation code again. | The code is sent to the new address. | FR-ADM-080 |  |
| **UAT-ADM-22** | Administrator | Open the Subscription tab of a company whose code status is Used. | The send control is not displayed. | FR-ADM-078 |  |
| **UAT-ADM-23** | Administrator | Enter a received date on the Subscription tab of a company with the annual period selected. | The activation date is set to the received date and the expiration date to one year later. | FR-ADM-083 |  |
| **UAT-ADM-24** | Administrator | Change the expiration date by hand, then change the activation date. | The manually entered expiration date is kept; the automatic formula no longer applies. | FR-ADM-085 |  |
| **UAT-ADM-25** | Administrator | Set an expiration date earlier than the activation date and save. | An inline error is shown below the field and saving is blocked. | FR-ADM-087 |  |
| **UAT-ADM-26** | Administrator | Reduce the licence count below the number of seats in use and save. | The change is stored, a message states that it takes effect after the subscription expires, and the remaining seats figure still shows the previous value. | FR-ADM-088 |  |
| **UAT-ADM-27** | Administrator, restaurant user | Register a client using the invitation code, then reopen the company card as the administrator. | The company is ACTIVE, the code is Used, the activation date is the actual registration date, the expiration date is recalculated, and the administrator has received the verification email. | FR-ADM-093 |  |
| **UAT-ADM-28** | Administrator | Leave the Information tab with unsaved changes by clicking a breadcrumb. | The "Unsaved changes" pop-up offers Save and Discard. | FR-ADM-098 |  |
| **UAT-ADM-29** | Administrator | Change the type of a company that has no products, orders, clients or type-specific teams. | The change is accepted and confirmed. | FR-ADM-120 |  |
| **UAT-ADM-30** | Administrator | Change the type of a company that holds catalog products and invoices. | The change is rejected on saving, the type field is highlighted, and the message names the blocking entities. The original type is kept. | FR-ADM-121 |  |
| **UAT-ADM-31** | Administrator | Delete every product, order and type-specific team from a blocked company, then change its type. | The change is now accepted, because only the general team remains. | FR-ADM-124 |  |
| **UAT-ADM-32** | Administrator | Start an import from Upload, having entered from the Vendors section of the sidebar. | No entity type is preselected. Confirm stays inactive until a type is chosen by hand. | FR-ADM-110 |  |
| **UAT-ADM-33** | Administrator | On the mapping step, map a second file column to a field already in use. | The selection is blocked. | FR-ADM-113 |  |
| **UAT-ADM-34** | Administrator | Leave a required field unmapped and try to continue. | The unmapped required columns are highlighted in red and the continue control is blocked. | FR-ADM-112 |  |

## **4.3 Manufacturer directory**

| ID | Role | Steps | Expected result | Covers | Result |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **UAT-MFR-01** | Vendor | Open MFR Contacts and filter by Preferred, then by Not Approved. | The table shows only manufacturers with that status, without a page reload. | FR-MFR-008 |  |
| **UAT-MFR-02** | Vendor | Change a manufacturer status directly from the list, then open the manufacturer catalog. | The status change is reflected globally, in every module that shows it. | FR-MFR-009 |  |
| **UAT-MFR-03** | Vendor | Find a manufacturer whose rebate percentage is above zero and one with none. | The rebate badge reads YES for the first and NO for the second. | FR-MFR-010 |  |
| **UAT-MFR-04** | Vendor | Open a manufacturer card and try to edit the name, address and standard contacts. | All master data is read-only and rendered as greyed-out fields. | FR-MFR-012 |  |
| **UAT-MFR-05** | Vendor | Enter a master discount, a margin and internal notes, and save. | The values are stored against this vendor only. | FR-MFR-013 |  |
| **UAT-MFR-06** | Manufacturer | Open the same manufacturer card from the manufacturer account. | The vendor discount, terms, margin, rebate and category discount blocks are not displayed at all. | FR-MFR-022 |  |
| **UAT-MFR-07** | Manufacturer | Edit the identity, address, logo and contact cards, and save. | The changes are accepted and appear to the vendor as read-only values. | FR-MFR-023 |  |
| **UAT-MFR-08** | Vendor | Type a non-numeric value into a Margin % field and leave the field. | The value falls back to zero and stays within 0.00 to 100.00. | FR-MFR-036 |  |
| **UAT-MFR-09** | Vendor | Enter "50/10/5" and then "50-10-5" into the Master Discount field. | Both tiered formats are accepted. | FR-MFR-037 |  |
| **UAT-MFR-10** | Vendor | Open the MAFSI selector, search by region name and by ID, and select several regions. | Multi-selection works, and the selected regions appear as removable tags. | FR-MFR-030 |  |
| **UAT-MFR-11** | Vendor | Upload a logo in a format other than PNG, JPG, JPEG or SVG, or larger than 5 MB. | An inline error states the restriction and the file is not accepted. | FR-MFR-039 |  |
| **UAT-MFR-12** | Vendor | Add a category discount row with a multiplier and margin, save, and then build a quotation with that manufacturer’s product. | The category values are stored but do not change the price used in the quotation. | FR-MFR-038 |  |

## **4.4 Manufacturer catalog and import**

| ID | Role | Steps | Expected result | Covers | Result |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **UAT-CAT-01** | Manufacturer | Upload a catalog in XLSX and then in CSV. | Both are parsed and shown in the mapping interface. | FR-CAT-010 |  |
| **UAT-CAT-02** | Manufacturer | Copy a block of rows from a spreadsheet and paste it into the bulk paste interface. | Rows and columns are identified correctly. | FR-CAT-011 |  |
| **UAT-CAT-03** | Manufacturer | Open the mapping step with a file whose headers differ slightly from the system names. | A mapping is suggested for every standard field, and any suggestion can be overridden by hand. | FR-CAT-020 |  |
| **UAT-CAT-04** | Manufacturer | Save the mapping as a profile, start a new import of a similar file and load the profile. | The mapping is restored in full and the manual mapping step can be skipped. | FR-CAT-026 |  |
| **UAT-CAT-05** | Manufacturer | Import a file where one row has no model number and another has text in the price column. | Both rows are flagged, the import of those records is prevented, and the report names the row, the field and the violation. | FR-CAT-034 |  |
| **UAT-CAT-06** | Manufacturer | Download the error report produced by the previous scenario. | A CSV or Excel file is downloaded listing the row number, the field in error and the description. | FR-CAT-038 |  |
| **UAT-CAT-07** | Manufacturer | Import a file where a short description exceeds 200 characters and a long description exceeds 5,000. | Both are rejected by the length rules. | FR-CAT-050 |  |
| **UAT-CAT-08** | Manufacturer | Import a file with optional fields such as certifications and pallet quantity left empty. | The import succeeds. | FR-CAT-052 |  |
| **UAT-CAT-09** | Manufacturer | Import the same file twice without changing the model numbers. | No duplicate products are created under the same customer number and model number; the existing records are updated. | FR-CAT-053 |  |
| **UAT-CAT-10** | Manufacturer | Complete an import, then open the catalog history. | A new version entry is recorded, showing the version, the timestamp and the user. | FR-CAT-006 |  |
| **UAT-CAT-11** | Manufacturer | Download the import template from inside the import interface. | A template is downloaded whose columns match the schema the system expects. | FR-CAT-014 |  |
| **UAT-CAT-12** | Second manufacturer | Attempt to open or edit the first manufacturer’s catalog and its mapping profiles. | Neither the catalog nor the profiles are reachable. | FR-CAT-008 |  |
| **UAT-CAT-13** | Restaurant user | Open the technical catalog as a restaurant client. | The catalog is read-only and the restricted prices are not shown. | FR-CAT-062 |  |

## **4.5 Quotations**

| ID | Role | Steps | Expected result | Covers | Result |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **UAT-QUO-01** | Vendor | Open the quotations list and switch between the five status tabs. | The table filters instantly to the selected status, without a page reload. | FR-QUO-019 |  |
| **UAT-QUO-02** | Vendor | Hover over the "i" icon beside a status tab. | A tooltip explains the business meaning of that status. | FR-QUO-020 |  |
| **UAT-QUO-03** | Vendor | Create a quotation and check the Valid Until date. | It is set to 30 days from the quotation date and can be edited by hand. | FR-QUO-021 |  |
| **UAT-QUO-04** | Vendor | Set Valid Until to a shorter custom period and let it pass without a client response. | The quotation moves to Over 30 Days on the custom date rather than after a fixed 30 days. | FR-QUO-010 |  |
| **UAT-QUO-05** | Vendor | Open a quotation in Draft status and look at the Valid Until column in the list. | The column shows an em dash for Draft and for Accepted. | FR-QUO-003 |  |
| **UAT-QUO-06** | Vendor | Create a quotation for a client already in the database. | The client ID and name populate automatically from the client record. | FR-QUO-030 |  |
| **UAT-QUO-07** | Vendor | Tick "Client is not in the system", fill the manual fields, then untick and tick the box again. | The manually entered data is preserved and reappears. | FR-QUO-046 |  |
| **UAT-QUO-08** | Vendor | Create a client whose phone number partly matches an existing record. | The duplicate warning modal names the conflict. Skip returns to the form; Proceed creates the record. | FR-QUO-052 |  |
| **UAT-QUO-09** | Manufacturer | Open the same creation flow from a manufacturer account. | The modal is titled "Choose Vendor", the dropdown queries vendors and the checkbox and address label change accordingly. | FR-QUO-041 |  |
| **UAT-QUO-10** | Vendor | On the quotation page change a quantity, then a discount, then a markup. | The row net price, sell price and subtotal, and the global subtotal, tax, total and gross profit all recalculate immediately. | FR-QUO-060 |  |
| **UAT-QUO-11** | Vendor | Apply a discount large enough to push the sell price below the net price. | The margin turns negative and is highlighted in red, but the entry is allowed. | FR-QUO-071 |  |
| **UAT-QUO-12** | Vendor | Enter a list price of $100 with the discount chain 50/10/5. | The net price is $42.75. | FR-QUO-062 |  |
| **UAT-QUO-13** | Vendor | Remove every product from a quotation and try to convert it into an invoice. | The totals reset to $0.00 and the conversion is prevented. | FR-QUO-072 |  |
| **UAT-QUO-14** | Vendor | Toggle the discount between $ and % in the Details section. | The percentage is calculated against the pre-discount total; the flat amount is deducted as entered. | FR-QUO-064 |  |
| **UAT-QUO-15** | Vendor | Switch to Client View and check the product table. | List price, net price, markup, margin and gross profit are hidden; sell price, quantity and subtotal remain. | FR-QUO-058 |  |
| **UAT-QUO-16** | Vendor | In Preview Settings tick "Without Price". | The three price checkboxes clear automatically and the price columns, the subtotal column and the financial totals disappear. | FR-QUO-085 |  |
| **UAT-QUO-17** | Vendor | With "Without Price" active, tick "Discount". | "Without Price" clears automatically and the discount column reappears. | FR-QUO-086 |  |
| **UAT-QUO-18** | Vendor | Set a price display configuration, then use Preview, Print and Export in turn. | All three documents carry exactly the column visibility chosen in the settings. | FR-QUO-088 |  |
| **UAT-QUO-19** | Vendor | Open the send modal with the "Send to Email" toggle off. | The email field is disabled. | FR-QUO-105 |  |
| **UAT-QUO-20** | Vendor | Turn both "Send to Email" and "Print" off and press Send. | Submission is blocked with a prompt to choose at least one delivery method. | FR-QUO-100 |  |
| **UAT-QUO-21** | Vendor | Choose a Valid Until date in the past and press Send. | An inline error states that the validity date must be in the future. | FR-QUO-103 |  |
| **UAT-QUO-22** | Vendor | Send a quotation successfully by email. | The client receives the standard template with the PDF attached, and the quotation moves from Draft to Sent. | FR-QUO-110 |  |
| **UAT-QUO-23** | Vendor | Open the manufacturer catalog without selecting a quotation and press "+" on a product. | The quantity does not increase; the context area is highlighted and a modal asks to select or create a quotation. | FR-QUO-125 |  |
| **UAT-QUO-24** | Vendor | Create a new quotation from that modal. | It becomes the active context automatically and the pending product is added. | FR-QUO-127 |  |
| **UAT-QUO-25** | Vendor | Reduce a product quantity to zero from the catalog stepper. | The line is removed from the quotation entirely rather than left at zero. | FR-QUO-129 |  |
| **UAT-QUO-26** | Vendor | Open the add-group modal on a quotation that already includes a manufacturer. | That manufacturer is greyed out and cannot be selected. | FR-QUO-150 |  |
| **UAT-QUO-27** | Restaurant | Open a received quotation and try to edit the quotation info and the addresses. | All of it is read-only, whatever edit icons appear in the layout. | FR-QUO-165 |  |
| **UAT-QUO-28** | Restaurant | Change a value in ORD QTY and then try to sign the quotation. | Signing is not available; the change has to be sent back through "Request modifications". | FR-QUO-167 |  |
| **UAT-QUO-29** | Restaurant | Tick the agreement checkbox and sign the quotation. | The quotation converts into an order, the status becomes Accepted, and a Go to Order control appears. | FR-QUO-169 |  |
| **UAT-QUO-30** | Restaurant | Open a received quotation whose Valid Until is blank and leave it untouched for the expiry window. | The 30 days count from the date received and the quotation moves to Over 30 days. | FR-QUO-163 |  |

## **4.6 Vendor portal**

| ID | Role | Steps | Expected result | Covers | Result |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **UAT-VND-01** | Vendor | Open the dashboard and change the period selector from Today to Month. | Completed orders, total sales and returns recalculate, each with the percentage change against the previous period. | FR-VND-014 |  |
| **UAT-VND-02** | Vendor | Click a past-due notification in the feed. | The details of that order open. | FR-VND-017 |  |
| **UAT-VND-03** | Vendor | Create an order, selecting an existing client. | The delivery address, Bill To and Ship To populate from the client record, and the billing and shipping checkbox is ticked by default. | FR-VND-036 |  |
| **UAT-VND-04** | Vendor | Try to move to the product step without a contact person selected. | The step cannot be completed until the contact person is filled in. | FR-VND-039 |  |
| **UAT-VND-05** | Vendor | Add a product to the order from the catalog step. | The add control becomes a tick and the running total in "Your Order" updates immediately. | FR-VND-034 |  |
| **UAT-VND-06** | Vendor | Open an order in New status and check the confirmation control. | It is labelled Confirm. In On the way it reads Arrived, and in Arrived, Confirm Delivery. | FR-VND-026 |  |
| **UAT-VND-07** | Vendor | Change a quantity and a discount on an order line. | The extension recalculates automatically, and the total reflects subtotal plus tax plus freight less the discounts. | FR-VND-023 |  |
| **UAT-VND-08** | Vendor | Add a line note to a product and save. | The note is stored against that line and is visible on reopening the order. | FR-VND-029 |  |
| **UAT-VND-09** | Vendor | Open the Documents tab of an order before generating an invoice, then use Generate Invoice. | The download control is inactive until the document exists, and the new invoice then appears in the list. | FR-VND-032 |  |
| **UAT-VND-10** | Vendor | Open the Order History tab. | Each event is logged against a product line with the exact date, time, user and role. | FR-VND-031 |  |
| **UAT-VND-11** | Shipping manager | Import products from a CSV, mapping name, price, quantity, unit and category. | The products appear in the store catalog with the mapped values. | FR-VND-040 |  |
| **UAT-VND-12** | Shipping manager | Write off a product choosing "Everything in stock" and the reason Damaged, then add a second product with the fields left blank. | Validation blocks the second line until every field is filled, since all fields are required. | FR-VND-042 |  |
| **UAT-VND-13** | Vendor | Upload a product image in a format other than PNG, JPG, JPEG or WEBP. | The error names the acceptable formats and the file is rejected. | FR-VND-050 |  |
| **UAT-VND-14** | Vendor | Set a product price by unit of measure, then switch the product to weight-based pricing. | The corresponding price field becomes available and accepts two decimal places, entered by hand or in steps of 0.01. | FR-VND-049 |  |
| **UAT-VND-15** | Vendor | Open a product report and export it, then apply a date range whose start is later than its end. | The export downloads in CSV and XLSX; the invalid date range returns no results. | FR-VND-055 |  |
| **UAT-VND-16** | Restaurant | Search the product list by category and by name using an exact term. | Only exact matches on those two columns are returned. | FR-VND-060 |  |
| **UAT-VND-17** | Restaurant | Open a product card by double-clicking a row and change the minimum stock quantity. | The card opens; the ID, name and category are read-only and the minimum quantity accepts whole numbers only. | FR-VND-063 |  |
| **UAT-VND-18** | Restaurant | Use "Add Vendor" on a product, then "Choose new vendor", then Back. | The first modal offers the current vendors, the second a search across vendors, and Back returns to the first. | FR-VND-066 |  |
| **UAT-VND-19** | Vendor | Upload a client file containing a malformed email address. | The "Please format your file" pop-up lists the requirements and the import does not proceed. | FR-VND-076 |  |
| **UAT-VND-20** | Vendor | Open a client profile and upload the first invoice PDF for a client that does not yet exist. | The client is created automatically and the invoice data is recognised into the Master Invoice tab. | FR-VND-080 |  |
| **UAT-VND-21** | Vendor | Open a client that has only a master invoice uploaded. | The Recognized Data tab is hidden. It appears once a second invoice is uploaded. | FR-VND-082 |  |
| **UAT-VND-22** | Vendor | Set invoice numbering to By Date with the letter designation ABC positioned before the number, and issue two invoices on the same day using the slash option. | The numbers are ABC071125/1 and ABC071125/2 for 11 July 2025\. | FR-VND-090 |  |
| **UAT-VND-23** | Vendor | Switch numbering to "Next in order of this client" and issue an invoice. | The number is the highest existing number for that restaurant, offline or online, plus one. | FR-VND-092 |  |
| **UAT-VND-24** | Vendor | Change the numbering setting and check the invoices already issued. | Existing numbers are unchanged; only new numbers follow the new rule. | FR-VND-094 |  |
| **UAT-VND-25** | Packer | Open a packing slip, mark every product packed and press Ready to Ship. | The control activates only once all products are marked, and the packing slip moves to PACKED. | FR-VND-097 |  |
| **UAT-VND-26** | Driver | Press Pick Up, then Arrived, then Confirm Delivery. | The status moves through ON THE WAY, ARRIVED and DELIVERED in order. | FR-VND-098 |  |
| **UAT-VND-27** | Vendor manager | Change a shipped quantity on a packing slip so that it is lower than the ordered quantity. | The back order value equals ordered less shipped. | FR-VND-100 |  |
| **UAT-VND-28** | Vendor CEO | Add a team member with a role, an assigned store and a phone number. | The member appears in the team table with the role, email, name and active state. | FR-VND-103 |  |
| **UAT-VND-29** | Vendor CEO | Block a team member, then open the team log. | The member’s status becomes Blocked and the action is recorded with the event, the member, the timestamp and the initiating user. | FR-VND-106 |  |
| **UAT-VND-30** | Vendor CEO | Set a delivery fee, a free delivery threshold and a maximum mileage, then place an order above the threshold. | Delivery is free for that order; an address beyond the mileage limit cannot be used. | FR-VND-108 |  |
| **UAT-VND-31** | Vendor CEO | Give a role View and Edit in the Orders module but not Create, and sign in as that role. | The role can open and change orders but cannot create one. | FR-VND-109 |  |
| **UAT-VND-32** | Vendor CEO | Set "All Permissions" for a role in one module. | Create, view, edit and delete are all granted in that module. | FR-VND-109 |  |

## **4.7 Restaurant portal**

| ID | Role | Steps | Expected result | Covers | Result |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **UAT-RST-01** | Restaurant | Sign in for the first time and look at the dashboard. | The welcome block and the three calls to action — upload invoices, add vendors, add team member — are shown. | FR-RST-001 |  |
| **UAT-RST-02** | Restaurant | Change the overview period selector. | Orders past due, orders paid and orders to be paid recalculate for the chosen period. | FR-RST-004 |  |
| **UAT-RST-03** | Restaurant | Open Orders with no orders yet and start an order. | The combined empty state offers Choose Vendor with the All Vendors block expanded. | FR-RST-030 |  |
| **UAT-RST-04** | Restaurant | With at least one order placed, press Create Order. | The vendor selection opens with Your Vendors expanded and All Vendors collapsed. | FR-RST-030 |  |
| **UAT-RST-05** | Restaurant | Search for a vendor the restaurant has never ordered from. | The search covers all vendors, not only current ones, and the results list opens automatically. | FR-RST-031 |  |
| **UAT-RST-06** | Restaurant | Open a vendor with no previous relationship and check Your Vendors. | Where Your Vendors is empty, an Invite Vendor control is offered. | FR-RST-032 |  |
| **UAT-RST-07** | Restaurant | In the vendor catalog set "Compare Prices To" to Last 30 Days. | The prior price column shows the price from that period alongside the current one. | FR-RST-034 |  |
| **UAT-RST-08** | Restaurant | Enter a quantity for a product. | The summary bar appears at the foot showing the running order total and a Next control. | FR-RST-035 |  |
| **UAT-RST-09** | Restaurant | Open the payment and delivery step. | The vendor’s available delivery days and time windows are displayed above the fields, and past dates cannot be chosen. | FR-RST-037 |  |
| **UAT-RST-10** | Restaurant | Submit the order and open the order card. | The card is the reduced version: no Generate Invoice, no Download Invoice, and no Ship To or Bill To blocks. | FR-RST-037 |  |
| **UAT-RST-11** | Restaurant | Try to change the freight fee, tax or discount on the order card. | Every financial field is read-only for the restaurant. | FR-RST-040 |  |
| **UAT-RST-12** | Restaurant | Change a quantity on the order card. | The "Order has been edited" block appears, offering a message and a Confirm Changes control. | FR-RST-041 |  |
| **UAT-RST-13** | Vendor | Receive the new order notification and open the confirmation screen. | The order arrives with a New Order Received notification and opens on "Review Your Order". | FR-RST-043 |  |
| **UAT-RST-14** | Vendor | Open an order in which one product is ordered in a quantity above available stock. | That line is highlighted with the insufficient stock warning naming the product. | FR-RST-044 |  |
| **UAT-RST-15** | Vendor | Reduce the vendor quantity on that line, change the unit price and remove another line, then confirm. | All changes are saved, the status becomes confirmed and the restaurant is notified. | FR-RST-050 |  |
| **UAT-RST-16** | Restaurant | Open the order after the vendor confirmed it with changes. | A warning block below the line items lists the changes and starts a 30-minute countdown, with Cancel Order and Confirm Order both beside the timer and at the foot of the page. | FR-RST-055 |  |
| **UAT-RST-17** | Restaurant | Leave the warning block untouched until the timer expires. | The order is confirmed automatically and can no longer be rejected through this flow; cancellation remains available from the order page. | FR-RST-056 |  |
| **UAT-RST-18** | Restaurant | Look for the comments section while the warning block is active. | Comments are hidden until the order is confirmed. | FR-RST-058 |  |
| **UAT-RST-19** | Vendor | Confirm an order without changing anything. | The restaurant receives only a confirmation notification: no warning block and no timer, and the status updates automatically. | FR-RST-054 |  |
| **UAT-RST-20** | Shipping manager | Upload a store product file where the category column is mapped but some rows leave it empty. | Those rows are imported. | FR-RST-060 |  |
| **UAT-RST-21** | Shipping manager | Upload a file with a tax column. | The tax value is stored separately and the price is not recalculated. | FR-RST-061 |  |
| **UAT-RST-22** | Shipping manager | Upload a file whose product matches an existing name but carries a different unit of measure. | The conflict pop-up offers to update the existing product or create a new one, with a bulk action available. | FR-RST-064 |  |
| **UAT-RST-23** | Packer or driver | Try to open the product uploader. | The uploader is not available to these roles. | FR-RST-059 |  |
| **UAT-RST-24** | Vendor | Generate a monthly statement for a client with unpaid and paid invoices, one of them 45 days overdue. | The payment method is blank on unpaid rows, the overdue invoice carries a visual indicator, and the first line shows the balance forward. | FR-RST-066 |  |

# **5\. Scenarios blocked by open decisions**

The scenarios below cannot be written as pass-or-fail tests until the corresponding decision is taken, because the requirements currently describe two incompatible behaviours. They are listed so that the gap is visible during acceptance rather than discovered in production.

| Area | What is undecided | Effect on testing |
| :---- | :---- | :---- |
| Order status model | Two status sets exist: one with pending, one with On the Way and Arrived | A status transition test cannot state the expected value. Scenarios UAT-VND-06 and UAT-RST-15 assume the second set |
| Grand total formula | The stated formula omits tax, GST and credit, while the order card includes them | No arithmetic test on an order or invoice total can be written until one formula is authoritative |
| Line subtotal | Defined once with the quantity and once without | The same applies to every line-level check |
| Catalog mandatory fields | Four mandatory fields in the business rules, eleven in the data model, with no SKU or UoM in the second | UAT-CAT-05 and UAT-CAT-08 assume the data model. A different decision changes both |
| Product uniqueness key | SKU within the company catalog, or customer number with model number | The duplicate detection test depends on which key applies |
| PDF import | One source requires PDF parsing into the mapping interface, another cancels the import and sends it to a manual process | No PDF import scenario can be written |
| Invalid rows on import | Block the whole import, or import the valid rows and report the rest | The expected result of UAT-CAT-05 changes entirely |
| NOT SUBSCRIBED in the subscriber table | Three contradictory statements about whether such a company appears there | UAT-ADM-15 and UAT-ADM-19 cannot both be satisfied under all three readings |
| Convert to Invoice permissions | Whether the action is restricted to managers or governed by a configurable approval rule | A permission test for a salesperson cannot state the expected outcome |
| Company type change through bulk edit | Whether the blocking validation applies to the bulk path and to cascaded subsidiaries | UAT-ADM-07 and UAT-ADM-30 may contradict each other in practice |

# **6\. Defect reporting**

Where a scenario fails, raise a defect carrying the following, so that it can be reproduced without a conversation:

* The scenario identifier and title

* The account and role used

* The exact steps taken, including the data entered

* The expected result, quoted from this document, and the actual result

* A screenshot or a short recording

* The requirement identifiers from the Covers column

* The date, the time and the environment

**Severity**

| Level | Definition |
| :---- | :---- |
| Critical | Money is calculated wrongly, data is lost, or a party sees data they must not see |
| Major | A scenario cannot be completed and no workaround exists |
| Minor | The scenario completes but the behaviour departs from the requirement |
| Cosmetic | Wording, alignment or formatting only |

*Anything that touches price visibility between manufacturer, vendor and client is Critical by default, whatever it looks like on screen. The confidentiality rules in Part 1 of the functional requirements are a commercial commitment, not a display preference.*

# **7\. Sign-off**

Testing is complete when every scenario in scope carries a result, no Critical or Major defect is open, and the blocked scenarios in section 5 have either been resolved or been accepted as deferred in writing.

| Suite | Scenarios | Passed | Result |
| :---- | :---- | :---- | :---- |
| 4.1 Authentication and onboarding | 11 |  |  |
| 4.2 Admin panel | 34 |  |  |
| 4.3 Manufacturer directory | 12 |  |  |
| 4.4 Manufacturer catalog and import | 13 |  |  |
| 4.5 Quotations | 30 |  |  |
| 4.6 Vendor portal | 32 |  |  |
| 4.7 Restaurant portal | 24 |  |  |
| Total | 156 |  |  |

**Signatures**

| Role | Name | Date |
| :---- | :---- | :---- |
| Client representative |  |  |
| Analyst |  |  |
| Delivery manager |  |  |

