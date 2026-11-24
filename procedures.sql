USE campus_remarket;

DELIMITER $$

-- ACCESS CONTROL: stops the procedure unless the user has one of the roles
-- usage: CALL sp_require(p_user, 'admin,seller');
CREATE PROCEDURE sp_require(IN p_user INT, IN p_roles VARCHAR(50))
BEGIN
  DECLARE v_role VARCHAR(10);
  SELECT role INTO v_role FROM users WHERE user_id = p_user;
  IF v_role IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30401, MESSAGE_TEXT = 'Please log in';
  ELSEIF FIND_IN_SET(v_role, p_roles) = 0 THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30403, MESSAGE_TEXT = 'Not allowed for your role';
  END IF;
END$$


-- AUTH

-- CREATE user (password stored as salted SHA-256 hash)
CREATE PROCEDURE sp_register(IN p_name VARCHAR(255), IN p_email VARCHAR(255),
                             IN p_password VARCHAR(255), IN p_role VARCHAR(20))
BEGIN
  DECLARE v_salt CHAR(32);
  SET p_name  = NULLIF(TRIM(p_name), '');
  SET p_email = LOWER(TRIM(p_email));

  IF p_name IS NULL OR CHAR_LENGTH(p_name) > 80 THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Name is required (max 80 chars)';
  END IF;
  IF p_email IS NULL OR p_email NOT REGEXP '^[A-Za-z0-9._+-]+@[A-Za-z0-9-]+([.][A-Za-z0-9-]+)+$' THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Invalid email format';
  END IF;
  IF p_password IS NULL OR CHAR_LENGTH(p_password) < 6 THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Password must be at least 6 characters';
  END IF;
  IF p_role IS NULL OR p_role NOT IN ('buyer','seller') THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Role must be buyer or seller';
  END IF;

  SET v_salt = MD5(RAND());
  INSERT INTO users(name, email, salt, password_hash, role)
  VALUES (p_name, p_email, v_salt, SHA2(CONCAT(v_salt, p_password), 256), p_role);
END$$

CREATE PROCEDURE sp_login(IN p_email VARCHAR(255), IN p_password VARCHAR(255))
BEGIN
  DECLARE v_id INT;
  SELECT user_id INTO v_id FROM users
   WHERE email = LOWER(TRIM(p_email)) AND password_hash = SHA2(CONCAT(salt, p_password), 256);
  IF v_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30401, MESSAGE_TEXT = 'Wrong email or password';
  END IF;
  SELECT user_id, name, role FROM users WHERE user_id = v_id;
END$$


-- CATEGORIES (admin CRUD)

CREATE PROCEDURE sp_category_list()
BEGIN
  SELECT * FROM categories ORDER BY name;
END$$

CREATE PROCEDURE sp_category_add(IN p_user INT, IN p_name VARCHAR(255))
BEGIN
  CALL sp_require(p_user, 'admin');
  SET p_name = NULLIF(TRIM(p_name), '');
  IF p_name IS NULL OR CHAR_LENGTH(p_name) > 60 THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Category name required (max 60 chars)';
  END IF;
  INSERT INTO categories(name) VALUES (p_name);
END$$

CREATE PROCEDURE sp_category_update(IN p_user INT, IN p_id INT, IN p_name VARCHAR(255))
BEGIN
  CALL sp_require(p_user, 'admin');
  SET p_name = NULLIF(TRIM(p_name), '');
  IF p_name IS NULL OR CHAR_LENGTH(p_name) > 60 THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Category name required (max 60 chars)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM categories WHERE category_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30404, MESSAGE_TEXT = 'Category not found';
  END IF;
  UPDATE categories SET name = p_name WHERE category_id = p_id;
END$$

