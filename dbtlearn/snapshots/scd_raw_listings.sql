{% snapshot scd_raw_listings %}

{{
   config(
       target_schema='DEV',
       unique_key='listing_id',
       strategy='timestamp',
       updated_at='updated_at',
       invalidate_hard_deletes=True
   )
}}

select * FROM {{ ref('dim_listings_cleansed') }}

{% endsnapshot %}