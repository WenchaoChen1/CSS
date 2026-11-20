\echo ##### N129_post_still_deleted [N129]
WITH tops AS (
    SELECT c.id, c.type::text AS type, c.status::text AS status, c.subscriber_status::text AS sub,
           c.user_id, c.deleted_at
    FROM company c
    WHERE c.parent_company_id IS NULL AND c.deleted_at IS NOT NULL
      AND EXISTS (SELECT 1 FROM company k WHERE k.parent_company_id = c.id)
),
batch AS (
    SELECT deleted_at AS ts FROM tops
    GROUP BY deleted_at
    ORDER BY count(*) DESC, deleted_at DESC
    LIMIT 1
)
SELECT t.type, t.status,
       (t.deleted_at = b.ts) AS in_8011_batch,
       b.ts AS batch_deleted_at,
       count(*) AS n_still_deleted,
       count(*) FILTER (WHERE t.sub = 'ACTIVE') AS n_subscriber_active,
       count(*) FILTER (WHERE t.user_id IS NOT NULL) AS n_with_owner,
       count(*) FILTER (WHERE bk.id IS NOT NULL AND bk.deleted_at IS NULL) AS n_live_before_sprint6,
       count(*) FILTER (WHERE bk.deleted_at IS NOT NULL) AS n_deleted_before_sprint6,
       count(*) FILTER (WHERE bk.id IS NULL) AS n_not_in_backup,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM company k WHERE k.parent_company_id = t.id AND k.deleted_at IS NULL)) AS n_with_live_child
FROM tops t
LEFT JOIN batch b ON true
LEFT JOIN deprecated_company_back bk ON bk.id = t.id
GROUP BY 1, 2, 3, 4
ORDER BY 3 DESC NULLS LAST, 1, 2
LIMIT 20;
\echo ##### N129_post_assets [N129]
WITH tops AS (
    SELECT c.id, c.type::text AS type, c.deleted_at
    FROM company c
    WHERE c.parent_company_id IS NULL AND c.deleted_at IS NOT NULL
      AND EXISTS (SELECT 1 FROM company k WHERE k.parent_company_id = c.id)
),
batch AS (
    SELECT deleted_at AS ts FROM tops
    GROUP BY deleted_at
    ORDER BY count(*) DESC, deleted_at DESC
    LIMIT 1
),
p AS (
    SELECT t.id, t.type FROM tops t JOIN batch b ON b.ts = t.deleted_at
),
vp AS (
    SELECT vendor_id AS cid, count(*) AS n FROM vendor_product
    WHERE deleted_at IS NULL AND vendor_id IN (SELECT id FROM p) GROUP BY vendor_id
),
mp AS (
    SELECT manufacturer_company_id AS cid, count(*) AS n FROM manufacturer_product
    WHERE deleted_at IS NULL AND manufacturer_company_id IN (SELECT id FROM p) GROUP BY manufacturer_company_id
),
inv AS (
    SELECT company_id AS cid, count(*) AS n FROM manufacturer_subdivision_product
    WHERE deleted_at IS NULL AND company_id IN (SELECT id FROM p) GROUP BY company_id
),
pr AS (
    SELECT company_id AS cid, count(*) AS n FROM product
    WHERE deleted_at IS NULL AND company_id IN (SELECT id FROM p) GROUP BY company_id
),
mi AS (
    SELECT company_id AS cid, count(*) AS n FROM master_invoice
    WHERE deleted_at IS NULL AND company_id IN (SELECT id FROM p) GROUP BY company_id
),
codes AS (
    SELECT company_id AS cid,
           count(*) FILTER (WHERE inviter_company_id IS NULL) AS n_admin,
           count(*) FILTER (WHERE inviter_company_id IS NOT NULL) AS n_other
    FROM company_invitation
    WHERE deleted_at IS NULL AND used_at IS NULL AND invalidated_at IS NULL AND company_id IN (SELECT id FROM p)
    GROUP BY company_id
),
acc AS (
    SELECT company_id AS cid, count(*) AS n FROM system_account
    WHERE deleted_at IS NULL AND company_id IN (SELECT id FROM p) GROUP BY company_id
),
agg AS (
    SELECT p.type,
           count(*) AS n_parents,
           count(vp.cid) AS n_parents_with_vendor_product,
           coalesce(sum(vp.n), 0) AS n_vendor_product,
           count(mp.cid) AS n_parents_with_catalog,
           coalesce(sum(mp.n), 0) AS n_manufacturer_product,
           coalesce(sum(inv.n), 0) AS n_inventory_rows,
           coalesce(sum(pr.n), 0) AS n_product_rows,
           count(mi.cid) AS n_parents_with_master_invoice,
           coalesce(sum(mi.n), 0) AS n_master_invoice,
           count(*) FILTER (WHERE codes.n_admin > 0) AS n_parents_with_open_admin_code,
           coalesce(sum(codes.n_admin), 0) AS n_open_admin_code,
           coalesce(sum(codes.n_other), 0) AS n_open_other_code,
           coalesce(sum(acc.n), 0) AS n_live_accounts
    FROM p
    LEFT JOIN vp ON vp.cid = p.id
    LEFT JOIN mp ON mp.cid = p.id
    LEFT JOIN inv ON inv.cid = p.id
    LEFT JOIN pr ON pr.cid = p.id
    LEFT JOIN mi ON mi.cid = p.id
    LEFT JOIN codes ON codes.cid = p.id
    LEFT JOIN acc ON acc.cid = p.id
    GROUP BY p.type
),
ua AS (
    SELECT DISTINCT p.type, a.user_id
    FROM system_account a
    JOIN p ON p.id = a.company_id
    JOIN "system_user" su ON su.id = a.user_id AND su.deleted_at IS NULL
    WHERE a.deleted_at IS NULL
),
ua_agg AS (
    SELECT ua.type,
           count(*) AS n_users,
           count(*) FILTER (WHERE NOT EXISTS (
               SELECT 1 FROM system_account a2 JOIN company c2 ON c2.id = a2.company_id
               WHERE a2.user_id = ua.user_id AND a2.deleted_at IS NULL AND c2.deleted_at IS NULL
           )) AS n_users_no_live_company_account
    FROM ua
    GROUP BY ua.type
)
SELECT agg.*,
       coalesce(ua_agg.n_users, 0) AS n_users,
       coalesce(ua_agg.n_users_no_live_company_account, 0) AS n_users_no_live_company_account
FROM agg
LEFT JOIN ua_agg ON ua_agg.type = agg.type
ORDER BY agg.type
LIMIT 20;
\echo ##### N148_post_restored [N148,F4]
WITH cand AS (
    SELECT c.id, c.type::text AS type, c.status::text AS status, c.updated_at
    FROM company c
    WHERE c.parent_company_id IS NULL AND c.deleted_at IS NULL
      AND c.type::text IN ('CLIENT', 'VENDOR')
      AND c.user_id IS NOT NULL
      AND EXISTS (SELECT 1 FROM company k WHERE k.parent_company_id = c.id)
),
batch AS (
    SELECT updated_at AS ts FROM cand
    WHERE status = 'INVITED'
    GROUP BY updated_at
    ORDER BY count(*) DESC, updated_at DESC
    LIMIT 1
),
aud AS (
    SELECT a.company_id,
           bool_or(lower(a.entity_type) = 'company' AND lower(a.action) LIKE '%delet%') AS has_del,
           bool_or(lower(a.action) LIKE '%merg%') AS has_merge
    FROM company_audit_log a
    WHERE a.company_id IN (SELECT id FROM cand)
    GROUP BY a.company_id
)
SELECT cand.type, cand.status,
       (cand.updated_at = b.ts) AS in_8b98_batch,
       CASE WHEN bk.id IS NULL THEN 'not_in_backup'
            WHEN bk.deleted_at IS NULL THEN 'live_before_sprint6'
            ELSE 'deleted_before_sprint6' END AS before_sprint6,
       count(*) AS n_companies,
       count(*) FILTER (WHERE coalesce(a.has_del, false)) AS n_with_audit_deleted,
       count(*) FILTER (WHERE coalesce(a.has_merge, false)) AS n_with_audit_merged,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM company k WHERE k.parent_company_id = cand.id AND k.deleted_at IS NULL)) AS n_with_live_child_copy,
       min(bk.deleted_at)::date AS min_deleted_before,
       max(bk.deleted_at)::date AS max_deleted_before,
       max(b.ts) AS batch_updated_at