-- a category that still has products is blocked by the FOREIGN KEY (ON DELETE RESTRICT)
CREATE PROCEDURE sp_category_delete(IN p_user INT, IN p_id INT)
BEGIN
  CALL sp_require(p_user, 'admin');
  IF NOT EXISTS (SELECT 1 FROM categories WHERE category_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30404, MESSAGE_TEXT = 'Category not found';
  END IF;
  DELETE FROM categories WHERE category_id = p_id;
END$$


-- USERS (admin)

CREATE PROCEDURE sp_user_list(IN p_user INT)
BEGIN
  CALL sp_require(p_user, 'admin');
  SELECT user_id, name, email, role, created_at FROM users ORDER BY user_id;
END$$

CREATE PROCEDURE sp_user_delete(IN p_user INT, IN p_id INT)
BEGIN
  CALL sp_require(p_user, 'admin');
  IF NOT EXISTS (SELECT 1 FROM users WHERE user_id = p_id AND role <> 'admin') THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30404, MESSAGE_TEXT = 'User not found, or is an admin';
  END IF;
  DELETE FROM users WHERE user_id = p_id;   -- blocked by FK if the user has listings/orders
END$$


-- PRODUCTS

-- READ approved, in-stock listings with search / filter / sort
CREATE PROCEDURE sp_product_browse(IN p_user INT, IN p_q VARCHAR(100), IN p_category VARCHAR(20),
                                   IN p_type VARCHAR(20), IN p_sort VARCHAR(20))
BEGIN
  CALL sp_require(p_user, 'admin,buyer,seller');
  SELECT * FROM v_product_listing
   WHERE status = 'approved' AND quantity > 0
     AND (p_q IS NULL OR title LIKE CONCAT('%', p_q, '%') OR description LIKE CONCAT('%', p_q, '%'))
     AND (p_category IS NULL OR category_id = p_category)
     AND (p_type IS NULL OR listing_type = p_type)
   ORDER BY CASE WHEN p_sort = 'price_asc'  THEN price END ASC,
            CASE WHEN p_sort = 'price_desc' THEN price END DESC,
            product_id DESC;
END$$

-- READ the seller's own listings
CREATE PROCEDURE sp_product_mine(IN p_user INT)
BEGIN
  CALL sp_require(p_user, 'seller');
  SELECT * FROM v_product_listing WHERE seller_id = p_user ORDER BY product_id DESC;
END$$

-- READ listings waiting for admin approval
CREATE PROCEDURE sp_product_pending(IN p_user INT)
BEGIN
  CALL sp_require(p_user, 'admin');
  SELECT * FROM v_product_listing WHERE status = 'pending';
END$$

-- CREATE listing (starts as 'pending' because status has DEFAULT 'pending')
CREATE PROCEDURE sp_product_add(IN p_user INT, IN p_category INT, IN p_title VARCHAR(255),
                                IN p_description TEXT, IN p_type VARCHAR(20),
                                IN p_price DECIMAL(12,2), IN p_quantity INT)
BEGIN
  CALL sp_require(p_user, 'seller');
  SET p_title = NULLIF(TRIM(p_title), '');
  IF p_title IS NULL OR CHAR_LENGTH(p_title) > 120 THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Title is required (max 120 chars)';
  END IF;
  IF p_type IS NULL OR p_type NOT IN ('sell','rent','exchange') THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Invalid listing type';
  END IF;
  IF p_price IS NULL OR p_price < 0 THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Price must be a number >= 0';
  END IF;
  IF p_quantity IS NULL OR p_quantity < 0 THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Quantity cannot be negative';
  END IF;
  INSERT INTO products(seller_id, category_id, title, description, listing_type, price, quantity)
  VALUES (p_user, p_category, p_title, p_description, p_type, p_price, p_quantity);
END$$

-- UPDATE own listing; edits go back to 'pending' for re-approval
CREATE PROCEDURE sp_product_update(IN p_user INT, IN p_id INT, IN p_title VARCHAR(255),
                                   IN p_price DECIMAL(12,2), IN p_quantity INT)
BEGIN
  CALL sp_require(p_user, 'seller');
  SET p_title = NULLIF(TRIM(p_title), '');
  IF p_title IS NULL OR CHAR_LENGTH(p_title) > 120 OR p_quantity IS NULL OR p_quantity < 0 THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Invalid title or quantity';
  END IF;
  IF p_price IS NULL OR p_price < 0 THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Price must be a number >= 0';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM products WHERE product_id = p_id AND seller_id = p_user) THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30404, MESSAGE_TEXT = 'Listing not found or not yours';
  END IF;
  UPDATE products SET title = p_title, price = p_price, quantity = p_quantity, status = 'pending'
   WHERE product_id = p_id AND seller_id = p_user;
END$$

-- DELETE listing: seller deletes own, admin deletes any.
CREATE PROCEDURE sp_product_delete(IN p_user INT, IN p_id INT)
BEGIN
  DECLARE v_role VARCHAR(10);
  CALL sp_require(p_user, 'seller,admin');
  SELECT role INTO v_role FROM users WHERE user_id = p_user;
  IF NOT EXISTS (SELECT 1 FROM products WHERE product_id = p_id AND (v_role = 'admin' OR seller_id = p_user)) THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30404, MESSAGE_TEXT = 'Listing not found or not yours';
  END IF;
  DELETE FROM products WHERE product_id = p_id;
END$$

-- UPDATE status: admin approves or rejects a listing
CREATE PROCEDURE sp_product_moderate(IN p_user INT, IN p_id INT, IN p_action VARCHAR(10))
BEGIN
  CALL sp_require(p_user, 'admin');
  IF p_action IS NULL OR p_action NOT IN ('approve','reject') THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Invalid action';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM products WHERE product_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30404, MESSAGE_TEXT = 'Not found';
  END IF;
  UPDATE products SET status = IF(p_action = 'approve', 'approved', 'rejected') WHERE product_id = p_id;
END$$

-- ORDERS: ONE TRANSACTION = order + payment (+ stock update by trigger)

CREATE PROCEDURE sp_order_place(IN p_user INT, IN p_product INT, IN p_quantity INT,
                                IN p_method VARCHAR(20), IN p_rent_days INT,
                                IN p_offered_item VARCHAR(200), IN p_simulate_failure BOOLEAN)
BEGIN
  DECLARE v_type  VARCHAR(10);
  DECLARE v_price DECIMAL(10,2);
  DECLARE v_total DECIMAL(10,2);
  DECLARE v_order INT;

  --- on any error: undo everything, then pass the same error to Python
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    RESIGNAL;
  END;

  CALL sp_require(p_user, 'buyer');
  IF p_quantity IS NULL OR p_quantity < 1 THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Quantity must be at least 1';
  END IF;

  START TRANSACTION;

  --- lock the product row so two buyers cannot take the same stock
  SELECT listing_type, price INTO v_type, v_price
    FROM products WHERE product_id = p_product AND status = 'approved' FOR UPDATE;
  IF v_type IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30404, MESSAGE_TEXT = 'Product not available';
  END IF;

  SET v_total = v_price * p_quantity;
  IF v_type = 'rent' THEN
    IF p_rent_days IS NULL OR p_rent_days < 1 THEN
      SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Rental days must be at least 1';
    END IF;
    SET v_total = v_total * p_rent_days;
  END IF;
  IF v_type = 'exchange' THEN
    IF p_offered_item IS NULL THEN
      SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Describe the item you offer';
    END IF;
    SET p_method = 'exchange';
    SET v_total  = 0;
  ELSEIF p_method IS NULL OR p_method NOT IN ('upi','card','cash') THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Payment method must be upi, card or cash';
  END IF;

  INSERT INTO orders(buyer_id, product_id, quantity, rent_days, offered_item, total_amount)
  VALUES (p_user, p_product, p_quantity,
          IF(v_type = 'rent', p_rent_days, NULL), p_offered_item, v_total);
  SET v_order = LAST_INSERT_ID();

  -- demo of rollback: fail AFTER the order was inserted
  IF p_simulate_failure THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30500,
      MESSAGE_TEXT = 'Simulated failure: transaction rolled back, nothing saved';
  END IF;

  INSERT INTO payments(order_id, method) VALUES (v_order, p_method);

  COMMIT;
  SELECT v_order AS orderId, v_total AS total;
END$$

--- READ orders: buyer sees own purchases, seller sees orders on own listings, admin sees all
CREATE PROCEDURE sp_order_list(IN p_user INT)
BEGIN
  DECLARE v_role VARCHAR(10);
  CALL sp_require(p_user, 'admin,buyer,seller');
  SELECT role INTO v_role FROM users WHERE user_id = p_user;
  SELECT * FROM v_order_details
   WHERE v_role = 'admin'
      OR (v_role = 'buyer'  AND buyer_id  = p_user)
      OR (v_role = 'seller' AND seller_id = p_user)
   ORDER BY order_id DESC;
END$$

--- UPDATE order status: seller marks an order on their own listing as completed
CREATE PROCEDURE sp_order_complete(IN p_user INT, IN p_id INT)
BEGIN
  CALL sp_require(p_user, 'seller');
  IF NOT EXISTS (SELECT 1 FROM v_order_details
                  WHERE order_id = p_id AND seller_id = p_user AND status = 'placed') THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30404,
      MESSAGE_TEXT = 'Order not found, not yours, or already completed';
  END IF;
  UPDATE orders SET status = 'completed' WHERE order_id = p_id;
END$$


-- WISHLIST (buyer)

CREATE PROCEDURE sp_wishlist_list(IN p_user INT)
BEGIN
  CALL sp_require(p_user, 'buyer');
  SELECT p.product_id, p.title, p.listing_type, p.price, p.quantity
    FROM wishlist w JOIN products p ON w.product_id = p.product_id
   WHERE w.user_id = p_user;
END$$

CREATE PROCEDURE sp_wishlist_add(IN p_user INT, IN p_product INT)
BEGIN
  CALL sp_require(p_user, 'buyer');
  INSERT IGNORE INTO wishlist(user_id, product_id) VALUES (p_user, p_product);   -- saving twice is ignored
END$$

CREATE PROCEDURE sp_wishlist_remove(IN p_user INT, IN p_product INT)
BEGIN
  CALL sp_require(p_user, 'buyer');
  DELETE FROM wishlist WHERE user_id = p_user AND product_id = p_product;
END$$


-- REVIEWS

CREATE PROCEDURE sp_review_add(IN p_user INT, IN p_product INT, IN p_rating INT, IN p_comment VARCHAR(500))
BEGIN
  CALL sp_require(p_user, 'buyer');
  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Rating must be between 1 and 5';
  END IF;
  INSERT INTO reviews(product_id, buyer_id, rating, comment) VALUES (p_product, p_user, p_rating, p_comment);
END$$


-- COMPLAINTS

CREATE PROCEDURE sp_complaint_add(IN p_user INT, IN p_order INT, IN p_description VARCHAR(1000))
BEGIN
  CALL sp_require(p_user, 'buyer');
  IF p_description IS NULL OR CHAR_LENGTH(p_description) > 500 THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Description required (max 500 chars)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM orders WHERE order_id = p_order AND buyer_id = p_user) THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30403, MESSAGE_TEXT = 'That is not your order';
  END IF;
  INSERT INTO complaints(order_id, raised_by, description) VALUES (p_order, p_user, p_description);
