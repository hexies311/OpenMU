-- Run after OpenMU has initialized its Season 6 configuration database.
-- Safe to re-run; existing matching variants and stock are reused.
BEGIN;

CREATE TEMP TABLE energy_armor_map ON COMMIT DROP AS
SELECT source."Id" AS source_definition_id,
       COALESCE(
           existing."Id",
           md5('openmu-energy-armor-v1:item:' || source."Id"::text || ':' || target.variant_number::text)::uuid) AS variant_definition_id,
       source."Group" AS item_group,
       source."Number" AS source_number,
       target.variant_number,
           CASE
               WHEN source."Number" = 50 THEN replace(source."Name", 'Faith', 'Divine')
               WHEN source."Group" = 8 AND source."Number" = 24 THEN replace(source."Name", 'Red Sprit', 'Red Spirit')
               ELSE source."Name"
           END || ' (Energy)' AS variant_name,
           source."GameConfigurationId" AS game_configuration_id
FROM config."ItemDefinition" source
JOIN (VALUES
    (10::smallint, 344::smallint),
    (11::smallint, 345::smallint),
    (12::smallint, 346::smallint),
    (14::smallint, 347::smallint),
    (13::smallint, 355::smallint),
    (50::smallint, 356::smallint),
    (24::smallint, 357::smallint),
    (31::smallint, 358::smallint),
    (36::smallint, 359::smallint),
    (49::smallint, 360::smallint)) target(source_number, variant_number)
  ON source."Number" = target.source_number
LEFT JOIN config."ItemDefinition" existing
  ON existing."GameConfigurationId" IS NOT DISTINCT FROM source."GameConfigurationId"
 AND existing."Group" = source."Group"
 AND existing."Number" = target.variant_number
WHERE source."Group" BETWEEN 7 AND 11;

DO $$
BEGIN
    IF (SELECT count(*) FROM energy_armor_map) <> 50 THEN
        RAISE EXCEPTION 'Expected 50 original armor definitions; found %', (SELECT count(*) FROM energy_armor_map);
    END IF;

    IF (SELECT count(*) FROM config."AttributeDefinition" WHERE "Designation" = 'Total Agility Requirement Value') <> 1
       OR (SELECT count(*) FROM config."AttributeDefinition" WHERE "Designation" = 'Total Energy Requirement Value') <> 1 THEN
        RAISE EXCEPTION 'Could not uniquely identify the Agility and Energy requirement attributes.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM energy_armor_map map
        JOIN config."ItemDefinition" source ON source."Id" = map.source_definition_id
        JOIN config."ItemDefinition" variant ON variant."Id" = map.variant_definition_id
        WHERE variant."Group" <> source."Group"
           OR variant."Number" <> map.variant_number
    ) THEN
        RAISE EXCEPTION 'A target Energy armor ID is occupied by a different item.';
    END IF;
END $$;

CREATE TEMP TABLE divine_glove_energy_requirement ON COMMIT DROP AS
SELECT target.source_definition_id AS item_definition_id,
       energy_attribute."Id" AS attribute_id,
       peer_requirement."GameMapDefinitionId" AS game_map_definition_id,
       peer_requirement."SkillId" AS skill_id,
       peer_requirement."SkillId1" AS skill_id1,
       min(peer_requirement."MinimumValue")::integer AS minimum_value
FROM energy_armor_map target
JOIN config."AttributeDefinition" energy_attribute
  ON energy_attribute."Designation" = 'Total Energy Requirement Value'
JOIN energy_armor_map peer
  ON peer.source_number = target.source_number
 AND peer.item_group IN (7, 8, 9, 11)
 AND peer.game_configuration_id IS NOT DISTINCT FROM target.game_configuration_id
JOIN config."AttributeRequirement" peer_requirement
  ON peer_requirement."ItemDefinitionId" = peer.source_definition_id
 AND peer_requirement."AttributeId" = energy_attribute."Id"
WHERE target.source_number = 50
  AND target.item_group = 10
  AND NOT EXISTS (
      SELECT 1
      FROM config."AttributeRequirement" existing_requirement
      WHERE existing_requirement."ItemDefinitionId" = target.source_definition_id
        AND existing_requirement."AttributeId" = energy_attribute."Id")
