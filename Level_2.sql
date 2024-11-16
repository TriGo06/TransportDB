--- Insertion Functions

-- Fonction pour ajouter un nouvel utilisateur au réseau
CREATE OR REPLACE FUNCTION add_person(
    firstname VARCHAR(32),
    lastname VARCHAR(32),
    p_email VARCHAR(128),  -- Renommage du paramètre pour éviter l'ambiguïté
    phone VARCHAR(10),
    address TEXT,
    town VARCHAR(32),
    zipcode VARCHAR(5)
) RETURNS BOOLEAN AS $$
BEGIN
    -- Vérification de la duplication de l'email
    IF EXISTS (SELECT 1 FROM Traveler WHERE email = p_email) THEN
        RETURN FALSE;
    END IF;

    -- Insertion de l'utilisateur
    INSERT INTO Traveler (firstname, lastname, email, phone, address, town, zipcode)
    VALUES (firstname, lastname, p_email, phone, address, town, zipcode);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Fonction pour ajouter une nouvelle offre
CREATE OR REPLACE FUNCTION add_offer(
    code VARCHAR(5),
    name VARCHAR(32),
    price FLOAT,
    nb_month INT,
    zone_from INT,
    zone_to INT
) RETURNS BOOLEAN AS $$
BEGIN
    -- Vérification que nb_month est positif et non nul
    IF nb_month <= 0 THEN
        RETURN FALSE;
    END IF;

    -- Vérification de l'existence des zones
    IF NOT EXISTS (SELECT 1 FROM Zone WHERE id = zone_from) OR
       NOT EXISTS (SELECT 1 FROM Zone WHERE id = zone_to) THEN
        RETURN FALSE;
    END IF;

    -- Insertion de l'offre
    INSERT INTO Offer (code, name, price, duration_months, zone_from, zone_to)
    VALUES (code, name, price, nb_month, zone_from, zone_to);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS add_subscription(INT, VARCHAR, VARCHAR, DATE);

-- Fonction pour ajouter un nouvel abonnement pour un utilisateur sans utiliser "num"
CREATE OR REPLACE FUNCTION add_subscription(
    p_email VARCHAR(128),
    p_code VARCHAR(5),
    date_sub DATE
) RETURNS BOOLEAN AS $$
DECLARE
    user_id INT;
BEGIN
    -- Vérifier que l'utilisateur existe
    SELECT id INTO user_id FROM Traveler WHERE email = p_email;
    IF user_id IS NULL THEN
        RETURN FALSE;
    END IF;

    -- Vérifier que l'offre existe
    IF NOT EXISTS (SELECT 1 FROM Offer WHERE code = p_code) THEN
        RETURN FALSE;
    END IF;

    -- Vérifier l'absence d'abonnements en "Pending" ou "Incomplete" pour l'utilisateur
    IF EXISTS (
        SELECT 1 FROM Subscription
        WHERE traveler_id = user_id AND status IN ('Pending', 'Incomplete')
    ) THEN
        RETURN FALSE;
    END IF;

    -- Insérer l'abonnement avec le statut par défaut "Incomplete"
    INSERT INTO Subscription (traveler_id, offer_code, date_subscribed, status, bank_account_provided, proof_of_address_provided)
    VALUES (user_id, p_code, date_sub, 'Incomplete', FALSE, FALSE);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


--- Update Functions

-- Fonction pour mettre à jour le statut d'un abonnement
CREATE OR REPLACE FUNCTION update_status(
    num INT,
    new_status VARCHAR(32)
) RETURNS BOOLEAN AS $$
BEGIN
    -- Vérifier que le statut est valide
    IF new_status NOT IN ('Registered', 'Pending', 'Incomplete') THEN
        RETURN FALSE;
    END IF;

    -- Vérifier que l'abonnement existe
    IF NOT EXISTS (SELECT 1 FROM Subscription WHERE id = num) THEN
        RETURN FALSE;
    END IF;

    -- Mettre à jour le statut de l'abonnement
    UPDATE Subscription
    SET status = new_status
    WHERE id = num;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS update_offer_price(VARCHAR, FLOAT);

-- Fonction pour mettre à jour le prix d'une offre
CREATE OR REPLACE FUNCTION update_offer_price(
    offer_code VARCHAR(5),
    new_price FLOAT  -- Renommage du paramètre pour éviter l'ambiguïté
) RETURNS BOOLEAN AS $$
BEGIN
    -- Vérifier que le prix est positif et non nul
    IF new_price <= 0 THEN
        RETURN FALSE;
    END IF;

    -- Vérifier que l'offre existe
    IF NOT EXISTS (SELECT 1 FROM Offer WHERE code = offer_code) THEN
        RETURN FALSE;
    END IF;

    -- Mettre à jour le prix de l'offre
    UPDATE Offer
    SET price = new_price
    WHERE code = offer_code;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


--- Views

-- Vue pour afficher les noms complets des personnes avec un nom de famille de 4 caractères ou moins
CREATE OR REPLACE VIEW view_user_small_name AS
SELECT lastname, firstname
FROM Traveler
WHERE LENGTH(lastname) <= 4
ORDER BY lastname ASC, firstname ASC;

