--- Insert Functions

-- Fonction pour ajouter un type de transport
CREATE OR REPLACE FUNCTION add_transport_type(
    code VARCHAR(3),
    name VARCHAR(32),
    capacity INT,
    avg_interval INT
) RETURNS BOOLEAN AS $$
BEGIN
    -- Vérification des valeurs de capacité et d'intervalle moyen
    IF capacity <= 0 OR avg_interval <= 0 THEN
        RETURN FALSE;
    END IF;

    -- Tentative d'insertion d'un nouveau type de transport
    BEGIN
        INSERT INTO TransportType (code, name, capacity, avg_interval)
        VALUES (code, name, capacity, avg_interval);  -- Utilisation correcte des arguments
        RETURN TRUE;
    EXCEPTION
        WHEN unique_violation THEN  -- Gestion d'erreur si code ou name existent déjà
            RETURN FALSE;
    END;
END;
$$ LANGUAGE plpgsql;


-- Fonction pour ajouter une zone
CREATE OR REPLACE FUNCTION add_zone(
    name VARCHAR(32),
    price FLOAT
) RETURNS BOOLEAN AS $$
BEGIN
    -- Vérification du prix : il doit être strictement positif et supérieur à 0.001
    IF price <= 0.001 THEN
        RETURN FALSE;
    END IF;

    -- Tentative d'insertion d'une nouvelle zone
    BEGIN
        INSERT INTO Zone (name, price)
        VALUES (name, price);
        RETURN TRUE;
    EXCEPTION
        WHEN unique_violation THEN  -- Gestion d'erreur si le nom existe déjà
            RETURN FALSE;
    END;
END;
$$ LANGUAGE plpgsql;


-- Fonction pour ajouter une station au réseau
CREATE OR REPLACE FUNCTION add_station(
    id INT,
    name VARCHAR(64),
    town VARCHAR(32),
    zone INT,
    type VARCHAR(3)
) RETURNS BOOLEAN AS $$
BEGIN
    -- Vérification de l'existence de la zone et du type de transport
    IF NOT EXISTS (SELECT 1 FROM Zone z WHERE z.id = zone) OR
       NOT EXISTS (SELECT 1 FROM TransportType t WHERE t.code = type) THEN
        RETURN FALSE;
    END IF;

    -- Tentative d'insertion de la station
    BEGIN
        INSERT INTO Station (id, name, town, zone_id, type_code)
        VALUES (id, name, town, zone, type);
        RETURN TRUE;
    EXCEPTION
        WHEN unique_violation THEN  -- Gestion d'erreur si l'id de la station existe déjà
            RETURN FALSE;
    END;
END;
$$ LANGUAGE plpgsql;

-- Fonction pour ajouter une ligne au réseau
CREATE OR REPLACE FUNCTION add_line(
    code VARCHAR(3),
    type VARCHAR(3)
) RETURNS BOOLEAN AS $$
BEGIN
    -- Vérification de l'existence du type de transport
    IF NOT EXISTS (SELECT 1 FROM TransportType tt WHERE tt.code = type) THEN
        RETURN FALSE;
    END IF;

    -- Tentative d'insertion de la ligne
    BEGIN
        INSERT INTO Line (code, type_code)
        VALUES (code, type);
        RETURN TRUE;
    EXCEPTION
        WHEN unique_violation THEN  -- Gestion d'erreur si le code de la ligne est déjà utilisé
            RETURN FALSE;
    END;
END;
$$ LANGUAGE plpgsql;

-- Fonction pour ajouter une station à une ligne avec des messages de débogage
CREATE OR REPLACE FUNCTION add_station_to_line(
    station INT,
    line VARCHAR(3),
    pos INT
) RETURNS BOOLEAN AS $$
DECLARE
    station_type VARCHAR(3);
    line_type VARCHAR(3);
BEGIN
    -- Récupération des types de la station et de la ligne
    SELECT s.type_code INTO station_type FROM Station s WHERE s.id = station;
    SELECT l.type_code INTO line_type FROM Line l WHERE l.code = line;

    -- Debug : Affichage des types de la station et de la ligne
    RAISE NOTICE 'Type de la station : %, Type de la ligne : %', station_type, line_type;

    -- Vérification que la station et la ligne existent et que les types correspondent
    IF station_type IS NULL OR line_type IS NULL THEN
        RAISE NOTICE 'Station ou ligne introuvable';
        RETURN FALSE;
    ELSIF station_type != line_type THEN
        RAISE NOTICE 'Types incompatibles entre la station et la ligne';
        RETURN FALSE;
    END IF;

    -- Tentative d'insertion de la station sur la ligne à la position spécifiée
    BEGIN
        INSERT INTO StationLine (station_id, line_code, position)
        VALUES (station, line, pos);
        RETURN TRUE;
    EXCEPTION
        WHEN unique_violation THEN  -- Gestion d'erreur si la station ou la position sont déjà utilisées sur la ligne
            RAISE NOTICE 'Violation d''unicité : la station est déjà sur la ligne ou la position est occupée';
            RETURN FALSE;
    END;