GROUP BY target.source_definition_id, energy_attribute."Id",
         peer_requirement."GameMapDefinitionId", peer_requirement."SkillId", peer_requirement."SkillId1"
HAVING count(DISTINCT peer.item_group) = 4
   AND min(peer_requirement."MinimumValue") = max(peer_requirement."MinimumValue");

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM energy_armor_map target
        JOIN config."AttributeDefinition" energy_attribute
          ON energy_attribute."Designation" = 'Total Energy Requirement Value'
        WHERE target.source_number = 50
          AND target.item_group = 10
          AND NOT EXISTS (
              SELECT 1
              FROM config."AttributeRequirement" existing_requirement
              WHERE existing_requirement."ItemDefinitionId" = target.source_definition_id
                AND existing_requirement."AttributeId" = energy_attribute."Id")
          AND NOT EXISTS (
              SELECT 1
              FROM divine_glove_energy_requirement recovered_requirement
              WHERE recovered_requirement.item_definition_id = target.source_definition_id)
    ) THEN
        RAISE EXCEPTION 'Could not recover the Divine glove Energy requirement from its matching set pieces.';
    END IF;
END $$;

INSERT INTO config."AttributeRequirement" (
    "Id", "AttributeId", "GameMapDefinitionId", "ItemDefinitionId", "SkillId", "SkillId1", "MinimumValue")
SELECT md5('openmu-energy-armor-v1:source-requirement:divine-glove-energy:' ||
           requirement.item_definition_id::text || ':' ||
           COALESCE(requirement.game_map_definition_id::text, 'NULL') || ':' ||
           COALESCE(requirement.skill_id::text, 'NULL') || ':' ||
           COALESCE(requirement.skill_id1::text, 'NULL'))::uuid,
       requirement.attribute_id, requirement.game_map_definition_id, requirement.item_definition_id,
       requirement.skill_id, requirement.skill_id1, requirement.minimum_value
FROM divine_glove_energy_requirement requirement;

CREATE TEMP TABLE energy_armor_requirement_map ON COMMIT DROP AS
SELECT map.variant_definition_id,
       requirement."AttributeId" AS attribute_id,
       requirement."GameMapDefinitionId" AS game_map_definition_id,
       requirement."SkillId" AS skill_id,
       requirement."SkillId1" AS skill_id1,
       requirement."MinimumValue" AS minimum_value,
       requirement."Id" AS source_requirement_id
FROM energy_armor_map map
JOIN config."AttributeRequirement" requirement ON requirement."ItemDefinitionId" = map.source_definition_id
JOIN config."AttributeDefinition" attribute ON attribute."Id" = requirement."AttributeId"
WHERE attribute."Designation" NOT IN ('Total Agility Requirement Value', 'Total Energy Requirement Value')
UNION ALL
SELECT map.variant_definition_id,
       (SELECT "Id" FROM config."AttributeDefinition" WHERE "Designation" = 'Total Energy Requirement Value'),
       requirement."GameMapDefinitionId",
       requirement."SkillId",
       requirement."SkillId1",
       sum(requirement."MinimumValue")::integer,
       NULL::uuid
FROM energy_armor_map map
JOIN config."AttributeRequirement" requirement ON requirement."ItemDefinitionId" = map.source_definition_id
JOIN config."AttributeDefinition" attribute ON attribute."Id" = requirement."AttributeId"
WHERE attribute."Designation" IN ('Total Agility Requirement Value', 'Total Energy Requirement Value')
GROUP BY map.variant_definition_id, requirement."GameMapDefinitionId", requirement."SkillId", requirement."SkillId1";

INSERT INTO config."ItemDefinition" (
    "Id", "ItemSlotId", "ConsumeEffectId", "SkillId", "GameConfigurationId",
    "Number", "Width", "Height", "DropsFromMonsters", "IsAmmunition",
    "IsBoundToCharacter", "Name", "DropLevel", "MaximumItemLevel", "Durability",
    "Group", "Value", "MaximumSockets", "PetExperienceFormula",
    "StorageLimitPerCharacter", "MaximumDropLevel", "IsQuestItem", "IsDroppable",
    "IsPersonalStoreSellable", "IsRepairable", "IsSellableToNpc", "IsStorable", "IsTradable")
