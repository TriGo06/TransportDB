--- Insertion Functions

DROP FUNCTION IF EXISTS add_journey(VARCHAR, TIMESTAMP, TIMESTAMP, INT, INT);
CREATE OR REPLACE FUNCTION add_journey(
    p_email VARCHAR(128),
    p_start_time TIMESTAMP,
    p_end_time TIMESTAMP,
    start_station INT,
    end_station INT
) RETURNS BOOLEAN AS $$
DECLARE
    traveler_id_var INT;
BEGIN
    -- Récupérer l'ID du voyageur à partir de son email
    SELECT id INTO traveler_id_var FROM Traveler WHERE email = p_email;

    -- Vérifier que le voyageur existe
    IF traveler_id_var IS NULL THEN
        RAISE NOTICE 'Voyageur avec l''email % non trouvé.', p_email;
        RETURN FALSE;
    END IF;

    -- Vérifier que la durée du voyage ne dépasse pas 24 heures
    IF p_end_time - p_start_time > INTERVAL '24 hours' THEN
        RAISE NOTICE 'Le voyage ne peut pas durer plus de 24 heures.';
        RETURN FALSE;
    END IF;

    -- Vérifier les chevauchements de temps
    IF EXISTS (
        SELECT 1 FROM Journey
        WHERE traveler_id = traveler_id_var
        AND (
            (start_time <= p_end_time AND end_time >= p_start_time)
        )
    ) THEN
        RAISE NOTICE 'Chevauchement de temps avec un autre voyage existant pour l''utilisateur.';
        RETURN FALSE;
    END IF;

    -- Insérer le nouveau voyage
    INSERT INTO Journey (traveler_id, start_time, end_time, start_station, end_station)
    VALUES (traveler_id_var, p_start_time, p_end_time, start_station, end_station);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


DROP FUNCTION IF EXISTS add_bill(VARCHAR, INT, INT);

CREATE OR REPLACE FUNCTION add_bill(
    p_email VARCHAR(128),
    p_year INT,
    p_month INT
) RETURNS BOOLEAN AS $$
DECLARE
    v_traveler_id INT;
    v_total_amount NUMERIC(10, 2) := 0;
    v_discount INT := 0;
    v_journey_cost NUMERIC(10, 2) := 0;
    v_subscription_cost NUMERIC(10, 2) := 0;
