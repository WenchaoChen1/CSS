\echo ##### N129_pre_parents [N129]
WITH kids AS (
    SELECT company_id AS pid, (deleted_at IS NULL) AS live FROM store
    UNION ALL
    SELECT company_id, (deleted_at IS NULL) FROM restaurant WHERE company_id IS NOT NULL
    UNION ALL
    SELECT manufacturer_company_id, (deleted_at IS NULL) FROM manufacturer_subdivision
),
kid_agg AS (
    SELECT pid, count(*) FILTER (WHERE live) AS n_live_kids
    FROM kids
    GROUP BY pid
),
p AS (
    SELECT c.id, c.type::text AS type, c.user_id, c.subscriber_status::text AS sub, c.created_at, k.n_live_kids,
           CASE
               WHEN c.user_id IS NOT NULL
                    AND NOT EXISTS (SELECT 1 FROM company_member m WHERE m.company_id = c.id AND m.user_id = c.user_id)
                   THEN 'INVITED'
               WHEN c.user_id IS NULL
                    AND NOT EXISTS (SELECT 1 FROM company_member m WHERE m.company_id = c.id AND m.deleted_at IS NULL)
                    AND NOT EXISTS (SELECT 1 FROM company_subscription s
                                    WHERE s.company_id = c.id AND s.invitation_code_used_at IS NOT NULL)
                    AND EXISTS (SELECT 1 FROM company_subscription s
                                WHERE s.company_id = c.id AND s.invitation_code IS NOT NULL
                                  AND s.invitation_code_used_at IS NULL)
                   THEN 'INVITED'
               ELSE 'ACTIVE'
           END AS pred_status
    FROM company c
    JOIN kid_agg k ON k.pid = c.id
    WHERE c.deleted_at IS NULL
)
SELECT type, pred_status,
       count(*) AS n_soft_deleted_by_8011,
       count(*) FILTER (WHERE sub = 'ACTIVE') AS n_subscriber_active,
       count(*) FILTER (WHERE sub = 'EXPIRED') AS n_subscriber_expired,
       count(*) FILTER (WHERE user_id IS NOT NULL) AS n_with_owner,
       count(*) FILTER (WHERE n_live_kids = 0) AS n_all_children_deleted,
       count(*) FILTER (WHERE type = 'MANUFACTURER') AS n_restored_by_36cd,
       count(*) FILTER (WHERE type <> 'MANUFACTURER' AND pred_status = 'INVITED' AND user_id IS NOT NULL) AS n_restored_by_8b98,
       count(*) FILTER (WHERE type <> 'MANUFACTURER' AND NOT (pred_status = 'INVITED' AND user_id IS NOT NULL)) AS n_still_deleted_after_upgrade,
       count(*) FILTER (WHERE type IN ('CLIENT', 'VENDOR') AND user_id IS NULL AND created_at >= '2026-09-17') AS n_may_be_hard_deleted_by_c4d8_first
FROM p
GROUP BY type, pred_status
ORDER BY type, pred_status
LIMIT 20;
\echo ##### N129_pre_assets [N129]
WITH kids AS (
    SELECT company_id AS pid, (deleted_at IS NULL) AS live FROM store
    UNION ALL
    SELECT company_id, (deleted_at IS NULL) FROM restaurant WHERE company_id IS NOT NULL
    UNION ALL
    SELECT manufacturer_company_id, (deleted_at IS NULL) FROM manufacturer_subdivision
),
kid_agg AS (
    SELECT pid, count(*) FILTER (WHERE live) AS n_live_kids
    FROM kids
    GROUP BY pid
),
p AS (
    SELECT c.id, c.type::text AS type, c.user_id, k.n_live_kids,
           CASE
               WHEN c.type::text = 'MANUFACTURER' THEN 'restored_by_36cd'
               WHEN c.user_id IS NOT NULL
                    AND NOT EXISTS (SELECT 1 FROM company_member m WHERE m.company_id = c.id AND m.user_id = c.user_id)
                   THEN 'restored_by_8b98'
               ELSE 'stays_deleted'
           END AS fate
    FROM company c
    JOIN kid_agg k ON k.pid = c.id
    WHERE c.deleted_at IS NULL
),
vp AS (
    SELECT vendor_id AS cid, count(*) AS n FROM vendor_product
    WHERE deleted_at IS NULL AND vendor_id IN (SELECT id FROM p)
    GROUP BY vendor_id
),
mp AS (
    SELECT manufacturer_company_id AS cid, count(*) AS n FROM manufacturer_product
    WHERE deleted_at IS NULL AND manufacturer_company_id IN (SELECT id FROM p)
    GROUP BY manufacturer_company_id
),
inv AS (
    SELECT mpr.manufacturer_company_id AS cid, count(*) AS n
    FROM manufacturer_subdivision_product i
    JOIN manufacturer_product mpr ON mpr.id = i.manufacturer_product_id
    WHERE i.deleted_at IS NULL AND mpr.manufacturer_company_id IN (SELECT id FROM p)
    GROUP BY mpr.manufacturer_company_id
),
mi AS (
    SELECT company_id AS cid, count(*) AS n FROM master_invoice
    WHERE deleted_at IS NULL AND store_id IS NULL AND restaurant_id IS NULL AND company_id IN (SELECT id FROM p)
    GROUP BY company_id
),
codes AS (
    SELECT s.company_id AS cid,
           count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM client cl WHERE cl.company_subscription_id = s.id)) AS n_admin,
           count(*) FILTER (WHERE EXISTS (SELECT 1 FROM client cl WHERE cl.company_subscription_id = s.id)) AS n_client_link
    FROM company_subscription s
    JOIN p ON p.id = s.company_id AND p.user_id IS NULL
    WHERE s.deleted_at IS NULL AND s.invitation_code IS NOT NULL AND s.invitation_code_used_at IS NULL
    GROUP BY s.company_id
),
mem AS (
    SELECT company_id AS cid, count(*) AS n FROM company_member
    WHERE deleted_at IS NULL AND company_id IN (SELECT id FROM p)
    GROUP BY company_id
)
SELECT p.type, p.fate,
       count(*) AS n_parents,
       count(*) FILTER (WHERE p.n_live_kids = 0) AS n_parents_no_live_child,
       count(vp.cid) AS n_parents_with_vendor_product,
       coalesce(sum(vp.n), 0) AS n_vendor_product,
       count(mp.cid) AS n_parents_with_catalog,
       coalesce(sum(mp.n), 0) AS n_manufacturer_product,
       count(inv.cid) AS n_parents_with_inventory,
       coalesce(sum(inv.n), 0) AS n_inventory_rows,
       count(mi.cid) AS n_parents_with_own_master_invoice,
       coalesce(sum(mi.n), 0) AS n_own_master_invoice,
       count(*) FILTER (WHERE codes.n_admin > 0) AS n_parents_with_open_admin_code,
       coalesce(sum(codes.n_admin), 0) AS n_open_admin_code,
       coalesce(sum(codes.n_client_link), 0) AS n_open_client_link_code,
       coalesce(sum(mem.n), 0) AS n_live_member_accounts
FROM p
LEFT JOIN vp ON vp.cid = p.id
LEFT JOIN mp ON mp.cid = p.id
LEFT JOIN inv ON inv.cid = p.id
LEFT JOIN mi ON mi.cid = p.id
LEFT JOIN codes ON codes.cid = p.id
LEFT JOIN mem ON mem.cid = p.id
GROUP BY p.type, p.fate
ORDER BY p.type, p.fate
LIMIT 20;
\echo ##### N129_pre_users [N129]
WITH kids AS (
    SELECT company_id AS pid, (deleted_at IS NULL) AS live FROM store
    UNION ALL
    SELECT company_id, (deleted_at IS NULL) FROM restaurant WHERE company_id IS NOT NULL
    UNION ALL
    SELECT manufacturer_company_id, (deleted_at IS NULL) FROM manufacturer_subdivision
),
kid_agg AS (
    SELECT pid, count(*) FILTER (WHERE live) AS n_live_kids
    FROM kids
    GROUP BY pid
),
p AS (
    SELECT c.id, c.type::text AS type, k.n_live_kids,
           CASE
               WHEN c.type::text = 'MANUFACTURER' THEN 'restored_by_36cd'
               WHEN c.user_id IS NOT NULL
                    AND NOT EXISTS (SELECT 1 FROM company_member m WHERE m.company_id = c.id AND m.user_id = c.user_id)
                   THEN 'restored_by_8b98'
               ELSE 'stays_deleted'
           END AS fate
    FROM company c
    JOIN kid_agg k ON k.pid = c.id
    WHERE c.deleted_at IS NULL
),
dead AS (
    SELECT id FROM p WHERE fate = 'stays_deleted' AND n_live_kids = 0
),
u AS (
    SELECT DISTINCT p.type, m.user_id
    FROM company_member m
    JOIN p ON p.id = m.company_id AND p.fate = 'stays_deleted'
    JOIN "user" usr ON usr.id = m.user_id AND usr.deleted_at IS NULL
    WHERE m.deleted_at IS NULL
)
SELECT u.type,
       count(*) AS n_users_with_live_account_in_stays_deleted_parent,
       count(*) FILTER (WHERE
           NOT EXISTS (SELECT 1 FROM company_member m2 JOIN company c2 ON c2.id = m2.company_id
                       WHERE m2.user_id = u.user_id AND m2.deleted_at IS NULL AND c2.deleted_at IS NULL
                         AND c2.id NOT IN (SELECT id FROM dead))
           AND NOT EXISTS (SELECT 1 FROM store_member sm JOIN store st ON st.id = sm.store_id
                           WHERE sm.user_id = u.user_id AND sm.deleted_at IS NULL AND st.deleted_at IS NULL)
           AND NOT EXISTS (SELECT 1 FROM restaurant_member rm JOIN restaurant r ON r.id = rm.restaurant_id
                           WHERE rm.user_id = u.user_id AND rm.deleted_at IS NULL AND r.deleted_at IS NULL)
           AND NOT EXISTS (SELECT 1 FROM manufacturer_subdivision_member mm
                           JOIN manufacturer_subdivision ms ON ms.id = mm.manufacturer_subdivision_id
                           WHERE mm.user_id = u.user_id AND mm.deleted_at IS NULL AND ms.deleted_at IS NULL)
       ) AS n_users_left_without_usable_account
FROM u
GROUP BY u.type
ORDER BY u.type
LIMIT 20;
\echo ##### N148_pre_restored [N148,F4]
WITH kids AS (
    SELECT company_id AS pid, (deleted_at IS NULL) AS live FROM store
    UNION ALL
    SELECT company_id, (deleted_at IS NULL) FROM restaurant WHERE company_id IS NOT NULL
    UNION ALL
    SELECT manufacturer_company_id, (deleted_at IS NULL) FROM manufacturer_subdivision
),
kid_agg AS (
    SELECT pid, count(*) FILTER (WHERE live) AS n_live_kids
    FROM kids
    GROUP BY pid
),
r AS (
    SELECT c.id, c.type::text AS type, c.deleted_at, c.subscriber_status::text AS sub, c.user_id, k.n_live_kids
    FROM company c
    JOIN kid_agg k ON k.pid = c.id
    WHERE c.type::text <> 'MANUFACTURER'
      AND c.user_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM company_member m WHERE m.company_id = c.id AND m.user_id = c.user_id)
),
aud AS (
    SELECT a.company_id,
           bool_or(lower(a.entity_type) = 'company' AND lower(a.action) LIKE '%delet%') AS has_del,
           bool_or(lower(a.action) LIKE '%merg%') AS has_merge
    FROM company_audit_log a
    WHERE a.company_id IN (SELECT id FROM r)
    GROUP BY a.company_id
)
SELECT r.type,
       CASE WHEN r.deleted_at IS NULL THEN 'live_now_deleted_by_8011' ELSE 'already_deleted_now' END AS source,
       count(*) AS n_restored_by_8b98,
       count(*) FILTER (WHERE coalesce(a.has_del, false)) AS n_with_audit_deleted,
       count(*) FILTER (WHERE coalesce(a.has_merge, false)) AS n_with_audit_merged,
       count(*) FILTER (WHERE r.n_live_kids > 0) AS n_with_live_child_copy,
       count(*) FILTER (WHERE r.sub = 'ACTIVE') AS n_subscriber_active,
       count(*) FILTER (WHERE u.deleted_at IS NULL) AS n_owner_user_live,
       min(r.deleted_at)::date AS min_deleted_date,
       max(r.deleted_at)::date AS max_deleted_date
FROM r
LEFT JOIN aud a ON a.company_id = r.id
LEFT JOIN "user" u ON u.id = r.user_id
GROUP BY 1, 2
ORDER BY 1, 2
LIMIT 20;
\echo ##### N133_pre_revived [N133]
WITH m AS (
    SELECT c.id, c.parent_company_id, c.deleted_at, c.user_id, c.name
    FROM company c
    WHERE c.type::text = 'MANUFACTURER' AND c.deleted_at IS NOT NULL
),
aud AS (
    SELECT a.company_id,
           bool_or(lower(a.entity_type) = 'company' AND lower(a.action) LIKE '%delet%') AS has_del,
           bool_or(lower(a.action) LIKE '%merg%') AS has_merge
    FROM company_audit_log a
    WHERE a.company_id IN (SELECT id FROM m)
    GROUP BY a.company_id
)
SELECT (m.parent_company_id IS NOT NULL) AS has_parent_now,
       coalesce(a.has_del, false) AS audit_deleted,
       coalesce(a.has_merge, false) AS audit_merged,
       count(*) AS n_revived_by_36cd,
       count(*) FILTER (WHERE m.user_id IS NOT NULL) AS n_with_owner,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM company_member cm WHERE cm.company_id = m.id AND cm.deleted_at IS NULL)) AS n_with_live_member,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM manufacturer_product mp WHERE mp.manufacturer_company_id = m.id AND mp.deleted_at IS NULL)) AS n_with_live_catalog,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM manufacturer_subdivision s WHERE s.manufacturer_company_id = m.id AND s.deleted_at IS NULL)) AS n_with_live_subdivision,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM company l
                                      WHERE l.type::text = 'MANUFACTURER' AND l.deleted_at IS NULL AND l.id <> m.id
                                        AND lower(btrim(l.name)) = lower(btrim(m.name)))) AS n_same_name_as_live_manufacturer,
       min(m.deleted_at)::date AS min_deleted_date,
       max(m.deleted_at)::date AS max_deleted_date,
       (SELECT count(*) FROM company x WHERE x.type::text = 'MANUFACTURER' AND x.deleted_at IS NULL) AS n_live_manufacturers_now
FROM m
LEFT JOIN aud a ON a.company_id = m.id
GROUP BY 1, 2, 3
ORDER BY 4 DESC
LIMIT 20;
\echo ##### F4_pre_mfr_default [F4]
WITH sub AS (
    SELECT manufacturer_company_id AS cid,
           count(*) FILTER (WHERE deleted_at IS NULL) AS n_live,
           count(*) FILTER (WHERE deleted_at IS NULL AND is_default) AS n_live_default
    FROM manufacturer_subdivision
    GROUP BY manufacturer_company_id
)
SELECT (c.deleted_at IS NOT NULL) AS deleted_now_revived_by_36cd,
       count(*) AS n_manufacturers_live_after_upgrade,
       count(*) FILTER (WHERE s.n_live_default > 0) AS n_with_live_default_copy,
       count(*) FILTER (WHERE s.n_live > 0) AS n_with_any_live_subdivision_copy,
       coalesce(sum(s.n_live), 0) AS n_live_subdivision_copies,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM store st WHERE st.company_id = c.id AND st.deleted_at IS NULL)) AS n_with_live_store_copy
FROM company c
LEFT JOIN sub s ON s.cid = c.id
WHERE c.type::text = 'MANUFACTURER'
GROUP BY 1
ORDER BY 1
LIMIT 20;
\echo ##### F3_pre_hierarchy [F3]
SELECT c.type::text AS child_type,
       p.type::text AS parent_type,
       (c.deleted_at IS NOT NULL) AS child_deleted,
       (p.deleted_at IS NOT NULL) AS parent_deleted,
       count(*) AS n_links_cleared_by_d8aa,
       count(DISTINCT c.parent_company_id) AS n_distinct_parents,
       count(*) FILTER (WHERE c.subscriber_status::text = 'ACTIVE') AS n_children_subscriber_active,
       count(*) FILTER (WHERE c.user_id IS NOT NULL) AS n_children_with_owner,
       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM company g WHERE g.parent_company_id = c.id)) AS n_children_also_parent,
       count(DISTINCT c.parent_company_id) FILTER (
           WHERE p.deleted_at IS NULL
             AND (EXISTS (SELECT 1 FROM store s WHERE s.company_id = p.id)
                  OR EXISTS (SELECT 1 FROM restaurant r WHERE r.company_id = p.id)
                  OR EXISTS (SELECT 1 FROM manufacturer_subdivision ms WHERE ms.manufacturer_company_id = p.id))
       ) AS n_parents_also_soft_deleted_by_8011
