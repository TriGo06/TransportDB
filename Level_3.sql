--- Insertion Functions
DROP FUNCTION IF EXISTS add_service(VARCHAR, INT);
-- Fonction pour ajouter un service à l'entreprise
CREATE OR REPLACE FUNCTION add_service(p_name VARCHAR(32), discount INT)
RETURNS BOOLEAN AS $$
BEGIN
    -- Vérifier que le rabais est compris entre 0 et 100 (inclus)
    IF discount < 0 OR discount > 100 THEN
        RETURN FALSE;
    END IF;

    -- Vérifier que le nom du service est unique
    IF EXISTS (SELECT 1 FROM Service WHERE name = p_name) THEN
        RETURN FALSE;
    END IF;

    -- Ajouter le service
    INSERT INTO Service (name, discount)
    VALUES (p_name, discount);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Fonction pour ajouter un contrat d'emploi
DROP FUNCTION IF EXISTS add_contract(p_email VARCHAR(128), date_beginning DATE, service VARCHAR(32));
CREATE OR REPLACE FUNCTION add_contract(p_email VARCHAR(128), date_beginning DATE, service VARCHAR(32))
RETURNS BOOLEAN AS $$
DECLARE
    user_id INT;
    generated_login VARCHAR(64);
    firstname_letter CHAR(1);
    lastname_part VARCHAR(6);
    attempts INT := 0;
BEGIN
    -- Vérifier que l'utilisateur existe
    SELECT id, LEFT(lastname, 6), LEFT(firstname, 1)
    INTO user_id, lastname_part, firstname_letter
    FROM Traveler
    WHERE Traveler.email = p_email;

    IF user_id IS NULL THEN
        RAISE NOTICE 'Utilisateur avec l''email % non trouvé.', p_email;
        RETURN FALSE;
    END IF;

    -- Vérifier que tous les contrats précédents sont terminés
    IF EXISTS (
        SELECT 1 FROM Contract
        WHERE employee_id = user_id AND (date_end IS NULL OR date_end >= date_beginning)
    ) THEN
        RETURN FALSE;
    END IF;

    -- Générer le login
    LOOP
        generated_login := lastname_part || '_' || firstname_letter;
        IF NOT EXISTS (SELECT 1 FROM Employee WHERE login = generated_login) THEN
            EXIT; -- Login valide trouvé
        END IF;

        -- Passer à la prochaine lettre pour éviter les doublons
        firstname_letter := CHR(ASCII(firstname_letter) + 1);
        attempts := attempts + 1;

        IF attempts > 26 THEN
            RAISE NOTICE 'Impossible de générer un login unique pour %', p_email;
            RETURN FALSE;
        END IF;
    END LOOP;

    -- Ajouter ou vérifier l'entrée dans Employee
    IF NOT EXISTS (SELECT 1 FROM Employee WHERE traveler_id = user_id) THEN
        INSERT INTO Employee (traveler_id, login) VALUES (user_id, generated_login);
    END IF;

    -- Ajouter le contrat
    INSERT INTO Contract (employee_id, service_name, date_start)
    VALUES (user_id, service, date_beginning);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


-- Fonction pour mettre fin à un contrat d'emploi
DROP FUNCTION IF EXISTS end_contract(VARCHAR(128), DATE);
CREATE OR REPLACE FUNCTION end_contract(p_email VARCHAR(128), p_date_end DATE)
RETURNS BOOLEAN AS $$
DECLARE
    user_id INT;
BEGIN
    -- Obtenir l'ID de l'utilisateur à partir de son email
    SELECT id INTO user_id
    FROM Traveler
    WHERE Traveler.email = p_email;

    -- Vérifier que l'utilisateur existe
    IF user_id IS NULL THEN
        RAISE NOTICE 'Utilisateur avec l''email % non trouvé.', p_email;
        RETURN FALSE;
    END IF;

    -- Vérifier s'il y a un contrat en cours pour l'employé
    IF NOT EXISTS (SELECT 1 FROM Contract WHERE employee_id = user_id AND date_end IS NULL) THEN
        RAISE NOTICE 'Aucun contrat en cours pour l''utilisateur avec l''email %.', p_email;
        RETURN FALSE;
    END IF;

    -- Mettre à jour la date de fin du contrat en cours
    UPDATE Contract
    SET date_end = p_date_end
    WHERE employee_id = user_id AND date_end IS NULL;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


--- Update Functions

-- Fonction pour mettre à jour le rabais d'un service
CREATE OR REPLACE FUNCTION update_service(p_name VARCHAR(32), p_discount INT)
RETURNS BOOLEAN AS $$
BEGIN
    -- Vérifier que le rabais est compris entre 0 et 100 (inclus)
    IF p_discount < 0 OR p_discount > 100 THEN
        RETURN FALSE;
    END IF;

    -- Vérifier que le service existe
    IF NOT EXISTS (SELECT 1 FROM Service WHERE name = p_name) THEN
        RAISE NOTICE 'Service avec le nom % non trouvé.', p_name;
        RETURN FALSE;
    END IF;

    -- Mettre à jour le rabais pour le service
    UPDATE Service
    SET discount = p_discount
    WHERE name = p_name;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

