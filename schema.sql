DROP DATABASE IF EXISTS campus_remarket;
CREATE DATABASE campus_remarket;
USE campus_remarket;

CREATE TABLE users(
  user_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(80) NOT NULL,
  email VARCHAR(120) NOT NULL UNIQUE,
  salt CHAR(32) NOT NULL,
  password_hash CHAR(64) NOT NULL,
  role ENUM('admin','buyer','seller') NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);

CREATE TABLE categories(
  category_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(60) NOT NULL UNIQUE);

CREATE TABLE products(
  product_id INT AUTO_INCREMENT PRIMARY KEY,
  seller_id INT NOT NULL, category_id INT NOT NULL,
  title VARCHAR(120) NOT NULL, description TEXT,
  listing_type ENUM('sell','rent','exchange') NOT NULL,
  price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
  quantity INT NOT NULL CHECK (quantity >= 0),
  status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  FOREIGN KEY (seller_id) REFERENCES users(user_id) ON DELETE RESTRICT,
  FOREIGN KEY (category_id) REFERENCES categories(category_id) ON DELETE RESTRICT);

CREATE TABLE orders(
  order_id INT AUTO_INCREMENT PRIMARY KEY,
  buyer_id INT NOT NULL, product_id INT NOT NULL,
  quantity INT NOT NULL CHECK (quantity > 0),
  rent_days INT NULL CHECK (rent_days IS NULL OR rent_days > 0),
  offered_item VARCHAR(200) NULL,
  total_amount DECIMAL(10,2) NOT NULL CHECK (total_amount >= 0),
  status ENUM('placed','completed','cancelled') NOT NULL DEFAULT 'placed',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (buyer_id) REFERENCES users(user_id) ON DELETE RESTRICT,
  FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE RESTRICT);

CREATE TABLE payments(
  payment_id INT AUTO_INCREMENT PRIMARY KEY,
  order_id INT NOT NULL UNIQUE,
  method ENUM('upi','card','cash','exchange') NOT NULL,
  status ENUM('paid','pending','refunded') NOT NULL DEFAULT 'paid',
  paid_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE RESTRICT);

CREATE TABLE reviews(
  review_id INT AUTO_INCREMENT PRIMARY KEY,
  product_id INT NOT NULL, buyer_id INT NOT NULL,
  rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment VARCHAR(500),
  UNIQUE (product_id, buyer_id),
  FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE RESTRICT,
  FOREIGN KEY (buyer_id) REFERENCES users(user_id) ON DELETE RESTRICT);

CREATE TABLE wishlist(
  user_id INT NOT NULL, product_id INT NOT NULL,
  PRIMARY KEY (user_id, product_id),
  FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(product_id) ON DELETE CASCADE);

CREATE TABLE complaints(
  complaint_id INT AUTO_INCREMENT PRIMARY KEY,
  order_id INT NOT NULL, raised_by INT NOT NULL,
  description VARCHAR(500) NOT NULL,
  status ENUM('open','resolved') NOT NULL DEFAULT 'open',
  resolution VARCHAR(500),
  FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE RESTRICT,
  FOREIGN KEY (raised_by) REFERENCES users(user_id) ON DELETE RESTRICT);

INSERT INTO categories(name) VALUES ('Textbooks'),('Electronics'),('Lab Equipment'),('Furniture'),('Sports'),('Other');