SELECT map.variant_definition_id, source."ItemSlotId", source."ConsumeEffectId", source."SkillId",
       source."GameConfigurationId", map.variant_number, source."Width", source."Height",
       source."DropsFromMonsters", source."IsAmmunition", source."IsBoundToCharacter",
       map.variant_name, source."DropLevel", source."MaximumItemLevel",
       source."Durability", source."Group", source."Value", source."MaximumSockets",
       source."PetExperienceFormula", source."StorageLimitPerCharacter",
       source."MaximumDropLevel", source."IsQuestItem", source."IsDroppable",
       source."IsPersonalStoreSellable", source."IsRepairable", source."IsSellableToNpc",
       source."IsStorable", source."IsTradable"
FROM energy_armor_map map
JOIN config."ItemDefinition" source ON source."Id" = map.source_definition_id
ON CONFLICT DO NOTHING;

-- Keep existing variants upgradeable when repairing definitions from an older seed.
UPDATE config."ItemDefinition" variant
SET "ItemSlotId" = source."ItemSlotId",
    "MaximumItemLevel" = source."MaximumItemLevel",
    "MaximumSockets" = source."MaximumSockets",
    "Name" = map.variant_name
FROM energy_armor_map map
JOIN config."ItemDefinition" source ON source."Id" = map.source_definition_id
WHERE variant."Id" = map.variant_definition_id
  AND (variant."ItemSlotId" IS DISTINCT FROM source."ItemSlotId"
       OR variant."MaximumItemLevel" IS DISTINCT FROM source."MaximumItemLevel"
       OR variant."MaximumSockets" IS DISTINCT FROM source."MaximumSockets"
       OR variant."Name" IS DISTINCT FROM map.variant_name);

DELETE FROM config."AttributeRequirement" variant_requirement
USING energy_armor_map map
WHERE variant_requirement."ItemDefinitionId" = map.variant_definition_id;

INSERT INTO config."AttributeRequirement" (
    "Id", "AttributeId", "GameMapDefinitionId", "ItemDefinitionId", "SkillId", "SkillId1", "MinimumValue")
SELECT md5('openmu-energy-armor-v1:requirement:' || requirement.variant_definition_id::text || ':' ||
           COALESCE(requirement.source_requirement_id::text,
               requirement.attribute_id::text || ':' || COALESCE(requirement.game_map_definition_id::text, 'NULL') || ':' ||
               COALESCE(requirement.skill_id::text, 'NULL') || ':' || COALESCE(requirement.skill_id1::text, 'NULL')))::uuid,
       requirement.attribute_id, requirement.game_map_definition_id, requirement.variant_definition_id,
       requirement.skill_id, requirement.skill_id1, requirement.minimum_value
FROM energy_armor_requirement_map requirement;

DELETE FROM config."ItemDefinitionCharacterClass" variant_class
USING energy_armor_map map
WHERE variant_class."ItemDefinitionId" = map.variant_definition_id;

INSERT INTO config."ItemDefinitionCharacterClass" ("ItemDefinitionId", "CharacterClassId")
SELECT map.variant_definition_id, link."CharacterClassId"
FROM energy_armor_map map
JOIN config."ItemDefinitionCharacterClass" link ON link."ItemDefinitionId" = map.source_definition_id
ON CONFLICT DO NOTHING;

DELETE FROM config."ItemDefinitionItemOptionDefinition" variant_option
USING energy_armor_map map
WHERE variant_option."ItemDefinitionId" = map.variant_definition_id;

INSERT INTO config."ItemDefinitionItemOptionDefinition" ("ItemDefinitionId", "ItemOptionDefinitionId")
SELECT map.variant_definition_id, link."ItemOptionDefinitionId"
FROM energy_armor_map map
JOIN config."ItemDefinitionItemOptionDefinition" link ON link."ItemDefinitionId" = map.source_definition_id
ON CONFLICT DO NOTHING;

INSERT INTO config."ItemDefinitionItemSetGroup" ("ItemDefinitionId", "ItemSetGroupId")
SELECT map.variant_definition_id, link."ItemSetGroupId"
FROM energy_armor_map map
JOIN config."ItemDefinitionItemSetGroup" link ON link."ItemDefinitionId" = map.source_definition_id
ON CONFLICT DO NOTHING;