FROM company c
LEFT JOIN company p ON p.id = c.parent_company_id
WHERE c.parent_company_id IS NOT NULL
GROUP BY 1, 2, 3, 4
ORDER BY 5 DESC
LIMIT 20;
\echo ##### N97_doomed_summary [N97]
WITH cand AS (
  -- d8aaccb9a900:56 clears parent_company_id of every existing company; d5a1c9e3f7b4:27 overwrites address from manufacturer_profile
  SELECT c.id, c.id AS link_id, c.type::text AS type, c.name, coalesce(mp.address, c.address) AS address,
         c.created_at, c.deleted_at, c.user_id, NULL::text AS company_status, false AS from_restaurant
  FROM company c
  LEFT JOIN LATERAL (
    SELECT trim(p.address) AS address FROM manufacturer_profile p
    WHERE p.company_id = c.id AND p.deleted_at IS NULL AND coalesce(trim(p.address), '') <> ''
      AND coalesce(length(trim(p.address)), 0) <= 255 AND coalesce(length(trim(p.city)), 0) <= 100
      AND coalesce(length(trim(p.state)), 0) <= 100 AND coalesce(length(trim(p.zip_code)), 0) <= 10
    LIMIT 1
  ) mp ON true
  WHERE c.type::text IN ('CLIENT', 'VENDOR')
  UNION ALL
  -- b7d82c2e651b:116: a restaurant without company_id becomes a top-level CLIENT company; its id is random (link_id NULL) when a company or a store copied just before already has it
  SELECT r.id, CASE WHEN EXISTS (SELECT 1 FROM company c0 WHERE c0.id = r.id)
                      OR EXISTS (SELECT 1 FROM store s0 WHERE s0.id = r.id) THEN NULL ELSE r.id END,
         'CLIENT', r.name, r.address, r.created_at, r.deleted_at, NULL::uuid, r.status::text, true
  FROM restaurant r WHERE r.company_id IS NULL
),
base AS (
  SELECT k.*,
         lower(regexp_replace(btrim(coalesce(k.name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(k.address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM cand k
  WHERE k.deleted_at IS NULL AND k.created_at >= '2026-09-17' AND k.user_id IS NULL
    AND coalesce(k.company_status, '') NOT IN ('UNREGISTERED', 'UNREGISTERED_WITH_ORDERS')
    AND NOT EXISTS (SELECT 1 FROM company_audit_log a
                    WHERE a.company_id = k.link_id AND a.action::text = 'created'
                      AND a.entity_type::text IN ('company', 'subscription')
                      AND abs(extract(epoch FROM a.created_at - k.created_at)) < 120)
    AND NOT EXISTS (SELECT 1 FROM company_subscription s
                    WHERE s.company_id = k.link_id AND s.invitation_code_used_at IS NOT NULL)
),
v_tmp AS (
  SELECT DISTINCT lower(regexp_replace(btrim(coalesce(temporary_name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(temporary_address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM client WHERE store_id IS NOT NULL
),
r_tmp AS (
  SELECT DISTINCT lower(regexp_replace(btrim(coalesce(name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM client_temporary_store
),
flagged AS (
  SELECT b.*,
    (b.type = 'CLIENT' AND EXISTS (SELECT 1 FROM client cl JOIN company_subscription s ON s.id = cl.company_subscription_id
                                   WHERE s.company_id = b.link_id)) AS r_client_link,
    (b.type = 'CLIENT' AND b.nm <> '' AND b.street <> ''
       AND EXISTS (SELECT 1 FROM v_tmp v WHERE v.nm = b.nm AND v.street = b.street)) AS r_client_tmp,
    (b.type = 'VENDOR' AND b.nm = '') AS r_vendor_noname,
    (b.type = 'VENDOR' AND b.nm <> '' AND b.street <> ''
       AND EXISTS (SELECT 1 FROM r_tmp r WHERE r.nm = b.nm AND r.street = b.street)) AS r_vendor_tmp
  FROM base b
),
doomed AS (
  SELECT f.* FROM flagged f WHERE f.r_client_link OR f.r_client_tmp OR f.r_vendor_noname OR f.r_vendor_tmp
),
x AS (
  SELECT d.*,
    EXISTS (SELECT 1 FROM company_subscription s WHERE s.company_id = d.link_id) AS has_sub,
    EXISTS (SELECT 1 FROM company_subscription s WHERE s.company_id = d.link_id AND s.invitation_code IS NOT NULL) AS has_code,
    EXISTS (SELECT 1 FROM company_subscription s WHERE s.company_id = d.link_id AND s.invitation_code IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM client cl WHERE cl.company_subscription_id = s.id)) AS code_lost,
    EXISTS (SELECT 1 FROM company_subscription s WHERE s.company_id = d.link_id AND s.invitation_code IS NOT NULL
              AND s.invitation_code_sent_at IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM client cl WHERE cl.company_subscription_id = s.id)) AS code_lost_sent,
    (EXISTS (SELECT 1 FROM company_member m WHERE m.company_id = d.link_id AND m.deleted_at IS NULL)
     OR EXISTS (SELECT 1 FROM restaurant_member m WHERE m.restaurant_id = d.link_id AND m.deleted_at IS NULL)
     OR EXISTS (SELECT 1 FROM store_member m WHERE m.store_id = d.link_id AND m.deleted_at IS NULL)
     OR EXISTS (SELECT 1 FROM manufacturer_subdivision_member m
                WHERE m.manufacturer_subdivision_id = d.link_id AND m.deleted_at IS NULL)) AS has_live_account
  FROM doomed d
),
y AS (
  -- d6b0f4a8c2e5:50-67: doomed rows never hold a used code, so INVITED = has a code and no live account, else ACTIVE
  SELECT x.*, CASE WHEN x.has_code AND NOT x.has_live_account THEN 'INVITED' ELSE 'ACTIVE' END AS status_sim
  FROM x
)
SELECT (SELECT count(*) FROM base) AS candidates_after_base_filter,
       count(*) AS doomed_total,
       count(*) FILTER (WHERE type = 'CLIENT') AS doomed_client,
       count(*) FILTER (WHERE type = 'VENDOR') AS doomed_vendor,
       count(*) FILTER (WHERE from_restaurant) AS doomed_from_restaurant_copy,
       count(*) FILTER (WHERE link_id IS NULL) AS doomed_id_collided_copy,
       count(*) FILTER (WHERE r_client_link) AS rule_client_link,
       count(*) FILTER (WHERE r_client_tmp) AS rule_client_name_street,
       count(*) FILTER (WHERE r_vendor_noname) AS rule_vendor_no_name,
       count(*) FILTER (WHERE r_vendor_tmp) AS rule_vendor_name_street,
       count(*) FILTER (WHERE status_sim = 'INVITED') AS status_invited,
       count(*) FILTER (WHERE status_sim = 'ACTIVE') AS status_active,
       count(*) FILTER (WHERE has_live_account) AS with_live_account,
       count(*) FILTER (WHERE has_sub) AS with_subscription,
       count(*) FILTER (WHERE has_code) AS with_invitation_code,
       count(*) FILTER (WHERE code_lost) AS code_not_moved_to_company_invitation,
       count(*) FILTER (WHERE code_lost_sent) AS code_not_moved_already_sent,
       min(created_at)::date AS first_created,
       max(created_at)::date AS last_created
FROM y;
\echo ##### N97_doomed_list [N97]
WITH cand AS (
  SELECT c.id, c.id AS link_id, c.type::text AS type, c.name, coalesce(mp.address, c.address) AS address,
         c.created_at, c.deleted_at, c.user_id, NULL::text AS company_status, false AS from_restaurant
  FROM company c
  LEFT JOIN LATERAL (
    SELECT trim(p.address) AS address FROM manufacturer_profile p
    WHERE p.company_id = c.id AND p.deleted_at IS NULL AND coalesce(trim(p.address), '') <> ''
      AND coalesce(length(trim(p.address)), 0) <= 255 AND coalesce(length(trim(p.city)), 0) <= 100
      AND coalesce(length(trim(p.state)), 0) <= 100 AND coalesce(length(trim(p.zip_code)), 0) <= 10
    LIMIT 1
  ) mp ON true
  WHERE c.type::text IN ('CLIENT', 'VENDOR')
  UNION ALL
  SELECT r.id, CASE WHEN EXISTS (SELECT 1 FROM company c0 WHERE c0.id = r.id)
                      OR EXISTS (SELECT 1 FROM store s0 WHERE s0.id = r.id) THEN NULL ELSE r.id END,
         'CLIENT', r.name, r.address, r.created_at, r.deleted_at, NULL::uuid, r.status::text, true
  FROM restaurant r WHERE r.company_id IS NULL
),
base AS (
  SELECT k.*,
         lower(regexp_replace(btrim(coalesce(k.name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(k.address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM cand k
  WHERE k.deleted_at IS NULL AND k.created_at >= '2026-09-17' AND k.user_id IS NULL
    AND coalesce(k.company_status, '') NOT IN ('UNREGISTERED', 'UNREGISTERED_WITH_ORDERS')
    AND NOT EXISTS (SELECT 1 FROM company_audit_log a
                    WHERE a.company_id = k.link_id AND a.action::text = 'created'
                      AND a.entity_type::text IN ('company', 'subscription')
                      AND abs(extract(epoch FROM a.created_at - k.created_at)) < 120)
    AND NOT EXISTS (SELECT 1 FROM company_subscription s
                    WHERE s.company_id = k.link_id AND s.invitation_code_used_at IS NOT NULL)
),
v_tmp AS (
  SELECT DISTINCT lower(regexp_replace(btrim(coalesce(temporary_name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(temporary_address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM client WHERE store_id IS NOT NULL
),
r_tmp AS (
  SELECT DISTINCT lower(regexp_replace(btrim(coalesce(name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM client_temporary_store
),
flagged AS (
  SELECT b.*,
    (b.type = 'CLIENT' AND EXISTS (SELECT 1 FROM client cl JOIN company_subscription s ON s.id = cl.company_subscription_id
                                   WHERE s.company_id = b.link_id)) AS r_client_link,
    (b.type = 'CLIENT' AND b.nm <> '' AND b.street <> ''
       AND EXISTS (SELECT 1 FROM v_tmp v WHERE v.nm = b.nm AND v.street = b.street)) AS r_client_tmp,
    (b.type = 'VENDOR' AND b.nm = '') AS r_vendor_noname,
    (b.type = 'VENDOR' AND b.nm <> '' AND b.street <> ''
       AND EXISTS (SELECT 1 FROM r_tmp r WHERE r.nm = b.nm AND r.street = b.street)) AS r_vendor_tmp
  FROM base b
),
doomed AS (
  SELECT f.* FROM flagged f WHERE f.r_client_link OR f.r_client_tmp OR f.r_vendor_noname OR f.r_vendor_tmp
),
x AS (
  SELECT d.*,
    EXISTS (SELECT 1 FROM company_subscription s WHERE s.company_id = d.link_id) AS has_sub,
    EXISTS (SELECT 1 FROM company_subscription s WHERE s.company_id = d.link_id AND s.invitation_code IS NOT NULL) AS has_code,
    EXISTS (SELECT 1 FROM company_subscription s WHERE s.company_id = d.link_id AND s.invitation_code IS NOT NULL
              AND NOT EXISTS (SELECT 1 FROM client cl WHERE cl.company_subscription_id = s.id)) AS code_lost,
    (EXISTS (SELECT 1 FROM company_member m WHERE m.company_id = d.link_id AND m.deleted_at IS NULL)
     OR EXISTS (SELECT 1 FROM restaurant_member m WHERE m.restaurant_id = d.link_id AND m.deleted_at IS NULL)
     OR EXISTS (SELECT 1 FROM store_member m WHERE m.store_id = d.link_id AND m.deleted_at IS NULL)
     OR EXISTS (SELECT 1 FROM manufacturer_subdivision_member m
                WHERE m.manufacturer_subdivision_id = d.link_id AND m.deleted_at IS NULL)) AS has_live_account
  FROM doomed d
),
y AS (
  SELECT x.*, CASE WHEN x.has_code AND NOT x.has_live_account THEN 'INVITED' ELSE 'ACTIVE' END AS status_sim
  FROM x
)
SELECT id, (link_id IS NULL) AS id_collided, type, status_sim, created_at::date AS created,
       r_client_link, r_client_tmp, r_vendor_noname, r_vendor_tmp,
       from_restaurant, has_live_account, has_sub, code_lost
FROM y
ORDER BY (status_sim = 'ACTIVE') DESC, has_live_account DESC, created_at
LIMIT 20;
\echo ##### N97_blast [N97,F50]
WITH cand AS (
  SELECT c.id, c.id AS link_id, c.type::text AS type, c.name, coalesce(mp.address, c.address) AS address,
         c.created_at, c.deleted_at, c.user_id, NULL::text AS company_status, false AS from_restaurant
  FROM company c
  LEFT JOIN LATERAL (
    SELECT trim(p.address) AS address FROM manufacturer_profile p
    WHERE p.company_id = c.id AND p.deleted_at IS NULL AND coalesce(trim(p.address), '') <> ''
      AND coalesce(length(trim(p.address)), 0) <= 255 AND coalesce(length(trim(p.city)), 0) <= 100
      AND coalesce(length(trim(p.state)), 0) <= 100 AND coalesce(length(trim(p.zip_code)), 0) <= 10
    LIMIT 1
  ) mp ON true
  WHERE c.type::text IN ('CLIENT', 'VENDOR')
  UNION ALL
  SELECT r.id, CASE WHEN EXISTS (SELECT 1 FROM company c0 WHERE c0.id = r.id)
                      OR EXISTS (SELECT 1 FROM store s0 WHERE s0.id = r.id) THEN NULL ELSE r.id END,
         'CLIENT', r.name, r.address, r.created_at, r.deleted_at, NULL::uuid, r.status::text, true
  FROM restaurant r WHERE r.company_id IS NULL
),
base AS (
  SELECT k.*,
         lower(regexp_replace(btrim(coalesce(k.name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(k.address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM cand k
  WHERE k.deleted_at IS NULL AND k.created_at >= '2026-09-17' AND k.user_id IS NULL
    AND coalesce(k.company_status, '') NOT IN ('UNREGISTERED', 'UNREGISTERED_WITH_ORDERS')
    AND NOT EXISTS (SELECT 1 FROM company_audit_log a
                    WHERE a.company_id = k.link_id AND a.action::text = 'created'
                      AND a.entity_type::text IN ('company', 'subscription')
                      AND abs(extract(epoch FROM a.created_at - k.created_at)) < 120)
    AND NOT EXISTS (SELECT 1 FROM company_subscription s
                    WHERE s.company_id = k.link_id AND s.invitation_code_used_at IS NOT NULL)
),
v_tmp AS (
  SELECT DISTINCT lower(regexp_replace(btrim(coalesce(temporary_name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(temporary_address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM client WHERE store_id IS NOT NULL
),
r_tmp AS (
  SELECT DISTINCT lower(regexp_replace(btrim(coalesce(name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM client_temporary_store
),
flagged AS (
  SELECT b.*,
    (b.type = 'CLIENT' AND EXISTS (SELECT 1 FROM client cl JOIN company_subscription s ON s.id = cl.company_subscription_id
                                   WHERE s.company_id = b.link_id)) AS r_client_link,
    (b.type = 'CLIENT' AND b.nm <> '' AND b.street <> ''
       AND EXISTS (SELECT 1 FROM v_tmp v WHERE v.nm = b.nm AND v.street = b.street)) AS r_client_tmp,
    (b.type = 'VENDOR' AND b.nm = '') AS r_vendor_noname,
    (b.type = 'VENDOR' AND b.nm <> '' AND b.street <> ''
       AND EXISTS (SELECT 1 FROM r_tmp r WHERE r.nm = b.nm AND r.street = b.street)) AS r_vendor_tmp
  FROM base b
),
doomed AS (
  SELECT f.* FROM flagged f WHERE f.r_client_link OR f.r_client_tmp OR f.r_vendor_noname OR f.r_vendor_tmp
)
SELECT
  (SELECT count(*) FROM doomed) AS doomed_total,
  (SELECT count(*) FROM company_subscription s JOIN doomed d ON d.link_id = s.company_id) AS subscriptions_cascade_deleted,
  (SELECT count(*) FROM company_subscription s JOIN doomed d ON d.link_id = s.company_id
    WHERE coalesce(s.paid_amount, 0) <> 0 OR coalesce(s.license_fee, 0) <> 0) AS paid_subscriptions_cascade_deleted,
  (SELECT count(*) FROM company_subscription s JOIN doomed d ON d.link_id = s.company_id
    WHERE s.invitation_code IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM client cl WHERE cl.company_subscription_id = s.id)) AS invitation_codes_lost,
  (SELECT count(*) FROM company_subscription s JOIN doomed d ON d.link_id = s.company_id
    WHERE s.invitation_code IS NOT NULL
      AND EXISTS (SELECT 1 FROM client cl WHERE cl.company_subscription_id = s.id)) AS codes_moved_with_null_company,
  (SELECT count(*) FROM company_audit_log a JOIN doomed d ON d.link_id = a.company_id) AS company_audit_rows_cascade_deleted,
  (SELECT count(*) FROM chat_party p JOIN doomed d ON d.link_id = coalesce(p.store_id, p.restaurant_id, p.company_id)) AS chat_party_cascade_deleted,
  (SELECT count(*) FROM (
      SELECT company_id AS business_id FROM company_member
      UNION ALL SELECT restaurant_id FROM restaurant_member
      UNION ALL SELECT store_id FROM store_member
      UNION ALL SELECT manufacturer_subdivision_id FROM manufacturer_subdivision_member) m
    JOIN doomed d ON d.link_id = m.business_id) AS accounts_left_orphaned,
  (SELECT count(*) FROM store st JOIN doomed d ON d.link_id = st.company_id)
    + (SELECT count(*) FROM restaurant r JOIN doomed d ON d.link_id = r.company_id) AS branches_losing_parent,
  (SELECT count(*) FROM manufacturer_subdivision ms JOIN doomed d ON d.link_id = ms.manufacturer_company_id) AS subdivisions_losing_parent,
  (SELECT count(*) FROM client cl JOIN doomed d ON d.link_id IN (cl.restaurant_id, cl.store_id)) AS client_links_set_null,
  (SELECT count(*) FROM "order" o JOIN doomed d ON d.link_id IN (o.restaurant_id, o.store_id)) AS order_links_set_null,
  (SELECT count(*) FROM quotation q JOIN doomed d ON d.link_id = q.restaurant_id) AS quotation_restaurant_set_null,
  (SELECT count(*) FROM master_invoice m JOIN doomed d
     ON d.link_id = coalesce(m.store_id, m.restaurant_id, m.company_id)) AS master_invoice_restrict_blocks_delete,
  (SELECT count(*) FROM quotation q JOIN doomed d
     ON d.link_id = coalesce(q.from_store_id, q.vendor_company_id)) AS quotation_vendor_restrict_blocks_delete,
  (SELECT count(*) FROM quotation_vendor_client v JOIN doomed d
     ON d.link_id = coalesce(v.store_id, v.vendor_company_id)) AS quotation_vendor_client_vendor_on_doomed,
  (SELECT count(*) FROM quotation_vendor_client v JOIN doomed d ON d.link_id = v.restaurant_id) AS quotation_vendor_client_restaurant_on_doomed,
  (SELECT count(*) FROM company_subscription s JOIN company c ON c.id = s.company_id
    WHERE s.invitation_code IS NOT NULL
      AND (length(s.invitation_code) > 50 OR length(c.name) > 255 OR length(c.email) > 254
           OR length(c.address) > 255 OR length(c.phone_number) > 64)) AS invitation_rows_overlong,
  (SELECT count(*) FROM (
     SELECT s.invitation_code FROM company_subscription s
     LEFT JOIN client cl ON cl.company_subscription_id = s.id
     WHERE s.invitation_code IS NOT NULL
       AND (cl.id IS NOT NULL OR NOT EXISTS (SELECT 1 FROM doomed d WHERE d.link_id = s.company_id))
     GROUP BY s.invitation_code HAVING count(*) > 1) x) AS invitation_codes_duplicated;
\echo ##### N97_fk_restrict_uat [N97]
SELECT count(*) AS restrict_fk_to_company,
       string_agg(con.conrelid::regclass::text || '.' || a.attname || ' ' || con.confdeltype::text, ', '
                  ORDER BY con.conrelid::regclass::text, a.attname) AS fk_list
FROM pg_constraint con
JOIN pg_attribute a ON a.attrelid = con.conrelid AND a.attnum = con.conkey[1]
WHERE con.contype = 'f'
  AND con.confrelid = 'public.company'::regclass
  AND con.confdeltype IN ('a', 'r');
\echo ##### F7_direct [F7]
WITH seed AS (
  SELECT cm.id, cm.chat_id, cm.deleted_at, cm.created_at FROM chat_member cm
  WHERE cm.store_member_id IS NULL AND cm.restaurant_member_id IS NULL AND cm.company_member_id IS NULL
),
msg AS (
  SELECT m.id, m.chat_id FROM chat_message m JOIN seed s ON s.id = m.chat_member_id
)
SELECT (SELECT count(*) FROM seed) AS orphan_chat_members,
       (SELECT count(*) FROM seed WHERE deleted_at IS NULL) AS orphan_members_not_soft_deleted,
       (SELECT count(DISTINCT chat_id) FROM seed) AS chats_with_orphan_members,
       (SELECT min(created_at)::date FROM seed) AS first_orphan_created,
       (SELECT max(created_at)::date FROM seed) AS last_orphan_created,
       (SELECT count(*) FROM msg) AS direct_messages_deleted,
       (SELECT count(DISTINCT chat_id) FROM msg) AS chats_losing_messages,
       (SELECT count(*) FROM chat_message_attachment a JOIN msg ON msg.id = a.chat_message_id) AS direct_attachments_deleted,
       (SELECT count(*) FROM chat_member cm JOIN msg ON msg.id = cm.last_read_message_id
         WHERE NOT EXISTS (SELECT 1 FROM seed s WHERE s.id = cm.id)) AS normal_members_cascaded_via_last_read,
       (SELECT count(*) FROM chat_message f JOIN msg ON msg.id = f.forwarded_message_id
         WHERE NOT EXISTS (SELECT 1 FROM msg m2 WHERE m2.id = f.id)) AS forwarded_messages_cascaded,
       (SELECT count(*) FROM (
          SELECT cm.chat_id, coalesce(cm.store_member_id, cm.restaurant_member_id, cm.company_member_id) AS account_id
          FROM chat_member cm
          WHERE NOT (cm.store_member_id IS NULL AND cm.restaurant_member_id IS NULL AND cm.company_member_id IS NULL)
          GROUP BY 1, 2 HAVING count(*) > 1) d) AS uq_chat_account_conflicts;
\echo ##### F7_cascade [F7]
WITH RECURSIVE edges AS MATERIALIZED (
  SELECT 'member'::text AS src_kind, m.chat_member_id AS src, 'message'::text AS dst_kind, m.id AS dst
  FROM chat_message m
  UNION ALL
  SELECT 'message', m.forwarded_message_id, 'message', m.id
  FROM chat_message m WHERE m.forwarded_message_id IS NOT NULL
  UNION ALL
  SELECT 'message', cm.last_read_message_id, 'member', cm.id
  FROM chat_member cm WHERE cm.last_read_message_id IS NOT NULL
),
gone(kind, id) AS (
  SELECT 'member'::text, cm.id
  FROM chat_member cm
  WHERE cm.store_member_id IS NULL AND cm.restaurant_member_id IS NULL AND cm.company_member_id IS NULL
  UNION
  SELECT e.dst_kind, e.dst
  FROM gone g JOIN edges e ON e.src_kind = g.kind AND e.src = g.id
)
SELECT count(*) FILTER (WHERE g.kind = 'member') AS members_deleted_total,
       count(*) FILTER (WHERE g.kind = 'member' AND cm.store_member_id IS NULL
                          AND cm.restaurant_member_id IS NULL AND cm.company_member_id IS NULL) AS orphan_seed_members,
       count(*) FILTER (WHERE g.kind = 'member' AND NOT (cm.store_member_id IS NULL
                          AND cm.restaurant_member_id IS NULL AND cm.company_member_id IS NULL)) AS normal_members_cascaded,
       count(*) FILTER (WHERE g.kind = 'message') AS messages_deleted_total,
       count(DISTINCT coalesce(cm.chat_id, m.chat_id)) AS chats_touched,
       (SELECT count(*) FROM chat_message_attachment a
          JOIN gone g2 ON g2.kind = 'message' AND g2.id = a.chat_message_id) AS attachments_deleted
FROM gone g
LEFT JOIN chat_member cm ON g.kind = 'member' AND cm.id = g.id
LEFT JOIN chat_message m ON g.kind = 'message' AND m.id = g.id;
\echo ##### F15_order_comment_no_author [F15]
SELECT count(*) AS order_comment_total,
       count(*) FILTER (WHERE company_member_id IS NULL AND restaurant_member_id IS NULL AND store_member_id IS NULL) AS rows_without_author,
       count(*) FILTER (WHERE company_member_id IS NULL AND restaurant_member_id IS NULL AND store_member_id IS NULL
                          AND deleted_at IS NULL) AS rows_without_author_live,
       count(DISTINCT order_id) FILTER (WHERE company_member_id IS NULL AND restaurant_member_id IS NULL
                                          AND store_member_id IS NULL) AS orders_affected,
       (min(created_at) FILTER (WHERE company_member_id IS NULL AND restaurant_member_id IS NULL
                                  AND store_member_id IS NULL))::date AS first_created,
       (max(created_at) FILTER (WHERE company_member_id IS NULL AND restaurant_member_id IS NULL
                                  AND store_member_id IS NULL))::date AS last_created,
       count(*) FILTER (WHERE num_nonnulls(company_member_id, restaurant_member_id, store_member_id) > 1) AS rows_with_several_authors,
       (count(*) FILTER (WHERE company_member_id IS NULL AND restaurant_member_id IS NULL
                           AND store_member_id IS NULL) > 0) AS upgrade_fails_at_0f14a819f8de
FROM order_comment;
\echo ##### F20_chat_party_all_null [F20]
SELECT count(*) AS chat_party_total,
       count(*) FILTER (WHERE store_id IS NULL AND restaurant_id IS NULL AND company_id IS NULL) AS rows_all_three_null,
       count(*) FILTER (WHERE store_id IS NULL AND restaurant_id IS NULL AND company_id IS NULL
                          AND deleted_at IS NULL) AS rows_all_three_null_live,
       count(DISTINCT chat_id) FILTER (WHERE store_id IS NULL AND restaurant_id IS NULL AND company_id IS NULL) AS chats_affected,
       count(*) FILTER (WHERE num_nonnulls(store_id, restaurant_id, company_id) > 1) AS rows_with_several_set,
       count(*) FILTER (WHERE company_id IS NOT NULL AND coalesce(store_id, restaurant_id) IS NOT NULL
                          AND company_id <> coalesce(store_id, restaurant_id)) AS company_id_overwritten,
       (count(*) FILTER (WHERE store_id IS NULL AND restaurant_id IS NULL AND company_id IS NULL) > 0) AS upgrade_fails_at_b76f719b477b
FROM chat_party;
\echo ##### F39_conflict_summary [F39]
WITH g AS (
  SELECT p.manufacturer_company_id AS mfr, i.manufacturer_product_id AS product_id,
         i.manufacturer_product_variation_id AS variation_id,
         count(*) AS n, count(*) FILTER (WHERE i.deleted_at IS NULL) AS n_live,
         count(DISTINCT i.manufacturer_subdivision_id) AS n_subdivisions,
         bool_or(EXISTS (
           SELECT 1 FROM manufacturer_subdivision_product own
           WHERE own.manufacturer_subdivision_id = p.manufacturer_company_id
             AND own.manufacturer_product_id = i.manufacturer_product_id
             AND own.manufacturer_product_variation_id IS NOT DISTINCT FROM i.manufacturer_product_variation_id
         )) AS has_own_row
  FROM manufacturer_subdivision_product i
  JOIN manufacturer_product p ON p.id = i.manufacturer_product_id
  WHERE i.manufacturer_subdivision_id <> p.manufacturer_company_id
  GROUP BY p.manufacturer_company_id, i.manufacturer_product_id, i.manufacturer_product_variation_id
)
SELECT count(*) FILTER (WHERE n > 1 OR has_own_row) AS conflict_groups,
       count(*) FILTER (WHERE n > 1 OR has_own_row) > 0 AS upgrade_would_raise,
       count(*) FILTER (WHERE n > 1 AND n_subdivisions > 1) AS groups_multi_subdivision,
       count(*) FILTER (WHERE n > 1 AND n_subdivisions = 1) AS groups_same_subdivision_dup,
       count(*) FILTER (WHERE has_own_row) AS groups_with_own_row,
       count(*) FILTER (WHERE (n > 1 OR has_own_row) AND n_live <= 1 AND NOT has_own_row) AS groups_only_due_to_soft_deleted,
       count(DISTINCT mfr) FILTER (WHERE n > 1 OR has_own_row) AS manufacturers_in_conflict,
       coalesce(sum(n), 0) AS inventory_rows_to_move,
       (SELECT count(*) FROM (SELECT manufacturer_company_id FROM manufacturer_subdivision
                              GROUP BY 1 HAVING count(*) > 1) x) AS mfr_with_multi_subdivisions_incl_deleted,
       (SELECT count(*) FROM (SELECT manufacturer_company_id FROM manufacturer_subdivision WHERE deleted_at IS NULL
                              GROUP BY 1 HAVING count(*) > 1) y) AS mfr_with_multi_live_subdivisions
FROM g;
\echo ##### F39_conflict_groups [F39]
WITH g AS (
  SELECT p.manufacturer_company_id AS mfr, i.manufacturer_product_id AS product_id,
         i.manufacturer_product_variation_id AS variation_id,
         count(*) AS n, count(*) FILTER (WHERE i.deleted_at IS NULL) AS n_live,
         count(DISTINCT i.manufacturer_subdivision_id) AS n_subdivisions,
         bool_or(EXISTS (
           SELECT 1 FROM manufacturer_subdivision_product own
           WHERE own.manufacturer_subdivision_id = p.manufacturer_company_id
             AND own.manufacturer_product_id = i.manufacturer_product_id
             AND own.manufacturer_product_variation_id IS NOT DISTINCT FROM i.manufacturer_product_variation_id
         )) AS has_own_row
  FROM manufacturer_subdivision_product i
  JOIN manufacturer_product p ON p.id = i.manufacturer_product_id
  WHERE i.manufacturer_subdivision_id <> p.manufacturer_company_id
  GROUP BY p.manufacturer_company_id, i.manufacturer_product_id, i.manufacturer_product_variation_id
)
SELECT mfr AS manufacturer_company_id, product_id, variation_id,
       n AS rows_in_group, n_live, n_subdivisions, has_own_row
FROM g
WHERE n > 1 OR has_own_row
ORDER BY n_live DESC, n DESC, mfr
LIMIT 20;
\echo ##### F50_orphan_accounts [F50,N97]
WITH cand AS (
  SELECT c.id, c.id AS link_id, c.type::text AS type, c.name, coalesce(mp.address, c.address) AS address,
         c.created_at, c.deleted_at, c.user_id, NULL::text AS company_status, false AS from_restaurant
  FROM company c
  LEFT JOIN LATERAL (
    SELECT trim(p.address) AS address FROM manufacturer_profile p
    WHERE p.company_id = c.id AND p.deleted_at IS NULL AND coalesce(trim(p.address), '') <> ''
      AND coalesce(length(trim(p.address)), 0) <= 255 AND coalesce(length(trim(p.city)), 0) <= 100
      AND coalesce(length(trim(p.state)), 0) <= 100 AND coalesce(length(trim(p.zip_code)), 0) <= 10
    LIMIT 1
  ) mp ON true
  WHERE c.type::text IN ('CLIENT', 'VENDOR')
  UNION ALL
  SELECT r.id, CASE WHEN EXISTS (SELECT 1 FROM company c0 WHERE c0.id = r.id)
                      OR EXISTS (SELECT 1 FROM store s0 WHERE s0.id = r.id) THEN NULL ELSE r.id END,
         'CLIENT', r.name, r.address, r.created_at, r.deleted_at, NULL::uuid, r.status::text, true
  FROM restaurant r WHERE r.company_id IS NULL
),
base AS (
  SELECT k.*,
         lower(regexp_replace(btrim(coalesce(k.name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(k.address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM cand k
  WHERE k.deleted_at IS NULL AND k.created_at >= '2026-09-17' AND k.user_id IS NULL
    AND coalesce(k.company_status, '') NOT IN ('UNREGISTERED', 'UNREGISTERED_WITH_ORDERS')
    AND NOT EXISTS (SELECT 1 FROM company_audit_log a
                    WHERE a.company_id = k.link_id AND a.action::text = 'created'
                      AND a.entity_type::text IN ('company', 'subscription')
                      AND abs(extract(epoch FROM a.created_at - k.created_at)) < 120)
    AND NOT EXISTS (SELECT 1 FROM company_subscription s
                    WHERE s.company_id = k.link_id AND s.invitation_code_used_at IS NOT NULL)
),
v_tmp AS (
  SELECT DISTINCT lower(regexp_replace(btrim(coalesce(temporary_name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(temporary_address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM client WHERE store_id IS NOT NULL
),
r_tmp AS (
  SELECT DISTINCT lower(regexp_replace(btrim(coalesce(name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM client_temporary_store
),
flagged AS (
  SELECT b.*,
    (b.type = 'CLIENT' AND EXISTS (SELECT 1 FROM client cl JOIN company_subscription s ON s.id = cl.company_subscription_id
                                   WHERE s.company_id = b.link_id)) AS r_client_link,
    (b.type = 'CLIENT' AND b.nm <> '' AND b.street <> ''
       AND EXISTS (SELECT 1 FROM v_tmp v WHERE v.nm = b.nm AND v.street = b.street)) AS r_client_tmp,
    (b.type = 'VENDOR' AND b.nm = '') AS r_vendor_noname,
    (b.type = 'VENDOR' AND b.nm <> '' AND b.street <> ''
       AND EXISTS (SELECT 1 FROM r_tmp r WHERE r.nm = b.nm AND r.street = b.street)) AS r_vendor_tmp
  FROM base b
),
doomed AS (
  SELECT f.id, f.link_id FROM flagged f
  WHERE f.r_client_link OR f.r_client_tmp OR f.r_vendor_noname OR f.r_vendor_tmp
),
acc AS (
  -- 8c6f5e1a90b1: every member row becomes an account whose company_id is its business id
  SELECT m.company_id AS business_id, m.deleted_at FROM company_member m
  UNION ALL SELECT m.manufacturer_subdivision_id, m.deleted_at FROM manufacturer_subdivision_member m
  UNION ALL SELECT m.restaurant_id, m.deleted_at FROM restaurant_member m
  UNION ALL SELECT m.store_id, m.deleted_at FROM store_member m
),
sm AS (
  SELECT
    (SELECT count(*) FROM acc) AS accounts_backfilled,
    (SELECT count(*) FROM acc a
      WHERE NOT EXISTS (SELECT 1 FROM company c WHERE c.id = a.business_id)
        AND NOT EXISTS (SELECT 1 FROM store st WHERE st.id = a.business_id)
        AND NOT EXISTS (SELECT 1 FROM restaurant r WHERE r.id = a.business_id)
        AND NOT EXISTS (SELECT 1 FROM manufacturer_subdivision ms WHERE ms.id = a.business_id)) AS orphans_without_c4d8,
    (SELECT count(*) FROM acc a JOIN doomed d ON d.link_id = a.business_id) AS orphans_from_c4d8,
    (SELECT count(*) FROM acc a JOIN doomed d ON d.link_id = a.business_id WHERE a.deleted_at IS NULL) AS live_orphans_from_c4d8,
    (SELECT count(DISTINCT d.link_id) FROM acc a JOIN doomed d ON d.link_id = a.business_id) AS doomed_companies_with_accounts,
    (SELECT count(*) FROM company c
      WHERE EXISTS (SELECT 1 FROM store st WHERE st.id = c.id)
         OR EXISTS (SELECT 1 FROM restaurant r WHERE r.id = c.id)
         OR EXISTS (SELECT 1 FROM manufacturer_subdivision ms WHERE ms.id = c.id)) AS business_id_collisions,
    (SELECT count(*) FROM restaurant r WHERE EXISTS (SELECT 1 FROM store st WHERE st.id = r.id))
      + (SELECT count(*) FROM manufacturer_subdivision ms
          WHERE EXISTS (SELECT 1 FROM store st WHERE st.id = ms.id)
             OR EXISTS (SELECT 1 FROM restaurant r WHERE r.id = ms.id)) AS branch_id_collisions
)
SELECT sm.*, (sm.orphans_without_c4d8 + sm.orphans_from_c4d8 > 0) AS upgrade_stops_at_049461d68471
FROM sm;
\echo ##### N95_credit_balance [N95]
SELECT count(*) AS restaurant_accounts,
       count(*) FILTER (WHERE ra.credit_balance <> 0) AS nonzero_accounts,
       count(DISTINCT ra.restaurant_id) FILTER (WHERE ra.credit_balance <> 0) AS nonzero_restaurants,
       count(*) FILTER (WHERE ra.credit_balance <> 0 AND ra.deleted_at IS NULL AND r.deleted_at IS NULL) AS nonzero_live,
       coalesce(sum(ra.credit_balance) FILTER (WHERE ra.credit_balance > 0), 0) AS positive_total,
       coalesce(sum(ra.credit_balance) FILTER (WHERE ra.credit_balance < 0), 0) AS negative_total,
       coalesce(sum(ra.credit_balance), 0) AS net_total,
       (min(ra.updated_at) FILTER (WHERE ra.credit_balance <> 0))::date AS first_nonzero_update,
       (max(ra.updated_at) FILTER (WHERE ra.credit_balance <> 0))::date AS last_nonzero_update
FROM restaurant_account ra
LEFT JOIN restaurant r ON r.id = ra.restaurant_id;
\echo ##### F25_vendor_cleared [F25]
SELECT count(*) AS audit_rows_joined_to_client,
       count(*) FILTER (WHERE c.store_id IS NOT NULL AND a.vendor_id IS DISTINCT FROM c.store_id) AS rows_repointed_to_store,
       count(*) FILTER (WHERE c.store_id IS NULL AND a.vendor_id IS NOT NULL) AS rows_vendor_cleared,
       count(DISTINCT a.client_id) FILTER (WHERE c.store_id IS NULL AND a.vendor_id IS NOT NULL) AS clients_affected,
       count(DISTINCT a.client_id) FILTER (WHERE c.store_id IS NULL AND a.vendor_id IS NOT NULL
                                             AND c.deleted_at IS NULL) AS live_clients_affected,
       count(DISTINCT a.vendor_id) FILTER (WHERE c.store_id IS NULL AND a.vendor_id IS NOT NULL) AS distinct_vendor_ids_lost,
       (min(a.created_at) FILTER (WHERE c.store_id IS NULL AND a.vendor_id IS NOT NULL))::date AS first_cleared_row,
       (max(a.created_at) FILTER (WHERE c.store_id IS NULL AND a.vendor_id IS NOT NULL))::date AS last_cleared_row,
       (SELECT count(*) FROM audit_client_log) AS audit_rows_total
FROM audit_client_log a
JOIN client c ON c.id = a.client_id;
\echo ##### PRE_schema_names [无编号（新增：按名字操作的约束/索引/序列/类型）；F37 同类]
WITH must_exist(kind, tbl, obj, mig) AS (VALUES
  ('con','role','role_pkey','0e2f71bd249e'),
  ('idx',NULL,'ix_role_created_at','0e2f71bd249e'),
  ('con','chat_member','uq_chat_member_chat_id_store_member_id','80a123f47df0'),
  ('con','chat_member','uq_chat_member_chat_id_restaurant_member_id','80a123f47df0'),
  ('con','chat_member','uq_chat_member_chat_id_company_member_id','80a123f47df0'),
  ('con','chat_member','chat_member_store_member_id_fkey','80a123f47df0'),
  ('con','chat_member','chat_member_restaurant_member_id_fkey','80a123f47df0'),
  ('con','chat_member','chat_member_company_member_id_fkey','80a123f47df0'),
  ('con','order_comment','order_comment_company_member_id_fkey','0f14a819f8de'),
  ('con','order_comment','order_comment_restaurant_member_id_fkey','0f14a819f8de'),
  ('con','order_comment','order_comment_store_member_id_fkey','0f14a819f8de'),
  ('con','order_comment','order_comment_updated_by_company_member_id_fkey','0f14a819f8de'),
  ('con','order_comment','order_comment_updated_by_store_member_id_fkey','0f14a819f8de'),
  ('con','order_packing_slip','order_packing_slip_packer_store_member_id_fkey','a56e6f86e0d7'),
  ('con','order_packing_slip','order_packing_slip_driver_store_member_id_fkey','a56e6f86e0d7'),
  ('con','order_packing_slip','order_packing_slip_approved_by_store_member_id_fkey','a56e6f86e0d7'),
  ('con','order_packing_slip','order_packing_slip_delivery_approved_by_restaurant_member__fkey','a56e6f86e0d7'),
  ('con','order_packing_slip','order_packing_slip_delivery_approved_by_store_member_id_fkey','a56e6f86e0d7'),
  ('con','chat_party','chat_party_store_id_fkey','b76f719b477b'),
  ('con','chat_party','chat_party_restaurant_id_fkey','b76f719b477b'),
  ('con','store_license','store_license_store_id_fkey','d3f8a61c2b94'),
  ('con','restaurant_license','restaurant_license_restaurant_id_fkey','d3f8a61c2b94'),
  ('con','store_category_m2m','store_category_m2m_store_id_fkey','a7c4e9d21f63'),
  ('con','restaurant_category_m2m','restaurant_category_m2m_restaurant_id_fkey','a7c4e9d21f63'),
  ('con','client','client_store_id_fkey','c5e2b81f4a07'),
  ('con','client','client_restaurant_id_fkey','c5e2b81f4a07'),
  ('con','client_invoice','client_invoice_store_id_fkey','c5e2b81f4a07'),
  ('con','client_master_invoice','client_master_invoice_store_id_fkey','c5e2b81f4a07'),
  ('con','client_request_product_catalog_updating','client_request_product_catalog_updating_store_id_fkey','c5e2b81f4a07'),
  ('con','restaurant_statement','restaurant_statement_restaurant_id_fkey','c5e2b81f4a07'),
  ('con','restaurant_product','restaurant_product_restaurant_id_fkey','6ab37f9b8662'),
  ('con','restaurant_product','restaurant_product_selected_store_id_fkey','6ab37f9b8662'),
  ('typ',NULL,'sign_in_data_contact_type','3d9e6b1c7a52'),
  ('typ',NULL,'sign_up_data_contact_type','3d9e6b1c7a52'),
  ('con','price_tier','price_tier_store_id_fkey','8c41f7d2e93a'),
  ('idx',NULL,'ix_price_tier_store_id','8c41f7d2e93a'),
  ('idx',NULL,'uq_price_tier_store_name','8c41f7d2e93a'),
  ('idx',NULL,'uq_price_tier_store_sort_order','8c41f7d2e93a'),
  ('idx',NULL,'uq_price_tier_one_default_per_store','8c41f7d2e93a'),
  ('con','order','order_store_id_fkey','b7e2a95c4d18'),
  ('con','order','order_restaurant_id_fkey','b7e2a95c4d18'),
  ('con','store_delivery','store_delivery_store_id_fkey','2c7d9e4b1a63'),
  ('con','store_delivery','store_delivery_store_id_key','2c7d9e4b1a63'),
  ('con','store_invoice_template','store_invoice_template_store_id_fkey','2c7d9e4b1a63'),
  ('con','store_invoice_template','store_invoice_template_store_id_key','2c7d9e4b1a63'),
  ('con','master_invoice','master_invoice_store_id_fkey','9a3e5c7d2f41'),
  ('con','master_invoice','master_invoice_restaurant_id_fkey','9a3e5c7d2f41'),
  ('con','vendor_request_product_catalog_updating','vendor_request_product_catalog_updating_store_id_fkey','6e2a9c4b7d13'),
  ('con','request_product_catalog_updating','request_product_catalog_updating_restaurant_id_fkey','6e2a9c4b7d13'),
  ('con','store_product','store_product_store_id_fkey','1f7c3a9e5b28'),
  ('seq',NULL,'product_id_seq','1f7c3a9e5b28'),
  ('seq',NULL,'store_product_id_seq','1f7c3a9e5b28'),
  ('tbl',NULL,'deprecated_product','1f7c3a9e5b28'),
  ('con','price_tier_config','price_tier_config_company_type_id_fkey','5d1b8f3e2a74'),
  ('idx',NULL,'ix_price_tier_config_company_type_id','5d1b8f3e2a74'),
  ('con','quotation','quotation_from_store_id_fkey','3b7e9d1c5a64'),
  ('con','quotation_vendor_client','fk_quotation_vendor_client_store_id','3b7e9d1c5a64'),
  ('con','quotation','quotation_restaurant_id_fkey','3b7e9d1c5a64'),
  ('con','quotation_vendor_client','quotation_vendor_client_restaurant_id_fkey','3b7e9d1c5a64'),
  ('con','manufacturer_subdivision_product','manufacturer_subdivision_produ_manufacturer_subdivision_id_fkey','6a2f8c4e1d93'),
  ('con','manufacturer_subdivision_product','uq_inventory_subdivision_product_variation','6a2f8c4e1d93'),
  ('idx',NULL,'uq_inventory_subdivision_product_no_variation','6a2f8c4e1d93'),
  ('idx',NULL,'ix_manufacturer_subdivision_product_manufacturer_subdivision_id','6a2f8c4e1d93'),
  ('con','manufacturer_catalog_import_job','manufacturer_catalog_ocr_job_manufacturer_subdivision_id_fkey','6a2f8c4e1d93'),
  ('idx',NULL,'ix_mfr_catalog_import_job_mfr_sub','6a2f8c4e1d93'),
  ('tbl',NULL,'company_emergency_contact_person','2e6a9c1f7b48'),
  ('tbl',NULL,'manufacturer_profile','e8b2f4a6c1d3'),
  ('tbl',NULL,'manufacturer_representation','e8b2f4a6c1d3'),
  ('con','user','user_email_key','c7f2a9d4e8b3'),
  ('idx',NULL,'uq_user_email_lower','c7f2a9d4e8b3'),
  ('con','user','user_phone_number_key','c7f2a9d4e8b3'),
  ('con','company','company_logo_id_fkey','b4d8f2a6c0e1'),
  ('con','user_action_log','user_action_log_user_id_fkey','7c1e4a9d2b58'),
  ('typ',NULL,'actiontype','7c1e4a9d2b58')
),
must_not_exist(kind, obj, mig) AS (VALUES
  ('tbl','account','8c6f5e1a90b1'), ('tbl','account_role_m2m','8c6f5e1a90b1'),
  ('tbl','company_type_role','0e2f71bd249e'), ('tbl','deprecated_company_back','5365a6cf834e'),
  ('tbl','company_info','a97c30031cc6'),
  ('tbl','deprecated_company_member','920893696493'), ('tbl','deprecated_company_company_type','920893696493'),
  ('tbl','deprecated_restaurant','920893696493'), ('tbl','deprecated_role','920893696493'),
  ('tbl','deprecated_store','920893696493'), ('tbl','deprecated_restaurant_member','920893696493'),
  ('tbl','deprecated_store_member','920893696493'), ('tbl','deprecated_manufacturer_subdivision','920893696493'),
  ('tbl','deprecated_manufacturer_subdivision_member','920893696493'),
  ('tbl','deprecated_restaurant_account','920893696493'), ('tbl','deprecated__css_pii_masked','920893696493'),
  ('tbl','deprecated_store_work_schedule_set','d3f8a61c2b94'), ('tbl','deprecated_store_work_schedule_day','d3f8a61c2b94'),
  ('tbl','system_account','da8ba148ea59'), ('tbl','system_account_role_m2m','da8ba148ea59'),
  ('tbl','system_company_type_role','da8ba148ea59'), ('tbl','system_role_permission','da8ba148ea59'),
  ('tbl','system_permission','da8ba148ea59'), ('tbl','system_user_action_log','da8ba148ea59'),
  ('tbl','system_sign_in_data','da8ba148ea59'), ('tbl','system_sign_up_data','da8ba148ea59'),
  ('tbl','system_user','da8ba148ea59'),
  ('typ','system_sign_in_data_contact_type','3d9e6b1c7a52'), ('typ','system_sign_up_data_contact_type','3d9e6b1c7a52'),
  ('tbl','product','1f7c3a9e5b28'), ('tbl','deprecated_product_category_remap_backup','8e4f2b6d9c31'),
  ('tbl','deprecated_quotation_store_split_backup','3b7e9d1c5a64'),
  ('tbl','deprecated_manufacturer_inventory_move_backup','6a2f8c4e1d93'),
  ('tbl','deprecated_manufacturer_category_copy_backup','6a2f8c4e1d93'),
  ('tbl','ix_mfr_catalog_import_job_mfr','6a2f8c4e1d93'),
  ('tbl','deprecated_notification_copy_backup','4c8e2a6f9b17'), ('tbl','deprecated_logo_copy_backup','9d3b7f1a5c62'),
  ('tbl','deprecated_company_emergency_contact_person','2e6a9c1f7b48'),
  ('tbl','deprecated_company_level_role_map','b5e1d7c3a920'), ('tbl','deprecated_company_level_role_backup','b5e1d7c3a920'),
  ('tbl','deprecated_company_level_role_reference_backup','b5e1d7c3a920'),
  ('tbl','company_buying_group','c4a8e1f6b2d9'),
  ('tbl','deprecated_manufacturer_profile','e8b2f4a6c1d3'), ('tbl','deprecated_manufacturer_representation','e8b2f4a6c1d3'),
  ('typ','company_status_enum','d6b0f4a8c2e5'), ('tbl','deprecated_onboarding','a2c4e6f8b0d1'),
  ('tbl','deprecated_logo','b4d8f2a6c0e1'),
  ('tbl','company_info_phone_number','f2a7c4e9b3d1'), ('tbl','company_info_contact_person','f2a7c4e9b3d1'),
  ('tbl','company_info_license','f2a7c4e9b3d1'), ('tbl','deprecated_company_billing','f2a7c4e9b3d1'),
  ('tbl','system_company_role','23e8d26d41eb'), ('tbl','system_permission_base','cd8e1f4305ce'),
  ('tbl','log_audit_client','31731a571e02'), ('tbl','system_confirmation_code','31731a571e02'),
  ('tbl','deprecated_api_entity','31731a571e02'),
  ('typ','logtype','7c1e4a9d2b58'), ('typ','logevent','7c1e4a9d2b58'),
  ('tbl','company_invitation','c4d8e2a6f1b3'),
  ('tbl','system_base_permission','6a31a24024e6'), ('tbl','deprecated_notification','6a31a24024e6')
)
SELECT 'missing' AS problem, e.mig, e.kind, e.tbl, e.obj
FROM must_exist e
WHERE NOT CASE e.kind
  WHEN 'con' THEN EXISTS (SELECT 1 FROM pg_constraint c
                          WHERE c.conname = e.obj AND c.conrelid = to_regclass(quote_ident(e.tbl)))
  WHEN 'idx' THEN EXISTS (SELECT 1 FROM pg_class i
                          WHERE i.relname = e.obj AND i.relkind IN ('i', 'I') AND i.relnamespace = 'public'::regnamespace)
  WHEN 'seq' THEN EXISTS (SELECT 1 FROM pg_class s
                          WHERE s.relname = e.obj AND s.relkind = 'S' AND s.relnamespace = 'public'::regnamespace)
  WHEN 'typ' THEN EXISTS (SELECT 1 FROM pg_type t WHERE t.typname = e.obj AND t.typnamespace = 'public'::regnamespace)
  WHEN 'tbl' THEN to_regclass(quote_ident(e.obj)) IS NOT NULL
END
UNION ALL
SELECT 'already_exists', n.mig, n.kind, NULL, n.obj
FROM must_not_exist n
WHERE CASE n.kind
  WHEN 'tbl' THEN to_regclass(quote_ident(n.obj)) IS NOT NULL
  WHEN 'typ' THEN EXISTS (SELECT 1 FROM pg_type t WHERE t.typname = n.obj AND t.typnamespace = 'public'::regnamespace)
END
ORDER BY 1, 2, 5
LIMIT 20;
\echo ##### PRE_8c6f_account_backfill [F52 / F11（同迁移；本条看 8c6f5e1a90b1 会不会因现有成员数据失败）]
WITH m AS (
  SELECT id, user_id, company_id AS biz, first_name, last_name, "position", security_code FROM company_member
  UNION ALL SELECT id, user_id, manufacturer_subdivision_id, first_name, last_name, NULL, security_code FROM manufacturer_subdivision_member
  UNION ALL SELECT id, user_id, restaurant_id, first_name, last_name, NULL, security_code FROM restaurant_member
  UNION ALL SELECT id, user_id, store_id, first_name, last_name, NULL, security_code FROM store_member
)
SELECT
  (SELECT count(*) FROM m) AS member_rows,
  (SELECT count(*) FROM (SELECT id FROM m GROUP BY id HAVING count(*) > 1) d) AS dup_member_id_pk_fails,
  (SELECT count(*) FROM (SELECT user_id, biz FROM m GROUP BY user_id, biz HAVING count(*) > 1) d) AS dup_user_business_unique_fails,
  (SELECT count(*) FROM m WHERE NOT EXISTS (SELECT 1 FROM "user" u WHERE u.id = m.user_id)) AS user_fk_orphans,
  (SELECT count(*) FROM m WHERE length(m.first_name) > 255 OR length(m.last_name) > 255 OR length(m."position") > 255) AS name_or_position_over_255,
  (SELECT count(*) FROM m WHERE length(m.security_code) > 4) AS security_code_over_4;
\echo ##### PRE_2e1b_company_type_code [无编号（2e1bd951650a 建 uq_company_type_code、c7e2a9d4f813 插管理员类型）]
SELECT
  (SELECT count(*) FROM company_type) AS company_types,
  (SELECT count(*) FROM company_type
    WHERE name IN ('Food Vendor','E&S Dealer','Broadliner Dealer','E&S Manufacturer','Food Manufacturer','Restaurant','Liquor Vendor')) AS mapped_rows,
  (SELECT count(*) FROM (
     SELECT name FROM company_type
     WHERE name IN ('Food Vendor','E&S Dealer','Broadliner Dealer','E&S Manufacturer','Food Manufacturer','Restaurant','Liquor Vendor')
     GROUP BY name HAVING count(*) > 1) d) AS names_sharing_one_code_unique_fails,
  (SELECT count(*) FROM company_type WHERE name IN ('devAdmin', 'admin')) AS admin_type_names_taken,
  (SELECT string_agg(indexdef, ' | ') FROM pg_indexes
    WHERE schemaname = 'public' AND tablename = 'company_type' AND indexdef LIKE 'CREATE UNIQUE%') AS unique_indexes;
\echo ##### PRE_role_codes [F18（同一 type 下重复的在用 code 会让升级中止）]
WITH r AS (
  SELECT id, type::text AS btype, name, belongs_to_company, deleted_at,
         btrim(regexp_replace(lower(name), '[^a-z0-9]+', '_', 'g'), '_') AS code
  FROM role
)
SELECT
  (SELECT count(*) FROM r) AS roles,
  (SELECT count(*) FROM (SELECT 1 FROM r WHERE NOT belongs_to_company AND deleted_at IS NULL
                         GROUP BY btype, code HAVING count(*) > 1) d) AS dup_live_facility_code_23e8_fails,
  (SELECT count(*) FROM (SELECT 1 FROM r WHERE NOT belongs_to_company AND deleted_at IS NULL
                         GROUP BY btype, name HAVING count(*) > 1) d) AS dup_live_facility_name_b9d4_fails,
  (SELECT count(*) FROM (SELECT 1 FROM r GROUP BY btype, name, belongs_to_company HAVING count(*) > 1) d) AS dup_name_same_level_incl_deleted,
  (SELECT count(*) FROM r WHERE length(code) > 64) AS code_over_64_a3d9_fails,
  (SELECT count(*) FROM r WHERE length(name) > 255) AS name_over_255_fails,
  (SELECT count(*) FROM r WHERE code = '') AS empty_code;
\echo ##### PRE_b5e1_unmapped_company_roles [N3（同迁移）；无编号（b5e1d7c3a920 的 RuntimeError）]
WITH grp(tname, btype) AS (VALUES
  ('Restaurant','BUYER'), ('Food Vendor','VENDOR'), ('Liquor Vendor','VENDOR'), ('E&S Dealer','VENDOR'),
  ('Broadliner Dealer','VENDOR'), ('Food Manufacturer','MANUFACTURER'), ('E&S Manufacturer','MANUFACTURER')
),
r AS (
  SELECT id, type::text AS btype, name, belongs_to_company, deleted_at,
         btrim(regexp_replace(lower(name), '[^a-z0-9]+', '_', 'g'), '_') AS code
  FROM role
),
ctype AS (
  SELECT c.id,
         coalesce(
           (SELECT min(ct.name) FROM company_company_type cct JOIN company_type ct ON ct.id = cct.company_type_id
             WHERE cct.company_id = c.id AND cct.deleted_at IS NULL),
           CASE c.type::text WHEN 'CLIENT' THEN 'Restaurant' WHEN 'VENDOR' THEN 'Food Vendor'
                             WHEN 'MANUFACTURER' THEN 'Food Manufacturer' END) AS tname
  FROM company c
),
refs AS (
  SELECT role_id, company_id AS cid FROM company_member
  UNION ALL SELECT m.role_id, s.company_id FROM store_member m LEFT JOIN store s ON s.id = m.store_id
  UNION ALL SELECT m.role_id, rs.company_id FROM restaurant_member m LEFT JOIN restaurant rs ON rs.id = m.restaurant_id
  UNION ALL SELECT m.role_id, ms.manufacturer_company_id FROM manufacturer_subdivision_member m
            LEFT JOIN manufacturer_subdivision ms ON ms.id = m.manufacturer_subdivision_id
  UNION ALL SELECT role_id, company_id FROM onboarding_company_member
  UNION ALL SELECT m.role_id, s.company_id FROM onboarding_store_member m LEFT JOIN store s ON s.id = m.store_id
  UNION ALL SELECT m.role_id, rs.company_id FROM onboarding_restaurant_member m LEFT JOIN restaurant rs ON rs.id = m.restaurant_id
  UNION ALL SELECT m.role_id, ms.manufacturer_company_id FROM onboarding_manufacturer_subdivision_member m
            LEFT JOIN manufacturer_subdivision ms ON ms.id = m.manufacturer_subdivision_id
  UNION ALL SELECT role_id, NULL::uuid FROM order_history
  UNION ALL SELECT role_id, NULL::uuid FROM order_invoice_history
  UNION ALL SELECT role_id, NULL::uuid FROM order_packing_slip_history
),
agg AS (SELECT role_id, cid, count(*) AS n FROM refs GROUP BY role_id, cid),
resolved AS (
  SELECT a.role_id, a.n, r.code,
         CASE WHEN g.btype IS NOT NULL AND g.btype <> r.btype
                   AND EXISTS (SELECT 1 FROM r r2 WHERE r2.btype = g.btype AND r2.name = r.name AND r2.belongs_to_company)
              THEN g.btype ELSE r.btype END AS final_btype
  FROM agg a
  JOIN r ON r.id = a.role_id AND r.belongs_to_company
  LEFT JOIN ctype ct ON ct.id = a.cid
  LEFT JOIN grp g ON g.tname = ct.tname
)
SELECT x.final_btype, x.role_id, sum(x.n) AS referencing_rows
FROM resolved x
WHERE NOT EXISTS (SELECT 1 FROM r f
                  WHERE f.btype = x.final_btype AND NOT f.belongs_to_company AND f.deleted_at IS NULL AND f.code = x.code)
  AND NOT (x.code = 'ceo' AND NOT EXISTS (SELECT 1 FROM r f
                                          WHERE f.btype = x.final_btype AND NOT f.belongs_to_company AND f.code = 'ceo'))
GROUP BY x.final_btype, x.role_id
ORDER BY 3 DESC
LIMIT 20;
\echo ##### PRE_F15_order_comment [F15]
WITH mid AS (
  SELECT DISTINCT id FROM (
    SELECT id FROM company_member UNION ALL SELECT id FROM restaurant_member
    UNION ALL SELECT id FROM store_member UNION ALL SELECT id FROM manufacturer_subdivision_member) u
),
oc AS (
  SELECT coalesce(company_member_id, restaurant_member_id, store_member_id) AS author,
         coalesce(updated_by_company_member_id, updated_by_store_member_id) AS editor,
         (company_member_id IS NOT NULL)::int + (restaurant_member_id IS NOT NULL)::int + (store_member_id IS NOT NULL)::int AS n_authors
  FROM order_comment
)
SELECT
  count(*) AS order_comments,
  count(*) FILTER (WHERE oc.author IS NULL) AS no_author_not_null_fails,
  count(*) FILTER (WHERE oc.author IS NOT NULL AND a.id IS NULL) AS author_fk_orphans,
  count(*) FILTER (WHERE oc.editor IS NOT NULL AND e.id IS NULL) AS editor_fk_orphans,
  count(*) FILTER (WHERE oc.n_authors > 1) AS several_author_columns_info
FROM oc
LEFT JOIN mid a ON a.id = oc.author
LEFT JOIN mid e ON e.id = oc.editor;
\echo ##### PRE_F7_chat_member [F7]
WITH mid AS (
  SELECT DISTINCT id FROM (
    SELECT id FROM company_member UNION ALL SELECT id FROM restaurant_member
    UNION ALL SELECT id FROM store_member UNION ALL SELECT id FROM manufacturer_subdivision_member) u
),
cm AS (
  SELECT id, chat_id, last_read_message_id,
         coalesce(store_member_id, restaurant_member_id, company_member_id) AS acc
  FROM chat_member
),
gone_msg AS (
  SELECT m.id FROM chat_message m JOIN cm ON cm.id = m.chat_member_id WHERE cm.acc IS NULL
)
SELECT
  (SELECT count(*) FROM cm) AS chat_members,
  (SELECT count(*) FROM cm WHERE acc IS NULL) AS rows_hard_deleted,
  (SELECT count(*) FROM gone_msg) AS messages_deleted_with_them,
  (SELECT count(*) FROM cm JOIN gone_msg g ON g.id = cm.last_read_message_id WHERE cm.acc IS NOT NULL) AS survivors_last_read_on_deleted_msg,
  (SELECT count(*) FROM chat_message m JOIN gone_msg g ON g.id = m.forwarded_message_id
    WHERE NOT EXISTS (SELECT 1 FROM gone_msg g2 WHERE g2.id = m.id)) AS survivors_forwarding_deleted_msg,
  (SELECT count(*) FROM (SELECT 1 FROM cm WHERE acc IS NOT NULL GROUP BY chat_id, acc HAVING count(*) > 1) d) AS dup_chat_account_unique_fails,
  (SELECT count(*) FROM cm LEFT JOIN mid ON mid.id = cm.acc WHERE cm.acc IS NOT NULL AND mid.id IS NULL) AS account_fk_orphans,
  (SELECT string_agg(c.conrelid::regclass::text || '.' || a.attname || '->' || c.confrelid::regclass::text || ':' || c.confdeltype::text,
                     '; ' ORDER BY c.conname)
     FROM pg_constraint c JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.contype = 'f' AND c.confrelid IN ('chat_member'::regclass, 'chat_message'::regclass)) AS fk_on_delete_actions;
\echo ##### PRE_F20_chat_party [F20]
SELECT
  count(*) AS chat_parties,
  count(*) FILTER (WHERE store_id IS NULL AND restaurant_id IS NULL AND company_id IS NULL) AS all_null_not_null_fails,
  count(*) FILTER (WHERE (store_id IS NOT NULL)::int + (restaurant_id IS NOT NULL)::int + (company_id IS NOT NULL)::int > 1) AS several_set_info,
  count(*) FILTER (WHERE store_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM store s WHERE s.id = cp.store_id)) AS store_orphans,
  count(*) FILTER (WHERE store_id IS NULL AND restaurant_id IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM restaurant r WHERE r.id = cp.restaurant_id)) AS restaurant_orphans,
  count(*) FILTER (WHERE store_id IS NULL AND restaurant_id IS NULL AND company_id IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM company c WHERE c.id = cp.company_id)) AS company_orphans
FROM chat_party cp;
\echo ##### PRE_a56e_packing_slip_accounts [无编号（a56e6f86e0d7 新外键）]
WITH mid AS (
  SELECT DISTINCT id FROM (
    SELECT id FROM company_member UNION ALL SELECT id FROM restaurant_member
    UNION ALL SELECT id FROM store_member UNION ALL SELECT id FROM manufacturer_subdivision_member) u
),
v AS (
  SELECT packer_store_member_id AS x FROM order_packing_slip WHERE packer_store_member_id IS NOT NULL
  UNION ALL SELECT driver_store_member_id FROM order_packing_slip WHERE driver_store_member_id IS NOT NULL
  UNION ALL SELECT approved_by_store_member_id FROM order_packing_slip WHERE approved_by_store_member_id IS NOT NULL
  UNION ALL SELECT coalesce(delivery_approved_by_restaurant_member_id, delivery_approved_by_store_member_id)
            FROM order_packing_slip
            WHERE coalesce(delivery_approved_by_restaurant_member_id, delivery_approved_by_store_member_id) IS NOT NULL
)
SELECT count(*) AS member_refs, count(*) FILTER (WHERE mid.id IS NULL) AS account_fk_orphans
FROM v LEFT JOIN mid ON mid.id = v.x;
\echo ##### PRE_F5_id_collisions [F5]
SELECT
  (SELECT count(*) FROM store s WHERE EXISTS (SELECT 1 FROM company c WHERE c.id = s.id)) AS store_ids_taken,
  (SELECT count(*) FROM restaurant r
    WHERE EXISTS (SELECT 1 FROM company c WHERE c.id = r.id) OR EXISTS (SELECT 1 FROM store s WHERE s.id = r.id)) AS restaurant_ids_taken,
  (SELECT count(*) FROM manufacturer_subdivision m
    WHERE EXISTS (SELECT 1 FROM company c WHERE c.id = m.id) OR EXISTS (SELECT 1 FROM store s WHERE s.id = m.id)
       OR EXISTS (SELECT 1 FROM restaurant r WHERE r.id = m.id)) AS subdivision_ids_taken;
\echo ##### PRE_insert_defaults [无编号（各迁移 INSERT 没给的 NOT NULL 列必须有默认值）]
WITH targets(mig, tbl, supplied) AS (VALUES
  ('b7d82c2e651b', 'company', ARRAY['id','name','alternative_name','display_name','address','logo_id','phone_number','email',
                                    'type','parent_company_id','created_at','updated_at','deleted_at']),
  ('4b52dd3297e5/a9d3f7b2e6c1', 'company', ARRAY['id','name','type','subscriber_status','created_at','updated_at']),
  ('4b52dd3297e5', 'user', ARRAY['id','email','password_hash','role','created_at','updated_at']),
  ('083296a8b071', 'company_company_type', ARRAY['company_id','company_type_id','created_at','updated_at']),
  ('d3f8a61c2b94', 'company_work_schedule_set', ARRAY['id','company_id','time_from','time_to','created_at','updated_at','deleted_at']),
  ('d3f8a61c2b94', 'company_work_schedule_day', ARRAY['id','work_schedule_set_id','company_id','day_of_week','created_at','updated_at','deleted_at']),
  ('f4a9c27e1b85', 'company_role_permission', ARRAY['company_id','role_id','permission_id','entity_id','created_at','updated_at','deleted_at']),
  ('7c2d4e8a1b96/6a2f8c4e1d93', 'product_category', ARRAY['id','name','created_at','updated_at','deleted_at','parent_id','company_id']),
  ('3b7e9d1c5a64', 'quotation_numeration', ARRAY['id','vendor_company_id','numeration_setting','next_rule','example','letter',
                                                 'last_offline_number','created_at','updated_at','deleted_at']),
  ('3b7e9d1c5a64', 'terms_template', ARRAY['vendor_company_id','title','text','created_at','updated_at','deleted_at']),
  ('4c8e2a6f9b17', 'notification', ARRAY['id','is_on','type','company_id','role_id','created_at','updated_at']),
  ('9d3b7f1a5c62', 'logo', ARRAY['id','filename','file_url','created_at','updated_at']),
  ('e7b3d9a1c5f2', 'price_tier', ARRAY['id','store_id','name','sort_order','is_default','created_at','updated_at']),
  ('f2c8a4e6d1b7', 'company_contact_person', ARRAY['id','company_id','name','first_name','last_name','title','email',
                                                   'phone_number','created_at','updated_at']),
  ('5286c79e362d', 'company_phone_number', ARRAY['id','company_id','phone_number','is_primary','phone_type','created_at','updated_at']),
  ('b4d8f2a6c0e1', 'file', ARRAY['id','filename','file_url','file_size','module_type','file_type','status','path_url',
                                 'created_at','updated_at','deleted_at']),
  ('1e76218f5233', 'store_delivery', ARRAY['id','store_id','created_at','updated_at']),
  ('c7e2a9d4f813', 'company_type', ARRAY['id','name','category','created_at','updated_at'])
)
SELECT t.mig, t.tbl, string_agg(c.column_name::text, ',' ORDER BY c.column_name) AS not_null_without_default
FROM targets t
JOIN information_schema.columns c
  ON c.table_schema = 'public' AND c.table_name = t.tbl
 AND c.is_nullable = 'NO' AND c.column_default IS NULL
 AND c.is_identity = 'NO' AND c.is_generated = 'NEVER'
 AND NOT (c.column_name::text = ANY (t.supplied))
GROUP BY t.mig, t.tbl
ORDER BY 1, 2
LIMIT 20;
\echo ##### PRE_b7d8_copy_fk_and_lengths [无编号（5365a6cf834e 备份表外键、b7d82c2e651b 复制行外键、a97c30031cc6 长度）]
SELECT
  (SELECT count(*) FROM company c WHERE c.logo_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM logo l WHERE l.id = c.logo_id)) AS company_logo_orphans,
  (SELECT count(*) FROM company c WHERE c.user_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM "user" u WHERE u.id = c.user_id)) AS company_user_orphans,
  (SELECT count(*) FROM company c WHERE c.parent_company_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM company p WHERE p.id = c.parent_company_id)) AS company_parent_orphans,
  (SELECT count(*) FROM store s WHERE NOT EXISTS (SELECT 1 FROM company c WHERE c.id = s.company_id)) AS store_parent_orphans,
  (SELECT count(*) FROM store s WHERE s.logo_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM logo l WHERE l.id = s.logo_id)) AS store_logo_orphans,
  (SELECT count(*) FROM restaurant r WHERE r.company_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM company c WHERE c.id = r.company_id)) AS restaurant_parent_orphans,
  (SELECT count(*) FROM manufacturer_subdivision m
    WHERE NOT EXISTS (SELECT 1 FROM company c WHERE c.id = m.manufacturer_company_id)) AS subdivision_parent_orphans,
  (SELECT count(*) FROM store s WHERE length(s.remit_to) > 255 OR length(s.remit_to_name) > 255) AS store_remit_to_over_255,
  (SELECT string_agg(conname || ': ' || pg_get_constraintdef(oid), ' | ')
     FROM pg_constraint WHERE conrelid = 'company'::regclass AND contype = 'c') AS company_check_constraints;
\echo ##### PRE_F1_fixed_seed_rows [F1（同迁移）；无编号（固定 id/邮箱撞车）]
SELECT
  (SELECT count(*) FROM "user" WHERE lower(email) = 'dev.admin@yopmail.com') AS dev_admin_email_taken,
  (SELECT count(*) FROM "user" WHERE id = 'bcd926a7-156b-45d0-803d-e59e33912032') AS dev_admin_user_id_taken,
  (SELECT count(*) FROM (SELECT id FROM company UNION ALL SELECT id FROM store UNION ALL SELECT id FROM restaurant
                         UNION ALL SELECT id FROM manufacturer_subdivision) x
    WHERE x.id IN ('be848550-2c98-43b3-8629-254109f5324d', 'c5e2a8f4-1b7d-4e39-8a60-d4f9b3c71e25')) AS fixed_company_ids_taken,
  (SELECT count(*) FROM role
    WHERE id IN ('3aee88f6-87d7-4838-acc5-872c25e4dd1d', '3025e9b3-4240-4d3b-93fb-364cafca0b6f',
                 '6d0b2e4a-8f13-4c57-9a6e-2b7c1d3e5f80')) AS fixed_role_ids_taken,
  (SELECT count(*) FROM (SELECT id FROM company_member UNION ALL SELECT id FROM store_member
                         UNION ALL SELECT id FROM restaurant_member UNION ALL SELECT id FROM manufacturer_subdivision_member) x
    WHERE x.id = '1b3ea549-8324-40f7-ab9b-43257cce14b3') AS fixed_account_id_taken,
  (SELECT count(*) FROM "user" WHERE role = 'admin' AND deleted_at IS NULL) AS platform_admins_info;
\echo ##### PRE_d3f8_store_schedule_copy [无编号（d3f8a61c2b94 门店营业时间搬到 company_work_schedule_*）]
SELECT
  (SELECT count(*) FROM store_work_schedule_set s
    WHERE EXISTS (SELECT 1 FROM company_work_schedule_set c WHERE c.id = s.id)) AS set_id_collisions,
  (SELECT count(*) FROM store_work_schedule_day s
    WHERE EXISTS (SELECT 1 FROM company_work_schedule_day c WHERE c.id = s.id)) AS day_id_collisions,
  (SELECT count(*) FROM store_work_schedule_day d
    WHERE NOT EXISTS (SELECT 1 FROM store_work_schedule_set s WHERE s.id = d.work_schedule_set_id)) AS day_without_set,
  (SELECT count(*) FROM store_work_schedule_set s WHERE NOT EXISTS (SELECT 1 FROM store x WHERE x.id = s.store_id)) AS set_store_orphans,
  (SELECT count(*) FROM (SELECT 1 FROM store_work_schedule_day GROUP BY work_schedule_set_id, day_of_week HAVING count(*) > 1) d) AS dup_set_day_all_rows,
  (SELECT count(*) FROM (SELECT 1 FROM store_work_schedule_day WHERE deleted_at IS NULL
                         GROUP BY work_schedule_set_id, day_of_week HAVING count(*) > 1) d) AS dup_set_day_live_rows,
  (SELECT count(*) FROM (SELECT 1 FROM store_work_schedule_day WHERE deleted_at IS NULL
                         GROUP BY store_id, day_of_week HAVING count(*) > 1) d) AS dup_store_day_live_rows,
  (SELECT string_agg(tablename || ': ' || indexdef, ' | ') FROM pg_indexes
    WHERE schemaname = 'public' AND tablename IN ('company_work_schedule_set', 'company_work_schedule_day')
      AND indexdef LIKE 'CREATE UNIQUE%') AS target_unique_indexes;
\echo ##### PRE_F32_product_number [F32]
WITH sp AS (
  SELECT sp.store_id, vp.product_number
  FROM store_product sp JOIN vendor_product vp ON vp.id = sp.vendor_product_id
  WHERE sp.deleted_at IS NULL AND vp.product_number IS NOT NULL
),
dup AS (SELECT store_id, product_number, count(*) AS n FROM sp GROUP BY store_id, product_number HAVING count(*) > 1)
SELECT
  (SELECT count(*) FROM sp) AS live_rows_with_number,
  (SELECT count(*) FROM dup) AS dup_groups_index_fails,
  (SELECT coalesce(sum(n), 0) FROM dup) AS dup_rows,
  (SELECT count(DISTINCT store_id) FROM dup) AS stores_affected,
  (SELECT count(*) FROM (SELECT 1 FROM store_product WHERE deleted_at IS NULL
                         GROUP BY store_id, vendor_product_id HAVING count(*) > 1) d) AS same_vendor_product_twice_in_store,
  (SELECT count(*) FROM store_product sp2 JOIN vendor_product vp2 ON vp2.id = sp2.vendor_product_id
    WHERE length(vp2.product_number) > 32) AS number_over_32_update_fails;
\echo ##### PRE_7c2d_category_copy_parent [无编号（7c2d4e8a1b96 / 6a2f8c4e1d93 按 md5 复制分类树）]
SELECT
  (SELECT count(*) FROM product_category pc JOIN product_category par ON par.id = pc.parent_id
    WHERE par.company_id IS DISTINCT FROM pc.company_id
      AND EXISTS (SELECT 1 FROM store s WHERE s.company_id = pc.company_id)) AS store_copy_parent_missing,
  (SELECT count(*) FROM product_category pc JOIN product_category par ON par.id = pc.parent_id
    WHERE par.company_id IS DISTINCT FROM pc.company_id
      AND EXISTS (SELECT 1 FROM manufacturer_subdivision ms WHERE ms.manufacturer_company_id = pc.company_id)) AS subdivision_copy_parent_missing,
  (SELECT count(*) FROM product_category pc
    WHERE pc.parent_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM product_category p WHERE p.id = pc.parent_id)) AS parent_orphans,
  (SELECT count(*) FROM product_category pc WHERE EXISTS (SELECT 1 FROM store s WHERE s.company_id = pc.company_id)) AS categories_with_store_copies_info,
  (SELECT string_agg(indexdef, ' | ') FROM pg_indexes
    WHERE schemaname = 'public' AND tablename = 'product_category' AND indexdef LIKE 'CREATE UNIQUE%') AS unique_indexes;
\echo ##### PRE_F39_inventory_raise [F39]
SELECT
  (SELECT count(*) FROM (
     SELECT 1
     FROM manufacturer_subdivision_product i JOIN manufacturer_product p ON p.id = i.manufacturer_product_id
     WHERE i.manufacturer_subdivision_id <> p.manufacturer_company_id
     GROUP BY p.manufacturer_company_id, i.manufacturer_product_id, i.manufacturer_product_variation_id
     HAVING count(*) > 1 OR bool_or(EXISTS (
         SELECT 1 FROM manufacturer_subdivision_product own
         WHERE own.manufacturer_subdivision_id = p.manufacturer_company_id
           AND own.manufacturer_product_id = i.manufacturer_product_id
           AND own.manufacturer_product_variation_id IS NOT DISTINCT FROM i.manufacturer_product_variation_id))
   ) d) AS conflicting_groups_raise,
  (SELECT count(*) FROM (SELECT manufacturer_company_id FROM manufacturer_subdivision
                         GROUP BY 1 HAVING count(*) > 1) d) AS manufacturers_with_several_subdivisions_incl_deleted,
  (SELECT count(*) FROM (SELECT manufacturer_company_id FROM manufacturer_subdivision WHERE deleted_at IS NULL
                         GROUP BY 1 HAVING count(*) > 1) d) AS manufacturers_with_several_live_subdivisions,
  (SELECT count(*) FROM manufacturer_subdivision_product) AS inventory_rows,
  (SELECT count(*) FROM manufacturer_subdivision_product i
    WHERE NOT EXISTS (SELECT 1 FROM manufacturer_product p WHERE p.id = i.manufacturer_product_id)) AS inventory_product_orphans;
\echo ##### PRE_3b7e_quotation_move [F35 / F36（同迁移）；无编号（升级时撞唯一）]
SELECT
  (SELECT count(*) FROM (SELECT 1 FROM quotation WHERE deleted_at IS NULL
                         GROUP BY coalesce(from_store_id, vendor_company_id), number HAVING count(*) > 1) d) AS dup_live_vendor_number_fails,
  (SELECT count(*) FROM (SELECT 1 FROM quotation_vendor_client WHERE deleted_at IS NULL AND custom_client_id IS NOT NULL
                         GROUP BY coalesce(store_id, vendor_company_id), lower(custom_client_id) HAVING count(*) > 1) d) AS dup_live_vendor_custom_id_fails,
  (SELECT count(*) FROM (SELECT 1 FROM quotation_vendor_client WHERE deleted_at IS NULL AND client_id IS NOT NULL
                         GROUP BY coalesce(store_id, vendor_company_id), client_id HAVING count(*) > 1) d) AS dup_live_vendor_client_fails,
  (SELECT count(*) FROM quotation q
    WHERE q.from_store_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM store s WHERE s.id = q.from_store_id AND s.company_id = q.vendor_company_id)) AS quotations_from_store_of_other_parent,
  (SELECT count(*) FROM quotation_vendor_client v
    WHERE v.store_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM store s WHERE s.id = v.store_id AND s.company_id = v.vendor_company_id)) AS vendor_clients_from_store_of_other_parent,
  (SELECT string_agg(tablename || ': ' || indexdef, ' | ') FROM pg_indexes
    WHERE schemaname = 'public' AND tablename IN ('quotation', 'quotation_vendor_client', 'quotation_numeration', 'terms_template')
      AND indexdef LIKE 'CREATE UNIQUE%') AS unique_indexes;
\echo ##### PRE_F34_price_tier_config [F34]
SELECT
  (SELECT count(*) FROM price_tier_config) AS config_rows,
  (SELECT count(*) FROM price_tier_config WHERE deleted_at IS NULL) AS live_config_rows,
  (SELECT count(*) FROM (SELECT config_module FROM price_tier_config WHERE deleted_at IS NULL
                         GROUP BY config_module HAVING count(*) > 1) d) AS live_modules_with_several_rows_fails,
  (SELECT count(*) FROM (SELECT config_module FROM price_tier_config GROUP BY config_module HAVING count(*) > 1) d) AS modules_with_several_rows_incl_deleted,
  (SELECT count(*) FROM price_tier_config WHERE config_module = 'price tier' AND deleted_at IS NULL) AS live_price_tier_module_rows,
  (SELECT string_agg(indexdef, ' | ') FROM pg_indexes
    WHERE schemaname = 'public' AND tablename = 'price_tier_config' AND indexdef LIKE 'CREATE UNIQUE%') AS unique_indexes;
\echo ##### PRE_e7b3_price_tier_seed [无编号（e7b3d9a1c5f2 补种 TierA-D）]
WITH liquor_parent AS (
  SELECT c.id, c.deleted_at FROM company c
  WHERE c.type::text = 'VENDOR'
    AND (SELECT min(ct.name) FROM company_company_type cct JOIN company_type ct ON ct.id = cct.company_type_id
          WHERE cct.company_id = c.id AND cct.deleted_at IS NULL AND ct.category::text = 'VENDOR') = 'Liquor Vendor'
),
liquor_store AS (
  SELECT s.id, s.deleted_at FROM store s
  WHERE (SELECT min(ct.name) FROM company_company_type cct JOIN company_type ct ON ct.id = cct.company_type_id
          WHERE cct.company_id = s.company_id AND cct.deleted_at IS NULL AND ct.category::text = 'VENDOR') = 'Liquor Vendor'
)
SELECT
  (SELECT count(*) FROM liquor_parent WHERE deleted_at IS NULL) AS liquor_parent_companies_seeded,
  (SELECT count(*) FROM liquor_store ls WHERE ls.deleted_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM price_tier pt WHERE pt.store_id = ls.id AND pt.deleted_at IS NULL)) AS liquor_stores_seeded,
  (SELECT count(*) FROM liquor_store ls WHERE ls.deleted_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM price_tier pt WHERE pt.store_id = ls.id AND pt.deleted_at IS NULL)
      AND EXISTS (SELECT 1 FROM price_tier pt WHERE pt.store_id = ls.id AND pt.deleted_at IS NOT NULL)) AS seeded_stores_with_deleted_tiers,
  (SELECT string_agg(indexdef, ' | ') FROM pg_indexes
    WHERE schemaname = 'public' AND tablename = 'price_tier' AND indexdef LIKE 'CREATE UNIQUE%') AS price_tier_unique_indexes;
\echo ##### PRE_e8b2_profile_merge [无编号（e8b2f4a6c1d3 合并进 company_info；N61 同链）]
SELECT
  (SELECT count(*) FROM (SELECT company_id FROM manufacturer_profile WHERE deleted_at IS NULL
                         GROUP BY company_id HAVING count(*) > 1) d) AS profile_multi_live_fails,
  (SELECT count(*) FROM (SELECT manufacturer_company_id FROM manufacturer_representation WHERE deleted_at IS NULL
                         GROUP BY manufacturer_company_id HAVING count(*) > 1) d) AS representation_multi_live_fails,
  (SELECT count(*) FROM manufacturer_profile p WHERE p.deleted_at IS NULL AND (
      length(p.mailing_address) > 255 OR length(p.mailing_city) > 255 OR length(p.mailing_state) > 255
      OR length(p.mailing_zip_code) > 20 OR length(p.mailing_country) > 255 OR length(p.country) > 255
      OR length(p.main_phone) > 50 OR length(p.main_phone_ext) > 10 OR length(p.accounting_phone) > 50
      OR length(p.accounting_phone_ext) > 10 OR length(p.customer_service_phone) > 50
      OR length(p.customer_service_phone_ext) > 10 OR length(p.sales_manager_name) > 255
      OR length(p.sales_phone) > 50 OR length(p.sales_phone_ext) > 10 OR length(p.contact_title) > 255
      OR length(p.contact_email) > 255)) AS profile_too_long,
  (SELECT count(*) FROM manufacturer_representation r WHERE r.deleted_at IS NULL AND (
      length(r.agency_name) > 255 OR length(r.agent_name) > 255 OR length(r.cell_phone) > 50
      OR length(r.office_phone) > 50 OR length(r.email) > 255 OR length(r.order_email) > 255
      OR EXISTS (SELECT 1 FROM unnest(r.mafsi_area_ids) AS a(v) WHERE length(a.v::text) > 8))) AS representation_too_long,
  (SELECT count(*) FROM manufacturer_profile p WHERE p.deleted_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM company c WHERE c.id = p.company_id)) AS profile_company_orphans,
  (SELECT count(*) FROM manufacturer_representation r WHERE r.deleted_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM company c WHERE c.id = r.manufacturer_company_id)) AS representation_company_orphans,
  (SELECT format_type(atttypid, atttypmod) FROM pg_attribute
    WHERE attrelid = 'manufacturer_representation'::regclass AND attname = 'mafsi_area_ids') AS mafsi_source_type;
\echo ##### PRE_address_split_lengths [N59 / N61 / N46（同迁移；本条只看拆分会不会因超长失败）]
WITH src AS (
  SELECT 'company/store/restaurant/subdivision' AS src, address AS a FROM company
  UNION ALL SELECT 'company/store/restaurant/subdivision', address FROM store
  UNION ALL SELECT 'company/store/restaurant/subdivision', address FROM restaurant
  UNION ALL SELECT 'company/store/restaurant/subdivision', address FROM manufacturer_subdivision
  UNION ALL SELECT 'quotation.from_address', from_address FROM quotation
  UNION ALL SELECT 'quotation.ship_to_address', ship_to_address FROM quotation
  UNION ALL SELECT 'client.temporary_address', temporary_address FROM client
  UNION ALL SELECT 'client_temporary_store.address', address FROM client_temporary_store
  UNION ALL SELECT 'quotation_vendor_client.address', address FROM quotation_vendor_client
),
parsed AS (
  SELECT src,
         regexp_match(
           regexp_replace(btrim(a), '\s*,\s*(US|USA|United States( of America)?)\s*$', '', 'i'),
           '^(.*\S)\s*,\s*([^,]*\S)\s*,\s*([A-Za-z]{2})(?:\s+(\d{5}(?:-\d{4})?))?\s*$') AS p
  FROM src WHERE a IS NOT NULL
)
SELECT src,
       count(*) AS addresses,
       count(*) FILTER (WHERE p IS NOT NULL AND length(p[2]) <= 100) AS will_split,
       count(*) FILTER (WHERE p IS NOT NULL AND length(p[2]) > 100) AS skipped_by_length_guard,
       max(length(p[2])) FILTER (WHERE p IS NOT NULL AND length(p[2]) <= 100) AS max_city_len,
       max(length(p[3])) FILTER (WHERE p IS NOT NULL) AS max_state_len,
       max(length(p[4])) FILTER (WHERE p IS NOT NULL) AS max_zip_len
FROM parsed
GROUP BY src
UNION ALL
SELECT 'manufacturer_profile (d5a1c9e3f7b4)', count(*),
       count(*) FILTER (WHERE coalesce(length(trim(address)), 0) <= 255 AND coalesce(length(trim(city)), 0) <= 100
                          AND coalesce(length(trim(state)), 0) <= 100 AND coalesce(length(trim(zip_code)), 0) <= 10),
       count(*) FILTER (WHERE NOT (coalesce(length(trim(address)), 0) <= 255 AND coalesce(length(trim(city)), 0) <= 100
                          AND coalesce(length(trim(state)), 0) <= 100 AND coalesce(length(trim(zip_code)), 0) <= 10)),
       NULL, NULL, NULL
FROM manufacturer_profile
WHERE deleted_at IS NULL AND coalesce(trim(address), '') <> ''
ORDER BY 1;
\echo ##### PRE_5286_phone_backfill [N53（同迁移）；无编号（长度）]
WITH maxlen AS (
  SELECT character_maximum_length AS n FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'company_phone_number' AND column_name = 'phone_number'
),
cand AS (
  SELECT btrim(c.phone_number) AS ph,
         EXISTS (SELECT 1 FROM company_phone_number p WHERE p.company_id = c.id AND p.deleted_at IS NOT NULL) AS has_deleted_rows
  FROM company c
  WHERE c.deleted_at IS NULL AND nullif(btrim(c.phone_number), '') IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM company_phone_number p WHERE p.company_id = c.id AND p.deleted_at IS NULL)
  UNION ALL SELECT btrim(phone_number), false FROM store
            WHERE deleted_at IS NULL AND nullif(btrim(phone_number), '') IS NOT NULL
  UNION ALL SELECT btrim(phone_number), false FROM restaurant
            WHERE deleted_at IS NULL AND nullif(btrim(phone_number), '') IS NOT NULL
  UNION ALL SELECT btrim(phone_number), false FROM manufacturer_subdivision
            WHERE deleted_at IS NULL AND nullif(btrim(phone_number), '') IS NOT NULL
)
SELECT (SELECT n FROM maxlen) AS phone_column_max_len,
       count(*) AS rows_to_insert,
       count(*) FILTER (WHERE length(ph) > coalesce((SELECT n FROM maxlen), 2147483647)) AS too_long_insert_fails,
       count(*) FILTER (WHERE has_deleted_rows) AS companies_with_only_deleted_phone_rows,
       (SELECT string_agg(indexdef, ' | ') FROM pg_indexes
         WHERE schemaname = 'public' AND tablename = 'company_phone_number' AND indexdef LIKE 'CREATE UNIQUE%') AS unique_indexes
FROM cand;
\echo ##### PRE_f2a7_company_billing_merge [N61（同迁移）；无编号（ON CONFLICT 重复命中、长度）]
WITH b AS (
  SELECT company_id, nullif(trim(name), '') AS n, nullif(trim(email), '') AS e, nullif(trim(phone_number), '') AS p
  FROM company_billing
  WHERE deleted_at IS NULL
    AND (coalesce(trim(name), '') <> '' OR coalesce(trim(email), '') <> '' OR coalesce(trim(phone_number), '') <> '')
)
SELECT count(*) AS rows_to_merge,
       (SELECT count(*) FROM (SELECT company_id FROM b GROUP BY company_id HAVING count(*) > 1) d) AS companies_with_several_rows_fails,
       count(*) FILTER (WHERE length(n) > 255 OR length(e) > 254 OR length(p) > 64) AS too_long_fails,
       count(*) FILTER (WHERE NOT EXISTS (SELECT 1 FROM company c WHERE c.id = b.company_id)) AS company_orphans
FROM b;
\echo ##### PRE_c4d8_invitation_codes [N97（同迁移）；无编号（invitation_code UNIQUE、长度、外键）]
WITH inv AS (
  SELECT s.invitation_code AS code, c.id AS company_id, c.name, c.address, c.email, c.phone_number,
         coalesce(s.invitation_code_used_by_user_id, c.user_id) AS used_by
  FROM client cl
  JOIN company_subscription s ON s.id = cl.company_subscription_id
  JOIN company c ON c.id = s.company_id
  WHERE s.invitation_code IS NOT NULL
  UNION ALL
  SELECT s.invitation_code, c.id, c.name, c.address, c.email, c.phone_number,
         coalesce(s.invitation_code_used_by_user_id, c.user_id)
  FROM company_subscription s
  JOIN company c ON c.id = s.company_id
  WHERE s.invitation_code IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM client cl WHERE cl.company_subscription_id = s.id)
)
SELECT
  count(*) AS invitation_rows_upper_bound,
  (SELECT count(*) FROM (SELECT code FROM inv GROUP BY code HAVING count(*) > 1) d) AS dup_codes_unique_fails,
  (SELECT count(*) FROM (SELECT company_subscription_id FROM client WHERE company_subscription_id IS NOT NULL
                         GROUP BY company_subscription_id HAVING count(*) > 1) d) AS subscriptions_shared_by_clients,
  count(*) FILTER (WHERE length(inv.code) > 50) AS code_over_50,
  count(*) FILTER (WHERE length(inv.name) > 255) AS name_over_255,
  count(*) FILTER (WHERE length(inv.address) > 255) AS address_over_255_upper_bound,
  count(*) FILTER (WHERE length(inv.email) > 254) AS email_over_254,
  count(*) FILTER (WHERE length(inv.phone_number) > 64
                   OR EXISTS (SELECT 1 FROM company_phone_number p
                              WHERE p.company_id = inv.company_id AND p.deleted_at IS NULL AND length(p.phone_number) > 64)) AS phone_over_64,
  count(*) FILTER (WHERE inv.used_by IS NOT NULL
                   AND NOT EXISTS (SELECT 1 FROM "user" u WHERE u.id = inv.used_by)) AS used_by_user_fk_orphans
FROM inv;
\echo ##### PRE_049461_orphan_accounts [F50 / N97（049461d68471 孤儿账号检查；c4d8e2a6f1b3 硬删公司）]
WITH admin_born AS (
  SELECT DISTINCT a.company_id
  FROM company_audit_log a JOIN company c ON c.id = a.company_id
  WHERE a.action::text = 'created' AND a.entity_type::text IN ('company', 'subscription')
    AND abs(extract(epoch FROM a.created_at - c.created_at)) < 120
),
client_link AS (
  SELECT s.company_id FROM client cl JOIN company_subscription s ON s.id = cl.company_subscription_id
),
top_rows AS (
  SELECT c.id, c.type::text AS type, c.name, c.address, c.user_id, NULL::text AS company_status, c.created_at,
         'company' AS kind
  FROM company c WHERE c.deleted_at IS NULL
  UNION ALL
  SELECT r.id, 'CLIENT', r.name, r.address, NULL::uuid, r.status::text, r.created_at, 'restaurant_without_company'
  FROM restaurant r WHERE r.company_id IS NULL AND r.deleted_at IS NULL
),
base AS (
  SELECT t.id, t.type, t.kind,
         lower(regexp_replace(btrim(coalesce(t.name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(t.address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM top_rows t
  WHERE t.created_at >= '2026-09-17'
    AND t.type IN ('CLIENT', 'VENDOR')
    AND t.id NOT IN (SELECT company_id FROM admin_born)
    AND coalesce(t.company_status, '') NOT IN ('UNREGISTERED', 'UNREGISTERED_WITH_ORDERS')
    AND t.user_id IS NULL
    AND NOT EXISTS (SELECT 1 FROM company_subscription s
                    WHERE s.company_id = t.id AND s.invitation_code_used_at IS NOT NULL)
),
v_tmp AS (
  SELECT DISTINCT lower(regexp_replace(btrim(coalesce(temporary_name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(temporary_address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM client WHERE store_id IS NOT NULL
),
r_tmp AS (
  SELECT DISTINCT lower(regexp_replace(btrim(coalesce(name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM client_temporary_store
),
doomed AS (
  SELECT b.id, b.kind FROM base b
  WHERE (b.type = 'CLIENT' AND b.id IN (SELECT company_id FROM client_link))
     OR (b.type = 'CLIENT' AND b.nm <> '' AND b.street <> ''
         AND EXISTS (SELECT 1 FROM v_tmp v WHERE v.nm = b.nm AND v.street = b.street))
     OR (b.type = 'VENDOR' AND b.nm = '')
     OR (b.type = 'VENDOR' AND b.nm <> '' AND b.street <> ''
         AND EXISTS (SELECT 1 FROM r_tmp r WHERE r.nm = b.nm AND r.street = b.street))
),
members AS (
  SELECT company_id AS biz FROM company_member
  UNION ALL SELECT manufacturer_subdivision_id FROM manufacturer_subdivision_member
  UNION ALL SELECT restaurant_id FROM restaurant_member
  UNION ALL SELECT store_id FROM store_member
)
SELECT
  (SELECT count(*) FROM doomed WHERE kind = 'company') AS doomed_companies,
  (SELECT count(*) FROM doomed WHERE kind <> 'company') AS doomed_restaurants_without_company,
  (SELECT count(*) FROM members m JOIN doomed d ON d.id = m.biz) AS accounts_in_deleted_companies_fails,
  (SELECT count(*) FROM members m
    WHERE NOT EXISTS (SELECT 1 FROM company c WHERE c.id = m.biz)
      AND NOT EXISTS (SELECT 1 FROM store s WHERE s.id = m.biz)
      AND NOT EXISTS (SELECT 1 FROM restaurant r WHERE r.id = m.biz)
      AND NOT EXISTS (SELECT 1 FROM manufacturer_subdivision ms WHERE ms.id = m.biz)) AS accounts_without_business_fails,
  (SELECT count(*) FROM doomed d
    WHERE EXISTS (SELECT 1 FROM store s WHERE s.company_id = d.id)
       OR EXISTS (SELECT 1 FROM restaurant r WHERE r.company_id = d.id)) AS doomed_with_children,
  (SELECT string_agg(DISTINCT confdeltype::text, ',') FROM pg_constraint
    WHERE contype = 'f' AND conrelid = 'company'::regclass AND confrelid = 'company'::regclass) AS company_parent_fk_on_delete,
  (SELECT string_agg(conrelid::regclass::text, ',' ORDER BY conrelid::regclass::text) FROM pg_constraint
    WHERE contype = 'f' AND confrelid = 'company'::regclass AND confdeltype IN ('a', 'r')) AS restrict_fks_to_company_now;
\echo ##### PRE_catalog_misc [无编号（049461d68471 assert、7c1e4a9d2b58 DROP TYPE、1f7c3a9e5b28 改名撞名、未验证外键、视图依赖）]
WITH t(tbl) AS (VALUES ('user'), ('user_action_log'), ('sign_in_data'), ('sign_up_data')),
names AS (
  SELECT t.tbl, c.conname::text AS name FROM t JOIN pg_constraint c ON c.conrelid = to_regclass(quote_ident(t.tbl))
  UNION
  SELECT t.tbl, i.indexname::text FROM t JOIN pg_indexes i ON i.schemaname = 'public' AND i.tablename = t.tbl
),
sp_names AS (
  SELECT conname::text AS name FROM pg_constraint WHERE conrelid = to_regclass('store_product')
  UNION
  SELECT ic.relname::text FROM pg_index x JOIN pg_class ic ON ic.oid = x.indexrelid
  WHERE x.indrelid = to_regclass('store_product')
),
sp_renamed AS (
  SELECT name,
         left(regexp_replace(regexp_replace(regexp_replace(regexp_replace(name,
           '^store_product_', 'product_'), '^(ix|ck|fk)_store_product_', '\1_product_'),
           '_store_id_', '_company_id_'), '_vendor_product_id_', '_deprecated_vendor_product_id_'), 63) AS new_name
  FROM sp_names
)
SELECT 'name_too_long_after_049461_rename' AS problem, n.tbl || ':' || n.name AS detail
FROM names n
WHERE length(n.name) + 7 > 63
  AND EXISTS (SELECT 1 FROM unnest(ARRAY['', 'uq_', 'ix_', 'fk_', 'pk_', 'ck_']) AS p(prefix)
              WHERE left(n.name, length(p.prefix || n.tbl) + 1) = p.prefix || n.tbl || '_')
UNION ALL
SELECT 'actiontype_used_elsewhere', c.table_name::text || '.' || c.column_name::text
FROM information_schema.columns c
WHERE c.table_schema = 'public' AND c.udt_name::text IN ('actiontype', '_actiontype')
  AND NOT (c.table_name::text = 'user_action_log' AND c.column_name::text = 'action')
UNION ALL
SELECT 'store_product_rename_collides', r.name || ' -> ' || r.new_name
FROM sp_renamed r
WHERE r.new_name <> r.name
  AND EXISTS (SELECT 1 FROM pg_class k
              WHERE k.relname = r.new_name AND k.relnamespace = 'public'::regnamespace
                AND k.oid NOT IN (SELECT x.indexrelid FROM pg_index x WHERE x.indrelid = to_regclass('deprecated_product')))
UNION ALL
SELECT 'fk_not_validated', conrelid::regclass::text || ':' || conname
FROM pg_constraint
WHERE contype = 'f' AND NOT convalidated AND connamespace = 'public'::regnamespace
UNION ALL
SELECT 'view_present', schemaname || '.' || viewname FROM pg_views WHERE schemaname = 'public'
UNION ALL
SELECT 'matview_present', schemaname || '.' || matviewname FROM pg_matviews WHERE schemaname = 'public'
ORDER BY 1, 2
LIMIT 20;
\echo ##### PRE_fe79_client_bill_to_lengths [N140（同迁移）；无编号（varchar 超长）]
WITH src AS (
  SELECT cl.id,
         coalesce(cl.restaurant_id IS NULL OR r.status::text IN ('UNREGISTERED', 'UNREGISTERED_WITH_ORDERS'), false) AS unregistered,
         cl.temporary_name, cl.temporary_address, r.name AS rname, r.address AS raddr
  FROM client cl LEFT JOIN restaurant r ON r.id = cl.restaurant_id
),
fc AS (
  SELECT DISTINCT ON (client_id) client_id, name, phone_number, email
  FROM client_restaurant_contact
  WHERE deleted_at IS NULL
  ORDER BY client_id, created_at, id
)
SELECT
  count(*) AS clients,
  count(*) FILTER (WHERE length(CASE WHEN s.unregistered THEN coalesce(nullif(trim(s.temporary_name), ''), s.rname)
                                     ELSE s.rname END) > 255) AS company_name_over_255,
  count(*) FILTER (WHERE length(CASE WHEN s.unregistered THEN coalesce(nullif(trim(s.temporary_address), ''), s.raddr)
                                     ELSE s.raddr END) > 255) AS address_over_255_upper_bound,
  count(*) FILTER (WHERE s.unregistered AND length(fc.name) > 255) AS contact_name_over_255,
  count(*) FILTER (WHERE s.unregistered AND length(fc.phone_number) > 64) AS contact_phone_over_64,
  count(*) FILTER (WHERE s.unregistered AND length(fc.email) > 254) AS contact_email_over_254,
  (SELECT count(*) FROM "user" u WHERE length(u.phone_number) > 64 OR length(u.email) > 254) AS any_user_phone_or_email_too_long
FROM src s LEFT JOIN fc ON fc.client_id = s.id;
\echo ##### PRE_b4d8_logo_to_file [无编号（b4d8f2a6c0e1 logo 复制进 file）]
WITH ml AS (
  SELECT column_name::text AS col, character_maximum_length AS n FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'file' AND column_name IN ('module_type', 'file_type', 'status')
),
used_logo AS (
  SELECT l.id, l.filename, l.file_url FROM logo l
  WHERE l.id IN (SELECT logo_id FROM company WHERE logo_id IS NOT NULL
                 UNION SELECT logo_id FROM store WHERE logo_id IS NOT NULL)
)
SELECT
  (SELECT n FROM ml WHERE col = 'module_type') AS module_type_max_len,
  (SELECT n FROM ml WHERE col = 'file_type') AS file_type_max_len,
  (SELECT n FROM ml WHERE col = 'status') AS status_max_len,
  (SELECT count(*) FROM used_logo) AS logos_to_copy,
  (SELECT count(*) FROM used_logo u
    WHERE length(lower(coalesce(substring(u.filename FROM '\.([A-Za-z0-9]{1,16})$'),
                                substring(u.file_url FROM '\.([A-Za-z0-9]{1,16})$'))))
          > coalesce((SELECT n FROM ml WHERE col = 'file_type'), 2147483647)) AS extension_too_long_fails,
  (SELECT count(*) FROM used_logo u WHERE EXISTS (SELECT 1 FROM file f WHERE f.id = u.id)) AS logo_id_taken_in_file_info;
\echo ##### PRE_unique_index_catalog [无编号（d51500b2df5e 去重键、4c8e2a6f9b17 ON CONFLICT 目标、36cd67a87d67 / 8b980708773e 恢复软删公司、f2c8a4e6d1b7、1e76218f5233 等）]
SELECT tablename, string_agg(indexdef, ' | ' ORDER BY indexname) AS unique_indexes
FROM pg_indexes
WHERE schemaname = 'public' AND indexdef LIKE 'CREATE UNIQUE%'
  AND tablename IN ('company', 'company_role_permission', 'notification', 'company_contact_person', 'store_delivery',
                    'company_member', 'store_member', 'restaurant_member', 'manufacturer_subdivision_member',
                    'invoice', 'master_invoice', 'client_invoice', 'client_master_invoice', 'chat_member',
                    'manufacturer_subdivision_product', 'company_subscription', 'company_company_type', 'role')
GROUP BY tablename
ORDER BY tablename
LIMIT 20;
\echo ##### PRE_N14_buying_group_table [N14（d3b8f1a6c592 忽略大小写唯一）]
SELECT
  to_regclass('company_buying_group') IS NULL AS company_buying_group_absent,
  to_regclass('company_info_buying_group') IS NULL AS company_info_buying_group_absent;
\echo ##### N99_custom_matrix_pre [N99]
WITH live_company AS (
  SELECT c.id, c.type::text AS ctype FROM company c WHERE c.deleted_at IS NULL
),
cell AS (
  SELECT crp.company_id, crp.role_id, p.type || '/' || e.name AS cell_key
  FROM company_role_permission crp
  JOIN live_company lc ON lc.id = crp.company_id
  JOIN permission p ON p.id = crp.permission_id
  JOIN api_entity e ON e.id = crp.entity_id
  WHERE crp.deleted_at IS NULL
),
role_sig AS (
  SELECT company_id, role_id,
         md5(string_agg(DISTINCT cell_key, ',' ORDER BY cell_key)) AS sig,
         count(DISTINCT cell_key) AS n_cells
  FROM cell
  GROUP BY company_id, role_id
),
has_matrix AS (
  SELECT DISTINCT rs.company_id, lc.ctype
  FROM role_sig rs JOIN live_company lc ON lc.id = rs.company_id
),
type_roles AS (
  SELECT DISTINCT hm.ctype, rs.role_id
  FROM role_sig rs JOIN has_matrix hm ON hm.company_id = rs.company_id
),
full_sig AS (
  SELECT hm.company_id, hm.ctype, tr.role_id,
         coalesce(rs.sig, 'none') AS sig,
         coalesce(rs.n_cells, 0) AS n_cells
  FROM has_matrix hm
  JOIN type_roles tr ON tr.ctype = hm.ctype
  LEFT JOIN role_sig rs ON rs.company_id = hm.company_id AND rs.role_id = tr.role_id
),
mode_sig AS (
  SELECT DISTINCT ON (ctype, role_id) ctype, role_id, sig, n_cells
  FROM (
    SELECT ctype, role_id, sig, n_cells, count(*) AS cnt
    FROM full_sig GROUP BY ctype, role_id, sig, n_cells
  ) x
  ORDER BY ctype, role_id, cnt DESC, sig
),
cmp AS (
  SELECT f.company_id,
         f.sig <> m.sig AS differs,
         f.n_cells < m.n_cells AS tighter,
         f.n_cells > m.n_cells AS looser
  FROM full_sig f
  JOIN mode_sig m ON m.ctype = f.ctype AND m.role_id = f.role_id
)
SELECT lc.ctype AS company_type,
  count(DISTINCT lc.id) AS live_companies,
  count(DISTINCT cmp.company_id) AS companies_with_matrix,
  count(DISTINCT cmp.company_id) FILTER (WHERE cmp.differs) AS companies_customized,
  count(*) FILTER (WHERE cmp.differs) AS company_roles_customized,
  count(*) FILTER (WHERE cmp.tighter) AS company_roles_tighter_than_mode,
  count(*) FILTER (WHERE cmp.looser) AS company_roles_looser_than_mode,
  count(*) FILTER (WHERE cmp.differs AND NOT cmp.tighter AND NOT cmp.looser) AS company_roles_same_size_other_cells
FROM live_company lc
LEFT JOIN cmp ON cmp.company_id = lc.id
GROUP BY lc.ctype
ORDER BY lc.ctype
LIMIT 20;
\echo ##### N99_zero_perm_pre [N99]
WITH role_c AS (
  SELECT r.id, r.name, r.type::text AS grp, r.belongs_to_company, r.deleted_at, r.created_at,
         btrim(regexp_replace(lower(r.name), '[^a-z0-9]+', '_', 'g'), '_') AS code
  FROM role r
),
ceo_added AS (
  SELECT g.grp FROM (SELECT DISTINCT grp FROM role_c) g
  WHERE NOT EXISTS (SELECT 1 FROM role_c x WHERE x.grp = g.grp AND x.code = 'ceo' AND NOT x.belongs_to_company)
),
template_name AS (
  SELECT DISTINCT grp, name FROM role_c WHERE NOT belongs_to_company AND deleted_at IS NULL
  UNION
  SELECT grp, 'CEO' FROM ceo_added
),
acc AS (
  SELECT 'company'::text AS kind, m.id, m.company_id AS biz_id, m.role_id, m.deleted_at, m.is_active,
         CASE c.type::text WHEN 'CLIENT' THEN 'BUYER' ELSE c.type::text END AS company_grp,
         c.deleted_at IS NULL AS biz_live
  FROM company_member m JOIN company c ON c.id = m.company_id
  UNION ALL
  SELECT 'store', m.id, m.store_id, m.role_id, m.deleted_at, m.is_active, 'VENDOR', s.deleted_at IS NULL
  FROM store_member m JOIN store s ON s.id = m.store_id
  UNION ALL
  SELECT 'restaurant', m.id, m.restaurant_id, m.role_id, m.deleted_at, m.is_active, 'BUYER', rs.deleted_at IS NULL
  FROM restaurant_member m JOIN restaurant rs ON rs.id = m.restaurant_id
  UNION ALL
  SELECT 'subdivision', m.id, m.manufacturer_subdivision_id, m.role_id, m.deleted_at, m.is_active, 'MANUFACTURER',
         ms.deleted_at IS NULL
  FROM manufacturer_subdivision_member m JOIN manufacturer_subdivision ms ON ms.id = m.manufacturer_subdivision_id
),
final_role AS (
  SELECT a.kind, a.biz_id, a.company_grp, a.biz_live,
    CASE WHEN rc.belongs_to_company THEN coalesce(
        (SELECT f.name FROM role_c f
         WHERE f.grp = rc.grp AND f.code = rc.code AND NOT f.belongs_to_company AND f.deleted_at IS NULL
         ORDER BY f.created_at, f.id LIMIT 1),
        CASE WHEN rc.code = 'ceo' AND rc.grp IN (SELECT grp FROM ceo_added) THEN 'CEO' END)
      ELSE rc.name END AS role_name
  FROM acc a JOIN role_c rc ON rc.id = a.role_id
  WHERE a.deleted_at IS NULL AND a.is_active
),
flag AS (
  SELECT fr.*,
    (fr.role_name IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM template_name t WHERE t.grp = fr.company_grp AND t.name = fr.role_name)) AS no_template
  FROM final_role fr
)
SELECT kind,
  count(*) AS live_accounts,
  count(*) FILTER (WHERE biz_live) AS live_accounts_in_live_business,
  count(*) FILTER (WHERE role_name IS NULL) AS company_role_without_facility_match,
  count(*) FILTER (WHERE no_template) AS accounts_zero_permission_after_upgrade,
  count(*) FILTER (WHERE no_template AND biz_live) AS zero_permission_in_live_business,
  count(DISTINCT biz_id) FILTER (WHERE no_template AND biz_live) AS businesses_affected,
  count(DISTINCT biz_id::text || '|' || role_name) FILTER (WHERE no_template AND biz_live) AS company_roles_without_template
FROM flag
GROUP BY kind
ORDER BY kind
LIMIT 20;
\echo ##### N119_ceo_gap_pre [N119]
WITH ct_code(name, code) AS (VALUES
  ('Food Vendor','Food_Vendor'), ('Liquor Vendor','Liquor_Vendor'), ('E&S Dealer','E&S_Dealer'),
  ('Broadliner Dealer','Broadliner_Dealer'), ('Food Manufacturer','Food_Manufacturer'),
  ('E&S Manufacturer','E&S_Manufacturer'), ('Restaurant','Restaurant')),
eff_cct AS (
  SELECT cct.company_id, ct.name, ct.category::text AS category
  FROM company_company_type cct
  JOIN company_type ct ON ct.id = cct.company_type_id
  WHERE cct.deleted_at IS NULL
  UNION ALL
  SELECT c.id, ct.name, ct.category::text
  FROM company c
  JOIN company_type ct ON ct.name = CASE
      WHEN c.type::text = 'CLIENT' THEN 'Restaurant'
      WHEN c.type::text = 'VENDOR' AND c.created_at < '2026-09-01 00:00:00+08' THEN 'Food Vendor'
      WHEN c.type::text = 'MANUFACTURER' THEN 'E&S Manufacturer'
    END
  WHERE NOT EXISTS (SELECT 1 FROM company_company_type x WHERE x.company_id = c.id)
),
first_type AS (
  SELECT DISTINCT ON (e.company_id, e.category) e.company_id, e.category, m.code
  FROM eff_cct e
  LEFT JOIN ct_code m ON m.name = e.name
  ORDER BY e.company_id, e.category, e.name
),
child AS (
  SELECT 'VENDOR'::text AS cat, 'Food_Vendor'::text AS default_code, t.company_id AS parent_id, t.deleted_at FROM store t
  UNION ALL
  SELECT 'CLIENT', 'Restaurant', t.company_id, t.deleted_at FROM restaurant t
  UNION ALL
  SELECT 'MANUFACTURER', 'Food_Manufacturer', t.manufacturer_company_id, t.deleted_at FROM manufacturer_subdivision t
),
has_child AS (SELECT DISTINCT parent_id FROM child WHERE parent_id IS NOT NULL),
owner_acc AS (SELECT DISTINCT company_id, user_id FROM company_member),
top_co AS (
  SELECT coalesce(ft.code, CASE c.type::text WHEN 'CLIENT' THEN 'Restaurant' WHEN 'VENDOR' THEN 'Food_Vendor' ELSE 'Food_Manufacturer' END) AS company_type,
    CASE
      WHEN c.type::text = 'MANUFACTURER' THEN true
      WHEN hc.parent_id IS NOT NULL THEN (c.user_id IS NOT NULL AND oa.company_id IS NULL)
      ELSE c.deleted_at IS NULL
    END AS alive
  FROM company c
  LEFT JOIN first_type ft ON ft.company_id = c.id AND ft.category = c.type::text
  LEFT JOIN has_child hc ON hc.parent_id = c.id
  LEFT JOIN owner_acc oa ON oa.company_id = c.id AND oa.user_id = c.user_id
),
kids AS (
  SELECT coalesce(ft.code, ch.default_code) AS company_type, ch.deleted_at IS NULL AS alive
  FROM child ch
  LEFT JOIN first_type ft ON ft.company_id = ch.parent_id AND ft.category = ch.cat
),
allc AS (
  SELECT company_type, alive FROM top_co
  UNION ALL
  SELECT company_type, alive FROM kids
)
SELECT company_type AS bucket,
  count(*) FILTER (WHERE alive) AS alive_after_upgrade,
  count(*) AS company_rows_after_upgrade,
  CASE WHEN company_type IN ('Food_Vendor','Liquor_Vendor','E&S_Dealer','Broadliner_Dealer') THEN 5 ELSE 0 END AS ceo_missing_shipping_nodes_each
FROM allc
GROUP BY company_type
UNION ALL
SELECT 'notif_ceo_email_on:' || CASE WHEN r.belongs_to_company THEN 'company_level' ELSE 'facility_level' END,
  count(*), count(DISTINCT n.company_id), NULL
FROM notification n
JOIN role r ON r.id = n.role_id
WHERE n.type::text = 'EMAIL' AND n.is_on AND n.deleted_at IS NULL AND r.name = 'CEO'
GROUP BY r.belongs_to_company
ORDER BY 1
LIMIT 20;
\echo ##### N7_names_pre [N7]
WITH m AS (
  SELECT id, user_id, first_name, last_name, deleted_at, is_active FROM company_member
  UNION ALL SELECT id, user_id, first_name, last_name, deleted_at, is_active FROM store_member
  UNION ALL SELECT id, user_id, first_name, last_name, deleted_at, is_active FROM restaurant_member
  UNION ALL SELECT id, user_id, first_name, last_name, deleted_at, is_active FROM manufacturer_subdivision_member
),
commenters AS (
  SELECT x.id
  FROM order_comment oc
  CROSS JOIN LATERAL (VALUES (oc.company_member_id), (oc.restaurant_member_id), (oc.store_member_id),
                             (oc.updated_by_company_member_id), (oc.updated_by_store_member_id)) AS x(id)
  WHERE oc.deleted_at IS NULL AND x.id IS NOT NULL
)
SELECT
  (SELECT count(*) FROM m WHERE first_name IS NULL OR last_name IS NULL) AS members_with_null_name,
  (SELECT count(*) FROM m WHERE btrim(first_name) = '') AS members_first_name_blank,
  (SELECT count(*) FROM m WHERE deleted_at IS NULL AND is_active
     AND btrim(first_name) = '' AND btrim(last_name) = '') AS live_members_both_names_blank,
  (SELECT count(DISTINCT c.id) FROM commenters c JOIN m ON m.id = c.id
     WHERE btrim(m.first_name) = '') AS blank_first_name_comment_authors,
  (SELECT count(*) FROM "user" u
     WHERE u.deleted_at IS NULL AND NOT EXISTS (SELECT 1 FROM m WHERE m.user_id = u.id)) AS live_users_without_any_member,
  (SELECT count(*) FROM (
     SELECT user_id FROM m WHERE deleted_at IS NULL
     GROUP BY user_id
     HAVING count(DISTINCT coalesce(first_name, '') || '|' || coalesce(last_name, '')) > 1
   ) d) AS users_with_different_names_across_live_accounts;
\echo ##### F13_type_rule_pre [F13]
WITH ct_code(name, code) AS (VALUES
  ('Food Vendor','Food_Vendor'), ('Liquor Vendor','Liquor_Vendor'), ('E&S Dealer','E&S_Dealer'),
  ('Broadliner Dealer','Broadliner_Dealer'), ('Food Manufacturer','Food_Manufacturer'),
  ('E&S Manufacturer','E&S_Manufacturer'), ('Restaurant','Restaurant')),
live_cct AS (
  SELECT cct.company_id, ct.name, ct.category::text AS category
  FROM company_company_type cct
  JOIN company_type ct ON ct.id = cct.company_type_id
  WHERE cct.deleted_at IS NULL
),
backfill AS (
  SELECT c.id AS company_id, ct.name, ct.category::text AS category
  FROM company c
  JOIN company_type ct ON ct.name = CASE
      WHEN c.type::text = 'CLIENT' THEN 'Restaurant'
      WHEN c.type::text = 'VENDOR' AND c.created_at < '2026-09-01 00:00:00+08' THEN 'Food Vendor'
      WHEN c.type::text = 'MANUFACTURER' THEN 'E&S Manufacturer'
    END
  WHERE NOT EXISTS (SELECT 1 FROM company_company_type x WHERE x.company_id = c.id)
),
eff AS (
  SELECT company_id, name, category FROM live_cct
  UNION ALL
  SELECT company_id, name, category FROM backfill
),
first_own AS (
  SELECT DISTINCT ON (e.company_id) e.company_id, m.code
  FROM eff e
  JOIN company c ON c.id = e.company_id AND e.category = c.type::text
  LEFT JOIN ct_code m ON m.name = e.name
  ORDER BY e.company_id, e.name
),
per AS (
  SELECT c.id, c.type::text AS ctype, c.deleted_at IS NULL AS is_live,
    count(l.company_id) AS n_live,
    count(l.company_id) FILTER (WHERE l.category = c.type::text) AS n_own
  FROM company c
  LEFT JOIN live_cct l ON l.company_id = c.id
  GROUP BY c.id, c.type, c.deleted_at
),
any_row AS (SELECT DISTINCT company_id FROM company_company_type),
bf AS (SELECT DISTINCT company_id FROM backfill),
kids AS (
  SELECT parent_id, count(*) AS n FROM (
    SELECT company_id AS parent_id FROM store WHERE deleted_at IS NULL
    UNION ALL SELECT company_id FROM restaurant WHERE deleted_at IS NULL AND company_id IS NOT NULL
    UNION ALL SELECT manufacturer_company_id FROM manufacturer_subdivision WHERE deleted_at IS NULL
  ) x
  GROUP BY parent_id
),
pred AS (
  SELECT p.ctype, p.is_live, p.n_live, coalesce(k.n, 0) AS live_children,
    CASE
      WHEN p.n_own > 1 THEN 'own_category_multiple:first_by_name'
      WHEN p.n_own = 1 THEN 'own_category_single'
      WHEN bf.company_id IS NOT NULL THEN 'no_rows:backfilled_by_083296a8b071'
      WHEN ar.company_id IS NULL THEN 'no_rows:not_backfilled->default'
      WHEN p.n_live = 0 THEN 'only_deleted_rows->default'
      ELSE 'only_other_category->default'
    END AS rule,
    coalesce(fo.code, CASE p.ctype WHEN 'CLIENT' THEN 'Restaurant' WHEN 'VENDOR' THEN 'Food_Vendor' ELSE 'Food_Manufacturer' END) AS predicted_company_type
  FROM per p
  LEFT JOIN bf ON bf.company_id = p.id
  LEFT JOIN any_row ar ON ar.company_id = p.id
  LEFT JOIN first_own fo ON fo.company_id = p.id
  LEFT JOIN kids k ON k.parent_id = p.id
)
SELECT ctype, rule, predicted_company_type,
  count(*) AS companies,
  count(*) FILTER (WHERE is_live) AS live_companies,
  count(*) FILTER (WHERE n_live > 1) AS with_multiple_live_types,
  sum(live_children) AS live_children_under_them
FROM pred
GROUP BY ctype, rule, predicted_company_type
ORDER BY ctype, companies DESC
LIMIT 20;
\echo ##### F17_copies_pre [F17]
WITH ct_code(name, code, grp) AS (VALUES
  ('Food Vendor','Food_Vendor','VENDOR'), ('Liquor Vendor','Liquor_Vendor','VENDOR'), ('E&S Dealer','E&S_Dealer','VENDOR'),
  ('Broadliner Dealer','Broadliner_Dealer','VENDOR'), ('Food Manufacturer','Food_Manufacturer','MANUFACTURER'),
  ('E&S Manufacturer','E&S_Manufacturer','MANUFACTURER'), ('Restaurant','Restaurant','BUYER')),
eff_cct AS (
  SELECT cct.company_id, ct.name, ct.category::text AS category
  FROM company_company_type cct
  JOIN company_type ct ON ct.id = cct.company_type_id
  WHERE cct.deleted_at IS NULL
  UNION ALL
  SELECT c.id, ct.name, ct.category::text
  FROM company c
  JOIN company_type ct ON ct.name = CASE
      WHEN c.type::text = 'CLIENT' THEN 'Restaurant'
      WHEN c.type::text = 'VENDOR' AND c.created_at < '2026-09-01 00:00:00+08' THEN 'Food Vendor'
      WHEN c.type::text = 'MANUFACTURER' THEN 'E&S Manufacturer'
    END
  WHERE NOT EXISTS (SELECT 1 FROM company_company_type x WHERE x.company_id = c.id)
),
first_type AS (
  SELECT DISTINCT ON (e.company_id, e.category) e.company_id, e.category, m.code
  FROM eff_cct e
  LEFT JOIN ct_code m ON m.name = e.name
  ORDER BY e.company_id, e.category, e.name
),
kids AS (
  SELECT ch.kind, ch.id, ch.parent_id, coalesce(ft.code, ch.default_code) AS company_type
  FROM (
    SELECT 'store'::text AS kind, 'VENDOR'::text AS cat, 'Food_Vendor'::text AS default_code, t.id, t.company_id AS parent_id
    FROM store t WHERE t.deleted_at IS NULL
    UNION ALL
    SELECT 'restaurant', 'CLIENT', 'Restaurant', t.id, t.company_id
    FROM restaurant t WHERE t.deleted_at IS NULL AND t.company_id IS NOT NULL
    UNION ALL
    SELECT 'subdivision', 'MANUFACTURER', 'Food_Manufacturer', t.id, t.manufacturer_company_id
    FROM manufacturer_subdivision t WHERE t.deleted_at IS NULL
  ) ch
  LEFT JOIN first_type ft ON ft.company_id = ch.parent_id AND ft.category = ch.cat
),
role_c AS (
  SELECT r.id, r.type::text AS grp, r.belongs_to_company, r.deleted_at,
         btrim(regexp_replace(lower(r.name), '[^a-z0-9]+', '_', 'g'), '_') AS code
  FROM role r
),
fac_avail AS (
  SELECT DISTINCT grp, code FROM role_c WHERE NOT belongs_to_company AND deleted_at IS NULL
  UNION
  SELECT g.grp, 'ceo' FROM (SELECT DISTINCT grp FROM role_c) g
  WHERE NOT EXISTS (SELECT 1 FROM role_c x WHERE x.grp = g.grp AND x.code = 'ceo' AND NOT x.belongs_to_company)
),
member_any AS (
  SELECT DISTINCT user_id, biz_id FROM (
    SELECT user_id, store_id AS biz_id FROM store_member
    UNION ALL SELECT user_id, restaurant_id FROM restaurant_member
    UNION ALL SELECT user_id, manufacturer_subdivision_id FROM manufacturer_subdivision_member
  ) x
),
pairs AS (
  SELECT k.kind, cm.user_id, cm.deleted_at, cm.is_active,
         f.code IS NOT NULL AS has_role,
         ma.user_id IS NOT NULL AS has_account
  FROM company_member cm
  JOIN role_c rc ON rc.id = cm.role_id
  JOIN kids k ON k.parent_id = cm.company_id
  LEFT JOIN ct_code g ON g.code = k.company_type
  LEFT JOIN fac_avail f ON f.grp = g.grp AND f.code = rc.code
  LEFT JOIN member_any ma ON ma.user_id = cm.user_id AND ma.biz_id = k.id
)
SELECT kind,
  count(*) AS member_branch_pairs,
  count(*) FILTER (WHERE has_role AND NOT has_account) AS predicted_copies,
  count(*) FILTER (WHERE has_role AND NOT has_account AND deleted_at IS NOT NULL) AS copies_of_deleted_accounts,
  count(*) FILTER (WHERE has_role AND NOT has_account AND deleted_at IS NULL AND NOT is_active) AS copies_of_inactive_accounts,
  count(DISTINCT user_id) FILTER (WHERE has_role AND NOT has_account AND deleted_at IS NULL AND is_active) AS users_gaining_live_access,
  count(*) FILTER (WHERE NOT has_role AND NOT has_account AND deleted_at IS NULL AND is_active) AS live_pairs_skipped_no_same_code_role,
  count(*) FILTER (WHERE has_account) AS pairs_skipped_existing_account
FROM pairs
GROUP BY kind
ORDER BY kind
LIMIT 20;
\echo ##### F17_gap_pre [F17]
WITH ct_code(name, code, grp) AS (VALUES
  ('Food Vendor','Food_Vendor','VENDOR'), ('Liquor Vendor','Liquor_Vendor','VENDOR'), ('E&S Dealer','E&S_Dealer','VENDOR'),
  ('Broadliner Dealer','Broadliner_Dealer','VENDOR'), ('Food Manufacturer','Food_Manufacturer','MANUFACTURER'),
  ('E&S Manufacturer','E&S_Manufacturer','MANUFACTURER'), ('Restaurant','Restaurant','BUYER')),
eff_cct AS (
  SELECT cct.company_id, ct.name, ct.category::text AS category
  FROM company_company_type cct
  JOIN company_type ct ON ct.id = cct.company_type_id
  WHERE cct.deleted_at IS NULL
  UNION ALL
  SELECT c.id, ct.name, ct.category::text
  FROM company c
  JOIN company_type ct ON ct.name = CASE
      WHEN c.type::text = 'CLIENT' THEN 'Restaurant'
      WHEN c.type::text = 'VENDOR' AND c.created_at < '2026-09-01 00:00:00+08' THEN 'Food Vendor'
      WHEN c.type::text = 'MANUFACTURER' THEN 'E&S Manufacturer'
    END
  WHERE NOT EXISTS (SELECT 1 FROM company_company_type x WHERE x.company_id = c.id)
),
first_type AS (
  SELECT DISTINCT ON (e.company_id, e.category) e.company_id, e.category, m.code
  FROM eff_cct e
  LEFT JOIN ct_code m ON m.name = e.name
  ORDER BY e.company_id, e.category, e.name
),
child_all AS (
  SELECT t.company_id AS parent_id FROM store t
  UNION ALL SELECT t.company_id FROM restaurant t WHERE t.company_id IS NOT NULL
  UNION ALL SELECT t.manufacturer_company_id FROM manufacturer_subdivision t
),
kids AS (
  SELECT ch.id, ch.parent_id, coalesce(ft.code, ch.default_code) AS company_type
  FROM (
    SELECT 'VENDOR'::text AS cat, 'Food_Vendor'::text AS default_code, t.id, t.company_id AS parent_id
    FROM store t WHERE t.deleted_at IS NULL
    UNION ALL
    SELECT 'CLIENT', 'Restaurant', t.id, t.company_id
    FROM restaurant t WHERE t.deleted_at IS NULL AND t.company_id IS NOT NULL
    UNION ALL
    SELECT 'MANUFACTURER', 'Food_Manufacturer', t.id, t.manufacturer_company_id
    FROM manufacturer_subdivision t WHERE t.deleted_at IS NULL
  ) ch
  LEFT JOIN first_type ft ON ft.company_id = ch.parent_id AND ft.category = ch.cat
),
role_c AS (
  SELECT r.id, r.type::text AS grp, r.belongs_to_company, r.deleted_at,
         btrim(regexp_replace(lower(r.name), '[^a-z0-9]+', '_', 'g'), '_') AS code
  FROM role r
),
fac_avail AS (
  SELECT DISTINCT grp, code FROM role_c WHERE NOT belongs_to_company AND deleted_at IS NULL
  UNION
  SELECT g.grp, 'ceo' FROM (SELECT DISTINCT grp FROM role_c) g
  WHERE NOT EXISTS (SELECT 1 FROM role_c x WHERE x.grp = g.grp AND x.code = 'ceo' AND NOT x.belongs_to_company)
),
member_any AS (
  SELECT DISTINCT user_id, biz_id FROM (
    SELECT user_id, store_id AS biz_id FROM store_member
    UNION ALL SELECT user_id, restaurant_id FROM restaurant_member
    UNION ALL SELECT user_id, manufacturer_subdivision_id FROM manufacturer_subdivision_member
  ) x
),
member_live AS (
  SELECT DISTINCT user_id, biz_id FROM (
    SELECT user_id, store_id AS biz_id FROM store_member WHERE deleted_at IS NULL AND is_active
    UNION ALL SELECT user_id, restaurant_id FROM restaurant_member WHERE deleted_at IS NULL AND is_active
    UNION ALL SELECT user_id, manufacturer_subdivision_id FROM manufacturer_subdivision_member WHERE deleted_at IS NULL AND is_active
  ) x
),
owner_acc AS (SELECT DISTINCT company_id, user_id FROM company_member),
doomed AS (
  SELECT cm.id, cm.user_id, cm.company_id, rc.code
  FROM company_member cm
  JOIN company c ON c.id = cm.company_id
  JOIN role_c rc ON rc.id = cm.role_id
  LEFT JOIN owner_acc oa ON oa.company_id = c.id AND oa.user_id = c.user_id
  WHERE cm.deleted_at IS NULL AND cm.is_active AND c.deleted_at IS NULL
    AND c.type::text <> 'MANUFACTURER'
    AND c.id IN (SELECT parent_id FROM child_all)
    AND NOT (c.user_id IS NOT NULL AND oa.company_id IS NULL)
),
usable AS (
  SELECT DISTINCT d.id
  FROM doomed d
  JOIN kids k ON k.parent_id = d.company_id
  LEFT JOIN ct_code g ON g.code = k.company_type
  LEFT JOIN fac_avail f ON f.grp = g.grp AND f.code = d.code
  LEFT JOIN member_any ma ON ma.user_id = d.user_id AND ma.biz_id = k.id
  LEFT JOIN member_live ml ON ml.user_id = d.user_id AND ml.biz_id = k.id
  WHERE ml.user_id IS NOT NULL OR (ma.user_id IS NULL AND f.code IS NOT NULL)
)
SELECT
  count(*) AS live_members_of_parents_to_be_deleted,
  count(*) FILTER (WHERE u.id IS NULL) AS members_left_without_usable_branch_account,
  count(DISTINCT d.user_id) FILTER (WHERE u.id IS NULL) AS users_left_without_usable_branch_account,
  count(DISTINCT d.company_id) FILTER (WHERE u.id IS NULL) AS parent_companies_involved
FROM doomed d
LEFT JOIN usable u ON u.id = d.id;
\echo ##### N140_bill_to_pre [N140]
WITH role_c AS (
  SELECT r.id, r.name, r.type::text AS grp, r.belongs_to_company, r.deleted_at,
         btrim(regexp_replace(lower(r.name), '[^a-z0-9]+', '_', 'g'), '_') AS code
  FROM role r
),
buyer_ceo_ok AS (
  SELECT (EXISTS (SELECT 1 FROM role_c WHERE grp = 'BUYER' AND code = 'ceo' AND NOT belongs_to_company AND deleted_at IS NULL)
          OR NOT EXISTS (SELECT 1 FROM role_c WHERE grp = 'BUYER' AND code = 'ceo' AND NOT belongs_to_company)) AS ok
),
own_ceo AS (
  SELECT rm.restaurant_id AS company_id, rm.id AS account_id, rm.user_id, rm.is_active, rm.created_at, 0 AS src
  FROM restaurant_member rm
  JOIN role_c r ON r.id = rm.role_id
  WHERE rm.deleted_at IS NULL AND (r.name = 'CEO' OR (r.belongs_to_company AND r.code = 'ceo'))
),
copied_ceo AS (
  SELECT rs.id AS company_id, md5(cm.id::text || ':' || rs.id::text)::uuid AS account_id,
         cm.user_id, cm.is_active, NULL::timestamptz AS created_at, 1 AS src
  FROM restaurant rs
  JOIN company_member cm ON cm.company_id = rs.company_id AND cm.deleted_at IS NULL
  JOIN role_c r ON r.id = cm.role_id AND r.code = 'ceo'
  CROSS JOIN buyer_ceo_ok b
  WHERE b.ok AND rs.deleted_at IS NULL
    AND NOT EXISTS (SELECT 1 FROM restaurant_member x WHERE x.restaurant_id = rs.id AND x.user_id = cm.user_id)
),
ceo_owner AS (
  SELECT DISTINCT ON (company_id) company_id, account_id, user_id, is_active, src
  FROM (SELECT * FROM own_ceo UNION ALL SELECT * FROM copied_ceo) c
  ORDER BY company_id, src, created_at, account_id
),
cl AS (
  SELECT c.id, c.deleted_at, c.store_id, c.restaurant_id,
         coalesce(c.restaurant_id IS NULL OR r.status::text IN ('UNREGISTERED', 'UNREGISTERED_WITH_ORDERS'), false) AS unregistered
  FROM client c
  LEFT JOIN restaurant r ON r.id = c.restaurant_id
)
SELECT
  count(*) AS clients_total,
  count(*) FILTER (WHERE NOT cl.unregistered) AS registered_clients,
  count(*) FILTER (WHERE NOT cl.unregistered AND o.company_id IS NOT NULL) AS registered_with_ceo_account,
  count(*) FILTER (WHERE NOT cl.unregistered AND u.email IS NOT NULL) AS will_write_ceo_login_email,
  count(*) FILTER (WHERE NOT cl.unregistered AND u.phone_number IS NOT NULL) AS will_write_ceo_login_phone,
  count(*) FILTER (WHERE NOT cl.unregistered AND u.email IS NOT NULL AND cl.deleted_at IS NULL) AS live_clients_getting_ceo_email,
  count(*) FILTER (WHERE NOT cl.unregistered AND o.company_id IS NOT NULL AND (NOT o.is_active OR u.deleted_at IS NOT NULL)) AS ceo_account_inactive_or_user_deleted,
  count(*) FILTER (WHERE NOT cl.unregistered AND o.company_id IS NOT NULL AND o.src = 1) AS ceo_from_parent_copy,
  count(DISTINCT cl.store_id) FILTER (WHERE NOT cl.unregistered AND u.email IS NOT NULL) AS vendor_stores_receiving,
  count(DISTINCT cl.restaurant_id) FILTER (WHERE NOT cl.unregistered AND u.email IS NOT NULL) AS restaurants_exposed
FROM cl
LEFT JOIN ceo_owner o ON o.company_id = cl.restaurant_id
LEFT JOIN "user" u ON u.id = o.user_id;
\echo ##### N2_dev_admin_pre [N2/H1]
SELECT 'users_with_dev_admin_fixed_email' AS metric, count(*) AS n
FROM "user" WHERE lower(email) = 'dev.admin@yopmail.com'
UNION ALL
SELECT 'dev_admin_user_id_taken', count(*) FROM "user" WHERE id = 'bcd926a7-156b-45d0-803d-e59e33912032'
UNION ALL
SELECT 'dev_admin_company_id_taken',
  (SELECT count(*) FROM company WHERE id = 'be848550-2c98-43b3-8629-254109f5324d')
  + (SELECT count(*) FROM store WHERE id = 'be848550-2c98-43b3-8629-254109f5324d')
  + (SELECT count(*) FROM restaurant WHERE id = 'be848550-2c98-43b3-8629-254109f5324d')
  + (SELECT count(*) FROM manufacturer_subdivision WHERE id = 'be848550-2c98-43b3-8629-254109f5324d')
UNION ALL
SELECT 'dev_admin_account_id_taken',
  (SELECT count(*) FROM company_member WHERE id = '1b3ea549-8324-40f7-ab9b-43257cce14b3')
  + (SELECT count(*) FROM store_member WHERE id = '1b3ea549-8324-40f7-ab9b-43257cce14b3')
  + (SELECT count(*) FROM restaurant_member WHERE id = '1b3ea549-8324-40f7-ab9b-43257cce14b3')
  + (SELECT count(*) FROM manufacturer_subdivision_member WHERE id = '1b3ea549-8324-40f7-ab9b-43257cce14b3')
UNION ALL
SELECT 'admin_company_id_taken',
  (SELECT count(*) FROM company WHERE id = 'c5e2a8f4-1b7d-4e39-8a60-d4f9b3c71e25')
  + (SELECT count(*) FROM store WHERE id = 'c5e2a8f4-1b7d-4e39-8a60-d4f9b3c71e25')
  + (SELECT count(*) FROM restaurant WHERE id = 'c5e2a8f4-1b7d-4e39-8a60-d4f9b3c71e25')
  + (SELECT count(*) FROM manufacturer_subdivision WHERE id = 'c5e2a8f4-1b7d-4e39-8a60-d4f9b3c71e25')
UNION ALL
SELECT 'fixed_role_ids_taken', count(*) FROM role
WHERE id IN ('3aee88f6-87d7-4838-acc5-872c25e4dd1d', '3025e9b3-4240-4d3b-93fb-364cafca0b6f', '6d0b2e4a-8f13-4c57-9a6e-2b7c1d3e5f80')
UNION ALL
SELECT 'live_users_role_admin', count(*) FROM "user" WHERE role = 'admin' AND deleted_at IS NULL;
\echo ##### ROLE_mig_fail_pre [额外（N3 相关）：b5e1d7c3a920 RAISE / b9d4f2a7c6e1 主键 / 23e8d26d41eb 唯一索引]
WITH role_c AS (
  SELECT r.id, r.name, r.type::text AS grp, r.belongs_to_company, r.deleted_at,
         btrim(regexp_replace(lower(r.name), '[^a-z0-9]+', '_', 'g'), '_') AS code
  FROM role r
),
fac AS (
  SELECT DISTINCT grp, code FROM role_c WHERE NOT belongs_to_company AND deleted_at IS NULL
  UNION
  SELECT g.grp, 'ceo' FROM (SELECT DISTINCT grp FROM role_c) g
  WHERE NOT EXISTS (SELECT 1 FROM role_c x WHERE x.grp = g.grp AND x.code = 'ceo' AND NOT x.belongs_to_company)
),
unmapped AS (
  SELECT rc.id FROM role_c rc
  WHERE rc.belongs_to_company
    AND NOT EXISTS (SELECT 1 FROM fac f WHERE f.grp = rc.grp AND f.code = rc.code)
),
refs AS (
  SELECT role_id FROM company_member
  UNION ALL SELECT role_id FROM store_member
  UNION ALL SELECT role_id FROM restaurant_member
  UNION ALL SELECT role_id FROM manufacturer_subdivision_member
  UNION ALL SELECT role_id FROM onboarding_company_member
  UNION ALL SELECT role_id FROM onboarding_store_member
  UNION ALL SELECT role_id FROM onboarding_restaurant_member
  UNION ALL SELECT role_id FROM onboarding_manufacturer_subdivision_member
  UNION ALL SELECT role_id FROM order_history
  UNION ALL SELECT role_id FROM order_invoice_history
  UNION ALL SELECT role_id FROM order_packing_slip_history
)
SELECT 'b5e1d7c3a920_unmapped_company_roles_in_use' AS metric, count(*) AS n
FROM unmapped u WHERE EXISTS (SELECT 1 FROM refs WHERE refs.role_id = u.id)
UNION ALL
SELECT 'b5e1d7c3a920_rows_referencing_unmapped_roles', count(*)
FROM refs JOIN unmapped u ON u.id = refs.role_id
UNION ALL
SELECT 'b9d4f2a7c6e1_dup_live_facility_role_names', count(*)
FROM (SELECT grp, name FROM role_c WHERE NOT belongs_to_company AND deleted_at IS NULL
      GROUP BY grp, name HAVING count(*) > 1) d
UNION ALL
SELECT '23e8d26d41eb_dup_live_facility_role_codes', count(*)
FROM (SELECT grp, code FROM role_c WHERE NOT belongs_to_company AND deleted_at IS NULL
      GROUP BY grp, code HAVING count(*) > 1) d
UNION ALL
SELECT 'roles_total', count(*) FROM role_c;
\echo ##### N59_pre_country_suffix [N59、F6]
WITH profile AS (
  SELECT DISTINCT ON (p.company_id) p.company_id, p.address, p.city, p.state, p.zip_code
  FROM manufacturer_profile p
  WHERE p.deleted_at IS NULL
    AND coalesce(trim(p.address), '') <> ''
    AND coalesce(length(trim(p.address)), 0) <= 255
    AND coalesce(length(trim(p.city)), 0) <= 100
    AND coalesce(length(trim(p.state)), 0) <= 100
    AND coalesce(length(trim(p.zip_code)), 0) <= 10
  ORDER BY p.company_id, p.updated_at DESC
),
src AS (
  SELECT 'company(existing)' AS src, c.deleted_at,
         CASE WHEN pf.company_id IS NULL THEN c.address
              WHEN nullif(trim(pf.city), '') IS NULL AND nullif(trim(pf.state), '') IS NULL
                   AND nullif(trim(pf.zip_code), '') IS NULL THEN trim(pf.address)
         END AS addr
  FROM company c LEFT JOIN profile pf ON pf.company_id = c.id
  UNION ALL SELECT 'company<-store', deleted_at, address FROM store
  UNION ALL SELECT 'company<-restaurant', deleted_at, address FROM restaurant
  UNION ALL SELECT 'company<-manufacturer_subdivision', deleted_at, address FROM manufacturer_subdivision
  UNION ALL SELECT 'client.temporary_address', deleted_at, temporary_address FROM client
  UNION ALL SELECT 'client_temporary_store.address', deleted_at, address FROM client_temporary_store
  UNION ALL SELECT 'quotation_vendor_client.address', deleted_at, address FROM quotation_vendor_client
  UNION ALL SELECT 'quotation.from_address', deleted_at, from_address FROM quotation
  UNION ALL SELECT 'quotation.ship_to_address', deleted_at, ship_to_address FROM quotation
),
tagged AS (
  SELECT src, deleted_at, addr,
         addr ~* ',[[:space:]]*(US|USA|United States( of America)?)[[:space:]]*$' AS has_country
  FROM src
  WHERE nullif(btrim(addr), '') IS NOT NULL
),
parsed AS (
  SELECT src, deleted_at, has_country,
         CASE WHEN has_country THEN regexp_match(btrim(addr),
           '^(.*[^[:space:]])[[:space:]]*,[[:space:]]*([^,]*[^[:space:]])[[:space:]]*,[[:space:]]*([A-Za-z]{2})(?:[[:space:]]+([0-9]{5}(?:-[0-9]{4})?))?[[:space:]]*$')
         END AS old_parts,
         CASE WHEN has_country THEN regexp_match(
           regexp_replace(btrim(addr), '[[:space:]]*,[[:space:]]*(US|USA|United States( of America)?)[[:space:]]*$', '', 'i'),
           '^(.*[^[:space:]])[[:space:]]*,[[:space:]]*([^,]*[^[:space:]])[[:space:]]*,[[:space:]]*([A-Za-z]{2})(?:[[:space:]]+([0-9]{5}(?:-[0-9]{4})?))?[[:space:]]*$')
         END AS new_parts
  FROM tagged
)
SELECT src,
       count(*) AS addresses,
       count(*) FILTER (WHERE has_country) AS ends_with_country,
       count(*) FILTER (WHERE has_country AND deleted_at IS NULL) AS ends_with_country_live,
       count(*) FILTER (WHERE new_parts IS NOT NULL AND length(new_parts[2]) <= 100) AS new_version_splits,
       count(*) FILTER (WHERE has_country AND new_parts IS NULL) AS new_version_leaves_whole,
       count(*) FILTER (WHERE old_parts IS NOT NULL AND upper(old_parts[3]) = 'US' AND length(old_parts[2]) <= 100) AS old_version_would_missplit
FROM parsed
GROUP BY src
ORDER BY src
LIMIT 20;
\echo ##### N61_N10_pre_profile_overwrite [N61、N10]
WITH p AS (
  SELECT p.company_id, p.address, p.city, p.state, p.zip_code, p.country,
         c.address AS company_address, c.deleted_at AS company_deleted_at,
         count(*) OVER (PARTITION BY p.company_id) AS profiles_of_company,
         coalesce(trim(p.address), '') <> '' AS has_street,
         (coalesce(trim(p.city), '') <> '' OR coalesce(trim(p.state), '') <> '' OR coalesce(trim(p.zip_code), '') <> '') AS has_city_state_zip,
         (coalesce(trim(p.address), '') <> ''
          AND coalesce(length(trim(p.address)), 0) <= 255
          AND coalesce(length(trim(p.city)), 0) <= 100
          AND coalesce(length(trim(p.state)), 0) <= 100
          AND coalesce(length(trim(p.zip_code)), 0) <= 10) AS will_overwrite,
         concat_ws(', ', nullif(p.address, ''), nullif(p.city, ''),
                   nullif(concat_ws(' ', nullif(p.state, ''), nullif(p.zip_code, '')), ''),
                   nullif(p.country, '')) AS composed
  FROM manufacturer_profile p
  JOIN company c ON c.id = p.company_id
  WHERE p.deleted_at IS NULL
)
SELECT count(*) AS live_profiles,
       count(*) FILTER (WHERE profiles_of_company > 1) AS profiles_sharing_one_company,
       count(*) FILTER (WHERE will_overwrite) AS will_overwrite,
       count(*) FILTER (WHERE will_overwrite AND company_address IS DISTINCT FROM trim(address)) AS overwrite_changes_address,
       count(*) FILTER (WHERE will_overwrite AND nullif(btrim(company_address), '') IS NOT NULL
                          AND btrim(company_address) <> btrim(composed)
                          AND btrim(company_address) <> trim(address)) AS overwrite_loses_independent_address,
       count(*) FILTER (WHERE will_overwrite AND nullif(trim(country), '') IS NOT NULL) AS overwrite_drops_country,
       count(*) FILTER (WHERE will_overwrite AND NOT has_city_state_zip) AS overwrite_street_only,
       count(*) FILTER (WHERE will_overwrite AND company_deleted_at IS NOT NULL) AS overwrite_on_deleted_company,
       count(*) FILTER (WHERE has_street AND NOT will_overwrite) AS street_too_long_skipped,
       count(*) FILTER (WHERE NOT has_street AND has_city_state_zip) AS no_street_has_city_state_zip,
       count(*) FILTER (WHERE NOT has_street AND has_city_state_zip
                          AND nullif(btrim(company_address), '') IS NOT NULL
                          AND regexp_match(
                                regexp_replace(btrim(company_address), '[[:space:]]*,[[:space:]]*(US|USA|United States( of America)?)[[:space:]]*$', '', 'i'),
                                '^(.*[^[:space:]])[[:space:]]*,[[:space:]]*([^,]*[^[:space:]])[[:space:]]*,[[:space:]]*([A-Za-z]{2})(?:[[:space:]]+([0-9]{5}(?:-[0-9]{4})?))?[[:space:]]*$'
                              ) IS NULL) AS no_street_flat_address_unsplittable,
       (SELECT count(*) FROM company_billing b
        WHERE b.deleted_at IS NULL AND nullif(btrim(b.address), '') IS NOT NULL) AS company_billing_addresses_dropped
FROM p;
\echo ##### N53_pre_phone_backfill [N53]
WITH existing AS (
  SELECT c.type::text AS kind, c.deleted_at,
         nullif(btrim(c.phone_number), '') IS NOT NULL AS has_phone_col,
         EXISTS (SELECT 1 FROM company_phone_number p WHERE p.company_id = c.id AND p.deleted_at IS NULL) AS has_live_row,
         EXISTS (SELECT 1 FROM company_phone_number p WHERE p.company_id = c.id AND p.deleted_at IS NOT NULL) AS has_deleted_row,
         (EXISTS (SELECT 1 FROM store s WHERE s.company_id = c.id)
          OR EXISTS (SELECT 1 FROM restaurant r WHERE r.company_id = c.id)
          OR EXISTS (SELECT 1 FROM manufacturer_subdivision m WHERE m.manufacturer_company_id = c.id)) AS has_children
  FROM company c
),
target AS (
  SELECT kind, has_deleted_row, has_children,
         (deleted_at IS NULL AND has_phone_col AND NOT has_live_row) AS will_insert,
         (deleted_at IS NULL AND has_phone_col AND has_live_row) AS untouched
  FROM existing
)
SELECT 'company:' || kind AS src,
       count(*) FILTER (WHERE untouched) AS has_rows_untouched,
       count(*) FILTER (WHERE will_insert) AS will_insert_primary_phone,
       count(*) FILTER (WHERE will_insert AND NOT has_children) AS will_insert_standalone,
       count(*) FILTER (WHERE will_insert AND has_deleted_row) AS will_insert_had_only_deleted_rows,
       count(*) FILTER (WHERE will_insert AND NOT has_deleted_row) AS will_insert_never_had_rows,
       count(*) FILTER (WHERE will_insert AND has_children) AS will_insert_on_parent_company
FROM target
GROUP BY kind
UNION ALL
SELECT 'copy<-store', 0, count(*) FILTER (WHERE deleted_at IS NULL AND nullif(btrim(phone_number), '') IS NOT NULL), 0, 0, 0, 0
FROM store
UNION ALL
SELECT 'copy<-restaurant', 0, count(*) FILTER (WHERE deleted_at IS NULL AND nullif(btrim(phone_number), '') IS NOT NULL), 0, 0, 0, 0
FROM restaurant
UNION ALL
SELECT 'copy<-manufacturer_subdivision', 0, count(*) FILTER (WHERE deleted_at IS NULL AND nullif(btrim(phone_number), '') IS NOT NULL), 0, 0, 0, 0
FROM manufacturer_subdivision
ORDER BY 1
LIMIT 20;
\echo ##### F35_pre_parent_quotations [F35]
WITH rows_ AS (
  SELECT 'quotation' AS tbl, q.vendor_company_id, q.deleted_at
  FROM quotation q
  WHERE q.from_store_id IS NULL
  UNION ALL
  SELECT 'quotation_vendor_client', v.vendor_company_id, v.deleted_at
  FROM quotation_vendor_client v
  WHERE v.store_id IS NULL
),
parent AS (
  SELECT c.id, c.type::text AS kind, c.deleted_at,
         (EXISTS (SELECT 1 FROM store s WHERE s.company_id = c.id)
          OR EXISTS (SELECT 1 FROM restaurant r WHERE r.company_id = c.id)
          OR EXISTS (SELECT 1 FROM manufacturer_subdivision m WHERE m.manufacturer_company_id = c.id)) AS has_children,
         (c.user_id IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM company_member cm WHERE cm.company_id = c.id AND cm.user_id = c.user_id)) AS owner_without_member
  FROM company c
  WHERE c.id IN (SELECT vendor_company_id FROM rows_)
),
classified AS (
  SELECT r.tbl, r.vendor_company_id, r.deleted_at,
         CASE
           WHEN NOT p.has_children AND p.deleted_at IS NULL THEN 'no_store_vendor:stays_visible'
           WHEN p.kind = 'MANUFACTURER' THEN 'manufacturer_top:restored_by_36cd67a87d67'
           WHEN NOT p.has_children THEN 'no_store_vendor:already_deleted'
           WHEN p.owner_without_member THEN 'parent_owner_without_member:est_restored_by_8b980708773e'
           WHEN p.deleted_at IS NOT NULL THEN 'parent_already_deleted:INVISIBLE'
           ELSE 'parent_deleted_by_8011513c0d5c:INVISIBLE'
         END AS outcome
  FROM rows_ r
  JOIN parent p ON p.id = r.vendor_company_id
)
SELECT tbl, outcome,
       count(*) FILTER (WHERE deleted_at IS NULL) AS live_rows,
       count(*) FILTER (WHERE deleted_at IS NOT NULL) AS deleted_rows,
       count(DISTINCT vendor_company_id) AS vendor_companies
FROM classified
GROUP BY tbl, outcome
ORDER BY tbl, outcome
LIMIT 20;
\echo ##### F30_pre_guard_comment_author [F30]
SELECT count(*) AS comments_without_any_member,
       count(*) FILTER (WHERE deleted_at IS NULL) AS live_comments_without_any_member
FROM order_comment
WHERE company_member_id IS NULL
  AND restaurant_member_id IS NULL
  AND store_member_id IS NULL;
\echo ##### F30_pre_comment_side [F30]
WITH cm_comment AS (
  SELECT oc.deleted_at AS comment_deleted_at, cm.user_id, cm.company_id AS author_company_id,
         btrim(regexp_replace(lower(r.name), '[^a-z0-9]+', '_', 'g'), '_') AS role_code,
         o.store_id, o.restaurant_id,
         s.company_id AS store_parent_id, s.deleted_at AS store_deleted_at,
         rt.company_id AS restaurant_parent_id, rt.deleted_at AS restaurant_deleted_at
  FROM order_comment oc
  JOIN company_member cm ON cm.id = oc.company_member_id
  JOIN "order" o ON o.id = oc.order_id
  JOIN role r ON r.id = cm.role_id
  LEFT JOIN store s ON s.id = o.store_id
  LEFT JOIN restaurant rt ON rt.id = o.restaurant_id
),
sided AS (
  SELECT x.*,
         CASE WHEN x.store_parent_id = x.author_company_id THEN 'store_parent'
              WHEN x.restaurant_parent_id = x.author_company_id THEN 'restaurant_parent'
              ELSE 'neither_parent' END AS side
  FROM cm_comment x
),
classified AS (
  SELECT c.side, c.comment_deleted_at,
         CASE
           WHEN c.side = 'neither_parent' THEN 'not_moved:author_company_not_parent'
           WHEN c.side = 'store_parent' AND EXISTS (
                SELECT 1 FROM store_member sm WHERE sm.user_id = c.user_id AND sm.store_id = c.store_id)
             THEN 'moved:has_store_member'
           WHEN c.side = 'restaurant_parent' AND EXISTS (
                SELECT 1 FROM restaurant_member rm WHERE rm.user_id = c.user_id AND rm.restaurant_id = c.restaurant_id)
             THEN 'moved:has_restaurant_member'
           WHEN c.side = 'store_parent' AND c.store_deleted_at IS NOT NULL THEN 'not_moved:store_deleted'
           WHEN c.side = 'restaurant_parent' AND c.restaurant_deleted_at IS NOT NULL THEN 'not_moved:restaurant_deleted'
           WHEN c.role_code = 'ceo' OR EXISTS (
                SELECT 1 FROM role r2
                WHERE NOT r2.belongs_to_company AND r2.deleted_at IS NULL
                  AND r2.type::text = CASE WHEN c.side = 'store_parent' THEN 'VENDOR' ELSE 'BUYER' END
                  AND btrim(regexp_replace(lower(r2.name), '[^a-z0-9]+', '_', 'g'), '_') = c.role_code)
             THEN 'moved_est:via_9d18fcda7ab1_copy'
           ELSE 'not_moved:no_same_code_role_on_side'
         END AS outcome
  FROM sided c
)
SELECT side, outcome,
       count(*) FILTER (WHERE comment_deleted_at IS NULL) AS live_comments,
       count(*) FILTER (WHERE comment_deleted_at IS NOT NULL) AS deleted_comments
FROM classified
GROUP BY side, outcome
ORDER BY side, outcome
LIMIT 20;
\echo ##### F126_pre_category_remap [F126]
WITH sp AS (
  SELECT p.deleted_at, p.store_id, s.company_id AS store_parent_id,
         pc.id AS cat_id, pc.company_id AS cat_company_id, pc.deleted_at AS cat_deleted_at, pc.name AS cat_name
  FROM store_product p
  JOIN store s ON s.id = p.store_id
  LEFT JOIN product_category pc ON pc.id = p.product_category_id
),
rp AS (
  SELECT r.deleted_at, pc.company_id AS cat_company_id, pc.name AS cat_name,
         coalesce(r.selected_store_id, (
             SELECT x.store_id FROM restaurant_product_m2m m
             JOIN store_product x ON x.id = m.product_id
             WHERE m.restaurant_product_id = r.id
             ORDER BY x.id LIMIT 1)) AS store_id
  FROM restaurant_product r
  JOIN product_category pc ON pc.id = r.category_id
),
rp2 AS (
  SELECT rp.*, s.company_id AS store_parent_id
  FROM rp LEFT JOIN store s ON s.id = rp.store_id
),
classified AS (
  SELECT 'store_product' AS kind, sp.deleted_at,
         CASE
           WHEN sp.cat_id IS NULL THEN 'no_category'
           WHEN sp.cat_company_id = sp.store_parent_id AND sp.cat_deleted_at IS NULL THEN 'parent_category->store_copy'
           WHEN sp.cat_company_id = sp.store_parent_id THEN 'parent_category_deleted->deleted_copy'
           WHEN sp.cat_company_id IS NULL AND EXISTS (
                SELECT 1 FROM product_category o
                WHERE o.company_id IN (sp.store_parent_id, sp.store_id) AND o.parent_id IS NULL
                  AND o.deleted_at IS NULL AND lower(o.name) = lower(sp.cat_name))
             THEN 'global->remapped_by_name'
           WHEN sp.cat_company_id IS NULL THEN 'global->STAYS_GLOBAL'
           WHEN sp.cat_company_id = sp.store_id THEN 'store_own_category'
           ELSE 'other_company_category'
         END AS outcome
  FROM sp
  UNION ALL
  SELECT 'restaurant_product', rp2.deleted_at,
         CASE
           WHEN rp2.store_id IS NULL AND rp2.cat_company_id IS NULL THEN 'global_no_vendor_store->STAYS_GLOBAL'
           WHEN rp2.store_id IS NULL THEN 'no_vendor_store->unchanged'
           WHEN rp2.cat_company_id IS NULL AND EXISTS (
                SELECT 1 FROM product_category o
                WHERE o.company_id IN (rp2.store_parent_id, rp2.store_id) AND o.parent_id IS NULL
                  AND o.deleted_at IS NULL AND lower(o.name) = lower(rp2.cat_name))
             THEN 'global->remapped_by_name'
           WHEN rp2.cat_company_id IS NULL THEN 'global->STAYS_GLOBAL'
           WHEN rp2.cat_company_id = rp2.store_parent_id THEN 'parent_category->store_copy'
           ELSE 'other_company_category->unchanged'
         END
  FROM rp2
)
SELECT kind, outcome,
       count(*) FILTER (WHERE deleted_at IS NULL) AS live_rows,
       count(*) FILTER (WHERE deleted_at IS NOT NULL) AS deleted_rows
FROM classified
GROUP BY kind, outcome
ORDER BY kind, outcome
LIMIT 20;
\echo ##### N141_N150_pre_bill_to [N141、N150]
WITH first_contact AS (
  SELECT DISTINCT ON (c.client_id) c.client_id,
         nullif(btrim(c.name), '') AS name,
         nullif(btrim(c.phone_number), '') AS phone,
         nullif(btrim(c.email), '') AS email
  FROM client_restaurant_contact c
  WHERE c.deleted_at IS NULL
  ORDER BY c.client_id, c.created_at, c.id
),
restaurant_ceo AS (
  SELECT DISTINCT ON (rm.restaurant_id) rm.restaurant_id,
         nullif(btrim(concat_ws(' ', rm.first_name, rm.last_name)), '') AS name,
         nullif(btrim(u.phone_number), '') AS phone,
         nullif(btrim(u.email), '') AS email
  FROM restaurant_member rm
  JOIN role r ON r.id = rm.role_id AND r.name = 'CEO'
  JOIN "user" u ON u.id = rm.user_id
  WHERE rm.deleted_at IS NULL
  ORDER BY rm.restaurant_id, rm.created_at, rm.id
),
base AS (
  SELECT (cl.restaurant_id IS NULL OR rt.status::text IN ('UNREGISTERED', 'UNREGISTERED_WITH_ORDERS')) AS unregistered,
         nullif(btrim(cl.temporary_name), '') AS t_name,
         nullif(btrim(rt.name), '') AS r_name,
         nullif(btrim(cl.temporary_address), '') AS t_addr,
         nullif(btrim(rt.address), '') AS r_addr,
         regexp_match(
           regexp_replace(btrim(cl.temporary_address), '[[:space:]]*,[[:space:]]*(US|USA|United States( of America)?)[[:space:]]*$', '', 'i'),
           '^(.*[^[:space:]])[[:space:]]*,[[:space:]]*([^,]*[^[:space:]])[[:space:]]*,[[:space:]]*([A-Za-z]{2})(?:[[:space:]]+([0-9]{5}(?:-[0-9]{4})?))?[[:space:]]*$') AS t_parts,
         regexp_match(
           regexp_replace(btrim(rt.address), '[[:space:]]*,[[:space:]]*(US|USA|United States( of America)?)[[:space:]]*$', '', 'i'),
           '^(.*[^[:space:]])[[:space:]]*,[[:space:]]*([^,]*[^[:space:]])[[:space:]]*,[[:space:]]*([A-Za-z]{2})(?:[[:space:]]+([0-9]{5}(?:-[0-9]{4})?))?[[:space:]]*$') AS r_parts,
         fc.name AS fc_name, fc.phone AS fc_phone, fc.email AS fc_email,
         CASE WHEN rc.restaurant_id IS NOT NULL THEN rc.name ELSE pc.name END AS o_name,
         CASE WHEN rc.restaurant_id IS NOT NULL THEN rc.phone ELSE pc.phone END AS o_phone,
         CASE WHEN rc.restaurant_id IS NOT NULL THEN rc.email ELSE pc.email END AS o_email
  FROM client cl
  LEFT JOIN restaurant rt ON rt.id = cl.restaurant_id
  LEFT JOIN first_contact fc ON fc.client_id = cl.id
  LEFT JOIN restaurant_ceo rc ON rc.restaurant_id = cl.restaurant_id
  LEFT JOIN LATERAL (
    SELECT nullif(btrim(concat_ws(' ', cm.first_name, cm.last_name)), '') AS name,
           nullif(btrim(u.phone_number), '') AS phone,
           nullif(btrim(u.email), '') AS email
    FROM company_member cm
    JOIN role r ON r.id = cm.role_id AND r.name = 'CEO'
    JOIN "user" u ON u.id = cm.user_id
    WHERE cm.company_id = rt.company_id AND cm.deleted_at IS NULL AND rt.deleted_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM restaurant_member rm2 WHERE rm2.user_id = cm.user_id AND rm2.restaurant_id = rt.id)
    ORDER BY md5(cm.id::text || ':' || rt.id::text)
    LIMIT 1
  ) pc ON true
  WHERE cl.deleted_at IS NULL
),
bill AS (
  SELECT unregistered,
         CASE WHEN unregistered THEN coalesce(t_name, r_name) ELSE r_name END AS company_name,
         CASE WHEN unregistered THEN coalesce(coalesce(t_parts[1], t_addr), coalesce(r_parts[1], r_addr))
              ELSE coalesce(r_parts[1], r_addr) END AS street,
         CASE WHEN unregistered THEN coalesce(t_parts[2], r_parts[2]) ELSE r_parts[2] END AS city,
         CASE WHEN unregistered THEN coalesce(t_parts[3], r_parts[3]) ELSE r_parts[3] END AS state,
         CASE WHEN unregistered THEN coalesce(t_parts[4], r_parts[4]) ELSE r_parts[4] END AS zip_code,
         CASE WHEN unregistered THEN fc_name ELSE o_name END AS contact_name,
         CASE WHEN unregistered THEN fc_phone ELSE o_phone END AS phone,
         CASE WHEN unregistered THEN fc_email ELSE o_email END AS email
  FROM base
)
SELECT CASE WHEN unregistered THEN 'unregistered' ELSE 'registered' END AS client_kind,
       count(*) AS live_clients,
       count(*) FILTER (WHERE company_name IS NULL OR street IS NULL OR city IS NULL OR state IS NULL
                          OR zip_code IS NULL OR contact_name IS NULL OR phone IS NULL OR email IS NULL) AS bill_to_incomplete,
       count(*) FILTER (WHERE contact_name IS NULL AND phone IS NULL AND email IS NULL) AS no_contact_at_all,
       count(*) FILTER (WHERE (phone IS NULL) <> (email IS NULL)) AS only_one_of_phone_email,
       count(*) FILTER (WHERE street IS NOT NULL AND (city IS NULL OR state IS NULL)) AS address_not_split,
       count(*) FILTER (WHERE city IS NOT NULL AND zip_code IS NULL) AS split_without_zip
FROM bill
GROUP BY 1
ORDER BY 1
LIMIT 20;
\echo ##### pre_acct_merge_counts [无独立编号（8c6f5e1a90b1 / 96fe8aa55b8c 成员表合并）]
WITH m AS (
  SELECT 'company_member'::text AS src, id, user_id, company_id AS biz_id, role_id, deleted_at, is_active FROM company_member
  UNION ALL SELECT 'store_member', id, user_id, store_id, role_id, deleted_at, is_active FROM store_member
  UNION ALL SELECT 'restaurant_member', id, user_id, restaurant_id, role_id, deleted_at, is_active FROM restaurant_member
  UNION ALL SELECT 'manufacturer_subdivision_member', id, user_id, manufacturer_subdivision_id, role_id, deleted_at, is_active FROM manufacturer_subdivision_member
)
SELECT coalesce(m.src, 'TOTAL') AS source_table,
  count(*) AS accounts_created,
  count(*) FILTER (WHERE m.deleted_at IS NOT NULL) AS deleted_accounts,
  count(*) FILTER (WHERE m.deleted_at IS NULL) AS live_accounts,
  count(*) FILTER (WHERE m.deleted_at IS NULL AND NOT m.is_active) AS live_inactive,
  count(*) FILTER (WHERE m.deleted_at IS NULL AND u.deleted_at IS NOT NULL) AS live_on_deleted_user,
  count(*) FILTER (WHERE m.deleted_at IS NULL AND coalesce(c.deleted_at, s.deleted_at, r.deleted_at, ms.deleted_at) IS NOT NULL) AS live_in_deleted_business,
  count(*) FILTER (WHERE u.id IS NULL) AS user_missing_fk_fail,
  count(*) FILTER (WHERE c.id IS NULL AND s.id IS NULL AND r.id IS NULL AND ms.id IS NULL) AS business_missing,
  count(*) FILTER (WHERE ro.id IS NULL) AS role_missing,
  count(*) FILTER (WHERE m.deleted_at IS NULL AND ro.deleted_at IS NOT NULL) AS live_with_deleted_role
FROM m
LEFT JOIN "user" u ON u.id = m.user_id
LEFT JOIN company c ON m.src = 'company_member' AND c.id = m.biz_id
LEFT JOIN store s ON m.src = 'store_member' AND s.id = m.biz_id
LEFT JOIN restaurant r ON m.src = 'restaurant_member' AND r.id = m.biz_id
LEFT JOIN manufacturer_subdivision ms ON m.src = 'manufacturer_subdivision_member' AND ms.id = m.biz_id
LEFT JOIN role ro ON ro.id = m.role_id
GROUP BY ROLLUP (m.src)
ORDER BY m.src NULLS LAST
LIMIT 20;
\echo ##### pre_acct_merge_conflicts [无独立编号（8c6f5e1a90b1 唯一约束/主键）、F5]
WITH m AS (
  SELECT id, user_id, company_id AS biz_id, deleted_at FROM company_member
  UNION ALL SELECT id, user_id, store_id, deleted_at FROM store_member
  UNION ALL SELECT id, user_id, restaurant_id, deleted_at FROM restaurant_member
  UNION ALL SELECT id, user_id, manufacturer_subdivision_id, deleted_at FROM manufacturer_subdivision_member
),
biz AS (
  SELECT id FROM company UNION ALL SELECT id FROM store
  UNION ALL SELECT id FROM restaurant UNION ALL SELECT id FROM manufacturer_subdivision
),
shared_biz AS (SELECT id FROM biz GROUP BY id HAVING count(*) > 1),
dup_pair AS (SELECT user_id, biz_id, count(*) AS n FROM m GROUP BY user_id, biz_id HAVING count(*) > 1),
dup_id AS (SELECT id, count(*) AS n FROM m GROUP BY id HAVING count(*) > 1)
SELECT 'dup (user_id, business_id) -> uq_account_user_id_company_id' AS check_name,
       count(*) AS groups_found, coalesce(sum(n), 0) AS member_rows, NULL::bigint AS live_member_rows
FROM dup_pair
UNION ALL
SELECT 'same member id in two member tables -> account_pkey', count(*), coalesce(sum(n), 0), NULL
FROM dup_id
UNION ALL
SELECT 'business id shared by company/store/restaurant/subdivision (F5)',
       (SELECT count(*) FROM shared_biz), count(*), count(*) FILTER (WHERE m.deleted_at IS NULL)
FROM m WHERE m.biz_id IN (SELECT id FROM shared_biz);
\echo ##### pre_acct_copies_9d18 [F17、N72（9d18fcda7ab1 账号副本数）]
WITH child AS (
  SELECT 'VENDOR'::text AS grp, s.id, s.company_id AS parent_id FROM store s WHERE s.deleted_at IS NULL
  UNION ALL SELECT 'BUYER', r.id, r.company_id FROM restaurant r WHERE r.deleted_at IS NULL AND r.company_id IS NOT NULL
  UNION ALL SELECT 'MANUFACTURER', ms.id, ms.manufacturer_company_id FROM manufacturer_subdivision ms WHERE ms.deleted_at IS NULL
),
own_all AS (
  SELECT user_id, store_id AS child_id FROM store_member
  UNION ALL SELECT user_id, restaurant_id FROM restaurant_member
  UNION ALL SELECT user_id, manufacturer_subdivision_id FROM manufacturer_subdivision_member
),
role_code AS (
  SELECT id, type::text AS grp, belongs_to_company, deleted_at,
         btrim(regexp_replace(lower(name), '[^a-z0-9]+', '_', 'g'), '_') AS code
  FROM role
),
pairs AS (
  SELECT cm.id AS account_id, cm.deleted_at, cm.is_active, u.deleted_at AS user_deleted_at, ch.id AS child_id,
         (EXISTS (SELECT 1 FROM role_code f WHERE f.grp = ch.grp AND NOT f.belongs_to_company AND f.deleted_at IS NULL AND f.code = rc.code)
          OR (rc.code = 'ceo' AND NOT EXISTS (SELECT 1 FROM role_code f WHERE f.grp = ch.grp AND NOT f.belongs_to_company AND f.code = 'ceo'))) AS role_mappable,
         EXISTS (SELECT 1 FROM own_all o WHERE o.user_id = cm.user_id AND o.child_id = ch.id) AS already_member
  FROM company_member cm
  JOIN role_code rc ON rc.id = cm.role_id
  JOIN "user" u ON u.id = cm.user_id
  JOIN child ch ON ch.parent_id = cm.company_id
)
SELECT count(*) AS company_account_x_branch_pairs,
  count(*) FILTER (WHERE role_mappable AND NOT already_member) AS copies_made,
  count(*) FILTER (WHERE role_mappable AND NOT already_member AND deleted_at IS NULL) AS live_copies,
  count(*) FILTER (WHERE role_mappable AND NOT already_member AND deleted_at IS NULL AND is_active AND user_deleted_at IS NULL) AS usable_copies,
  count(DISTINCT child_id) FILTER (WHERE role_mappable AND NOT already_member) AS branches_receiving_copies,
  count(*) FILTER (WHERE NOT role_mappable) AS skipped_no_branch_role,
  count(*) FILTER (WHERE NOT role_mappable AND deleted_at IS NULL) AS skipped_no_branch_role_live,
  count(*) FILTER (WHERE already_member) AS skipped_already_member,
  (SELECT count(*) FROM "user" u2 WHERE u2.role = 'admin' AND u2.deleted_at IS NULL) AS admin_accounts_added_a9d3f7b2e6c1
FROM pairs;
\echo ##### pre_F7_chat_member_cascade [F7]
WITH RECURSIVE edges AS MATERIALIZED (
  SELECT 'member'::text AS src_kind, m.chat_member_id AS src_id, 'message'::text AS dst_kind, m.id AS dst_id FROM chat_message m
  UNION ALL
  SELECT 'message', f.forwarded_message_id, 'message', f.id FROM chat_message f WHERE f.forwarded_message_id IS NOT NULL
  UNION ALL
  SELECT 'message', cm.last_read_message_id, 'member', cm.id FROM chat_member cm WHERE cm.last_read_message_id IS NOT NULL
),
seed AS (
  SELECT id FROM chat_member
  WHERE store_member_id IS NULL AND restaurant_member_id IS NULL AND company_member_id IS NULL
),
gone (kind, id) AS (
  SELECT 'member'::text, id FROM seed
  UNION
  SELECT e.dst_kind, e.dst_id FROM gone g JOIN edges e ON e.src_kind = g.kind AND e.src_id = g.id
)
SELECT
  (SELECT count(*) FROM seed) AS orphan_members_deleted,
  count(*) FILTER (WHERE g.kind = 'member' AND s.id IS NULL) AS other_members_deleted_by_last_read_cascade,
  count(*) FILTER (WHERE g.kind = 'message') AS messages_deleted,
  (SELECT count(*) FROM chat_message_attachment a WHERE a.chat_message_id IN (SELECT id FROM gone WHERE kind = 'message')) AS attachments_deleted,
  (SELECT count(DISTINCT cm.chat_id) FROM chat_member cm WHERE cm.id IN (SELECT id FROM gone WHERE kind = 'member')) AS chats_affected,
  (SELECT min(m.created_at)::date FROM chat_message m WHERE m.id IN (SELECT id FROM gone WHERE kind = 'message')) AS first_deleted_msg_date,
  (SELECT max(m.created_at)::date FROM chat_message m WHERE m.id IN (SELECT id FROM gone WHERE kind = 'message')) AS last_deleted_msg_date
FROM gone g
LEFT JOIN seed s ON s.id = g.id;
\echo ##### pre_chat_member_account_fk [F7、F8（80a123f47df0 外键与唯一约束）]
WITH ids AS (
  SELECT id, user_id FROM company_member
  UNION ALL SELECT id, user_id FROM store_member
  UNION ALL SELECT id, user_id FROM restaurant_member
  UNION ALL SELECT id, user_id FROM manufacturer_subdivision_member
),
cm AS (
  SELECT id, chat_id, user_id,
         COALESCE(store_member_id, restaurant_member_id, company_member_id) AS acc,
         (store_member_id IS NOT NULL)::int + (restaurant_member_id IS NOT NULL)::int + (company_member_id IS NOT NULL)::int AS n_set
  FROM chat_member
)
SELECT count(*) AS chat_members,
  count(*) FILTER (WHERE cm.acc IS NULL) AS no_member_deleted,
  count(*) FILTER (WHERE cm.n_set > 1) AS several_member_cols,
  count(*) FILTER (WHERE cm.acc IS NOT NULL AND i.id IS NULL) AS account_missing_fk_fail,
  count(*) FILTER (WHERE i.user_id IS NOT NULL AND i.user_id <> cm.user_id) AS chat_user_differs_from_account_user,
  (SELECT count(*) FROM (SELECT chat_id, acc FROM cm WHERE acc IS NOT NULL GROUP BY chat_id, acc HAVING count(*) > 1) d) AS dup_chat_account_unique_fail
FROM cm LEFT JOIN ids i ON i.id = cm.acc;
\echo ##### pre_F15_order_comment_account [F15、F30]
WITH ids AS (
  SELECT id FROM company_member UNION ALL SELECT id FROM store_member
  UNION ALL SELECT id FROM restaurant_member UNION ALL SELECT id FROM manufacturer_subdivision_member
),
oc AS (
  SELECT id, created_at, deleted_at,
         COALESCE(company_member_id, restaurant_member_id, store_member_id) AS acc,
         COALESCE(updated_by_company_member_id, updated_by_store_member_id) AS upd,
         (company_member_id IS NOT NULL)::int + (restaurant_member_id IS NOT NULL)::int + (store_member_id IS NOT NULL)::int AS n_set,
         (company_member_id IS NOT NULL AND store_member_id IS NOT NULL) AS company_and_store
  FROM order_comment
)
SELECT count(*) AS comments,
  count(*) FILTER (WHERE oc.acc IS NULL) AS no_author_not_null_fail,
  count(*) FILTER (WHERE oc.acc IS NULL AND oc.deleted_at IS NULL) AS no_author_live,
  (min(oc.created_at) FILTER (WHERE oc.acc IS NULL))::date AS no_author_first_date,
  (max(oc.created_at) FILTER (WHERE oc.acc IS NULL))::date AS no_author_last_date,
  count(*) FILTER (WHERE oc.n_set > 1) AS several_authors,
  count(*) FILTER (WHERE oc.company_and_store) AS company_and_store_author,
  count(*) FILTER (WHERE oc.acc IS NOT NULL AND a.id IS NULL) AS author_account_missing_fk_fail,
  count(*) FILTER (WHERE oc.upd IS NOT NULL AND b.id IS NULL) AS editor_account_missing_fk_fail
FROM oc
LEFT JOIN ids a ON a.id = oc.acc
LEFT JOIN ids b ON b.id = oc.upd;
\echo ##### pre_packing_slip_accounts [无独立编号（a56e6f86e0d7）]
SELECT count(*) AS slips,
  count(ps.packer_store_member_id) AS packer_set,
  count(ps.driver_store_member_id) AS driver_set,
  count(ps.approved_by_store_member_id) AS approver_set,
  count(COALESCE(ps.delivery_approved_by_restaurant_member_id, ps.delivery_approved_by_store_member_id)) AS delivery_approver_set,
  count(*) FILTER (WHERE ps.delivery_approved_by_restaurant_member_id IS NOT NULL AND ps.delivery_approved_by_store_member_id IS NOT NULL) AS both_delivery_approvers,
  count(*) FILTER (WHERE ps.packer_store_member_id IS NOT NULL AND p.id IS NULL) AS packer_missing_fk_fail,
  count(*) FILTER (WHERE ps.driver_store_member_id IS NOT NULL AND d.id IS NULL) AS driver_missing_fk_fail,
  count(*) FILTER (WHERE ps.approved_by_store_member_id IS NOT NULL AND ap.id IS NULL) AS approver_missing_fk_fail,
  count(*) FILTER (WHERE ps.delivery_approved_by_restaurant_member_id IS NOT NULL AND rd.id IS NULL) AS delivery_restaurant_missing_fk_fail,
  count(*) FILTER (WHERE ps.delivery_approved_by_restaurant_member_id IS NULL AND ps.delivery_approved_by_store_member_id IS NOT NULL AND sd.id IS NULL) AS delivery_store_missing_fk_fail,
  count(*) FILTER (WHERE p.deleted_at IS NOT NULL OR d.deleted_at IS NOT NULL) AS packer_or_driver_member_deleted
FROM order_packing_slip ps
LEFT JOIN store_member p ON p.id = ps.packer_store_member_id
LEFT JOIN store_member d ON d.id = ps.driver_store_member_id
LEFT JOIN store_member ap ON ap.id = ps.approved_by_store_member_id
LEFT JOIN restaurant_member rd ON rd.id = ps.delivery_approved_by_restaurant_member_id
LEFT JOIN store_member sd ON sd.id = ps.delivery_approved_by_store_member_id;
\echo ##### pre_049461_orphan_accounts [N97（c4d8e2a6f1b3 硬删公司，叠加 049461d68471 的孤儿账号检查）]
WITH top AS (
  SELECT c.id, c.type::text AS type, c.name, c.address, c.created_at, c.deleted_at, c.user_id, NULL::text AS cstatus FROM company c
  UNION ALL
  SELECT r.id, 'CLIENT', r.name, r.address, r.created_at, r.deleted_at, NULL::uuid, r.status::text FROM restaurant r WHERE r.company_id IS NULL
),
base AS (
  SELECT t.id, t.type,
         lower(regexp_replace(btrim(coalesce(t.name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(t.address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM top t
  WHERE t.deleted_at IS NULL
    AND t.created_at >= '2026-09-17'
    AND t.type IN ('CLIENT', 'VENDOR')
    AND coalesce(t.cstatus, '') NOT IN ('UNREGISTERED', 'UNREGISTERED_WITH_ORDERS')
    AND t.user_id IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM company_audit_log a
      WHERE a.company_id = t.id AND a.action = 'created' AND a.entity_type IN ('company', 'subscription')
        AND abs(extract(epoch FROM a.created_at - t.created_at)) < 120)
    AND NOT EXISTS (SELECT 1 FROM company_subscription s WHERE s.company_id = t.id AND s.invitation_code_used_at IS NOT NULL)
),
v_tmp AS (
  SELECT DISTINCT lower(regexp_replace(btrim(coalesce(temporary_name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(temporary_address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM client WHERE store_id IS NOT NULL
),
r_tmp AS (
  SELECT DISTINCT lower(regexp_replace(btrim(coalesce(name, '')), '\s+', ' ', 'g')) AS nm,
         lower(regexp_replace(btrim(split_part(coalesce(address, ''), ',', 1)), '\s+', ' ', 'g')) AS street
  FROM client_temporary_store
),
doomed AS (
  SELECT b.id FROM base b
  WHERE (b.type = 'CLIENT' AND b.id IN (SELECT s.company_id FROM client cl JOIN company_subscription s ON s.id = cl.company_subscription_id))
     OR (b.type = 'CLIENT' AND b.nm <> '' AND b.street <> '' AND EXISTS (SELECT 1 FROM v_tmp v WHERE v.nm = b.nm AND v.street = b.street))
     OR (b.type = 'VENDOR' AND b.nm = '')
     OR (b.type = 'VENDOR' AND b.nm <> '' AND b.street <> '' AND EXISTS (SELECT 1 FROM r_tmp r WHERE r.nm = b.nm AND r.street = b.street))
),
acc AS (
  SELECT company_id AS biz_id, deleted_at FROM company_member
  UNION ALL SELECT restaurant_id, deleted_at FROM restaurant_member
)
SELECT (SELECT count(*) FROM base) AS candidates_upper_bound,
       (SELECT count(*) FROM doomed) AS predicted_hard_deleted,
       count(b.id) AS accounts_in_candidates,
       count(d.id) AS accounts_in_predicted_deleted,
       count(d.id) FILTER (WHERE acc.deleted_at IS NULL) AS live_accounts_in_predicted_deleted
FROM acc
LEFT JOIN base b ON b.id = acc.biz_id
LEFT JOIN doomed d ON d.id = acc.biz_id;
\echo ##### pre_N41_invited_staged_members [N41]
WITH parent AS (
  SELECT c.id, c.deleted_at, c.user_id,
    CASE
      WHEN c.user_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM company_member cm WHERE cm.company_id = c.id AND cm.user_id = c.user_id)
        THEN 'INVITED(owner_signed_up)'
      WHEN c.user_id IS NULL
           AND NOT EXISTS (SELECT 1 FROM company_member cm WHERE cm.company_id = c.id AND cm.deleted_at IS NULL)
           AND NOT EXISTS (SELECT 1 FROM company_subscription s WHERE s.company_id = c.id AND s.invitation_code_used_at IS NOT NULL)
           AND EXISTS (SELECT 1 FROM company_subscription s WHERE s.company_id = c.id AND s.invitation_code IS NOT NULL AND s.invitation_code_used_at IS NULL)
        THEN 'INVITED(code_unused)'
      ELSE 'ACTIVE'
    END AS predicted_status
  FROM company c
),
staged AS (
  SELECT 'onboarding_company_member'::text AS tbl, o.company_id AS parent_id, o.deleted_at FROM onboarding_company_member o
  UNION ALL
  SELECT 'onboarding_store_member', s.company_id, o.deleted_at FROM onboarding_store_member o LEFT JOIN store s ON s.id = o.store_id
  UNION ALL
  SELECT 'onboarding_restaurant_member', r.company_id, o.deleted_at FROM onboarding_restaurant_member o LEFT JOIN restaurant r ON r.id = o.restaurant_id
  UNION ALL
  SELECT 'onboarding_manufacturer_subdivision_member', ms.manufacturer_company_id, o.deleted_at FROM onboarding_manufacturer_subdivision_member o LEFT JOIN manufacturer_subdivision ms ON ms.id = o.manufacturer_subdivision_id
)
SELECT coalesce(p.predicted_status, 'NO_PARENT') AS parent_predicted_status,
       CASE WHEN p.predicted_status = 'ACTIVE' THEN 'all onboarding_*_member' ELSE st.tbl END AS item,
       count(*) AS rows_total,
       count(*) FILTER (WHERE st.deleted_at IS NULL) AS rows_live,
       count(*) FILTER (WHERE st.deleted_at IS NULL AND p.deleted_at IS NOT NULL) AS rows_live_parent_deleted,
       count(DISTINCT st.parent_id) AS parent_companies
FROM staged st LEFT JOIN parent p ON p.id = st.parent_id
GROUP BY 1, 2
UNION ALL
SELECT p.predicted_status, 'owner onboarding.step=' || o.step::text,
       count(*), count(*) FILTER (WHERE o.deleted_at IS NULL),
       count(*) FILTER (WHERE o.deleted_at IS NULL AND p.deleted_at IS NOT NULL), count(DISTINCT p.id)
FROM parent p JOIN onboarding o ON o.user_id = p.user_id
WHERE p.predicted_status <> 'ACTIVE'
GROUP BY 1, 2
ORDER BY 1, 2
LIMIT 20;
\echo ##### pre_N41_branches_without_accounts [N41、N129]
WITH parent AS (
  SELECT c.id, c.deleted_at,
    CASE
      WHEN c.user_id IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM company_member cm WHERE cm.company_id = c.id AND cm.user_id = c.user_id)
        THEN 'INVITED(owner_signed_up)'
      WHEN c.user_id IS NULL
           AND NOT EXISTS (SELECT 1 FROM company_member cm WHERE cm.company_id = c.id AND cm.deleted_at IS NULL)
           AND NOT EXISTS (SELECT 1 FROM company_subscription s WHERE s.company_id = c.id AND s.invitation_code_used_at IS NOT NULL)
           AND EXISTS (SELECT 1 FROM company_subscription s WHERE s.company_id = c.id AND s.invitation_code IS NOT NULL AND s.invitation_code_used_at IS NULL)
        THEN 'INVITED(code_unused)'
      ELSE 'ACTIVE'
    END AS predicted_status
  FROM company c
),
child AS (
  SELECT 'store'::text AS kind, 'VENDOR'::text AS grp, s.id, s.company_id AS parent_id FROM store s WHERE s.deleted_at IS NULL
  UNION ALL SELECT 'restaurant', 'BUYER', r.id, r.company_id FROM restaurant r WHERE r.deleted_at IS NULL AND r.company_id IS NOT NULL
  UNION ALL SELECT 'manufacturer_subdivision', 'MANUFACTURER', ms.id, ms.manufacturer_company_id FROM manufacturer_subdivision ms WHERE ms.deleted_at IS NULL
),
own AS (
  SELECT m.store_id AS child_id, bool_or(m.is_active AND u.deleted_at IS NULL) AS usable
  FROM store_member m JOIN "user" u ON u.id = m.user_id WHERE m.deleted_at IS NULL GROUP BY m.store_id
  UNION ALL
  SELECT m.restaurant_id, bool_or(m.is_active AND u.deleted_at IS NULL)
  FROM restaurant_member m JOIN "user" u ON u.id = m.user_id WHERE m.deleted_at IS NULL GROUP BY m.restaurant_id
  UNION ALL
  SELECT m.manufacturer_subdivision_id, bool_or(m.is_active AND u.deleted_at IS NULL)
  FROM manufacturer_subdivision_member m JOIN "user" u ON u.id = m.user_id WHERE m.deleted_at IS NULL GROUP BY m.manufacturer_subdivision_id
),
own_all AS (
  SELECT user_id, store_id AS child_id FROM store_member
  UNION ALL SELECT user_id, restaurant_id FROM restaurant_member
  UNION ALL SELECT user_id, manufacturer_subdivision_id FROM manufacturer_subdivision_member
),
role_code AS (
  SELECT id, type::text AS grp, belongs_to_company, deleted_at,
         btrim(regexp_replace(lower(name), '[^a-z0-9]+', '_', 'g'), '_') AS code
  FROM role
),
copied AS (
  SELECT ch.id AS child_id, bool_or(cm.is_active AND u.deleted_at IS NULL) AS usable
  FROM child ch
  JOIN company_member cm ON cm.company_id = ch.parent_id AND cm.deleted_at IS NULL
  JOIN role_code rc ON rc.id = cm.role_id
  JOIN "user" u ON u.id = cm.user_id
  WHERE (EXISTS (SELECT 1 FROM role_code f WHERE f.grp = ch.grp AND NOT f.belongs_to_company AND f.deleted_at IS NULL AND f.code = rc.code)
         OR (rc.code = 'ceo' AND NOT EXISTS (SELECT 1 FROM role_code f WHERE f.grp = ch.grp AND NOT f.belongs_to_company AND f.code = 'ceo')))
    AND NOT EXISTS (SELECT 1 FROM own_all o WHERE o.user_id = cm.user_id AND o.child_id = ch.id)
  GROUP BY ch.id
),
staged_branch AS (
  SELECT store_id AS child_id FROM onboarding_store_member WHERE deleted_at IS NULL
  UNION SELECT restaurant_id FROM onboarding_restaurant_member WHERE deleted_at IS NULL
  UNION SELECT manufacturer_subdivision_id FROM onboarding_manufacturer_subdivision_member WHERE deleted_at IS NULL
)
SELECT ch.kind,
  coalesce(p.predicted_status, 'PARENT_MISSING') AS parent_predicted_status,
  count(*) AS live_branches,
  count(*) FILTER (WHERE p.deleted_at IS NOT NULL) AS parent_already_deleted,
  count(*) FILTER (WHERE o.child_id IS NULL AND cp.child_id IS NULL) AS no_live_account_after_upgrade,
  count(*) FILTER (WHERE NOT coalesce(o.usable, false) AND NOT coalesce(cp.usable, false)) AS no_usable_account_after_upgrade,
  count(*) FILTER (WHERE o.child_id IS NULL AND cp.child_id IS NULL AND sb.child_id IS NOT NULL) AS no_account_but_staged_team
FROM child ch
LEFT JOIN parent p ON p.id = ch.parent_id
LEFT JOIN own o ON o.child_id = ch.id
LEFT JOIN copied cp ON cp.child_id = ch.id
LEFT JOIN staged_branch sb ON sb.child_id = ch.id
GROUP BY 1, 2
ORDER BY 1, 2
LIMIT 20;
\echo ##### pre_b5e1_member_roles_unmapped [无独立编号（b5e1d7c3a920 RuntimeError，涉及成员/账号角色）]
WITH role_code AS (
  SELECT id, type::text AS grp, belongs_to_company, deleted_at,
         btrim(regexp_replace(lower(name), '[^a-z0-9]+', '_', 'g'), '_') AS code
  FROM role
),
refs AS (
  SELECT role_id, 'company_member'::text AS tbl FROM company_member
  UNION ALL SELECT role_id, 'store_member' FROM store_member
  UNION ALL SELECT role_id, 'restaurant_member' FROM restaurant_member
  UNION ALL SELECT role_id, 'manufacturer_subdivision_member' FROM manufacturer_subdivision_member
  UNION ALL SELECT role_id, 'onboarding_company_member' FROM onboarding_company_member
  UNION ALL SELECT role_id, 'onboarding_store_member' FROM onboarding_store_member
  UNION ALL SELECT role_id, 'onboarding_restaurant_member' FROM onboarding_restaurant_member
  UNION ALL SELECT role_id, 'onboarding_manufacturer_subdivision_member' FROM onboarding_manufacturer_subdivision_member
  UNION ALL SELECT role_id, 'order_history' FROM order_history
  UNION ALL SELECT role_id, 'order_invoice_history' FROM order_invoice_history
  UNION ALL SELECT role_id, 'order_packing_slip_history' FROM order_packing_slip_history
)
SELECT rc.id AS role_id, rc.grp AS role_business_type, rc.code AS role_code, refs.tbl AS referenced_from, count(*) AS rows_referencing
FROM refs JOIN role_code rc ON rc.id = refs.role_id
WHERE rc.belongs_to_company
  AND NOT EXISTS (SELECT 1 FROM role_code f WHERE f.grp = rc.grp AND NOT f.belongs_to_company AND f.deleted_at IS NULL AND f.code = rc.code)
  AND NOT (rc.code = 'ceo' AND NOT EXISTS (SELECT 1 FROM role_code f WHERE f.grp = rc.grp AND NOT f.belongs_to_company AND f.code = 'ceo'))
GROUP BY rc.id, rc.grp, rc.code, refs.tbl
ORDER BY rows_referencing DESC
LIMIT 20;