BEGIN
    -- Obtenir l'ID du voyageur à partir de son email
    SELECT id INTO v_traveler_id
    FROM Traveler
    WHERE email = p_email;

    -- Vérifier que le voyageur existe
    IF v_traveler_id IS NULL THEN
        RAISE NOTICE 'Voyageur avec l''email % non trouvé.', p_email;
        RETURN FALSE;
    END IF;

    -- Vérifier que le mois est terminé
    IF p_year > EXTRACT(YEAR FROM CURRENT_DATE) OR (p_year = EXTRACT(YEAR FROM CURRENT_DATE) AND p_month >= EXTRACT(MONTH FROM CURRENT_DATE)) THEN
        RAISE NOTICE 'Le mois spécifié doit être terminé pour générer une facture.';
        RETURN FALSE;
    END IF;

    -- Vérifier si une facture existe déjà pour ce mois, cette année et cet utilisateur
    IF EXISTS (
        SELECT 1 FROM Billing
        WHERE traveler_id = v_traveler_id AND year = p_year AND month = p_month
    ) THEN
        RAISE NOTICE 'Une facture existe déjà pour ce mois et cet utilisateur.';
        RETURN FALSE;
    END IF;

    -- Calculer le coût des voyages pour le mois spécifié
    SELECT COALESCE(SUM(journey_cost), 0) INTO v_journey_cost
    FROM (
        SELECT
            EXTRACT(YEAR FROM start_time) AS year,
            EXTRACT(MONTH FROM start_time) AS month,
            10 AS journey_cost  -- Remplacer par le coût réel si disponible
        FROM Journey
        WHERE traveler_id = v_traveler_id AND EXTRACT(YEAR FROM start_time) = p_year AND EXTRACT(MONTH FROM start_time) = p_month
    ) AS journey_costs;

    -- Ajouter le coût des voyages au montant total
    v_total_amount := v_total_amount + v_journey_cost;
    RAISE NOTICE 'Coût des voyages pour le mois et l''année spécifiés : %', v_journey_cost;

    -- Calculer le coût des abonnements en cours pour le mois
    SELECT COALESCE(SUM(price), 0) INTO v_subscription_cost
    FROM Subscription
    JOIN Offer ON Subscription.offer_code = Offer.code
    WHERE Subscription.traveler_id = v_traveler_id AND Subscription.status = 'Registered'
      AND (Subscription.date_subscribed <= MAKE_DATE(p_year, p_month, 1)
           OR Subscription.date_subscribed + INTERVAL '1 month' * Offer.duration_months >= MAKE_DATE(p_year, p_month, 1));

    -- Ajouter le coût des abonnements au montant total
    v_total_amount := v_total_amount + v_subscription_cost;
    RAISE NOTICE 'Coût des abonnements pour le mois et l''année spécifiés : %', v_subscription_cost;

    -- Vérifier si l'utilisateur a une remise (s'il est employé)
    SELECT COALESCE(s.discount, 0) INTO v_discount
    FROM Employee e
    JOIN Contract c ON e.traveler_id = v_traveler_id AND c.employee_id = e.traveler_id
    JOIN Service s ON c.service_name = s.name
    WHERE c.date_start <= MAKE_DATE(p_year, p_month, 1)
      AND (c.date_end IS NULL OR c.date_end >= MAKE_DATE(p_year, p_month, 1));

    -- Appliquer la remise si elle existe
    IF v_discount > 0 THEN
        v_total_amount := v_total_amount * (1 - v_discount / 100.0);
    END IF;
    RAISE NOTICE 'Montant total après remise : %, remise appliquée : %', v_total_amount, v_discount;

    -- Arrondir le montant total à 2 décimales
    v_total_amount := ROUND(v_total_amount, 2);

    -- Ne pas insérer de facture si le montant total est nul
    IF v_total_amount = 0 THEN
        RAISE NOTICE 'Montant total nul, facture non ajoutée.';
        RETURN TRUE;
    END IF;

    -- Insérer la facture dans la table Billing
    INSERT INTO Billing (traveler_id, month, year, amount, is_paid, discount_applied)
    VALUES (v_traveler_id, p_month, p_year, v_total_amount, FALSE, v_discount);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


-- Fonction pour marquer une facture comme payée pour un utilisateur donné, un mois et une année spécifiés
CREATE OR REPLACE FUNCTION pay_bill(
    p_email VARCHAR(128),
    p_year INT,
    p_month INT
) RETURNS BOOLEAN AS $$
DECLARE
    v_traveler_id INT;
    v_bill_id INT;
    v_total_amount NUMERIC(10, 2);
BEGIN
    -- Obtenir l'ID du voyageur à partir de son email
    SELECT id INTO v_traveler_id
    FROM Traveler
    WHERE email = p_email;

    -- Vérifier que le voyageur existe
    IF v_traveler_id IS NULL THEN
        RAISE NOTICE 'Voyageur avec l''email % non trouvé.', p_email;
        RETURN FALSE;
    END IF;

    -- Vérifier si la facture existe pour le mois et l'année spécifiés
    SELECT id, amount INTO v_bill_id, v_total_amount
    FROM Billing
    WHERE traveler_id = v_traveler_id AND year = p_year AND month = p_month;

    -- Si la facture n'existe pas, créer une nouvelle facture
    IF v_bill_id IS NULL THEN
        IF NOT add_bill(p_email, p_year, p_month) THEN
            RAISE NOTICE 'Impossible de créer une facture pour l''utilisateur % pour le mois % et l''année %.', p_email, p_month, p_year;
            RETURN FALSE;
        END IF;

        -- Récupérer les informations de la facture nouvellement créée
        SELECT id, amount INTO v_bill_id, v_total_amount
        FROM Billing
        WHERE traveler_id = v_traveler_id AND year = p_year AND month = p_month;
    END IF;

    -- Si le montant de la facture est nul, retourner FALSE
    IF v_total_amount = 0 THEN
        RAISE NOTICE 'Le montant de la facture est nul pour l''utilisateur %, mois %, année %.', p_email, p_month, p_year;
        RETURN FALSE;
    END IF;

    -- Vérifier si la facture a déjà été payée
    IF EXISTS (
        SELECT 1 FROM Billing
        WHERE id = v_bill_id AND is_paid = TRUE
    ) THEN
        RAISE NOTICE 'La facture pour l''utilisateur % pour le mois % et l''année % est déjà payée.', p_email, p_month, p_year;
        RETURN TRUE;
    END IF;

    -- Marquer la facture comme payée
    UPDATE Billing
    SET is_paid = TRUE
    WHERE id = v_bill_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Fonction pour générer des factures pour tous les utilisateurs d'un mois et d'une année donnés
