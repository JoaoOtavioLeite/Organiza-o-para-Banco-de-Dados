-- schema.sql
-- Modelo inicial para um "Airbnb" simplificado (PostgreSQL)
-- Requisitos: PostgreSQL 12+ (btree_gist) para exclusion constraints

-- Extensões necessárias
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- Usuários
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(320) NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  name VARCHAR(255) NOT NULL,
  phone VARCHAR(50),
  is_verified BOOLEAN NOT NULL DEFAULT FALSE,
  profile_photo_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ
);

-- Anúncios (listings)
CREATE TABLE IF NOT EXISTS listings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title VARCHAR(255) NOT NULL,
  description TEXT,
  price_per_night NUMERIC(10,2) NOT NULL CHECK (price_per_night >= 0),
  currency CHAR(3) NOT NULL DEFAULT 'USD',
  guests_allowed INT NOT NULL DEFAULT 1,
  bedrooms INT NOT NULL DEFAULT 1,
  bathrooms NUMERIC(4,2) NOT NULL DEFAULT 1,
  address_line1 VARCHAR(255),
  address_line2 VARCHAR(255),
  city VARCHAR(100),
  state VARCHAR(100),
  country VARCHAR(100),
  postal_code VARCHAR(30),
  latitude NUMERIC(9,6),
  longitude NUMERIC(9,6),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  avg_rating NUMERIC(3,2) NOT NULL DEFAULT 0.00,
  ratings_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_listings_owner_id ON listings(owner_id);
CREATE INDEX IF NOT EXISTS idx_listings_city_price ON listings(city, price_per_night);

-- Fotos do anúncio
CREATE TABLE IF NOT EXISTS listing_photos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  position INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Amenidades
CREATE TABLE IF NOT EXISTS amenities (
  id SERIAL PRIMARY KEY,
  slug VARCHAR(100) NOT NULL UNIQUE,
  name VARCHAR(150) NOT NULL
);

CREATE TABLE IF NOT EXISTS listing_amenities (
  listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  amenity_id INT NOT NULL REFERENCES amenities(id) ON DELETE CASCADE,
  PRIMARY KEY (listing_id, amenity_id)
);

-- Reservas (bookings)
-- Usamos start_date/end_date + exclusion constraint para evitar overlap de reservas por listing
CREATE TABLE IF NOT EXISTS bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  guest_id UUID REFERENCES users(id) ON DELETE SET NULL,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  nights INT NOT NULL CHECK (nights >= 0),
  total_price NUMERIC(12,2) NOT NULL CHECK (total_price >= 0),
  currency CHAR(3) NOT NULL DEFAULT 'USD',
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','confirmed','cancelled','completed','declined')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ
);

-- Constraint básica de validade
ALTER TABLE bookings
  ADD CONSTRAINT bookings_dates_valid CHECK (end_date > start_date);

-- Exclusion constraint para prevenir double-booking por listing (usa btree_gist)
ALTER TABLE bookings
  ADD CONSTRAINT bookings_no_overlap EXCLUDE USING GIST (
    listing_id WITH =,
    daterange(start_date, end_date, '[]') WITH &&
  );

CREATE INDEX IF NOT EXISTS idx_bookings_listing ON bookings(listing_id);
CREATE INDEX IF NOT EXISTS idx_bookings_guest ON bookings(guest_id);

-- Pagamentos (opcional)
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID UNIQUE REFERENCES bookings(id) ON DELETE CASCADE,
  amount NUMERIC(12,2) NOT NULL,
  currency CHAR(3) NOT NULL DEFAULT 'USD',
  status VARCHAR(50) NOT NULL,
  provider VARCHAR(100),
  provider_payment_id VARCHAR(255),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Avaliações (reviews)
CREATE TABLE IF NOT EXISTS reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID REFERENCES bookings(id) ON DELETE SET NULL,
  listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  rating SMALLINT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- para permitir que tanto hóspede quanto anfitrião escrevam avaliações por booking,
  -- garantimos uma única avaliação por (booking_id, author_id)
  CONSTRAINT uq_booking_author UNIQUE (booking_id, author_id)
);

