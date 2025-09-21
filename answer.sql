-- farmers_coop_db.sql
-- Database for Farmer <-> Cooperative Marketplace


CREATE DATABASE farmers_coop_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE farmers_coop_db;

-- 1) Users table: stores all accounts (farmer, coop_admin, buyer, admin)
CREATE TABLE users (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('farmer','coop','buyer','admin') NOT NULL DEFAULT 'farmer',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 2) Farmers profile (one-to-one with users when role='farmer')
CREATE TABLE farmers (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL UNIQUE,
    full_name VARCHAR(150) NOT NULL,
    phone VARCHAR(30),
    village VARCHAR(150),
    latitude DECIMAL(9,6),
    longitude DECIMAL(9,6),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 3) Cooperatives profile (one-to-one with users when role='coop')
CREATE TABLE cooperatives (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT UNSIGNED NOT NULL UNIQUE,
    coop_name VARCHAR(200) NOT NULL,
    registration_number VARCHAR(100) UNIQUE,
    contact_phone VARCHAR(30),
    address VARCHAR(255),
    latitude DECIMAL(9,6),
    longitude DECIMAL(9,6),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 4) Farmer <-> Cooperative membership (Many-to-Many)
CREATE TABLE farmer_coop_memberships (
    farmer_id BIGINT UNSIGNED NOT NULL,
    coop_id BIGINT UNSIGNED NOT NULL,
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    role_in_coop ENUM('member','officer') DEFAULT 'member',
    PRIMARY KEY (farmer_id, coop_id),
    FOREIGN KEY (farmer_id) REFERENCES farmers(id) ON DELETE CASCADE,
    FOREIGN KEY (coop_id) REFERENCES cooperatives(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 5) Product categories
CREATE TABLE categories (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT
) ENGINE=InnoDB;

-- 6) Products (created by farmers)
CREATE TABLE products (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    farmer_id BIGINT UNSIGNED NOT NULL,
    category_id INT UNSIGNED,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    unit VARCHAR(50) NOT NULL, -- e.g., kg, bag, litre
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (farmer_id) REFERENCES farmers(id) ON DELETE CASCADE,
    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
) ENGINE=InnoDB;



-- Create the table WITHOUT the problematic CHECK
CREATE TABLE coop_product_offers (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    coop_id BIGINT UNSIGNED NOT NULL,
    product_id BIGINT UNSIGNED NULL,
    category_id INT UNSIGNED NULL,
    price_per_unit DECIMAL(12,2) NOT NULL,
    min_quantity DECIMAL(12,2) DEFAULT 0,
    max_quantity DECIMAL(12,2) DEFAULT NULL,
    currency CHAR(3) DEFAULT 'KES',
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (coop_id) REFERENCES cooperatives(id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE SET NULL,
    FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- Trigger: enforce that at least product_id or category_id is set on INSERT
DELIMITER $$

CREATE TRIGGER trg_coop_offer_before_insert
BEFORE INSERT ON coop_product_offers
FOR EACH ROW
BEGIN
    IF (NEW.product_id IS NULL AND NEW.category_id IS NULL) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Either product_id or category_id must be provided';
    END IF;
END$$

-- Trigger: enforce same rule on UPDATE
CREATE TRIGGER trg_coop_offer_before_update
BEFORE UPDATE ON coop_product_offers
FOR EACH ROW
BEGIN
    IF (NEW.product_id IS NULL AND NEW.category_id IS NULL) THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Either product_id or category_id must be provided';
    END IF;
END$$

DELIMITER ;


-- 8) Orders: a cooperative places an order to buy from a farmer (or farmer sells to coop)
CREATE TABLE orders (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_number VARCHAR(50) NOT NULL UNIQUE,
    farmer_id BIGINT UNSIGNED NOT NULL,
    coop_id BIGINT UNSIGNED NOT NULL,
    status ENUM('pending','accepted','in_transit','completed','cancelled') DEFAULT 'pending',
    total_amount DECIMAL(14,2) NOT NULL DEFAULT 0.00,
    currency CHAR(3) DEFAULT 'KES',
    placed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (farmer_id) REFERENCES farmers(id) ON DELETE CASCADE,
    FOREIGN KEY (coop_id) REFERENCES cooperatives(id) ON DELETE CASCADE
) ENGINE=InnoDB;



CREATE TABLE order_items (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT UNSIGNED NOT NULL,
    product_id BIGINT UNSIGNED NOT NULL,
    quantity DECIMAL(12,3) NOT NULL,
    unit_price DECIMAL(12,2) NOT NULL,
    subtotal DECIMAL(14,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE RESTRICT
) ENGINE=InnoDB;


-- 10) Inventory (optional) - tracks available product quantities per farmer
CREATE TABLE inventory (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED NOT NULL UNIQUE,
    available_quantity DECIMAL(12,3) NOT NULL DEFAULT 0,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 11) Price history (audit of prices offered by coops or set by farmers)
CREATE TABLE price_history (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    product_id BIGINT UNSIGNED NOT NULL,
    source_type ENUM('farmer','coop') NOT NULL,
    source_id BIGINT UNSIGNED NOT NULL, -- farmer.id or cooperative.id depending on source_type
    price_per_unit DECIMAL(12,2) NOT NULL,
    currency CHAR(3) DEFAULT 'KES',
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
) ENGINE=InnoDB;


-- 12) Messages / negotiations between farmer and coop (simple chat log)
CREATE TABLE negotiations (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT UNSIGNED NULL,
    sender_user_id BIGINT UNSIGNED NOT NULL,
    receiver_user_id BIGINT UNSIGNED NOT NULL,
    message TEXT NOT NULL,
    sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    read_at TIMESTAMP NULL,
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE SET NULL,
    FOREIGN KEY (sender_user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (receiver_user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- 13) Helpful indexes to improve lookup speed (non-unique)
CREATE INDEX idx_products_farmer ON products(farmer_id);
CREATE INDEX idx_offers_coop ON coop_product_offers(coop_id);
CREATE INDEX idx_orders_coop ON orders(coop_id);
CREATE INDEX idx_orders_farmer ON orders(farmer_id);

-- 14) Example view: current active offers for a product (optional)
CREATE OR REPLACE VIEW active_offers AS
SELECT
    o.id AS offer_id,
    c.coop_name,
    o.coop_id,
    o.product_id,
    o.category_id,
    o.price_per_unit,
    o.min_quantity,
    o.max_quantity,
    o.currency,
    o.active
FROM coop_product_offers o
JOIN cooperatives c ON o.coop_id = c.id
WHERE o.active = TRUE;

-- done

-- 1) Add some users
INSERT INTO users (username, email, password_hash, role)
VALUES
('farmer_dan', 'dan@farm.com', 'hashedpass1', 'farmer'),
('coop_hope', 'hope@coop.com', 'hashedpass2', 'coop'),
('buyer_jane', 'jane@market.com', 'hashedpass3', 'buyer');