CREATE OR REPLACE FUNCTION generate_bill(year INT, month INT)
RETURNS BOOLEAN AS $$
DECLARE
    current_date DATE := CURRENT_DATE;
    billing_date DATE := make_date(year, month, 1);
    user_email VARCHAR(128);
BEGIN
    -- Vérifier que le mois et l'année sont passés
    IF billing_date >= date_trunc('month', current_date) THEN
        RAISE NOTICE 'Le mois et l''année spécifiés ne sont pas encore terminés. Facturation impossible.';
        RETURN FALSE;
    END IF;

    -- Boucle sur tous les utilisateurs pour générer leurs factures
    FOR user_email IN SELECT email FROM Traveler LOOP
        -- Appeler la fonction add_bill pour chaque utilisateur
        PERFORM add_bill(user_email, year, month);
    END LOOP;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


--- Views

-- Vue pour afficher toutes les factures avec le numéro de facture, le montant et l'utilisateur associé
CREATE OR REPLACE VIEW view_all_bills AS
SELECT
    t.lastname,
    t.firstname,
    b.id AS bill_number,
    b.amount AS bill_amount
FROM
    Billing b
JOIN
    Traveler t ON b.traveler_id = t.id
ORDER BY
    b.id;


-- Vue pour afficher le nombre de factures et le montant total par mois et année
CREATE OR REPLACE VIEW view_bill_per_month AS
SELECT
    b.year,
    b.month,
    COUNT(b.id) AS bills,
    SUM(b.amount) AS total
FROM
    Billing b
GROUP BY
    b.year,
    b.month
ORDER BY
    b.year,
    b.month;


-- Vue pour afficher les entrées moyennes quotidiennes pour chaque station avec leur type de transport
CREATE OR REPLACE VIEW view_average_entries_station AS
SELECT
    s.type_code AS type,
    s.name AS station,
    TRUNC(
        CAST(COUNT(j.id) AS NUMERIC) /
        NULLIF(days_active.jours_actifs, 0),
        2
    ) AS entries -- Affiche la moyenne des entrées
FROM
    Station s
LEFT JOIN
    Journey j ON s.id = j.end_station -- Utilisation d'un LEFT JOIN pour inclure toutes les stations
LEFT JOIN (
    SELECT
        j.end_station,
        COUNT(DISTINCT DATE(j.start_time)) AS jours_actifs
    FROM
        Journey j
    GROUP BY
        j.end_station
) AS days_active ON s.id = days_active.end_station
GROUP BY
    s.type_code,
    s.name,
    days_active.jours_actifs
ORDER BY
    s.type_code,
    s.name;



-- Vue pour afficher les factures impayés
CREATE OR REPLACE VIEW view_current_non_paid_bills AS
SELECT
    t.lastname,
    t.firstname,
    b.id AS bill_number,
    b.amount AS bill_amount
FROM
    Billing b
JOIN
    Traveler t ON b.traveler_id = t.id
WHERE
    b.is_paid = FALSE
ORDER BY
    t.lastname,
    t.firstname,
    b.id;