CREATE INDEX IF NOT EXISTS idx_reviews_listing ON reviews(listing_id);
CREATE INDEX IF NOT EXISTS idx_reviews_author ON reviews(author_id);

-- Trigger: evitar inserção de review se reserva não estiver concluída
CREATE OR REPLACE FUNCTION fn_check_review_allowed()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.booking_id IS NULL THEN
    -- Permitimos reviews sem booking_id? Preferimos forçar booking_id, mas aqui bloqueamos
    RAISE EXCEPTION 'reviews must be associated to a booking in this model';
  END IF;

  PERFORM 1 FROM bookings b WHERE b.id = NEW.booking_id AND b.status = 'completed' AND b.end_date <= now()::date;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'only completed bookings (with end_date passed) can be reviewed';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_review_allowed ON reviews;
CREATE TRIGGER trg_check_review_allowed
BEFORE INSERT OR UPDATE ON reviews
FOR EACH ROW EXECUTE FUNCTION fn_check_review_allowed();

-- Trigger: manter avg_rating e ratings_count na tabela listings
CREATE OR REPLACE FUNCTION fn_update_listing_rating()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  v_count INT;
  v_avg NUMERIC(3,2);
BEGIN
  IF (TG_OP = 'DELETE') THEN
    -- recalcular com todas as reviews remanescentes
    SELECT COUNT(*)::INT, COALESCE(ROUND(AVG(rating)::numeric,2), 0)
      INTO v_count, v_avg
    FROM reviews
    WHERE listing_id = OLD.listing_id;

    UPDATE listings SET ratings_count = v_count, avg_rating = v_avg WHERE id = OLD.listing_id;
    RETURN OLD;
  ELSIF (TG_OP = 'INSERT') THEN
    SELECT COUNT(*)::INT, COALESCE(ROUND(AVG(rating)::numeric,2), 0)
      INTO v_count, v_avg
    FROM reviews
    WHERE listing_id = NEW.listing_id;

    UPDATE listings SET ratings_count = v_count, avg_rating = v_avg WHERE id = NEW.listing_id;
    RETURN NEW;
  ELSIF (TG_OP = 'UPDATE') THEN
    -- quando rating muda, recalcular
    SELECT COUNT(*)::INT, COALESCE(ROUND(AVG(rating)::numeric,2), 0)
      INTO v_count, v_avg
    FROM reviews
    WHERE listing_id = NEW.listing_id;

    UPDATE listings SET ratings_count = v_count, avg_rating = v_avg WHERE id = NEW.listing_id;
    RETURN NEW;
  END IF;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_listing_rating ON reviews;
CREATE TRIGGER trg_update_listing_rating
AFTER INSERT OR UPDATE OR DELETE ON reviews
FOR EACH ROW EXECUTE FUNCTION fn_update_listing_rating();

-- Blocos de indisponibilidade do anfitrião (opcional)
CREATE TABLE IF NOT EXISTS listing_blocks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  listing_id UUID NOT NULL REFERENCES listings(id) ON DELETE CASCADE,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE listing_blocks
  ADD CONSTRAINT listing_blocks_dates_valid CHECK (end_date > start_date);

-- Você pode criar um EXCLUDE para bloquear sobreposições entre bookings e blocks
ALTER TABLE listing_blocks
  ADD CONSTRAINT blocks_no_overlap EXCLUDE USING GIST (
    listing_id WITH =,
    daterange(start_date, end_date, '[]') WITH &&
  );

-- Observações:
-- - Para buscas geográficas mais avançadas, instale PostGIS e troque latitude/longitude por geometry/geography.
-- - Para performance em produção, avalie partições e índices adicionais (por cidade, faixa de preço, host).
-- - Não armazenar dados sensíveis de pagamento; apenas IDs de provedores.

-- Fim do schema
