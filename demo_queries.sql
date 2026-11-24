USE campus_remarket;

START TRANSACTION;

-- CREATE (INSERT)
INSERT INTO categories(name) VALUES ('Stationery');
INSERT INTO products(seller_id, category_id, title, description, listing_type, price, quantity) VALUES (2, 1, 'Data Structures Book', 'Like new', 'sell', 300, 2);

-- READ (SELECT)
SELECT * FROM products;
SELECT title, price FROM products WHERE listing_type = 'sell' AND price > 100 ORDER BY price DESC;
SELECT title FROM products WHERE title LIKE '%book%';
SELECT p.title, c.name AS category, u.name AS seller
  FROM products p
  JOIN categories c ON p.category_id = c.category_id
  JOIN users u      ON p.seller_id   = u.user_id;

-- UPDATE
UPDATE products SET status = 'approved' WHERE title = 'Data Structures Book';   -- admin approves
UPDATE products SET price = 280, quantity = 5 WHERE title = 'Data Structures Book';

-- DELETE
DELETE FROM products WHERE title = 'Data Structures Book';

-- AGGREGATE: GROUP BY + COUNT/SUM/AVG
SELECT listing_type, COUNT(*) AS listings, AVG(price) AS avg_price
  FROM products GROUP BY listing_type;
SELECT * FROM v_sales_by_seller;

-- CALL a stored procedure
CALL sp_product_browse(3, NULL, NULL, 'rent', 'price_asc');

-- TRANSACTION + TRIGGER
SELECT quantity AS stock_before FROM products WHERE product_id = 1;
INSERT INTO orders(buyer_id, product_id, quantity, total_amount) VALUES (3, 1, 1, 250);
SELECT quantity AS stock_after  FROM products WHERE product_id = 1;

ROLLBACK;
