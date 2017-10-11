[string]$CredentialManagerCode = @"
using System;
using System.Runtime.InteropServices;

namespace CredentialManagement
{
    public class CredentialManager
    {
        #region Imports

        // DllImport derives from System.Runtime.InteropServices
        [DllImport("Advapi32.dll", SetLastError = true, EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode)]
        private static extern bool CredDeleteW([In] string target, [In] CRED_TYPE type, [In] int reservedFlag);

        [DllImport("Advapi32.dll", SetLastError = true, EntryPoint = "CredEnumerateW", CharSet = CharSet.Unicode)]
        private static extern bool CredEnumerateW([In] string Filter, [In] int Flags, out int Count, out IntPtr CredentialPtr);

        [DllImport("Advapi32.dll", SetLastError = true, EntryPoint = "CredFree")]
        private static extern void CredFree([In] IntPtr cred);

        [DllImport("Advapi32.dll", SetLastError = true, EntryPoint = "CredReadW", CharSet = CharSet.Unicode)]
        private static extern bool CredReadW([In] string target, [In] CRED_TYPE type, [In] int reservedFlag, out IntPtr CredentialPtr);

        [DllImport("Advapi32.dll", SetLastError = true, EntryPoint = "CredWriteW", CharSet = CharSet.Unicode)]
        private static extern bool CredWriteW([In] ref Credential userCredential, [In] UInt32 flags);

        #endregion

        #region Fields

        public enum CRED_FLAGS : uint
        {
            NONE = 0x0,
            PROMPT_NOW = 0x2,
            USERNAME_TARGET = 0x4
        }

        public enum CRED_ERRORS : uint
        {
            ERROR_SUCCESS = 0x0,
            ERROR_INVALID_PARAMETER = 0x80070057,
            ERROR_INVALID_FLAGS = 0x800703EC,
            ERROR_NOT_FOUND = 0x80070490,
            ERROR_NO_SUCH_LOGON_SESSION = 0x80070520,
            ERROR_BAD_USERNAME = 0x8007089A
        }

        public enum CRED_PERSIST : uint
        {
            SESSION = 1,
            LOCAL_MACHINE = 2,
            ENTERPRISE = 3
        }

