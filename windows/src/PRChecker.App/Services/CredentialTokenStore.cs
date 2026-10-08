using System.ComponentModel;
using System.Runtime.InteropServices;
using PRChecker.Core;

namespace PRChecker.App.Services;

/// <summary>
/// Tokens as generic credentials in Windows Credential Manager, one per server, persisted
/// for this user on this machine only (not roamed). CredWrite updates an existing entry in
/// place, so a failed write never leaves the previous token deleted.
/// </summary>
internal sealed partial class CredentialTokenStore : ITokenStore
{
    private const uint CredTypeGeneric = 1;
    private const uint CredPersistLocalMachine = 2;
    private const int ErrorNotFound = 1168;

    [StructLayout(LayoutKind.Sequential)]
    private struct Credential
    {
        public uint Flags;
        public uint Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public long LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }

    [LibraryImport("advapi32.dll", EntryPoint = "CredReadW", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CredRead(string target, uint type, uint flags, out IntPtr credential);

    [LibraryImport("advapi32.dll", EntryPoint = "CredWriteW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CredWrite(ref Credential credential, uint flags);

    [LibraryImport("advapi32.dll", EntryPoint = "CredDeleteW", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CredDelete(string target, uint type, uint flags);

    [LibraryImport("advapi32.dll", EntryPoint = "CredFree")]
    private static partial void CredFree(IntPtr buffer);

    public unsafe string? Read(string account)
    {
        if (!CredRead(account, CredTypeGeneric, 0, out var pointer)) return null;
        try
        {
            var credential = *(Credential*)pointer;
            if (credential.CredentialBlob == IntPtr.Zero || credential.CredentialBlobSize == 0) return null;
            return Marshal.PtrToStringUni(credential.CredentialBlob, (int)credential.CredentialBlobSize / 2);
        }
        finally { CredFree(pointer); }
    }

    public void Save(string token, string account)
    {
        var target = Marshal.StringToHGlobalUni(account);
        var user = Marshal.StringToHGlobalUni("PR Checker");
        var blob = Marshal.StringToHGlobalUni(token);
        try
        {
            var credential = new Credential
            {
                Type = CredTypeGeneric,
                TargetName = target,
                UserName = user,
                CredentialBlob = blob,
                CredentialBlobSize = (uint)(token.Length * 2),
                Persist = CredPersistLocalMachine,
            };
            if (!CredWrite(ref credential, 0)) throw Failure("save");
        }
        finally
        {
            Marshal.ZeroFreeGlobalAllocUnicode(blob);
            Marshal.FreeHGlobal(user);
            Marshal.FreeHGlobal(target);
        }
    }

    public void Delete(string account)
    {
        if (!CredDelete(account, CredTypeGeneric, 0) && Marshal.GetLastPInvokeError() != ErrorNotFound) throw Failure("delete");
    }

    private static TokenStoreException Failure(string action) =>
        new($"Couldn't {action} the access token in Credential Manager: {new Win32Exception(Marshal.GetLastPInvokeError()).Message}");
}