FROM cand
LEFT JOIN batch b ON true
LEFT JOIN deprecated_company_back bk ON bk.id = cand.id
LEFT JOIN aud a ON a.company_id = cand.id
GROUP BY 1, 2, 3, 4
ORDER BY 3 DESC NULLS LAST, 1, 2, 4
LIMIT 20;
\echo ##### N133_post_revived [N133]
WITH m AS (
    SELECT c.id, c.deleted_at, c.name, bk.id AS bk_id, bk.deleted_at AS bk_deleted_at
    FROM company c
    LEFT JOIN deprecated_company_back bk ON bk.id = c.id
    WHERE c.type::text = 'MANUFACTURER' AND c.parent_company_id IS NULL
),
aud AS (
    SELECT a.company_id,
           bool_or(lower(a.entity_type) = 'company' AND lower(a.action) LIKE '%delet%') AS has_del,
           bool_or(lower(a.action) LIKE '%merg%') AS has_merge
    FROM company_audit_log a
    WHERE a.company_id IN (SELECT id FROM m)
    GROUP BY a.company_id
)
SELECT CASE WHEN m.bk_id IS NULL THEN 'not_in_backup'
            WHEN m.bk_deleted_at IS NULL THEN 'live_before_sprint6'
            ELSE 'deleted_before_sprint6' END AS before_sprint6,
       (m.deleted_at IS NULL) AS live_now,
       count(*) AS n_top_manufacturers,
       count(*) FILTER (WHERE coalesce(a.has_del, false)) AS n_with_audit_deleted,
       count(*) FILTER (WHERE coalesce(a.has_merge, false)) AS n_with_audit_merged,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM system_account sa WHERE sa.company_id = m.id AND sa.deleted_at IS NULL)) AS n_with_live_account,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM company l
                                      WHERE l.type::text = 'MANUFACTURER' AND l.parent_company_id IS NULL
                                        AND l.deleted_at IS NULL AND l.id <> m.id
                                        AND lower(btrim(l.name)) = lower(btrim(m.name)))) AS n_same_name_as_other_live_top_mfr,
       min(m.bk_deleted_at)::date AS min_deleted_before,
       max(m.bk_deleted_at)::date AS max_deleted_before
FROM m
LEFT JOIN aud a ON a.company_id = m.id
GROUP BY 1, 2
ORDER BY 1, 2
LIMIT 20;
\echo ##### F4_post_mfr_default [F4]
WITH par AS (
    SELECT c.id FROM company c
    WHERE c.type::text = 'MANUFACTURER' AND c.parent_company_id IS NULL AND c.deleted_at IS NULL
),
kid AS (
    SELECT k.parent_company_id AS pid, k.type::text AS type, k.is_default, k.status::text AS status
    FROM company k
    WHERE k.deleted_at IS NULL AND k.parent_company_id IN (SELECT id FROM par)
)
SELECT (SELECT count(*) FROM par) AS n_live_top_manufacturers,
       (SELECT count(DISTINCT pid) FROM kid WHERE type = 'MANUFACTURER' AND is_default) AS n_with_live_default_child,
       (SELECT count(DISTINCT pid) FROM kid WHERE type = 'MANUFACTURER') AS n_with_any_live_mfr_child,
       (SELECT count(*) FROM kid WHERE type = 'MANUFACTURER' AND is_default) AS n_live_default_children,
       (SELECT count(*) FROM kid WHERE type = 'MANUFACTURER' AND NOT is_default) AS n_live_non_default_mfr_children,
       (SELECT count(*) FROM kid WHERE type = 'MANUFACTURER' AND status = 'ACTIVE') AS n_live_mfr_children_active,
       (SELECT count(*) FROM kid WHERE type <> 'MANUFACTURER') AS n_live_other_type_children;
\echo ##### F4_post_client_vendor [F4,N148]
WITH kid AS (
    SELECT k.parent_company_id AS pid,
           count(*) AS n_live_copies,
           count(*) FILTER (WHERE NOT EXISTS (
               SELECT 1 FROM system_account a WHERE a.company_id = k.id AND a.deleted_at IS NULL
           )) AS n_copies_without_account
    FROM company k
    WHERE k.deleted_at IS NULL AND k.parent_company_id IS NOT NULL
    GROUP BY k.parent_company_id
)
SELECT c.type::text AS type, c.status::text AS status,
       count(*) AS n_live_parents_with_live_copy,
       count(*) FILTER (WHERE c.user_id IS NOT NULL) AS n_with_owner,
       sum(kid.n_live_copies) AS n_live_copies,
       sum(kid.n_copies_without_account) AS n_copies_without_live_account
FROM company c
JOIN kid ON kid.pid = c.id
WHERE c.parent_company_id IS NULL AND c.deleted_at IS NULL
  AND c.type::text IN ('CLIENT', 'VENDOR')
GROUP BY 1, 2
ORDER BY 1, 2
LIMIT 20;
\echo ##### F3_post_hierarchy [F3]
SELECT bk.type::text AS type,
       CASE WHEN c.id IS NULL THEN 'row_gone'
            WHEN bk.parent_company_id IS NULL THEN 'parent_set_after_upgrade'
            WHEN c.parent_company_id IS NULL THEN 'parent_cleared'
            WHEN c.parent_company_id = bk.parent_company_id THEN 'same_parent'
            ELSE 'other_parent' END AS now_state,
       (bk.deleted_at IS NOT NULL) AS deleted_before_sprint6,
       count(*) AS n_rows,
       count(DISTINCT bk.parent_company_id) AS n_distinct_parents_before,
       count(DISTINCT c.parent_company_id) AS n_distinct_parents_now
FROM deprecated_company_back bk
LEFT JOIN company c ON c.id = bk.id
WHERE bk.parent_company_id IS NOT NULL OR c.parent_company_id IS NOT NULL
GROUP BY 1, 2, 3
ORDER BY 4 DESC
LIMIT 20;
\echo ##### N97_deleted_on_test [N97]
WITH gone AS (
  SELECT b.id, b.type::text AS type, b.created_at, b.user_id, b.deleted_at
  FROM deprecated_company_back b
  WHERE NOT EXISTS (SELECT 1 FROM company c WHERE c.id = b.id)
),
r_gone AS (
  -- b7d82c2e651b copied each restaurant under its own id unless the id was taken; a parentless restaurant
  -- whose id was free and is no longer in company was hard-deleted (only c4d8e2a6f1b3 deletes company rows)
  SELECT r.id, r.created_at, r.deleted_at
  FROM deprecated_restaurant r
  WHERE r.company_id IS NULL
    AND NOT EXISTS (SELECT 1 FROM company c WHERE c.id = r.id)
    AND NOT EXISTS (SELECT 1 FROM deprecated_company_back b WHERE b.id = r.id)
    AND NOT EXISTS (SELECT 1 FROM deprecated_store s WHERE s.id = r.id)
)
SELECT (SELECT count(*) FROM deprecated_company_back) AS company_back_rows,
       count(*) AS back_rows_gone_from_company,
       count(*) FILTER (WHERE type = 'CLIENT') AS gone_client,
       count(*) FILTER (WHERE type = 'VENDOR') AS gone_vendor,
       count(*) FILTER (WHERE type NOT IN ('CLIENT', 'VENDOR')) AS gone_other_type,
       count(*) FILTER (WHERE created_at >= '2026-09-17' AND user_id IS NULL AND deleted_at IS NULL) AS gone_with_doomed_shape,
       min(created_at)::date AS gone_first_created,
       max(created_at)::date AS gone_last_created,
       (SELECT count(*) FROM r_gone) AS restaurant_copies_gone,
       (SELECT count(*) FROM r_gone WHERE created_at >= '2026-09-17' AND deleted_at IS NULL) AS restaurant_copies_gone_doomed_shape,
       (SELECT count(*) FROM deprecated_store s
         WHERE NOT EXISTS (SELECT 1 FROM company c WHERE c.id = s.id)
           AND NOT EXISTS (SELECT 1 FROM deprecated_company_back b WHERE b.id = s.id)) AS store_copies_gone,
       (SELECT count(*) FROM company_invitation i
         WHERE i.company_id IS NULL AND i.client_id IS NOT NULL) AS invitations_client_linked_no_company,
       (SELECT count(*) FROM company_invitation i
         WHERE i.company_id IS NULL AND i.client_id IS NOT NULL
           AND i.used_at IS NULL AND i.invalidated_at IS NULL AND i.deleted_at IS NULL) AS of_which_still_open
FROM gone;
\echo ##### N97_fk_restrict_test [N97]
SELECT count(*) AS restrict_fk_to_company,
       string_agg(con.conrelid::regclass::text || '.' || a.attname || ' ' || con.confdeltype::text, ', '
                  ORDER BY con.conrelid::regclass::text, a.attname) AS fk_list
FROM pg_constraint con
JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = con.conkey[1]
WHERE con.contype = 'f'
  AND con.confrelid = 'public.company'::regclass
  AND con.confdeltype IN ('a', 'r');
\echo ##### F39_moved_on_test [F39]
SELECT (SELECT count(*) FROM deprecated_manufacturer_inventory_move_backup) AS moved_rows,
       (SELECT count(DISTINCT manufacturer_subdivision_id) FROM deprecated_manufacturer_inventory_move_backup) AS source_subdivisions,
       (SELECT count(*) FROM deprecated_manufacturer_inventory_move_backup b
          JOIN manufacturer_subdivision_product i ON i.id = b.row_id
         WHERE i.deleted_at IS NOT NULL) AS moved_rows_soft_deleted,
       (SELECT count(*) FROM (SELECT company_id, manufacturer_product_id, manufacturer_product_variation_id
                              FROM manufacturer_subdivision_product
                              GROUP BY 1, 2, 3 HAVING count(*) > 1) x) AS duplicate_groups_now,
       (SELECT count(*) FROM (SELECT manufacturer_company_id FROM deprecated_manufacturer_subdivision
                              GROUP BY 1 HAVING count(*) > 1) y) AS mfr_with_multi_subdivisions_incl_deleted;
