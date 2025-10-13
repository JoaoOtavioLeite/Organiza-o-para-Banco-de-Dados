-- sample_queries.sql
-- Exemplos de uso do schema criado em schema.sql

-- 1) Inserir dois usuários
INSERT INTO users (email, password_hash, name) VALUES
('host@example.com', 'hash-host', 'Host Example'),
('guest@example.com', 'hash-guest', 'Guest Example');

-- 2) Criar um listing do host
WITH h AS (SELECT id FROM users WHERE email = 'host@example.com' LIMIT 1)
INSERT INTO listings (owner_id, title, description, price_per_night, city)
SELECT id, 'Apartamento central', 'Aconchegante, próximo ao metrô', 120.00, 'São Paulo' FROM h
RETURNING id;

-- 3) Exemplo de booking válido
-- Supondo que o listing id retornado seja conhecido; substitua pelo UUID real ou use subquery
-- Aqui usamos subqueries para buscar os ids
INSERT INTO bookings (listing_id, guest_id, start_date, end_date, nights, total_price, status)
VALUES (
  (SELECT l.id FROM listings l WHERE l.title ILIKE 'Apartamento central' LIMIT 1),
  (SELECT u.id FROM users u WHERE u.email = 'guest@example.com' LIMIT 1),
  '2025-10-10', '2025-10-15', 5, 120.00 * 5, 'confirmed'
);

-- 4) Tentativa de booking que sobrescreve (deve falhar por exclusion constraint)
-- Esta inserção deve levantar erro se as datas se sobrepõem
INSERT INTO bookings (listing_id, guest_id, start_date, end_date, nights, total_price, status)
VALUES (
  (SELECT l.id FROM listings l WHERE l.title ILIKE 'Apartamento central' LIMIT 1),
  (SELECT u.id FROM users u WHERE u.email = 'guest@example.com' LIMIT 1),
  '2025-10-14', '2025-10-18', 4, 120.00 * 4, 'pending'
);

-- 5) Inserir review (apenas após booking com status 'completed' e end_date <= now())
-- Primeiro atualize a reserva para completed e ajuste end_date no passado para teste
UPDATE bookings SET status = 'completed', end_date = now()::date - 1 WHERE status = 'confirmed' AND start_date = '2025-10-10';

INSERT INTO reviews (booking_id, listing_id, author_id, rating, comment)
VALUES (
  (SELECT b.id FROM bookings b WHERE b.status = 'completed' LIMIT 1),
  (SELECT b.listing_id FROM bookings b WHERE b.status = 'completed' LIMIT 1),
  (SELECT b.guest_id FROM bookings b WHERE b.status = 'completed' LIMIT 1),
  5, 'Ótima estadia, anfitrião atencioso.'
);

-- 6) Consultas úteis
-- Buscar listings por cidade e faixa de preço
SELECT id, title, price_per_night, city, avg_rating, ratings_count
FROM listings
WHERE city = 'São Paulo' AND price_per_night BETWEEN 50 AND 200
ORDER BY avg_rating DESC, price_per_night ASC
LIMIT 20;

-- Verificar disponibilidade (exemplo: existe booking no intervalo?)
-- True se houver conflito
SELECT EXISTS (
  SELECT 1 FROM bookings
  WHERE listing_id = (SELECT id FROM listings WHERE title ILIKE 'Apartamento central' LIMIT 1)
    AND daterange(start_date, end_date, '[]') && daterange('2025-10-14','2025-10-18','[]')
) AS has_conflict;

-- Ver avaliações de um listing
SELECT r.id, r.rating, r.comment, r.created_at, u.name AS author
FROM reviews r
JOIN users u ON u.id = r.author_id
WHERE r.listing_id = (SELECT id FROM listings WHERE title ILIKE 'Apartamento central' LIMIT 1)
ORDER BY r.created_at DESC;