-- 2) Add farmer profile (linked to user farmer_dan)
INSERT INTO farmers (user_id, full_name, phone, village, latitude, longitude)
VALUES
(1, 'Dan Okoth', '+254700111111', 'Gweth Village', -0.091234, 34.761234);

-- 3) Add cooperative profile (linked to user coop_hope)
INSERT INTO cooperatives (user_id, coop_name, registration_number, contact_phone, address, latitude, longitude)
VALUES
(2, 'Hope Cooperative Society', 'COOP12345', '+254722222222', 'Kisumu Town', -0.089123, 34.759876);

-- 4) Link farmer to cooperative membership
INSERT INTO farmer_coop_memberships (farmer_id, coop_id, role_in_coop)
VALUES
(1, 1, 'member');

-- 5) Add categories
INSERT INTO categories (name, description)
VALUES
('Maize', 'All maize products'),
('Beans', 'Different varieties of beans');

-- 6) Add products (farmer creates them)
INSERT INTO products (farmer_id, category_id, name, description, unit)
VALUES
(1, 1, 'White Maize', 'Freshly harvested maize bags', 'bag'),
(1, 2, 'Red Beans', 'Organic red beans', 'kg');

-- 7) Coop makes an offer to buy Maize
INSERT INTO coop_product_offers (coop_id, product_id, price_per_unit, min_quantity, currency, active)
VALUES
(1, 1, 2500.00, 1, 'KES', TRUE);

-- 8) Create an order (farmer sells maize to coop)
INSERT INTO orders (order_number, farmer_id, coop_id, status, total_amount, currency)
VALUES
('ORD-1001', 1, 1, 'pending', 0.00, 'KES');

-- 9) Add order items (subtotal will auto-calc)
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES
(1, 1, 10, 2500.00);  -- 10 bags of maize @ 2500 each



-- VIEW: Farmer Sales History


CREATE OR REPLACE VIEW farmer_sales_history AS
SELECT
    f.id AS farmer_id,
    f.full_name AS farmer_name,
    c.coop_name,
    p.name AS product_name,
    oi.quantity,
    oi.unit_price,
    oi.subtotal,
    o.order_number,
    o.status AS order_status,
    o.total_amount,
    o.placed_at
FROM orders o
JOIN farmers f ON o.farmer_id = f.id
JOIN cooperatives c ON o.coop_id = c.id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id
ORDER BY o.placed_at DESC;

SELECT * FROM farmer_sales_history;


-- VIEW: Cooperative Purchase History


CREATE OR REPLACE VIEW coop_purchase_history AS
SELECT
    c.id AS coop_id,
    c.coop_name,
    f.full_name AS farmer_name,
    p.name AS product_name,
    oi.quantity,
    oi.unit_price,
    oi.subtotal,
    o.order_number,
    o.status AS order_status,
    o.total_amount,
    o.placed_at
FROM orders o
JOIN cooperatives c ON o.coop_id = c.id
JOIN farmers f ON o.farmer_id = f.id
JOIN order_items oi ON o.id = oi.order_id
JOIN products p ON oi.product_id = p.id
ORDER BY o.placed_at DESC;

SELECT * FROM coop_purchase_history;