CREATE TEMP TABLE energy_armor_set_map ON COMMIT DROP AS
SELECT source_set."Id" AS source_set_item_id,
       COALESCE(
           existing_set."Id",
           md5('openmu-energy-armor-v1:set-item:' || source_set."Id"::text || ':' || map.variant_definition_id::text)::uuid) AS variant_set_item_id,
       map.variant_definition_id,
       source_set."ItemSetGroupId",
       source_set."BonusOptionId",
       source_set."AncientSetDiscriminator"
FROM config."ItemOfItemSet" source_set
JOIN energy_armor_map map ON map.source_definition_id = source_set."ItemDefinitionId"
LEFT JOIN LATERAL (
    SELECT target_set."Id"
    FROM config."ItemOfItemSet" target_set
    WHERE target_set."ItemDefinitionId" = map.variant_definition_id
      AND target_set."ItemSetGroupId" = source_set."ItemSetGroupId"
      AND target_set."BonusOptionId" IS NOT DISTINCT FROM source_set."BonusOptionId"
      AND target_set."AncientSetDiscriminator" = source_set."AncientSetDiscriminator"
    ORDER BY target_set."Id"
    LIMIT 1) existing_set ON TRUE;

INSERT INTO config."ItemOfItemSet" (
    "Id", "ItemSetGroupId", "ItemDefinitionId", "BonusOptionId", "AncientSetDiscriminator")
SELECT map.variant_set_item_id, map."ItemSetGroupId", map.variant_definition_id,
       map."BonusOptionId", map."AncientSetDiscriminator"
FROM energy_armor_set_map map
WHERE NOT EXISTS (
    SELECT 1
    FROM config."ItemOfItemSet" existing
    WHERE existing."ItemDefinitionId" = map.variant_definition_id
      AND existing."ItemSetGroupId" = map."ItemSetGroupId"
      AND existing."BonusOptionId" IS NOT DISTINCT FROM map."BonusOptionId"
      AND existing."AncientSetDiscriminator" = map."AncientSetDiscriminator")
ON CONFLICT DO NOTHING;

INSERT INTO config."DropItemGroupItemDefinition" ("DropItemGroupId", "ItemDefinitionId")
SELECT link."DropItemGroupId", map.variant_definition_id
FROM energy_armor_map map
JOIN config."DropItemGroupItemDefinition" link ON link."ItemDefinitionId" = map.source_definition_id
ON CONFLICT DO NOTHING;

CREATE TEMP TABLE energy_armor_drop_map ON COMMIT DROP AS
SELECT source_drop."Id" AS source_drop_id,
       COALESCE(
           existing_drop."Id",
           md5('openmu-energy-armor-v1:item-drop-group:' || source_drop."Id"::text || ':' || map.variant_definition_id::text)::uuid) AS variant_drop_id,
       map.variant_definition_id
FROM config."ItemDropItemGroup" source_drop
JOIN energy_armor_map map ON map.source_definition_id = source_drop."ItemDefinitionId"
LEFT JOIN LATERAL (
    SELECT target_drop."Id"
    FROM config."ItemDropItemGroup" target_drop
    WHERE target_drop."ItemDefinitionId" = map.variant_definition_id
      AND target_drop."MonsterId" IS NOT DISTINCT FROM source_drop."MonsterId"
      AND target_drop."Description" IS NOT DISTINCT FROM source_drop."Description"
      AND target_drop."Chance" IS NOT DISTINCT FROM source_drop."Chance"
      AND target_drop."MinimumMonsterLevel" IS NOT DISTINCT FROM source_drop."MinimumMonsterLevel"
      AND target_drop."MaximumMonsterLevel" IS NOT DISTINCT FROM source_drop."MaximumMonsterLevel"
      AND target_drop."ItemLevel" IS NOT DISTINCT FROM source_drop."ItemLevel"
      AND target_drop."ItemType" IS NOT DISTINCT FROM source_drop."ItemType"
      AND target_drop."SourceItemLevel" IS NOT DISTINCT FROM source_drop."SourceItemLevel"
      AND target_drop."MoneyAmount" IS NOT DISTINCT FROM source_drop."MoneyAmount"
      AND target_drop."MinimumLevel" IS NOT DISTINCT FROM source_drop."MinimumLevel"
      AND target_drop."MaximumLevel" IS NOT DISTINCT FROM source_drop."MaximumLevel"
      AND target_drop."RequiredCharacterLevel" IS NOT DISTINCT FROM source_drop."RequiredCharacterLevel"
      AND target_drop."DropEffect" IS NOT DISTINCT FROM source_drop."DropEffect"
    ORDER BY target_drop."Id"
    LIMIT 1) existing_drop ON TRUE;