\echo ##### F50_fk_on_test [F50]
SELECT (SELECT string_agg(con.conname || ' on_delete=' || con.confdeltype::text, ', ')
          FROM pg_constraint con
         WHERE con.contype = 'f' AND con.conrelid = 'public.system_account'::regclass
           AND con.confrelid = 'public.company'::regclass) AS account_company_fk,
       (SELECT count(*) FROM system_account a
         WHERE NOT EXISTS (SELECT 1 FROM company c WHERE c.id = a.company_id)) AS orphan_accounts,
       (SELECT count(*) FROM system_account a JOIN company c ON c.id = a.company_id
         WHERE c.deleted_at IS NOT NULL) AS accounts_on_soft_deleted_companies,
       (SELECT count(*) FROM system_account a JOIN company c ON c.id = a.company_id
         WHERE c.deleted_at IS NOT NULL AND a.deleted_at IS NULL) AS live_accounts_on_soft_deleted_companies;
\echo ##### N95_credit_balance_test [N95]
SELECT count(*) AS restaurant_accounts,
       count(*) FILTER (WHERE ra.credit_balance <> 0) AS nonzero_accounts,
       count(DISTINCT ra.restaurant_id) FILTER (WHERE ra.credit_balance <> 0) AS nonzero_restaurants,
       count(*) FILTER (WHERE ra.credit_balance <> 0 AND ra.deleted_at IS NULL AND r.deleted_at IS NULL) AS nonzero_live,
       coalesce(sum(ra.credit_balance) FILTER (WHERE ra.credit_balance > 0), 0) AS positive_total,
       coalesce(sum(ra.credit_balance) FILTER (WHERE ra.credit_balance < 0), 0) AS negative_total,
       coalesce(sum(ra.credit_balance), 0) AS net_total,
       (max(ra.updated_at) FILTER (WHERE ra.credit_balance <> 0))::date AS last_nonzero_update
FROM deprecated_restaurant_account ra
LEFT JOIN deprecated_restaurant r ON r.id = ra.restaurant_id;
\echo ##### F25_vendor_cleared_test [F25]
SELECT count(*) AS audit_rows_joined_to_client,
       count(*) FILTER (WHERE c.store_id IS NULL AND a.vendor_id IS NULL) AS rows_store_null_vendor_null,
       count(DISTINCT a.client_id) FILTER (WHERE c.store_id IS NULL AND a.vendor_id IS NULL) AS clients_store_null_vendor_null,
       (min(a.created_at) FILTER (WHERE c.store_id IS NULL AND a.vendor_id IS NULL))::date AS first_row,
       (max(a.created_at) FILTER (WHERE c.store_id IS NULL AND a.vendor_id IS NULL))::date AS last_row,
       count(*) FILTER (WHERE c.store_id IS NULL AND a.vendor_id IS NOT NULL) AS rows_store_null_vendor_kept,
       count(*) FILTER (WHERE c.store_id IS NOT NULL AND a.vendor_id IS DISTINCT FROM c.store_id) AS rows_vendor_not_store
FROM log_audit_client a
JOIN client c ON c.id = a.client_id;
\echo ##### POST_F32_product_number [F32]
SELECT
  (SELECT count(*) FROM product) AS products,
  (SELECT count(*) FROM product WHERE product_number IS NOT NULL) AS with_number,
  (SELECT count(*) FROM (SELECT 1 FROM product WHERE deleted_at IS NULL AND product_number IS NOT NULL
                         GROUP BY company_id, product_number HAVING count(*) > 1) d) AS dup_live_groups,
  (SELECT count(*) FROM (SELECT 1 FROM product WHERE product_number IS NOT NULL
                         GROUP BY company_id, product_number HAVING count(*) > 1) d) AS dup_groups_incl_deleted,
  (SELECT count(*) FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'uq_product_company_id_product_number') AS unique_index_present;
\echo ##### POST_N14_buying_group [N14]
SELECT
  (SELECT count(*) FROM company_info_buying_group) AS buying_groups,
  (SELECT count(*) FROM company_info_buying_group WHERE deleted_at IS NOT NULL) AS deleted_buying_groups,
  (SELECT count(*) FROM (SELECT 1 FROM company_info_buying_group
                         GROUP BY company_id, lower(name) HAVING count(*) > 1) d) AS dup_ignoring_case,
  (SELECT count(*) FROM pg_indexes WHERE schemaname = 'public'
      AND indexname = 'uq_company_info_buying_group_company_id_lower_name') AS lower_index_present,
  (SELECT count(*) FROM pg_constraint WHERE conname = 'uq_company_info_buying_group_company_id_name') AS old_constraint_left;
\echo ##### POST_049461_account_company_fk [F50]
SELECT
  (SELECT count(*) FROM system_account) AS accounts,
  (SELECT count(*) FROM system_account a WHERE NOT EXISTS (SELECT 1 FROM company c WHERE c.id = a.company_id)) AS orphan_accounts,
  (SELECT count(*) FROM system_account a JOIN company c ON c.id = a.company_id
    WHERE c.deleted_at IS NOT NULL AND a.deleted_at IS NULL) AS live_accounts_in_deleted_companies,
  (SELECT string_agg(conname || ':' || confdeltype::text, ',') FROM pg_constraint
    WHERE contype = 'f' AND conrelid = 'system_account'::regclass AND confrelid = 'company'::regclass) AS company_fk;
\echo ##### POST_role_codes [F18]
SELECT
  (SELECT count(*) FROM (SELECT 1 FROM system_company_role WHERE deleted_at IS NULL AND code IS NOT NULL
                         GROUP BY company_id, code HAVING count(*) > 1) d) AS dup_live_company_role_code,
  (SELECT count(*) FROM (SELECT 1 FROM system_company_role WHERE deleted_at IS NULL
                         GROUP BY company_id, name HAVING count(*) > 1) d) AS dup_live_company_role_name,
  (SELECT count(*) FROM (SELECT 1 FROM system_company_type_role_template WHERE deleted_at IS NULL
                         GROUP BY company_type, role_name HAVING count(*) > 1) d) AS dup_live_templates,
  (SELECT count(*) FROM (SELECT 1 FROM deprecated_system_company_type_role
                         WHERE NOT belongs_to_company AND deleted_at IS NULL
                         GROUP BY type, code HAVING count(*) > 1) d) AS dup_live_type_role_code,
  (SELECT count(*) FROM system_company_role WHERE code IS NULL AND deleted_at IS NULL) AS live_company_roles_without_code;
\echo ##### POST_b5e1_company_level_roles [N3 / N93（同迁移）]
SELECT '(role_map rows)' AS tbl, '' AS action, count(*) AS n FROM deprecated_company_level_role_map
UNION ALL
SELECT '(company-level roles removed)', '', count(*) FROM deprecated_company_level_role_backup
UNION ALL
SELECT '(removed roles with no mapping)', '', count(*) FROM deprecated_company_level_role_backup b
 WHERE NOT EXISTS (SELECT 1 FROM deprecated_company_level_role_map m WHERE m.old_role_id = b.id)
UNION ALL
SELECT tbl, action, count(*) FROM deprecated_company_level_role_reference_backup GROUP BY tbl, action
ORDER BY 1, 2
LIMIT 20;
\echo ##### POST_c4d8_invitations [N97]
SELECT
  count(*) AS invitations,
  count(*) FILTER (WHERE client_id IS NOT NULL) AS from_client_links,
  (SELECT count(*) FROM (SELECT 1 FROM company_invitation GROUP BY invitation_code HAVING count(*) > 1) d) AS dup_codes,
  max(length(invitation_code)) AS max_code_len,
  max(length(name)) AS max_name_len,
  max(length(address)) AS max_address_len,
  max(length(email)) AS max_email_len,
  max(length(phone_number)) AS max_phone_len,
  count(*) FILTER (WHERE company_id IS NULL) AS invitations_without_company
FROM company_invitation;
\echo ##### POST_merge_into_company_info [N61（同迁移）]
SELECT
  (SELECT count(*) FROM (SELECT company_id FROM deprecated_manufacturer_profile WHERE deleted_at IS NULL
                         GROUP BY company_id HAVING count(*) > 1) d) AS profile_multi_live,
  (SELECT count(*) FROM (SELECT manufacturer_company_id FROM deprecated_manufacturer_representation WHERE deleted_at IS NULL
                         GROUP BY manufacturer_company_id HAVING count(*) > 1) d) AS representation_multi_live,
  (SELECT count(*) FROM (SELECT company_id FROM deprecated_company_billing WHERE deleted_at IS NULL
                         GROUP BY company_id HAVING count(*) > 1) d) AS billing_multi_live,
  (SELECT count(*) FROM company_info
    WHERE accounts_payable_name IS NOT NULL OR accounts_payable_email IS NOT NULL
       OR accounts_payable_phone_number IS NOT NULL) AS company_info_with_ap;
