-- Active rentals are runtime-only. This removes the obsolete table from builds
-- that previously persisted active rental state.
DROP TABLE IF EXISTS `snipe_carrental_rentals`;

CREATE TABLE IF NOT EXISTS `snipe_carrental_stations` (
    `id` VARCHAR(48) NOT NULL,
    `label` VARCHAR(80) NOT NULL,
    `variant` VARCHAR(16) NOT NULL DEFAULT 'tablet',
    `coords` JSON NOT NULL,
    `platform` JSON NOT NULL,
    `color` VARCHAR(9) NOT NULL DEFAULT '#00d7c8',
    `sort_order` INT UNSIGNED NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `snipe_carrental_vehicles` (
    `station_id` VARCHAR(48) NOT NULL,
    `id` VARCHAR(48) NOT NULL,
    `model` VARCHAR(64) NOT NULL,
    `label` VARCHAR(64) NOT NULL,
    `base_price` INT UNSIGNED NOT NULL DEFAULT 0,
    `enabled` TINYINT(1) NOT NULL DEFAULT 1,
    `sort_order` INT UNSIGNED NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`station_id`, `id`),
    KEY `idx_snipe_carrental_vehicle_model` (`model`),
    CONSTRAINT `fk_snipe_carrental_vehicle_station`
        FOREIGN KEY (`station_id`) REFERENCES `snipe_carrental_stations` (`id`)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Vehicle disabling is no longer part of the simplified catalog. Repair rows
-- written as disabled by older TINYINT/boolean loading behavior.
UPDATE `snipe_carrental_vehicles` SET `enabled` = 1 WHERE `enabled` <> 1;

ALTER TABLE `snipe_carrental_stations`
    MODIFY `variant` VARCHAR(16) NOT NULL DEFAULT 'tablet';
UPDATE `snipe_carrental_stations` SET `variant` = 'tablet' WHERE `variant` <> 'tablet';
