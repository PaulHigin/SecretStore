# Microsoft.PowerShell.SecretStore Module Architecture

## Description

The Microsoft.PowerShell.SecretStore is a PowerShell module extension vault for Microsoft.PowerShell.SecretManagement.
It is a secure storage solution that stores secret data on the local machine.
It is based on .NET cryptography APIs, and works on all PowerShell supported platforms for Windows, Linux, macOS.  

Secret data is stored at rest in encrypted form on the file system, and decrypted when returned to a user request.  

The store file data integrity is verified using a cryptographic hash embedded in the file.  

The store can be configured to require a password or operate password-less.
Requiring a password is more secure since password-less operation relies solely on file system protections.
Password-less operation still encrypts data, but the encryption key is stored on file and is accessible.  

Configuration and data files are stored in user context locations, and have file permissions or access control lists limiting access to the single user owner.  
Configuration options include password requirement, password timeout, and the ability to prompt user for a password in interactive sessions.  
There is an unimplemented configuration option to allow `AllUser` access to the store, instead of `CurrentUser` only access.
This configuration is not supported in the current implementation.  

## Files

Configuration and data are stored in separate files.
File location depends on the platform OS.  

For Windows platforms the location is:  
`$env:USERPROFILE\AppData\Local\Microsoft\PowerShell\secretmanagement\localstore\`  

For Non-Windows platforms the location is:  
`~/.secretmanagement/localstore/`

### Scope

SecretStore is intended to be configurable and work in both user and machine wide scopes.
However, the current implementation supports only `CurrentUser` scope.  

### File permissions

#### Windows platform

On Windows platforms, file permissions are determined by an access control list, which restricts all access of the contents to the current user.
Default access rules of the `localstore` containing directory are removed, and the following access rules are applied:  

- Full control of the `localstore` directory is given to the current user only.  

- Full control of any child directories and files of the `localstore` directory is given to the current user only.  

- A protection rule is added that prevents the `localstore` directory from inheriting any rules from parent directories.  

- The owner of the security descriptor for the `localstore` directory is set to the current user.  

#### Non-Windows platforms

For Non-Windows platforms, file permissions are set to the owning user only using the `chmod` command.
The following file access permissions are set:  

```csharp
    /*
    Current user is user owner.
    Current user is group owner.
    Permission for user dir owner:      rwx    (execute for directories only)
    Permission for user file owner:     rw-    (no file execute)
    Permissions for group owner:        ---    (no access)
    Permissions for others:             ---    (no access)
    */