\echo ##### POST_F39_inventory_move [F39]
SELECT
  (SELECT count(*) FROM deprecated_manufacturer_inventory_move_backup) AS inventory_rows_moved,
  (SELECT count(*) FROM (SELECT 1 FROM manufacturer_subdivision_product
                         GROUP BY company_id, manufacturer_product_id, manufacturer_product_variation_id
                         HAVING count(*) > 1) d) AS dup_company_product_variation,
  (SELECT count(*) FROM company WHERE type::text = 'MANUFACTURER' AND parent_company_id IS NOT NULL) AS former_subdivisions,
  (SELECT count(*) FROM (SELECT parent_company_id FROM company
                         WHERE type::text = 'MANUFACTURER' AND parent_company_id IS NOT NULL
                         GROUP BY parent_company_id HAVING count(*) > 1) d) AS manufacturers_with_several_subdivisions;
\echo ##### POST_address_split [N59 / N61 / N46]
SELECT 'company' AS tbl,
       count(*) FILTER (WHERE city IS NOT NULL OR state IS NOT NULL OR zip_code IS NOT NULL) AS split_rows,
       max(length(city)) AS max_city, max(length(state)) AS max_state, max(length(zip_code)) AS max_zip
FROM company
UNION ALL
SELECT 'quotation.from', count(*) FILTER (WHERE from_city IS NOT NULL OR from_state IS NOT NULL OR from_zip_code IS NOT NULL),
       max(length(from_city)), max(length(from_state)), max(length(from_zip_code))
FROM quotation
UNION ALL
SELECT 'quotation.ship_to', count(*) FILTER (WHERE ship_to_city IS NOT NULL OR ship_to_state IS NOT NULL OR ship_to_zip_code IS NOT NULL),
       max(length(ship_to_city)), max(length(ship_to_state)), max(length(ship_to_zip_code))
FROM quotation
UNION ALL
SELECT 'client.temporary', count(*) FILTER (WHERE temporary_city IS NOT NULL OR temporary_state IS NOT NULL OR temporary_zip_code IS NOT NULL),
       max(length(temporary_city)), max(length(temporary_state)), max(length(temporary_zip_code))
FROM client
UNION ALL
SELECT 'client_temporary_store', count(*) FILTER (WHERE city IS NOT NULL OR state IS NOT NULL OR zip_code IS NOT NULL),
       max(length(city)), max(length(state)), max(length(zip_code))
FROM client_temporary_store
UNION ALL
SELECT 'quotation_vendor_client', count(*) FILTER (WHERE city IS NOT NULL OR state IS NOT NULL OR zip_code IS NOT NULL),
       max(length(city)), max(length(state)), max(length(zip_code))
FROM quotation_vendor_client
ORDER BY 1;
\echo ##### POST_seeded_rows [N53（同迁移）；无编号（e7b3d9a1c5f2 补种价格档）]
SELECT
  (SELECT count(*) FROM price_tier pt
    WHERE pt.id = md5('price_tier_seed:' || pt.company_id::text || ':' || pt.sort_order::text)::uuid) AS seeded_price_tiers,
  (SELECT count(DISTINCT pt.company_id) FROM price_tier pt
    WHERE pt.id = md5('price_tier_seed:' || pt.company_id::text || ':' || pt.sort_order::text)::uuid) AS companies_seeded,
  (SELECT count(*) FROM price_tier pt JOIN company c ON c.id = pt.company_id
    WHERE pt.id = md5('price_tier_seed:' || pt.company_id::text || ':' || pt.sort_order::text)::uuid
      AND c.parent_company_id IS NULL) AS seeded_on_top_level_companies,
  (SELECT count(*) FROM price_tier pt JOIN company c ON c.id = pt.company_id
    WHERE pt.id = md5('price_tier_seed:' || pt.company_id::text || ':' || pt.sort_order::text)::uuid
      AND c.deleted_at IS NOT NULL) AS seeded_on_deleted_companies,
  (SELECT count(*) FROM company_info_phone_number p
    WHERE p.id = md5('company.phone_number:' || p.company_id::text)::uuid) AS backfilled_phones,
  (SELECT max(length(phone_number)) FROM company_info_phone_number) AS max_phone_len;
\echo ##### N99_zero_perm_post [N99]
WITH live_role AS (
  SELECT cr.id, cr.company_id, cr.name, c.company_type
  FROM system_company_role cr
  JOIN company c ON c.id = cr.company_id
  WHERE cr.deleted_at IS NULL AND c.deleted_at IS NULL
),
perm AS (
  SELECT system_company_role_id AS role_id, count(*) AS n
  FROM system_company_role_permission_m2m
  WHERE deleted_at IS NULL
  GROUP BY system_company_role_id
),
holder AS (
  SELECT arm.role_id, count(*) AS n
  FROM system_account_role_m2m arm
  JOIN system_account a ON a.id = arm.account_id
  WHERE a.deleted_at IS NULL AND a.is_active
  GROUP BY arm.role_id
),
r AS (
  SELECT lr.company_type, lr.id, lr.company_id,
         coalesce(p.n, 0) AS n_perm,
         coalesce(h.n, 0) AS n_holders,
         EXISTS (SELECT 1 FROM system_company_type_role_template t
                 WHERE t.company_type = lr.company_type AND t.role_name = lr.name AND t.deleted_at IS NULL) AS has_template
  FROM live_role lr
  LEFT JOIN perm p ON p.role_id = lr.id
  LEFT JOIN holder h ON h.role_id = lr.id
)
SELECT company_type,
  count(*) AS live_roles,
  count(*) FILTER (WHERE NOT has_template) AS roles_without_template,
  count(*) FILTER (WHERE n_perm = 0) AS roles_zero_permission,
  count(*) FILTER (WHERE n_perm = 0 AND n_holders > 0) AS zero_perm_roles_held,
  sum(n_holders) FILTER (WHERE n_perm = 0) AS live_accounts_on_zero_perm_roles,
  count(DISTINCT company_id) FILTER (WHERE n_perm = 0 AND n_holders > 0) AS companies_affected
FROM r
GROUP BY company_type
ORDER BY company_type
LIMIT 20;
\echo ##### N119_ceo_gap_post [N119]
WITH t0 AS (
  SELECT min(tp.created_at) AS t
  FROM system_company_type_role_permission_template tp
  JOIN system_company_type_role_template t ON t.id = tp.system_company_type_role_template_id
  JOIN system_base_permission p ON p.id = tp.system_permission_base_id
  WHERE t.role_name = 'CEO' AND p.code = 'packing_slips:assign_packer_driver'
),
ceo AS (
  SELECT cr.id AS role_id, c.id AS company_id, c.company_type,
         cr.created_at > t0.t AS created_after_2ea4,
         EXISTS (SELECT 1 FROM system_account_role_m2m arm
                 JOIN system_account a ON a.id = arm.account_id
                 WHERE arm.role_id = cr.id AND a.deleted_at IS NULL AND a.is_active) AS has_live_holder
  FROM company c
  JOIN system_company_role cr ON cr.company_id = c.id AND cr.name = 'CEO' AND cr.deleted_at IS NULL
  CROSS JOIN t0
  WHERE c.deleted_at IS NULL
),
tmpl AS (
  SELECT t.company_type, p.id AS node_id, p.code
  FROM system_company_type_role_template t
  JOIN system_company_type_role_permission_template tp
    ON tp.system_company_type_role_template_id = t.id AND tp.deleted_at IS NULL
  JOIN system_base_permission p ON p.id = tp.system_permission_base_id AND p.deleted_at IS NULL
  WHERE t.role_name = 'CEO' AND t.deleted_at IS NULL
),
missing AS (
  SELECT ceo.role_id, tmpl.code
  FROM ceo
  JOIN tmpl ON tmpl.company_type = ceo.company_type
  WHERE NOT EXISTS (
    SELECT 1 FROM system_company_role_permission_m2m m
    WHERE m.system_company_role_id = ceo.role_id
      AND m.system_permission_base_id = tmpl.node_id
      AND m.deleted_at IS NULL)
)
SELECT ceo.company_type,
  count(DISTINCT ceo.company_id) AS companies_with_ceo_role,
  count(DISTINCT ceo.company_id) FILTER (WHERE mi.role_id IS NOT NULL) AS ceo_missing_any_template_node,
  count(DISTINCT ceo.company_id) FILTER (WHERE mi.role_id IS NOT NULL AND ceo.has_live_holder) AS missing_and_ceo_role_held,
  count(DISTINCT ceo.company_id) FILTER (WHERE ceo.created_after_2ea4) AS ceo_roles_created_after_2ea4,
  count(DISTINCT ceo.company_id) FILTER (WHERE ceo.created_after_2ea4 AND mi.role_id IS NOT NULL) AS created_after_2ea4_but_missing,
  count(DISTINCT ceo.company_id) FILTER (WHERE mi.code = 'packing_slips:packing_driving_approve') AS missing_packing_approve,
  count(DISTINCT ceo.company_id) FILTER (WHERE mi.code = 'packing_slips:assign_packer_driver') AS missing_assign_packer_driver,
  count(DISTINCT ceo.company_id) FILTER (WHERE mi.code = 'packing_slips:turn_approval') AS missing_turn_approval,
  count(DISTINCT ceo.company_id) FILTER (WHERE mi.code = 'packing_slips:order_problem_popups') AS missing_order_problem_popups,
  count(DISTINCT ceo.company_id) FILTER (WHERE mi.code = 'new_order_email') AS missing_new_order_email
