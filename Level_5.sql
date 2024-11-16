--- Triggers

CREATE OR REPLACE FUNCTION log_offer_price_update() RETURNS TRIGGER AS $$
BEGIN
    -- Enregistrer la modification du prix si elle a lieu
    IF NEW.price IS DISTINCT FROM OLD.price THEN
        INSERT INTO OfferPriceHistory (offer_code, modification_datetime, old_price, new_price)
        VALUES (OLD.code, CURRENT_TIMESTAMP, OLD.price, NEW.price);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER store_offer_updates
BEFORE UPDATE ON Offer
FOR EACH ROW
EXECUTE FUNCTION log_offer_price_update();

-- Fonction de trigger pour enregistrer les modifications de statut dans SubscriptionStatusHistory
CREATE OR REPLACE FUNCTION log_subscription_status_update() RETURNS TRIGGER AS $$
BEGIN
    -- Enregistrer la modification de statut si elle a lieu
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO SubscriptionStatusHistory (user_email, subscription_code, modification_datetime, old_status, new_status)
        VALUES (
            (SELECT email FROM Traveler WHERE id = OLD.traveler_id),  -- Récupérer l'email de l'utilisateur via l'ID
            OLD.offer_code,  -- Utilisation de OLD.offer_code au lieu de OLD.code
            CURRENT_TIMESTAMP,
            OLD.status,
            NEW.status
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER store_status_updates
BEFORE UPDATE ON Subscription
FOR EACH ROW
EXECUTE FUNCTION log_subscription_status_update();

--- Views

CREATE OR REPLACE VIEW view_offer_updates AS
SELECT
    offer_code,
    modification_datetime,
    old_price,
    new_price
FROM
    OfferPriceHistory
ORDER BY
    modification_datetime;

CREATE OR REPLACE VIEW view_status_updates AS
SELECT
    user_email AS email,
    subscription_code AS sub,
    modification_datetime AS modification,
    old_status,
    new_status
FROM
    SubscriptionStatusHistory
ORDER BY
    modification_datetime;
