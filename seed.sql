USE campus_remarket;

-- Demo users (password for all three: pass123). Same hashing as sp_register.
INSERT INTO users(name, email, salt, password_hash, role) VALUES
 ('Admin',       'admin@campus.edu',  'salt-admin',  SHA2(CONCAT('salt-admin',  'pass123'), 256), 'admin'),
 ('Sita Seller', 'seller@campus.edu', 'salt-seller', SHA2(CONCAT('salt-seller', 'pass123'), 256), 'seller'),
 ('Bob Buyer',   'buyer@campus.edu',  'salt-buyer',  SHA2(CONCAT('salt-buyer',  'pass123'), 256), 'buyer');

SET @seller = (SELECT user_id FROM users WHERE email = 'seller@campus.edu');

INSERT INTO products(seller_id, category_id, title, description, listing_type, price, quantity, status) VALUES
 (@seller, 1, 'Engineering Maths Textbook', 'Good condition', 'sell',     250, 3, 'approved'),
 (@seller, 2, 'Scientific Calculator',      'Casio fx-991',   'rent',      20, 2, 'approved'),
 (@seller, 3, 'Lab Coat (M)',               'Barely used',    'exchange',   0, 1, 'approved');