FROM ceo
LEFT JOIN missing mi ON mi.role_id = ceo.role_id
GROUP BY ceo.company_type
ORDER BY ceo.company_type
LIMIT 20;
\echo ##### N7_names_post [N7]
WITH acc AS (
  SELECT a.id, a.first_name, a.last_name,
         (a.deleted_at IS NULL AND a.is_active AND c.deleted_at IS NULL) AS in_use
  FROM system_account a
  LEFT JOIN company c ON c.id = a.company_id
),
noname AS (
  SELECT id, first_name IS NULL AS fn_null
  FROM acc
  WHERE in_use AND btrim(coalesce(first_name, '')) = '' AND btrim(coalesce(last_name, '')) = ''
),
slip_people AS (
  SELECT x.id
  FROM order_packing_slip ps
  CROSS JOIN LATERAL (VALUES (ps.packer_account_id), (ps.driver_account_id)) AS x(id)
  WHERE ps.deleted_at IS NULL AND x.id IS NOT NULL
),
comment_people AS (
  SELECT x.id, oc.order_id
  FROM order_comment oc
  CROSS JOIN LATERAL (VALUES (oc.account_id), (oc.updated_by_account_id)) AS x(id)
  WHERE oc.deleted_at IS NULL AND x.id IS NOT NULL
)
SELECT
  (SELECT count(*) FROM acc WHERE in_use) AS accounts_in_use,
  (SELECT count(*) FROM noname) AS in_use_both_names_empty,
  (SELECT count(*) FROM noname WHERE fn_null) AS in_use_first_name_null,
  (SELECT count(*) FROM noname n WHERE n.id IN (SELECT id FROM slip_people)) AS noname_assigned_packer_or_driver,
  (SELECT count(*) FROM noname n WHERE n.id IN (SELECT id FROM comment_people)) AS noname_wrote_or_edited_comment,
  (SELECT count(DISTINCT cp.order_id) FROM comment_people cp
     JOIN system_account a ON a.id = cp.id
     WHERE a.first_name IS NULL) AS orders_with_comment_by_null_first_name,
  (SELECT count(*) FROM "system_user" u
     WHERE u.deleted_at IS NULL AND btrim(coalesce(u.first_name, '')) = '') AS live_users_without_first_name;
\echo ##### F13_type_rule_post [F13]
WITH live_cct AS (
  SELECT d.company_id, ct.code, ct.category::text AS category
  FROM deprecated_company_company_type d
  JOIN company_type ct ON ct.id = d.company_type_id
  WHERE d.deleted_at IS NULL
),
agg AS (
  SELECT company_id, count(*) AS n_types,
    count(*) FILTER (WHERE category = 'VENDOR') AS n_vendor,
    count(*) FILTER (WHERE category = 'MANUFACTURER') AS n_mfr,
    count(*) FILTER (WHERE category = 'CLIENT') AS n_client,
    array_agg(code) AS codes
  FROM live_cct
  GROUP BY company_id
),
legacy AS (
  SELECT c.id, c.type::text AS ctype, c.company_type, c.deleted_at IS NULL AS is_live,
         c.parent_company_id IS NOT NULL AS is_child,
         coalesce(c.parent_company_id, c.id) AS source_id
  FROM company c
  WHERE c.type::text <> 'ADMIN'
    AND (c.parent_company_id IS NOT NULL OR c.id IN (SELECT b.id FROM deprecated_company_back b))
)
SELECT l.ctype, l.is_child,
  CASE
    WHEN a.company_id IS NULL THEN 'source_no_live_type'
    WHEN (CASE l.ctype WHEN 'VENDOR' THEN a.n_vendor WHEN 'MANUFACTURER' THEN a.n_mfr ELSE a.n_client END) > 1 THEN 'source_multi_own_category'
    WHEN (CASE l.ctype WHEN 'VENDOR' THEN a.n_vendor WHEN 'MANUFACTURER' THEN a.n_mfr ELSE a.n_client END) = 1 THEN 'source_single_own_category'
    ELSE 'source_only_other_category'
  END AS source_rule,
  count(*) AS companies,
  count(*) FILTER (WHERE l.is_live) AS live_companies,
  count(*) FILTER (WHERE a.n_types > 1) AS source_has_multiple_types,
  count(*) FILTER (WHERE a.codes IS NOT NULL AND NOT (l.company_type = ANY (a.codes))) AS company_type_not_among_source_types,
  count(DISTINCT l.company_type) AS distinct_company_types
FROM legacy l
LEFT JOIN agg a ON a.company_id = l.source_id
GROUP BY 1, 2, 3
ORDER BY companies DESC
LIMIT 20;
\echo ##### F17_copies_post [F17]
WITH copies AS (
  SELECT cp.id, cp.deleted_at, cp.is_active, ch.company_type, ch.deleted_at AS ch_deleted
  FROM system_account cp
  JOIN company ch ON ch.id = cp.company_id AND ch.parent_company_id IS NOT NULL
  JOIN system_account src ON src.company_id = ch.parent_company_id AND src.user_id = cp.user_id
  WHERE cp.id = md5(src.id::text || ':' || ch.id::text)::uuid
),
parent_acc AS (
  SELECT a.user_id, a.company_id AS parent_id
  FROM system_account a
  JOIN company p ON p.id = a.company_id
  WHERE a.deleted_at IS NULL AND a.is_active
    AND p.parent_company_id IS NULL AND p.deleted_at IS NOT NULL
    AND EXISTS (SELECT 1 FROM company ch WHERE ch.parent_company_id = p.id)
),
gap AS (
  SELECT pa.user_id, pa.parent_id,
    EXISTS (SELECT 1 FROM system_account x
            JOIN company ch ON ch.id = x.company_id
            WHERE ch.parent_company_id = pa.parent_id AND ch.deleted_at IS NULL
              AND x.user_id = pa.user_id AND x.deleted_at IS NULL AND x.is_active) AS has_branch_account
  FROM parent_acc pa
)
SELECT 'copies:' || coalesce(company_type, 'null') AS metric, count(*) AS n FROM copies GROUP BY company_type
UNION ALL SELECT 'copies_of_deleted_accounts', count(*) FROM copies WHERE deleted_at IS NOT NULL
UNION ALL SELECT 'copies_of_inactive_accounts', count(*) FROM copies WHERE deleted_at IS NULL AND NOT is_active
UNION ALL SELECT 'copies_usable_now', count(*) FROM copies WHERE deleted_at IS NULL AND is_active AND ch_deleted IS NULL
UNION ALL SELECT 'live_accounts_in_deleted_parents', count(*) FROM gap
UNION ALL SELECT 'of_which_no_usable_branch_account', count(*) FROM gap WHERE NOT has_branch_account
UNION ALL SELECT 'users_without_usable_branch_account', count(DISTINCT user_id) FROM gap WHERE NOT has_branch_account
ORDER BY 1
LIMIT 20;
\echo ##### N140_bill_to_post [N140]
WITH ceo AS (
  SELECT a.company_id, a.is_active AS acc_active, u.email, u.phone_number,
         u.is_active AS user_active, u.deleted_at AS user_deleted
  FROM system_account a
  JOIN system_account_role_m2m m ON m.account_id = a.id
  JOIN system_company_role r ON r.id = m.role_id AND r.name = 'CEO'
  JOIN "system_user" u ON u.id = a.user_id
  WHERE a.deleted_at IS NULL
),
hit AS (
  SELECT cl.id,
    bool_or(cl.bill_to_email IS NOT NULL AND lower(c.email) = lower(cl.bill_to_email)) AS email_eq,
    bool_or(cl.bill_to_phone IS NOT NULL AND c.phone_number = cl.bill_to_phone) AS phone_eq,
    bool_or(cl.bill_to_email IS NOT NULL AND lower(c.email) = lower(cl.bill_to_email)
            AND (NOT c.acc_active OR NOT c.user_active OR c.user_deleted IS NOT NULL)) AS email_eq_inactive
  FROM client cl
  JOIN ceo c ON c.company_id = cl.restaurant_id
  GROUP BY cl.id
)
SELECT
  count(*) AS clients_total,
  count(*) FILTER (WHERE cl.bill_to_email IS NOT NULL) AS with_bill_to_email,
  count(*) FILTER (WHERE h.email_eq) AS bill_to_email_eq_ceo_login,
  count(*) FILTER (WHERE h.phone_eq) AS bill_to_phone_eq_ceo_login,
  count(*) FILTER (WHERE h.email_eq AND cl.deleted_at IS NULL) AS live_clients_email_eq_ceo_login,
  count(*) FILTER (WHERE h.email_eq_inactive) AS email_eq_inactive_ceo,
  count(DISTINCT cl.store_id) FILTER (WHERE h.email_eq) AS vendor_stores_seeing_it
