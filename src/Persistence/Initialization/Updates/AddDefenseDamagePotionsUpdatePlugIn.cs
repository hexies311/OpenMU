// <copyright file="AddDefenseDamagePotionsUpdatePlugIn.cs" company="MUnique">
// Licensed under the MIT License. See LICENSE file in the project root for full license information.
// </copyright>

namespace MUnique.OpenMU.Persistence.Initialization.Updates;

using System.Runtime.InteropServices;
using MUnique.OpenMU.DataModel.Configuration;
using MUnique.OpenMU.Persistence.Initialization.VersionSeasonSix;
using MUnique.OpenMU.Persistence.Initialization.VersionSeasonSix.Items;
using MUnique.OpenMU.PlugIns;

/// <summary>
/// Adds the Defense Up and Damage Up potions and their Chaos Machine recipes.
/// </summary>
[PlugIn]
[Display(Name = PlugInName, Description = PlugInDescription)]
[Guid("22EDF1C2-70B5-4937-ADA2-2B0506A9F899")]
public sealed class AddDefenseDamagePotionsUpdatePlugIn : UpdatePlugInBase
{
    private const string PlugInName = "Add Defense Up and Damage Up potions";
    private const string PlugInDescription = "Adds six potion variants, their temporary effects, and their Chaos Machine recipes.";

    /// <inheritdoc />
    public override string Name => PlugInName;

    /// <inheritdoc />
    public override string Description => PlugInDescription;

    /// <inheritdoc />
    public override string DataInitializationKey => VersionSeasonSix.DataInitialization.Id;

    /// <inheritdoc />
    public override bool IsMandatory => true;

    /// <inheritdoc />
    public override DateTime CreatedAt => new(2026, 10, 11, 1, 24, 26, DateTimeKind.Utc);

    /// <inheritdoc />
    protected override ValueTask ApplyAsync(IContext context, GameConfiguration gameConfiguration)
    {
        DefenseDamagePotions.InitializeItems(context, gameConfiguration);
        DefenseDamagePotions.InitializeCraftings(context, gameConfiguration);
        ItemRules.Apply(gameConfiguration);
        return ValueTask.CompletedTask;
    }
}