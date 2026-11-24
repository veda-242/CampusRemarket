USE campus_remarket;

-- VIEWS: saved SELECT queries (JOINs + aggregates) that procedures reuse

-- Product + category name + seller name + average rating
CREATE OR REPLACE VIEW v_product_listing AS
SELECT p.*, c.name AS category, u.name AS seller,
       (SELECT ROUND(AVG(r.rating),1) FROM reviews r WHERE r.product_id = p.product_id) AS rating
FROM products p
JOIN categories c ON p.category_id = c.category_id
JOIN users u      ON p.seller_id   = u.user_id;

-- One readable row per order: joins orders, products, buyer, seller, payments
CREATE OR REPLACE VIEW v_order_details AS
SELECT o.order_id, o.product_id, p.title, p.listing_type AS order_type,
       o.buyer_id, b.name AS buyer, p.seller_id, s.name AS seller,
       o.quantity, o.rent_days, o.total_amount, py.method, o.status
FROM orders o
JOIN products p ON o.product_id = p.product_id
JOIN users b    ON o.buyer_id   = b.user_id
JOIN users s    ON p.seller_id  = s.user_id
LEFT JOIN payments py ON py.order_id = o.order_id;

-- REPORT: revenue per seller (JOIN + GROUP BY + COUNT/SUM)
CREATE OR REPLACE VIEW v_sales_by_seller AS
SELECT u.user_id AS seller_id, u.name AS seller,
       COUNT(o.order_id) AS orders, SUM(o.total_amount) AS revenue
FROM orders o
JOIN products p ON o.product_id = p.product_id
JOIN users u    ON p.seller_id  = u.user_id
WHERE o.status <> 'cancelled'
GROUP BY u.user_id, u.name;

-- REPORT: sales per category
CREATE OR REPLACE VIEW v_sales_by_category AS
SELECT c.name AS category, COUNT(o.order_id) AS orders,
       SUM(o.quantity) AS units, SUM(o.total_amount) AS revenue
FROM orders o
JOIN products p   ON o.product_id  = p.product_id
JOIN categories c ON p.category_id = c.category_id
WHERE o.status <> 'cancelled'
GROUP BY c.category_id, c.name;

-- TRIGGERS: business rules the database enforces by itself
DELIMITER $$

-- RULE: you cannot buy your own listing, and stock cannot go below zero
CREATE TRIGGER trg_orders_before_insert BEFORE INSERT ON orders
FOR EACH ROW
BEGIN
  DECLARE v_seller INT;
  DECLARE v_stock  INT;
  DECLARE v_msg    VARCHAR(100);
  SELECT seller_id, quantity INTO v_seller, v_stock
    FROM products WHERE product_id = NEW.product_id;
  IF v_seller = NEW.buyer_id THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30403, MESSAGE_TEXT = 'You cannot buy your own listing';
  END IF;
  IF v_stock < NEW.quantity THEN
    SET v_msg = CONCAT('Insufficient stock (available: ', v_stock, ')');
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30409, MESSAGE_TEXT = v_msg;
  END IF;
END$$

-- AUTOMATIC STOCK UPDATE: every new order reduces the product quantity
CREATE TRIGGER trg_orders_after_insert AFTER INSERT ON orders
FOR EACH ROW
BEGIN
  UPDATE products SET quantity = quantity - NEW.quantity WHERE product_id = NEW.product_id;
END$$

-- RULE: a review is allowed only after a completed order for that product
CREATE TRIGGER trg_reviews_before_insert BEFORE INSERT ON reviews
FOR EACH ROW
BEGIN
  IF NOT EXISTS (SELECT 1 FROM orders
                 WHERE buyer_id = NEW.buyer_id AND product_id = NEW.product_id AND status = 'completed') THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30403, MESSAGE_TEXT = 'You can review only after a completed order';
  END IF;
END$$

DELIMITER ;
