CREATE DATABASE Transport_db;

-- Table pour les types de transport
CREATE TABLE TransportType (
    code VARCHAR(3) PRIMARY KEY,  -- Identifiant du type de transport, unique et limité à 3 caractères
    name VARCHAR(32) NOT NULL UNIQUE,  -- Nom convivial du type de transport, limité à 32 caractères
    capacity INT NOT NULL CHECK (capacity > 0),  -- Capacité maximale, doit être positive
    avg_interval INT NOT NULL CHECK (avg_interval > 0)  -- Durée en minutes entre deux stations, doit être positive
);

-- Table pour les zones tarifaires
CREATE TABLE Zone (
    id SERIAL PRIMARY KEY,  -- Numéro séquentiel de la zone (numérotation de 1 à X)
    name VARCHAR(32) NOT NULL UNIQUE,  -- Nom de la zone, limité à 32 caractères et unique
    price FLOAT NOT NULL CHECK (price > 0)  -- Prix de la zone, doit être un nombre flottant positif
);

-- Table pour les lignes de transport
CREATE TABLE Line (
    code VARCHAR(3) PRIMARY KEY,  -- Code de la ligne, unique et limité à 3 caractères alphanumériques
    type_code VARCHAR(3) NOT NULL,  -- Type de transport associé (référence vers TransportType)
    FOREIGN KEY (type_code) REFERENCES TransportType(code)  -- Clé étrangère vers TransportType
);

-- Table pour les stations du réseau
CREATE TABLE Station (
    id SERIAL PRIMARY KEY,  -- Identifiant unique de la station (numérotation séquentielle)
    name VARCHAR(64) NOT NULL,  -- Nom de la station, limité à 64 caractères
    town VARCHAR(32) NOT NULL,  -- Commune où se trouve la station, limité à 32 caractères
    zone_id INT NOT NULL,  -- Zone dans laquelle se situe la station (référence vers Zone)
    type_code VARCHAR(3) NOT NULL,  -- Type de transport associé à la station
    FOREIGN KEY (zone_id) REFERENCES Zone(id),  -- Clé étrangère vers Zone
    FOREIGN KEY (type_code) REFERENCES TransportType(code)  -- Clé étrangère vers TransportType
);

-- Table pour lier les stations et les lignes avec une position spécifique
CREATE TABLE StationLine (
    station_id INT NOT NULL,  -- Identifiant de la station
    line_code VARCHAR(3) NOT NULL,  -- Code de la ligne
    position INT NOT NULL,  -- Position de la station sur la ligne (de 1 à terminus)
    PRIMARY KEY (station_id, line_code),  -- Clé primaire composite pour éviter les doublons
    FOREIGN KEY (station_id) REFERENCES Station(id),  -- Clé étrangère vers Station
    FOREIGN KEY (line_code) REFERENCES Line(code),  -- Clé étrangère vers Line
    CONSTRAINT unique_position UNIQUE (line_code, position)  -- Contrainte d'unicité pour la position sur la ligne
);

-- Table pour les utilisateurs du réseau de transport public
CREATE TABLE Traveler (
    id SERIAL PRIMARY KEY,  -- Identifiant unique pour chaque utilisateur (numérotation séquentielle)
    firstname VARCHAR(32) NOT NULL,  -- Prénom de l'utilisateur, limité à 32 caractères
    lastname VARCHAR(32) NOT NULL,  -- Nom de famille de l'utilisateur, limité à 32 caractères
    email VARCHAR(128) NOT NULL UNIQUE,  -- Email de l'utilisateur, limité à 128 caractères et unique
    phone VARCHAR(10) NOT NULL,  -- Numéro de téléphone, exactement 10 caractères
    address TEXT NOT NULL,  -- Adresse postale de l'utilisateur
    town VARCHAR(32) NOT NULL,  -- Commune où réside l'utilisateur, limité à 32 caractères
    zipcode VARCHAR(5) NOT NULL  -- Code postal, exactement 5 caractères
);

-- Table pour les employés, qui sont aussi des utilisateurs (référence à Traveler)
CREATE TABLE Employee (
    traveler_id INT PRIMARY KEY,  -- Identifiant de l'employé (référence à Traveler.id)
    login VARCHAR(8) NOT NULL UNIQUE,  -- Login unique pour identifier l'employé
    FOREIGN KEY (traveler_id) REFERENCES Traveler(id)  -- Clé étrangère vers Traveler
);