INSERT INTO config."ItemDropItemGroup" (
    "Id", "MonsterId", "ItemDefinitionId", "Description", "Chance",
    "MinimumMonsterLevel", "MaximumMonsterLevel", "ItemLevel", "ItemType",
    "SourceItemLevel", "MoneyAmount", "MinimumLevel", "MaximumLevel",
    "RequiredCharacterLevel", "DropEffect")
SELECT map.variant_drop_id, source_drop."MonsterId", map.variant_definition_id,
       source_drop."Description", source_drop."Chance", source_drop."MinimumMonsterLevel",
       source_drop."MaximumMonsterLevel", source_drop."ItemLevel", source_drop."ItemType",
       source_drop."SourceItemLevel", source_drop."MoneyAmount", source_drop."MinimumLevel",
       source_drop."MaximumLevel", source_drop."RequiredCharacterLevel", source_drop."DropEffect"
FROM energy_armor_drop_map map
JOIN config."ItemDropItemGroup" source_drop ON source_drop."Id" = map.source_drop_id
ON CONFLICT DO NOTHING;

INSERT INTO config."ItemDropItemGroupItemDefinition" ("ItemDropItemGroupId", "ItemDefinitionId")
SELECT drop_map.variant_drop_id, link."ItemDefinitionId"
FROM energy_armor_drop_map drop_map
JOIN config."ItemDropItemGroupItemDefinition" link ON link."ItemDropItemGroupId" = drop_map.source_drop_id
ON CONFLICT DO NOTHING;

INSERT INTO config."ItemDropItemGroupItemDefinition" ("ItemDropItemGroupId", "ItemDefinitionId")
SELECT link."ItemDropItemGroupId", map.variant_definition_id
FROM energy_armor_map map
JOIN config."ItemDropItemGroupItemDefinition" link ON link."ItemDefinitionId" = map.source_definition_id
ON CONFLICT DO NOTHING;

-- Restore Elf Lala's default stock by removing any previously seeded Energy copies.
DELETE FROM data."Item" variant_item
USING config."MonsterDefinition" npc, energy_armor_map map
WHERE npc."Number" = 242
  AND npc."MerchantStoreId" = variant_item."ItemStorageId"
  AND map.variant_number BETWEEN 344 AND 347
  AND variant_item."DefinitionId" = map.variant_definition_id;

CREATE TEMP TABLE energy_armor_shop_sources ON COMMIT DROP AS
SELECT source_item."Id" AS source_item_id,
       COALESCE(
           existing_item."Id",
           md5('openmu-energy-armor-v1:merchant-item:' || source_item."Id"::text || ':' || map.variant_definition_id::text)::uuid) AS variant_item_id,
       map.variant_definition_id,
       source_item."ItemStorageId" AS item_storage_id,
       existing_item."Id" AS existing_variant_item_id,
       existing_item."ItemSlot" AS existing_variant_slot,
       map.item_group,
       map.variant_number
FROM data."Item" source_item
JOIN config."MonsterDefinition" npc ON npc."MerchantStoreId" = source_item."ItemStorageId"
JOIN energy_armor_map map
  ON map.source_definition_id = source_item."DefinitionId"
 AND map.variant_number BETWEEN 344 AND 347
LEFT JOIN LATERAL (
    SELECT target_item."Id", target_item."ItemSlot"
    FROM data."Item" target_item
    WHERE target_item."ItemStorageId" = source_item."ItemStorageId"
      AND target_item."DefinitionId" = map.variant_definition_id
    ORDER BY target_item."ItemSlot"
    LIMIT 1) existing_item ON TRUE
WHERE npc."Number" <> 242;

CREATE TEMP TABLE energy_armor_shop_missing ON COMMIT DROP AS
SELECT source.*,
       row_number() OVER (PARTITION BY source.item_storage_id ORDER BY source.item_group, source.variant_number) AS slot_rank
FROM energy_armor_shop_sources source
WHERE source.existing_variant_item_id IS NULL;

