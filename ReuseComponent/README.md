# ReuseComponent

ReuseComponent searches component instances already placed on schematic sheets. Select a result to inspect its metadata, locate its source, or place a copy on the schematic that was active when the script started. Placement uses Altium Designer's native schematic Copy/Paste commands.

## Features

- Search the current sheet or the schematic documents in its owning PCB project.
- Filter as you type by value/comment, manufacturer part number (MPN), manufacturer, package or footprint name, designator, symbol reference, description, rating, or sheet path, where available.
- Match search text without case sensitivity; all space-separated search terms must match. Micro symbols are normalized to `u`, and quantities such as `1uF` and `1 uF` are supported.
- Group instances using the metadata read by the script, with usage counts and a list of designators and source sheets.
- Show value/comment, MPN, manufacturer, package, rating, and description. Missing purchasing metadata does not prevent reuse; package information falls back to a PCB footprint model name when available.
- Use **Locate** to select and zoom to a representative source instance.
- Use **Place copy** or double-click a result to start native paste into the original destination sheet. The search dialog reopens after native placement ends, keeping the query and loaded results.
- Load sheets incrementally and report skipped unreadable items.

The script does not automatically save design documents. Its copy operation restores the source selection and the two schematic Copy preferences it temporarily changes. **Locate** intentionally leaves the source selected and its sheet open.

## Requirements

- Altium Designer on Windows with the DelphiScript scripting system and schematic editor available. The source identifies **Altium Designer 24.4.1** as its target; this release preparation did not verify runtime compatibility with that or any other version.
- An open schematic document (`.SchDoc`) active as the destination. Save it first so it has a stable file location.
- For **Current project** search, an open, saved PCB project (`.PrjPcb`) that contains the destination schematic. The script prefers the focused owning project; otherwise it requires a unique owning project. If no owner is resolved, it searches the destination sheet only.
- These three files kept together:

| File | Purpose |
| --- | --- |
| `ReuseComponent.PrjScr` | Script project; references the source and configures the startup procedure. |
| `ReuseComponent.pas` | DelphiScript implementation and form event handlers. |
| `ReuseComponent.dfm` | Search dialog layout and event bindings. |

The script uses Altium's built-in schematic, workspace, client, and native process APIs. No additional script units, external packages, or bundled component libraries are referenced. It copies existing schematic instances rather than placing new components from a library catalog.

## Installation

1. Download and extract the repository, or clone it locally.
2. Keep all three script files in this `ReuseComponent` directory.
3. Open `ReuseComponent.PrjScr` in Altium Designer.

The project uses a relative source path. No local path editing is required.

## Run in Altium Designer

1. Open your design project and activate the schematic sheet where copies should be placed.
2. Choose **File > Run Script**. If needed, use **Browse > From File** to select `ReuseComponent.PrjScr`.
3. Select `ReuseComponent.pas > ReuseComponent_01_Main` and run it.

The configured entry point is `ReuseComponent_01_Main`; it calls `RC_ReuseComponent`. Open the script project with its form file present, rather than running the Pascal file alone. Menu availability may vary by Altium configuration; see Altium's [Running Scripts documentation](https://www.altium.com/documentation/altium-designer/scripting/running-scripts).

## Usage

1. Choose **Current project** (the default) or **Current sheet**. Results appear as sheets load.
2. Enter search terms, such as a value, MPN fragment, package, or designator. Clear the search box to show all loaded groups.
3. Select a row to inspect its metadata, count, and source locations.
4. Choose **Place copy**, or double-click the row. Complete or end placement using Altium's native paste controls. The search dialog then returns for another choice.
5. Alternatively, choose **Locate** to select and zoom to the group's representative source instance. This closes the search dialog.
6. Choose **Cancel** to close the search dialog. Copies already placed remain in the design; save the design yourself when appropriate.

## Limitations and diagnostics

- Search covers placed schematic components in the selected scope. It does not search PCB components or an external library catalog.
- Grouping compares a subset of component metadata, rather than every parameter or model. A grouped row reuses its first recorded source instance; the usage list is informational and does not select a different source.
- Metadata aliases are limited to those recognized by the source. Arbitrary custom parameters are not generally indexed.
- Results are a loaded snapshot. Changing scope rebuilds the list; rerun the script to refresh after source edits. Unreadable sheets or instances may be skipped, with a warning count in the status line.
- Copy/Paste uses Altium's clipboard behavior. The script does not restore previous clipboard contents.
- Each run attempts to write `ReuseComponent-debug.log` beside the destination schematic. It can contain full sheet paths and designators. Check it for confidential information before sharing. Log write failures are silently ignored.
- Release validation was limited to static source, project, form, and packaging checks. No Altium runtime execution or version compatibility testing was performed during release preparation.
