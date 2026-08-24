# Trade Subscription Renew

## About the mod

Trade Subscription Renew adds two default ship behaviors to X4: Foundations 9.00.
They send player-owned ships to known stations with stale trade information.
The extension is independent and has no dependency on another mod.

**TradeSub Renew** requires a one-star pilot. It searches within a configurable
gate-jump limit. It can return to a parking sector and proactively revisit old
non-permanent subscriptions when no stale station remains.

**TradeSub Renew - Global** requires a four-star pilot. It searches without a
range limit and can return to an optional parking sector.

Both behaviors respect the ship's civilian sector-travel and sector-activity
blacklists. They clear the current sector first, then prefer the smallest gate
distance and use physical distance as a tiebreaker. Successful stale refreshes
create a General logbook entry. Successful travel and station visits award a
small amount of Piloting and Morale experience.

- [GitHub](https://github.com/ruslan-sh/x4-tradesub-renew)
- [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3789049684)

## AI assistance disclosure

This mod was developed with substantial assistance from generative AI. The mod
author directed the work and remains responsible for the published result.

## Installation

After installation, enable **Trade Subscription Renew** in the X4 Extensions
menu and restart the game.

### Steam Workshop

1. Open the [Trade Subscription Renew Steam Workshop page](https://steamcommunity.com/sharedfiles/filedetails/?id=3789049684).
2. Select **Subscribe**. Steam downloads and installs the extension.
3. Start X4 and open **Extensions** from the main menu.
4. Enable **Trade Subscription Renew** if it is not already enabled.
5. Restart X4 when prompted.

### Manual installation from a GitHub release

1. Download the latest release archive from the GitHub Releases page.
2. Extract the archive.
3. Right-click `install.ps1` and select **Run with PowerShell**.

The installer finds a single profile under the default
`Documents/Egosoft/X4` path without asking for input. If it finds multiple
profiles, select one from the displayed list. If it finds no profile, enter the
full path to your X4 player profile.

If the mod is already installed, the installer asks for permission before it
clears and replaces the existing mod directory.

You can also install the release manually. Extract the `tradesub_renew` folder
into your active X4 profile's `extensions` folder.

The final path must be:

```text
Documents/Egosoft/X4/<player-id>/extensions/tradesub_renew
```

The `tradesub_renew` folder must contain `content.xml` and the packaged mod
files.

### Manual installation from source code

1. Download or clone this repository.
2. Create this directory in your active X4 profile:

   ```text
   Documents/Egosoft/X4/<player-id>/extensions/tradesub_renew
   ```

3. Copy the contents of `src/` into the new `tradesub_renew` directory.

The destination must contain `content.xml`, `aiscripts/`, `libraries/`, and
`t/` directly. Do not copy the `src` directory itself.

### Automated installation from source code

On Windows, configure the development tool as described in the
[Developer guide](#developer-guide). Then run:

```powershell
.\tool.ps1 sync
```

The command installs the loose source files into the configured X4 profile.
It removes and recreates only the `extensions/tradesub_renew` directory before
it copies the files. Do not keep unrelated files in that directory.

## Developer guide

### Requirements

- Windows PowerShell or PowerShell 7
- X4: Foundations 9.00 for runtime testing
- Egosoft X Tools for catalog packaging or Steam Workshop publishing

### Configure the tool

The tool stores local settings in the ignored `.tools.ini` file. Configure the
active X4 profile before the first sync:

```powershell
.\tool.ps1 config -ProfileId <player-id>
```

If both X Tools programs are in one directory, configure that directory:

```powershell
.\tool.ps1 config -ToolsPath "<X Tools directory>"
```

The command saves each tool that it finds. The directory must contain at least
one of `XRCatTool.exe` or `WorkshopTool.exe`.

You can also configure either program separately:

```powershell
.\tool.ps1 config -XRCatToolPath "<path-to-XRCatTool.exe>"
.\tool.ps1 config -WorkshopToolPath "<path-to-WorkshopTool.exe>"
```

You can combine profile and tool parameters in one config command. Every
supplied value is validated before the settings file changes. An unspecified
setting keeps its current value.

### Install for development

Install loose source files:

```powershell
.\tool.ps1 sync
```

Install the catalog package created by the package command:

```powershell
.\tool.ps1 sync -Packaged
```

Rebuild the package before installation:

```powershell
.\tool.ps1 sync -Packaged -Repack
```

Both modes remove and recreate only the
`extensions/tradesub_renew` destination. This prevents stale loose files or
catalogs from affecting a test.

If the profile is not configured, sync stops before it changes the destination
and tells you which config command to run.

### Package a release

Install Egosoft X Tools and configure `XRCatTool.exe`. Then create a local
catalog package:

```powershell
.\tool.ps1 package
```

The script copies `install.ps1` to `dist` and copies `content.xml` into
`dist/tradesub_renew`. It builds `ext_01.cat` and `ext_01.dat` in the same mod
directory. The contents of `dist` have the required GitHub release layout:

```text
dist/
├── install.ps1
└── tradesub_renew/
    ├── content.xml
    ├── preview.png
    ├── ext_01.cat
    └── ext_01.dat
```

The command does not publish or upload anything. If `XRCatTool.exe` is not
configured or no longer exists, the command stops before it changes the
package.

The package directory is suitable as input for a later Workshop publishing
step. Review and test the package before upload.

If `src/preview.png` exists, the package command copies it to the package
root. The publish command requires this PNG file.

### Create a GitHub release archive

Build the package and create a ZIP archive with:

```powershell
.\tool.ps1 release
```

The command reads the integer version from `src/content.xml`. For version
`101`, it creates `dist/release_v101.zip`. The ZIP root contains:

```text
install.ps1
tradesub_renew/
```

The command replaces an existing archive for the same version. It does not
upload the archive to GitHub.

### Generate a Steam-formatted README

Convert `README.md` to Steam formatting with:

```powershell
.\tool.ps1 steam-readme
```

The command writes `dist/README.steam.txt`. It converts headings, emphasis,
links, lists, quotes, horizontal rules, and code to the tags that Steam
supports. It does not upload or change a Workshop item.

You can also use the converter directly with other Markdown files:

```powershell
.\convert-markdown-to-steam.ps1 -InputPath <markdown-file> -OutputPath <steam-file>
```

The converter creates the output directory if it does not exist.

### Publish to Steam Workshop

Install X Tools through Steam and configure both `XRCatTool.exe` and
`WorkshopTool.exe`. They can be in the same directory or in separate
directories. You must own X4 on Steam, be logged in to Steam, and accept the
Steam Workshop Legal Agreement.

Put the Workshop preview at `src/preview.png`. The file must be a PNG. Publish
a new Workshop item with:

```powershell
.\tool.ps1 publish
```

The tool rebuilds the package first. WorkshopTool shows the metadata and asks
for confirmation before it uploads. After a successful first upload,
WorkshopTool writes the Workshop item ID and `sync="false"` to `content.xml`.
The tool copies this updated manifest back to `src/content.xml`.

For later updates, give the change note as the second argument:

```powershell
.\tool.ps1 publish "Improve station selection"
```

The tool increments the integer manifest version by one before an update. For
example, `101` becomes `102`, which X4 displays as 1.02. The source manifest is
changed only after WorkshopTool reports success and updates the staged
manifest.

Use `-KeepVersion` for an update that must keep the current version:

```powershell
.\tool.ps1 publish "Correct documentation" -KeepVersion
```

Use `-UpdateNameAndDescription` to also copy the name and description from
`content.xml` to the Workshop item:

```powershell
.\tool.ps1 publish "Update Workshop text" -UpdateNameAndDescription
```

Publishing is always an explicit command. Sync, package, and steam-readme
commands never upload files.

Official Egosoft documentation:

- [X Catalog Tool](https://wiki.egosoft.com/X4%20Foundations%20Wiki/Modding%20Support/X%20Catalog%20Tool/)
- [Steam Workshop and Workshop Tool](https://wiki.egosoft.com/X%20Rebirth%20Wiki/Modding%20support/Steam%20Workshop%20for%20X%20Rebirth%20and%20X4/)

### Validate and test

Run the dependency-free XML syntax check before syncing:

```powershell
.\validate.ps1
```

This check uses the .NET XML parser. It confirms only that the files are
well-formed XML. It does not use or redistribute X4 schemas, validate against
an XSD, or prove that the scripts work in the game.

Run the development tool tests with:

```powershell
.\tests\tool.tests.ps1
```

These tests cover configuration, packaging, installation, and publishing tool
behavior. They do not test AI Script behavior in X4.

For runtime testing, start X4 with:

```text
-logfile debuglog.txt -debug scripts
```

Then test both behaviors in game and inspect `debuglog.txt` for script errors.

## License

The original source code and documentation in this repository use the
[MIT License](LICENSE).

X4: Foundations, its trademarks, and its game assets belong to Egosoft GmbH.
The MIT License does not cover them.