-- Fonction pour mettre à jour l'email d'un employé en fonction de son login
CREATE OR REPLACE FUNCTION update_employee_mail(p_login VARCHAR(8), p_email VARCHAR(128))
RETURNS BOOLEAN AS $$
DECLARE
    current_email VARCHAR(128);
BEGIN
    -- Vérifier que le login existe et obtenir l'email actuel
    SELECT T.email INTO current_email
    FROM Employee E
    JOIN Traveler T ON E.traveler_id = T.id
    WHERE E.login = p_login;

    -- Si le login n'existe pas, retourner FALSE
    IF current_email IS NULL THEN
        RAISE NOTICE 'Login % non trouvé.', p_login;
        RETURN FALSE;
    END IF;

    -- Si le nouvel email est le même que l'email actuel, retourner TRUE
    IF current_email = p_email THEN
        RETURN TRUE;
    END IF;

    -- Vérifier que le nouvel email n'est pas déjà attribué à un autre utilisateur
    IF EXISTS (SELECT 1 FROM Traveler WHERE email = p_email) THEN
        RAISE NOTICE 'Email % déjà attribué à un autre utilisateur.', p_email;
        RETURN FALSE;
    END IF;

    -- Mettre à jour l'email de l'employé
    UPDATE Traveler
    SET email = p_email
    WHERE id = (SELECT traveler_id FROM Employee WHERE login = p_login);

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


--- Views

-- Vue pour afficher les employés actuels avec leurs noms complets, services et logins
CREATE OR REPLACE VIEW view_employees AS
SELECT
    T.lastname,
    T.firstname,
    E.login,
    C.service_name AS service
FROM
    Traveler T
JOIN
    Employee E ON T.id = E.traveler_id
JOIN
    Contract C ON E.traveler_id = C.employee_id
WHERE
    C.date_end IS NULL  -- Filtrer pour les contrats en cours
ORDER BY
    T.lastname, T.firstname, E.login;

-- Vue pour afficher le nombre d'employés par service
CREATE OR REPLACE VIEW view_nb_employees_per_service AS
SELECT
    s.name AS service,
    COUNT(e.traveler_id) AS nb
FROM
    Service s
LEFT JOIN
    Contract c ON s.name = c.service_name AND c.date_end IS NULL
LEFT JOIN
    Employee e ON c.employee_id = e.traveler_id
GROUP BY
    s.name
ORDER BY
    s.name;


--- Procedures

CREATE OR REPLACE FUNCTION list_login_employee(date_service DATE)
RETURNS SETOF VARCHAR(8) AS $$
BEGIN
    RETURN QUERY
    SELECT e.login
    FROM Employee e
    JOIN Contract c ON e.traveler_id = c.employee_id  -- Correction ici pour correspondre à la clé étrangère appropriée
    WHERE c.date_start <= date_service
      AND (c.date_end IS NULL OR c.date_end >= date_service)
    ORDER BY e.login;
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION list_not_employee(date_service DATE)
RETURNS TABLE (
    lastname VARCHAR(32),
    firstname VARCHAR(32),
    has_worked TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        Traveler.lastname,
        Traveler.firstname,
        CASE
            WHEN EXISTS (
                SELECT 1
                FROM Contract
                JOIN Employee ON Contract.employee_id = Employee.traveler_id  -- Remplacement de Employee.id par Employee.traveler_id
                WHERE Employee.traveler_id = Traveler.id
            )
            THEN 'YES'
            ELSE 'NO'
        END AS has_worked
    FROM
        Traveler
    LEFT JOIN
        Employee ON Traveler.id = Employee.traveler_id
    LEFT JOIN
        Contract ON Employee.traveler_id = Contract.employee_id
                AND Contract.date_start <= date_service
                AND (Contract.date_end IS NULL OR Contract.date_end > date_service)
    WHERE
        Contract.id IS NULL  -- Contract manquant à cette date
    ORDER BY
        has_worked DESC, Traveler.lastname, Traveler.firstname;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION list_subscription_history(p_email VARCHAR(128))
RETURNS TABLE(type TEXT, name VARCHAR, start_date DATE, duration INTERVAL) AS $$
BEGIN
    -- Affiche un message si l'email est trouvé dans Traveler
    RAISE NOTICE 'Recherche d''email : %', p_email;

    RETURN QUERY
    (
        -- Historique des abonnements
        SELECT
            'sub' AS type,
            o.name AS name,
            s.date_subscribed AS start_date,
            (s.date_subscribed + INTERVAL '1 month' * o.duration_months) - s.date_subscribed AS duration
        FROM
            Subscription s
        JOIN
            Offer o ON s.offer_code = o.code
        JOIN
            Traveler t ON s.traveler_id = t.id
        WHERE
            t.email = p_email

        UNION ALL

        -- Historique des contrats
        SELECT
            'ctr' AS type,
            c.service_name AS name,
            c.date_start AS start_date,
            CASE
                WHEN c.date_end IS NOT NULL
                THEN (c.date_end - c.date_start) * INTERVAL '1 day'
                ELSE NULL
            END AS duration
        FROM
            Contract c
        JOIN
            Employee e ON c.employee_id = e.traveler_id
        JOIN
            Traveler t ON e.traveler_id = t.id
        WHERE
            t.email = p_email
    )
    ORDER BY start_date;
END;
$$ LANGUAGE plpgsql;