END;
$$ LANGUAGE plpgsql;


--- Views

-- Vue pour afficher les types de transport avec une capacité entre 50 et 300
CREATE OR REPLACE VIEW view_transport_50_300_users AS
SELECT name
FROM TransportType
WHERE capacity BETWEEN 50 AND 300
ORDER BY name ASC;

-- Vue pour afficher les noms des stations situées dans la commune de "Villejuif"
CREATE OR REPLACE VIEW view_stations_from_villejuif AS
SELECT name AS station
FROM Station
WHERE town ILIKE 'Villejuif'
ORDER BY name ASC;


-- Vue pour afficher les noms des stations avec le nom de leur zone correspondante
CREATE OR REPLACE VIEW view_stations_zones AS
SELECT s.name AS station, z.name AS zone
FROM Station s
JOIN Zone z ON s.zone_id = z.id
ORDER BY z.id ASC, s.name ASC;


-- Vue pour afficher le nombre de stations par type de transport
CREATE OR REPLACE VIEW view_nb_station_type AS
SELECT tt.name AS type, COUNT(s.id) AS stations
FROM TransportType tt
JOIN Station s ON s.type_code = tt.code
GROUP BY tt.name
ORDER BY stations DESC, type ASC;


-- Vue pour afficher la durée totale du trajet pour chaque ligne
CREATE OR REPLACE VIEW view_line_duration AS
SELECT tt.name AS type,
       l.code AS line,
       CASE
           WHEN (COUNT(sl.station_id) - 1) * tt.avg_interval > 0 THEN (COUNT(sl.station_id) - 1) * tt.avg_interval
           ELSE 0
       END AS minutes
FROM Line l
JOIN TransportType tt ON l.type_code = tt.code
JOIN StationLine sl ON l.code = sl.line_code
GROUP BY tt.name, l.code, tt.avg_interval
ORDER BY tt.name ASC, l.code;


-- Vue pour afficher la capacité des stations commençant par "A"
CREATE OR REPLACE VIEW view_a_station_capacity AS
SELECT s.name AS station, tt.capacity
FROM Station s
JOIN TransportType tt ON s.type_code = tt.code
WHERE s.name ILIKE 'A%'  -- Recherche insensible à la casse pour les noms commençant par "A"
ORDER BY s.name ASC, tt.capacity ASC;


--- Procedures

-- Fonction pour lister les noms des stations sur une ligne donnée
CREATE OR REPLACE FUNCTION list_station_in_line(p_line_code VARCHAR(3))
RETURNS SETOF VARCHAR(64) AS $$
BEGIN
    RETURN QUERY
    SELECT s.name
    FROM StationLine sl
    JOIN Station s ON sl.station_id = s.id
    WHERE sl.line_code = p_line_code  -- Utilisation de "p_line_code" pour éviter l'ambiguïté
    ORDER BY sl.position ASC;
END;
$$ LANGUAGE plpgsql;

-- Fonction pour lister les types de transport dans une zone donnée
CREATE OR REPLACE FUNCTION list_types_in_zone(zone INT)
RETURNS SETOF VARCHAR(32) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT tt.name
    FROM Station s
    JOIN TransportType tt ON s.type_code = tt.code
    WHERE s.zone_id = zone  -- Filtrer par la zone spécifiée
    ORDER BY tt.name ASC;
END;
$$ LANGUAGE plpgsql;

-- Fonction pour calculer le coût d'un trajet entre deux stations
CREATE OR REPLACE FUNCTION get_cost_travel(station_start INT, station_end INT)
RETURNS FLOAT AS $$
DECLARE
    start_zone INT;
    end_zone INT;
    total_cost FLOAT := 0;
    zone_price FLOAT;
BEGIN
    -- Récupérer les zones des stations de départ et d'arrivée
    SELECT zone_id INTO start_zone FROM Station WHERE id = station_start;
    SELECT zone_id INTO end_zone FROM Station WHERE id = station_end;

    -- Vérifier si les deux stations existent
    IF start_zone IS NULL OR end_zone IS NULL THEN
        RETURN 0;
    END IF;

    -- Calculer les bornes des zones à inclure dans le coût
    FOR z IN LEAST(start_zone, end_zone)..GREATEST(start_zone, end_zone) LOOP
        SELECT price INTO zone_price FROM Zone WHERE id = z;
        total_cost := total_cost + zone_price;
    END LOOP;

    RETURN total_cost;
END;
$$ LANGUAGE plpgsql;