FROM client cl
LEFT JOIN hit h ON h.id = cl.id;
\echo ##### N2_dev_admin_post [N2/H1]
WITH dev_user AS (
  SELECT id, deleted_at, is_active
  FROM "system_user"
  WHERE id = 'bcd926a7-156b-45d0-803d-e59e33912032' OR lower(email) = 'dev.admin@yopmail.com'
),
dev_acc AS (
  SELECT a.id, a.company_id, a.deleted_at, a.is_active, c.company_type, c.deleted_at AS c_deleted,
    EXISTS (SELECT 1 FROM system_account_role_m2m m
            JOIN system_company_role r ON r.id = m.role_id
            WHERE m.account_id = a.id AND r.name = 'CEO') AS is_ceo
  FROM system_account a
  JOIN dev_user du ON du.id = a.user_id
  LEFT JOIN company c ON c.id = a.company_id
)
SELECT 'dev_admin_users_found' AS metric, NULL::text AS company_type, count(*) AS n FROM dev_user
UNION ALL
SELECT 'dev_admin_users_active', NULL, count(*) FROM dev_user WHERE deleted_at IS NULL AND is_active
UNION ALL
SELECT 'dev_admin_accounts_all_states', NULL, count(*) FROM dev_acc
UNION ALL
SELECT 'dev_admin_accounts_usable', company_type, count(*)
FROM dev_acc WHERE deleted_at IS NULL AND is_active AND c_deleted IS NULL
GROUP BY company_type
UNION ALL
SELECT 'dev_admin_usable_companies_total', NULL, count(DISTINCT company_id)
FROM dev_acc WHERE deleted_at IS NULL AND is_active AND c_deleted IS NULL
UNION ALL
SELECT 'dev_admin_usable_ceo_accounts', NULL, count(*)
FROM dev_acc WHERE deleted_at IS NULL AND is_active AND c_deleted IS NULL AND is_ceo
UNION ALL
SELECT 'users_with_usable_account_in_' || c.company_type, c.company_type, count(DISTINCT a.user_id)
FROM system_account a
JOIN company c ON c.id = a.company_id
WHERE c.company_type IN ('dev_admin', 'admin') AND a.deleted_at IS NULL AND a.is_active AND c.deleted_at IS NULL
GROUP BY c.company_type
ORDER BY 1, 2
LIMIT 20;
\echo ##### N59_post_us_state [N59、F6]
WITH v AS (
  SELECT 'company' AS src, city, state, deleted_at FROM company
  UNION ALL SELECT 'company_invitation', city, state, deleted_at FROM company_invitation
  UNION ALL SELECT 'client.temporary_*', temporary_city, temporary_state, deleted_at FROM client
  UNION ALL SELECT 'client.bill_to_*', bill_to_city, bill_to_state, deleted_at FROM client
  UNION ALL SELECT 'client_temporary_store', city, state, deleted_at FROM client_temporary_store
  UNION ALL SELECT 'quotation_vendor_client', city, state, deleted_at FROM quotation_vendor_client
  UNION ALL SELECT 'quotation.from_*', from_city, from_state, deleted_at FROM quotation
  UNION ALL SELECT 'quotation.ship_to_*', ship_to_city, ship_to_state, deleted_at FROM quotation
  UNION ALL SELECT 'order.bill_to', bill_to ->> 'city', bill_to ->> 'state', deleted_at FROM "order" WHERE bill_to IS NOT NULL
),
f AS (
  SELECT src, deleted_at,
         state IS NOT NULL AS has_state,
         upper(btrim(state)) = 'US' AS state_us,
         city ~ '^[[:space:]]*[A-Za-z]{2}[[:space:]]+[0-9]{5}(-[0-9]{4})?[[:space:]]*$' AS city_st_zip
  FROM v
)
SELECT src,
       count(*) FILTER (WHERE has_state) AS rows_with_state,
       count(*) FILTER (WHERE state_us) AS state_us,
       count(*) FILTER (WHERE city_st_zip) AS city_like_st_zip,
       count(*) FILTER (WHERE state_us AND city_st_zip) AS state_us_and_city_st_zip,
       count(*) FILTER (WHERE state_us AND deleted_at IS NULL) AS state_us_live
FROM f
GROUP BY src
ORDER BY src
LIMIT 20;
\echo ##### N61_N10_post_profile_address [N61、N10]
WITH m AS (
  SELECT DISTINCT ON (p.company_id) p.company_id,
         coalesce(trim(p.address), '') <> '' AS has_street,
         (coalesce(trim(p.city), '') <> '' OR coalesce(trim(p.state), '') <> '' OR coalesce(trim(p.zip_code), '') <> '') AS has_city_state_zip,
         c.address, c.city, c.state, c.zip_code,
         b.id IS NOT NULL AS has_backup, b.address AS backup_address
  FROM deprecated_manufacturer_profile p
  JOIN company c ON c.id = p.company_id
  LEFT JOIN deprecated_company_back b ON b.id = c.id
  WHERE p.deleted_at IS NULL
  ORDER BY p.company_id, p.updated_at DESC
)
SELECT count(*) AS companies_with_live_profile,
       count(*) FILTER (WHERE has_street) AS profile_with_street,
       count(*) FILTER (WHERE has_street AND has_backup AND backup_address IS DISTINCT FROM address) AS street_profile_address_differs_from_backup,
       count(*) FILTER (WHERE NOT has_street AND has_city_state_zip) AS no_street_profile,
       count(*) FILTER (WHERE NOT has_street AND has_city_state_zip AND nullif(btrim(address), '') IS NOT NULL
                          AND city IS NULL AND state IS NULL AND zip_code IS NULL) AS no_street_still_flat,
       count(*) FILTER (WHERE NOT has_street AND has_city_state_zip AND upper(btrim(state)) = 'US') AS no_street_missplit_state_us,
       (SELECT count(*) FROM company x
        WHERE x.type::text = 'MANUFACTURER' AND x.deleted_at IS NULL
          AND nullif(btrim(x.address), '') IS NOT NULL
          AND x.city IS NULL AND x.state IS NULL AND x.zip_code IS NULL) AS live_manufacturers_flat_address
FROM m;
\echo ##### N53_post_phone_backfill [N53]
SELECT c.type::text AS kind,
       count(*) AS backfilled_rows,
       count(*) FILTER (WHERE p.deleted_at IS NOT NULL) AS backfilled_row_deleted_since,
       count(*) FILTER (WHERE c.deleted_at IS NOT NULL) AS company_now_deleted,
       count(*) FILTER (WHERE b.id IS NOT NULL) AS on_pre_existing_company,
       count(*) FILTER (WHERE b.id IS NOT NULL AND EXISTS (
           SELECT 1 FROM company_info_phone_number o
           WHERE o.company_id = c.id AND o.id <> p.id AND o.deleted_at IS NOT NULL)) AS pre_existing_with_other_deleted_rows,
       count(*) FILTER (WHERE p.deleted_at IS NULL AND EXISTS (
           SELECT 1 FROM company_info_phone_number o
           WHERE o.company_id = c.id AND o.id <> p.id AND o.deleted_at IS NULL)) AS now_has_other_live_rows,
       count(*) FILTER (WHERE EXISTS (
           SELECT 1 FROM "order" o
           WHERE o.restaurant_id = c.id AND o.bill_to ->> 'phone' = p.phone_number)) AS used_in_order_bill_to
FROM company_info_phone_number p
JOIN company c ON c.id = p.company_id
LEFT JOIN deprecated_company_back b ON b.id = c.id
WHERE p.id = md5('company.phone_number:' || c.id::text)::uuid
GROUP BY c.type::text
ORDER BY 1
LIMIT 20;
\echo ##### F35_post_invisible_quotations [F35]
SELECT 'quotation' AS tbl, c.type::text AS vendor_type,
       (c.parent_company_id IS NULL) AS vendor_is_top_level,
       (q.deprecated_from_store_id IS NULL) AS had_no_store,
       count(*) FILTER (WHERE q.deleted_at IS NULL) AS live_rows,
       count(*) FILTER (WHERE q.deleted_at IS NOT NULL) AS deleted_rows,
       count(DISTINCT c.id) AS vendor_companies
FROM quotation q
JOIN company c ON c.id = q.vendor_company_id
WHERE c.deleted_at IS NOT NULL
GROUP BY c.type::text, (c.parent_company_id IS NULL), (q.deprecated_from_store_id IS NULL)
UNION ALL
SELECT 'quotation_vendor_client', c.type::text,
       (c.parent_company_id IS NULL),
       (v.deprecated_store_id IS NULL),
       count(*) FILTER (WHERE v.deleted_at IS NULL),
       count(*) FILTER (WHERE v.deleted_at IS NOT NULL),
       count(DISTINCT c.id)
