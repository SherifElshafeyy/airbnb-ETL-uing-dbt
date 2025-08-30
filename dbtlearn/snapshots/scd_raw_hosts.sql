{% snapshot scd_raw_hosts %}

{{
   config(
       
       target_schema='dev',
       unique_key='host_id',

       strategy='timestamp',
       updated_at='updated_at',
   )
}}

select * from {{ ref('dim_hosts_cleansed') }}


{% endsnapshot %}
