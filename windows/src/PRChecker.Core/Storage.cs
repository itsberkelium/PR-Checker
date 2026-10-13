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
/// <remarks>
/// Setters rather than init: for init-only properties the JSON source generator sets every one
/// in an object initializer, so a property missing from the file becomes null/false/0 instead
/// of keeping its default below. Treat instances as immutable and change them with <c>with</c>.
/// </remarks>
public sealed record SettingsData
{
    public string? ServerUrl { get; set; }
    public int RefreshMinutes { get; set; } = 5;
    public bool HideDrafts { get; set; } = true;
    /// <summary>How many recently merged PRs to show under Mine; 0 is off.</summary>
    public int RecentlyMergedCount { get; set; } = 3;
    public string RepoFilter { get; set; } = "";
    public bool NotificationsEnabled { get; set; } = true;
    public bool NotificationDetails { get; set; } = true;
    public bool OpenAtLogin { get; set; }
    public LanguagePreference Language { get; set; } = LanguagePreference.System;
    /// <summary>The Terms of Use version the user agreed to; 0 if never.</summary>
    public int AcceptedTermsVersion { get; set; }
    /// <summary>"dev" takes updates from the dev feed; null is the release feed.</summary>
    public string? UpdateChannel { get; set; }
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
        try { return JsonSerializer.Deserialize(File.ReadAllBytes(SettingsPath), JsonContext.Default.SettingsData) ?? new(); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return new(); }
    }

    public void Save(SettingsData settings) => WriteAtomically(SettingsPath, JsonSerializer.SerializeToUtf8Bytes(settings, JsonContext.Default.SettingsData));

    public Snapshot? Load(string serverId, string username)
    {
        try { return JsonSerializer.Deserialize(File.ReadAllBytes(SnapshotPath(serverId, username)), JsonContext.Default.Snapshot); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return null; }
    }

    public void Save(string serverId, string username, Snapshot snapshot) =>
        WriteAtomically(SnapshotPath(serverId, username), JsonSerializer.SerializeToUtf8Bytes(snapshot, JsonContext.Default.Snapshot));

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
