using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace PRChecker.Core;

/// <summary>Where access tokens are kept (Windows Credential Manager in the app). Abstracted for tests.</summary>
public interface ITokenStore
{
    string? Read(string account);
    /// <summary>Updates in place or adds; throws <see cref="TokenStoreException"/> on failure.</summary>
    void Save(string token, string account);
    void Delete(string account);
}

public sealed class TokenStoreException(string message) : Exception(message);

public static class TokenAccounts
{
    public static string For(ServerAddress server) => $"PRChecker/token:{server.Id}";
}

/// <summary>Settings persisted as JSON. Tokens never go here.</summary>
public sealed record SettingsData
{
    public string? ServerUrl { get; init; }
    public int RefreshMinutes { get; init; } = 5;
    public bool HideDrafts { get; init; } = true;
    public string RepoFilter { get; init; } = "";
    public bool NotificationsEnabled { get; init; } = true;
    public bool NotificationDetails { get; init; } = true;
    public bool OpenAtLogin { get; init; }
}

public interface ISettingsStore
{
    SettingsData Load();
    void Save(SettingsData settings);
}

public interface ISnapshotStore
{
    Snapshot? Load(string serverId, string username);
    void Save(string serverId, string username, Snapshot snapshot);
    void DeleteAll(string serverId);
}

/// <summary>
/// Settings and snapshots as JSON files in one folder (e.g. %LOCALAPPDATA%\PRChecker).
/// Snapshot file names are hashes, so server URLs and user names don't appear in them.
/// </summary>
public sealed class JsonFileStore(string directory) : ISettingsStore, ISnapshotStore
{
    private string SettingsPath => Path.Combine(directory, "settings.json");
    private string SnapshotDirectory => Path.Combine(directory, "snapshots");

    public SettingsData Load()
    {
        try { return JsonSerializer.Deserialize<SettingsData>(File.ReadAllBytes(SettingsPath), Json.Options) ?? new(); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return new(); }
    }

    public void Save(SettingsData settings) => WriteAtomically(SettingsPath, JsonSerializer.SerializeToUtf8Bytes(settings, Json.Options));

    public Snapshot? Load(string serverId, string username)
    {
        try { return JsonSerializer.Deserialize<Snapshot>(File.ReadAllBytes(SnapshotPath(serverId, username)), Json.Options); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return null; }
    }

    public void Save(string serverId, string username, Snapshot snapshot) =>
        WriteAtomically(SnapshotPath(serverId, username), JsonSerializer.SerializeToUtf8Bytes(snapshot, Json.Options));

    public void DeleteAll(string serverId)
    {
        if (!Directory.Exists(SnapshotDirectory)) return;
        foreach (var file in Directory.EnumerateFiles(SnapshotDirectory, Hash(serverId) + "-*.json")) File.Delete(file);
    }

    private string SnapshotPath(string serverId, string username) =>
        Path.Combine(SnapshotDirectory, $"{Hash(serverId)}-{Hash(username.ToLowerInvariant())}.json");

    private static string Hash(string value) => Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(value)))[..16];

    private static void WriteAtomically(string path, byte[] data)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".tmp";
        File.WriteAllBytes(temporary, data);
        File.Move(temporary, path, overwrite: true);
    }
}