-- Vue pour afficher les utilisateurs et leurs offres
CREATE OR REPLACE VIEW view_user_subscription AS
SELECT
    CONCAT(Traveler.lastname, ' ', Traveler.firstname) AS user,
    Offer.name AS offer
FROM
    Subscription
JOIN
    Traveler ON Subscription.traveler_id = Traveler.id
JOIN
    Offer ON Subscription.offer_code = Offer.code
GROUP BY
    Traveler.lastname, Traveler.firstname, Offer.name
ORDER BY
    user ASC, offer ASC;



-- Vue pour afficher les offres sans abonnés
CREATE OR REPLACE VIEW view_unloved_offers AS
SELECT Offer.name AS offer
FROM Offer
LEFT JOIN Subscription ON Offer.code = Subscription.offer_code
WHERE Subscription.offer_code IS NULL
ORDER BY Offer.name ASC;


-- Vue pour afficher les utilisateurs avec des abonnements en statut "Pending"
CREATE OR REPLACE VIEW view_pending_subscriptions AS
SELECT
    Traveler.lastname,
    Traveler.firstname,
    Subscription.date_subscribed
FROM
    Subscription
JOIN
    Traveler ON Subscription.traveler_id = Traveler.id
WHERE
    Subscription.status = 'Pending'
ORDER BY
    Subscription.date_subscribed ASC;


-- Vue pour afficher les abonnements en "Incomplete" ou "Pending" depuis au moins un an
CREATE OR REPLACE VIEW view_old_subscription AS
SELECT
    Traveler.lastname,
    Traveler.firstname,
    Offer.name AS subscription,
    Subscription.status
FROM
    Subscription
JOIN
    Traveler ON Subscription.traveler_id = Traveler.id
JOIN
    Offer ON Subscription.offer_code = Offer.code
WHERE
    Subscription.status IN ('Incomplete', 'Pending')
    AND Subscription.date_subscribed <= (CURRENT_DATE - INTERVAL '1 year')
ORDER BY
    Traveler.lastname ASC,
    Traveler.firstname ASC,
    Offer.name ASC;


--- Procedures

-- Fonction pour lister les stations proches de l'utilisateur (dans la même ville)
CREATE OR REPLACE FUNCTION list_station_near_user(user_email VARCHAR(128))
RETURNS SETOF VARCHAR(64) AS $$
DECLARE
    user_town VARCHAR(32);
BEGIN
    -- Obtenir la ville de l'utilisateur
    SELECT town INTO user_town
    FROM Traveler
    WHERE email = user_email;

    -- Vérifier si la ville est trouvée pour éviter les erreurs
    IF user_town IS NULL THEN
        RAISE NOTICE 'Utilisateur avec l''email % non trouvé.', user_email;
        RETURN;
    END IF;

    -- Retourner la liste des stations dans la même ville, en minuscules, sans doublon, et triée par nom
    RETURN QUERY
    SELECT DISTINCT LOWER(Station.name)::VARCHAR(64)
    FROM Station
    WHERE Station.town = user_town
    ORDER BY 1;  -- Utilisation de ORDER BY 1 pour faire référence à la première colonne
END;
$$ LANGUAGE plpgsql;

-- Fonction pour lister les abonnés à une offre spécifique
CREATE OR REPLACE FUNCTION list_subscribers(code_offer VARCHAR(5))
RETURNS SETOF VARCHAR(65) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT CONCAT(Traveler.lastname, ' ', Traveler.firstname)::VARCHAR(65)
    FROM Subscription
    JOIN Traveler ON Subscription.traveler_id = Traveler.id
    WHERE Subscription.offer_code = code_offer
    ORDER BY 1; -- Tri basé sur la première colonne sélectionnée (nom complet)
END;
$$ LANGUAGE plpgsql;

DROP FUNCTION IF EXISTS list_subscription(VARCHAR, DATE);
-- Fonction pour lister les codes des offres d'abonnements en "Registered" pour un utilisateur donné à une date donnée
CREATE OR REPLACE FUNCTION list_subscription(p_email VARCHAR(128), p_date DATE)
RETURNS SETOF VARCHAR(5) AS $$
DECLARE
    user_id INT;
BEGIN
    -- Obtenir l'ID de l'utilisateur à partir de son email
    SELECT id INTO user_id
    FROM Traveler
    WHERE email = p_email;

    -- Vérifier si l'utilisateur existe
    IF user_id IS NULL THEN
        RAISE NOTICE 'Utilisateur avec l''email % non trouvé.', p_email;
        RETURN;
    END IF;

    -- Retourner les codes des abonnements en "Registered" actifs à la date donnée
    RETURN QUERY
    SELECT DISTINCT Subscription.offer_code::VARCHAR(5)
    FROM Subscription
    WHERE Subscription.traveler_id = user_id
      AND Subscription.status = 'Registered'
      AND p_date BETWEEN Subscription.date_subscribed AND (Subscription.date_subscribed + INTERVAL '1 month' * (SELECT duration_months FROM Offer WHERE Offer.code = Subscription.offer_code))
    ORDER BY Subscription.offer_code;
END;
$$ LANGUAGE plpgsql;