CREATE TEMP TABLE energy_armor_shop_free_slots ON COMMIT DROP AS
SELECT stores.item_storage_id, candidate.item_slot,
       row_number() OVER (PARTITION BY stores.item_storage_id ORDER BY candidate.item_slot) AS slot_rank
FROM (SELECT DISTINCT item_storage_id FROM energy_armor_shop_missing) stores
CROSS JOIN LATERAL generate_series(0, 119) AS candidate(item_slot)
WHERE NOT EXISTS (
    SELECT 1
    FROM data."Item" occupied
    WHERE occupied."ItemStorageId" = stores.item_storage_id
      AND occupied."ItemSlot" = candidate.item_slot);

CREATE TEMP TABLE energy_armor_shop_map ON COMMIT DROP AS
SELECT source.source_item_id, source.variant_item_id, source.variant_definition_id,
       source.item_storage_id,
       COALESCE(source.existing_variant_slot, free.item_slot)::smallint AS variant_slot
FROM energy_armor_shop_sources source
LEFT JOIN energy_armor_shop_missing missing ON missing.source_item_id = source.source_item_id
LEFT JOIN energy_armor_shop_free_slots free
  ON free.item_storage_id = source.item_storage_id
 AND free.slot_rank = missing.slot_rank;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM energy_armor_shop_map WHERE variant_slot IS NULL) THEN
        RAISE EXCEPTION 'An NPC merchant inventory has no free slot for its Energy armor copy.';
    END IF;
END $$;

INSERT INTO data."Item" (
    "Id", "ItemStorageId", "DefinitionId", "ItemSlot", "Durability", "Level",
    "HasSkill", "SocketCount", "StorePrice", "PetExperience")
SELECT map.variant_item_id, map.item_storage_id, map.variant_definition_id, map.variant_slot,
       source_item."Durability", source_item."Level", source_item."HasSkill",
       source_item."SocketCount", source_item."StorePrice", source_item."PetExperience"
FROM energy_armor_shop_map map
JOIN data."Item" source_item ON source_item."Id" = map.source_item_id
WHERE NOT EXISTS (SELECT 1 FROM data."Item" existing WHERE existing."Id" = map.variant_item_id)
ON CONFLICT DO NOTHING;

INSERT INTO data."ItemOptionLink" ("Id", "ItemOptionId", "ItemId", "Level", "Index")
SELECT md5('openmu-energy-armor-v1:merchant-option:' || source_option."Id"::text || ':' || map.variant_item_id::text)::uuid,
       source_option."ItemOptionId", map.variant_item_id, source_option."Level", source_option."Index"
FROM energy_armor_shop_map map
JOIN data."ItemOptionLink" source_option ON source_option."ItemId" = map.source_item_id
WHERE NOT EXISTS (
    SELECT 1
    FROM data."ItemOptionLink" existing
    WHERE existing."ItemId" = map.variant_item_id
      AND existing."ItemOptionId" = source_option."ItemOptionId"
      AND existing."Level" = source_option."Level"
      AND existing."Index" = source_option."Index")
ON CONFLICT DO NOTHING;

