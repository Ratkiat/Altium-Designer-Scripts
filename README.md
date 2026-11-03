# Altium Designer Scripts

A collection of automation scripts for Altium Designer. Each script has its own directory containing the files needed to run it and documentation for installation, usage, and limitations.

## Available scripts

| Script | Description |
| --- | --- |
| [ReuseComponent](ReuseComponent/) | Search components already placed on schematic sheets, inspect their metadata and usage, locate a source instance, and place a copy using Altium's native Copy/Paste commands. |

ReuseComponent is the first script in this collection. Additional scripts can be added in separate directories.

## Installation

1. Clone this repository or download and extract its ZIP archive.
2. Keep each script's project, source, and form files together in their original directory.
3. Follow the requirements and execution instructions in that script's README.

Scripts run inside Altium Designer's scripting system. Compatibility and prerequisites are specific to each script; this repository does not claim compatibility with untested Altium Designer versions.

See the [ReuseComponent documentation](ReuseComponent/README.md) to get started.

## Contributions, bug reports, and feedback

Use [GitHub Issues](https://github.com/Ratkiat/Altium-Designer-Scripts/issues) to report bugs, suggest scripts, or provide feedback. Include the script name, Altium Designer version, steps to reproduce, expected behavior, and actual behavior. Remove confidential design information from examples and logs before sharing them.

Pull requests are welcome. Keep changes focused, describe their purpose, and state what validation was performed. Place new scripts in their own directories with their required files and a README.
