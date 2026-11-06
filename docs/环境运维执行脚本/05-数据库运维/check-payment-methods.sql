-- 付款方式枚举一致性核查（只读）。用法示例见 docs/付款方式枚举一致性排查报告-2026-10-27.md 第六节。
-- psql -h <RDS端点> -U <账号> -d <库名> -f check-payment-methods.sql

\echo '### alembic_version'
select version_num from alembic_version;
\echo '### enum paymentmethod labels'
select e.enumlabel, e.enumsortorder from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='paymentmethod' order by e.enumsortorder;
\echo '### enum orderpaymenttype labels'
select e.enumlabel from pg_enum e join pg_type t on t.oid=e.enumtypid where t.typname='orderpaymenttype' order by e.enumsortorder;
\echo '### payment_method table columns'
select column_name, data_type from information_schema.columns where table_name='payment_method' order by ordinal_position;
\echo '### payment_method rows'
select id, name, code, sort_order, is_system, created_at, deleted_at from payment_method order by sort_order nulls last, name;
\echo '### columns typed paymentmethod or named *payment_method*'
select table_name||'.'||column_name||' : '||udt_name from information_schema.columns where udt_name in ('paymentmethod','_paymentmethod') or column_name ilike '%payment_method%' order by 1;
\echo '### client_finances.payment_methods'
select unnest(payment_methods) as v, count(*) from client_finances group by 1 order by 2 desc;
\echo '### order.payment_method'
select payment_method, count(*) from "order" group by 1 order by 2 desc;
\echo '### order_payment.payment_method'
select payment_method, count(*) from order_payment group by 1 order by 2 desc;
\echo '### order_packing_slip.received_payment_method'
select received_payment_method, count(*) from order_packing_slip group by 1 order by 2 desc;
\echo '### order_invoice_payment_record.paymentmethod'
select paymentmethod, count(*) from order_invoice_payment_record group by 1 order by 2 desc;
\echo '### order_invoice_transaction.payment_method'
select payment_method, count(*) from order_invoice_transaction group by 1 order by 2 desc;
\echo '### quotation.payment_method (varchar)'
select payment_method, count(*) from quotation group by 1 order by 2 desc;
\echo '### company_subscription.payment_method_id -> payment_method'
select cs.payment_method_id, pm.name, pm.code, count(*) from company_subscription cs left join payment_method pm on pm.id=cs.payment_method_id group by 1,2,3 order by 4 desc;