```

### Configuration file

The configuration data is stored on file in a simple json format.  

```json
{
  "StoreScope": "CurrentUser",
  "Authentication": "Password",
  "PasswordTimeout": 900,
  "Interaction": "Prompt"
}
```

### Key file

The key file contains the AES 256 key and IV (initialization vector) blobs.
This key is randomly generated and is used in the encryption of secrets.
If a password is required, a new encryption key is derived from this key and the password.
Otherwise, for no-password operation, a new encryption key is derived from this key and the current username.
The contents of this file is encrypted with current user username to prevent casual disclosure.  

The key file structure consists of two main sections:

- Encryption key blob    (AES Encryption key)

- Encryption iv blob     (AES initialization vector)

### Data file

The data file structure consists of three main sections:  

- File data hash         (Sha256 hash is computed over secret metadata and data blob)

- Secret metadata json   (Information about each secret item)

- Secret data blob       (sequence of individual secret values)

The file data hash is a cryptographic hash of the key, iv, metadata, data, and is used to verify file content integrity.  

The metadata is a json structure that contains information about each secret.
It includes secret name, type, optional attributes, and encrypted blob size and offset information.
It also includes optional additional data associated with the secret, to support SecretManagement optional metadata.
The optional SecretManagement metadata allows users to associate arbitrary data to a stored secret as name/value pairs.
The metadata is not stored securely and must not contain sensitive information.  

```json
{
    "MetaData": [
    {
        "Name": "TestSecret1",
        "Type": "String",
        "Offset": 34593,
        "Size": 3500,
        "Attributes": {},
        "AdditionalData": {}
    },
    {
        "Name": "TestSecret2",
        "Type": "PSCredential",
        "Offset": 59837,
        "Size": 4200,
        "Attributes": {
            "UserName": "UserA"
        },
        "AdditionalData": {
            "Desc": "MySecret"
        }
    }
    ]
}
```

The data blob is a byte array containing all secret values.
The metadata offset and size fields are used to extract the specific encrypted secret value from the data blob.  

## Encryption

All encryption is performed using the .NET Core cryptography APIs to ensure cross platform operation.
The configuration file, key file, and data files are all encrypted.  

### Configuration file encryption

The configuration file is encrypted with the current user name.
This is a defense-in-depth measure to prevent casual access and modification of configuration data.  

### Key file encryption

The key file is encrypted with the current user name.
This is a defense-in-depth measure to prevent casual access.  

### Data file encryption

The data file uses symmetric encryption with an AES 256 key.
The secret data and metadata are stored in the data file.
If a password is required, then a new AES key is cryptographically derived from the stored AES key plus the provided password, and the derived key is used for encryption.
For password-less operation, then a new AES key is cryptographically derived from the stored AES key plus the current username.  

The metadata is decrypted and read into memory.
Metadata does not include the actual secret values, so it remains in memory un-encrypted.
The secret data blob is also read into memory, but each individually encrypted secret remains encrypted until returned in a user request response.  

## Data file integrity

The integrity of the data file contents is verified through a cryptographic hash computed over all the data file contents: metadata json and data blob.  
If a password is required, then the hash value is computed based on a salt value and the provided password.
If no password is required, then the hash value is computed with the salt value and the current username.  

## Configuration

Requiring a password, password timeout, and user prompting are all configuration options for SecretStore.
The default configuration requires a password for best security, allows the user to be prompted in interactive sessions, and sets the session password timeout to 15 minutes.  

For non-interactive automation scenarios, the `Do Not Prompt` option can be configured, to suppress user prompting.
In this case a `Microsoft.PowerShell.SecretStore.PasswordRequiredException` exception is thrown if there is no valid session password.
The `Unlock-SecretStore` cmdlet can be used (typically by automation) to provide the password for the current PowerShell session.
The password will remain valid until the password timeout expires.  

## Security

SecretStore security depends on the selected configuration options.  

### Password required

The strongest security is when a password is required.
The password is used to encrypt both metadata and data on file.
This protects the data from being read by other system users.
It also protects the data from exposure if the physical media containing the data files is lost.  

### No password required

If SecretStore is configured with no password required, data is still encrypted as before.
The difference is that data encryption is performed with an AES key that is stored on file plus current username.
Whereas a password is protected by the user, the AES key is protected only by the file system.
The file system protects the secret data from other low privilege users.
But admin or root users will be able to discover the key and potentially access secrets.
So security is clearly not as strong when compared to password based protection.  

### Data encryption

Secret metadata is not considered sensitive and so it is decrypted once and remains in memory un-encrypted.
But secret value blobs are individually encrypted and remain encrypted after being read into memory.
Secret values are decrypted only when returned to a user from a request.  

### Data integrity

SecretStore data integrity is protected through a computed hash value stored in the file.
Data integrity is verified whenever data is read from file.
If a password is being used, the hash value is computed using it.
Otherwise, the current user name is used to compute the hash value.  

### Configuration information

Meddling with the configuration file can prevent SecretStore from operating correctly, and thus be used as a denial of service (DOS) attack.
For example, if the `Authentication` field is changed, the store data integrity check will fail, preventing access to secret data.
StoreFile relies on the file system to protect the configuration file.
But the configuration file is also encrypted with the user name to prevent inadvertent disclosure or modification.  