-- Table pour enregistrer les contrats de travail des employés
CREATE TABLE Contract (
    id SERIAL PRIMARY KEY,  -- Identifiant unique pour chaque contrat
    employee_id INT NOT NULL,  -- Référence vers Employee (l'employé concerné par le contrat)
    service_name VARCHAR(32) NOT NULL,  -- Nom du service dans lequel l'employé travaille ou a travaillé, limité à 32 caractères
    date_start DATE NOT NULL,  -- Date de début du contrat
    date_end DATE,  -- Date de fin du contrat (peut être NULL si l'employé travaille encore)
    FOREIGN KEY (employee_id) REFERENCES Employee(traveler_id),  -- Clé étrangère vers Employee
    CHECK (date_end IS NULL OR date_end > date_start)  -- Vérifie que la date de fin est postérieure à la date de début (si elle existe)
);

-- Table pour enregistrer les trajets des utilisateurs
CREATE TABLE Journey (
    id SERIAL PRIMARY KEY,  -- Identifiant unique pour chaque trajet
    traveler_id INT NOT NULL,  -- Identifiant de l'utilisateur qui effectue le trajet (référence vers Traveler)
    start_time TIMESTAMP NOT NULL,  -- Date et heure de la validation d'entrée
    end_time TIMESTAMP NOT NULL,  -- Date et heure de la validation de sortie
    start_station INT NOT NULL,  -- Station d'entrée (référence vers Station)
    end_station INT NOT NULL,  -- Station de sortie (référence vers Station)
    FOREIGN KEY (traveler_id) REFERENCES Traveler(id),  -- Clé étrangère vers Traveler
    FOREIGN KEY (start_station) REFERENCES Station(id),  -- Clé étrangère vers Station pour la station de départ
    FOREIGN KEY (end_station) REFERENCES Station(id),  -- Clé étrangère vers Station pour la station d'arrivée
    CHECK (end_time > start_time),  -- Contrainte de vérification : la date de sortie doit être postérieure à la date d'entrée
    CHECK (end_time - start_time <= INTERVAL '24 HOURS')  -- Vérification : un trajet ne peut pas durer plus de 24 heures
);

-- Table pour les offres d'abonnement
CREATE TABLE Offer (
    code VARCHAR(5) PRIMARY KEY,  -- Code unique pour identifier l'offre, limité à 5 caractères
    name VARCHAR(32) NOT NULL,  -- Nom convivial de l'offre, limité à 32 caractères
    price FLOAT NOT NULL CHECK (price > 0),  -- Prix mensuel de l'offre, doit être positif
    duration_months INT NOT NULL CHECK (duration_months > 0),  -- Durée de l'offre en mois, doit être au moins de 1 mois
    zone_from INT NOT NULL,  -- Zone la plus basse couverte par l'offre (référence vers Zone)
    zone_to INT NOT NULL,  -- Zone la plus élevée couverte par l'offre (référence vers Zone)
    FOREIGN KEY (zone_from) REFERENCES Zone(id),  -- Clé étrangère vers Zone pour le point de départ des zones couvertes
    FOREIGN KEY (zone_to) REFERENCES Zone(id),  -- Clé étrangère vers Zone pour le point de fin des zones couvertes
    CHECK (zone_to >= zone_from)  -- Contrainte de vérification : la zone de fin doit être égale ou supérieure à la zone de début
);

-- Table pour gérer les abonnements aux offres
CREATE TABLE Subscription (
    id SERIAL PRIMARY KEY,  -- Identifiant unique pour chaque abonnement
    traveler_id INT NOT NULL,  -- Identifiant de l'utilisateur (référence vers Traveler)
    offer_code VARCHAR(5) NOT NULL,  -- Code de l'offre à laquelle l'utilisateur est abonné (référence vers Offer)
    date_subscribed DATE NOT NULL,  -- Date de début de l'abonnement
    status VARCHAR(32) NOT NULL CHECK (status IN ('Registered', 'Pending', 'Incomplete')),  -- Statut de l'abonnement
    bank_account_provided BOOLEAN DEFAULT FALSE,  -- Document : preuve d'un compte bancaire
    proof_of_address_provided BOOLEAN DEFAULT FALSE,  -- Document : preuve de résidence
    FOREIGN KEY (traveler_id) REFERENCES Traveler(id),  -- Clé étrangère vers Traveler
    FOREIGN KEY (offer_code) REFERENCES Offer(code)  -- Clé étrangère vers Offer
);

-- Table pour gérer la facturation mensuelle des utilisateurs
CREATE TABLE Billing (
    id SERIAL PRIMARY KEY,  -- Identifiant unique pour chaque facture
    traveler_id INT NOT NULL,  -- Identifiant de l'utilisateur facturé (référence vers Traveler)
    month INT NOT NULL CHECK (month >= 1 AND month <= 12),  -- Mois de la facture (1 à 12)
    year INT NOT NULL,  -- Année de la facture
    amount FLOAT NOT NULL CHECK (amount >= 0),  -- Montant total de la facture, après réduction éventuelle
    is_paid BOOLEAN DEFAULT FALSE,  -- Statut de paiement (true si payé, false sinon)
    discount_applied INT DEFAULT 0 CHECK (discount_applied BETWEEN 0 AND 100),  -- Pourcentage de réduction appliqué pour les employés (0 à 100)
    FOREIGN KEY (traveler_id) REFERENCES Traveler(id),  -- Clé étrangère vers Traveler
    UNIQUE (traveler_id, month, year)  -- Contrainte d'unicité pour une seule facture par utilisateur, par mois et année
);

-- Création de la table Service
CREATE TABLE Service (
    id SERIAL PRIMARY KEY,        -- Identifiant unique pour chaque service
    name VARCHAR(32) UNIQUE NOT NULL,  -- Nom unique du service
    discount INT NOT NULL CHECK (discount >= 0 AND discount <= 100) -- Rabais en pourcentage (0-100)
);

CREATE TABLE OfferPriceHistory (
    offer_code VARCHAR(128),
    modification_datetime TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    old_price NUMERIC(10, 2),
    new_price NUMERIC(10, 2)
);


CREATE TABLE SubscriptionStatusHistory (
    user_email VARCHAR(128),
    subscription_code VARCHAR(128),
    modification_datetime TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    old_status VARCHAR(50),
    new_status VARCHAR(50)
);