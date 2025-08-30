/* Make sure that every review_date in fct_reviews is more recent 
   than the associated created_at in dim_listings_cleansed. */

SELECT * FROM {{ ref('dim_listings_cleansed') }} l
INNER JOIN {{ ref('fct_reviews') }} r
USING (listing_id)
WHERE l.created_at >= r.review_date