// <copyright file="EnergyArmorVariantSeedService.cs" company="MUnique">
// Licensed under the MIT License. See LICENSE file in the project root for full license information.
// </copyright>

namespace MUnique.OpenMU.Startup;

using System.IO;
using System.Threading;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using MUnique.OpenMU.Persistence;
using MUnique.OpenMU.Persistence.EntityFramework;
using Npgsql;

/// <summary>
/// Applies the all-in-one Energy armor seed before the server containers load configuration.
/// </summary>
internal sealed class EnergyArmorVariantSeedService : IHostedService
{
    private readonly IDatabaseConnectionSettingProvider _connectionSettingProvider;
    private readonly IMigratableDatabaseContextProvider _contextProvider;
    private readonly ILogger<EnergyArmorVariantSeedService> _logger;

    /// <summary>
    /// Initializes a new instance of the <see cref="EnergyArmorVariantSeedService"/> class.
    /// </summary>
    /// <param name="connectionSettingProvider">The database connection settings.</param>
    /// <param name="contextProvider">The persistence context provider whose cache is reset after seeding.</param>
    /// <param name="logger">The logger.</param>
    public EnergyArmorVariantSeedService(
        IDatabaseConnectionSettingProvider connectionSettingProvider,
        IMigratableDatabaseContextProvider contextProvider,
        ILogger<EnergyArmorVariantSeedService> logger)
    {
        this._connectionSettingProvider = connectionSettingProvider;
        this._contextProvider = contextProvider;
        this._logger = logger;
    }

    /// <inheritdoc />
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        var scriptPath = Path.Combine(AppContext.BaseDirectory, "energy-armor-variants.sql");
        var script = await File.ReadAllTextAsync(scriptPath, cancellationToken).ConfigureAwait(false);
        var connectionString = this._connectionSettingProvider.GetConnectionSetting(typeof(EntityDataContext)).ConnectionString
            ?? throw new InvalidOperationException("The database connection string for the energy armor seed is missing.");

        await using var connection = new NpgsqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken).ConfigureAwait(false);
        await using var command = new NpgsqlCommand(script, connection);
        await command.ExecuteNonQueryAsync(cancellationToken).ConfigureAwait(false);

        this._contextProvider.ResetCache();
        this._logger.LogInformation("Applied the Energy armor variants seed.");
    }

    /// <inheritdoc />
    public Task StopAsync(CancellationToken cancellationToken)
    {
        return Task.CompletedTask;
    }
}