        public enum CRED_TYPE : uint
        {
            GENERIC = 1,
            DOMAIN_PASSWORD = 2,
            DOMAIN_CERTIFICATE = 3,
            DOMAIN_VISIBLE_PASSWORD = 4,
            GENERIC_CERTIFICATE = 5,
            DOMAIN_EXTENDED = 6,
            MAXIMUM = 7,      // Maximum supported cred type
            MAXIMUM_EX = (MAXIMUM + 1000),  // Allow new applications to run on old OSes
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct Credential
        {
            public CRED_FLAGS Flags;
            public CRED_TYPE Type;
            public string TargetName;
            public string Comment;
            public DateTime LastWritten;
            public UInt32 CredentialBlobSize;
            public string CredentialBlob;
            public CRED_PERSIST Persist;
            public UInt32 AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct NativeCredential
        {
            public CRED_FLAGS Flags;
            public CRED_TYPE Type;
            public IntPtr TargetName;
            public IntPtr Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public UInt32 CredentialBlobSize;
            public IntPtr CredentialBlob;
            public UInt32 Persist;
            public UInt32 AttributeCount;
            public IntPtr Attributes;
            public IntPtr TargetAlias;
            public IntPtr UserName;
        }

        #endregion

        #region Child Class

        private class CriticalCredentialHandle : Microsoft.Win32.SafeHandles.CriticalHandleZeroOrMinusOneIsInvalid
        {
            public CriticalCredentialHandle(IntPtr preexistingHandle)
            {
                SetHandle(preexistingHandle);
            }

            private Credential ConvertNativeCredential(IntPtr pCred)
            {
                NativeCredential nativeCredential = (NativeCredential)Marshal.PtrToStructure(pCred, typeof(NativeCredential));
                Credential credential = new Credential();
                credential.Type = nativeCredential.Type;
                credential.Flags = nativeCredential.Flags;
                credential.Persist = (CRED_PERSIST)nativeCredential.Persist;

                long LastWritten = nativeCredential.LastWritten.dwHighDateTime;
                LastWritten = (LastWritten << 32) + nativeCredential.LastWritten.dwLowDateTime;
                credential.LastWritten = DateTime.FromFileTime(LastWritten);

                credential.UserName = Marshal.PtrToStringUni(nativeCredential.UserName);
                credential.TargetName = Marshal.PtrToStringUni(nativeCredential.TargetName);
                credential.TargetAlias = Marshal.PtrToStringUni(nativeCredential.TargetAlias);
                credential.Comment = Marshal.PtrToStringUni(nativeCredential.Comment);
                credential.CredentialBlobSize = nativeCredential.CredentialBlobSize;
                if (nativeCredential.CredentialBlobSize > 0)
                {
                    credential.CredentialBlob = Marshal.PtrToStringUni(nativeCredential.CredentialBlob, (int)nativeCredential.CredentialBlobSize / 2);
                }

                return credential;
            }

            public Credential[] GetCredentials(int count)
            {
                if (IsInvalid)
                {
                    throw new InvalidOperationException("Invalid CriticalHandle!");
                }
                Credential[] credentials = new Credential[count];
                IntPtr pCredential = IntPtr.Zero;
                for (int index = 0; index < count; index++)
                {
                    pCredential = Marshal.ReadIntPtr(handle, index * IntPtr.Size);
                    credentials[index] = ConvertNativeCredential(pCredential);
                }
                return credentials;
            }

            public Credential GetCredential()
            {
                if (IsInvalid)
                {
                    throw new InvalidOperationException("Invalid CriticalHandle!");
                }
                
                return ConvertNativeCredential(handle);
            }

            override protected bool ReleaseHandle()
            {
                if (IsInvalid)
                {
                    return false;
                }

                CredFree(handle);
                SetHandleAsInvalid();

                return true;
            }
        }

        #endregion

        #region Custom API

        public static Credential[] GetCredentials(string filter, out int result)
        {
            result = 0;

            int flags = 0x0;
            if (string.IsNullOrEmpty(filter) || filter == "*")
            {
                filter = null;
                if (6 <= Environment.OSVersion.Version.Major)
                {
                    flags = 0x1; //CRED_ENUMERATE_ALL_CREDENTIALS; only valid is OS >= Vista
                }
            }

            int count = 0;
            IntPtr pCredentials = IntPtr.Zero;
            if (!CredEnumerateW(filter, flags, out count, out pCredentials))
            {
                result = Marshal.GetHRForLastWin32Error();
                return null;
            }

            CriticalCredentialHandle credentialHandle = new CriticalCredentialHandle(pCredentials);
            return credentialHandle.GetCredentials(count);
        }

        public static Credential GetCredential(string target, CRED_TYPE type, out int result)
        {
            result = 0;

            IntPtr pCredential = IntPtr.Zero;
            if (!CredReadW(target, type, 0, out pCredential))
            {
                result = Marshal.GetHRForLastWin32Error();
                return new Credential();
            }

            CriticalCredentialHandle CredHandle = new CriticalCredentialHandle(pCredential);
            return CredHandle.GetCredential();
        }

        public static void WriteCredential(Credential credential, out int result)
        {
            result = 0;
            if (!CredWriteW(ref credential, 0))
            {
                result = Marshal.GetHRForLastWin32Error();
            }
        }

        public static void DeleteCredential(string target, CRED_TYPE type, out int result)
        {
            result = 0;
            if (!CredDeleteW(target, type, 0))
            {
                result = Marshal.GetHRForLastWin32Error();
            }
        }

        #endregion
    }
}
"@

try {
	$credentialManager = [CredentialManagement.CredentialManager]
}
catch {
	# only remove the error we generated
    if ($Error) {
	    $Error.RemoveAt($Error.Count - 1)
    }
}

if(-not $credentialManager) {
	Add-Type $CredentialManagerCode
}
else {
	Add-Type $CredentialManagerCode
}