INSERT INTO data."ItemItemOfItemSet" ("ItemId", "ItemOfItemSetId")
SELECT shop.variant_item_id, set_map.variant_set_item_id
FROM energy_armor_shop_map shop
JOIN data."ItemItemOfItemSet" source_link ON source_link."ItemId" = shop.source_item_id
JOIN energy_armor_set_map set_map ON set_map.source_set_item_id = source_link."ItemOfItemSetId"
ON CONFLICT DO NOTHING;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM energy_armor_map map
        JOIN config."ItemDefinition" source ON source."Id" = map.source_definition_id
        JOIN config."ItemDefinition" variant ON variant."Id" = map.variant_definition_id
        WHERE variant."MaximumItemLevel" IS DISTINCT FROM source."MaximumItemLevel"
           OR variant."MaximumSockets" IS DISTINCT FROM source."MaximumSockets"
    ) THEN
        RAISE EXCEPTION 'An Energy armor definition does not preserve its source upgrade limits.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM energy_armor_map map
        JOIN config."AttributeRequirement" requirement ON requirement."ItemDefinitionId" = map.variant_definition_id
        JOIN config."AttributeDefinition" attribute ON attribute."Id" = requirement."AttributeId"
        WHERE attribute."Designation" = 'Total Agility Requirement Value'
    ) THEN
        RAISE EXCEPTION 'An Energy armor variant still has an Agility requirement.';
    END IF;

    IF EXISTS (
        (SELECT variant_definition_id, attribute_id, game_map_definition_id, skill_id, skill_id1, minimum_value
         FROM energy_armor_requirement_map
         EXCEPT
         SELECT map.variant_definition_id, requirement."AttributeId", requirement."GameMapDefinitionId",
                requirement."SkillId", requirement."SkillId1", sum(requirement."MinimumValue")::integer
         FROM energy_armor_map map
         JOIN config."AttributeRequirement" requirement ON requirement."ItemDefinitionId" = map.variant_definition_id
         GROUP BY map.variant_definition_id, requirement."AttributeId", requirement."GameMapDefinitionId",
                  requirement."SkillId", requirement."SkillId1")
        UNION ALL
        (SELECT map.variant_definition_id, requirement."AttributeId", requirement."GameMapDefinitionId",
                requirement."SkillId", requirement."SkillId1", sum(requirement."MinimumValue")::integer
         FROM energy_armor_map map
         JOIN config."AttributeRequirement" requirement ON requirement."ItemDefinitionId" = map.variant_definition_id
         GROUP BY map.variant_definition_id, requirement."AttributeId", requirement."GameMapDefinitionId",
                  requirement."SkillId", requirement."SkillId1"
         EXCEPT
         SELECT variant_definition_id, attribute_id, game_map_definition_id, skill_id, skill_id1, minimum_value
         FROM energy_armor_requirement_map)
    ) THEN
        RAISE EXCEPTION 'An Energy armor variant does not match its source requirements with Agility added to Energy.';
    END IF;

    IF EXISTS (
        (SELECT map.variant_definition_id, link."ItemOptionDefinitionId"
         FROM energy_armor_map map
         JOIN config."ItemDefinitionItemOptionDefinition" link ON link."ItemDefinitionId" = map.source_definition_id
         EXCEPT
         SELECT map.variant_definition_id, link."ItemOptionDefinitionId"
         FROM energy_armor_map map
         JOIN config."ItemDefinitionItemOptionDefinition" link ON link."ItemDefinitionId" = map.variant_definition_id)
        UNION ALL
        (SELECT map.variant_definition_id, link."ItemOptionDefinitionId"
         FROM energy_armor_map map
         JOIN config."ItemDefinitionItemOptionDefinition" link ON link."ItemDefinitionId" = map.variant_definition_id
         EXCEPT
         SELECT map.variant_definition_id, link."ItemOptionDefinitionId"
         FROM energy_armor_map map
         JOIN config."ItemDefinitionItemOptionDefinition" link ON link."ItemDefinitionId" = map.source_definition_id)
    ) THEN
        RAISE EXCEPTION 'An Energy armor variant does not exactly mirror the item options used by jewel upgrade handlers.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM energy_armor_map map
        JOIN data."Item" item ON item."DefinitionId" = map.variant_definition_id
        JOIN config."MonsterDefinition" npc ON npc."MerchantStoreId" = item."ItemStorageId"
        WHERE map.variant_number BETWEEN 355 AND 360
    ) THEN
        RAISE EXCEPTION 'An Elf Energy armor variant was added to an NPC shop.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM energy_armor_map map
        JOIN data."Item" item ON item."DefinitionId" = map.variant_definition_id
        JOIN config."MonsterDefinition" npc ON npc."MerchantStoreId" = item."ItemStorageId"
        WHERE npc."Number" = 242
          AND map.variant_number BETWEEN 344 AND 347
    ) THEN
        RAISE EXCEPTION 'An Energy armor variant was added to Elf Lala''s shop.';
    END IF;

    IF (
        SELECT count(*)
        FROM energy_armor_map map
        JOIN data."Item" item ON item."DefinitionId" = map.source_definition_id
        JOIN config."MonsterDefinition" npc ON npc."MerchantStoreId" = item."ItemStorageId"
        WHERE npc."Number" = 242
          AND map.source_number BETWEEN 10 AND 12
    ) <> 15 THEN
        RAISE EXCEPTION 'Elf Lala''s original Vine, Silk, and Wind stock is incomplete.';
    END IF;
END $$;

COMMIT;