END$$

CREATE PROCEDURE sp_complaint_list(IN p_user INT)
BEGIN
  DECLARE v_role VARCHAR(10);
  CALL sp_require(p_user, 'buyer,admin');
  SELECT role INTO v_role FROM users WHERE user_id = p_user;
  SELECT * FROM complaints WHERE v_role = 'admin' OR raised_by = p_user ORDER BY complaint_id DESC;
END$$

CREATE PROCEDURE sp_complaint_resolve(IN p_user INT, IN p_id INT, IN p_resolution VARCHAR(1000))
BEGIN
  CALL sp_require(p_user, 'admin');
  IF p_resolution IS NULL OR CHAR_LENGTH(p_resolution) > 500 THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30400, MESSAGE_TEXT = 'Resolution text required (max 500 chars)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM complaints WHERE complaint_id = p_id) THEN
    SIGNAL SQLSTATE '45000' SET MYSQL_ERRNO = 30404, MESSAGE_TEXT = 'Not found';
  END IF;
  UPDATE complaints SET status = 'resolved', resolution = p_resolution WHERE complaint_id = p_id;
END$$


-- REPORTS (use the views; admin sees all sellers, a seller sees only themself)

CREATE PROCEDURE sp_report_sales(IN p_user INT)
BEGIN
  DECLARE v_role VARCHAR(10);
  CALL sp_require(p_user, 'admin,seller');
  SELECT role INTO v_role FROM users WHERE user_id = p_user;
  SELECT * FROM v_sales_by_seller WHERE v_role = 'admin' OR seller_id = p_user ORDER BY revenue DESC;
END$$

CREATE PROCEDURE sp_report_categories(IN p_user INT)
BEGIN
  CALL sp_require(p_user, 'admin');
  SELECT * FROM v_sales_by_category ORDER BY revenue DESC;
END$$

DELIMITER ;
