# Network Everything

English · [Русский](README.ru.md)

Network Everything is a native macOS client for an existing [Everything HTTP server](https://www.voidtools.com/support/everything/http/). The server handles search, sorting, and filtering. The Mac app opens matching files and folders over SMB, shows previews, and remembers searches.

Building requires macOS 14 or later and Swift 6.2 or later. The package has no third-party dependencies.

## Build and install

```sh
git clone https://github.com/ampire5/EverythingMac.git
cd EverythingMac
swift test
./scripts/build.sh --install
open "$HOME/Applications/Network Everything.app"
```

Omit `--install` to leave the app at `build/Network Everything.app`. Set `CODE_SIGN_IDENTITY` to choose a signing certificate. With local signing, macOS may ask for Keychain access again after a rebuild.

## Connect to a server

1. Enable the Everything HTTP server on the Windows computer that holds the index.
2. In Network Everything settings, enter your server address and any required username and password. Use HTTPS or a trusted local network when connecting with HTTP Basic authentication.
3. To open results on your Mac, map a Windows path to the same folder on an SMB share. The mounted-shares picker can use a share already connected in Finder.

For example, `C:\Photos`, `smb://server/Photos`, and `/Volumes/Photos` should all refer to the same folder. If the share is disconnected, connect to it in Finder and retry. Search works while the share is disconnected.

## Search and browse

Enter an Everything query such as `ext:jpg fox`. Click a column header to sort the results. You can filter by file type or folder, bookmark a query, or return to an earlier search.

| Shortcut | Action |
| --- | --- |
| ⌘F | Focus search |
| ⌘N / ⌘T | Open a new window or tab |
| ⌘D | Bookmark the current search |
| ⌘[ / ⌘] | Go back or forward in the window's search history |
| Return in the results table | Open the selected result |
| Space in the results table | Show or hide the preview |
| ⌘R | Reveal the result in Finder |

Deleting files requires confirmation. On an SMB share, confirmed deletion removes the selected files without moving them to the Trash.

## Embed search in Loupe or another app

Add EverythingMac to your package dependencies and add the `EverythingSearchUI` product to your app target.

```swift
.package(url: "https://github.com/ampire5/EverythingMac.git", from: "0.1.0")
.product(name: "EverythingSearchUI", package: "EverythingMac")
```

Create an `EverythingSearchPage` for each AppKit window. Supply a connection loader and a handler that opens a resolved local file or folder. Apps can use `SavedEverythingConnection.load` when the user has already configured Network Everything. The first attempt to read the password may prompt for Keychain access.

Loupe shows **Everything** in Home once a connection is saved in Network Everything. Each host app keeps its own search settings and bookmarks.

## Local data

Server addresses, usernames, and SMB mappings are stored locally. Passwords are stored in macOS Keychain. Search results stay in memory. Bookmarks, recent searches, and the list of recently used apps for opening files are stored on the Mac.