FROM quotation_vendor_client v
JOIN company c ON c.id = v.vendor_company_id
WHERE c.deleted_at IS NOT NULL
GROUP BY c.type::text, (c.parent_company_id IS NULL), (v.deprecated_store_id IS NULL)
ORDER BY 1, 2, 3, 4
LIMIT 20;
\echo ##### F30_post_comment_side [F30]
SELECT CASE
         WHEN a.company_id = o.store_id THEN 'vendor_side:author_in_store'
         WHEN a.company_id = o.restaurant_id THEN 'restaurant_side:author_in_restaurant'
         WHEN a.company_id = st.parent_company_id THEN 'MISJUDGED:author_in_store_parent'
         WHEN a.company_id = rs.parent_company_id THEN 'DROPPED_FROM_LV:author_in_restaurant_parent'
         ELSE 'DROPPED_FROM_LV:author_elsewhere'
       END AS bucket,
       (oc.deprecated_company_member_id IS NOT NULL) AS authored_as_company_member,
       count(*) FILTER (WHERE oc.deleted_at IS NULL) AS live_comments,
       count(*) FILTER (WHERE oc.deleted_at IS NOT NULL) AS deleted_comments
FROM order_comment oc
JOIN system_account a ON a.id = oc.account_id
JOIN "order" o ON o.id = oc.order_id
LEFT JOIN company st ON st.id = o.store_id
LEFT JOIN company rs ON rs.id = o.restaurant_id
GROUP BY 1, 2
ORDER BY 1, 2
LIMIT 20;
\echo ##### F126_post_category [F126]
WITH x AS (
  SELECT 'product' AS kind, p.deleted_at,
         CASE WHEN pc.id IS NULL THEN 'no_category'
              WHEN pc.company_id IS NULL THEN 'GLOBAL_category'
              WHEN pc.company_id = p.company_id AND pc.deleted_at IS NULL THEN 'own_category_ok'
              WHEN pc.company_id = p.company_id THEN 'own_category_deleted'
              ELSE 'other_company_category' END AS outcome
  FROM product p
  LEFT JOIN product_category pc ON pc.id = p.product_category_id
  UNION ALL
  SELECT 'restaurant_product', r.deleted_at,
         CASE WHEN pc.id IS NULL THEN 'no_category'
              WHEN pc.company_id IS NULL THEN 'GLOBAL_category'
              WHEN pc.company_id = r.select_company_id THEN 'selected_store_category'
              WHEN cc.deleted_at IS NOT NULL THEN 'category_of_deleted_company'
              ELSE 'other_company_category' END
  FROM restaurant_product r
  LEFT JOIN product_category pc ON pc.id = r.category_id
  LEFT JOIN company cc ON cc.id = pc.company_id
)
SELECT kind, outcome,
       count(*) FILTER (WHERE deleted_at IS NULL) AS live_rows,
       count(*) FILTER (WHERE deleted_at IS NOT NULL) AS deleted_rows
FROM x
GROUP BY kind, outcome
UNION ALL
SELECT 'remap_backup', table_name, count(*), 0
FROM deprecated_product_category_remap_backup
GROUP BY table_name
ORDER BY 1, 2
LIMIT 20;
\echo ##### N141_N150_post_bill_to [N141、N150]
WITH fc AS (
  SELECT DISTINCT ON (c.client_id) c.client_id, c.name, c.phone_number, c.email
  FROM client_restaurant_contact c
  WHERE c.deleted_at IS NULL
  ORDER BY c.client_id, c.created_at, c.id
),
x AS (
  SELECT
    CASE WHEN cl.restaurant_id IS NULL THEN 'no_restaurant_yet'
         WHEN r.company_status::text IN ('UNREGISTERED', 'UNREGISTERED_WITH_ORDERS') THEN 'linked_unregistered'
         ELSE 'registered' END AS kind,
    (nullif(btrim(cl.bill_to_company_name), '') IS NULL OR nullif(btrim(cl.bill_to_address), '') IS NULL
     OR nullif(btrim(cl.bill_to_city), '') IS NULL OR nullif(btrim(cl.bill_to_state), '') IS NULL
     OR nullif(btrim(cl.bill_to_zip_code), '') IS NULL OR nullif(btrim(cl.bill_to_contact_name), '') IS NULL
     OR nullif(btrim(cl.bill_to_phone), '') IS NULL OR nullif(btrim(cl.bill_to_email), '') IS NULL) AS incomplete,
    (cl.bill_to_company_name IS NULL AND cl.bill_to_address IS NULL AND cl.bill_to_contact_name IS NULL
     AND cl.bill_to_phone IS NULL AND cl.bill_to_email IS NULL) AS bill_to_all_empty,
    (nullif(btrim(cl.bill_to_contact_name), '') IS NULL AND nullif(btrim(cl.bill_to_phone), '') IS NULL
     AND nullif(btrim(cl.bill_to_email), '') IS NULL) AS no_contact,
    ((nullif(btrim(cl.bill_to_phone), '') IS NULL) <> (nullif(btrim(cl.bill_to_email), '') IS NULL)) AS one_of_phone_email,
    (nullif(btrim(cl.bill_to_address), '') IS NOT NULL AND (cl.bill_to_city IS NULL OR cl.bill_to_state IS NULL)) AS address_not_split,
    (cl.bill_to_company_name IS NOT DISTINCT FROM coalesce(nullif(trim(cl.temporary_name), ''), r.name)
     AND cl.bill_to_address IS NOT DISTINCT FROM coalesce(nullif(trim(cl.temporary_address), ''), r.address)
     AND cl.bill_to_city IS NOT DISTINCT FROM coalesce(nullif(trim(cl.temporary_city), ''), r.city)
     AND cl.bill_to_state IS NOT DISTINCT FROM coalesce(nullif(trim(cl.temporary_state), ''), r.state)
     AND cl.bill_to_zip_code IS NOT DISTINCT FROM coalesce(nullif(trim(cl.temporary_zip_code), ''), r.zip_code)) AS company_part_matches,
    (cl.bill_to_contact_name IS NOT DISTINCT FROM fc.name
     AND cl.bill_to_phone IS NOT DISTINCT FROM fc.phone_number
     AND cl.bill_to_email IS NOT DISTINCT FROM fc.email) AS contact_part_matches
  FROM client cl
  LEFT JOIN company r ON r.id = cl.restaurant_id
  LEFT JOIN fc ON fc.client_id = cl.id
  WHERE cl.deleted_at IS NULL
)
SELECT kind,
       count(*) AS live_clients,
       count(*) FILTER (WHERE incomplete) AS bill_to_incomplete,
       count(*) FILTER (WHERE bill_to_all_empty) AS bill_to_all_empty,
       count(*) FILTER (WHERE no_contact) AS no_contact,
       count(*) FILTER (WHERE one_of_phone_email) AS only_one_of_phone_email,
       count(*) FILTER (WHERE address_not_split) AS address_not_split,
       count(*) FILTER (WHERE kind <> 'registered' AND NOT company_part_matches) AS unreg_company_part_diverged,
       count(*) FILTER (WHERE kind <> 'registered' AND NOT contact_part_matches) AS unreg_contact_part_diverged,
       count(*) FILTER (WHERE kind = 'linked_unregistered' AND NOT (company_part_matches AND contact_part_matches)) AS linked_unreg_will_not_refresh
FROM x
GROUP BY kind
ORDER BY kind
LIMIT 20;
\echo ##### post_acct_origin [无独立编号（8c6f5e1a90b1 合并结果）、F17]
WITH src AS (
  SELECT id, 'company_member'::text AS src FROM deprecated_company_member
  UNION ALL SELECT id, 'store_member' FROM deprecated_store_member
  UNION ALL SELECT id, 'restaurant_member' FROM deprecated_restaurant_member
  UNION ALL SELECT id, 'manufacturer_subdivision_member' FROM deprecated_manufacturer_subdivision_member
),
acc AS (
  SELECT a.id, a.deleted_at, a.is_active, c.deleted_at AS company_deleted_at,
         u.deleted_at AS user_deleted_at, u.is_active AS user_active,
         coalesce(s.src,
           CASE WHEN EXISTS (
                  SELECT 1 FROM system_account p JOIN company ch ON ch.id = a.company_id
                  WHERE p.company_id = ch.parent_company_id
                    AND md5(p.id::text || ':' || a.company_id::text)::uuid = a.id)
                THEN '9d18fcda7ab1_copy'
                WHEN c.type::text = 'ADMIN' THEN 'admin_company'
                ELSE 'created_after_upgrade' END) AS origin,
         EXISTS (SELECT 1 FROM system_account_role_m2m r WHERE r.account_id = a.id) AS has_role
  FROM system_account a
  JOIN company c ON c.id = a.company_id
  JOIN "system_user" u ON u.id = a.user_id
  LEFT JOIN src s ON s.id = a.id
)
SELECT coalesce(acc.origin, 'TOTAL') AS account_origin,
  count(*) AS accounts,
  count(*) FILTER (WHERE acc.deleted_at IS NULL) AS live,
  count(*) FILTER (WHERE acc.deleted_at IS NULL AND acc.is_active AND acc.user_deleted_at IS NULL AND acc.user_active AND acc.company_deleted_at IS NULL) AS usable,
  count(*) FILTER (WHERE acc.deleted_at IS NULL AND acc.user_deleted_at IS NOT NULL) AS live_on_deleted_user,
  count(*) FILTER (WHERE acc.deleted_at IS NULL AND acc.company_deleted_at IS NOT NULL) AS live_in_deleted_company,
  count(*) FILTER (WHERE acc.deleted_at IS NULL AND NOT acc.has_role) AS live_without_role
