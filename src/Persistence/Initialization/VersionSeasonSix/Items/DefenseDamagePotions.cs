// <copyright file="DefenseDamagePotions.cs" company="MUnique">
// Licensed under the MIT License. See LICENSE file in the project root for full license information.
// </copyright>

namespace MUnique.OpenMU.Persistence.Initialization.VersionSeasonSix.Items;

using MUnique.OpenMU.AttributeSystem;
using MUnique.OpenMU.DataModel.Attributes;
using MUnique.OpenMU.DataModel.Configuration;
using MUnique.OpenMU.DataModel.Configuration.ItemCrafting;
using MUnique.OpenMU.DataModel.Configuration.Items;
using MUnique.OpenMU.GameLogic;
using MUnique.OpenMU.GameLogic.Attributes;
using MUnique.OpenMU.Interfaces;
using MUnique.OpenMU.Persistence.Initialization.Properties;
using MUnique.OpenMU.Persistence.Initialization.Skills;

/// <summary>
/// Initializes the Defense Up and Damage Up potion items and Chaos Machine recipes.
/// </summary>
internal static class DefenseDamagePotions
{
    private static readonly PotionSpecification[] Specifications =
    [
        new(140, 38, 31, 42, LocalizedString.FromResource(() => ItemNames.SmallDefenseUpPotion), "Small Defense Up Potion", MagicEffectNumber.DefenseUpSmall, 17, Stats.GreaterDefenseBonus, 25, 20),
        new(141, 39, 31, 43, LocalizedString.FromResource(() => ItemNames.MediumDefenseUpPotion), "Medium Defense Up Potion", MagicEffectNumber.DefenseUpMedium, 17, Stats.GreaterDefenseBonus, 50, 40),
        new(142, 40, 31, 44, LocalizedString.FromResource(() => ItemNames.LargeDefenseUpPotion), "Large Defense Up Potion", MagicEffectNumber.DefenseUpLarge, 17, Stats.GreaterDefenseBonus, 75, 60),
        new(143, 38, 15, 45, LocalizedString.FromResource(() => ItemNames.SmallDamageUpPotion), "Small Damage Up Potion", MagicEffectNumber.DamageUpSmall, 18, Stats.GreaterDamageBonus, 25, 20),
        new(144, 39, 15, 47, LocalizedString.FromResource(() => ItemNames.MediumDamageUpPotion), "Medium Damage Up Potion", MagicEffectNumber.DamageUpMedium, 18, Stats.GreaterDamageBonus, 50, 40),
        new(145, 40, 15, 48, LocalizedString.FromResource(() => ItemNames.LargeDamageUpPotion), "Large Damage Up Potion", MagicEffectNumber.DamageUpLarge, 18, Stats.GreaterDamageBonus, 75, 60),
    ];

    /// <summary>
    /// Adds or updates the six potion definitions and their consume effects.
    /// </summary>
    /// <param name="context">The persistence context.</param>
    /// <param name="gameConfiguration">The game configuration.</param>
    public static void InitializeItems(IContext context, GameConfiguration gameConfiguration)
    {
        foreach (var specification in Specifications)
        {
            var item = gameConfiguration.Items.FirstOrDefault(candidate => candidate.Group == 14 && candidate.Number == specification.ItemNumber);
            if (item is null)
            {
                item = context.CreateNew<ItemDefinition>();
                gameConfiguration.Items.Add(item);
            }

            item.Name = specification.Name;
            item.Number = specification.ItemNumber;
            item.Group = 14;
            item.MaximumItemLevel = 1;
            item.Durability = 3;
            item.Value = specification.ItemValue;
            item.Width = 1;
            item.Height = 1;
            item.SetGuid(item.Group, item.Number);

            var effectNumber = (short)specification.EffectNumber;
            var effect = gameConfiguration.MagicEffects.FirstOrDefault(candidate => candidate.Number == effectNumber);
            if (effect is null)
            {
                effect = context.CreateNew<MagicEffectDefinition>();
                gameConfiguration.MagicEffects.Add(effect);
            }

            effect.SetGuid(item.Number, effectNumber);
            effect.Name = item.Name;
            effect.Number = effectNumber;
            effect.InformObservers = false;
            effect.StopByDeath = true;
            effect.SendDuration = true;
            effect.SubType = specification.SubType;
            effect.Duration ??= context.CreateNew<PowerUpDefinitionValue>();
            effect.Duration.ConstantValue.Value = 600;
            effect.PowerUpDefinitions.Clear();

            var powerUp = context.CreateNew<PowerUpDefinition>();
            powerUp.TargetAttribute = specification.BonusAttribute.GetPersistent(gameConfiguration);
            powerUp.Boost = context.CreateNew<PowerUpDefinitionValue>();
            powerUp.Boost.ConstantValue.Value = specification.BonusValue;
            powerUp.Boost.ConstantValue.AggregateType = AggregateType.AddRaw;
            effect.PowerUpDefinitions.Add(powerUp);
            item.ConsumeEffect = effect;
        }
    }

    /// <summary>
    /// Adds or updates the six Chaos Machine recipes.
    /// </summary>
    /// <param name="context">The persistence context.</param>
    /// <param name="gameConfiguration">The game configuration.</param>
    public static void InitializeCraftings(IContext context, GameConfiguration gameConfiguration)
    {
        var chaosMachine = gameConfiguration.Monsters.First(monster => monster.NpcWindow == NpcWindow.ChaosMachine);
        foreach (var specification in Specifications)
        {
            var crafting = chaosMachine.ItemCraftings.FirstOrDefault(candidate => candidate.Number == specification.CraftingNumber);
            if (crafting is null)
            {
                crafting = context.CreateNew<ItemCrafting>();
                chaosMachine.ItemCraftings.Add(crafting);
            }

            crafting.Name = specification.RecipeName;
            crafting.Number = specification.CraftingNumber;
            crafting.SimpleCraftingSettings ??= context.CreateNew<SimpleCraftingSettings>();
            var settings = crafting.SimpleCraftingSettings;
            settings.Money = 0;
            settings.SuccessPercent = 100;
            settings.RequiredItems.Clear();
            settings.ResultItems.Clear();

            AddRequiredItem(context, gameConfiguration, settings, 14, specification.ComplexPotionNumber);
            AddRequiredItem(context, gameConfiguration, settings, specification.JewelGroup, specification.JewelNumber);

            var result = context.CreateNew<ItemCraftingResultItem>();
            result.ItemDefinition = gameConfiguration.Items.Single(item => item.Group == 14 && item.Number == specification.ItemNumber);
            result.Durability = 1;
            settings.ResultItems.Add(result);
        }
    }

    private static void AddRequiredItem(IContext context, GameConfiguration gameConfiguration, SimpleCraftingSettings settings, byte group, short number)
    {
        var requiredItem = context.CreateNew<ItemCraftingRequiredItem>();
        requiredItem.PossibleItems.Add(gameConfiguration.Items.Single(item => item.Group == group && item.Number == number));
        requiredItem.MinimumAmount = 1;
        requiredItem.MaximumAmount = 1;
        requiredItem.MaximumItemLevel = 1;
        settings.RequiredItems.Add(requiredItem);
    }

    private sealed record PotionSpecification(
        short ItemNumber,
        short ComplexPotionNumber,
        short JewelNumber,
        byte CraftingNumber,
        LocalizedString Name,
        string RecipeName,
        MagicEffectNumber EffectNumber,
        byte SubType,
        AttributeDefinition BonusAttribute,
        float BonusValue,
        int ItemValue)
    {
        public byte JewelGroup => this.JewelNumber == 15 ? (byte)12 : (byte)14;
    }
}