FROM acc
GROUP BY ROLLUP (acc.origin)
ORDER BY acc.origin NULLS LAST
LIMIT 20;
\echo ##### post_members_without_account [无独立编号（8c6f5e1a90b1 合并结果）]
WITH src AS (
  SELECT 'company_member'::text AS src, id, deleted_at FROM deprecated_company_member
  UNION ALL SELECT 'store_member', id, deleted_at FROM deprecated_store_member
  UNION ALL SELECT 'restaurant_member', id, deleted_at FROM deprecated_restaurant_member
  UNION ALL SELECT 'manufacturer_subdivision_member', id, deleted_at FROM deprecated_manufacturer_subdivision_member
)
SELECT s.src AS source_table,
  count(*) AS member_rows,
  count(*) FILTER (WHERE a.id IS NULL) AS without_account,
  count(*) FILTER (WHERE a.id IS NULL AND s.deleted_at IS NULL) AS live_member_without_account,
  count(*) FILTER (WHERE a.id IS NOT NULL AND a.deleted_at IS NULL) AS account_live,
  count(*) FILTER (WHERE a.id IS NOT NULL AND a.deleted_at IS NULL AND c.deleted_at IS NOT NULL) AS live_account_in_deleted_company
FROM src s
LEFT JOIN system_account a ON a.id = s.id
LEFT JOIN company c ON c.id = a.company_id
GROUP BY s.src
ORDER BY s.src
LIMIT 20;
\echo ##### post_F7_chat_member [F7]
SELECT count(*) AS chat_members,
  count(*) FILTER (WHERE cm.deprecated_store_member_id IS NULL AND cm.deprecated_restaurant_member_id IS NULL AND cm.deprecated_company_member_id IS NULL AND cm.created_at < '2026-10-30') AS old_rows_without_member,
  count(*) FILTER (WHERE COALESCE(cm.deprecated_store_member_id, cm.deprecated_restaurant_member_id, cm.deprecated_company_member_id) <> cm.account_id) AS account_differs_from_old_member,
  count(*) FILTER (WHERE cm.deleted_at IS NULL AND a.deleted_at IS NOT NULL) AS live_on_deleted_account,
  count(*) FILTER (WHERE cm.deleted_at IS NULL AND a.deleted_at IS NULL AND c.deleted_at IS NOT NULL) AS live_on_account_in_deleted_company,
  count(*) FILTER (WHERE a.user_id <> cm.user_id) AS chat_user_differs_from_account_user,
  count(DISTINCT cm.chat_id) AS chats,
  count(DISTINCT cm.chat_id) FILTER (WHERE cm.deleted_at IS NULL AND (a.deleted_at IS NOT NULL OR c.deleted_at IS NOT NULL)) AS chats_with_dead_member
FROM chat_member cm
JOIN system_account a ON a.id = cm.account_id
JOIN company c ON c.id = a.company_id;
\echo ##### post_F15_order_comment [F15、F30]
SELECT count(*) AS comments,
  count(*) FILTER (WHERE oc.deprecated_company_member_id IS NULL AND oc.deprecated_restaurant_member_id IS NULL AND oc.deprecated_store_member_id IS NULL AND oc.created_at < '2026-10-30') AS old_rows_without_author,
  count(*) FILTER (WHERE COALESCE(oc.deprecated_company_member_id, oc.deprecated_restaurant_member_id, oc.deprecated_store_member_id) <> oc.account_id) AS author_moved_off_old_member,
  count(*) FILTER (WHERE oc.deprecated_company_member_id IS NOT NULL AND oc.deprecated_store_member_id IS NOT NULL) AS had_company_and_store_author,
  count(*) FILTER (WHERE a.deleted_at IS NOT NULL) AS author_account_deleted,
  count(*) FILTER (WHERE c.deleted_at IS NOT NULL) AS author_company_deleted,
  count(*) FILTER (WHERE oc.updated_by_account_id IS NULL AND COALESCE(oc.deprecated_updated_by_company_member_id, oc.deprecated_updated_by_store_member_id) IS NOT NULL) AS editor_lost
FROM order_comment oc
JOIN system_account a ON a.id = oc.account_id
JOIN company c ON c.id = a.company_id;
\echo ##### post_packing_slip_accounts [无独立编号（a56e6f86e0d7）]
SELECT count(*) AS slips,
  count(*) FILTER (WHERE ps.deprecated_packer_store_member_id IS NOT NULL AND ps.packer_account_id IS NULL) AS packer_lost,
  count(*) FILTER (WHERE ps.deprecated_driver_store_member_id IS NOT NULL AND ps.driver_account_id IS NULL) AS driver_lost,
  count(*) FILTER (WHERE ps.deprecated_approved_by_store_member_id IS NOT NULL AND ps.approved_by_account_id IS NULL) AS approver_lost,
  count(*) FILTER (WHERE COALESCE(ps.deprecated_delivery_approved_by_restaurant_member_id, ps.deprecated_delivery_approved_by_store_member_id) IS NOT NULL AND ps.delivery_approved_by_account_id IS NULL) AS delivery_approver_lost,
  count(*) FILTER (WHERE ps.packer_account_id IS NOT NULL AND pa.deleted_at IS NOT NULL) AS packer_account_deleted,
  count(*) FILTER (WHERE ps.driver_account_id IS NOT NULL AND dr.deleted_at IS NOT NULL) AS driver_account_deleted,
  count(*) FILTER (WHERE ps.packer_account_id IS NOT NULL AND pc.deleted_at IS NOT NULL) AS packer_in_deleted_company
FROM order_packing_slip ps
LEFT JOIN system_account pa ON pa.id = ps.packer_account_id
LEFT JOIN company pc ON pc.id = pa.company_id
LEFT JOIN system_account dr ON dr.id = ps.driver_account_id;
\echo ##### post_N41_companies_without_accounts [N41]
WITH live_acc AS (
  SELECT a.company_id, bool_or(a.is_active AND u.deleted_at IS NULL AND u.is_active) AS usable
  FROM system_account a JOIN "system_user" u ON u.id = a.user_id
  WHERE a.deleted_at IS NULL
  GROUP BY a.company_id
)
SELECT c.type::text AS company_kind,
       c.status::text AS status,
       CASE WHEN c.parent_company_id IS NULL THEN 'top'
            WHEN p.id IS NULL THEN 'branch(parent missing)'
            ELSE 'branch(parent ' || p.status::text || CASE WHEN p.deleted_at IS NULL THEN ',live)' ELSE ',deleted)' END
       END AS level,
       count(*) AS live_companies,
       count(*) FILTER (WHERE la.company_id IS NULL) AS no_live_account,
       count(*) FILTER (WHERE NOT coalesce(la.usable, false)) AS no_usable_account
FROM company c
LEFT JOIN company p ON p.id = c.parent_company_id
LEFT JOIN live_acc la ON la.company_id = c.id
WHERE c.deleted_at IS NULL
GROUP BY 1, 2, 3
ORDER BY 6 DESC, 1, 2, 3
LIMIT 20;
\echo ##### post_N41_invited_parents [N41、N129、N148]
WITH inv AS (
  SELECT c.id, c.user_id FROM company c
  WHERE c.parent_company_id IS NULL AND c.deleted_at IS NULL AND c.status = 'INVITED'
),
live_acc AS (SELECT DISTINCT company_id FROM system_account WHERE deleted_at IS NULL),
br AS (
  SELECT ch.id, ch.parent_company_id FROM company ch
  WHERE ch.deleted_at IS NULL AND ch.parent_company_id IN (SELECT id FROM inv)
)
SELECT
  (SELECT count(*) FROM inv) AS invited_top_companies,
  (SELECT count(*) FROM inv WHERE user_id IS NOT NULL) AS with_owner,
  (SELECT count(*) FROM inv WHERE id IN (SELECT company_id FROM live_acc)) AS with_live_account,
  (SELECT count(DISTINCT parent_company_id) FROM br) AS with_live_branches,
  (SELECT count(*) FROM br) AS live_branches,
  (SELECT count(*) FROM br WHERE id NOT IN (SELECT company_id FROM live_acc)) AS live_branches_without_live_account,
  (SELECT count(*) FROM deprecated_onboarding_company_member o WHERE o.deleted_at IS NULL AND o.company_id IN (SELECT id FROM inv)) AS staged_company_team_void,
  (SELECT count(*) FROM deprecated_onboarding_store_member o JOIN company ch ON ch.id = o.store_id WHERE o.deleted_at IS NULL AND ch.parent_company_id IN (SELECT id FROM inv)) AS staged_store_team_void,
  (SELECT count(*) FROM deprecated_onboarding_restaurant_member o JOIN company ch ON ch.id = o.restaurant_id WHERE o.deleted_at IS NULL AND ch.parent_company_id IN (SELECT id FROM inv)) AS staged_restaurant_team_void,
  (SELECT count(*) FROM deprecated_onboarding_manufacturer_subdivision_member o JOIN company ch ON ch.id = o.manufacturer_subdivision_id WHERE o.deleted_at IS NULL AND ch.parent_company_id IN (SELECT id FROM inv)) AS staged_subdivision_team_void;
